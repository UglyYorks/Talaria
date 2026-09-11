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
- (NSArray *)paths { return @[@"/fixed",@"/closed",@"/pointer",@"/frame",@"/clear",@"/gradient",@"/read",@"/find",@"/footer-color",@"/footer"]; }
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
  } else if ([path isEqual:@"/footer-color"]) {
    [self.bridge configureDocumentFooter:@{@"enabled":@YES,@"height":@70,@"width":@1000} completion:^(BOOL applied) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        [self.bridge sampleFooterColorAllowingCapture:YES completion:^(NSDictionary *sample) {
          [self.webView evaluateJavaScript:@"({scroll:scrollY,height:document.scrollingElement.scrollHeight})" completionHandler:^(id state, NSError *error) {
            NSMutableDictionary *result=[@{@"sample":sample[@"rgb"] ?: @[],@"prepared":sample[@"extensionRGB"] ?: @[],@"state":state ?: @{},@"applied":@(applied)} mutableCopy];
            [self checkFillVisibility:0 result:result colors:[NSMutableArray array]];
          }];
        }];
      });
    }];
  } else if ([path isEqual:@"/footer"]) {
    [self checkFooterStep:0 results:[NSMutableArray array]];
  } else [self.bridge probeOverlayRect:NSMakeRect(100,20,800,48) viewportSize:NSMakeSize(1000,700) quick:YES completion:^(NSDictionary *result) { [self record:result]; }];
}
- (void)checkFillVisibility:(NSUInteger)step result:(NSMutableDictionary *)result colors:(NSMutableArray *)colors {
  if(step==4) {
    [self.bridge resetForNavigation];
    NSColor *reset=[self.webView.underPageBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    result[@"resetColor"]=@[@((int)round(reset.redComponent*255)),@((int)round(reset.greenComponent*255)),@((int)round(reset.blueComponent*255))];
    result[@"fillColors"]=colors;
    [self record:result];return;
  }
  NSString *script=step%2 ? @"scrollTo(0,document.scrollingElement.scrollHeight)" : @"scrollTo(0,0)";
  [self.webView evaluateJavaScript:script completionHandler:^(id value,NSError *error){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
      NSColor *color=[self.webView.underPageBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      [colors addObject:@[@((int)round(color.redComponent*255)),@((int)round(color.greenComponent*255)),@((int)round(color.blueComponent*255))]];
      [self checkFillVisibility:step+1 result:result colors:colors];
    });
  }];
}
- (void)checkFooterStep:(NSUInteger)step results:(NSMutableArray *)results {
  NSArray *heights = @[@70, @110, @0, @70];
  if (step == heights.count) {
    [self.bridge stop];
    CGFloat stoppedInset = 0;
    if (@available(macOS 26.0, *)) stoppedInset = self.webView.obscuredContentInsets.bottom;
    [self record:@{@"steps":results, @"stoppedInset":@(stoppedInset)}];
    return;
  }
  CGFloat height = [heights[step] doubleValue];
  [self.bridge configureDocumentFooter:@{@"enabled":@(height > 0), @"height":@(height), @"width":@1000, @"fallbackColor":@"rgb(10,20,30)"} completion:^(BOOL applied) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
      NSString *script = @"let fixed=document.getElementById('footer-fixed'); if(!fixed){fixed=document.createElement('div');fixed.id='footer-fixed';fixed.style='position:fixed;bottom:0;height:20px;width:20px';document.body.append(fixed);} return {height:document.scrollingElement.scrollHeight,viewport:innerHeight,fixedBottom:fixed.getBoundingClientRect().bottom,spacer:!!document.querySelector('[data-talaria-document-footer]')};";
      [self.webView callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:self.bridge.contentWorld completionHandler:^(id value, NSError *error) {
        CGFloat inset = 0; BOOL native = NO;
        if (@available(macOS 26.0, *)) { inset = self.webView.obscuredContentInsets.bottom; native = YES; }
        [results addObject:@{@"applied":@(applied), @"native":@(native), @"inset":@(inset), @"viewHeight":@(NSHeight(self.webView.bounds)), @"state":value ?: @{}}];
        [self checkFooterStep:step + 1 results:results];
      }];
    });
  }];
}

@end
int main(void) {
  @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication;
    TLPageBridgeTestDelegate *delegate = [TLPageBridgeTestDelegate new]; app.delegate = delegate; [app run];
  }
  return 0;
}
