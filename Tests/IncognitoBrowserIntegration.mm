// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_request_context.h"
#include "include/cef_devtools_message_observer.h"
@interface TLProbeApplication : NSApplication <CefAppProtocol>
@property BOOL handlingSendEvent;
@end
@implementation TLProbeApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
@end
@interface TLChromiumBrowserController (Integration)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (void)checkBackgroundBrowsers;
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
class TLProbeEvaluation : public CefDevToolsMessageObserver {
 public:
 explicit TLProbeEvaluation(void (^completion)(id)) : completion_([completion copy]) {}
 void Start(CefRefPtr<CefBrowser> browser, const char *expression) {
   registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
   auto parameters = CefDictionaryValue::Create(); parameters->SetString("expression",expression); parameters->SetBool("returnByValue",true);
   identifier_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",parameters);
 }
 void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,int identifier,bool success,const void *result,size_t size) override {
   if (identifier != identifier_) return;
   CefRefPtr<TLProbeEvaluation> keepAlive = this;
   NSDictionary *response = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
   auto completion = completion_; completion_ = nil; registration_ = nullptr;
   Check(success && !response[@"exceptionDetails"],@"read browser fixture state");
   completion(response[@"result"][@"value"]);
 }
 private:
 int identifier_ = 0;
 CefRefPtr<CefRegistration> registration_;
 void (^completion_)(id);
 IMPLEMENT_REFCOUNTING(TLProbeEvaluation);
};
@interface TLPrivateBrowserProbe : NSObject <NSApplicationDelegate>
@property NSMutableArray<NSWindow *> *windows;
@property NSMutableArray<TLChromiumBrowserSession *> *sessions;
@property NSURL *URL;
@end
@implementation TLPrivateBrowserProbe
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  Check([NSProcessInfo.processInfo.environment[@"TL_CHROMIUM_PROFILE_DIR"] hasPrefix:@"/tmp/talaria-native-browser-test-"], @"disposable browser profile");
  self.windows = [NSMutableArray array]; self.sessions = [NSMutableArray array];
  self.URL = [NSURL URLWithString:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"]];
  for (NSUInteger i = 0; i < 3; i++) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [self.windows addObject:window];
    if (i > 0) [TLChromiumBrowserController.sharedController markWindowIncognito:window];
    [self addSessionInWindow:window];
  }
  [self addSessionInWindow:self.windows[1]];
  [self waitForPages:0];
}
- (void)addSessionInWindow:(NSWindow *)window {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
  [window.contentView addSubview:view];
  TLChromiumBrowserSession *session = [TLChromiumBrowserController.sharedController loadURL:self.URL inView:view fromWindow:window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  Check(session != nil, @"browser session created");
  [self.sessions addObject:session];
}
- (void)waitForPages:(NSUInteger)attempt {
  BOOL ready = YES;
  for (TLChromiumBrowserSession *session in self.sessions) {
    auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)session.browserIdentifier];
    if (!browser || browser->IsLoading() || browser->GetMainFrame()->GetURL().ToString().find("127.0.0.1") == std::string::npos) ready = NO;
  }
  if (!ready) {
    Check(attempt < 300, @"page load deadline");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self waitForPages:attempt+1]; });
    return;
  }
  auto normal = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.sessions[0].browserIdentifier]->GetHost()->GetRequestContext();
  auto private1 = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.sessions[1].browserIdentifier]->GetHost()->GetRequestContext();
  auto private2 = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.sessions[2].browserIdentifier]->GetHost()->GetRequestContext();
  auto sibling = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.sessions[3].browserIdentifier]->GetHost()->GetRequestContext();
  Check(!normal->GetCachePath().empty() && private1->GetCachePath().empty(), @"normal disk cache and private in-memory cache");
  Check(!private1->IsSharingWith(normal) && !private1->IsSharingWith(private2), @"separate normal and private windows");
  Check(private1->IsSame(sibling), @"tabs within one private window share their ephemeral context");
  [self evaluate:1 script:"document.cookie='incognito=TALARIA_INCOGNITO_MARKER';localStorage.setItem('incognito','TALARIA_INCOGNITO_MARKER');true" completion:^(id value) {
    [self evaluate:0 script:"!document.cookie.includes('incognito=') && localStorage.getItem('incognito')===null" completion:^(id value) {
      Check([value boolValue], @"normal window cannot see private cookies or localStorage");
      [self evaluate:2 script:"!document.cookie.includes('incognito=') && localStorage.getItem('incognito')===null" completion:^(id value) {
        Check([value boolValue], @"another private window cannot see private cookies or localStorage");
        [self evaluate:3 script:"document.cookie.includes('incognito=') && localStorage.getItem('incognito')!==null" completion:^(id value) {
          Check([value boolValue], @"sibling private tab retains live cookies and localStorage");
          [self performSelector:@selector(finish) withObject:nil afterDelay:0.1];
        }];
      }];
    }];
  }];
}
- (void)finish {
  for (TLChromiumBrowserSession *session in self.sessions) [TLChromiumBrowserController.sharedController closeSession:session];
  for (NSWindow *window in self.windows) [TLChromiumBrowserController.sharedController forgetIncognitoWindow:window];
  [NSApp terminate:nil];
}
- (void)evaluate:(NSUInteger)index script:(const char *)script completion:(void (^)(id))completion {
  auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.sessions[index].browserIdentifier];
  CefRefPtr<TLProbeEvaluation> evaluation = new TLProbeEvaluation(completion);
  evaluation->Start(browser,script);
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLChromiumBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [TLChromiumBrowserController.sharedController shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  TLChromiumBrowserControllerConfigureMainArgs(argc,argv);
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLPrivateBrowserProbe *delegate; delegate = [TLPrivateBrowserProbe new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
  [app finishLaunching]; [app run]; return 0;
}}
