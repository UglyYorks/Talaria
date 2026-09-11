#import "TLAppReset.h"
#import <WebKit/WebKit.h>

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

- (WKWebsiteDataStore *)defaultBrowserDataStore {
  return WKWebsiteDataStore.defaultDataStore;
}

- (BOOL)removeDefaultBrowserDataStore:(NSError **)error {
  NSURL *marker = [self.libraryURL URLByAppendingPathComponent:@"Application Support/com.talaria.chat/WebKit/WebKitDefaultDataStore"];
  if (![NSFileManager.defaultManager fileExistsAtPath:marker.path]) return YES;
  NSURL *userLibrary = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
  // An injected fixture library represents fixture files, never the process's
  // real WebKit default store. This also keeps reset tests out of user sessions.
  if (![self.libraryURL.URLByResolvingSymlinksInPath.URLByStandardizingPath.path
        isEqual:userLibrary.URLByResolvingSymlinksInPath.URLByStandardizingPath.path]) return YES;
  __block BOOL finished = NO;
  void (^remove)(void) = ^{
    [[self defaultBrowserDataStore] removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes
      modifiedSince:NSDate.distantPast completionHandler:^{ finished = YES; }];
  };
  if (NSThread.isMainThread) remove(); else dispatch_async(dispatch_get_main_queue(), remove);
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
  while (!finished && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  if (!finished && error) *error = [NSError errorWithDomain:@"Talaria.AppReset" code:3 userInfo:@{
    NSLocalizedDescriptionKey:@"WebKit did not finish deleting its browser data. Retry the reset."
  }];
  return finished;
}

- (BOOL)removeNamedBrowserDataStore:(NSError **)error {
  NSURL *record = [self.libraryURL URLByAppendingPathComponent:@"Application Support/com.talaria.chat/WebKit/WebKitStoreIdentifier"];
  if (![NSFileManager.defaultManager fileExistsAtPath:record.path]) return YES;
  NSError *metadataError = nil;
  NSString *identifierString = [[NSString stringWithContentsOfURL:record encoding:NSUTF8StringEncoding error:&metadataError]
    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSUUID *identifier = identifierString ? [[NSUUID alloc] initWithUUIDString:identifierString] : nil;
  if (!identifier || [identifier.UUIDString isEqual:@"00000000-0000-0000-0000-000000000000"]) {
    if (error) *error = metadataError ?: [NSError errorWithDomain:@"Talaria.AppReset" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Talaria's browser data-store identifier is unreadable. Reset has stopped so browser data is not left behind."}];
    return NO;
  }
  if (@available(macOS 14.0, *)) {
    __block BOOL finished = NO;
    __block NSError *removalError = nil;
    void (^remove)(void) = ^{
      [WKWebsiteDataStore fetchAllDataStoreIdentifiers:^(NSArray<NSUUID *> *identifiers) {
        if (![identifiers containsObject:identifier]) { finished = YES; return; }
        [WKWebsiteDataStore removeDataStoreForIdentifier:identifier completionHandler:^(NSError *failure) {
          removalError = failure; finished = YES;
        }];
      }];
    };
    if (NSThread.isMainThread) remove(); else dispatch_async(dispatch_get_main_queue(), remove);
    // Startup is synchronous; keep servicing the main loop while WebKit removes
    // its own named store. Retain the reset request and identifier on failure.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!finished && deadline.timeIntervalSinceNow > 0)
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (!finished || removalError) {
      if (error) *error = removalError ?: [NSError errorWithDomain:@"Talaria.AppReset" code:3 userInfo:@{NSLocalizedDescriptionKey:@"WebKit did not finish deleting its browser data. Retry the reset."}];
      return NO;
    }
    return YES;
  }
  if (error) *error = [NSError errorWithDomain:@"Talaria.AppReset" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Deleting this browser data store requires macOS 14 or later."}];
  return NO;
}

- (BOOL)performPendingReset:(NSError **)error {
  if (!self.resetPending) return YES;
  // Fail before removing files when the trusted helper cannot erase the token.
  if (![self.credentialStore removeCredentialForAccount:TLOpenRouterTokenCredentialAccount error:error]) return NO;

  if (![self removeDefaultBrowserDataStore:error] || ![self removeNamedBrowserDataStore:error]) return NO;

  // Fixed app-owned roots include orphaned VMs, SQLite sidecars, and the whole
  // WebKit profile. Never follow VM paths from database rows or delete the
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
