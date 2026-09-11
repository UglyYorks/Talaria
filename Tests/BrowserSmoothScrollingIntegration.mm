// Exercise the production local event monitor and a real desktop WKWebView.
// JavaScript observes native input; it never drives the scrolling under test.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "WebKitBrowserController.h"
#import "TLBrowserPreferences.h"
#import "WebKitBrowserSettings.h"
#import "design_system/TLBrowserWebView.h"
#import "BrowserWebKitTestSupport.h"

static void Later(double seconds,dispatch_block_t action){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);}
static void Check(BOOL condition,NSString *message){fprintf(condition?stdout:stderr,"%s: %s\n",condition?"PASS":"FAIL",message.UTF8String);fflush(condition?stdout:stderr);if(!condition)exit(1);}
static BOOL simulatedReduceMotion;
static IMP originalReduceMotion;
static void SetSmoothing(BOOL enabled){NSError *error=nil;Check([TLBrowserPreferences.sharedPreferences saveValue:@(enabled) forSetting:[TLBrowserPreferences settingWithID:@"smoothMouseWheelScrolling"] error:&error],@"browser setting saves successfully");}

@interface TLSmoothTestWindow : NSWindow
@property NSEvent *lastWheelEvent;
@end
@implementation TLSmoothTestWindow
- (void)sendEvent:(NSEvent *)event {if(event.type==NSEventTypeScrollWheel)self.lastWheelEvent=event;[super sendEvent:event];}
@end

@interface TLSmoothProbe : NSObject <NSApplicationDelegate>
@property TLSmoothTestWindow *window;
@property TLWebKitBrowserSession *session;
@property NSMutableArray *results;
@property NSArray *cases;
@property NSUInteger index;
@end
@implementation TLSmoothProbe
- (TLBrowserWebView *)view{return (TLBrowserWebView *)self.session.webView;}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  Method method=class_getInstanceMethod(NSWorkspace.class,@selector(accessibilityDisplayShouldReduceMotion));
  originalReduceMotion=method_getImplementation(method);
  // Only this fixture's process is changed; no system accessibility setting is written.
  method_setImplementation(method,imp_implementationWithBlock(^BOOL(NSWorkspace *workspace){return simulatedReduceMotion || ((BOOL (*)(id,SEL))originalReduceMotion)(workspace,@selector(accessibilityDisplayShouldReduceMotion));}));
  self.results=[NSMutableArray array];
  self.cases=@[
    @{@"name":@"smooth-long",@"target":@"page"},
    @{@"name":@"smooth-repeated",@"target":@"page",@"repeat":@3},
    @{@"name":@"smooth-reversal",@"target":@"page",@"repeat":@2,@"reverse":@YES},
    @{@"name":@"smooth-horizontal",@"target":@"page",@"horizontal":@YES},
    @{@"name":@"smooth-shift",@"target":@"page",@"shift":@YES},
    @{@"name":@"smooth-panel",@"target":@"panel"},
    @{@"name":@"smooth-panel-horizontal",@"target":@"panel",@"horizontal":@YES},
    @{@"name":@"smooth-frame",@"target":@"frame"},
    @{@"name":@"smooth-moving-panel",@"target":@"panel",@"moving":@YES},
    @{@"name":@"smooth-consumer",@"target":@"consumer"},
    @{@"name":@"bypass-control",@"target":@"consumer",@"control":@YES},
    @{@"name":@"bypass-command",@"target":@"consumer",@"command":@YES},
    @{@"name":@"bypass-option",@"target":@"consumer",@"option":@YES},
    @{@"name":@"bypass-precise",@"target":@"page",@"precise":@YES},
    @{@"name":@"bypass-momentum",@"target":@"page",@"precise":@YES,@"momentum":@YES},
    @{@"name":@"bypass-phased",@"target":@"page",@"precise":@YES,@"phased":@YES},
    @{@"name":@"bypass-diagonal",@"target":@"page",@"diagonal":@YES},
    @{@"name":@"smooth-boundary",@"target":@"panel",@"boundary":@YES},
    @{@"name":@"smooth-near-boundary",@"target":@"panel",@"nearBoundary":@YES},
    @{@"name":@"cancel-disable",@"target":@"page",@"cancel":@"disable"},
    @{@"name":@"bypass-disabled",@"target":@"page",@"disabled":@YES},
    @{@"name":@"cancel-hidden",@"target":@"page",@"cancel":@"hidden"},
    @{@"name":@"cancel-detached",@"target":@"page",@"cancel":@"detached"},
    @{@"name":@"cancel-window",@"target":@"page",@"cancel":@"window"},
    @{@"name":@"cancel-key",@"target":@"page",@"cancel":@"key"},
    @{@"name":@"cancel-motion",@"target":@"page",@"cancel":@"motion"},
    @{@"name":@"bypass-reduce-motion",@"target":@"page",@"motion":@YES},
    @{@"name":@"cancel-stalled",@"target":@"page",@"cancel":@"stalled"},
    @{@"name":@"cancel-navigation",@"target":@"page",@"cancel":@"navigation"},
    @{@"name":@"cancel-same-document",@"target":@"page",@"cancel":@"same-document"},
    @{@"name":@"cancel-close",@"target":@"page",@"cancel":@"close"}
  ];
  self.window=[[TLSmoothTestWindow alloc] initWithContentRect:NSMakeRect(60,60,920,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed=NO;self.window.level=NSFloatingWindowLevel;[self.window makeKeyAndOrderFront:nil];
  self.session=[TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"]]
    inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  if([NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_BACKGROUND"] boolValue])Later(.2,^{[self waitForLoad:0];});
  else TLTestActivateWindow(self.window,^{[self waitForLoad:0];});
  Later(55,^{Check(NO,@"smoothing probe deadline");});
}
- (void)waitForLoad:(NSUInteger)attempt {
  if(!self.view.loading && self.session.documentGeneration){
    TLTestEvaluate(self.view,@"typeof frameReady !== 'undefined' && frameReady === true",^(id ready){
      if([ready isEqual:@YES]){Check(self.view.smoothMouseWheelScrolling,@"smoothing defaults on in a new browser view");[self nextCase];return;}
      Check(attempt<100,@"cross-origin fixture loads");Later(.05,^{[self waitForLoad:attempt+1];});
    });return;
  }
  Check(attempt<100,@"main fixture loads");Later(.05,^{[self waitForLoad:attempt+1];});
}
- (void)nextCase {
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_RESULTS"] atomically:YES];
  if(self.index==self.cases.count){[self finish];return;}
  NSDictionary *test=self.cases[self.index];
  SetSmoothing(![test[@"disabled"] boolValue]);simulatedReduceMotion=[test[@"motion"] boolValue];
  NSString *code=[NSString stringWithFormat:@"resetProbe(%@,%@,%@);",test[@"moving"]?@"true":@"false",test[@"boundary"]?@"true":@"false",test[@"nearBoundary"]?@"true":@"false"];
  TLTestEvaluate(self.view,code,^(id value){Later(.15,^{[self deliverSlice:0];});});
}
- (void)postWheel:(NSDictionary *)test slice:(NSUInteger)slice ending:(BOOL)ending {
  NSString *target=test[@"target"];
  CGFloat x=[target isEqual:@"panel"]?100:[target isEqual:@"frame"]?700:[target isEqual:@"consumer"]?400:850;
  CGFloat y=self.view.isFlipped?100:NSHeight(self.view.bounds)-100;
  NSPoint point=[self.view convertPoint:NSMakePoint(x,y) toView:nil];
  BOOL precise=[test[@"precise"] boolValue],horizontal=[test[@"horizontal"] boolValue];
  int delta=(ending || test[@"zero"])?0:precise?-120:-3;if(test[@"reverse"] && slice)delta=-delta;
  // The public CG scroll-event factory has no window argument. Start with an
  // AppKit mouse-event template to retain the window and local coordinate data,
  // then change its CG type and wheel fields using public Quartz APIs.
  NSEvent *templateEvent=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
  CGEventRef event=CGEventCreateCopy(templateEvent.CGEvent);CGEventSetType(event,kCGEventScrollWheel);
  int dx=(horizontal || test[@"diagonal"])?delta:0,dy=horizontal?0:delta;
  CGEventSetIntegerValueField(event,kCGScrollWheelEventDeltaAxis1,dy);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventDeltaAxis2,dx);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventFixedPtDeltaAxis1,dy*65536);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventFixedPtDeltaAxis2,dx*65536);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventPointDeltaAxis1,dy);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventPointDeltaAxis2,dx);
  CGEventSetIntegerValueField(event,kCGScrollWheelEventIsContinuous,precise);
  CGEventFlags flags=0;if(test[@"shift"])flags|=kCGEventFlagMaskShift;if(test[@"control"])flags|=kCGEventFlagMaskControl;
  if(test[@"command"])flags|=kCGEventFlagMaskCommand;if(test[@"option"])flags|=kCGEventFlagMaskAlternate;CGEventSetFlags(event,flags);
  if(test[@"momentum"])CGEventSetIntegerValueField(event,kCGScrollWheelEventMomentumPhase,ending?kCGMomentumScrollPhaseEnd:kCGMomentumScrollPhaseBegin);
  if(test[@"phased"])CGEventSetIntegerValueField(event,kCGScrollWheelEventScrollPhase,ending?kCGScrollPhaseEnded:kCGScrollPhaseBegan);
  NSEvent *wheel=[NSEvent eventWithCGEvent:event];
  Check(wheel.window==self.window && NSEqualPoints(wheel.locationInWindow,point),@"native test event has the correct window and local position");
  self.window.lastWheelEvent=nil;[NSApp sendEvent:wheel];
  if([test[@"name"] hasPrefix:@"bypass"])
    Check(self.window.lastWheelEvent==wheel,@"bypassed event reaches NSWindow unchanged, including precise/momentum metadata");
  CFRelease(event);
}
- (void)deliverSlice:(NSUInteger)slice {
  NSDictionary *test=self.cases[self.index];
  if(test[@"momentum"]){
    NSDictionary *prime=@{@"target":test[@"target"],@"precise":@YES,@"phased":@YES,@"zero":@YES};
    [self postWheel:prime slice:0 ending:NO];[self postWheel:prime slice:0 ending:YES];
  }
  [self postWheel:test slice:slice ending:NO];
  Later(.02,^{[self afterSlice:slice];});
}
- (void)afterSlice:(NSUInteger)slice {
  NSDictionary *test=self.cases[self.index];
  BOOL bypass=[test[@"name"] hasPrefix:@"bypass"];
  Check(self.view.mouseWheelAnimationActive!=bypass,[test[@"name"] stringByAppendingString:@" uses the expected native event path"]);
  if(test[@"cancel"]){[self cancelCase:test];return;}
  if(test[@"repeat"] && slice+1<[test[@"repeat"] unsignedIntegerValue]){Later(.005,^{[self deliverSlice:slice+1];});return;}
  if(test[@"phased"] || test[@"momentum"])Later(.02,^{[self postWheel:test slice:1 ending:YES];});
  Later(.5,^{
    Check(!self.view.mouseWheelAnimationActive,@"no scheduled animation remains after settling");
    Check(self.view.allowsBackForwardNavigationGestures,@"native history gestures are restored after wheel handling");
    TLTestEvaluate(self.view,@"JSON.stringify(readProbe())",^(NSString *JSON){
      NSMutableDictionary *result=[[NSJSONSerialization JSONObjectWithData:[JSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
      result[@"name"]=test[@"name"];[self.results addObject:result];self.index++;[self nextCase];
    });
  });
}
- (void)cancelCase:(NSDictionary *)test {
  NSString *action=test[@"cancel"];
  TLBrowserWebView *view=self.view;
  if([action isEqual:@"disable"]){SetSmoothing(NO);Check(!view.smoothMouseWheelScrolling,@"preference applies immediately to the existing view");}
  if([action isEqual:@"hidden"]){self.window.contentView.hidden=YES;self.window.contentView.hidden=NO;}
  if([action isEqual:@"detached"]){[view removeFromSuperview];[self.window.contentView addSubview:view];}
  if([action isEqual:@"window"]){[self.window orderOut:nil];[self.window makeKeyAndOrderFront:nil];}
  if([action isEqual:@"key"])[NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53]];
  if([action isEqual:@"motion"]){simulatedReduceMotion=YES;[NSWorkspace.sharedWorkspace.notificationCenter postNotificationName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];}
  if([action isEqual:@"stalled"])usleep(300000); // Simulate a blocked main run loop, fixture only.
  if([action isEqual:@"navigation"])[view reload];
  if([action isEqual:@"same-document"])TLTestEvaluate(view,@"history.pushState({},'', '#changed')",nil);
  if([action isEqual:@"close"])[TLWebKitBrowserController.sharedController closeSession:self.session];
  Later(.15,^{
    Check(!view.mouseWheelAnimationActive,[action stringByAppendingString:@" cancels the pending timer"]);
    TLTestEvaluate(view,@"JSON.stringify(readProbe())",^(NSString *JSON){
      NSDictionary *before=[NSJSONSerialization JSONObjectWithData:[JSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
      Later(.2,^{TLTestEvaluate(view,@"JSON.stringify(readProbe())",^(NSString *afterJSON){
        NSMutableDictionary *after=[[NSJSONSerialization JSONObjectWithData:[afterJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        Check([before[@"wheel"] isEqual:after[@"wheel"]] && [before[@"y"] isEqual:after[@"y"]],[action stringByAppendingString:@" produces no delayed input or scrolling after returning"]);
        Check(!view.mouseWheelAnimationActive && view.allowsBackForwardNavigationGestures,@"cancelled animation stays idle and restores history gestures");
        after[@"name"]=test[@"name"];[self.results addObject:after];self.index++;[self nextCase];
      });});
    });
  });
}
- (void)finish {
  method_setImplementation(class_getInstanceMethod(NSWorkspace.class,@selector(accessibilityDisplayShouldReduceMotion)),originalReduceMotion);
  NSString *path=NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_RESULTS"];
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil] writeToFile:path atomically:YES];
  [TLWebKitBrowserController.sharedController closeSession:self.session];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{return [TLWebKitBrowserController.sharedController prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater;}
- (void)applicationWillTerminate:(NSNotification *)note{[TLWebKitBrowserController.sharedController shutdown];printf("TALARIA_BROWSER_TEST_COMPLETE\n");fflush(stdout);}
@end
int main(int argc,char **argv){@autoreleasepool{NSApplication *application=NSApplication.sharedApplication;TLSmoothProbe *delegate=[TLSmoothProbe new];application.delegate=delegate;[application run];}return 0;}
