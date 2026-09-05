#import <AppKit/AppKit.h>
#import "Theme.h"
#import "WorkspaceState.h"
#import "design_system/TLTransitionCoordinator.h"

NS_ASSUME_NONNULL_BEGIN

@class TLWorkspaceTabsController;
@class TLChromeTabSelectionView;

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
@property (nonatomic, strong, readonly) TLTransitionCoordinator *transitionCoordinator;
@property (nonatomic, strong, readonly) TLChromeTabSelectionView *selectionView;
// tabStack.trailing = newTabButton.leading + constant; animated with insertion.
@property (nonatomic, strong, nullable) NSLayoutConstraint *createTabButtonSpacingConstraint;
@property (nonatomic, copy, nullable) void (^animationActivityChanged)(BOOL animating);

- (instancetype)initWithTabStack:(NSStackView *)tabStack
                          target:(nullable id)target
                        delegate:(nullable id<TLWorkspaceTabsControllerDelegate>)delegate
                          palette:(TLThemePalette *)palette;
- (instancetype)initWithTabStack:(NSStackView *)tabStack
                          target:(nullable id)target
                        delegate:(nullable id<TLWorkspaceTabsControllerDelegate>)delegate
                         palette:(TLThemePalette *)palette
           transitionCoordinator:(TLTransitionCoordinator *)transitionCoordinator;
- (void)reloadTabs;
- (void)setNewTabButtonHovered:(BOOL)hovered;
- (void)updateTabWidthsForAvailableWidth:(CGFloat)availableWidth;
- (void)updateEdgeAttachmentState;
- (void)setControlsEnabled:(BOOL)enabled disabledOpacity:(CGFloat)disabledOpacity;

@end

NS_ASSUME_NONNULL_END
