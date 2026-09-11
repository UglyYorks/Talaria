// Native wheel-routing contract probe. Subdivided events are an experiment in
// this test executable only; the application continues to forward native input.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"

static void Later(double seconds, dispatch_block_t action) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr,"%s: %s\n",condition ? "PASS" : "FAIL",message.UTF8String);
  fflush(condition ? stdout : stderr);if(!condition)exit(1);
}

@interface TLWheelProbe : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property NSMutableArray *results;
@property NSArray *cases;
@property NSUInteger index;
@property NSView *nativeTarget;
@property BOOL animatorFeatureAvailable;
@end
@implementation TLWheelProbe
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  self.results=[NSMutableArray array];
  self.cases=@[
    @{@"name":@"native-long",@"target":@"page"},
    @{@"name":@"native-animator-enabled",@"target":@"page",@"animator":@YES},
    @{@"name":@"native-horizontal",@"target":@"page",@"horizontal":@YES},
    @{@"name":@"native-shift-wheel",@"target":@"page",@"shift":@YES},
    @{@"name":@"native-repeated",@"target":@"page",@"repeat":@3},
    @{@"name":@"native-reversal",@"target":@"page",@"repeat":@2,@"reverse":@YES},
    @{@"name":@"native-precise",@"target":@"page",@"precise":@YES},
    @{@"name":@"native-momentum",@"target":@"page",@"precise":@YES,@"momentum":@YES},
    @{@"name":@"native-panel",@"target":@"panel"},
    @{@"name":@"native-iframe",@"target":@"frame"},
    @{@"name":@"native-consumer",@"target":@"consumer"},
    @{@"name":@"native-control-consumer",@"target":@"consumer",@"control":@YES},
    @{@"name":@"subdivided-consumer",@"target":@"consumer",@"split":@YES},
    @{@"name":@"phased-consumer",@"target":@"consumer",@"split":@YES,@"phased":@YES},
    @{@"name":@"native-moving-panel",@"target":@"panel",@"moving":@YES},
    @{@"name":@"subdivided-moving-panel",@"target":@"panel",@"moving":@YES,@"split":@YES},
    @{@"name":@"phased-moving-panel",@"target":@"panel",@"moving":@YES,@"split":@YES,@"phased":@YES},
    @{@"name":@"native-boundary",@"target":@"panel",@"boundary":@YES},
    @{@"name":@"subdivided-boundary",@"target":@"panel",@"boundary":@YES,@"split":@YES},
    @{@"name":@"phased-boundary",@"target":@"panel",@"boundary":@YES,@"split":@YES,@"phased":@YES},
    @{@"name":@"native-near-boundary",@"target":@"panel",@"nearBoundary":@YES},
    @{@"name":@"subdivided-near-boundary",@"target":@"panel",@"nearBoundary":@YES,@"split":@YES},
    @{@"name":@"phased-near-boundary",@"target":@"panel",@"nearBoundary":@YES,@"split":@YES,@"phased":@YES}
  ];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(60,60,920,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed=NO;self.window.level=NSFloatingWindowLevel;
  [self.window makeKeyAndOrderFront:nil];
  self.session=[TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"]]
    inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  TLTestActivateWindow(self.window,^{[self waitForLoad:0];});
  Later(45,^{Check(NO,@"wheel probe deadline");});
}
- (void)waitForLoad:(NSUInteger)attempt {
  if(!self.session.webView.loading && self.session.documentGeneration) {
    TLTestEvaluate(self.session.webView,@"typeof frameReady !== 'undefined' && frameReady === true",^(id ready){
      if([ready isEqual:@YES]){[self nextCase];return;}
      Check(attempt<100,@"cross-origin fixture loads");Later(.05,^{[self waitForLoad:attempt+1];});
    });return;
  }
  Check(attempt<100,@"main fixture loads");Later(.05,^{[self waitForLoad:attempt+1];});
}
- (void)nextCase {
  if(self.index==self.cases.count){[self finish];return;}
  NSDictionary *test=self.cases[self.index];
  // This private feature is evaluated as an alternative, never enabled by app code.
  if(test[@"animator"]){
    SEL features=NSSelectorFromString(@"_features"),setter=NSSelectorFromString(@"_setEnabled:forFeature:");
    BOOL found=NO;
    if([WKPreferences respondsToSelector:features] && [self.session.webView.configuration.preferences respondsToSelector:setter]) {
      for(id feature in ((id (*)(id,SEL))objc_msgSend)(WKPreferences.class,features)) {
        if([[feature valueForKey:@"key"] isEqual:@"ScrollAnimatorEnabled"]){
          ((void (*)(id,SEL,BOOL,id))objc_msgSend)(self.session.webView.configuration.preferences,setter,YES,feature);found=YES;
        }
      }
    }
    self.animatorFeatureAvailable=found;
    fprintf(stdout,"ScrollAnimatorEnabled feature available: %d\n",found);
  }
  NSString *code=[NSString stringWithFormat:@"resetProbe(%@,%@,%@);",test[@"moving"] ? @"true" : @"false",test[@"boundary"] ? @"true" : @"false",test[@"nearBoundary"] ? @"true" : @"false"];
  TLTestEvaluate(self.session.webView,code,^(id value){Later(.12,^{[self deliverSlice:0];});});
}
- (void)deliverSlice:(NSUInteger)slice {
  NSDictionary *test=self.cases[self.index];
  BOOL split=[test[@"split"] boolValue],phased=[test[@"phased"] boolValue],horizontal=[test[@"horizontal"] boolValue];
  BOOL precise=split || [test[@"precise"] boolValue];
  BOOL momentum=[test[@"momentum"] boolValue];
  BOOL ending=(split && slice==15) || (momentum && slice==1);
  if(!ending || phased || momentum){
    NSString *target=test[@"target"];
    CGFloat x=[target isEqual:@"panel"] ? 100 : [target isEqual:@"frame"] ? 700 : [target isEqual:@"consumer"] ? 400 : 850;
    CGFloat y=self.session.webView.isFlipped ? 100 : NSHeight(self.session.webView.bounds)-100;
    NSPoint point=[self.session.webView convertPoint:NSMakePoint(x,y) toView:nil];
    int delta=ending ? 0 : split ? -8 : precise ? -120 : -3;
    if(test[@"reverse"] && slice)delta=-delta;
    CGEventRef event=CGEventCreateScrollWheelEvent(NULL,precise ? kCGScrollEventUnitPixel : kCGScrollEventUnitLine,2,
      horizontal ? 0 : delta,horizontal ? delta : 0);
    CGEventSetIntegerValueField(event,kCGScrollWheelEventIsContinuous,precise);
    // Do not inherit keys that the person using the desktop happens to hold.
    CGEventSetFlags(event,0);
    if(test[@"shift"])CGEventSetFlags(event,kCGEventFlagMaskShift);
    if(test[@"control"])CGEventSetFlags(event,kCGEventFlagMaskControl);
    if(momentum)CGEventSetIntegerValueField(event,kCGScrollWheelEventMomentumPhase,ending ? kCGMomentumScrollPhaseEnd : kCGMomentumScrollPhaseBegin);
    if(phased)CGEventSetIntegerValueField(event,kCGScrollWheelEventScrollPhase,ending ? kCGScrollPhaseEnded : slice ? kCGScrollPhaseChanged : kCGScrollPhaseBegan);
    NSPoint screen=[self.window convertPointToScreen:point];
    CGEventSetLocation(event,CGPointMake(screen.x,NSMaxY(NSScreen.screens.firstObject.frame)-screen.y));
    NSEvent *wheel=[NSEvent eventWithCGEvent:event];
    if(wheel.hasPreciseScrollingDeltas!=precise)Check(NO,@"native fixture preserves precise-input metadata");
    if(momentum && wheel.momentumPhase!=(ending ? NSEventPhaseEnded : NSEventPhaseBegan))Check(NO,@"native fixture preserves momentum metadata");
    if(phased && wheel.phase!=(ending ? NSEventPhaseEnded : slice ? NSEventPhaseChanged : NSEventPhaseBegan))Check(NO,@"native fixture preserves gesture-phase metadata");
    if(!slice)fprintf(stdout,"%s: native precise=%d phase=%lu momentum=%lu delta=(%g,%g)\n",[test[@"name"] UTF8String],wheel.hasPreciseScrollingDeltas,(unsigned long)wheel.phase,(unsigned long)wheel.momentumPhase,wheel.scrollingDeltaX,wheel.scrollingDeltaY);
    // Pin both native receiver and coordinates for every slice. WebKit still
    // resolves the DOM scroller internally; an NSView reference cannot pin it.
    if(!slice)self.nativeTarget=[self.window.contentView hitTest:[self.window.contentView.superview convertPoint:point fromView:nil]];
    if(!self.nativeTarget)Check(NO,@"wheel has a native hit target");
    [self.nativeTarget scrollWheel:wheel];CFRelease(event);
  }
  if(split && !ending){Later(.008,^{[self deliverSlice:slice+1];});return;}
  if(momentum && !ending){Later(.008,^{[self deliverSlice:slice+1];});return;}
  if(test[@"repeat"] && slice+1<[test[@"repeat"] unsignedIntegerValue]){Later(.025,^{[self deliverSlice:slice+1];});return;}
  Later(.45,^{
    TLTestEvaluate(self.session.webView,@"JSON.stringify(readProbe())",^(NSString *JSON){
      NSMutableDictionary *result=[[NSJSONSerialization JSONObjectWithData:[JSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
      result[@"name"]=test[@"name"];[self.results addObject:result];
      if(test[@"animator"])result[@"animatorFeatureAvailable"]=@(self.animatorFeatureAvailable);
      fprintf(stdout,"PASS: completed native input scenario %s\n",[test[@"name"] UTF8String]);fflush(stdout);
      self.index++;[self nextCase];
    });
  });
}
- (void)finish {
  NSString *path=NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_RESULTS"];
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:path atomically:YES];
  [TLWebKitBrowserController.sharedController closeSession:self.session];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)note {
  [TLWebKitBrowserController.sharedController shutdown];printf("TALARIA_BROWSER_TEST_COMPLETE\n");fflush(stdout);
}
@end
int main(int argc,char **argv){@autoreleasepool{
  NSApplication *application=NSApplication.sharedApplication;
  [NSUserDefaults.standardUserDefaults registerDefaults:@{@"NSScrollAnimationEnabled":@YES}];
  TLWheelProbe *delegate=[TLWheelProbe new];application.delegate=delegate;[application run];
}return 0;}
