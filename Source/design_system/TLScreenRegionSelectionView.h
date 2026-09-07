#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
// Covers the full display, including the space alongside the notch, without taking typing focus.
@interface TLScreenRegionSelectionPanel : NSPanel
@end

@interface TLScreenRegionSelectionView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, readonly) NSRect selectionRect;
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSRect screenRect);
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);
- (void)resetSelection;
@end
NS_ASSUME_NONNULL_END
