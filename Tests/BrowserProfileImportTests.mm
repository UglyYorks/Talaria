#import <Foundation/Foundation.h>
#import "TLBrowserProfileImporter.h"
#import <CommonCrypto/CommonCrypto.h>
#include <sqlite3.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
#include <fcntl.h>
#include <unistd.h>
#include "leveldb/db.h"
#include "leveldb/write_batch.h"
#include "snappy.h"
static void Check(BOOL value, NSString *message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } puts(message.UTF8String); }
static NSURL *At(NSURL *root,NSString *path) { return [root URLByAppendingPathComponent:path]; }
static void SQL(NSURL *url, const char *query) {
  [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
  sqlite3 *db=nullptr; Check(sqlite3_open(url.fileSystemRepresentation,&db)==SQLITE_OK,@"Open fixture");
  Check(sqlite3_exec(db,query,nullptr,nullptr,nullptr)==SQLITE_OK,@"Create fixture"); sqlite3_close(db);
}
static std::string Key(const char *origin,const char *key) { return std::string("_")+origin+std::string("\0\1",2)+key; }
static NSData *D(const std::string &s) { return [NSData dataWithBytes:s.data() length:s.size()]; }
static leveldb::DB *Open(NSURL *url) {
  [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
  leveldb::Options options; options.create_if_missing=true; options.write_buffer_size=1024;
  leveldb::DB *db=nullptr; Check(leveldb::DB::Open(options,url.path.UTF8String,&db).ok(),@"Open LevelDB fixture"); return db;
}
static NSData *Encrypted(NSString *host, NSString *value, BOOL hash, NSString *keyPassword = @"fixture-key") {
  NSData *password=[keyPassword dataUsingEncoding:NSUTF8StringEncoding]; unsigned char key[16],iv[16]; memset(iv,' ',16);
  CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)password.bytes,password.length,(const uint8_t *)"saltysalt",9,kCCPRFHmacAlgSHA1,1003,key,16);
  NSMutableData *plain=[NSMutableData data]; if(hash) { unsigned char digest[32]; NSData *domain=[host dataUsingEncoding:NSUTF8StringEncoding]; CC_SHA256(domain.bytes,(CC_LONG)domain.length,digest); [plain appendBytes:digest length:32]; }
  [plain appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
  NSMutableData *encrypted=[NSMutableData dataWithLength:plain.length+16]; size_t length=0;
  CCCrypt(kCCEncrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key,16,iv,plain.bytes,plain.length,encrypted.mutableBytes,encrypted.length,&length); encrypted.length=length;
  NSMutableData *result=[NSMutableData dataWithBytes:"v10" length:3]; [result appendData:encrypted]; return result;
}
// Separate process owns LevelDB's exclusive LOCK and an active SQLite WAL
// transaction, just as an open browser does. No real browser data is used.
static int SourceWorker(const char *path) {
  std::string root(path); leveldb::DB *db=nullptr; leveldb::Options options;
  if(!leveldb::DB::Open(options,root+"/Local Storage/leveldb",&db).ok()) return 2;
  sqlite3 *sql=nullptr;
  if(sqlite3_open((root+"/Network/Cookies").c_str(),&sql)!=SQLITE_OK) return 2;
  if(sqlite3_exec(sql,"PRAGMA journal_mode=WAL; BEGIN IMMEDIATE; UPDATE cookies SET value='uncommitted' WHERE name='session';",nullptr,nullptr,nullptr)!=SQLITE_OK) return 2;
  if(!db->Put(leveldb::WriteOptions(),Key("https://example.test","live-browser"),std::string("\1",1)+"open").ok()) return 2;
  write(STDOUT_FILENO,"R",1); char command;
  while(read(STDIN_FILENO,&command,1)==1 && command!='q') {
    if(command!='w') continue;
    write(STDOUT_FILENO,"W",1);
    for(int i=0;i<200;++i) {
      leveldb::WriteBatch batch; std::string value=std::string("\1",1)+std::to_string(i);
      batch.Put(Key("https://example.test","pair-a"),value); batch.Put(Key("https://example.test","pair-b"),value);
      if(!db->Write(leveldb::WriteOptions(),&batch).ok()) return 2;
      if(i%20==0) db->CompactRange(nullptr,nullptr);
      usleep(1000);
    }
    write(STDOUT_FILENO,"D",1);
  }
  sqlite3_exec(sql,"ROLLBACK",nullptr,nullptr,nullptr); sqlite3_close(sql); delete db; return 0;
}
static void TestLiveSource(const char *executable, NSURL *profile, NSDictionary *browser) {
  int commands[2],responses[2]; Check(pipe(commands)==0 && pipe(responses)==0,@"Create live browser fixture channels");
  posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions,commands[0],STDIN_FILENO);
  posix_spawn_file_actions_adddup2(&actions,responses[1],STDOUT_FILENO);
  for(int fd : {commands[0],commands[1],responses[0],responses[1]}) posix_spawn_file_actions_addclose(&actions,fd);
  char *args[]={(char *)executable,(char *)"--live-source",(char *)profile.fileSystemRepresentation,nullptr};
  extern char **environ; pid_t pid=0;
  Check(posix_spawn(&pid,executable,&actions,nullptr,args,environ)==0,@"Start a separate browser database owner");
  posix_spawn_file_actions_destroy(&actions); close(commands[0]); close(responses[1]);
  char ready=0; Check(read(responses[0],&ready,1)==1 && ready=='R',@"Live browser owns the databases");
  int lockFD=open(At(profile,@"Local Storage/leveldb/LOCK").fileSystemRepresentation,O_RDONLY);
  struct flock lock={}; lock.l_type=F_RDLCK; lock.l_whence=SEEK_SET;
  Check(lockFD>=0 && fcntl(lockFD,F_SETLK,&lock)<0,@"Source LevelDB is exclusively locked by another process"); close(lockFD);
  NSError *error=nil; NSDictionary *source=@{@"URL":profile};
  NSDictionary *data=[TLBrowserProfileImporter readProfile:source browser:browser error:&error];
  Check(data && [data[@"cookies"] count]==1 && [[[data[@"cookies"] firstObject][@"value"] description] isEqual:@"hello"],@"Import committed cookies while a live WAL writer has an uncommitted transaction");
  Check([data[@"storage"][D(Key("https://example.test","live-browser"))] isEqual:D(std::string("\1",1)+"open")],@"Import local storage while the source browser retains its lock");
  write(commands[1],"w",1); Check(read(responses[0],&ready,1)==1 && ready=='W',@"Start live writes and compaction");
  for(int i=0;i<3;++i) {
    error=nil; data=[TLBrowserProfileImporter readProfile:source browser:browser error:&error];
    if(!data) { Check(error!=nil,@"An unstable live snapshot fails explicitly"); continue; }
    NSData *a=data[@"storage"][D(Key("https://example.test","pair-a"))], *b=data[@"storage"][D(Key("https://example.test","pair-b"))];
    Check((!a && !b) || [a isEqual:b],@"Concurrent writes never expose a torn LevelDB batch");
  }
  Check(read(responses[0],&ready,1)==1 && ready=='D',@"Live writer finished compaction");
  data=[TLBrowserProfileImporter readProfile:source browser:browser error:&error];
  Check([data[@"storage"][D(Key("https://example.test","pair-a"))] isEqual:D(std::string("\1",1)+"199")],@"Retry reads the latest committed values with the browser still open");
  write(commands[1],"q",1); close(commands[1]); close(responses[0]); int status=0; waitpid(pid,&status,0);
  Check(WIFEXITED(status) && WEXITSTATUS(status)==0,@"Source browser database owner closes cleanly");
}
int main(int argc,char **argv) { @autoreleasepool {
  if(argc==3 && strcmp(argv[1],"--live-source")==0) return SourceWorker(argv[2]);
  NSURL *home=At([NSURL fileURLWithPath:NSTemporaryDirectory()],[@"talaria-import-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]);
  NSDictionary *chrome=TLBrowserProfileImporter.browserCatalogue.firstObject;
  NSURL *root=At(home,@"Library/Application Support/Google/Chrome"), *profile=At(root,@"Profile 2");
  SQL(At(profile,@"Network/Cookies"),"CREATE TABLE meta(key TEXT,value TEXT); INSERT INTO meta VALUES('version','24'); CREATE TABLE cookies(host_key TEXT,name TEXT,value TEXT,path TEXT,expires_utc INTEGER,is_secure INTEGER,is_httponly INTEGER,samesite INTEGER,top_frame_site_key TEXT,encrypted_value BLOB,has_expires INTEGER); INSERT INTO cookies VALUES('.example.test','session','hello','/',0,1,1,2,'',X'',0); INSERT INTO cookies VALUES('.example.test','expired','no','/',1,0,0,1,'',X'',1); INSERT INTO cookies VALUES('.example.test','partition','no','/',0,1,0,0,'https://other.test',X'',0);");
  [@"{\"profile\":{\"info_cache\":{\"Profile 2\":{\"name\":\"Work\"}}}}" writeToURL:At(root,@"Local State") atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSURL *sourceDB=At(profile,@"Local Storage/leveldb"); leveldb::DB *db=Open(sourceDB);
  db->Put(leveldb::WriteOptions(),"VERSION","1");
  auto live=Key("https://example.test","token"),deleted=Key("https://example.test","deleted");
  db->Put(leveldb::WriteOptions(),live,std::string("\1",1)+"live");
  db->Put(leveldb::WriteOptions(),deleted,"secret"); db->CompactRange(nullptr,nullptr); db->Delete(leveldb::WriteOptions(),deleted);
  db->Put(leveldb::WriteOptions(),Key("chrome-extension://extension","key"),"secret"); delete db;
  NSDictionary *browser=[chrome mutableCopy]; [browser setValue:@"test.browser.not-running" forKey:@"bundleID"];
  NSArray *profiles=[TLBrowserProfileImporter profilesForBrowser:browser homeURL:home];
  Check(profiles.count==1 && [profiles[0][@"name"] isEqual:@"Work"],@"Discover named Chromium profiles including Network/Cookies");
  NSError *discoveryError = nil;
  Check(chmod(root.fileSystemRepresentation,0000)==0,@"Make the fixture profile root inaccessible");
  NSArray *blocked = [TLBrowserProfileImporter profilesForBrowser:browser homeURL:home error:&discoveryError];
  Check(blocked.count==0 && discoveryError!=nil,@"Denied Chrome directory access is reported, not mistaken for missing profiles");
  Check(chmod(root.fileSystemRepresentation,0700)==0,@"Restore fixture access");
  profiles = [TLBrowserProfileImporter profilesForBrowser:browser homeURL:home error:&discoveryError];
  Check(profiles.count==1 && !discoveryError,@"Discover Chrome profiles after folder access is restored");
  Check(chmod(profile.fileSystemRepresentation,0000)==0,@"Make an individual Chrome profile inaccessible");
  blocked = [TLBrowserProfileImporter profilesForBrowser:browser homeURL:home error:&discoveryError];
  Check(blocked.count==0 && discoveryError!=nil,@"Report access denial inside a readable Chrome root");
  Check(chmod(profile.fileSystemRepresentation,0700)==0,@"Restore individual profile access");
  NSArray *missing = [TLBrowserProfileImporter profilesForBrowser:browser homeURL:At(home,@"missing") error:&discoveryError];
  Check(missing.count==0 && !discoveryError,@"A browser that has not created a profile is distinct from access denial");
  NSError *error=nil; NSDictionary *data=[TLBrowserProfileImporter readProfile:profiles[0] browser:browser error:&error];
  Check(data && [data[@"cookies"] count]==1 && [data[@"storage"] count]==1,@"Import live cookies/storage and honor LevelDB tombstones");
  Check([data[@"skipped"] integerValue]==3,@"Skip expired, partitioned and extension data");
  TestLiveSource(argv[0],profile,browser);
  NSDictionary *cookie=[data[@"cookies"] firstObject];
  Check([cookie[@"httpOnly"] boolValue] && [cookie[@"secure"] boolValue] && [cookie[@"sameSite"] integerValue]==2 && ![cookie[@"persistent"] boolValue],@"Preserve cookie attributes and sessions");
  NSData *password=[@"fixture-key" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *encrypted=Encrypted(@".example.test",@"value ✓",YES);
  Check([[[NSString alloc] initWithData:[TLBrowserProfileImporter decryptCookie:encrypted password:password host:@".example.test" version:24] encoding:NSUTF8StringEncoding] isEqual:@"value ✓"],@"Decrypt v24 host-bound cookie values");
  Check(![TLBrowserProfileImporter decryptCookie:encrypted password:password host:@"wrong.test" version:24],@"Reject encrypted cookies bound to another host");
  Check(![TLBrowserProfileImporter decryptCookie:encrypted password:[NSData data] host:@".example.test" version:24],@"Reject a wrong encryption key");
  Check([TLBrowserProfileImporter decryptCookie:Encrypted(@".example.test",@"",NO) password:password host:@".example.test" version:23].length==0,@"Handle legacy encrypted empty cookie values");
  NSURL *target=At(home,@"Talaria");
  Check([TLBrowserProfileImporter stageLocalStorage:data[@"storage"] profileURL:target error:&error],@"Stage local storage import");
  NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:At(target,@"TalariaPendingLocalStorage.plist").path error:nil];
  Check([attrs[NSFilePosixPermissions] intValue]==0600,@"Pending secrets are private to the user");
  NSDictionary *origins=[TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:target error:&error];
  Check([origins[@"https://example.test"][@"token"] isEqual:@"live"],@"Decode imported local storage into origin-scoped values");
  Check([NSFileManager.defaultManager fileExistsAtPath:At(target,@"TalariaPendingLocalStorage.plist").path],@"Reading pending values preserves them until successful browser replay");
  Check([TLBrowserProfileImporter clearPendingLocalStorageForOrigin:@"https://unrelated.test" profileURL:target error:&error],@"Clearing an unrelated origin is a no-op");
  Check([TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:target error:&error].count==1,@"Keep unrelated pending site data");
  Check([TLBrowserProfileImporter clearPendingLocalStorageForOrigin:@"https://example.test" profileURL:target error:&error],@"Acknowledge successfully replayed origin");
  Check([TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:target error:&error].count==0,@"Remove successfully replayed staging data");
  Check([TLBrowserProfileImporter clearPendingLocalStorageAtProfileURL:target error:&error],@"Restart without a pending import is a no-op");
  Check([TLBrowserProfileImporter stageLocalStorage:data[@"storage"] sessionCookies:@[cookie] profileURL:target error:&error],@"Queue sessions with the required storage restart");
  Check([TLBrowserProfileImporter pendingSessionCookiesAtProfileURL:target error:&error].count==1,@"Session restoration is pending until restart");
  Check([TLBrowserProfileImporter clearPendingSessionCookiesAtProfileURL:target error:&error],@"Clear cookies cancels pending session restoration");
  Check([TLBrowserProfileImporter pendingSessionCookiesAtProfileURL:target error:&error].count==0,@"Cleared cookies cannot be resurrected by the import");
  Check([TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:target error:&error].count==1,@"Clearing cookies preserves the pending local storage import");
  // Upgrading Talaria migrates its own previous profile once, including cookies
  // encrypted using the previous embedded engine's explicit mock-Keychain mode.
  NSURL *migrationRoot = At(home, @"upgrade"), *legacyRoot = At(migrationRoot, @"Chromium"), *webKitRoot = At(migrationRoot, @"WebKit");
  Check([NSFileManager.defaultManager createDirectoryAtURL:legacyRoot withIntermediateDirectories:YES attributes:nil error:&error], @"Create legacy Talaria fixture root");
  Check([NSFileManager.defaultManager copyItemAtURL:profile toURL:At(legacyRoot, @"Default") error:&error], @"Copy an isolated previous Talaria profile");
  NSURL *legacyCookies = At(legacyRoot, @"Default/Network/Cookies");
  NSData *legacyEncrypted = Encrypted(@".example.test", @"migrated-session", YES, @"mock_password");
  sqlite3 *migrationSQL = nullptr; sqlite3_stmt *migrationStatement = nullptr;
  Check(sqlite3_open(legacyCookies.fileSystemRepresentation, &migrationSQL) == SQLITE_OK, @"Open legacy encrypted-cookie fixture");
  Check(sqlite3_prepare_v2(migrationSQL, "UPDATE cookies SET value='',encrypted_value=? WHERE name='session'", -1, &migrationStatement, nullptr) == SQLITE_OK, @"Prepare legacy encrypted-cookie fixture");
  sqlite3_bind_blob(migrationStatement, 1, legacyEncrypted.bytes, (int)legacyEncrypted.length, SQLITE_TRANSIENT);
  Check(sqlite3_step(migrationStatement) == SQLITE_DONE, @"Store a legacy mock-Keychain cookie");
  sqlite3_finalize(migrationStatement); sqlite3_close(migrationSQL);
  Check([TLBrowserProfileImporter stageLocalStorage:@{D(live):D(std::string("\1",1)+"latest-pending")} profileURL:legacyRoot error:&error], @"Stage an unapplied import in the previous profile");
  NSData *sourceCookieBytes = [NSData dataWithContentsOfURL:legacyCookies];
  Check([TLBrowserProfileImporter prepareMigrationFromLegacyProfileAtProfileURL:webKitRoot error:&error], @"Stage the previous Talaria profile for WebKit");
  NSArray *migratedCookies = [TLBrowserProfileImporter pendingSessionCookiesAtProfileURL:webKitRoot error:&error];
  Check(migratedCookies.count == 1 && [migratedCookies[0][@"value"] isEqual:@"migrated-session"] && [migratedCookies[0][@"httpOnly"] boolValue], @"Migration decrypts prior cookies and preserves HTTP-only access");
  NSDictionary *migratedOrigins = [TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:webKitRoot error:&error];
  Check([migratedOrigins[@"https://example.test"][@"token"] isEqual:@"latest-pending"], @"An unapplied legacy import supersedes its older database value");
  Check([sourceCookieBytes isEqual:[NSData dataWithContentsOfURL:legacyCookies]], @"Migration does not modify the previous cookie database");
  Check([TLBrowserProfileImporter clearPendingSessionCookiesAtProfileURL:webKitRoot error:&error] && [TLBrowserProfileImporter clearPendingLocalStorageAtProfileURL:webKitRoot error:&error], @"Acknowledge migrated browser data");
  Check([TLBrowserProfileImporter prepareMigrationFromLegacyProfileAtProfileURL:webKitRoot error:&error] && [TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:webKitRoot error:&error].count == 0 && [TLBrowserProfileImporter pendingSessionCookiesAtProfileURL:webKitRoot error:&error].count == 0, @"A later launch never resurrects cleared legacy cookies or local storage");
  // Firefox profile discovery and current compressed SQLite local storage.
  NSDictionary *firefox=nil; for(NSDictionary *b in TLBrowserProfileImporter.browserCatalogue) if([b[@"name"] isEqual:@"Firefox"]) firefox=b.mutableCopy;
  [firefox setValue:@"test.firefox.not-running" forKey:@"bundleID"];
  NSURL *ffroot=At(home,@"Library/Application Support/Firefox"), *ff=At(ffroot,@"Profiles/test.default");
  SQL(At(ff,@"cookies.sqlite"),"PRAGMA user_version=17; CREATE TABLE moz_cookies(host TEXT,name TEXT,value TEXT,path TEXT,expiry INTEGER,isSecure INTEGER,isHttpOnly INTEGER,sameSite INTEGER,originAttributes TEXT); INSERT INTO moz_cookies VALUES('example.test','ff','value','/',4102444800000,1,1,1,''); INSERT INTO moz_cookies VALUES('example.test','container','no','/',4102444800000,1,1,1,'^userContextId=1');");
  [@"[Profile0]\nName=Personal\nIsRelative=1\nPath=Profiles/test.default\n" writeToURL:At(ffroot,@"profiles.ini") atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSURL *ls=At(ff,@"storage/default/https+++example.test/ls/data.sqlite");
  SQL(ls,"CREATE TABLE database(origin TEXT); INSERT INTO database VALUES('https://example.test'); CREATE TABLE data(key TEXT,value BLOB,conversion_type INTEGER,compression_type INTEGER);");
  sqlite3 *sql=nullptr; sqlite3_open(ls.fileSystemRepresentation,&sql); sqlite3_stmt *s=nullptr;
  sqlite3_prepare_v2(sql,"INSERT INTO data VALUES('token',?,1,1)",-1,&s,nullptr);
  std::string compressed; snappy::Compress("firefox value",13,&compressed); sqlite3_bind_blob(s,1,compressed.data(),(int)compressed.size(),SQLITE_TRANSIENT); sqlite3_step(s); sqlite3_finalize(s); sqlite3_close(sql);
  profiles=[TLBrowserProfileImporter profilesForBrowser:firefox homeURL:home];
  Check(profiles.count==1 && [profiles[0][@"name"] isEqual:@"Personal"],@"Discover Firefox profiles.ini entries");
  data=[TLBrowserProfileImporter readProfile:profiles[0] browser:firefox error:&error];
  Check(data && [data[@"cookies"] count]==1 && [data[@"storage"] count]==1,@"Read Firefox cookies and compressed local storage");
  Check([data[@"storage"][D(live)] isEqual:D(std::string("\1",1)+"firefox value")],@"Canonicalize Firefox strings to Chromium encoding");
  Check([[data[@"cookies"] firstObject][@"expires"] doubleValue]==4102444800, @"Convert modern Firefox millisecond expiry to seconds");
  Check([data[@"skipped"] intValue]==1,@"Never flatten Firefox container cookies");
  SQL(ls,"UPDATE data SET compression_type=9;");
  Check(![TLBrowserProfileImporter readProfile:profiles[0] browser:firefox error:&error],@"Unsupported storage encoding fails without importing");
  [NSFileManager.defaultManager removeItemAtURL:home error:nil];
  puts("Browser profile import tests passed");
} }
