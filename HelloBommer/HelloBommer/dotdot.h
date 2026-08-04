#import <Foundation/Foundation.h>

typedef void (^dd_progress_t)(NSString *step);
int dd_write(const char *identifier, const char *targetPath, dd_progress_t progress);
