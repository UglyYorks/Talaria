// Run with python3 Tests/run-browser-overlay-webkit.py. Uses an isolated test profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
#import "TLBrowserHeightTransition.h"
#import <QuartzCore/QuartzCore.h>
@interface TLBrowserTabController (OverlayResizeTest)
- (void)toggleBrowserHeightMode:(id)sender;
@end
static NSDictionary *TLResizeViewTree(NSView *view, NSUInteger depth) {
  NSMutableArray *children=[NSMutableArray array];
  if(depth) for(NSView *child in view.subviews) [children addObject:TLResizeViewTree(child,depth-1)];
  return @{@"class":NSStringFromClass(view.class),@"frame":NSStringFromRect(view.frame),@"bounds":NSStringFromRect(view.bounds),@"layer":NSStringFromRect(view.layer.frame),@"children":children};
}
@interface TLOverlayTestApplication : NSApplication
@end
@implementation TLOverlayTestApplication
@end
@interface TLOverlayTestBrowser : TLWebKitBrowserController
@property(nonatomic,strong) NSDictionary *lastProbe;
@property(nonatomic,strong) NSMutableArray *trace;
@end
@implementation TLOverlayTestBrowser
- (void)probeOverlayInSession:(TLWebKitBrowserSession *)session overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion {
  NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
  [super probeOverlayInSession:session overlayRect:rect viewportSize:viewport quick:quick completion:^(NSDictionary *result) {
    self.lastProbe=@{@"result":result,@"rect":NSStringFromRect(rect),@"viewport":NSStringFromSize(viewport)};
    if (self.trace.count < 200) [self.trace addObject:@{@"started":@(started),@"completed":@(NSProcessInfo.processInfo.systemUptime),@"quick":@(quick),@"result":result}];
    completion(result);
  }];
}
@end
@interface TLOverlayTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLOverlayTestBrowser *browser;
@property(nonatomic,strong) TLWebKitBrowserSession *session;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic) NSInteger index;
@property(nonatomic) BOOL scheduled;
@property(nonatomic,strong) TLBrowserTabController *tab;
@property(nonatomic) NSInteger latencyIndex;
@property(nonatomic) NSTimeInterval shownAt, detectedAt;
@property(nonatomic,strong) NSMutableArray *resizeCycles;
@end
@implementation TLOverlayTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  self.results=[NSMutableArray array];
  NSLog(@"Overlay integration started: %@",args);
  [[NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.browser=[TLOverlayTestBrowser new];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
  self.window.level=NSFloatingWindowLevel;
  self.window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.window.titlebarAppearsTransparent=YES;
  self.window.titleVisibility=NSWindowTitleHidden;
  self.window.releasedWhenClosed=NO;[self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  __weak __typeof__(self) weakSelf=self;
  self.session=[self.browser loadURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/fixed"]] inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:^(BOOL back,BOOL forward,BOOL loading) {
    NSLog(@"Overlay navigation: index=%ld loading=%d generation=%lu scheduled=%d",(long)weakSelf.index,loading,(unsigned long)weakSelf.session.documentGeneration,weakSelf.scheduled);
    if (!loading && !weakSelf.scheduled) {
      weakSelf.scheduled=YES;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{TLTestActivateWindow(weakSelf.window,^{[weakSelf probe];});});
    }
  }];
}
- (void)probe {
  NSLog(@"Overlay probe: %ld",(long)self.index);
  id bridge=[self.session valueForKey:@"pageBridge"];
  NSLog(@"Overlay view geometry: frame=%@ bounds=%@ visibleRect=%@",NSStringFromRect(self.session.webView.frame),NSStringFromRect(self.session.webView.bounds),NSStringFromRect(self.session.webView.visibleRect));
  NSLog(@"Overlay placement: frame=%@ screen=%@ active=%d hidden=%d paused=%@ generation=%@",NSStringFromRect(self.window.frame),NSStringFromRect(self.window.screen.frame),NSApp.active,self.session.webView.hiddenOrHasHiddenAncestor,[self.session valueForKey:@"paused"],[self.session valueForKey:@"transitionGeneration"]);
  NSLog(@"Overlay native state: visible=%d occlusion=%lu cover=%@ frames=%@",self.window.visible,(unsigned long)self.window.occlusionState,[self.session valueForKey:@"navigationCover"],[[bridge valueForKey:@"frames"] allKeys]);
  [self.session.webView evaluateJavaScript:@"({visibility:document.visibilityState,hidden:document.hidden,bridge:typeof globalThis.__talariaWebKitBridge,candidate:typeof globalThis.__talariaWebKitBridge?.candidate})" inFrame:nil inContentWorld:[bridge valueForKey:@"contentWorld"] completionHandler:^(id state,NSError *error){NSLog(@"Overlay document state: %@ error=%@",state,error);}];
  NSArray *paths=@[@"/fixed",@"/closed",@"/frame",@"/clear",@"/large",@"/large-quick",@"/closed-quick",@"/thin-quick",@"/closed-thin-quick",@"/guardian-quick",@"/guardian-normal-quick",@"/guardian-scrolling-quick",@"/guardian-shared-quick"];
  if (self.index>=paths.count) return;
  NSString *path=paths[self.index];
  __weak __typeof__(self) weakSelf=self;
  NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
  [self.browser probeOverlayInSession:self.session overlayRect:NSMakeRect(100,20,800,48) viewportSize:NSMakeSize(1000,700) quick:[path hasSuffix:@"-quick"] completion:^(NSDictionary *result){
    NSLog(@"Overlay result: %@",result);
    TLOverlayTestDelegate *owner=weakSelf;
    [owner.results addObject:@{@"path":path,@"result":result,@"elapsedMS":@((NSProcessInfo.processInfo.systemUptime-start)*1000)}];
    owner.index++;
    if(owner.index==paths.count){
      [owner.browser closeSession:owner.session];
      [owner startLatencyCase];
    }else{
      owner.scheduled=NO;
      [owner.browser navigateSession:owner.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:paths[owner.index]]]];
    }
  }];
}
- (void)startLatencyCase {
  NSLog(@"Overlay latency case: %ld",(long)self.latencyIndex);
  BOOL live=NSProcessInfo.processInfo.arguments.count>4;
  if (self.latencyIndex == (live ? 8 : 7)) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];
    [NSApp terminate:nil];
    return;
  }
  self.shownAt = 0; self.detectedAt = 0;
  self.browser.trace=[NSMutableArray array];
  NSString *path=[NSString stringWithFormat:@"/latency-%ld",(long)self.latencyIndex];
  NSURL *URL=[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:path]];
  if (self.latencyIndex==7) URL=[NSURL URLWithString:NSProcessInfo.processInfo.arguments[4]];
  // This browser-only fixture never opens a chat or accesses persistent data.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:URL
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]
    database:(TLDatabase *)nil orchestrator:(TLAgentOrchestrator *)nil inputWidth:800 browserService:self.browser];
#pragma clang diagnostic pop
  __weak __typeof__(self) weakSelf=self;
  self.tab.metadataChangedHandler=^(NSString *title,NSURL *URL) {
    if ([title isEqualToString:@"banner-visible"] && weakSelf.shownAt == 0)
      weakSelf.shownAt=NSProcessInfo.processInfo.systemUptime;
  };
  NSView *content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1000,700)];
  content.wantsLayer=YES; content.layer.masksToBounds=YES;
  content.layer.cornerRadius=self.tab.palette.space5;
  self.window.contentView=content;
  [content addSubview:self.tab.view];
  [NSLayoutConstraint activateConstraints:@[
    [self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [self.tab.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor],
    [self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:self.latencyIndex==0 ? -0.5 : 0],
  ]];
  [content layoutSubtreeIfNeeded];
  [self.tab startInWindow:self.window];
  NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
  NSTimer *monitor=[NSTimer timerWithTimeInterval:0.005 repeats:YES block:^(NSTimer *timer) {
    TLOverlayTestDelegate *owner=weakSelf;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if (owner.latencyIndex==7 && !owner.shownAt) {
      for (NSDictionary *probe in owner.browser.trace) {
        if ([probe[@"result"][@"obstructed"] isEqual:@YES]) {
          owner.shownAt=[probe[@"completed"] doubleValue]; break;
        }
      }
    }
    BOOL reduced=[[owner.tab valueForKey:@"browserUsesReducedHeight"] boolValue];
    if (owner.shownAt && reduced && !owner.detectedAt) owner.detectedAt=now;
    id transition=[owner.tab valueForKey:@"heightTransition"];
    BOOL animating=[[transition valueForKey:@"browserHeightTimer"] isValid];
    if ((owner.detectedAt && !animating) || now-started>(owner.latencyIndex==7 ? 35 : 8)) {
      [timer invalidate];
      [owner.results addObject:@{@"path":path,
        @"title":owner.tab.title ?: @"", @"shown":@(owner.shownAt), @"reduced":@(reduced),
        @"lastProbe":owner.browser.lastProbe ?: @{}, @"visible":@(owner.window.isVisible),
        @"bounds":NSStringFromRect(owner.tab.view.bounds),
        @"trace":owner.browser.trace ?: @[],
        @"timingOrigin":owner.latencyIndex==7 ? @"first-positive-probe" : @"banner-visible-title",
        @"detectionMS":owner.detectedAt ? @((owner.detectedAt-owner.shownAt)*1000) : @(-1),
        @"settledMS":owner.detectedAt ? @((now-owner.shownAt)*1000) : @(-1)}];
      // Repeated geometry assertions use the controlled fixture. A live site's
      // unrelated styled elements are not reliable viewport-bottom markers.
      if(owner.latencyIndex==0) {
        owner.resizeCycles=[NSMutableArray array];
        TLWebKitBrowserSession *session=[owner.tab valueForKey:@"browserSession"];
        [session.webView evaluateJavaScript:@"window.__talariaResizeCount=0;addEventListener('resize',e=>{if(e.isTrusted)window.__talariaResizeCount++})" completionHandler:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[owner resizeCycle];});
      } else [owner finishLatencyCase];
    }
  }];
  [NSRunLoop.mainRunLoop addTimer:monitor forMode:NSRunLoopCommonModes];
}
- (void)finishLatencyCase {
  [self.tab close]; self.tab=nil; self.latencyIndex++;
  dispatch_async(dispatch_get_main_queue(),^{[self startLatencyCase];});
}
- (void)resizeCycle {
  if(self.resizeCycles.count==24) {
    NSMutableDictionary *record=[self.results.lastObject mutableCopy];
    record[@"resizeCycles"]=self.resizeCycles; self.results[self.results.count-1]=record;
    [self finishLatencyCase]; return;
  }
  CGFloat startHeight=NSHeight([[self.tab valueForKey:@"browserHostView"] frame]);
  [self.tab toggleBrowserHeightMode:nil];
  __block NSDictionary *visualSample;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
    NSView *host=[self.tab valueForKey:@"browserHostView"];
    CALayer *visual=host.layer.presentationLayer ?: host.layer;
    visualSample=@{@"active":@([(TLBrowserHeightTransition *)[self.tab valueForKey:@"heightTransition"] isAnimating]),
      @"heightDifference":@(fabs(NSHeight(host.frame)-startHeight)),
      @"unscaled":@(CATransform3DIsIdentity(visual.transform)),
      @"topError":@(fabs(NSMaxY(host.frame)-NSHeight(host.superview.bounds)))};
  });
  // Exercise rapid reversals, which previously interrupted the 200ms animation.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self.tab toggleBrowserHeightMode:nil];});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,95*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self.tab toggleBrowserHeightMode:nil];});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
    TLWebKitBrowserSession *session=[self.tab valueForKey:@"browserSession"];
    NSString *script=[NSString stringWithFormat:@"requestAnimationFrame(()=>{document.title=JSON.stringify({cycle:%lu,height:innerHeight,resizes:window.__talariaResizeCount,bottom:(document.querySelector('#fides-banner,.als-cookie-button')||document.querySelector('[style]')).getBoundingClientRect().bottom})})",(unsigned long)self.resizeCycles.count];
    [session.webView evaluateJavaScript:script completionHandler:nil];
    [self collectResizeCycle:visualSample deadline:NSProcessInfo.processInfo.systemUptime+5];
  });
}
- (void)collectResizeCycle:(NSDictionary *)visualSample deadline:(NSTimeInterval)deadline {
  NSData *data=[self.tab.title dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *page=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  BOOL current=[page isKindOfClass:NSDictionary.class] && page[@"cycle"] && [page[@"cycle"] unsignedIntegerValue]==self.resizeCycles.count;
  if(!current && NSProcessInfo.processInfo.systemUptime<deadline) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self collectResizeCycle:visualSample deadline:deadline];});
    return;
  }
  NSView *host=[self.tab valueForKey:@"browserHostView"];
  [self.resizeCycles addObject:@{@"tree":TLResizeViewTree(host,4),@"page":self.tab.title ?: @"",@"reduced":[self.tab valueForKey:@"browserUsesReducedHeight"],
    @"visual":visualSample ?: @{}, @"reduceMotion":@(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)}];
  [self resizeCycle];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{if(argc>2)setenv("TL_WEBKIT_PROFILE_DIR",argv[2],1);TLOverlayTestApplication *app=[TLOverlayTestApplication sharedApplication];TLOverlayTestDelegate *delegate=[TLOverlayTestDelegate new];app.delegate=delegate;[app run];}return 0;}
