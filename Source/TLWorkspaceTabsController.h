#import <AppKit/AppKit.h>
#import "Theme.h"
#import "WorkspaceState.h"

NS_ASSUME_NONNULL_BEGIN

@class TLWorkspaceTabsController;

@protocol TLWorkspaceTabsControllerDelegate <NSObject>

- (NSArray<TLWorkspaceTab *> *)workspaceTabsForTabsController:(TLWorkspaceTabsController *)controller;
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller isTabActive:(TLWorkspaceTab *)tab;
- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayTitleForTab:(TLWorkspaceTab *)tab;
- (nullable NSImage *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayImageForTab:(TLWorkspaceTab *)tab;
- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayIconForTab:(TLWorkspaceTab *)tab;
- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displaySystemIconNameForTab:(TLWorkspaceTab *)tab;
- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayToolTipForTab:(TLWorkspaceTab *)tab;
- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller openActionForTab:(TLWorkspaceTab *)tab;
- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller closeActionForTab:(TLWorkspaceTab *)tab;
- (NSRect)workspaceTabsControllerContentDragBoundsInWindow:(TLWorkspaceTabsController *)controller;
- (NSRect)workspaceTabsControllerNewTabButtonBoundsInWindow:(TLWorkspaceTabsController *)controller;
- (BOOL)workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:(TLWorkspaceTabsController *)controller;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller firstTabEdgeCornerRadiusDidChange:(CGFloat)cornerRadius;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index;

@end

@interface TLWorkspaceTabsController : NSObject

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, weak, nullable) id<TLWorkspaceTabsControllerDelegate> delegate;

- (instancetype)initWithTabStack:(NSStackView *)tabStack
                          target:(nullable id)target
                        delegate:(nullable id<TLWorkspaceTabsControllerDelegate>)delegate
                         palette:(TLThemePalette *)palette;
- (void)reloadTabs;
- (void)updateTabWidthsForAvailableWidth:(CGFloat)availableWidth;
- (void)updateEdgeAttachmentState;
- (void)setControlsEnabled:(BOOL)enabled disabledOpacity:(CGFloat)disabledOpacity;

@end

NS_ASSUME_NONNULL_END
