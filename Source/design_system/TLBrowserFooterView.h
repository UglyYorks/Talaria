#import <AppKit/AppKit.h>
#import "Theme.h"

// Uniform footer blur with normalized edges and an inverse rounded page cutout.
@interface TLBrowserFooterView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@end
