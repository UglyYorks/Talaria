#import <AppKit/AppKit.h>
#import "TLWheelScrollAnimation.h"
#import "TLBrowserWheelSmoother.h"
#import <math.h>

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
  if(!condition){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}checks++;
}
static NSPoint Plus(NSPoint a,NSPoint b){return NSMakePoint(a.x+b.x,a.y+b.y);}
static BOOL Equal(NSPoint a,NSPoint b){return fabs(a.x-b.x)<1e-8 && fabs(a.y-b.y)<1e-8;}
static NSEvent *Wheel(BOOL precise,CGScrollPhase phase,CGMomentumScrollPhase momentum,CGEventFlags flags,int x,int y) {
  CGEventRef native=CGEventCreateScrollWheelEvent(NULL,precise ? kCGScrollEventUnitPixel : kCGScrollEventUnitLine,2,y,x);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventIsContinuous,precise);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventScrollPhase,phase);
  CGEventSetIntegerValueField(native,kCGScrollWheelEventMomentumPhase,momentum);
  CGEventSetFlags(native,flags);NSEvent *event=[NSEvent eventWithCGEvent:native];CFRelease(native);return event;
}
int main(void){@autoreleasepool{
  TLWheelScrollAnimation *animation=[TLWheelScrollAnimation new];
  NSPoint total=[animation addDelta:NSMakePoint(0,120) atTime:1];
  Check(total.y>0 && total.y<120 && animation.active,@"first tick responds immediately and leaves a short tail");
  for(int i=1;i<=15;i++)total=Plus(total,[animation advanceToTime:1+i/120.0]);
  Check(Equal(total,NSMakePoint(0,120)) && !animation.active,@"one tick preserves its full distance and settles");
  Check(Equal([animation advanceToTime:2],NSZeroPoint),@"idle frames emit nothing");
  total=NSZeroPoint;NSPoint requested=NSZeroPoint;
  for(int i=0;i<500;i++){
    NSPoint delta=NSMakePoint(0.17+i%3,0.31+i%7);requested=Plus(requested,delta);
    total=Plus(total,[animation addDelta:delta atTime:10+i*.003]);
    total=Plus(total,[animation advanceToTime:10+i*.003+.001]);
  }
  total=Plus(total,[animation advanceToTime:12]);
  Check(Equal(total,requested),@"rapid fractional input preserves both axes without accumulated drift");
  Check(!animation.active,@"repeated input stops scheduling after the last tail");
  total=[animation addDelta:NSMakePoint(0,120) atTime:20];
  total=Plus(total,[animation advanceToTime:20.02]);total=Plus(total,[animation finish]);
  NSPoint reversed=[animation addDelta:NSMakePoint(0,-40) atTime:20.02];
  Check(reversed.y<0,@"reversal produces an immediate delta in the new direction");
  total=Plus(Plus(total,reversed),[animation advanceToTime:21]);
  Check(Equal(total,NSMakePoint(0,80)),@"settling the old tail before reversal preserves signed distance");
  [animation addDelta:NSMakePoint(0,120) atTime:30];[animation cancel];
  Check(!animation.active && Equal([animation advanceToTime:100],NSZeroPoint),@"cancellation discards pending work permanently");
  total=[animation addDelta:NSMakePoint(-120,0) atTime:101];total=Plus(total,[animation advanceToTime:102]);
  Check(Equal(total,NSMakePoint(-120,0)),@"horizontal input after cancellation has no stale vertical distance");
  Check(TLBrowserWheelEventCanBeSmoothed(Wheel(NO,0,0,0,0,-3)),@"ordinary wheel is eligible");
  NSEvent *shift=Wheel(NO,0,0,kCGEventFlagMaskShift,0,-3);
  Check(shift.deltaX==-3 && shift.deltaY==0 && TLBrowserWheelEventCanBeSmoothed(shift),@"AppKit maps Shift-wheel to the horizontal axis once");
  Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(YES,0,0,0,0,-120)),@"precise input bypasses smoothing");
  Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(NO,kCGScrollPhaseBegan,0,0,0,-3)),@"phased input bypasses smoothing even without the precise flag");
  Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(NO,0,kCGMomentumScrollPhaseBegin,0,0,-3)),@"momentum bypasses smoothing even without the precise flag");
  for(NSNumber *flags in @[@(kCGEventFlagMaskCommand),@(kCGEventFlagMaskControl),@(kCGEventFlagMaskAlternate)])
    Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(NO,0,0,flags.unsignedLongLongValue,0,-3)),@"browser/site modifier actions bypass smoothing");
  Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(NO,0,0,0,-3,-3)),@"diagonal input bypasses gesture axis locking");
  Check(!TLBrowserWheelEventCanBeSmoothed(Wheel(NO,0,0,0,0,0)),@"zero input does not start animation");
  printf("PASS: %lu wheel animation and eligibility checks\n",(unsigned long)checks);
}return 0;}
