#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Main-thread, per-document placement. Unknown observations preserve placement
// and break confirmation. Clear means a completed scan, not an unfinished slice.
@interface TLBrowserOverlayPolicy : NSObject
@property (nonatomic, readonly) BOOL reducedHeight;
@property (nonatomic, readonly) BOOL manuallyOverridden;
@property (nonatomic, readonly) BOOL latchedReducedHeight;
@property (nonatomic) NSTimeInterval observationInterval;
- (BOOL)observe:(nullable NSNumber *)obstructed atTime:(NSTimeInterval)time;
- (void)setManualReducedHeight:(BOOL)reduced;
- (void)resetForNavigation;
// Full content dimensions, before subtracting the address-bar reservation.
- (void)updateContentSize:(NSSize)size;
// Give full scans and quick checks separate work budgets. JavaScript is measured;
// browser hit tests use a fixed allowance, so this is not a total CPU guarantee.
// Full clear proofs have a 1.5s minimum cadence; quick checks a 200ms minimum.
// Charge unfinished work too. For quick scheduling, known also includes a
// completed DOM scan whose opaque fallback is independently cooling down.
+ (NSTimeInterval)delayForCostMS:(double)cost known:(BOOL)known;
+ (NSTimeInterval)quickDelayForCostMS:(double)cost known:(BOOL)known;
@end
NS_ASSUME_NONNULL_END
