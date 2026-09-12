// Real WebKit Fullscreen API and AppKit view restoration; isolated profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
#import "TalariaWindowController.h"
@interface TalariaWindowController (FullscreenTests)
- (TLBrowserTabController *)activeBrowserController;
@end
@interface TLFullscreenWorkspace : TalariaWindowController
@end
@implementation TLFullscreenWorkspace
- (void)loadInitialState {}
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
@end
@interface TLBrowserTabController (FullscreenTests)
- (BOOL)canSamplePageAppearance;
@end
@interface TLFullscreenTestApplication : NSApplication
@end
@implementation TLFullscreenTestApplication
@end
@interface TLFullscreenTestBrowser : TLWebKitBrowserController
@end
@implementation TLFullscreenTestBrowser
@end
@interface TLFullscreenTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLFullscreenTestBrowser *browser;
@property(nonatomic,strong) TLBrowserTabController *tab;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSView *originalHost;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,copy) void (^reply)(id);
@property(nonatomic) NSUInteger scriptID;
@property(nonatomic) NSRect originalWindow;
@property(nonatomic) CGFloat originalInset;
@property(nonatomic,weak) NSWindow *fullscreenWindow;
@property(nonatomic,strong) NSURL *liveURL;
@property(nonatomic,strong) TLFullscreenWorkspace *workspace;
@property(nonatomic,copy) NSString *diagnostic;
@end
@implementation TLFullscreenTestDelegate
- (void)after:(double)seconds run:(dispatch_block_t)block { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block); }
- (TLWebKitBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (WKWebView *)webView { return self.session.webView; }
- (NSView *)nativeView { return self.session.webView; }
- (void)check:(BOOL)passed name:(NSString *)name { NSLog(@"%@: %@",passed ? @"PASS" : @"FAIL",name); [self.results addObject:@{@"name":name,@"passed":@(passed)}]; }
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)completion attempt:(NSUInteger)attempt {
  if(condition()){completion();return;}
  if(attempt>=120){NSLog(@"Fullscreen state=%ld session=%d view=%@ host=%@",(long)self.webView.fullscreenState,self.session.fullscreen,self.webView,self.webView.superview);[self check:NO name:@"Native fullscreen transition completes"];[self finish];return;}
  [self after:0.05 run:^{[self waitFor:condition then:completion attempt:attempt+1];}];
}
- (void)eval:(NSString *)code then:(void (^)(id))completion {
  self.reply=completion; self.scriptID++;
  NSString *script=[NSString stringWithFormat:@"Promise.resolve((()=>{%@})()).then(value=>{document.title=JSON.stringify({test:%lu,value})}).catch(error=>{document.title=JSON.stringify({test:%lu,value:{error:String(error)}})})",code,(unsigned long)self.scriptID,(unsigned long)self.scriptID];
  [self.session.webView evaluateJavaScript:script completionHandler:nil];
}
- (void)enterFullscreen:(NSString *)target then:(void (^)(id))completion {
  if (self.liveURL) { [self clickPlayerFullscreen:completion]; return; }
  self.reply=completion; self.scriptID++;
  NSString *script=[NSString stringWithFormat:@"(()=>{let button=document.createElement('button');button.id='talaria-fullscreen-test';button.textContent='Enter fullscreen';button.style='position:fixed;top:0;left:0;width:180px;height:60px;z-index:2147483647';button.onclick=()=>{button.remove();%@.requestFullscreen().then(()=>{document.title=JSON.stringify({test:%lu,value:true})}).catch(error=>{document.title=JSON.stringify({test:%lu,value:{error:String(error)}})})};document.body.append(button)})()",target,(unsigned long)self.scriptID,(unsigned long)self.scriptID];
  [self.webView evaluateJavaScript:script completionHandler:^(id value,NSError *error){
    if(error){NSLog(@"Fullscreen setup failed: %@",error);completion(@NO);return;}
    [self after:0.1 run:^{
      NSView *view=self.webView;
      NSPoint point=[view convertPoint:NSMakePoint(50,view.isFlipped?30:NSHeight(view.bounds)-30) toView:nil];
      NSView *targetView=[self.window.contentView hitTest:[self.window.contentView convertPoint:point fromView:nil]];
      NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
      NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
      NSLog(@"Posting trusted fullscreen click to %@",targetView);
      [NSApp postEvent:down atStart:NO];[NSApp postEvent:up atStart:NO];
    }];
  }];
}
- (void)clickPlayerFullscreen:(void (^)(id))completion {
  [self.webView evaluateJavaScript:@"(()=>{const b=document.querySelector('.ytp-fullscreen-button');if(!b)return null;const r=b.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,width:r.width,height:r.height}})()" completionHandler:^(NSDictionary *rect,NSError *error){
    if(error || ![rect isKindOfClass:NSDictionary.class] || [rect[@"width"] doubleValue]<=0){completion(@NO);return;}
    NSView *view=self.webView;NSWindow *window=view.window;
    NSPoint point=[view convertPoint:NSMakePoint([rect[@"x"] doubleValue],view.isFlipped ? [rect[@"y"] doubleValue] : NSHeight(view.bounds)-[rect[@"y"] doubleValue]) toView:nil];
    // YouTube fades its controls and disables their hit testing while idle.
    // Reveal them with native pointer motion before sending the trusted click.
    window.acceptsMouseMovedEvents=YES;
    NSEvent *move=[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    [NSApp postEvent:move atStart:NO];
    [self after:.25 run:^{
    for(NSNumber *type in @[@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]) {
      NSEvent *event=[NSEvent mouseEventWithType:(NSEventType)type.integerValue location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
      [NSApp postEvent:event atStart:NO];
    }
    completion(@YES);
    }];
  }];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  self.liveURL=args.count>4 ? [NSURL URLWithString:args[4]] : nil;
  self.diagnostic=args.count>5 ? args[5] : @"";
  self.results=[NSMutableArray array];
  [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.browser=[TLFullscreenTestBrowser new];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,1000,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; self.window.releasedWhenClosed=NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  if(self.liveURL) {
    self.browser=(id)TLWebKitBrowserController.sharedController;
    NSURL *databaseURL=[NSURL fileURLWithPath:[args[2] stringByAppendingPathComponent:@"fullscreen.sqlite"]];
    self.workspace=[[TLFullscreenWorkspace alloc] initWithDatabase:[[TLDatabase alloc] initWithURL:databaseURL error:nil] agentOrchestrator:nil appStateManager:[TLAppStateManager new]];
    self.window=self.workspace.window;
    [self.window setContentSize:NSMakeSize(2600,1400)];
    [self.workspace openBrowserTabWithURL:self.liveURL];
    self.tab=[self.workspace activeBrowserController];
  } else {
    self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/fullscreen"]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:360 browserService:self.browser];
  }
#pragma clang diagnostic pop
  __weak TLFullscreenTestDelegate *weakSelf=self;
  void (^originalMetadata)(NSString *,NSURL *)=self.tab.metadataChangedHandler;
  self.tab.metadataChangedHandler=^(NSString *title,NSURL *URL){
    id value=[NSJSONSerialization JSONObjectWithData:[title dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if(![value isKindOfClass:NSDictionary.class] && originalMetadata)originalMetadata(title,URL);
    if([value isKindOfClass:NSDictionary.class] && [value[@"test"] unsignedIntegerValue]==weakSelf.scriptID && weakSelf.reply){
      void (^callback)(id)=weakSelf.reply;weakSelf.reply=nil;dispatch_async(dispatch_get_main_queue(),^{callback(value[@"value"]);});
    }
  };
  NSView *content=self.window.contentView;
  if(!self.liveURL){[content addSubview:self.tab.view];
  // A tab occupies only part of the window, like a split pane; fullscreen must
  // escape these constraints and restore them unchanged afterwards.
  [NSLayoutConstraint activateConstraints:@[[self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[self.tab.view.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.6],[self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor constant:40],[self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
  }
  [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[content layoutSubtreeIfNeeded];
  self.originalWindow=self.window.frame;[self.tab startInWindow:self.window];
  if(self.liveURL) {
    NSView *blur=[self.tab valueForKey:@"bottomBlur"];
    [self check:!blur.hidden && blur.backgroundFilters.count>0 && self.tab.headerColorChangedHandler!=nil && [[self.workspace valueForKey:@"sidebarVisible"] boolValue] name:@"Live YouTube uses production sidebar, blur and tab color matching"];
    if([self.diagnostic isEqual:@"no-blur"])blur.hidden=YES;
    if([self.diagnostic isEqual:@"no-sampling"]){
      [[self.tab valueForKey:@"pageAppearanceTimer"] invalidate];
      self.session.topColorChanged=nil;self.session.topScrollEnded=nil;
    }
    if(self.diagnostic.length)[self.results addObject:@{@"name":@"Diagnostic configuration",@"passed":@YES,@"diagnostic":self.diagnostic}];
  }
  TLTestActivateWindow(self.window,^{[self waitForPage:0];});
  [self after:self.liveURL ? 100 : 35 run:^{if(self.tab){[self check:NO name:@"Fullscreen integration deadline"];[self finish];}}];
}
- (void)waitForPage:(NSUInteger)attempt {
  if(self.session.browserIdentifier<0 || ![[[self.session valueForKey:@"pageBridge"] valueForKey:@"ready"] boolValue]) {
    if(attempt<80){[self after:0.1 run:^{[self waitForPage:attempt+1];}];return;}
    [self check:NO name:@"Page ready"];[self finish];return;
  }
  if(self.liveURL){[self waitForPlayer:0];return;}
  [self after:0.5 run:^{[self cycle:0];}];
}
- (void)waitForPlayer:(NSUInteger)attempt {
  [self.webView evaluateJavaScript:@"!!document.querySelector('.ytp-fullscreen-button') && !!document.querySelector('video')?.readyState" completionHandler:^(id ready,NSError *error){
    if([ready isEqual:@YES]){
      NSDictionary *processes=@{@"app":@(NSProcessInfo.processInfo.processIdentifier),@"renderer":[self.webView valueForKey:@"_webProcessIdentifier"] ?: @0};
      [[NSJSONSerialization dataWithJSONObject:processes options:0 error:nil] writeToFile:[NSProcessInfo.processInfo.arguments[3] stringByAppendingString:@".profile-ready"] atomically:YES];
      [self.webView evaluateJavaScript:@"document.querySelector('video').muted=true;document.querySelector('video').play();true" completionHandler:nil];[self after:3 run:^{[self cycle:0];}];return;
    }
    if(attempt>=60){[self check:NO name:@"Live YouTube player ready"];[self finish];return;}
    [self after:.5 run:^{[self waitForPlayer:attempt+1];}];
  }];
}
- (void)cycle:(NSUInteger)index {
  if(index==4){[self finish];return;}
  TLTestActivateWindow(self.window,^{[self beginCycle:index];});
}
- (void)beginCycle:(NSUInteger)index {
  [self after:0.6 run:^{
    self.originalHost=[self nativeView].superview;
    if (@available(macOS 26.0, *)) self.originalInset=self.webView.obscuredContentInsets.bottom;
    NSString *target=index==1?@"document.querySelector('video')":@"document.querySelector('#target')";
    if(index==2)target=@"document.querySelector('iframe')";
    [self enterFullscreen:target then:^(id entered){
      if(![entered isEqual:@YES])NSLog(@"Fullscreen request result: %@",entered);
      [self check:[entered isEqual:@YES] name:@"Renderer accepts user-initiated fullscreen"];
      [self waitFor:^BOOL{return self.webView.fullscreenState==WKFullscreenStateInFullscreen;} then:^{[self after:0.35 run:^{[self verifyEntry:index];}];} attempt:0];
    }];
  }];
}
- (void)verifyEntry:(NSUInteger)index {
  NSView *view=[self nativeView];
  NSView *host=self.originalHost;
  for(NSWindow *candidate in NSApp.windows) {
    if(candidate!=self.window && candidate.isVisible && NSEqualSizes(candidate.frame.size,candidate.screen.frame.size)) { self.fullscreenWindow=candidate;break; }
  }
  NSWindow *fullscreenWindow=self.fullscreenWindow;
  [self check:self.session.fullscreen && self.session.webView.fullscreenState == WKFullscreenStateInFullscreen && fullscreenWindow!=nil name:@"Browser content enters native fullscreen"];
  [self check:fullscreenWindow && NSEqualSizes(fullscreenWindow.frame.size,fullscreenWindow.screen.frame.size) name:@"Browser fills the selected display"];
  [self check:NSEqualRects(self.originalWindow,self.window.frame) && NSWidth(host.bounds)<NSWidth(self.window.contentView.bounds) name:@"Original split layout and window stay unchanged"];
  [self check:![self.tab canSamplePageAppearance] name:@"Footer probes pause in fullscreen"];
  [self eval:@"let f=document.querySelector('[data-talaria-document-footer]');return {fullscreen:!!document.fullscreenElement,spacer:f?f.getBoundingClientRect().height:0,width:innerWidth,height:innerHeight}" then:^(NSDictionary *state){
    [self check:[state[@"fullscreen"] boolValue] && [state[@"spacer"] doubleValue]==0 name:@"Fullscreen has no document extension"];
    NSLog(@"Fullscreen geometry: page=%@ view=%@ window=%@",state,NSStringFromRect(view.bounds),NSStringFromRect(fullscreenWindow.frame));
    [self check:fullscreenWindow && fabs([state[@"width"] doubleValue]-NSWidth(view.bounds))<1 && fabs([state[@"height"] doubleValue]-NSHeight(view.bounds))<1 name:@"Renderer viewport matches native fullscreen content size"];
    if(index==3){
      [self.tab close];
      [self check:!fullscreenWindow.isVisible && !view.inFullScreenMode name:@"Closing fullscreen tab restores native presentation"];
      [self after:0.2 run:^{[self finish];}];return;
    }
    NSTimeInterval exitStarted=NSProcessInfo.processInfo.systemUptime;
    if(index==1){
      NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:fullscreenWindow.windowNumber context:nil
        characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
      [NSApp sendEvent:escape];
    }else if(index==2 && self.liveURL){
      [self clickPlayerFullscreen:^(id clicked){[self check:[clicked isEqual:@YES] name:@"Click YouTube exit fullscreen control"];}];
    }else if(index==2){
      [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/fullscreen?again"]]];
    }else{
      [self eval:@"return document.exitFullscreen().then(()=>true)" then:^(id result){}];
    }
    [self waitFor:^BOOL{return self.webView.fullscreenState==WKFullscreenStateNotInFullscreen && view.window==self.window && NSEqualRects(view.frame,host.bounds);} then:^{
      [self.results addObject:@{@"name":@"Fullscreen exit latency",@"passed":@YES,@"cycle":@(index),@"elapsedMS":@((NSProcessInfo.processInfo.systemUptime-exitStarted)*1000)}];
      [self check:!self.session.fullscreen && !(self.session.webView.fullscreenState == WKFullscreenStateInFullscreen) && view.superview==host name:@"Exit restores the browser to its original host"];
      [self check:NSEqualRects(view.frame,host.bounds) && NSEqualRects(self.window.frame,self.originalWindow) name:@"Exit restores exact browser and window geometry"];
      if (@available(macOS 26.0, *)) {
        if(index!=2)[self check:self.originalInset==self.webView.obscuredContentInsets.bottom name:@"Exit restores the native footer inset"];
      }
      [self eval:@"return !document.fullscreenElement" then:^(id cleared){
        [self check:[cleared isEqual:@YES] name:@"Exit also clears renderer fullscreen"];
        NSTimeInterval began=NSProcessInfo.processInfo.systemUptime;
        [self eval:@"return new Promise(resolve=>{let last=performance.now(),maxGap=0,frames=0;const start=last;function frame(now){maxGap=Math.max(maxGap,now-last);last=now;frames++;if(now-start<1000)requestAnimationFrame(frame);else resolve({maxGap,frames})}requestAnimationFrame(frame)})" then:^(NSDictionary *cadence){
          [self.results addObject:@{@"name":@"Post-fullscreen frame cadence",@"passed":@([cadence[@"frames"] intValue]>20 && [cadence[@"maxGap"] doubleValue]<250),@"cycle":@(index),@"cadence":cadence,@"elapsedMS":@((NSProcessInfo.processInfo.systemUptime-began)*1000)}];
          // Keep the immediate measurement above: WebKit can publish its
          // NotInFullscreen state before its native presentation is removed.
          // Separately measure recovery once the original window is interactive.
          [self waitFor:^BOOL{return !fullscreenWindow.isVisible && self.window.isKeyWindow;} then:^{
            [self.results addObject:@{@"name":@"Fullscreen recovery observation time",@"passed":@YES,@"cycle":@(index),@"elapsedMS":@((NSProcessInfo.processInfo.systemUptime-exitStarted)*1000)}];
            [self eval:@"return new Promise(resolve=>{let last=performance.now(),maxGap=0,frames=0;const start=last;function frame(now){maxGap=Math.max(maxGap,now-last);last=now;frames++;if(now-start<1000)requestAnimationFrame(frame);else resolve({maxGap,frames,visible:document.visibilityState==='visible',focused:document.hasFocus()})}requestAnimationFrame(frame)})" then:^(NSDictionary *recovery){
              [self.results addObject:@{@"name":@"Recovered fullscreen frame cadence",@"passed":@([recovery[@"frames"] intValue]>20 && [recovery[@"maxGap"] doubleValue]<250 && [recovery[@"visible"] boolValue] && [recovery[@"focused"] boolValue]),@"cycle":@(index),@"cadence":recovery}];
              [self cycle:index+1];
            }];
          } attempt:0];
        }];
      }];
    } attempt:0];
  }];
}
- (void)finish {
  [self.tab close];self.tab=nil;
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{if(argc>2)setenv("TL_WEBKIT_PROFILE_DIR",argv[2],1);TLFullscreenTestApplication *app=[TLFullscreenTestApplication sharedApplication];TLFullscreenTestDelegate *delegate=[TLFullscreenTestDelegate new];app.delegate=delegate;[app run];}return 0;}
