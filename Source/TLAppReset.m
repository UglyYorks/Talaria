#import "TLAppReset.h"

static NSString * const TLAppDataIdentifier = @"com.talaria.chat";

@interface TLAppReset ()
@property (nonatomic, strong) NSURL *libraryURL;
@property (nonatomic, strong) NSUserDefaults *userDefaults;
@property (nonatomic, strong) id<TLCredentialStore> credentialStore;
@end

@implementation TLAppReset

- (instancetype)init {
  return [self initWithLibraryURL:[NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject
                    userDefaults:NSUserDefaults.standardUserDefaults
                 credentialStore:[[TLKeychainCredentialStore alloc] init]];
}

- (instancetype)initWithLibraryURL:(NSURL *)libraryURL
                     userDefaults:(NSUserDefaults *)userDefaults
                  credentialStore:(id<TLCredentialStore>)credentialStore {
  if ((self = [super init])) {
    _libraryURL = libraryURL;
    _userDefaults = userDefaults;
    _credentialStore = credentialStore;
  }
  return self;
}

- (NSURL *)pendingResetURL {
  // Keep the request outside the directories being erased so a partial failure
  // or interrupted launch can safely retry the same idempotent cleanup.
  return [self.libraryURL URLByAppendingPathComponent:@"Application Support/com.talaria.chat.reset-pending"];
}

- (BOOL)resetPending {
  return [NSFileManager.defaultManager fileExistsAtPath:self.pendingResetURL.path];
}

- (BOOL)requestReset:(NSError **)error {
  if (![NSFileManager.defaultManager createDirectoryAtURL:self.pendingResetURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  return [[NSData data] writeToURL:self.pendingResetURL options:NSDataWritingAtomic error:error];
}

- (BOOL)removeItemIfPresent:(NSURL *)url error:(NSError **)error {
  NSError *removalError = nil;
  if ([NSFileManager.defaultManager removeItemAtURL:url error:&removalError]) return YES;
  if ([removalError.domain isEqualToString:NSCocoaErrorDomain] && removalError.code == NSFileNoSuchFileError) return YES;
  if (error) *error = removalError;
  return NO;
}

- (BOOL)cancelReset:(NSError **)error {
  return [self removeItemIfPresent:self.pendingResetURL error:error];
}

- (BOOL)performPendingReset:(NSError **)error {
  if (!self.resetPending) return YES;
  // Fail before removing files when the trusted helper cannot erase the token.
  if (![self.credentialStore removeCredentialForAccount:TLOpenRouterTokenCredentialAccount error:error]) return NO;

  // Fixed app-owned roots include orphaned VMs, SQLite sidecars, and the whole
  // Chromium profile. Never follow VM paths from database rows or delete the
  // bundled runtime, downloaded user files, or the installed credential helper.
  NSArray<NSString *> *paths = @[
    @"Application Support/com.talaria.chat",
    @"Caches/com.talaria.chat",
    @"WebKit/com.talaria.chat",
    @"HTTPStorages/com.talaria.chat",
    @"HTTPStorages/com.talaria.chat.binarycookies",
    @"Saved Application State/com.talaria.chat.savedState",
    @"Logs/com.talaria.chat",
  ];
  for (NSString *path in paths) {
    if (![self removeItemIfPresent:[self.libraryURL URLByAppendingPathComponent:path] error:error]) return NO;
  }
  [self.userDefaults removePersistentDomainForName:TLAppDataIdentifier];
  if (![self.userDefaults synchronize]) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.AppReset" code:1 userInfo:@{
      NSLocalizedDescriptionKey: @"Talaria could not clear its saved preferences. Retry the reset."
    }];
    return NO;
  }
  return [self cancelReset:error];
}

@end
