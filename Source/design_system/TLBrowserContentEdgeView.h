#import <AppKit/AppKit.h>
#import "Theme.h"

// Rounded visible-page border with loading progress immediately below it.
@interface TLBrowserContentEdgeView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
- (void)setLoading:(BOOL)loading progress:(double)progress;
@end
