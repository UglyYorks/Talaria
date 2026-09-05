#import <Foundation/Foundation.h>
#import "TLAppReset.h"
#import "Database.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TLResetTestCredentials : NSObject <TLCredentialStore>
@property NSMutableDictionary *values;
@property BOOL failRemoval;
@property NSUInteger removals;
@end
@implementation TLResetTestCredentials
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error { return self.values[account]; }
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error {
  self.values[account] = credential; return YES;
}
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error {
  self.removals++;
  if (self.failRemoval) {
    if (error) *error = [NSError errorWithDomain:@"Test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Helper unavailable"}];
    return NO;
  }
  [self.values removeObjectForKey:account]; return YES;
}
@end

// Never write the real Talaria preferences or touch the user's Keychain.
@interface TLResetTestDefaults : NSUserDefaults
@property NSMutableDictionary *domains;
@property BOOL failSync;
@end
@implementation TLResetTestDefaults
- (instancetype)init { if ((self = [super initWithSuiteName:NSUUID.UUID.UUIDString])) _domains = [NSMutableDictionary dictionary]; return self; }
- (void)removePersistentDomainForName:(NSString *)name { [self.domains removeObjectForKey:name]; }
- (BOOL)synchronize { return !self.failSync; }
@end

static NSURL *WriteFile(NSURL *library, NSString *path) {
  NSURL *url = [library URLByAppendingPathComponent:path];
  NSError *error = nil;
  Check([NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:&error], @"create fixture parent");
  Check([@"fixture" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error], @"write fixture");
  return url;
}

int main(void) {
  @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *library = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
      URLByAppendingPathComponent:[@"TalariaResetTests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    TLResetTestCredentials *credentials = [[TLResetTestCredentials alloc] init];
    TLResetTestDefaults *defaults = [[TLResetTestDefaults alloc] init];
    defaults.domains[@"com.talaria.chat"] = @{@"theme":@"dark"};
    defaults.domains[@"another.app"] = @{@"keep":@YES};
    credentials.values[@"unrelatedAccount"] = @"keep";
    TLAppReset *reset = [[TLAppReset alloc] initWithLibraryURL:library userDefaults:defaults credentialStore:credentials];
    NSError *error = nil;
    Check([reset performPendingReset:&error] && credentials.removals == 0, @"ordinary startup does not erase anything");

    NSURL *dbURL = [library URLByAppendingPathComponent:@"Application Support/com.talaria.chat/talaria.sqlite3"];
    @autoreleasepool {
      TLDatabase *database = [[TLDatabase alloc] initWithURL:dbURL credentialStore:credentials error:&error];
      Check(database != nil, @"open fixture database");
      TLAppSettings *settings = [database appSettings:&error];
      settings.onboardingCompleted = YES;
      settings.openRouterToken = @"test-token";
      Check([database saveAppSettings:settings error:&error] != nil, @"save completed onboarding and fake token");
      Check([database createChatWithModel:@"test/model" error:&error] != nil, @"create chat");
      Check([database createAgentWithName:@"Test VM" guestKind:TLAgentGuestKindLinux runtime:TLAgentRuntimePython
        vmDirectory:[[library URLByAppendingPathComponent:@"Application Support/com.talaria.chat/Agents/test"] path]
        error:&error] != nil, @"create registered VM");
    }
    NSArray *ownedFiles = @[
      @"Application Support/com.talaria.chat/Agents/test/workspace/file.txt",
      @"Application Support/com.talaria.chat/Agents/orphan/workspace/file.txt",
      @"Application Support/com.talaria.chat/Chromium/Default/Cookies",
      @"Application Support/com.talaria.chat/talaria.sqlite3-wal",
      @"Application Support/com.talaria.chat/talaria.sqlite3-shm",
      @"Caches/com.talaria.chat/cache", @"WebKit/com.talaria.chat/data",
      @"HTTPStorages/com.talaria.chat/data", @"HTTPStorages/com.talaria.chat.binarycookies",
      @"Saved Application State/com.talaria.chat.savedState/window",
      @"Logs/com.talaria.chat/log"
    ];
    for (NSString *path in ownedFiles) WriteFile(library, path);
    NSURL *unrelated = WriteFile(library, @"Application Support/another.app/keep.txt");
    NSURL *helper = WriteFile(library, @"Application Support/Talaria/CredentialHelper/Talaria Credentials.app/keep.txt");
    NSURL *linkedFile = WriteFile(library, @"UserDocuments/keep.txt");
    Check([fm createSymbolicLinkAtPath:[library URLByAppendingPathComponent:@"Application Support/com.talaria.chat/Agents/test/external"].path
                 withDestinationPath:linkedFile.URLByDeletingLastPathComponent.path error:&error], @"create VM symlink");
    Check([reset requestReset:&error] && reset.resetPending, @"persist reset request");
    credentials.failRemoval = YES;
    Check(![reset performPendingReset:&error] && error != nil, @"surface credential helper failure");
    Check(reset.resetPending && [fm fileExistsAtPath:dbURL.path], @"credential failure keeps request and database");
    credentials.failRemoval = NO;
    error = nil;
    // A new service simulates the next process after the original app exits.
    reset = [[TLAppReset alloc] initWithLibraryURL:library userDefaults:defaults credentialStore:credentials];
    Check([reset performPendingReset:&error] && error == nil && !reset.resetPending, @"restart completes reset");
    Check(![fm fileExistsAtPath:dbURL.path], @"remove entire database");
    for (NSString *path in ownedFiles) Check(![fm fileExistsAtPath:[library URLByAppendingPathComponent:path].path], path);
    Check([fm fileExistsAtPath:unrelated.path] && [fm fileExistsAtPath:helper.path] && [fm fileExistsAtPath:linkedFile.path],
      @"preserve unrelated data, helper installation, and symlink targets");
    Check(!defaults.domains[@"com.talaria.chat"] && defaults.domains[@"another.app"], @"only erase app preferences");
    Check(!credentials.values[TLOpenRouterTokenCredentialAccount] && credentials.values[@"unrelatedAccount"], @"only erase Talaria token");
    @autoreleasepool {
      TLDatabase *fresh = [[TLDatabase alloc] initWithURL:dbURL credentialStore:credentials error:&error];
      Check(fresh != nil && ![fresh appSettings:&error].onboardingCompleted, @"fresh database requires onboarding");
      Check([fresh appSettings:&error].openRouterToken.length == 0, @"fresh onboarding has no token");
      Check([fresh listAgents:&error].count == 0 && [fresh listChats:&error].count == 0, @"fresh database has no agents or chats");
    }
    // A filesystem failure after some files are erased must remain retryable.
    Check([fm removeItemAtURL:[library URLByAppendingPathComponent:@"Caches"] error:&error], @"remove empty cache parent");
    WriteFile(library, @"Caches");
    Check([reset requestReset:&error], @"request another reset");
    error = nil;
    Check(![reset performPendingReset:&error] && error && reset.resetPending, @"partial filesystem failure remains pending");
    Check([fm removeItemAtURL:[library URLByAppendingPathComponent:@"Caches"] error:&error], @"remove fixture obstruction");
    defaults.failSync = YES;
    error = nil;
    Check(![reset performPendingReset:&error] && error && reset.resetPending, @"preference flush failure remains pending");
    defaults.failSync = NO;
    error = nil;
    Check([reset performPendingReset:&error] && !reset.resetPending, @"retry tolerates already deleted files and token");
    NSUInteger removals = credentials.removals;
    Check([reset performPendingReset:&error] && credentials.removals == removals, @"successful reset does not repeat on next launch");
    Check([reset requestReset:&error] && [reset cancelReset:&error] && !reset.resetPending, @"cancel request after relaunch failure");
    Check([fm removeItemAtURL:library error:&error], @"clean up isolated test fixtures");
    NSLog(@"AppResetTests passed");
  }
  return 0;
}
