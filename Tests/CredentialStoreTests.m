#import <Foundation/Foundation.h>
#import "Database.h"
#import "SQLiteConnection.h"

// Every test injects this store; the test executable never accesses Keychain.
@interface TLFakeCredentialStore : NSObject <TLCredentialStore>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *credentials;
@property (nonatomic) BOOL failReads;
@property (nonatomic) BOOL failWrites;
@property (nonatomic) BOOL failRemovals;
@property (nonatomic) NSUInteger readCount;
@end

@implementation TLFakeCredentialStore
- (instancetype)init {
  self = [super init];
  if (self) { _credentials = [NSMutableDictionary dictionary]; }
  return self;
}
- (BOOL)fail:(NSError **)error {
  if (error) {
    *error = [NSError errorWithDomain:@"Talaria.FakeCredentialStore" code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"Simulated credential failure"}];
  }
  return NO;
}
- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error {
  self.readCount++;
  if (self.failReads) { [self fail:error]; return nil; }
  return self.credentials[account];
}
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error {
  if (self.failWrites) { return [self fail:error]; }
  self.credentials[account] = credential;
  return YES;
}
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error {
  if (self.failRemovals) { return [self fail:error]; }
  [self.credentials removeObjectForKey:account];
  return YES;
}
@end

static void TLAssert(BOOL condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

@interface TLCredentialTestFixture : NSObject
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLSQLiteConnection *inspectionConnection;
@property (nonatomic, strong) TLFakeCredentialStore *store;
@end

@implementation TLCredentialTestFixture
- (instancetype)init {
  self = [super init];
  if (self) {
    NSString *templatePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TalariaCredentialTests.XXXXXX"];
    char *temporaryPath = strdup(templatePath.fileSystemRepresentation);
    char *createdPath = mkdtemp(temporaryPath);
    TLAssert(createdPath != NULL, @"creates an isolated temporary directory");
    _directory = [NSURL fileURLWithPath:@(createdPath) isDirectory:YES];
    free(temporaryPath);
    _url = [_directory URLByAppendingPathComponent:@"test.sqlite3"];
    _store = [[TLFakeCredentialStore alloc] init];
    NSError *error = nil;
    _database = [[TLDatabase alloc] initWithURL:_url credentialStore:_store error:&error];
    TLAssert(_database != nil && error == nil, @"creates a database with fake credentials");
    _inspectionConnection = [TLSQLiteConnection openURL:_url error:&error];
    TLAssert(_inspectionConnection != nil && error == nil, @"opens isolated database for inspection");
  }
  return self;
}
- (void)dealloc {
  _database = nil;
  _inspectionConnection = nil;
  [NSFileManager.defaultManager removeItemAtURL:_directory error:nil];
}
- (void)execute:(const char *)sql {
  NSError *error = nil;
  TLAssert([self.inspectionConnection executeSQL:sql error:&error], error.localizedDescription ?: @"executes test SQL");
}
- (NSString *)setting:(NSString *)key {
  TLSQLiteStatement *statement = [self.inspectionConnection prepareSQL:"SELECT value FROM settings WHERE key = ?1" error:nil];
  TLAssert(statement != nil, @"prepares settings inspection");
  [statement bindText:key atIndex:1];
  return [statement step] == SQLITE_ROW ? [statement stringAtColumn:0] : nil;
}
- (void)seedLegacyToken {
  [self execute:"INSERT INTO settings (key, value) VALUES ('rememberOpenRouterToken', 'true'), ('openRouterToken', 'legacy-secret-for-migration')"];
}
@end

static void TestCredentialPersistence(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  NSError *error = nil;
  TLAppSettings *settings = [fixture.database appSettings:&error];
  TLAssert(settings != nil && fixture.store.readCount == 0, @"default settings do not read Keychain");
  settings.openRouterToken = @"  remembered-secret  ";
  settings.rememberOpenRouterToken = YES;
  settings.selectedModel = @"model/custom";
  TLAssert([fixture.database saveAppSettings:settings error:&error] != nil && error == nil, @"saves credentials and preferences");
  TLAssert([fixture.store.credentials[TLOpenRouterTokenCredentialAccount] isEqualToString:@"remembered-secret"], @"trims token in credential store");
  TLAssert([fixture setting:@"openRouterToken"] == nil, @"never stores a token row in SQLite");
  TLAssert([[fixture setting:@"selectedModel"] isEqualToString:@"model/custom"], @"keeps ordinary preferences in SQLite");
  NSData *bytes = [NSData dataWithContentsOfURL:fixture.url];
  NSData *secret = [@"remembered-secret" dataUsingEncoding:NSUTF8StringEncoding];
  TLAssert([bytes rangeOfData:secret options:0 range:NSMakeRange(0, bytes.length)].location == NSNotFound, @"SQLite file contains no saved credential bytes");

  fixture.database = [[TLDatabase alloc] initWithURL:fixture.url credentialStore:fixture.store error:&error];
  TLAssert([[[fixture.database appSettings:&error] openRouterToken] isEqualToString:@"remembered-secret"], @"reopened database retrieves remembered token from credential store");
  settings.rememberOpenRouterToken = NO;
  settings.openRouterToken = @"session-only-secret";
  TLAppSettings *saved = [fixture.database saveAppSettings:settings error:&error];
  TLAssert([saved.openRouterToken isEqualToString:@"session-only-secret"], @"keeps unremembered token in returned session settings");
  TLAssert(fixture.store.credentials.count == 0, @"forgetting token removes secure persistence");
  TLAssert([[[fixture.database appSettings:&error] openRouterToken] isEqualToString:@""], @"does not reload a session-only token");
}

static void TestLegacyMigration(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  [fixture seedLegacyToken];
  fixture.store.failWrites = YES;
  NSError *error = nil;
  TLAssert([fixture.database appSettings:&error] == nil && error != nil, @"reports a migration write failure");
  TLAssert([[fixture setting:@"openRouterToken"] isEqualToString:@"legacy-secret-for-migration"], @"keeps only copy when Keychain write fails");
  fixture.store.failWrites = NO;
  error = nil;
  TLAppSettings *settings = [fixture.database appSettings:&error];
  TLAssert(settings != nil && error == nil, @"retries a failed migration successfully");
  TLAssert([settings.openRouterToken isEqualToString:@"legacy-secret-for-migration"], @"migrates legacy token");
  TLAssert([fixture setting:@"openRouterToken"] == nil, @"deletes legacy row after secure write");
  NSData *bytes = [NSData dataWithContentsOfURL:fixture.url];
  NSData *legacyBytes = [@"legacy-secret-for-migration" dataUsingEncoding:NSUTF8StringEncoding];
  TLAssert([bytes rangeOfData:legacyBytes options:0 range:NSMakeRange(0, bytes.length)].location == NSNotFound, @"migration scrubs legacy secret from live SQLite pages");
}

static void TestMigrationDeleteFailureAndExistingCredential(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  [fixture seedLegacyToken];
  [fixture execute:"CREATE TRIGGER reject_credential_delete BEFORE DELETE ON settings WHEN OLD.key = 'openRouterToken' BEGIN SELECT RAISE(ABORT, 'simulated deletion failure'); END"];
  NSError *error = nil;
  TLAssert([fixture.database appSettings:&error] == nil && error != nil, @"reports failed plaintext cleanup");
  TLAssert(fixture.store.credentials[TLOpenRouterTokenCredentialAccount] != nil, @"retains secure copy when SQLite cleanup fails");
  TLAssert([fixture setting:@"openRouterToken"] != nil, @"keeps retryable legacy migration row");
  fixture.store.credentials[TLOpenRouterTokenCredentialAccount] = @"newer-secure-secret";
  [fixture execute:"DROP TRIGGER reject_credential_delete"];
  error = nil;
  TLAppSettings *settings = [fixture.database appSettings:&error];
  TLAssert([settings.openRouterToken isEqualToString:@"newer-secure-secret"] && error == nil, @"retry preserves newer secure credential");
  TLAssert([fixture setting:@"openRouterToken"] == nil, @"retry removes obsolete plaintext copy");
}

static void TestUnrememberedLegacyToken(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  [fixture execute:"INSERT INTO settings (key, value) VALUES ('rememberOpenRouterToken', 'false'), ('openRouterToken', 'stale-unremembered-token')"];
  fixture.store.failReads = YES;
  NSError *error = nil;
  TLAppSettings *settings = [fixture.database appSettings:&error];
  TLAssert(settings != nil && error == nil && settings.openRouterToken.length == 0, @"does not load or migrate unremembered legacy token");
  TLAssert(fixture.store.credentials.count == 0 && fixture.store.readCount == 0, @"unremembered legacy cleanup does not access Keychain");
  TLAssert([fixture setting:@"openRouterToken"] == nil, @"removes stale unremembered plaintext");
}

static void TestSaveFailures(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  TLAppSettings *settings = [fixture.database appSettings:nil];
  settings.rememberOpenRouterToken = YES;
  settings.openRouterToken = @"original-secret";
  TLAssert([fixture.database saveAppSettings:settings error:nil] != nil, @"establishes original credential");
  settings.openRouterToken = @"replacement-secret";
  settings.selectedModel = @"model/changed";
  fixture.store.failWrites = YES;
  NSError *error = nil;
  TLAssert([fixture.database saveAppSettings:settings error:&error] == nil && error != nil, @"reports failed secure save");
  TLAssert([[fixture setting:@"selectedModel"] isEqualToString:TLDefaultModelID], @"failed credential save rolls back preferences");
  TLAssert([fixture.store.credentials[TLOpenRouterTokenCredentialAccount] isEqualToString:@"original-secret"], @"failed write preserves old credential");
  fixture.store.failWrites = NO;
  fixture.store.failReads = YES;
  error = nil;
  TLAssert([fixture.database appSettings:&error] == nil && error != nil, @"propagates Keychain read failures instead of returning an empty token");
  fixture.store.failReads = NO;
  fixture.store.failRemovals = YES;
  settings.rememberOpenRouterToken = NO;
  error = nil;
  TLAssert([fixture.database saveAppSettings:settings error:&error] == nil && error != nil, @"reports failure to forget a token");
  TLAssert([[fixture setting:@"rememberOpenRouterToken"] isEqualToString:@"true"], @"failed deletion does not falsely report token forgotten");
  fixture.store.failRemovals = NO;
  error = nil;
  TLAssert([fixture.database saveAppSettings:settings error:&error] != nil && error == nil, @"can retry forgetting the credential");
  TLAssert(fixture.store.credentials.count == 0, @"retry removes credential");
}

static void TestDatabaseCommitFailure(void) {
  TLCredentialTestFixture *fixture = [[TLCredentialTestFixture alloc] init];
  TLAppSettings *settings = [fixture.database appSettings:nil];
  settings.rememberOpenRouterToken = YES;
  settings.openRouterToken = @"original-secret";
  TLAssert([fixture.database saveAppSettings:settings error:nil] != nil, @"saves initial credential");
  // The deferred foreign key fails only at COMMIT, after the secure write.
  [fixture execute:"CREATE TABLE credential_test_parent (id INTEGER PRIMARY KEY); CREATE TABLE credential_test_child (parent_id INTEGER REFERENCES credential_test_parent(id) DEFERRABLE INITIALLY DEFERRED); CREATE TRIGGER reject_settings_commit AFTER UPDATE ON settings WHEN NEW.key = 'selectedModel' BEGIN INSERT INTO credential_test_child VALUES (42); END"];
  settings.openRouterToken = @"replacement-secret";
  settings.selectedModel = @"model/changed";
  NSError *error = nil;
  TLAssert([fixture.database saveAppSettings:settings error:&error] == nil && error != nil, @"reports SQLite commit failure");
  TLAssert([fixture.store.credentials[TLOpenRouterTokenCredentialAccount] isEqualToString:@"original-secret"], @"restores previous secure credential after failed SQLite commit");
  TLAssert([[fixture setting:@"selectedModel"] isEqualToString:TLDefaultModelID], @"failed commit preserves ordinary preferences");
  [fixture execute:"DROP TRIGGER reject_settings_commit"];
  error = nil;
  TLAssert([fixture.database saveAppSettings:settings error:&error] != nil && error == nil, @"can retry after SQLite failure");
  TLAssert([fixture.store.credentials[TLOpenRouterTokenCredentialAccount] isEqualToString:@"replacement-secret"], @"retry stores new credential");
}

int main(void) {
  @autoreleasepool {
    TestCredentialPersistence();
    TestLegacyMigration();
    TestMigrationDeleteFailureAndExistingCredential();
    TestUnrememberedLegacyToken();
    TestSaveFailures();
    TestDatabaseCommitFailure();
    NSLog(@"CredentialStoreTests passed");
  }
  return 0;
}
