#import <Foundation/Foundation.h>
#import "TLCredentialStore.h"

NS_ASSUME_NONNULL_BEGIN

// Cleanup runs only during startup, before opening SQLite, Chromium, or any VM.
@interface TLAppReset : NSObject
@property (nonatomic, readonly) BOOL resetPending;
- (instancetype)init;
- (instancetype)initWithLibraryURL:(NSURL *)libraryURL
                     userDefaults:(NSUserDefaults *)userDefaults
                  credentialStore:(id<TLCredentialStore>)credentialStore;
- (BOOL)requestReset:(NSError **)error;
- (BOOL)cancelReset:(NSError **)error;
- (BOOL)performPendingReset:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
