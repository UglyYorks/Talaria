#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN
/// Adaptive shell shared by settings-style workspaces. At narrow widths the
/// sidebar becomes a page menu, without imposing a minimum window width.
@interface TLSettingsWorkspaceView : TLTokenView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL showsSidebar;
@property (nonatomic, strong, readonly) NSSegmentedControl *sectionTabs;
@property (nonatomic, strong, readonly) TLTokenView *sidebar;
@property (nonatomic, strong, readonly) NSView *header;
@property (nonatomic, strong, readonly) NSView *pageHost;
@property (nonatomic, strong, readonly) TLTokenView *footer;
@property (nonatomic, strong, readonly) NSPopUpButton *pageMenu;
@property (nonatomic, strong, readonly) NSTextField *pageTitle;
@property (nonatomic, strong, readonly) NSTextField *pageDescription;
@end
NS_ASSUME_NONNULL_END
