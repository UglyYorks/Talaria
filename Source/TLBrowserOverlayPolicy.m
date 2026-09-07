#import "TLBrowserOverlayPolicy.h"
#import <math.h>
@interface TLBrowserOverlayPolicy ()
@property (nonatomic, readwrite) BOOL reducedHeight, manuallyOverridden, latchedReducedHeight;
@property (nonatomic) BOOL hasEvidence, evidenceValue, hasSample, hasRelease;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic) NSTimeInterval evidenceStart, lastSample, releasedAt, releaseGrace;
@property (nonatomic) NSSize contentSize;
@end
@implementation TLBrowserOverlayPolicy
+ (NSTimeInterval)delayForCostMS:(double)cost known:(BOOL)known {
  if (!isfinite(cost) || cost < 0) return 8.0;
  return MAX(known ? 1.5 : 3.0, MIN(120.0, cost * 0.08));
}
+ (NSTimeInterval)quickDelayForCostMS:(double)cost known:(BOOL)known {
  if (!isfinite(cost) || cost < 0) return 8.0;
  return MAX(known ? 0.2 : 3.0, MIN(120.0, cost * 0.08));
}
- (BOOL)observe:(NSNumber *)obstructed atTime:(NSTimeInterval)time {
  if (self.manuallyOverridden) return NO;
  if (!isfinite(time)) { self.hasEvidence = NO; return NO; }
  if (self.hasSample && time <= self.lastSample) return NO;
  NSTimeInterval interval = isfinite(self.observationInterval) ? MAX(0.2, MIN(120.0, self.observationInterval)) : 0.2;
  if (self.hasSample && time-self.lastSample > interval*2+3) self.hasEvidence = NO;
  self.hasSample = YES; self.lastSample = time;
  if (!obstructed) { self.hasEvidence = NO; return NO; }
  BOOL value = obstructed.boolValue;
  if (!self.hasEvidence || self.evidenceValue != value) {
    self.hasEvidence = YES; self.evidenceValue = value;
    self.evidenceStart = time; self.sampleCount = 0;
  }
  self.sampleCount++;
  if (!self.reducedHeight && value && self.sampleCount >= 2 && time-self.evidenceStart >= 0.15) {
    self.reducedHeight = YES;
    self.latchedReducedHeight = self.hasRelease && self.evidenceStart-self.releasedAt <= self.releaseGrace;
    self.hasRelease = NO; self.hasEvidence = NO;
    return YES;
  }
  if (self.reducedHeight && !value && !self.latchedReducedHeight && self.sampleCount >= 2 && time-self.evidenceStart >= 0.45) {
    self.reducedHeight = NO; self.hasEvidence = NO;
    self.hasRelease = YES; self.releasedAt = time; self.releaseGrace = interval+3;
    return YES;
  }
  return NO;
}
- (void)setManualReducedHeight:(BOOL)reduced {
  [self resetForNavigation];
  self.reducedHeight = reduced; self.manuallyOverridden = YES;
}
- (void)resetForNavigation {
  self.reducedHeight = NO; self.manuallyOverridden = NO; self.latchedReducedHeight = NO;
  self.hasEvidence = NO; self.hasSample = NO; self.hasRelease = NO;
}
- (void)updateContentSize:(NSSize)size {
  if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0) return;
  if (fabs(size.width-self.contentSize.width)<8 && fabs(size.height-self.contentSize.height)<8) return;
  self.contentSize = size;
  self.latchedReducedHeight = NO; self.hasEvidence = NO; self.hasRelease = NO;
}
@end
