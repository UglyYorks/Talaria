#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "WebKitPageBridge.h"

@interface TLPageBridgeTestDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) TLWebKitPageBridge *bridge;
@property(nonatomic, strong) NSMutableArray *results;
@property(nonatomic) NSUInteger index;
@end
@implementation TLPageBridgeTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.results = [NSMutableArray array];
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,700) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed = NO;
  WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
  configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
  self.webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0,0,1000,700) configuration:configuration];
  self.window.contentView = self.webView;
  self.webView.navigationDelegate = self;
  self.bridge = [[TLWebKitPageBridge alloc] initWithWebView:self.webView];
  [self.bridge install];
  [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  [self next];
}
- (NSArray *)paths { return @[@"/fixed",@"/closed",@"/pointer",@"/frame",@"/clear",@"/gradient",@"/read",@"/find",@"/footer"]; }
- (void)next {
  if (self.index == self.paths.count) {
    [self.bridge stop];
    [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.arguments[2] atomically:YES];
    [NSApp terminate:nil]; return;
  }
  NSURL *URL = [NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:self.paths[self.index]]];
  [self.webView loadRequest:[NSURLRequest requestWithURL:URL]];
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation { [self.bridge resetForNavigation]; }
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation { [self.bridge install]; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  [self.bridge install];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [self check]; });
}
- (void)record:(NSDictionary *)value {
  [self.results addObject:@{@"path":self.paths[self.index], @"result":value ?: @{}}]; self.index++; [self next];
}
- (void)check {
  NSString *path = self.paths[self.index];
  if ([path isEqual:@"/read"]) {
    [self.bridge readPageExpectedURL:self.webView.URL completion:^(NSDictionary *page, NSError *error) {
      [self record:page ?: @{@"error":error.localizedDescription ?: @"unknown"}];
    }];
  } else if ([path isEqual:@"/find"]) {
    [self.bridge findText:@"needle" forward:YES findNext:NO completion:^(NSInteger count, NSInteger active, BOOL final) {
      NSMutableArray *values = [NSMutableArray arrayWithObject:@[@(count),@(active)]];
      [self.bridge findText:@"needle" forward:YES findNext:YES completion:^(NSInteger nextCount, NSInteger nextActive, BOOL nextFinal) {
        [values addObject:@[@(nextCount),@(nextActive)]];
        [self.bridge findText:@"needle" forward:NO findNext:YES completion:^(NSInteger backCount, NSInteger backActive, BOOL backFinal) {
          [values addObject:@[@(backCount),@(backActive)]]; [self.bridge stopFinding];
          [self record:@{@"matches":values,@"finding":@(self.bridge.finding)}];
        }];
      }];
    }];
  } else if ([path isEqual:@"/gradient"]) {
    [self.bridge sampleFooterColorAllowingCapture:YES completion:^(NSDictionary *sample) { [self record:sample]; }];
  } else if ([path isEqual:@"/footer"]) {
    [self.bridge configureDocumentFooter:@{@"enabled":@YES,@"height":@70,@"width":@1000,@"color":@"rgb(10,20,30)"} completion:^(BOOL applied) {
      [self.webView evaluateJavaScript:@"({ready:!!globalThis.__talariaDocumentFooter,height:document.scrollingElement.scrollHeight})" inFrame:nil inContentWorld:self.bridge.contentWorld completionHandler:^(id value, NSError *error) {
        [self record:@{@"applied":@(applied),@"state":value ?: @{}}];
      }];
    }];
  } else [self.bridge probeOverlayRect:NSMakeRect(100,20,800,48) viewportSize:NSMakeSize(1000,700) quick:YES completion:^(NSDictionary *result) { [self record:result]; }];
}
@end
int main(void) {
  @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication;
    TLPageBridgeTestDelegate *delegate = [TLPageBridgeTestDelegate new]; app.delegate = delegate; [app run];
  }
  return 0;
}
