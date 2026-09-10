#import <AppKit/AppKit.h>
#import "Theme.h"

// A non-interactive privacy indicator; it must never toggle a sidebar.
@interface TLIncognitoPill : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@end
