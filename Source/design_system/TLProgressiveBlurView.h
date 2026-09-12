#import <AppKit/AppKit.h>
#import "Theme.h"

// A window-anchored, hit-transparent blur with the translucent chat backdrop.
@interface TLProgressiveBlurView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@end
