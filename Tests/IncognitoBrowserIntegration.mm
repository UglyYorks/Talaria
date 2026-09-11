// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
@interface TLProbeApplication : NSApplication
@end
@implementation TLProbeApplication
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
@interface TLPrivateBrowserProbe : NSObject <NSApplicationDelegate>
@property NSMutableArray<NSWindow *> *windows;
@property NSMutableArray<TLWebKitBrowserSession *> *sessions;
@property NSURL *URL;
@end
@implementation TLPrivateBrowserProbe
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  Check([NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"] hasPrefix:@"/tmp/talaria-native-browser-test-"], @"disposable browser profile");
  self.windows = [NSMutableArray array]; self.sessions = [NSMutableArray array];
  self.URL = [NSURL URLWithString:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"]];
  for (NSUInteger i = 0; i < 3; i++) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [self.windows addObject:window];
    if (i > 0) [TLWebKitBrowserController.sharedController markWindowIncognito:window];
    [self addSessionInWindow:window];
  }
  [self addSessionInWindow:self.windows[1]];
  [self waitForPages:0];
}
- (void)addSessionInWindow:(NSWindow *)window {
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
  [window.contentView addSubview:view];
  TLWebKitBrowserSession *session = [TLWebKitBrowserController.sharedController loadURL:self.URL inView:view fromWindow:window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  Check(session != nil, @"browser session created");
  [self.sessions addObject:session];
}
- (void)waitForPages:(NSUInteger)attempt {
  BOOL ready = YES;
  for (TLWebKitBrowserSession *session in self.sessions) {
    if (!session.webView || session.webView.loading || ![session.webView.URL.host isEqual:@"127.0.0.1"]) ready = NO;
  }
  if (!ready) {
    Check(attempt < 300, @"page load deadline");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self waitForPages:attempt+1]; });
    return;
  }
  WKWebsiteDataStore *normal = self.sessions[0].webView.configuration.websiteDataStore;
  WKWebsiteDataStore *private1 = self.sessions[1].webView.configuration.websiteDataStore;
  WKWebsiteDataStore *private2 = self.sessions[2].webView.configuration.websiteDataStore;
  WKWebsiteDataStore *sibling = self.sessions[3].webView.configuration.websiteDataStore;
  Check(normal.persistent && !private1.persistent, @"normal disk cache and private in-memory cache");
  Check(private1 != normal && private1 != private2, @"separate normal and private windows");
  Check(private1 == sibling, @"tabs within one private window share their ephemeral context");
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
  for (TLWebKitBrowserSession *session in self.sessions) [TLWebKitBrowserController.sharedController closeSession:session];
  for (NSWindow *window in self.windows) [TLWebKitBrowserController.sharedController forgetIncognitoWindow:window];
  [NSApp terminate:nil];
}
- (void)evaluate:(NSUInteger)index script:(const char *)script completion:(void (^)(id))completion {
  TLTestEvaluate(self.sessions[index].webView, [NSString stringWithUTF8String:script], completion);
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [TLWebKitBrowserController.sharedController shutdown]; fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); }
@end
int main(int argc,char **argv) { @autoreleasepool {
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLPrivateBrowserProbe *delegate; delegate = [TLPrivateBrowserProbe new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
  [app finishLaunching]; [app run]; return 0;
}}
