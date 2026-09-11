#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Time-based displacement only; routing and pixel quantization belong to the caller.
@interface TLWheelScrollAnimation : NSObject
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) NSPoint remainingDelta;
- (NSPoint)addDelta:(NSPoint)delta atTime:(NSTimeInterval)time;
- (NSPoint)advanceToTime:(NSTimeInterval)time;
- (NSPoint)finish;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
