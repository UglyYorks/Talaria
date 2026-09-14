// Exercise the production AppKit event path and observe native WebKit scrolling.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"

static void Later(double seconds, dispatch_block_t action) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr,"%s: %s\n",condition ? "PASS" : "FAIL",message.UTF8String);
  fflush(condition ? stdout : stderr);if(!condition)exit(1);
}

@interface TLWheelTestWindow : NSWindow
@property NSEvent *lastWheelEvent;
@end
@implementation TLWheelTestWindow
- (void)sendEvent:(NSEvent *)event {
  if(event.type==NSEventTypeScrollWheel)self.lastWheelEvent=event;
  [super sendEvent:event];
}
@end

@interface TLWheelProbe : NSObject <NSApplicationDelegate>
@property TLWheelTestWindow *window;
@property TLWebKitBrowserSession *session;
@property NSMutableArray *results;
@property NSArray *cases;
@property NSUInteger index;
@end
@implementation TLWheelProbe
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  self.results=[NSMutableArray array];
  self.cases=@[
    @{@"name":@"native-long",@"target":@"page"},
    @{@"name":@"native-horizontal",@"target":@"page",@"horizontal":@YES},
    @{@"name":@"native-shift-wheel",@"target":@"page",@"shift":@YES},
    @{@"name":@"native-repeated",@"target":@"page",@"repeat":@3},
    @{@"name":@"native-reversal",@"target":@"page",@"repeat":@2,@"reverse":@YES},
    @{@"name":@"native-precise",@"target":@"page",@"precise":@YES},
    @{@"name":@"native-phased",@"target":@"page",@"precise":@YES,@"phased":@YES},
    @{@"name":@"native-diagonal",@"target":@"page",@"diagonal":@YES},
    @{@"name":@"native-momentum",@"target":@"page",@"precise":@YES,@"momentum":@YES},
    @{@"name":@"native-panel",@"target":@"panel"},
    @{@"name":@"native-panel-horizontal",@"target":@"panel",@"horizontal":@YES},
    @{@"name":@"native-iframe",@"target":@"frame"},
    @{@"name":@"native-consumer",@"target":@"consumer"},
    @{@"name":@"native-control-consumer",@"target":@"consumer",@"control":@YES},
    @{@"name":@"native-command-consumer",@"target":@"consumer",@"command":@YES},
    @{@"name":@"native-option-consumer",@"target":@"consumer",@"option":@YES},
    @{@"name":@"native-moving-panel",@"target":@"panel",@"moving":@YES},
    @{@"name":@"native-boundary",@"target":@"panel",@"boundary":@YES},
    @{@"name":@"native-near-boundary",@"target":@"panel",@"nearBoundary":@YES},
  ];
  self.window=[[TLWheelTestWindow alloc] initWithContentRect:NSMakeRect(60,60,920,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
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
  NSString *code=[NSString stringWithFormat:@"resetProbe(%@,%@,%@);",test[@"moving"] ? @"true" : @"false",test[@"boundary"] ? @"true" : @"false",test[@"nearBoundary"] ? @"true" : @"false"];
  TLTestEvaluate(self.session.webView,code,^(id value){Later(.12,^{[self deliverSlice:0];});});
}
- (void)deliverSlice:(NSUInteger)slice {
  NSDictionary *test=self.cases[self.index];
  BOOL precise=[test[@"precise"] boolValue],horizontal=[test[@"horizontal"] boolValue];
  BOOL momentum=[test[@"momentum"] boolValue],phased=[test[@"phased"] boolValue];
  BOOL ending=(momentum || phased) && slice==1;
  NSString *target=test[@"target"];
  CGFloat x=[target isEqual:@"panel"] ? 100 : [target isEqual:@"frame"] ? 700 : [target isEqual:@"consumer"] ? 400 : 850;
  CGFloat y=self.session.webView.isFlipped ? 100 : NSHeight(self.session.webView.bounds)-100;
  NSPoint point=[self.session.webView convertPoint:NSMakePoint(x,y) toView:nil];
  int delta=ending ? 0 : precise ? -120 : -3;
  if(test[@"reverse"] && slice)delta=-delta;
  // Public AppKit mouse-event templates retain the window and local coordinates
  // that CGEventCreateScrollWheelEvent cannot specify for NSApplication routing.
  NSEvent *templateEvent=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
  CGEventRef event=CGEventCreateCopy(templateEvent.CGEvent);
  CGEventSetType(event,kCGEventScrollWheel);
  int dx=(horizontal || test[@"diagonal"]) ? delta : 0,dy=horizontal ? 0 : delta;
  CGEventSetIntegerValueField(event,kCGScrollWheelEventDeltaAxis1,dy);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventDeltaAxis2,dx);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventFixedPtDeltaAxis1,dy*65536);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventFixedPtDeltaAxis2,dx*65536);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventPointDeltaAxis1,dy);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventPointDeltaAxis2,dx);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventIsContinuous,precise);
  CGEventFlags flags=0;
  if(test[@"shift"])flags|=kCGEventFlagMaskShift;
  if(test[@"control"])flags|=kCGEventFlagMaskControl;
  if(test[@"command"])flags|=kCGEventFlagMaskCommand;
  if(test[@"option"])flags|=kCGEventFlagMaskAlternate;
  CGEventSetFlags(event,flags);
  if(momentum)CGEventSetIntegerValueField(event,kCGScrollWheelEventMomentumPhase,ending ? kCGMomentumScrollPhaseEnd : kCGMomentumScrollPhaseBegin);
  if(phased)CGEventSetIntegerValueField(event,kCGScrollWheelEventScrollPhase,ending ? kCGScrollPhaseEnded : kCGScrollPhaseBegan);
  NSEvent *wheel=[NSEvent eventWithCGEvent:event];
  Check(wheel.window==self.window && NSEqualPoints(wheel.locationInWindow,point),@"native event retains its window and position");
  Check(wheel.hasPreciseScrollingDeltas==precise,@"native event retains precise-input metadata");
  Check(wheel.phase==(phased ? (ending ? NSEventPhaseEnded : NSEventPhaseBegan) : NSEventPhaseNone),@"native event retains gesture phases");
  Check(wheel.momentumPhase==(momentum ? (ending ? NSEventPhaseEnded : NSEventPhaseBegan) : NSEventPhaseNone),@"native event retains momentum phases");
  self.window.lastWheelEvent=nil;
  [NSApp sendEvent:wheel];
  Check(self.window.lastWheelEvent==wheel,@"original wheel event reaches NSWindow unchanged");
  Check(self.session.webView.allowsBackForwardNavigationGestures,@"wheel input leaves native history gestures enabled");
  CFRelease(event);
  if((momentum || phased) && !ending){Later(.02,^{[self deliverSlice:slice+1];});return;}
  if(test[@"repeat"] && slice+1<[test[@"repeat"] unsignedIntegerValue]){Later(.025,^{[self deliverSlice:slice+1];});return;}
  Later(.45,^{
    TLTestEvaluate(self.session.webView,@"JSON.stringify(readProbe())",^(NSString *JSON){
      NSMutableDictionary *result=[[NSJSONSerialization JSONObjectWithData:[JSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
      result[@"name"]=test[@"name"];[self.results addObject:result];
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
  TLWheelProbe *delegate=[TLWheelProbe new];application.delegate=delegate;[application run];
}return 0;}
