#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Animates the actual viewport at native scale, with at most 60 layout updates/s.
@interface TLBrowserHeightTransition : NSObject
@property (nonatomic, readonly, getter=isAnimating) BOOL animating;
@property (nonatomic, copy, nullable) void (^insetChanged)(CGFloat inset);
- (instancetype)initWithContentView:(NSView *)contentView bottomConstraint:(NSLayoutConstraint *)constraint;
- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot;
- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot completion:(nullable dispatch_block_t)completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
