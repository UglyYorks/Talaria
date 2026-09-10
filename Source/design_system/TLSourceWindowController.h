#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLSourceWindowController : NSWindowController
+ (void)showText:(NSString *)text title:(NSString *)title palette:(TLThemePalette *)palette;
+ (void)applyPaletteToOpenWindows:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
