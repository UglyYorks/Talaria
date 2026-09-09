#import "TLBrowserProfileImporter.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#include <sqlite3.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <tuple>
#include <memory>
#include <map>
#include "leveldb/db.h"
#include "leveldb/write_batch.h"
#include "db/filename.h"
#include "snappy.h"

static NSError *ImportError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.BrowserImport" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL Fail(NSError **error, NSString *message) { if (error) *error = ImportError(message); return NO; }
static NSURL *Child(NSURL *root, NSString *path) { return [root URLByAppendingPathComponent:path]; }
static BOOL Exists(NSURL *url) { return [NSFileManager.defaultManager fileExistsAtPath:url.path]; }
static NSURL *ProfileRoot(NSDictionary *browser, NSURL *home) { return Child(Child(home,@"Library/Application Support"),browser[@"root"]); }
static BOOL MissingFile(NSError *error) {
  return [error.domain isEqual:NSCocoaErrorDomain] && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError);
}
static NSMutableDictionary<NSString *,NSURL *> *GrantedRoots(void) {
  static NSMutableDictionary *roots; static dispatch_once_t once;
  dispatch_once(&once, ^{ roots = [NSMutableDictionary dictionary]; }); return roots;
}
static NSString *const ImportBookmarksKey = @"BrowserImportFolderBookmarks";
static NSString *Text(sqlite3_stmt *s, int i) {
  const char *p = (const char *)sqlite3_column_text(s,i);
  return p ? [[NSString alloc] initWithBytes:p length:sqlite3_column_bytes(s,i) encoding:NSUTF8StringEncoding] : @"";
}
static NSData *Blob(sqlite3_stmt *s, int i) { return [NSData dataWithBytes:sqlite3_column_blob(s,i) length:sqlite3_column_bytes(s,i)]; }
static std::string Bytes(NSData *data) { return std::string((const char *)data.bytes, data.length); }
static NSData *Data(const leveldb::Slice &s) { return [NSData dataWithBytes:s.data() length:s.size()]; }
static BOOL WebOrigin(NSString *origin) {
  NSURLComponents *c = [NSURLComponents componentsWithString:origin];
  return [origin rangeOfString:@"^"].location == NSNotFound && c.host.length && [@[@"http",@"https"] containsObject:c.scheme] && !c.user && !c.password && !c.query && !c.fragment && !c.path.length;
}
// Use SQLite's backup API so WAL records are included in a consistent snapshot.
static sqlite3 *Snapshot(NSURL *url, NSError **error) {
  sqlite3 *source = nullptr, *dest = nullptr;
  if (sqlite3_open_v2(url.fileSystemRepresentation, &source, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK ||
      sqlite3_open(":memory:",&dest) != SQLITE_OK) {
    if(source) sqlite3_close(source); if(dest) sqlite3_close(dest);
    Fail(error,@"Could not read the browser database. Check folder access and retry."); return nullptr;
  }
  sqlite3_busy_timeout(source, 1000);
  sqlite3_backup *backup = sqlite3_backup_init(dest,"main",source,"main");
  int result = SQLITE_ERROR;
  if(backup) for(int attempt=0; attempt<5; ++attempt) {
    result=sqlite3_backup_step(backup,-1);
    if(result!=SQLITE_BUSY && result!=SQLITE_LOCKED) break;
    sqlite3_sleep(50);
  }
  if(backup) sqlite3_backup_finish(backup); sqlite3_close(source);
  if(result != SQLITE_DONE) { sqlite3_close(dest); Fail(error,@"The browser database is busy or unreadable. Try importing again in a moment."); return nullptr; }
  return dest;
}
static BOOL Column(sqlite3 *db, const char *table, NSString *name) {
  sqlite3_stmt *s = nullptr; BOOL found = NO;
  std::string query = std::string("PRAGMA table_info(")+table+")";
  if(sqlite3_prepare_v2(db,query.c_str(),-1,&s,nullptr)==SQLITE_OK)
    while(sqlite3_step(s)==SQLITE_ROW) if([Text(s,1) isEqual:name]) found=YES;
  sqlite3_finalize(s); return found;
}
static NSData *StorageString(NSString *s) {
  BOOL latin = [s canBeConvertedToEncoding:NSISOLatin1StringEncoding];
  unsigned char marker = latin ? 1 : 0;
  NSMutableData *data = [NSMutableData dataWithBytes:&marker length:1];
  [data appendData:[s dataUsingEncoding:latin ? NSISOLatin1StringEncoding : NSUTF16LittleEndianStringEncoding]]; return data;
}
static NSData *StorageKey(NSString *origin, NSString *key) {
  NSMutableData *data = [[[@"_" stringByAppendingString:origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [data appendBytes:"\0" length:1]; [data appendData:StorageString(key)]; return data;
}
static NSString *EntryOrigin(NSData *data) {
  const char *p = (const char *)data.bytes;
  if(data.length < 3 || p[0]!='_') return nil;
  const char *end = (const char *)memchr(p+1,0,data.length-1);
  if(!end || end+1 >= p+data.length) return nil;
  NSString *origin = [[NSString alloc] initWithBytes:p+1 length:end-p-1 encoding:NSUTF8StringEncoding];
  return WebOrigin(origin) ? origin : nil;
}

// Only database files matter. Never open or replace the source LOCK, and never
// run LevelDB recovery against a live browser's directory.
using StorageStamp = std::tuple<dev_t,ino_t,off_t,time_t,long,time_t,long>;
using StorageFiles = std::map<std::string,StorageStamp>;
static BOOL StorageInventory(NSURL *root, StorageFiles &files, NSError **error) {
  NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:error];
  if(!names) return NO;
  for(NSString *name in names) {
    uint64_t number=0; leveldb::FileType type;
    if(!leveldb::ParseFileName(name.UTF8String,&number,&type)) continue;
    if(type!=leveldb::kCurrentFile && type!=leveldb::kDescriptorFile && type!=leveldb::kLogFile && type!=leveldb::kTableFile) continue;
    struct stat st={};
    if(lstat(Child(root,name).fileSystemRepresentation,&st)!=0)
      return Fail(error,@"The browser’s local storage changed during import. Try again in a moment.");
    if(!S_ISREG(st.st_mode)) return Fail(error,@"The browser’s local storage contains an unsupported file.");
    files[name.UTF8String]=std::make_tuple(st.st_dev,st.st_ino,st.st_size,st.st_mtimespec.tv_sec,st.st_mtimespec.tv_nsec,st.st_ctimespec.tv_sec,st.st_ctimespec.tv_nsec);
  }
  return YES;
}

@implementation TLBrowserProfileImporter
+ (NSArray<NSDictionary *> *)browserCatalogue {
  // Bundle IDs also find apps moved out of /Applications through Launch Services.
  NSArray *rows = @[
    @[@"Google Chrome",@"com.google.Chrome",@"Google/Chrome",@"Chrome Safe Storage",@"chromium"],
    @[@"Google Chrome Beta",@"com.google.Chrome.beta",@"Google/Chrome Beta",@"Chrome Safe Storage",@"chromium"],
    @[@"Google Chrome Canary",@"com.google.Chrome.canary",@"Google/Chrome Canary",@"Chrome Safe Storage",@"chromium"],
    @[@"Chromium",@"org.chromium.Chromium",@"Chromium",@"Chromium Safe Storage",@"chromium"],
    @[@"Microsoft Edge",@"com.microsoft.edgemac",@"Microsoft Edge",@"Microsoft Edge Safe Storage",@"chromium"],
    @[@"Microsoft Edge Beta",@"com.microsoft.edgemac.Beta",@"Microsoft Edge Beta",@"Microsoft Edge Safe Storage",@"chromium"],
    @[@"Brave Browser",@"com.brave.Browser",@"BraveSoftware/Brave-Browser",@"Brave Safe Storage",@"chromium"],
    @[@"Brave Browser Beta",@"com.brave.Browser.beta",@"BraveSoftware/Brave-Browser-Beta",@"Brave Safe Storage",@"chromium"],
    @[@"Arc",@"company.thebrowser.Browser",@"Arc/User Data",@"Arc Safe Storage",@"chromium"],
    @[@"Dia",@"company.thebrowser.dia",@"Dia/User Data",@"Dia Safe Storage",@"chromium"],
    @[@"Vivaldi",@"com.vivaldi.Vivaldi",@"Vivaldi",@"Vivaldi Safe Storage",@"chromium"],
    @[@"Opera",@"com.operasoftware.Opera",@"com.operasoftware.Opera",@"Opera Safe Storage",@"chromium"],
    @[@"Opera GX",@"com.operasoftware.OperaGX",@"com.operasoftware.OperaGX",@"Opera Safe Storage",@"chromium"],
    @[@"Firefox",@"org.mozilla.firefox",@"Firefox",@"",@"firefox"],
    @[@"Firefox Developer Edition",@"org.mozilla.firefoxdeveloperedition",@"Firefox",@"",@"firefox"],
    @[@"Firefox Nightly",@"org.mozilla.nightly",@"Firefox",@"",@"firefox"],
    @[@"Zen",@"app.zen-browser.zen",@"zen",@"",@"firefox"],
    @[@"LibreWolf",@"io.gitlab.librewolf-community",@"librewolf",@"",@"firefox"],
    @[@"Waterfox",@"net.waterfox.waterfox",@"Waterfox",@"",@"firefox"],
    @[@"Floorp",@"one.ablaze.floorp",@"Floorp",@"",@"firefox"],
    @[@"Safari",@"com.apple.Safari",@"",@"",@"unsupported"],
    @[@"Safari Technology Preview",@"com.apple.SafariTechnologyPreview",@"",@"",@"unsupported"],
    @[@"Orion",@"com.kagi.kagimacOS",@"",@"",@"unsupported"],
    @[@"DuckDuckGo",@"com.duckduckgo.macos.browser",@"",@"",@"unsupported"]];
  NSMutableArray *result = [NSMutableArray array];
  for(NSArray *r in rows) [result addObject:@{@"name":r[0],@"bundleID":r[1],@"root":r[2],@"keychainService":r[3],@"engine":r[4]}];
  return result;
}
+ (NSArray<NSDictionary *> *)installedBrowsers {
  NSMutableArray *result = [NSMutableArray array];
  for(NSDictionary *browser in self.browserCatalogue) {
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:browser[@"bundleID"]];
    if(!app || !Exists(app)) continue;
    NSMutableDictionary *entry = browser.mutableCopy; entry[@"applicationURL"] = app;
    NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory()];
    NSURL *root = ProfileRoot(browser,home); entry[@"profileRootURL"] = root;
    if(![browser[@"engine"] isEqual:@"unsupported"]) {
      @synchronized(self) {
        if(!GrantedRoots()[browser[@"bundleID"]]) {
          NSData *bookmark = [NSUserDefaults.standardUserDefaults dictionaryForKey:ImportBookmarksKey][browser[@"bundleID"]];
          if([bookmark isKindOfClass:NSData.class]) {
            BOOL stale = NO;
            NSURL *granted = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
            if([granted.URLByStandardizingPath.path isEqual:root.URLByStandardizingPath.path]) {
              [granted startAccessingSecurityScopedResource]; GrantedRoots()[browser[@"bundleID"]] = granted;
              if(stale) [self grantAccessToBrowser:browser directoryURL:granted error:nil];
            }
          }
        }
      }
    }
    NSError *error = nil;
    entry[@"profiles"] = [self profilesForBrowser:browser homeURL:home error:&error];
    if(error) entry[@"discoveryError"] = error;
    [result addObject:entry];
  }
  return result;
}
+ (NSArray<NSDictionary *> *)profilesForBrowser:(NSDictionary *)browser homeURL:(NSURL *)home {
  return [self profilesForBrowser:browser homeURL:home error:nil];
}
+ (BOOL)grantAccessToBrowser:(NSDictionary *)browser directoryURL:(NSURL *)URL error:(NSError **)error {
  NSURL *expected = ProfileRoot(browser,[NSURL fileURLWithPath:NSHomeDirectory()]);
  if(![URL.URLByStandardizingPath.path isEqual:expected.URLByStandardizingPath.path])
    return Fail(error,[NSString stringWithFormat:@"Select the %@ folder at %@.",expected.lastPathComponent,expected.path]);
  BOOL scoped = [URL startAccessingSecurityScopedResource];
  if(![NSFileManager.defaultManager contentsOfDirectoryAtURL:URL includingPropertiesForKeys:nil options:0 error:error]) {
    if(scoped) [URL stopAccessingSecurityScopedResource]; return NO;
  }
  NSData *bookmark = [URL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess includingResourceValuesForKeys:nil relativeToURL:nil error:error];
  if(!bookmark) { if(scoped) [URL stopAccessingSecurityScopedResource]; return NO; }
  @synchronized(self) {
    NSMutableDictionary *saved = [[NSUserDefaults.standardUserDefaults dictionaryForKey:ImportBookmarksKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    saved[browser[@"bundleID"]] = bookmark; [NSUserDefaults.standardUserDefaults setObject:saved forKey:ImportBookmarksKey];
    [GrantedRoots()[browser[@"bundleID"]] stopAccessingSecurityScopedResource];
    GrantedRoots()[browser[@"bundleID"]] = URL;
  }
  return YES;
}
+ (NSArray<NSDictionary *> *)profilesForBrowser:(NSDictionary *)browser homeURL:(NSURL *)home error:(NSError **)error {
  if(error) *error = nil;
  if([browser[@"engine"] isEqual:@"unsupported"]) return @[];
  NSURL *root = ProfileRoot(browser,home);
  NSError *listingError = nil;
  NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:&listingError];
  // EPERM (macOS privacy) and EACCES are different from a browser with no profile yet.
  if(!children) { if(error && !MissingFile(listingError)) *error = listingError; return @[]; }
  NSMutableArray *result = [NSMutableArray array]; NSMutableDictionary<NSString *,NSString *> *paths = [NSMutableDictionary dictionary];
  if([browser[@"engine"] isEqual:@"firefox"]) {
    NSString *ini = [NSString stringWithContentsOfURL:Child(root,@"profiles.ini") encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *sections = [NSMutableArray array]; NSMutableDictionary *section;
    for(NSString *raw in [ini componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if([line hasPrefix:@"["]) { section = [NSMutableDictionary dictionary]; if([line hasPrefix:@"[Profile"]) [sections addObject:section]; }
      else { NSRange eq = [line rangeOfString:@"="]; if(eq.location!=NSNotFound) section[[line substringToIndex:eq.location]]=[line substringFromIndex:eq.location+1]; }
    }
    for(NSDictionary *s in sections) if([s[@"Path"] length]) {
      NSURL *url = [s[@"IsRelative"] isEqual:@"0"] ? [NSURL fileURLWithPath:s[@"Path"]] : Child(root,s[@"Path"]);
      paths[url.path] = s[@"Name"] ?: url.lastPathComponent;
    }
  } else {
    NSData *state = [NSData dataWithContentsOfURL:Child(root,@"Local State")];
    id json = state ? [NSJSONSerialization JSONObjectWithData:state options:0 error:nil] : nil;
    id cache = [json isKindOfClass:NSDictionary.class] && [json[@"profile"] isKindOfClass:NSDictionary.class] ? json[@"profile"][@"info_cache"] : nil;
    if(![cache isKindOfClass:NSDictionary.class]) cache = @{};
    NSMutableSet *names = [NSMutableSet setWithArray:children];
    [names addObjectsFromArray:[cache allKeys]];
    for(NSString *name in names) {
      if(![name isEqual:@"Default"] && ![name hasPrefix:@"Profile "] && !cache[name]) continue;
      if(![name.lastPathComponent isEqual:name] || [name isEqual:@".."] || [name isEqual:@"Guest Profile"] || [name isEqual:@"System Profile"]) continue;
      id metadata = cache[name]; id label = [metadata isKindOfClass:NSDictionary.class] ? metadata[@"name"] : nil;
      paths[Child(root,name).path] = [label isKindOfClass:NSString.class] && [label length] ? label : name;
    }
    if(Exists(Child(root,@"Cookies")) || Exists(Child(root,@"Network/Cookies"))) paths[root.path] = @"Default"; // Opera
  }
  for(NSString *path in [paths.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *profileError = nil;
    if(![NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&profileError]) {
      if(error && !MissingFile(profileError)) *error = profileError;
      continue;
    }
    BOOL firefox = [browser[@"engine"] isEqual:@"firefox"];
    BOOL cookies = Exists(Child(url,firefox ? @"cookies.sqlite" : @"Cookies")) || (!firefox && Exists(Child(url,@"Network/Cookies")));
    BOOL storage = Exists(Child(url,firefox ? @"storage/default" : @"Local Storage/leveldb"));
    if(cookies || storage) [result addObject:@{@"name":paths[path],@"URL":url}];
  }
  return result;
}
+ (NSData *)decryptCookie:(NSData *)encrypted password:(NSData *)password host:(NSString *)host version:(NSInteger)version {
  if(encrypted.length < 19 || memcmp(encrypted.bytes,"v10",3)!=0) return nil;
  unsigned char key[16], iv[16]; memset(iv,' ',sizeof(iv));
  if(CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)password.bytes,password.length,(const uint8_t *)"saltysalt",9,kCCPRFHmacAlgSHA1,1003,key,sizeof(key))!=kCCSuccess) return nil;
  NSMutableData *plain = [NSMutableData dataWithLength:encrypted.length+16]; size_t length=0;
  CCCryptorStatus status=CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,key,sizeof(key),iv,(const char *)encrypted.bytes+3,encrypted.length-3,plain.mutableBytes,plain.length,&length);
  for (volatile unsigned char *p = key; p < key + sizeof(key); ++p) *p = 0;
  if(status!=kCCSuccess) return nil; plain.length=length;
  if(version>=24) {
    NSData *domain=[host dataUsingEncoding:NSUTF8StringEncoding]; unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(domain.bytes,(CC_LONG)domain.length,hash);
    if(length<sizeof(hash) || memcmp(plain.bytes,hash,sizeof(hash))) return nil;
    return [plain subdataWithRange:NSMakeRange(sizeof(hash),length-sizeof(hash))];
  }
  return plain;
}
+ (NSArray *)readCookies:(NSURL *)url browser:(NSDictionary *)browser skipped:(NSUInteger *)skipped error:(NSError **)error {
  if(!Exists(url)) return @[];
  sqlite3 *db=Snapshot(url,error); if(!db) return nil;
  BOOL firefox=[browser[@"engine"] isEqual:@"firefox"];
  NSInteger version=0; sqlite3_stmt *s=nullptr;
  if(!firefox && sqlite3_prepare_v2(db,"SELECT value FROM meta WHERE key='version'",-1,&s,nullptr)==SQLITE_OK && sqlite3_step(s)==SQLITE_ROW) version=sqlite3_column_int(s,0);
  sqlite3_finalize(s); s=nullptr;
  if(firefox && sqlite3_prepare_v2(db,"PRAGMA user_version",-1,&s,nullptr)==SQLITE_OK && sqlite3_step(s)==SQLITE_ROW) version=sqlite3_column_int(s,0);
  sqlite3_finalize(s); s=nullptr;
  NSString *sameSiteColumn = firefox && Column(db,"moz_cookies",@"rawSameSite") ? @"CASE WHEN sameSite=1 AND rawSameSite=0 THEN 256 ELSE sameSite END" : @"sameSite";
  NSString *partition = firefox ? (Column(db,"moz_cookies",@"originAttributes") ? @"originAttributes" : @"''") : (Column(db,"cookies",@"top_frame_site_key") ? @"top_frame_site_key" : @"''");
  NSString *query = firefox ? [NSString stringWithFormat:@"SELECT host,name,value,path,expiry,isSecure,isHttpOnly,%@,%@ FROM moz_cookies",sameSiteColumn,partition] : [NSString stringWithFormat:@"SELECT host_key,name,value,path,expires_utc,is_secure,is_httponly,samesite,%@,encrypted_value,has_expires FROM cookies",partition];
  if(sqlite3_prepare_v2(db,query.UTF8String,-1,&s,nullptr)!=SQLITE_OK) { sqlite3_close(db); Fail(error,@"This browser’s cookie database format is not supported."); return nil; }
  NSMutableArray *cookies=[NSMutableArray array]; NSData *password=nil; BOOL failed=NO; int rc;
  while((rc=sqlite3_step(s))==SQLITE_ROW) {
    if(Text(s,8).length) { (*skipped)++; continue; } // Never flatten partitions or Firefox containers.
    NSString *host=Text(s,0), *value=Text(s,2);
    double expiry=sqlite3_column_double(s,4); BOOL persistent=firefox ? expiry>0 : sqlite3_column_int(s,10);
    if(!firefox) expiry=expiry/1000000.0-11644473600.0;
    else if(version>=16) expiry/=1000.0;
    if(persistent && expiry <= NSDate.date.timeIntervalSince1970) { (*skipped)++; continue; }
    if(!firefox && sqlite3_column_bytes(s,9)>0) {
      if(!password) {
        CFTypeRef secret=nullptr;
        OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:browser[@"keychainService"],(__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne},&secret);
        if(status!=errSecSuccess) { Fail(error,@"Could not access this browser’s Safe Storage key. Allow the macOS Keychain request and retry."); failed=YES; break; }
        password=CFBridgingRelease(secret);
      }
      NSData *plain=[self decryptCookie:Blob(s,9) password:password host:host version:version];
      value=plain ? [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] : nil;
      if(!value) { Fail(error,@"This browser’s cookie encryption could not be decoded. Nothing has been imported."); failed=YES; break; }
    }
    NSInteger sameSite=sqlite3_column_int(s,7); if(firefox && sameSite==256) sameSite=-1;
    [cookies addObject:@{@"domain":host ?: @"",@"name":Text(s,1) ?: @"",@"value":value ?: @"",@"path":Text(s,3) ?: @"/",@"expires":@(expiry),@"persistent":@(persistent),@"secure":@(sqlite3_column_int(s,5)!=0),@"httpOnly":@(sqlite3_column_int(s,6)!=0),@"sameSite":@(sameSite)}];
  }
  sqlite3_finalize(s); sqlite3_close(db);
  if(rc!=SQLITE_DONE && !failed) { Fail(error,@"Could not finish reading the browser’s cookies."); failed=YES; }
  return failed ? nil : cookies;
}
+ (BOOL)readChromiumStorage:(NSURL *)url into:(NSMutableDictionary *)entries skipped:(NSUInteger *)skipped error:(NSError **)error {
  if(!Exists(url)) return YES;
  NSURL *scratch=Child([NSURL fileURLWithPath:NSTemporaryDirectory()],[@"TalariaBrowserImport-" stringByAppendingString:NSUUID.UUID.UUIDString]);
  NSFileManager *fm=NSFileManager.defaultManager;
  if(![fm createDirectoryAtURL:scratch withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
  NSURL *snapshot=Child(scratch,@"leveldb");
  BOOL copied=NO; NSError *copyError=nil;
  // A quiet copy interval is enough; the browser can stay open and hold LOCK.
  // Include WAL/manifest files and reject changes, replacements, new files or
  // compaction deletions during the entire copy. Retry before exposing any data.
  for(int attempt=0; attempt<5 && !copied; ++attempt) {
    [fm removeItemAtURL:snapshot error:nil]; copyError=nil;
    StorageFiles before,after;
    if(StorageInventory(url,before,&copyError) &&
       [fm createDirectoryAtURL:snapshot withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&copyError]) {
      BOOL complete=YES;
      for(const auto &file : before) {
        NSString *name=[NSString stringWithUTF8String:file.first.c_str()];
        if(![fm copyItemAtURL:Child(url,name) toURL:Child(snapshot,name) error:&copyError]) { complete=NO; break; }
      }
      copied=complete && StorageInventory(url,after,&copyError) && before==after;
    }
    if(!copied && attempt<4) usleep(50000);
  }
  BOOL ok=copied;
  if(!copied) { if(copyError && error) *error=copyError; else Fail(error,@"The browser’s local storage kept changing during import. Try again in a moment."); }
  if(copied) {
    leveldb::Options options; options.paranoid_checks=true; leveldb::DB *raw=nullptr;
    auto status=leveldb::DB::Open(options,snapshot.path.UTF8String,&raw); std::unique_ptr<leveldb::DB> db(raw);
    if(!status.ok()) ok=Fail(error,@"Could not read the local storage snapshot. Try importing again.");
    else {
      std::string version; status=db->Get(leveldb::ReadOptions(),"VERSION",&version);
      if(!status.ok() || version!="1") ok=Fail(error,@"This browser’s local storage version is not supported.");
      else {
        leveldb::ReadOptions read; read.verify_checksums=true;
        std::unique_ptr<leveldb::Iterator> it(db->NewIterator(read));
        for(it->SeekToFirst();it->Valid();it->Next()) {
          NSData *key=Data(it->key());
          if(it->key().size() && it->key().data()[0]=='_') {
            if(EntryOrigin(key)) entries[key]=Data(it->value()); else (*skipped)++;
          }
        }
        if(!it->status().ok()) ok=Fail(error,@"The browser’s local storage is damaged or unreadable.");
      }
    }
  }
  [fm removeItemAtURL:scratch error:nil]; return ok;
}
+ (BOOL)readFirefoxStorage:(NSURL *)root into:(NSMutableDictionary *)entries skipped:(NSUInteger *)skipped error:(NSError **)error {
  if(!Exists(root)) return YES;
  NSArray *origins=[NSFileManager.defaultManager contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:error]; if(!origins) return NO;
  for(NSURL *directory in origins) {
    NSURL *url=Child(directory,@"ls/data.sqlite"); if(!Exists(url)) continue;
    sqlite3 *db=Snapshot(url,error); if(!db) return NO; sqlite3_stmt *s=nullptr;
    NSString *origin=nil;
    if(sqlite3_prepare_v2(db,"SELECT origin FROM database",-1,&s,nullptr)==SQLITE_OK && sqlite3_step(s)==SQLITE_ROW) origin=Text(s,0);
    sqlite3_finalize(s); s=nullptr;
    if([directory.lastPathComponent containsString:@"^"] || !WebOrigin(origin)) { (*skipped)++; sqlite3_close(db); continue; }
    BOOL modern=Column(db,"data",@"conversion_type");
    const char *query=modern ? "SELECT key,value,conversion_type,compression_type FROM data" : "SELECT key,value,1,compressed FROM data";
    if(sqlite3_prepare_v2(db,query,-1,&s,nullptr)!=SQLITE_OK) { sqlite3_close(db); return Fail(error,@"This Firefox local storage format is not supported."); }
    int rc; BOOL ok=YES;
    while((rc=sqlite3_step(s))==SQLITE_ROW) {
      NSData *value=Blob(s,1); int encoding=sqlite3_column_int(s,2), compression=sqlite3_column_int(s,3);
      if(compression==1) {
        std::string plain; size_t length=0;
        if(!snappy::GetUncompressedLength((const char *)value.bytes,value.length,&length) || length>64*1024*1024 || !snappy::Uncompress((const char *)value.bytes,value.length,&plain)) { ok=NO; break; }
        value=Data(plain);
      } else if(compression!=0) { ok=NO; break; }
      NSString *decoded=encoding==0 || encoding==1 ? [[NSString alloc] initWithData:value encoding:encoding==1 ? NSUTF8StringEncoding : NSUTF16LittleEndianStringEncoding] : nil;
      NSString *key=Text(s,0); if(!decoded || !key) { ok=NO; break; }
      entries[StorageKey(origin,key)]=StorageString(decoded);
    }
    sqlite3_finalize(s); sqlite3_close(db);
    if(!ok || rc!=SQLITE_DONE) return Fail(error,@"Could not decode this Firefox local storage database. Nothing has been imported.");
  }
  return YES;
}
+ (NSDictionary *)readProfile:(NSDictionary *)profile browser:(NSDictionary *)browser error:(NSError **)error {
  NSURL *url=profile[@"URL"]; BOOL firefox=[browser[@"engine"] isEqual:@"firefox"];
  NSURL *cookiesURL=Child(url,firefox ? @"cookies.sqlite" : @"Network/Cookies");
  if(!firefox && !Exists(cookiesURL)) cookiesURL=Child(url,@"Cookies");
  NSUInteger skipped=0; NSArray *cookies=[self readCookies:cookiesURL browser:browser skipped:&skipped error:error]; if(!cookies) return nil;
  NSMutableDictionary *storage=[NSMutableDictionary dictionary];
  BOOL ok=firefox ? [self readFirefoxStorage:Child(url,@"storage/default") into:storage skipped:&skipped error:error] : [self readChromiumStorage:Child(url,@"Local Storage/leveldb") into:storage skipped:&skipped error:error];
  if(!ok) return nil;
  if(!cookies.count && !storage.count) { Fail(error,@"No supported cookies or local storage were found in this profile."); return nil; }
  return @{@"cookies":cookies,@"storage":storage,@"skipped":@(skipped)};
}
// Session cookies are replayed once after the restart needed for local storage,
// preserving their session-only lifetime on subsequent launches.
+ (BOOL)writePending:(NSDictionary *)payload profileURL:(NSURL *)URL error:(NSError **)error {
  NSData *data=[NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
  if(!data || ![NSFileManager.defaultManager createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
  NSURL *pending=Child(URL,@"TalariaPendingLocalStorage.plist"), *temp=Child(URL,[@".import-" stringByAppendingString:NSUUID.UUID.UUIDString]);
  if(![NSFileManager.defaultManager createFileAtPath:temp.path contents:data attributes:@{NSFilePosixPermissions:@0600}]) return Fail(error,@"Could not save the pending browser import.");
  if(rename(temp.fileSystemRepresentation,pending.fileSystemRepresentation)!=0) { [NSFileManager.defaultManager removeItemAtURL:temp error:nil]; return Fail(error,@"Could not save the pending browser import."); }
  return YES;
}
+ (NSDictionary *)readPending:(NSURL *)URL error:(NSError **)error {
  NSURL *pending=Child(URL,@"TalariaPendingLocalStorage.plist");
  if(!Exists(pending)) return @{@"entries":@[],@"sessionCookies":@[]};
  NSDictionary *payload=[NSDictionary dictionaryWithContentsOfURL:pending];
  if(![payload[@"entries"] isKindOfClass:NSArray.class] || ![payload[@"sessionCookies"] isKindOfClass:NSArray.class]) { Fail(error,@"The pending browser import is unreadable."); return nil; }
  for(id cookie in payload[@"sessionCookies"]) {
    if(![cookie isKindOfClass:NSDictionary.class]) { Fail(error,@"Invalid pending session cookie."); return nil; }
    for(NSString *key in @[@"domain",@"name",@"value",@"path"]) if(![cookie[key] isKindOfClass:NSString.class]) { Fail(error,@"Invalid pending session cookie."); return nil; }
    for(NSString *key in @[@"expires",@"persistent",@"secure",@"httpOnly",@"sameSite"]) if(![cookie[key] isKindOfClass:NSNumber.class]) { Fail(error,@"Invalid pending session cookie."); return nil; }
  }
  return payload;
}
+ (BOOL)stageLocalStorage:(NSDictionary<NSData *,NSData *> *)entries profileURL:(NSURL *)URL error:(NSError **)error {
  return [self stageLocalStorage:entries sessionCookies:@[] profileURL:URL error:error];
}
+ (BOOL)stageLocalStorage:(NSDictionary<NSData *,NSData *> *)entries sessionCookies:(NSArray *)cookies profileURL:(NSURL *)URL error:(NSError **)error {
  if(!entries.count && !cookies.count) return YES;
  @synchronized(self) {
    NSDictionary *old=[self readPending:URL error:error]; if(!old) return NO;
    NSMutableDictionary *merged=[NSMutableDictionary dictionary];
    for(NSDictionary *entry in old[@"entries"]) {
      if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"key"] isKindOfClass:NSData.class] || ![entry[@"value"] isKindOfClass:NSData.class]) return Fail(error,@"The pending browser import contains an invalid entry.");
      merged[entry[@"key"]]=entry[@"value"];
    }
    [merged addEntriesFromDictionary:entries]; NSMutableArray *rows=[NSMutableArray array];
    for(NSData *key in merged) [rows addObject:@{@"key":key,@"value":merged[key]}];
    NSMutableArray *sessions=[old[@"sessionCookies"] mutableCopy];
    for(NSDictionary *cookie in cookies) {
      NSIndexSet *replaced=[sessions indexesOfObjectsPassingTest:^BOOL(NSDictionary *other, NSUInteger index, BOOL *stop) {
        return [other[@"domain"] isEqual:cookie[@"domain"]] && [other[@"path"] isEqual:cookie[@"path"]] && [other[@"name"] isEqual:cookie[@"name"]];
      }];
      [sessions removeObjectsAtIndexes:replaced]; [sessions addObject:cookie];
    }
    return [self writePending:@{@"entries":rows,@"sessionCookies":sessions} profileURL:URL error:error];
  }
}
+ (NSArray *)pendingSessionCookiesAtProfileURL:(NSURL *)URL error:(NSError **)error {
  return [self readPending:URL error:error][@"sessionCookies"];
}
+ (BOOL)clearPendingSessionCookiesAtProfileURL:(NSURL *)URL error:(NSError **)error {
  @synchronized(self) {
    NSURL *pending=Child(URL,@"TalariaPendingLocalStorage.plist"); if(!Exists(pending)) return YES;
    NSDictionary *payload=[self readPending:URL error:error]; if(!payload) return NO;
    if(![payload[@"entries"] count]) return [NSFileManager.defaultManager removeItemAtURL:pending error:error];
    return [self writePending:@{@"entries":payload[@"entries"],@"sessionCookies":@[]} profileURL:URL error:error];
  }
}
+ (BOOL)applyPendingLocalStorageAtProfileURL:(NSURL *)URL error:(NSError **)error {
  NSURL *pending=Child(URL,@"TalariaPendingLocalStorage.plist"); if(!Exists(pending)) return YES;
  NSDictionary *payload=[self readPending:URL error:error]; if(!payload) return NO;
  NSArray *rows=payload[@"entries"]; if(!rows.count) return YES;
  // CEF’s Chrome runtime stores the active profile under cache_path/Default.
  NSURL *directory=Child(URL,@"Default/Local Storage/leveldb");
  if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
  leveldb::Options options; options.create_if_missing=true; options.paranoid_checks=true; leveldb::DB *raw=nullptr;
  auto status=leveldb::DB::Open(options,directory.path.UTF8String,&raw); std::unique_ptr<leveldb::DB> db(raw);
  if(!status.ok()) return Fail(error,@"Local storage import is pending. Close other Talaria instances and restart to retry.");
  std::string version; status=db->Get(leveldb::ReadOptions(),"VERSION",&version);
  if((!status.ok() && !status.IsNotFound()) || (status.ok() && version!="1")) return Fail(error,@"Talaria’s local storage version is not supported by this import.");
  leveldb::WriteBatch batch; batch.Put("VERSION","1");
  std::map<std::string,std::string> merged;
  leveldb::ReadOptions read; read.verify_checksums=true; std::unique_ptr<leveldb::Iterator> it(db->NewIterator(read));
  for(it->Seek("_");it->Valid() && it->key().starts_with("_");it->Next()) merged[it->key().ToString()]=it->value().ToString();
  if(!it->status().ok()) return Fail(error,@"Talaria’s local storage could not be read. Import remains pending.");
  NSMutableSet *origins=[NSMutableSet set];
  for(id row in rows) {
    if(![row isKindOfClass:NSDictionary.class] || ![row[@"key"] isKindOfClass:NSData.class] || ![row[@"value"] isKindOfClass:NSData.class] || !EntryOrigin(row[@"key"])) return Fail(error,@"The pending import contains an invalid local storage entry.");
    NSData *key=row[@"key"], *value=row[@"value"]; merged[Bytes(key)]=Bytes(value); batch.Put(Bytes(key),Bytes(value)); [origins addObject:EntryOrigin(key)];
  }
  // Recalculate metadata for merged origins instead of copying stale source quotas.
  for(NSString *origin in origins) {
    std::string prefix="_"+std::string(origin.UTF8String)+std::string(1,'\0'); uint64_t size=0;
    for(auto iter=merged.lower_bound(prefix);iter!=merged.end() && iter->first.compare(0,prefix.size(),prefix)==0;++iter) size+=iter->first.size()-prefix.size()+iter->second.size();
    std::string meta; auto varint=[&meta](uint64_t v) { while(v>=128) { meta.push_back((v&127)|128); v>>=7; } meta.push_back(v); };
    meta.push_back(8); varint((NSDate.date.timeIntervalSince1970+11644473600.0)*1000000); meta.push_back(16); varint(size);
    batch.Put("META:"+std::string(origin.UTF8String),meta);
  }
  leveldb::WriteOptions write; write.sync=true; status=db->Write(write,&batch);
  if(!status.ok()) return Fail(error,@"Local storage could not be merged. Import remains pending for the next restart.");
  if([payload[@"sessionCookies"] count]) return [self writePending:@{@"entries":@[],@"sessionCookies":payload[@"sessionCookies"]} profileURL:URL error:error];
  return [NSFileManager.defaultManager removeItemAtURL:pending error:error];
}
@end
