// Real WebKit consumer test, launched as a desktop app against disposable data.
#import <AppKit/AppKit.h>
#import "TLBrowserProfileImporter.h"
#import "TLBrowserPreferences.h"
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
static NSString *resultPath, *baseURL; static BOOL verifying, sessionEnded;
static void Check(BOOL condition, NSString *message) {
  if(!condition) { [[@"FAIL: " stringByAppendingString:message] writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; exit(1); }
}
@interface TLImportApplication : NSApplication
@end
@implementation TLImportApplication
@end
static void EvaluateImportedData(WKWebView *view) {
  TLTestEvaluate(view, @"JSON.stringify({token:localStorage.getItem('token'),unicode:localStorage.getItem('unicode'),proto:localStorage.getItem('__proto__'),cookies:document.cookie})", ^(NSString *json) {
    NSDictionary *data=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    Check([data[@"token"] isEqual:@"imported"],[@"WebKit reads imported localStorage: " stringByAppendingString:json ?: @"nil"]);
    Check([data[@"unicode"] isEqual:@"東京 ✓"],@"WebKit reads UTF-16 localStorage");
    Check([data[@"proto"] isEqual:@"prototype value"],@"Imported __proto__ localStorage key remains ordinary data");
    Check([data[@"cookies"] containsString:@"visible=imported"],@"WebKit reads imported cookies");
    Check([data[@"cookies"] containsString:@"session=restored"] != sessionEnded,@"Session cookies survive the required restart, then expire normally");
    Check(![data[@"cookies"] containsString:@"private"],@"HTTP-only imported cookies stay hidden from JavaScript");
    [@"PASS" writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
  });
}
@interface TLImportDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property BOOL evaluated;
@end
@implementation TLImportDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSURL *profile=TLBrowserPreferences.profileURL;
  Check([profile.path hasPrefix:@"/tmp/talaria-import-webkit-"],@"Use disposable profile only");
  if(!verifying) {
    NSString *origin=baseURL;
    NSMutableData *key=[[[NSString stringWithFormat:@"_%@",origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [key appendBytes:"\0\1token" length:7];
    NSMutableData *unicodeKey=[[[NSString stringWithFormat:@"_%@",origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [unicodeKey appendBytes:"\0\1unicode" length:9];
    NSMutableData *unicodeValue=[NSMutableData dataWithBytes:"\0" length:1]; [unicodeValue appendData:[@"東京 ✓" dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    NSMutableData *protoKey=[[[NSString stringWithFormat:@"_%@",origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [protoKey appendBytes:"\0\1__proto__" length:11];
    NSMutableData *protoValue=[NSMutableData dataWithBytes:"\1" length:1]; [protoValue appendData:[@"prototype value" dataUsingEncoding:NSUTF8StringEncoding]];
    NSError *error=nil;
    Check([TLBrowserProfileImporter stageLocalStorage:@{key:[NSData dataWithBytes:"\1imported" length:9],unicodeKey:unicodeValue,protoKey:protoValue} sessionCookies:@[@{@"domain":@"127.0.0.1",@"name":@"session",@"value":@"restored",@"path":@"/",@"expires":@0,@"persistent":@NO,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1}] profileURL:profile error:&error],@"Stage fixture before browser startup");
  }
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,450) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  [TLBrowserPreferences.sharedPreferences prepareInWindow:self.window completion:^(NSError *error) {
    Check(!error,@"Start embedded browser");
    if(verifying) { [self load]; return; }
    // Stage another one-shot session replay, as an import into an already running
    // browser does, to verify the required next restart as well.
    Check([TLBrowserProfileImporter stageLocalStorage:@{} sessionCookies:@[@{@"domain":@"127.0.0.1",@"name":@"session",@"value":@"restored",@"path":@"/",@"expires":@0,@"persistent":@NO,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1}] profileURL:profile error:nil],@"Keep sessions for one required restart");
    NSDictionary *cookie=@{@"domain":@"127.0.0.1",@"name":@"visible",@"value":@"imported",@"path":@"/",@"expires":@4102444800,@"persistent":@YES,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1};
    NSMutableDictionary *privateCookie=cookie.mutableCopy; privateCookie[@"name"]=@"private"; privateCookie[@"httpOnly"]=@YES;
    [TLWebKitBrowserController.sharedController importCookies:@[cookie,privateCookie] completion:^(NSUInteger imported,NSUInteger failed) {
      Check(imported==2 && failed==0,@"WebKit accepts and flushes imported cookies"); [self load];
    }];
  }];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"Browser import integration timed out"); });
}
- (void)load {
  self.session=[TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:[baseURL stringByAppendingString:@"/fixture"]] inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:^(BOOL back,BOOL forward,BOOL loading) {
    if(loading || !self.session.documentGeneration || self.evaluated) return; self.evaluated=YES;
    Check(![[TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:TLBrowserPreferences.profileURL error:nil] objectForKey:baseURL], @"Consume localStorage only after the destination origin accepts it");
    EvaluateImportedData(self.session.webView);
  }];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [TLWebKitBrowserController.sharedController shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  if(argc!=5) return 2; setenv("TL_WEBKIT_PROFILE_DIR",argv[1],1);
  baseURL=[NSString stringWithUTF8String:argv[2]]; resultPath=[NSString stringWithUTF8String:argv[3]]; verifying=strcmp(argv[4],"import")!=0; sessionEnded=strcmp(argv[4],"session-end")==0;
  TLImportApplication *app=[TLImportApplication sharedApplication]; TLImportDelegate *delegate=[TLImportDelegate new]; app.delegate=delegate; [app run];
} return 0; }
