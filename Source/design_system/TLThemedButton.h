#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
/// Native button behavior and geometry with explicit palette text and symbol colors.
@interface TLThemedButton : NSButton
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL primary;
@end
NS_ASSUME_NONNULL_END
