#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
  CGFloat minimumAxisDelta;
  CGFloat minimumAxisVelocity;
  CGFloat scoreDecayPerSecond;
  CGFloat triggerScore;
  NSTimeInterval gestureTimeout;
} TLShakeRecognizerConfiguration;

typedef struct {
  NSRect frame;
  NSRect auxiliaryTopLeftArea;
  NSRect auxiliaryTopRightArea;
  CGFloat safeAreaTopInset;
  CGFloat fallbackNotchWidth;
  CGFloat minimumOverlayHeight;
} TLNotchScreenMetrics;

TLShakeRecognizerConfiguration TLDefaultShakeRecognizerConfiguration(void);
TLNotchScreenMetrics TLNotchScreenMetricsMake(NSRect frame,
                                              NSRect auxiliaryTopLeftArea,
                                              NSRect auxiliaryTopRightArea,
                                              CGFloat safeAreaTopInset,
                                              CGFloat fallbackNotchWidth,
                                              CGFloat minimumOverlayHeight);
NSRect TLDetectedNotchRectForScreenMetrics(TLNotchScreenMetrics metrics);
NSRect TLVirtualNotchRectForScreenMetrics(TLNotchScreenMetrics metrics);

@interface TLShakeRecognizer : NSObject

@property (nonatomic, readonly) CGFloat score;

- (instancetype)initWithConfiguration:(TLShakeRecognizerConfiguration)configuration;
- (void)reset;
- (BOOL)recordPoint:(NSPoint)point timestamp:(NSTimeInterval)timestamp;

@end

@interface TLDropPromptTimer : NSObject

@property (nonatomic, readonly) BOOL armed;
@property (nonatomic, readonly) NSTimeInterval expiresAt;

- (void)armAtTimestamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration;
- (void)reset;
- (BOOL)updateAtTimestamp:(NSTimeInterval)timestamp hovered:(BOOL)hovered;
- (CGFloat)progressAtTimestamp:(NSTimeInterval)timestamp duration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
