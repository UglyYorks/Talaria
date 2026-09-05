#import <AppKit/AppKit.h>
#import "Theme.h"
@class TLTokenView, TLChromeTabSelectionView;

NS_ASSUME_NONNULL_BEGIN
// One hit-transparent perimeter around the union of content and selected tab.
@interface TLWorkspaceOutlineView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, weak) TLTokenView *contentView;
@property (nonatomic, weak) TLChromeTabSelectionView *selectionView;
- (void)updateOutline;
@end
NS_ASSUME_NONNULL_END
