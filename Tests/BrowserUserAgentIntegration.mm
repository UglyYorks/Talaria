// Signed desktop probe: actual WebKit requests and page-visible browser identity.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"

static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr,"%s: %s\n",condition ? "PASS" : "FAIL",message.UTF8String);
  fflush(condition ? stdout : stderr);if(!condition)exit(1);
}
static void Later(double seconds, dispatch_block_t action) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}

@interface TLUserAgentProbe : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property NSWindow *window;
@property WKWebView *baseline;
@property TLWebKitBrowserSession *session;
@property NSString *baseURL;
@property NSString *expected;
@property BOOL privateMode;
@end
@implementation TLUserAgentProbe
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.baseURL=NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  self.expected=NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_EXPECTED_UA"];
  Check([self.baseURL hasPrefix:@"http://127.0.0.1:"] && self.expected.length,@"local fixture and expected Safari identity");
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(70,70,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed=NO;
  TLTestActivateWindow(self.window,^{
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    configuration.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    self.baseline=[[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:configuration];
    self.baseline.navigationDelegate=self;self.window.contentView=self.baseline;
    [self.baseline loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/baseline"]]]];
  });
  Later(50,^{Check(NO,@"user-agent probe deadline");});
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  TLTestEvaluate(webView,@"navigator.userAgent",^(NSString *value){
    fprintf(stdout,"DEFAULT WEBKIT UA: %s\n",value.UTF8String);
    self.window.contentView=[[NSView alloc] initWithFrame:self.baseline.bounds];self.baseline=nil;
    [self startSession];
  });
}
- (void)startSession {
  TLWebKitBrowserController *controller=TLWebKitBrowserController.sharedController;
  if(self.privateMode)[controller markWindowIncognito:self.window];
  NSString *path=self.privateMode ? @"/private" : @"/redirect";
  self.session=[controller loadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:path]] inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  Check(self.session!=nil,@"production browser session starts");
  Check(self.session.webView.configuration.websiteDataStore.isPersistent!=self.privateMode,@"requested storage mode is preserved");
  [self waitForFixture:0 popup:NO];
}
- (void)waitForFixture:(NSUInteger)attempt popup:(BOOL)popup {
  if(attempt>=250)Check(NO,@"browser identity fixture becomes ready");
  if(self.session.webView.loading || !self.session.documentGeneration) {
    Later(.05,^{[self waitForFixture:attempt+1 popup:popup];});return;
  }
  NSString *script=popup ? @"window.uaProbe?.popupUA ? uaProbe : null" : @"window.uaProbe?.ready ? uaProbe : null";
  TLTestEvaluate(self.session.webView,script,^(NSDictionary *probe){
    if(![probe isKindOfClass:NSDictionary.class]){Later(.05,^{[self waitForFixture:attempt+1 popup:popup];});return;}
    if(popup){
      Check([probe[@"blankPopupUA"] isEqual:self.expected],@"initial about:blank popup identifies as installed Safari");
      Check([probe[@"popupUA"] isEqual:self.expected],@"navigated popup identifies as installed Safari");
      TLTestEvaluate(self.session.webView,@"testPopup.close();true",^(id value){[self finishSession];});return;
    }
    for(NSString *key in @[@"initialUA",@"currentUA",@"frameUA",@"fetchUA",@"workerUA"])
      Check([probe[key] isEqual:self.expected],[NSString stringWithFormat:@"%@ %@ identifies as installed Safari",self.privateMode ? @"private" : @"regular",key]);
    Check([probe[@"appVersion"] isEqual:[self.expected substringFromIndex:@"Mozilla/".length]],@"navigator.appVersion agrees with the browser identity");
    Check(![probe[@"frameOrigin"] isEqual:probe[@"origin"]],@"frame identity was checked across origins");
    fprintf(stdout,"TALARIA UA: %s\n",[probe[@"currentUA"] UTF8String]);
    TLTestActivateWindow(self.window,^{[self clickPopupButton];});
  });
}
- (void)clickPopupButton {
  WKWebView *view=self.session.webView;
  NSPoint point=[view convertPoint:NSMakePoint(70,view.isFlipped ? 35 : NSHeight(view.bounds)-35) toView:nil];
  NSView *target=[self.window.contentView hitTest:[self.window.contentView.superview convertPoint:point fromView:nil]];
  for(NSNumber *type in @[@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]) {
    NSEvent *event=[NSEvent mouseEventWithType:(NSEventType)type.integerValue location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    if(event.type==NSEventTypeLeftMouseDown)[target mouseDown:event];else [target mouseUp:event];
  }
  [self waitForFixture:0 popup:YES];
}
- (void)finishSession {
  [TLWebKitBrowserController.sharedController closeSession:self.session];
  if(!self.privateMode){self.privateMode=YES;[self startSession];return;}
  [TLWebKitBrowserController.sharedController forgetIncognitoWindow:self.window];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
  [TLWebKitBrowserController.sharedController shutdown];printf("TALARIA_BROWSER_TEST_COMPLETE\n");fflush(stdout);
}
@end
int main(int argc,char **argv){@autoreleasepool{
  NSApplication *application=NSApplication.sharedApplication;
  TLUserAgentProbe *delegate=[TLUserAgentProbe new];application.delegate=delegate;[application run];
}return 0;}
