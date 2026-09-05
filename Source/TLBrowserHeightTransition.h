#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Owns the cancellable geometry animation needed by the embedded browser host.
@interface TLBrowserHeightTransition : NSObject
- (instancetype)initWithContentView:(NSView *)contentView bottomConstraint:(NSLayoutConstraint *)constraint;
- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
