// Desktop-only performance probe. Production browser objects, disposable pages.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/resource.h>
#import <os/signpost.h>
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
#import "WebKitPageBridge.h"
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLBrowserContentColor.h"

@interface TalariaWindowController (FrameProfile)
- (void)buildInterface;
- (void)installAppStateBindings;
- (TLBrowserTabController *)activeBrowserController;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
@end
@interface FrameWorkspace : TalariaWindowController
@end
@implementation FrameWorkspace
// No external AI traffic in a rendering fixture.
- (void)loadInitialState {}
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
@end

static os_log_t profileLog;
static double CPUSeconds(void) { struct rusage usage;getrusage(RUSAGE_SELF,&usage);return usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6; }

static void Later(double seconds, dispatch_block_t action) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
static void Activate(NSWindow *window, NSUInteger attempt, dispatch_block_t completion) {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  if(@available(macOS 14.0,*))[NSApp activate];
  Later(.25,^{
    if(NSApp.isActive){completion();return;}
    if(attempt>=120){fprintf(stderr,"FAIL: profiling window could not activate within 30 seconds\n");exit(1);}
    Activate(window,attempt+1,completion);
  });
}
@interface FrameProfile : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property TLBrowserTabController *tab;
@property TLWebKitBrowserSession *session;
@property NSMutableArray *cases, *results, *ticks;
@property NSTimer *timer;
@property NSUInteger index;
@property double lastTick, began;
@property double cpuBegan;
@property BOOL stayedVisible, stayedActive;
@property FrameWorkspace *workspace;
@property double width,height;
@property NSMutableArray *colors;
@property NSColor *lastColor;
@property double wallBegan;
@end
@implementation FrameProfile
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  NSDictionary *env=NSProcessInfo.processInfo.environment;
  profileLog=os_log_create("com.talaria.frame-profile",OS_LOG_CATEGORY_POINTS_OF_INTEREST);
  NSApp.appearance=[NSAppearance appearanceNamed:[env[@"TL_PROFILE_DARK"] boolValue] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  if(![env[@"TL_WEBKIT_PROFILE_DIR"] hasPrefix:@"/tmp/talaria-frame-"])exit(2);
  self.width=[env[@"TL_PROFILE_WIDTH"] doubleValue] ?: 1200;self.height=[env[@"TL_PROFILE_HEIGHT"] doubleValue] ?: 850;
  self.window=[[TLMainWindow alloc] initWithContentRect:NSMakeRect(100,100,self.width,self.height)
    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
  self.window.titleVisibility=NSWindowTitleHidden;self.window.titlebarAppearsTransparent=YES;
  self.window.releasedWhenClosed=NO;
  self.window.level=NSFloatingWindowLevel;
  self.cases=[NSMutableArray array];self.results=[NSMutableArray array];
  NSUInteger repeats=MAX(1,[env[@"TL_PROFILE_REPEATS"] integerValue]);
  // Rotate order on each repetition to reduce warm-up/order bias.
  NSArray *modes=env[@"TL_PROFILE_MODES"] ? [env[@"TL_PROFILE_MODES"] componentsSeparatedByString:@","] : @[@"raw",@"session",@"tab"];
  NSArray *workloads=env[@"TL_PROFILE_WORKLOADS"] ? [env[@"TL_PROFILE_WORKLOADS"] componentsSeparatedByString:@","] : @[@"simple",@"dense",@"churn",@"canvas",@"resize"];
  for(NSUInteger repeat=0;repeat<repeats;repeat++)
    for(NSString *workload in workloads)
      for(NSUInteger m=0;m<modes.count;m++)[self.cases addObject:@{@"mode":modes[(m+repeat)%modes.count],@"workload":workload,@"repeat":@(repeat)}];
  Activate(self.window,0,^{
    [@(NSProcessInfo.processInfo.processIdentifier).stringValue writeToFile:env[@"TL_PROFILE_PID"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Later([env[@"TL_PROFILE_DELAY"] doubleValue],^{[self next];});
  });
}
- (void)next {
  BOOL reuseWorkspace=self.workspace && self.index<self.cases.count && [self.cases[self.index][@"mode"] isEqual:@"workspace"];
  if(!reuseWorkspace){
    if(self.tab)[self.tab close];
    else if(self.session)[TLWebKitBrowserController.sharedController closeSession:self.session];
    [self.web removeFromSuperview];self.tab=nil;self.session=nil;self.web=nil;
    if(self.workspace)[self.window orderOut:nil];self.workspace=nil;
  }
  if(self.index==self.cases.count){
    NSDictionary *output=@{@"cases":self.results,@"fps":@(self.window.screen.maximumFramesPerSecond),
      @"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"windowPoints":@[@(self.width),@(self.height)],@"scale":@(self.window.backingScaleFactor)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:output options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_RESULTS"] atomically:YES];
    fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n");fflush(stdout);[NSApp terminate:nil];return;
  }
  NSDictionary *test=self.cases[self.index];
  fprintf(stdout,"CASE %lu %s %s\n",(unsigned long)self.index,[test[@"mode"] UTF8String],[test[@"workload"] UTF8String]);fflush(stdout);
  [self.window setContentSize:NSMakeSize(self.width,self.height)];
  if(!reuseWorkspace)self.window.contentView=[[NSView alloc] initWithFrame:NSMakeRect(0,0,self.width,self.height)];
  NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@",NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"],test[@"workload"]]];
  if(reuseWorkspace){
    [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:url];
  }else if([test[@"mode"] isEqual:@"workspace"]){
    NSString *db=[NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"] stringByAppendingPathComponent:[NSString stringWithFormat:@"workspace-%lu.sqlite",(unsigned long)self.index]];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    self.workspace=[[FrameWorkspace alloc] initWithDatabase:[[TLDatabase alloc] initWithURL:[NSURL fileURLWithPath:db] error:nil] agentOrchestrator:nil appStateManager:[TLAppStateManager new]];
#pragma clang diagnostic pop
    [self.window orderOut:nil];self.window=self.workspace.window;
    self.window.level=NSFloatingWindowLevel;
    [self.window setContentSize:NSMakeSize(self.width,self.height)];
    [self.window setFrameOrigin:NSMakePoint(100,100)];
    [self.workspace startNewChatWithModel:@"fixture" focus:NO];
    for(int i=0;i<3;i++)[self.workspace openBrowserTabWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/simple?background=%d",NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"],i]]];
    [self.workspace openBrowserTabWithURL:url];
    self.tab=[self.workspace activeBrowserController];self.session=[self.tab valueForKey:@"browserSession"];self.web=self.session.webView;
  }else if([test[@"mode"] isEqual:@"tab"]){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    self.tab=[[TLBrowserTabController alloc] initWithURL:url palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:600];
#pragma clang diagnostic pop
    self.window.contentView=self.tab.view;[self.tab.view layoutSubtreeIfNeeded];
    [self.tab startInWindow:self.window];self.session=[self.tab valueForKey:@"browserSession"];self.web=self.session.webView;
  }else if([test[@"mode"] isEqual:@"session"]){
    self.session=[TLWebKitBrowserController.sharedController loadURL:url inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];self.web=self.session.webView;
  }else{
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    self.web=[[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:config];
    self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;[self.window.contentView addSubview:self.web];[self.web loadRequest:[NSURLRequest requestWithURL:url]];
  }
  if(self.tab && [NSProcessInfo.processInfo.environment[@"TL_PROFILE_NO_BLUR"] boolValue])[[self.tab valueForKey:@"bottomBlur"] setHidden:YES];
  if(self.tab && [NSProcessInfo.processInfo.environment[@"TL_PROFILE_NO_COLOR_WAVE"] boolValue])self.tab.headerColorChangedHandler=nil;
  [self waitReady:0];
}
- (void)waitReady:(NSUInteger)attempt {
  if(attempt>200){fprintf(stderr,"FAIL: page readiness timeout\n");exit(1);}
  if(self.web.loading){Later(.05,^{[self waitReady:attempt+1];});return;}
  TLTestEvaluate(self.web,@"typeof startProfile === 'function'",^(id ready){
    if(![ready boolValue]){Later(.05,^{[self waitReady:attempt+1];});return;}
    Activate(self.window,0,^{Later(.7,^{[self measure];});});
  });
}
- (void)measure {
  TLTestEvaluate(self.web,@"startProfile()",^(id value){
    os_signpost_interval_begin(profileLog,1,"Frame workload","%{public}s %{public}s",[self.cases[self.index][@"mode"] UTF8String],[self.cases[self.index][@"workload"] UTF8String]);
    self.ticks=[NSMutableArray array];self.lastTick=self.began=CACurrentMediaTime();
    self.cpuBegan=CPUSeconds();
    self.wallBegan=NSDate.date.timeIntervalSince1970;
    self.stayedVisible=YES;self.stayedActive=YES;
    self.colors=[NSMutableArray array];self.lastColor=nil;
    self.timer=[NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer){
      double now=CACurrentMediaTime(),elapsed=now-self.began;
      self.stayedVisible &= (self.window.occlusionState & NSWindowOcclusionStateVisible)!=0;
      self.stayedActive &= NSApp.isActive;
      NSColor *color=self.tab.headerContentColor;
      if(color && ![color isEqual:self.lastColor]){self.lastColor=color;[self.colors addObject:[TLBrowserContentColor CSSStringForColor:color]];}
      [self.ticks addObject:@((now-self.lastTick)*1000)];self.lastTick=now;
      if([self.cases[self.index][@"workload"] isEqual:@"resize"])
        [self.window setContentSize:NSMakeSize(self.width-100+100*cos(elapsed*3),self.height-50+50*cos(elapsed*3))];
      else if(![@[@"idle",@"gradient",@"color-pulse",@"canvas-edge"] containsObject:self.cases[self.index][@"workload"]]) TLTestScroll(self.web,elapsed<2.5 ? 12 : -12);
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    Later(5,^{
      [self.timer invalidate];self.timer=nil;
      double cpu=CPUSeconds()-self.cpuBegan;
      os_signpost_interval_end(profileLog,1,"Frame workload");
      TLTestEvaluate(self.web,@"stopProfile()",^(id data){
        NSMutableDictionary *result=[self.cases[self.index] mutableCopy];result[@"page"]=data;result[@"nativeIntervalsMS"]=self.ticks;
        result[@"nativeCPUSeconds"]=@(cpu);
        result[@"startUnixSeconds"]=@(self.wallBegan);result[@"endUnixSeconds"]=@(NSDate.date.timeIntervalSince1970);
        result[@"headerColors"]=self.colors;
        NSView *blur=[self.tab valueForKey:@"bottomBlur"];
        result[@"blurEnabled"]=@(blur && !blur.hidden && blur.backgroundFilters.count>0);
        result[@"headerBindingEnabled"]=@(self.tab.headerColorChangedHandler!=nil);
        result[@"windowDelegateEnabled"]=@(self.workspace && self.window.delegate==(id)self.workspace);
        result[@"sidebarVisible"]=@([[self.workspace valueForKey:@"sidebarVisible"] boolValue]);
        result[@"dark"]=@(self.tab.palette.dark);
        result[@"active"]=@(self.stayedActive);result[@"visible"]=@(self.stayedVisible);
        void (^complete)(void)=^{
          [self.results addObject:result];
          NSData *partial=[NSJSONSerialization dataWithJSONObject:@{@"complete":@NO,@"cases":self.results} options:NSJSONWritingPrettyPrinted error:nil];
          [partial writeToFile:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_RESULTS"] atomically:YES];
          self.index++;Later(.2,^{[self next];});
        };
        if(self.session){
          TLWebKitPageBridge *bridge=[self.session valueForKey:@"pageBridge"];
          [self.web evaluateJavaScript:@"globalThis.__frameColorProfile || null" inFrame:nil inContentWorld:bridge.contentWorld completionHandler:^(id stats,NSError *error){if(stats)result[@"colorProfile"]=stats;complete();}];
        }else complete();
      });
    });
  });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{return [TLWebKitBrowserController.sharedController prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater;}
- (void)applicationWillTerminate:(NSNotification *)note{[TLWebKitBrowserController.sharedController shutdown];}
@end
int main(int argc,const char *argv[]){@autoreleasepool{
  NSApplication *app=NSApplication.sharedApplication;FrameProfile *delegate=[FrameProfile new];app.delegate=delegate;[app run];
}return 0;}
