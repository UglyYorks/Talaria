#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>
#import "design_system/TLProgressiveBlurView.h"
static void Check(BOOL value, NSString *message) {
  NSLog(@"%@: %@",value ? @"PASS" : @"FAIL",message); if(!value)exit(1);
}
@interface TLBackdropTest : NSObject <NSApplicationDelegate,WKNavigationDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property TLProgressiveBlurView *blur;
@end
@implementation TLBackdropTest
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,800,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.contentView.wantsLayer=YES;
  self.web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
  self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  if(@available(macOS 26.0,*))self.web.obscuredContentInsets=NSEdgeInsetsMake(0,0,140,0);
  [self.window.contentView addSubview:self.web];
  self.blur=[[TLProgressiveBlurView alloc] initWithFrame:NSMakeRect(0,0,800,140)];
  self.blur.autoresizingMask=NSViewWidthSizable|NSViewMaxYMargin;
  self.blur.palette=[TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [self.window.contentView addSubview:self.blur];
  self.web.navigationDelegate=self;
  [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  [self.web loadHTMLString:@"<!doctype html><style>html,body{margin:0;background:#000}article{height:2400px;background:repeating-linear-gradient(90deg,#000 0 4px,#fff 4px 8px);content-visibility:auto}button{position:fixed;bottom:30px;left:30px}</style><article></article><button>Page control</button>" baseURL:nil];
}
- (void)eval:(NSString *)script then:(void (^)(id))completion {
  [self.web evaluateJavaScript:script completionHandler:^(id value,NSError *error){Check(!error,@"fixture JavaScript succeeds");if(completion)completion(value);}];
}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
  NSString *source=[NSString stringWithContentsOfFile:NSProcessInfo.processInfo.arguments[1] encoding:NSUTF8StringEncoding error:nil];
  [self eval:[NSString stringWithFormat:@"(%@)();__talariaDocumentFooter.configure({enabled:false,nativeFill:true,height:140,width:800,fallbackColor:'rgb(0,0,0)'});innerHeight",source] then:^(id height){
    Check([height doubleValue]==460,@"extended area still reserves space below the main page");
    Check([self.blur hitTest:NSMakePoint(20,20)]==nil,@"native blur does not intercept page input");
    for(NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
      self.blur.palette=[TLThemePalette paletteForPreference:theme.integerValue];
      [self.blur layoutSubtreeIfNeeded];
      Check(self.blur.backgroundFilters.count==1 && CGColorEqualToColor(self.blur.layer.backgroundColor,TLCGColor(self.blur.palette.chatInputBackdrop)),@"footer combines native blur with the themed translucent chat backdrop");
    }
    [self checkScroll:0];
  }];
}
- (void)checkDelayedRedraw:(NSUInteger)tick {
  if(tick==12) {
    if(getenv("TL_BLUR_INSPECT")) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:20]];
    NSLog(@"BrowserBackdropTests passed");[NSApp terminate:nil];return;
  }
  self.blur.hidden=YES; self.blur.hidden=NO;
  self.blur.needsLayout=YES; self.blur.needsDisplay=YES;
  [self.blur layoutSubtreeIfNeeded];[self.window displayIfNeeded];
  Check(self.blur.backgroundFilters.count==1 && self.blur.layer.backgroundFilters.count==1,@"AppKit retains Core Image rendering across delayed redraws");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self checkDelayedRedraw:tick+1];});
}
- (void)checkScroll:(NSUInteger)index {
  NSArray *positions=@[@0,@1850,@100000,@100000,@1200,@0];
  if(index==positions.count) {
    [self checkDelayedRedraw:0];return;
  }
  [self eval:[NSString stringWithFormat:@"scrollTo(0,%@);__talariaDocumentFooter.refresh();JSON.stringify({end:document.scrollingElement.scrollHeight,blur:!!document.querySelector('[data-talaria-bottom-blur]')})",positions[index]] then:^(id value){
    NSDictionary *state=[NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    Check([state[@"end"] doubleValue]==2400 && ![state[@"blur"] boolValue],@"page has no moving blur element or extra scroll overflow");
    Check(NSEqualRects(self.blur.frame,NSMakeRect(0,0,800,140)),@"blur stays attached to window bottom across scrolling and the page end");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self checkScroll:index+1];});
  }];
}
@end
int main(int argc,const char *argv[]) {
  @autoreleasepool {
    NSApplication *app=NSApplication.sharedApplication;
    TLBackdropTest *delegate=[TLBackdropTest new];app.delegate=delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];[app run];
  }
}
