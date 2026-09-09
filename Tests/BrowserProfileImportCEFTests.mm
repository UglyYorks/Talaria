// Real Chromium consumer test, launched as a desktop app against disposable data.
#import <AppKit/AppKit.h>
#import "TLBrowserProfileImporter.h"
#import "TLBrowserPreferences.h"
#import "ChromiumBrowserController.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_devtools_message_observer.h"
static NSString *resultPath, *baseURL; static BOOL verifying, sessionEnded;
static void Check(BOOL condition, NSString *message) {
  if(!condition) { [[@"FAIL: " stringByAppendingString:message] writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; exit(1); }
}
@interface TLImportApplication : NSApplication <CefAppProtocol>
@property BOOL handlingSendEvent;
@end
@implementation TLImportApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
@end
@interface TLChromiumBrowserController (ImportProbe)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
@end
class Evaluation : public CefDevToolsMessageObserver {
 public:
  void Start(CefRefPtr<CefBrowser> browser) {
    registration_=browser->GetHost()->AddDevToolsMessageObserver(this);
    auto parameters=CefDictionaryValue::Create(); parameters->SetString("expression","JSON.stringify({token:localStorage.getItem('token'),unicode:localStorage.getItem('unicode'),cookies:document.cookie})"); parameters->SetBool("returnByValue",true);
    identifier_=browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",parameters);
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int identifier,bool success,const void *result,size_t size) override {
    if(identifier!=identifier_) return; CefRefPtr<Evaluation> keep=this;
    NSDictionary *response=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    Check(success && !response[@"exceptionDetails"],@"Evaluate imported data");
    NSString *json=response[@"result"][@"value"];
    NSDictionary *data=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    Check([data[@"token"] isEqual:@"imported"],[@"Chromium reads imported localStorage: " stringByAppendingString:json ?: @"nil"]);
    Check([data[@"unicode"] isEqual:@"東京 ✓"],@"Chromium reads UTF-16 localStorage");
    Check([data[@"cookies"] containsString:@"visible=imported"],@"Chromium reads imported cookies");
    Check([data[@"cookies"] containsString:@"session=restored"] != sessionEnded,@"Session cookies survive the required restart, then expire normally");
    Check(![data[@"cookies"] containsString:@"private"],@"HTTP-only imported cookies stay hidden from JavaScript");
    registration_=nullptr;
    [@"PASS" writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
  }
 private:
  int identifier_=0; CefRefPtr<CefRegistration> registration_;
  IMPLEMENT_REFCOUNTING(Evaluation);
};
@interface TLImportDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLChromiumBrowserSession *session;
@property BOOL evaluated;
@end
@implementation TLImportDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSURL *profile=TLBrowserPreferences.profileURL;
  Check([profile.path hasPrefix:@"/tmp/talaria-import-cef-"],@"Use disposable profile only");
  if(!verifying) {
    NSString *origin=baseURL;
    NSMutableData *key=[[[NSString stringWithFormat:@"_%@",origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [key appendBytes:"\0\1token" length:7];
    NSMutableData *unicodeKey=[[[NSString stringWithFormat:@"_%@",origin] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [unicodeKey appendBytes:"\0\1unicode" length:9];
    NSMutableData *unicodeValue=[NSMutableData dataWithBytes:"\0" length:1]; [unicodeValue appendData:[@"東京 ✓" dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    NSError *error=nil;
    Check([TLBrowserProfileImporter stageLocalStorage:@{key:[NSData dataWithBytes:"\1imported" length:9],unicodeKey:unicodeValue} sessionCookies:@[@{@"domain":@"127.0.0.1",@"name":@"session",@"value":@"restored",@"path":@"/",@"expires":@0,@"persistent":@NO,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1}] profileURL:profile error:&error],@"Stage fixture before browser startup");
  }
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,450) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  [TLBrowserPreferences.sharedPreferences prepareInWindow:self.window completion:^(NSError *error) {
    Check(!error,@"Start embedded browser");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[profile URLByAppendingPathComponent:@"TalariaPendingLocalStorage.plist"].path],@"Consume pending localStorage");
    if(verifying) { [self load]; return; }
    // Stage another one-shot session replay, as an import into an already running
    // browser does, to verify the required next restart as well.
    Check([TLBrowserProfileImporter stageLocalStorage:@{} sessionCookies:@[@{@"domain":@"127.0.0.1",@"name":@"session",@"value":@"restored",@"path":@"/",@"expires":@0,@"persistent":@NO,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1}] profileURL:profile error:nil],@"Keep sessions for one required restart");
    NSDictionary *cookie=@{@"domain":@"127.0.0.1",@"name":@"visible",@"value":@"imported",@"path":@"/",@"expires":@4102444800,@"persistent":@YES,@"secure":@NO,@"httpOnly":@NO,@"sameSite":@1};
    NSMutableDictionary *privateCookie=cookie.mutableCopy; privateCookie[@"name"]=@"private"; privateCookie[@"httpOnly"]=@YES;
    [TLChromiumBrowserController.sharedController importCookies:@[cookie,privateCookie] completion:^(NSUInteger imported,NSUInteger failed) {
      Check(imported==2 && failed==0,@"CEF accepts and flushes imported cookies"); [self load];
    }];
  }];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"Browser import integration timed out"); });
}
- (void)load {
  self.session=[TLChromiumBrowserController.sharedController loadURL:[NSURL URLWithString:[baseURL stringByAppendingString:@"/fixture"]] inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:^(BOOL back,BOOL forward,BOOL loading) {
    if(loading || !self.session.documentGeneration || self.evaluated) return; self.evaluated=YES;
    auto browser=[TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
    CefRefPtr<Evaluation> evaluation=new Evaluation(); evaluation->Start(browser);
  }];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [TLChromiumBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [TLChromiumBrowserController.sharedController shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  if(argc!=5) return 2; setenv("TL_CHROMIUM_PROFILE_DIR",argv[1],1);
  baseURL=[NSString stringWithUTF8String:argv[2]]; resultPath=[NSString stringWithUTF8String:argv[3]]; verifying=strcmp(argv[4],"import")!=0; sessionEnded=strcmp(argv[4],"session-end")==0;
  TLChromiumBrowserControllerConfigureMainArgs(argc,argv);
  TLImportApplication *app=[TLImportApplication sharedApplication]; TLImportDelegate *delegate=[TLImportDelegate new]; app.delegate=delegate; [app run];
} return 0; }
