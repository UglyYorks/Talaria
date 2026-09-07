#import "Theme.h"
NS_ASSUME_NONNULL_BEGIN
/// Compact action groups that wrap instead of imposing a window minimum width.
@interface TLWrappingActionView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
- (instancetype)initWithViews:(NSArray<NSView *> *)views palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
