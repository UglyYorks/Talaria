#import "TLWheelScrollAnimation.h"
#import <math.h>

@implementation TLWheelScrollAnimation {
  NSPoint _segment, _delivered;
  NSTimeInterval _started;
}
- (BOOL)active { return _segment.x!=_delivered.x || _segment.y!=_delivered.y; }
- (NSPoint)remainingDelta { return NSMakePoint(_segment.x-_delivered.x,_segment.y-_delivered.y); }
- (NSPoint)advanceToTime:(NSTimeInterval)time {
  if(!self.active)return NSZeroPoint;
  double t=fmin(1,fmax(0,(time-_started)/0.100));
  double eased=1-pow(1-t,3);
  NSPoint next=t==1 ? _segment : NSMakePoint(_segment.x*eased,_segment.y*eased);
  NSPoint result=NSMakePoint(next.x-_delivered.x,next.y-_delivered.y);
  _delivered=next;return result;
}
- (NSPoint)addDelta:(NSPoint)delta atTime:(NSTimeInterval)time {
  if(!isfinite(delta.x) || !isfinite(delta.y) || !isfinite(time))return NSZeroPoint;
  NSPoint result=[self advanceToTime:time], pending=self.remainingDelta;
  // Give every tick immediate feedback; blend its remainder into the existing
  // tail. The whole tail settles within 100 ms of the most recent input.
  NSPoint immediate=NSMakePoint(delta.x*0.20,delta.y*0.20);
  _segment=NSMakePoint(pending.x+delta.x-immediate.x,pending.y+delta.y-immediate.y);
  _delivered=NSZeroPoint;_started=time;
  return NSMakePoint(result.x+immediate.x,result.y+immediate.y);
}
- (NSPoint)finish { NSPoint result=self.remainingDelta;[self cancel];return result; }
- (void)cancel { _segment=NSZeroPoint;_delivered=NSZeroPoint; }
@end
