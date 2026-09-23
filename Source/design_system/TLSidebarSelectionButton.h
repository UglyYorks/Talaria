#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// A selectable text row for sidebar tabs and lists.
@interface TLSidebarSelectionButton : NSButton
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic) BOOL compact;
@end

NS_ASSUME_NONNULL_END
