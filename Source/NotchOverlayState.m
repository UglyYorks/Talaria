#import "NotchOverlayState.h"
#import <math.h>

TLShakeRecognizerConfiguration TLDefaultShakeRecognizerConfiguration(void) {
  TLShakeRecognizerConfiguration configuration;
  configuration.minimumAxisDelta = 7.0;
  configuration.minimumAxisVelocity = 420.0;
  configuration.scoreDecayPerSecond = 3.2;
  configuration.triggerScore = 3.0;
  configuration.gestureTimeout = 0.22;
  return configuration;
}

TLNotchScreenMetrics TLNotchScreenMetricsMake(NSRect frame,
                                              NSRect auxiliaryTopLeftArea,
                                              NSRect auxiliaryTopRightArea,
                                              CGFloat safeAreaTopInset,
                                              CGFloat fallbackNotchWidth,
                                              CGFloat minimumOverlayHeight) {
  TLNotchScreenMetrics metrics;
  metrics.frame = frame;
  metrics.auxiliaryTopLeftArea = auxiliaryTopLeftArea;
  metrics.auxiliaryTopRightArea = auxiliaryTopRightArea;
  metrics.safeAreaTopInset = safeAreaTopInset;
  metrics.fallbackNotchWidth = fallbackNotchWidth;
  metrics.minimumOverlayHeight = minimumOverlayHeight;
  return metrics;
}

NSRect TLDetectedNotchRectForScreenMetrics(TLNotchScreenMetrics metrics) {
  NSRect leftArea = metrics.auxiliaryTopLeftArea;
  NSRect rightArea = metrics.auxiliaryTopRightArea;

  if (!NSIsEmptyRect(leftArea) && !NSIsEmptyRect(rightArea)) {
    CGFloat minX = NSMaxX(leftArea);
    CGFloat maxX = NSMinX(rightArea);
    CGFloat minY = MAX(NSMinY(leftArea), NSMinY(rightArea));
    CGFloat height = MIN(NSHeight(leftArea), NSHeight(rightArea));

    if (maxX > minX && height > 0.0) {
      return NSMakeRect(minX, minY, maxX - minX, height);
    }
  }

  if (metrics.safeAreaTopInset <= 0.0) {
    return NSZeroRect;
  }

  CGFloat width = MIN(metrics.fallbackNotchWidth, NSWidth(metrics.frame) * 0.24);
  CGFloat height = metrics.safeAreaTopInset;
  return NSMakeRect(NSMidX(metrics.frame) - (width * 0.5),
                    NSMaxY(metrics.frame) - height,
                    width,
                    height);
}

NSRect TLVirtualNotchRectForScreenMetrics(TLNotchScreenMetrics metrics) {
  CGFloat width = MIN(metrics.fallbackNotchWidth, NSWidth(metrics.frame) * 0.24) * 0.90;
  CGFloat height = metrics.minimumOverlayHeight * 0.50;
  return NSMakeRect(NSMidX(metrics.frame) - (width * 0.5),
                    NSMaxY(metrics.frame) - height,
                    width,
                    height);
}

@interface TLShakeRecognizer ()
@property (nonatomic) TLShakeRecognizerConfiguration configuration;
@property (nonatomic, readwrite) CGFloat score;
@property (nonatomic) BOOL hasSample;
@property (nonatomic) NSPoint previousLocation;
@property (nonatomic) NSTimeInterval previousTime;
@property (nonatomic) NSInteger previousHorizontalDirection;
@property (nonatomic) NSInteger previousVerticalDirection;
@end

@implementation TLShakeRecognizer

- (instancetype)initWithConfiguration:(TLShakeRecognizerConfiguration)configuration {
  self = [super init];
  if (self) {
    _configuration = configuration;
  }
  return self;
}

- (void)reset {
  self.hasSample = NO;
  self.previousLocation = NSZeroPoint;
  self.previousTime = 0.0;
  self.previousHorizontalDirection = 0;
  self.previousVerticalDirection = 0;
  self.score = 0.0;
}

- (BOOL)recordPoint:(NSPoint)point timestamp:(NSTimeInterval)timestamp {
  if (!self.hasSample) {
    self.hasSample = YES;
    self.previousLocation = point;
    self.previousTime = timestamp;
    return NO;
  }

  NSTimeInterval elapsed = MAX(0.001, timestamp - self.previousTime);
  CGFloat dx = point.x - self.previousLocation.x;
  CGFloat dy = point.y - self.previousLocation.y;
  self.score = MAX(0.0, self.score - (elapsed * self.configuration.scoreDecayPerSecond));

  self.previousLocation = point;
  self.previousTime = timestamp;

  if (elapsed > self.configuration.gestureTimeout) {
    self.previousHorizontalDirection = 0;
    self.previousVerticalDirection = 0;
    self.score = 0.0;
  }

  NSInteger horizontalDirection = fabs(dx) >= self.configuration.minimumAxisDelta ? (dx > 0.0 ? 1 : -1) : 0;
  NSInteger verticalDirection = fabs(dy) >= self.configuration.minimumAxisDelta ? (dy > 0.0 ? 1 : -1) : 0;
  CGFloat horizontalVelocity = fabs(dx) / elapsed;
  CGFloat verticalVelocity = fabs(dy) / elapsed;

  BOOL reversedHorizontally = self.previousHorizontalDirection != 0 &&
    horizontalDirection != 0 &&
    horizontalDirection != self.previousHorizontalDirection &&
    horizontalVelocity >= self.configuration.minimumAxisVelocity;
  BOOL reversedVertically = self.previousVerticalDirection != 0 &&
    verticalDirection != 0 &&
    verticalDirection != self.previousVerticalDirection &&
    verticalVelocity >= self.configuration.minimumAxisVelocity;

  if (reversedHorizontally) {
    self.score += 1.0;
  }
  if (reversedVertically) {
    self.score += 1.0;
  }

  if (horizontalDirection != 0) {
    self.previousHorizontalDirection = horizontalDirection;
  }
  if (verticalDirection != 0) {
    self.previousVerticalDirection = verticalDirection;
  }

  if (self.score < self.configuration.triggerScore) {
    return NO;
  }

  self.score = 0.0;
  return YES;
}

@end

@interface TLDropPromptTimer ()
@property (nonatomic, readwrite) BOOL armed;
@property (nonatomic, readwrite) NSTimeInterval expiresAt;
@property (nonatomic) NSTimeInterval lastUpdateAt;
@end

@implementation TLDropPromptTimer

- (void)armAtTimestamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration {
  self.armed = YES;
  self.expiresAt = timestamp + duration;
  self.lastUpdateAt = timestamp;
}

- (void)reset {
  self.armed = NO;
  self.expiresAt = 0.0;
  self.lastUpdateAt = 0.0;
}

- (BOOL)updateAtTimestamp:(NSTimeInterval)timestamp hovered:(BOOL)hovered {
  if (!self.armed) {
    return NO;
  }

  if (hovered && self.lastUpdateAt > 0.0) {
    self.expiresAt += MAX(0.0, timestamp - self.lastUpdateAt);
  }

  self.lastUpdateAt = timestamp;
  if (!hovered && timestamp >= self.expiresAt) {
    [self reset];
    return NO;
  }

  return YES;
}

- (CGFloat)progressAtTimestamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration {
  if (!self.armed || duration <= 0.0) {
    return 0.0;
  }

  CGFloat remaining = MAX(0.0, self.expiresAt - timestamp);
  CGFloat elapsed = duration - remaining;
  return MIN(1.0, MAX(0.0, elapsed / duration));
}

@end
