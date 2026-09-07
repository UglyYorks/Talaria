#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
NSBezierPath *TLNotchSurfacePath(NSRect rect, TLThemePalette *palette);

// Shared top-pinned notch shape for the compact overlay and expanded composer.
@interface TLNotchSurfaceView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@end
NS_ASSUME_NONNULL_END
