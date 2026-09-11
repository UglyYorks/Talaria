#import "TLBrowserWheelSmoother.h"
#import "TLWheelScrollAnimation.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

BOOL TLBrowserWheelEventCanBeSmoothed(NSEvent *event) {
  if(event.type!=NSEventTypeScrollWheel || event.hasPreciseScrollingDeltas || event.phase!=NSEventPhaseNone || event.momentumPhase!=NSEventPhaseNone)return NO;
  if(event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption))return NO;
  // WebKit direction-locks gesture streams. Forward diagonal input unchanged
  // rather than silently losing its secondary axis.
  return isfinite(event.deltaX) && isfinite(event.deltaY) && ((event.deltaX!=0) != (event.deltaY!=0));
}

@interface TLBrowserWheelSmoother ()
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, weak) NSView *receiver;
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic) id monitor;
@property (nonatomic) NSMutableArray *observers;
@property (nonatomic) id accessibilityObserver;
@property (nonatomic) TLWheelScrollAnimation *animation;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) NSEvent *original;
@property (nonatomic) NSPoint anchor, roundingRemainder;
@property (nonatomic) BOOL gestureStarted, restoreNavigationGestures;
@property (nonatomic) CFTimeInterval lastFrame;
@end

@implementation TLBrowserWheelSmoother
static __weak TLBrowserWheelSmoother *activeSmoother;
- (instancetype)initWithWebView:(WKWebView *)webView {
  if((self=[super init])){_webView=webView;_animation=[TLWheelScrollAnimation new];_enabled=YES;}
  return self;
}
- (void)dealloc { [self attachToWindow:nil]; }
- (BOOL)animating { return self.timer!=nil; }
- (void)setEnabled:(BOOL)enabled { _enabled=enabled;if(!enabled)[self cancel]; }
- (void)attachToWindow:(NSWindow *)window {
  [self cancel];
  if(self.monitor)[NSEvent removeMonitor:self.monitor];self.monitor=nil;
  for(id observer in self.observers)[NSNotificationCenter.defaultCenter removeObserver:observer];
  if(self.accessibilityObserver)[NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self.accessibilityObserver];
  self.accessibilityObserver=nil;self.observers=[NSMutableArray array];self.window=window;
  if(!window)return;
  __weak typeof(self) weakSelf=self;
  NSEventMask mask=NSEventMaskScrollWheel|NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown|NSEventMaskOtherMouseDown|NSEventMaskKeyDown|NSEventMaskFlagsChanged|NSEventMaskMagnify;
  self.monitor=[NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event){
    TLBrowserWheelSmoother *owner=weakSelf;
    if(event.type!=NSEventTypeScrollWheel){[owner cancel];return event;}
    return [owner handleWheel:event] ? nil : event;
  }];
  for(NSNotificationName name in @[NSWindowWillCloseNotification,NSWindowDidResignKeyNotification,NSWindowDidMiniaturizeNotification,NSWindowDidChangeOcclusionStateNotification,NSWindowDidMoveNotification,NSWindowDidResizeNotification])
    [self.observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:window queue:nil usingBlock:^(NSNotification *note){[weakSelf cancel];}]];
  [self.observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note){[weakSelf cancel];}]];
  self.accessibilityObserver=[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[weakSelf cancel];}];
}
- (BOOL)canAnimate {
  return self.enabled && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && self.window && self.window==self.webView.window && self.window.visible && !self.window.miniaturized && !NSApp.hidden && !self.webView.hiddenOrHasHiddenAncestor;
}
- (BOOL)handleWheel:(NSEvent *)event {
  if(![self canAnimate] || !TLBrowserWheelEventCanBeSmoothed(event) || !event.CGEvent || event.window!=self.window){[self cancel];return NO;}
  // Fail open for unusual app-generated input whose CG representation lacks
  // AppKit's window metadata. Reconstructing it must retain exact local routing.
  NSEvent *roundTrip=[NSEvent eventWithCGEvent:event.CGEvent];
  if(roundTrip.window!=event.window || !NSEqualPoints(roundTrip.locationInWindow,event.locationInWindow)){[self cancel];return NO;}
  NSView *content=self.window.contentView;
  NSView *hit=[content hitTest:[content.superview convertPoint:event.locationInWindow fromView:nil]];
  if(!hit || ![hit isDescendantOf:self.webView]){[self cancel];return NO;}
  if(activeSmoother!=self)[activeSmoother cancel];
  activeSmoother=self;
  NSPoint anchor=[self.webView convertPoint:event.locationInWindow fromView:nil];
  // WebKit converts non-precise line deltas to 40-point steps. AppKit has
  // already converted Shift-wheel to deltaX; never rotate the axes a second time.
  NSPoint delta=NSMakePoint(event.deltaX*40,event.deltaY*40), pending=self.animation.remainingDelta;
  BOOL changedTarget=self.original && (hit!=self.receiver || !NSEqualPoints(anchor,self.anchor));
  BOOL changedAxis=self.original && ((delta.x!=0)!=(self.original.deltaX!=0));
  BOOL reversed=pending.x*delta.x<0 || pending.y*delta.y<0;
  if(changedTarget || changedAxis || reversed){
    // Settle already accepted distance at the old target before starting the
    // new direction/target. No stale-direction frames survive the new input.
    [self emitDelta:[self.animation finish] ending:NO];[self endGesture];
  }
  if(!self.original){
    self.original=event;self.receiver=hit;self.anchor=anchor;
    self.restoreNavigationGestures=self.webView.allowsBackForwardNavigationGestures;
    self.webView.allowsBackForwardNavigationGestures=NO;
  }
  CFTimeInterval now=CACurrentMediaTime();self.lastFrame=now;
  [self emitDelta:[self.animation addDelta:delta atTime:now] ending:NO];
  if(!self.timer){
    __weak typeof(self) weakSelf=self;
    NSInteger fps=MAX(60,MIN(120,self.window.screen.maximumFramesPerSecond));
    self.timer=[NSTimer timerWithTimeInterval:1.0/fps repeats:YES block:^(NSTimer *timer){
      TLBrowserWheelSmoother *owner=weakSelf;if(owner.timer==timer)[owner advance];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
  }
  return YES;
}
- (void)emitDelta:(NSPoint)delta ending:(BOOL)ending {
  if(!self.original || !self.receiver || self.receiver.window!=self.window)return;
  NSPoint sum=NSMakePoint(delta.x+self.roundingRemainder.x,delta.y+self.roundingRemainder.y);
  NSPoint pixels=ending ? NSZeroPoint : NSMakePoint(round(sum.x),round(sum.y));
  if(!ending)self.roundingRemainder=NSMakePoint(sum.x-pixels.x,sum.y-pixels.y);
  if(!ending && pixels.x==0 && pixels.y==0)return;
  if(ending && !self.gestureStarted)return;
  CGEventRef native=CGEventCreateCopy(self.original.CGEvent);
  CGEventSetTimestamp(native,(CGEventTimestamp)(NSProcessInfo.processInfo.systemUptime*1e9));
  CGEventSetIntegerValueField(native,kCGScrollWheelEventIsContinuous,1);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventScrollPhase,ending ? kCGScrollPhaseEnded : self.gestureStarted ? kCGScrollPhaseChanged : kCGScrollPhaseBegan);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventMomentumPhase,0);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventDeltaAxis1,(int64_t)pixels.y);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventDeltaAxis2,(int64_t)pixels.x);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventFixedPtDeltaAxis1,(int64_t)(pixels.y*65536));
  CGEventSetIntegerValueField(native,kCGScrollWheelEventFixedPtDeltaAxis2,(int64_t)(pixels.x*65536));
  CGEventSetIntegerValueField(native,kCGScrollWheelEventPointDeltaAxis1,(int64_t)pixels.y);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventPointDeltaAxis2,(int64_t)pixels.x);
  // Keep the original CG location data intact. CGEventSetLocation discards
  // AppKit's window-local coordinates. View/window movement cancels the stream.
  NSEvent *replacement=[NSEvent eventWithCGEvent:native];
  self.gestureStarted=!ending;
  // Deliver only to the captured native receiver, outside the application's
  // event queue. WebKit owns DOM hit testing, latching and preventDefault.
  [self.receiver scrollWheel:replacement];CFRelease(native);
}
- (void)endGesture {
  [self emitDelta:NSZeroPoint ending:YES];
  if(self.original)self.webView.allowsBackForwardNavigationGestures=self.restoreNavigationGestures;
  self.original=nil;self.receiver=nil;self.gestureStarted=NO;
}
- (void)advance {
  CFTimeInterval now=CACurrentMediaTime();
  BOOL moved=!NSEqualPoints([self.webView convertPoint:self.anchor toView:nil],self.original.locationInWindow);
  if(![self canAnimate] || moved || self.receiver.hiddenOrHasHiddenAncestor || self.receiver.window!=self.window || now-self.lastFrame>0.25){[self cancel];return;}
  self.lastFrame=now;[self emitDelta:[self.animation advanceToTime:now] ending:NO];
  if(!self.animation.active){[self.timer invalidate];self.timer=nil;[self endGesture];if(activeSmoother==self)activeSmoother=nil;}
}
- (void)cancel {
  [self.timer invalidate];self.timer=nil;[self.animation cancel];[self endGesture];
  self.roundingRemainder=NSZeroPoint;if(activeSmoother==self)activeSmoother=nil;
}
@end
