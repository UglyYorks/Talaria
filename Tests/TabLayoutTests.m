#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"

@interface TLChromeTabView (TabLayoutTesting)
- (NSRect)activeTabRectInRect:(NSRect)rect;
- (NSRect)inactiveHoverPillRectInRect:(NSRect)rect;
- (CGFloat)inactiveLeadingSeparatorCenterXInRect:(NSRect)rect;
@end

@interface TLWorkspaceTabsController (TabSelectionTesting)
- (void)updateSelectionIndicatorAnimated:(BOOL)animated;
- (void)performPendingSelectionAnimation;
- (void)updateSeparatorVisibility;
- (void)chromeTabView:(TLChromeTabView *)tabView didDragWithEvent:(NSEvent *)event;
- (CGFloat)chromeTabView:(TLChromeTabView *)tabView constrainedHorizontalTranslationForEvent:(NSEvent *)event proposedTranslation:(CGFloat)translationX;
- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView;
- (void)chromeTabViewDidRequestCloseOtherTabs:(TLChromeTabView *)tabView;
@end

@interface TLTabContextMenuHarness : NSObject
@property (nonatomic, copy) NSArray<TLWorkspaceTab *> *tabs;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *openedTabIDs;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *closedTabIDs;
@property (nonatomic) NSInteger activeTabID;
@property (nonatomic, weak) TLWorkspaceTabsController *controller;
@property (nonatomic) NSRect contentDragBounds;
@property (nonatomic) NSRect newTabButtonBounds;
@property (nonatomic) CGFloat contentCornerRadius;
@end

@implementation TLTabContextMenuHarness

- (instancetype)init {
  self = [super init];
  if (self) {
    _openedTabIDs = [NSMutableArray array];
    _closedTabIDs = [NSMutableArray array];
  }
  return self;
}

- (NSArray<TLWorkspaceTab *> *)workspaceTabsForTabsController:(TLWorkspaceTabsController *)controller {
  return self.tabs;
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller openActionForTab:(TLWorkspaceTab *)tab {
  return @selector(openTab:);
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller closeActionForTab:(TLWorkspaceTab *)tab {
  return @selector(closeTab:);
}

- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller isTabActive:(TLWorkspaceTab *)tab {
  return tab.tabID == self.activeTabID;
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayTitleForTab:(TLWorkspaceTab *)tab {
  return tab.title;
}

- (NSImage *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayImageForTab:(TLWorkspaceTab *)tab {
  return nil;
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayIconForTab:(TLWorkspaceTab *)tab {
  return @"";
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displaySystemIconNameForTab:(TLWorkspaceTab *)tab {
  return @"";
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayToolTipForTab:(TLWorkspaceTab *)tab {
  return tab.toolTip;
}

- (NSRect)workspaceTabsControllerContentDragBoundsInWindow:(TLWorkspaceTabsController *)controller {
  return self.contentDragBounds;
}

- (NSRect)workspaceTabsControllerNewTabButtonBoundsInWindow:(TLWorkspaceTabsController *)controller {
  return self.newTabButtonBounds;
}

- (BOOL)workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:(TLWorkspaceTabsController *)controller {
  return NO;
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller firstTabEdgeCornerRadiusDidChange:(CGFloat)cornerRadius {
  self.contentCornerRadius = cornerRadius;
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index {
}

- (void)openTab:(NSButton *)sender {
  [self.openedTabIDs addObject:@(sender.tag)];
  self.activeTabID = sender.tag;
  [self.controller reloadTabs];
}

- (void)closeTab:(NSButton *)sender {
  [self.closedTabIDs addObject:@(sender.tag)];
}

@end

static void AssertOffset(TLChromeTabView *tab, CGFloat expected, NSString *context) {
  NSLayoutConstraint *constraint = [tab valueForKey:@"iconCenterYConstraint"];
  if (fabs(constraint.constant - expected) > 0.001) {
    NSLog(@"FAIL %@: expected %g, got %g", context, expected, constraint.constant);
    exit(1);
  }
}

static void AssertClose(CGFloat actual, CGFloat expected, NSString *context) {
  if (fabs(actual - expected) > 0.001) {
    NSLog(@"FAIL %@: expected %g, got %g", context, expected, actual);
    exit(1);
  }
}

static void TestSharedFlareSpace(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *left = [[TLChromeTabView alloc] init];
  TLChromeTabView *right = [[TLChromeTabView alloc] init];
  NSLayoutConstraint *leftWidth = [left.widthAnchor constraintEqualToConstant:palette.tabMaxWidth];
  NSLayoutConstraint *rightWidth = [right.widthAnchor constraintEqualToConstant:palette.tabMaxWidth];
  [controller setValue:[NSMutableArray arrayWithObjects:leftWidth, rightWidth, nil] forKey:@"tabWidthConstraints"];

  [controller updateTabWidthsForAvailableWidth:300.0];
  AssertClose(leftWidth.constant, 156.0, @"two tabs reclaim their tightened shared boundary");
  AssertClose(rightWidth.constant, 156.0, @"tightened flare layout keeps tab widths equal");
  AssertClose(stack.spacing, -(palette.tabFlareRadius + palette.space2), @"neighboring tab bodies sit closer together");
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 300.0, @"tightened tabs leave no unused strip width");

  [controller updateTabWidthsForAvailableWidth:20.0];
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 20.0, @"narrow tabs continue sharing their reduced flares");
}

static void TestHoveredTabSeparators(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *left = [[TLChromeTabView alloc] init];
  TLChromeTabView *middle = [[TLChromeTabView alloc] init];
  TLChromeTabView *right = [[TLChromeTabView alloc] init];
  middle.dragDelegate = (id<TLChromeTabViewDelegate>)controller;
  [controller setValue:[NSMutableArray arrayWithObjects:left, middle, right, nil] forKey:@"tabViews"];
  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];

  [middle mouseEntered:event];
  if (middle.showsLeadingSeparator || right.showsLeadingSeparator) {
    NSLog(@"FAIL hovered tab keeps an adjacent separator visible");
    exit(1);
  }

  [middle mouseExited:event];
  if (!middle.showsLeadingSeparator || !right.showsLeadingSeparator) {
    NSLog(@"FAIL leaving a tab does not restore its adjacent separators");
    exit(1);
  }

  [controller setNewTabButtonHovered:YES];
  if (right.showsTrailingSeparator) {
    NSLog(@"FAIL new-tab hover keeps the final separator visible");
    exit(1);
  }
  [controller setNewTabButtonHovered:NO];
  if (!right.showsTrailingSeparator) {
    NSLog(@"FAIL leaving the new-tab button does not restore the final separator");
    exit(1);
  }
}

static void TestTabContextMenu(TLThemePalette *palette) {
  TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  tab.palette = palette;
  tab.closeable = YES;
  tab.canCloseOtherTabs = YES;

  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];
  NSMenu *menu = [tab menuForEvent:event];
  if (menu.numberOfItems != 2 ||
      ![menu.itemArray[0].title isEqualToString:@"Close"] ||
      ![menu.itemArray[1].title isEqualToString:@"Close Other Tabs"]) {
    NSLog(@"FAIL tab context menu does not contain exactly the expected close actions");
    exit(1);
  }
  if (!menu.itemArray[0].enabled || !menu.itemArray[1].enabled) {
    NSLog(@"FAIL available tab context menu actions are disabled");
    exit(1);
  }

  tab.closeable = NO;
  tab.canCloseOtherTabs = NO;
  menu = [tab menuForEvent:event];
  if (menu.itemArray[0].enabled || menu.itemArray[1].enabled) {
    NSLog(@"FAIL unavailable tab context menu actions remain enabled");
    exit(1);
  }
}

static void TestCloseOtherTabsDispatchesExistingActions(TLThemePalette *palette) {
  TLWorkspaceTab *retainedTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                      tabID:11
                                                      title:@"Retained"
                                                    toolTip:@""
                                                         URL:nil
                                                   closeable:YES];
  TLWorkspaceTab *closedTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser
                                                    tabID:22
                                                    title:@"Closed"
                                                  toolTip:@""
                                                       URL:nil
                                                 closeable:YES];
  TLWorkspaceTab *nonCloseableTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindHistory
                                                           tabID:33
                                                           title:@"Kept"
                                                         toolTip:@""
                                                              URL:nil
                                                        closeable:NO];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.tabs = @[retainedTab, closedTab, nonCloseableTab];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:[[NSStackView alloc] init]
              target:harness
            delegate:(id<TLWorkspaceTabsControllerDelegate>)harness
             palette:palette];
  TLChromeTabView *tabView = [[TLChromeTabView alloc] init];
  tabView.representedObject = retainedTab;

  [controller chromeTabViewDidRequestCloseOtherTabs:tabView];
  if (![harness.openedTabIDs isEqualToArray:@[@11]]) {
    NSLog(@"FAIL close-other-tabs does not activate the right-clicked tab");
    exit(1);
  }
  if (![harness.closedTabIDs isEqualToArray:@[@22]]) {
    NSLog(@"FAIL close-other-tabs does not dispatch only the other closable tabs");
    exit(1);
  }
}

static void TestMouseDownSelectsBeforeMouseUpAndPreservesDragView(TLThemePalette *palette) {
  TLWorkspaceTab *firstTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                   tabID:41
                                                   title:@"First"
                                                 toolTip:@""
                                                      URL:nil
                                                closeable:YES];
  TLWorkspaceTab *secondTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                    tabID:42
                                                    title:@"Second"
                                                  toolTip:@""
                                                       URL:nil
                                                 closeable:YES];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.tabs = @[firstTab, secondTab];
  harness.activeTabID = firstTab.tabID;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:[[NSStackView alloc] init]
              target:harness
            delegate:(id<TLWorkspaceTabsControllerDelegate>)harness
             palette:palette];
  harness.controller = controller;
  [controller reloadTabs];
  TLChromeTabView *pressedTabView = ((NSArray<TLChromeTabView *> *)[controller valueForKey:@"tabViews"])[1];
  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSMakePoint(20.0, 10.0)
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];

  [pressedTabView mouseDown:event];
  if (![harness.openedTabIDs isEqualToArray:@[@42]]) {
    NSLog(@"FAIL tab selection is not dispatched on mouse down");
    exit(1);
  }
  NSArray<TLChromeTabView *> *refreshedTabViews = [controller valueForKey:@"tabViews"];
  if (refreshedTabViews[1] != pressedTabView) {
    NSLog(@"FAIL mouse-down selection replaces the view needed to continue dragging");
    exit(1);
  }

  [pressedTabView mouseUp:event];
  if (harness.openedTabIDs.count != 1) {
    NSLog(@"FAIL tab selection is dispatched again on mouse up");
    exit(1);
  }
}

static void TestClosingActiveTabAnimatesToFallback(TLThemePalette *palette) {
  NSMutableArray<TLWorkspaceTab *> *tabs = [NSMutableArray array];
  for (NSInteger tabID = 1; tabID <= 3; tabID += 1) {
    [tabs addObject:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                          tabID:tabID
                                          title:[NSString stringWithFormat:@"Tab %ld", tabID]
                                        toolTip:@""
                                             URL:nil
                                       closeable:YES]];
  }
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.tabs = tabs;
  harness.activeTabID = 3;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:[[NSStackView alloc] init]
              target:harness
            delegate:(id<TLWorkspaceTabsControllerDelegate>)harness
             palette:palette];
  harness.controller = controller;
  [controller reloadTabs];

  harness.tabs = @[tabs[0], tabs[1]];
  [controller reloadTabs];
  if (![[controller valueForKey:@"hasPendingSelectionAnimation"] boolValue] ||
      [[controller valueForKey:@"pendingSelectionTargetIndex"] unsignedIntegerValue] != NSNotFound) {
    NSLog(@"FAIL closing the active tab does not preserve its selection animation origin");
    exit(1);
  }

  harness.activeTabID = 1;
  [controller reloadTabs];
  if ([[controller valueForKey:@"pendingSelectionTargetIndex"] unsignedIntegerValue] != 0 ||
      ![[controller valueForKey:@"selectionAnimationScheduled"] boolValue]) {
    NSLog(@"FAIL fallback activation does not schedule selection animation after closing a tab");
    exit(1);
  }
  [controller performPendingSelectionAnimation];
}

static void TestTabRemovalUsesClipMaskAndClosesLayoutGap(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  stack.wantsLayer = YES;
  [window.contentView addSubview:stack];
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  TLWorkspaceTab *first = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:71
    title:@"First" toolTip:@"" URL:nil closeable:YES];
  TLWorkspaceTab *second = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:72
    title:@"Second" toolTip:@"" URL:nil closeable:YES];
  harness.tabs = @[first, second];
  harness.activeTabID = first.tabID;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:500];
  TLChromeTabView *closing = ((NSArray *)[controller valueForKey:@"tabViews"])[0];
  TLChromeTabView *surviving = ((NSArray *)[controller valueForKey:@"tabViews"])[1];
  NSRect closingFrame = closing.frame;
  CGFloat survivingStartX = NSMinX(surviving.frame);
  harness.tabs = @[second];
  harness.activeTabID = second.tabID;
  [controller reloadTabs];
  [controller performPendingSelectionAnimation];
  TLChromeTabSelectionView *selection = [controller valueForKey:@"selectionView"];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    now += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    id transition = ((NSArray *)[controller valueForKey:@"removalTransitions"]).firstObject;
    NSView *placeholder = [transition valueForKey:@"placeholderView"];
    CGFloat targetWidth = MAX(0, -stack.spacing);
    CGFloat expectedWidth = (NSWidth(closingFrame) + targetWidth) * 0.5;
    AssertClose(NSWidth(placeholder.frame), expectedWidth, @"closing slot contracts at shared progress");
    AssertClose(closing.lifecycleVisibleWidth, expectedWidth, @"mask exactly matches the moving layout boundary");
    AssertClose(NSWidth(closing.frame), NSWidth(closingFrame), @"content geometry is not scaled");
    AssertClose(NSMinX(selection.selectionFrame), NSMinX(closingFrame), @"background stays in the closing slot");
    AssertClose(NSMinX(surviving.frame), survivingStartX - (NSWidth(closingFrame) - expectedWidth),
                @"neighbor moves with the closing slot");
    if (selection.layer.mask || closing.drawsActiveBackground) {
      NSLog(@"FAIL closing content clips or duplicates the selection background"); exit(1);
    }
    // A metadata-only update must not restart/cancel the transition or replace views.
    second.title = @"Renamed";
    [controller reloadTabs];
    if (((NSArray *)[controller valueForKey:@"tabViews"])[0] != surviving) {
      NSLog(@"FAIL metadata reload replaced the surviving view"); exit(1);
    }
    AssertClose(closing.lifecycleVisibleWidth, expectedWidth, @"metadata update preserves animation progress");
    now += palette.tabLifecycleTransitionDuration;
    [timeline advance];
  }
  if (closing.superview || ((NSArray *)[controller valueForKey:@"removalTransitions"]).count) {
    NSLog(@"FAIL removal completion leaves a view or placeholder behind"); exit(1);
  }
  // Creation prepares before first paint; closing during creation starts from
  // the currently visible mask/opacity and retires the old completion.
  harness.tabs = @[second, first];
  harness.activeTabID = first.tabID;
  [controller reloadTabs];
  TLChromeTabView *inserted = ((NSArray *)[controller valueForKey:@"tabViews"])[1];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(inserted.lifecycleVisibleWidth, NSWidth(inserted.bounds) * palette.tabLifecycleCollapsedWidthRatio,
                @"new tab starts clipped before the first tick");
    AssertClose(inserted.lifecycleContentOpacity, 0.0, @"new tab starts transparent");
    now += palette.tabLifecycleTransitionDuration * 0.25;
    [timeline advance];
    CGFloat interruptedWidth = inserted.lifecycleVisibleWidth;
    CGFloat interruptedOpacity = inserted.lifecycleContentOpacity;
    harness.tabs = @[second];
    harness.activeTabID = second.tabID;
    [controller reloadTabs];
    AssertClose(inserted.lifecycleVisibleWidth, interruptedWidth, @"closing preserves interrupted creation mask");
    AssertClose(inserted.lifecycleContentOpacity, interruptedOpacity, @"closing preserves interrupted creation opacity");
    now += palette.tabLifecycleTransitionDuration * 2;
    [timeline advance];
    if (inserted.superview) { NSLog(@"FAIL interrupted insertion leaves a ghost tab"); exit(1); }
  }
  [timeline finishAllTransitions];

  // Replacing a draft identity removes and inserts in the same render batch.
  // Both must remain alive until the shared lifecycle finishes.
  harness.tabs = @[first, second];
  harness.activeTabID = first.tabID;
  [controller reloadTabs];
  [controller performPendingSelectionAnimation];
  [timeline finishAllTransitions];
  TLChromeTabView *replaced = ((NSArray *)[controller valueForKey:@"tabViews"])[0];
  CGFloat replacedWidth = NSWidth(replaced.frame);
  TLWorkspaceTab *replacement = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:73
    title:@"Persisted draft" toolTip:@"" URL:nil closeable:YES];
  harness.tabs = @[replacement, second];
  harness.activeTabID = replacement.tabID;
  [controller reloadTabs];
  [controller performPendingSelectionAnimation];
  TLChromeTabView *appearing = ((NSArray *)[controller valueForKey:@"tabViews"])[0];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    if (!replaced.superview || ((NSArray *)[controller valueForKey:@"removalTransitions"]).count != 1 ||
        ((NSArray *)[controller valueForKey:@"insertingTabViews"]).count != 1) {
      NSLog(@"FAIL same-batch insertion cancels the closing tab"); exit(1);
    }
    AssertClose(appearing.lifecycleContentOpacity, 0.0, @"same-batch replacement starts hidden");
    now += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    id removal = ((NSArray *)[controller valueForKey:@"removalTransitions"]).firstObject;
    NSView *placeholder = [removal valueForKey:@"placeholderView"];
    CGFloat collapsedWidth = MAX(0, -stack.spacing);
    AssertClose(NSWidth(placeholder.frame), (replacedWidth + collapsedWidth) * 0.5,
                @"same-batch replacement contracts the outgoing slot at shared midpoint");
    AssertClose(replaced.lifecycleVisibleWidth, NSWidth(placeholder.frame),
                @"same-batch replacement keeps the outgoing mask aligned");
    AssertClose(appearing.lifecycleVisibleWidth,
                NSWidth(appearing.frame) * (1.0 + palette.tabLifecycleCollapsedWidthRatio) * 0.5,
                @"same-batch replacement reveals incoming content on the same timeline");
    if (!replaced.superview || appearing.lifecycleContentOpacity <= 0.0) {
      NSLog(@"FAIL replacement does not animate both outgoing and incoming content"); exit(1);
    }
  }
  [timeline finishAllTransitions];
  if (replaced.superview || ((NSArray *)[controller valueForKey:@"removalTransitions"]).count ||
      ((NSArray *)[controller valueForKey:@"insertingTabViews"]).count) {
    NSLog(@"FAIL same-batch replacement leaves lifecycle state behind"); exit(1);
  }
  AssertClose(appearing.lifecycleVisibleWidth, NSWidth(appearing.frame), @"replacement finishes at full content width");
  AssertClose(appearing.lifecycleContentOpacity, 1.0, @"replacement finishes at full content opacity");

  // In a batched close, later removed tabs must move with their own slots while
  // keeping their original content width and clipping at the slot's right edge.
  harness.tabs = @[first, second, replacement];
  harness.activeTabID = replacement.tabID;
  [controller reloadTabs];
  [controller performPendingSelectionAnimation];
  [timeline finishAllTransitions];
  TLChromeTabView *laterClosing = ((NSArray *)[controller valueForKey:@"tabViews"])[1];
  NSRect laterClosingFrame = laterClosing.frame;
  harness.tabs = @[replacement];
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    now += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    id laterRemoval = ((NSArray *)[controller valueForKey:@"removalTransitions"])[1];
    NSView *laterPlaceholder = [laterRemoval valueForKey:@"placeholderView"];
    AssertClose(NSMinX(laterClosing.frame), NSMinX(laterPlaceholder.frame), @"later closing content follows its moving slot");
    AssertClose(NSWidth(laterClosing.frame), NSWidth(laterClosingFrame), @"batched closure does not scale content geometry");
    AssertClose(laterClosing.lifecycleVisibleWidth, NSWidth(laterPlaceholder.frame), @"later closing mask follows slot width");
    if (NSMinX(laterClosing.frame) >= NSMinX(laterClosingFrame)) {
      NSLog(@"FAIL later closing tab did not move with earlier collapsing slot"); exit(1);
    }
  }
  [timeline finishAllTransitions];
  harness.tabs = @[first, replacement];
  harness.activeTabID = replacement.tabID;
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    now += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    TLChromeTabView *retainedActive = ((NSArray *)[controller valueForKey:@"tabViews"])[1];
    AssertClose(NSMinX(selection.selectionFrame), NSMinX(retainedActive.frame) + retainedActive.reorderTranslationX,
                @"selection follows retained active content while a neighbor appears");
  }
  [timeline finishAllTransitions];
  [window close];
}

static void TestDraggedTabOpensInsertionGap(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 400.0, palette.tabHeight)];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.contentDragBounds = stack.bounds;
  harness.newTabButtonBounds = NSMakeRect(385.0, 0, 15.0, palette.tabHeight);
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:(id<TLWorkspaceTabsControllerDelegate>)harness
                                                                                      palette:palette];
  NSMutableArray<TLChromeTabView *> *tabs = [NSMutableArray array];
  for (NSUInteger index = 0; index < 4; index += 1) {
    TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(index * 100.0, 0, 100.0, palette.tabHeight)];
    tab.palette = palette;
    tab.representedObject = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                  tabID:(NSInteger)index + 1
                                                  title:@""
                                                toolTip:@""
                                                     URL:nil
                                               closeable:YES];
    [stack addSubview:tab];
    [tabs addObject:tab];
  }
  [controller setValue:tabs forKey:@"tabViews"];
  TLChromeTabView *draggedTab = tabs[1];
  draggedTab.active = YES;
  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];
  CGFloat finalSlotTranslation = [controller chromeTabView:draggedTab
                        constrainedHorizontalTranslationForEvent:event
                                             proposedTranslation:CGFLOAT_MAX];
  AssertClose(finalSlotTranslation, 200.0, @"drag constraint reaches the final tab slot");
  [draggedTab setValue:@(finalSlotTranslation) forKey:@"dragTranslationX"];

  [controller chromeTabView:draggedTab didDragWithEvent:event];
  TLChromeTabSelectionView *selectionView = [controller valueForKey:@"selectionView"];
  NSUInteger selectionSubviewIndex = [stack.subviews indexOfObjectIdenticalTo:selectionView];
  NSUInteger draggedSubviewIndex = [stack.subviews indexOfObjectIdenticalTo:draggedTab];
  NSUInteger neighborSubviewIndex = [stack.subviews indexOfObjectIdenticalTo:tabs[2]];
  if (selectionSubviewIndex <= neighborSubviewIndex || draggedSubviewIndex <= selectionSubviewIndex) {
    NSLog(@"FAIL dragged tab and its selection slab are not promoted above neighboring tabs");
    exit(1);
  }
  AssertClose(tabs[0].reorderTranslationX, 0.0, @"tab before the source stays in place");
  AssertClose(tabs[2].reorderTranslationX, -100.0, @"first crossed tab shifts into the open slot");
  AssertClose(tabs[3].reorderTranslationX, -100.0, @"second crossed tab shifts to leave a drop gap");
  if (!tabs[2].showsLeadingSeparator) {
    NSLog(@"FAIL separator does not return where the dragged tab left its source slot");
    exit(1);
  }
  if (tabs[3].showsTrailingSeparator) {
    NSLog(@"FAIL separator remains visible beside the prospective drop gap");
    exit(1);
  }

  [draggedTab setValue:@110.0 forKey:@"dragTranslationX"];
  [controller chromeTabView:draggedTab didDragWithEvent:event];
  if (!tabs[2].showsLeadingSeparator || tabs[3].showsLeadingSeparator) {
    NSLog(@"FAIL internal drop gap does not restore its source separator and hide its destination separator");
    exit(1);
  }

  [controller chromeTabViewDidEndDragging:draggedTab];
  if ([stack.subviews indexOfObjectIdenticalTo:selectionView] != 0) {
    NSLog(@"FAIL selection slab does not return beneath tabs after dropping");
    exit(1);
  }
  AssertClose(tabs[2].reorderTranslationX, 0.0, @"drop clears first sibling reorder translation");
  AssertClose(tabs[3].reorderTranslationX, 0.0, @"drop clears second sibling reorder translation");
  if (tabs[2].showsLeadingSeparator || !tabs[3].showsTrailingSeparator) {
    NSLog(@"FAIL normal separator visibility is not restored after dropping");
    exit(1);
  }
  CGFloat firstSlotTranslation = [controller chromeTabView:draggedTab
                        constrainedHorizontalTranslationForEvent:event
                                             proposedTranslation:-CGFLOAT_MAX];
  [draggedTab setValue:@(firstSlotTranslation) forKey:@"dragTranslationX"];
  [controller chromeTabView:draggedTab didDragWithEvent:event];
  AssertClose([[controller valueForKey:@"draggedCurrentIndex"] unsignedIntegerValue], 0,
              @"second tab can enter the first slot at the left drag boundary");
  AssertClose(tabs[0].reorderTranslationX, 100.0, @"first tab moves aside for incoming tab");
  AssertClose(draggedTab.leadingFlareOutset, palette.space0,
              @"incoming tab connects its leading edge to the content at the first slot");
  AssertClose(harness.contentCornerRadius, palette.space0,
              @"content corner connects when the second tab reaches the left edge");
  [controller chromeTabViewDidEndDragging:draggedTab];
  draggedTab.active = NO;
  TLChromeTabView *lastTab = tabs.lastObject;
  lastTab.active = YES;
  [lastTab setValue:@(-300.0) forKey:@"dragTranslationX"];
  [controller chromeTabView:lastTab didDragWithEvent:event];
  AssertClose([[controller valueForKey:@"draggedCurrentIndex"] unsignedIntegerValue], 0,
              @"last tab can also enter the first slot");
  AssertClose(harness.contentCornerRadius, palette.space0, @"last tab connects the content corner");
  [lastTab setValue:@(-275.0) forKey:@"dragTranslationX"];
  [controller chromeTabView:lastTab didDragWithEvent:event];
  AssertClose(harness.contentCornerRadius, palette.space5, @"content corner restores away from the edge");
  AssertClose(lastTab.leadingFlareOutset, palette.tabFlareRadius, @"tab flare restores away from the edge");
  [controller chromeTabViewDidEndDragging:lastTab];
}

static void TestInactiveFirstTabPadding(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *first = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  first.palette = palette;
  first.active = NO;
  TLChromeTabView *second = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  [controller setValue:[NSMutableArray arrayWithObjects:first, second, nil] forKey:@"tabViews"];

  [controller updateEdgeAttachmentState];
  NSLayoutConstraint *leading = [first valueForKey:@"iconLeadingConstraint"];
  AssertClose(first.leadingFlareOutset, palette.space0, @"first inactive tab does not reserve an impossible leading flare");
  AssertClose(leading.constant,
              palette.tabIconLeadingInset - palette.tabFlareRadius,
              @"first inactive tab uses the same left content padding as the selected state");

  NSRect hoverRect = [first inactiveHoverPillRectInRect:first.bounds];
  AssertClose(NSMinX(hoverRect), palette.tabFlareRadius, @"inactive hover excludes the leading flare width");
  AssertClose(NSMaxX(hoverRect), NSWidth(first.bounds) - palette.tabFlareRadius,
              @"inactive hover excludes the trailing flare width");
}

static void TestInactiveSeparatorCentering(TLThemePalette *palette) {
  CGFloat width = palette.tabMaxWidth;
  CGFloat overlap = TLChromeTabInterTabOverlapForWidth(width, palette);
  CGFloat flareOutset = MIN(palette.tabFlareRadius, width * 0.18);
  TLChromeTabView *right = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, width, palette.tabHeight)];
  right.palette = palette;

  CGFloat leftHandleTrailingX = width - flareOutset;
  CGFloat rightFrameX = width - overlap;
  CGFloat rightHandleLeadingX = rightFrameX + flareOutset;
  CGFloat expectedWorldCenterX = (leftHandleTrailingX + rightHandleLeadingX) * 0.5;
  CGFloat actualWorldCenterX = rightFrameX + [right inactiveLeadingSeparatorCenterXInRect:right.bounds];
  AssertClose(actualWorldCenterX, expectedWorldCenterX,
              @"inactive separator is centered between neighboring tab handles");

  if (palette.dark) {
    TLChromeTabView *left = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, width, palette.tabHeight)];
    left.palette = palette;
    left.icon = @"\U0001F41F";
    left.title = @"First tab";
    right.frame = NSMakeRect(rightFrameX, 0, width, palette.tabHeight);
    right.icon = @"\U0001F4AC";
    right.title = @"Second tab";
    right.showsLeadingSeparator = YES;
    NSView *strip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width * 2.0 - overlap, palette.tabHeight)];
    strip.wantsLayer = YES;
    strip.layer.backgroundColor = TLCGColor(palette.sidebarSurface);
    [strip addSubview:left];
    [strip addSubview:right];
    NSBitmapImageRep *preview = [strip bitmapImageRepForCachingDisplayInRect:strip.bounds];
    [strip cacheDisplayInRect:strip.bounds toBitmapImageRep:preview];
    [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:@"/tmp/talaria-centered-tab-separator.png" atomically:YES];
  }
}

static void TestInactiveDecorationFades(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.tabMaxWidth, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:window.contentView.bounds];
  tab.palette = palette;
  tab.showsLeadingSeparator = YES;
  [window.contentView addSubview:tab];
  [tab layoutSubtreeIfNeeded];
  CALayer *separator = [tab valueForKey:@"leadingSeparatorLayer"];
  CALayer *hover = [tab valueForKey:@"inactiveHoverBackgroundLayer"];

  tab.showsLeadingSeparator = NO;
  AssertClose(separator.opacity, 0.0, @"separator fade-out updates its final state");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *fade = (CABasicAnimation *)[separator animationForKey:@"tab-decoration-fade"];
    AssertClose(fade.duration, palette.tabSeparatorFadeDuration, @"separator fades out over the themed duration");
  }
  tab.showsLeadingSeparator = YES;
  AssertClose(separator.opacity, 1.0, @"separator fade-in updates its final state");

  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:window.windowNumber
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];
  [tab mouseEntered:event];
  AssertClose(hover.opacity, 1.0, @"hover background fade-in updates its final state");
  AssertClose(separator.opacity, 0.0, @"hover fades out the separator");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *fade = (CABasicAnimation *)[hover animationForKey:@"tab-decoration-fade"];
    AssertClose(fade.duration, palette.tabHoverFadeDuration, @"hover background fades in over the themed duration");
  }
  [tab mouseExited:event];
  AssertClose(hover.opacity, 0.0, @"hover background fade-out updates its final state");
  AssertClose(separator.opacity, 1.0, @"hover exit fades the separator back in");
  [window close];
}

static void TestSelectionSlabSlidesBetweenTabs(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.tabMaxWidth * 2.0, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  stack.wantsLayer = YES;
  [window.contentView addSubview:stack];
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette transitionCoordinator:timeline];
  TLChromeTabView *left = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, palette.tabMaxWidth, palette.tabHeight)];
  TLChromeTabView *right = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(palette.tabMaxWidth, 0,
                                                                            palette.tabMaxWidth,
                                                                            palette.tabHeight)];
  left.active = YES;
  right.active = NO;
  [stack addSubview:left];
  [stack addSubview:right];
  [controller setValue:[NSMutableArray arrayWithObjects:left, right, nil] forKey:@"tabViews"];

  [controller updateSelectionIndicatorAnimated:NO];
  TLChromeTabSelectionView *selectionView = [controller valueForKey:@"selectionView"];
  if (selectionView.hidden || !NSEqualRects(selectionView.selectionFrame, left.frame)) {
    NSLog(@"FAIL selection slab does not begin behind the active tab");
    exit(1);
  }

  left.active = NO;
  right.active = YES;
  [controller setValue:[NSValue valueWithRect:left.frame] forKey:@"pendingSelectionStartFrame"];
  [controller setValue:@YES forKey:@"hasPendingSelectionAnimation"];
  [controller performPendingSelectionAnimation];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMinX(selectionView.selectionFrame), NSMinX(left.frame), @"selection begins at previous tab");
    now = palette.tabSelectionSlideDuration * 0.5;
    [timeline advance];
    AssertClose(NSMinX(selectionView.selectionFrame), (NSMinX(left.frame) + NSMinX(right.frame)) * 0.5,
                @"selection progresses on the shared clock");
    [controller updateSelectionIndicatorAnimated:NO];
    if (![timeline hasTransitionForKey:@"selection"]) {
      NSLog(@"FAIL duplicate reload cancels the selection transition"); exit(1);
    }
    now = palette.tabSelectionSlideDuration;
    [timeline advance];
  }
  if (!NSEqualRects(selectionView.selectionFrame, right.frame) || timeline.hasTransitions) {
    NSLog(@"FAIL selection transition does not finish behind the active tab"); exit(1);
  }

  [right setValue:@35.0 forKey:@"dragTranslationX"];
  NSEvent *dragEvent = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                          location:NSZeroPoint
                                     modifierFlags:0
                                         timestamp:0
                                      windowNumber:window.windowNumber
                                           context:nil
                                           subtype:0
                                             data1:0
                                             data2:0];
  [controller chromeTabView:right didDragWithEvent:dragEvent];
  AssertClose(NSMinX(selectionView.selectionFrame), NSMinX(right.frame) + 35.0,
              @"selection slab follows the active tab while it is dragged");
  [window close];
}

static void TestLongSelectionJumpStartsNearDestination(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.tabMaxWidth * 5.0, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  stack.wantsLayer = YES;
  [window.contentView addSubview:stack];
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette transitionCoordinator:timeline];
  NSMutableArray<TLChromeTabView *> *tabs = [NSMutableArray array];
  for (NSUInteger index = 0; index < 5; index += 1) {
    TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(index * palette.tabMaxWidth,
                                                                            0,
                                                                            palette.tabMaxWidth,
                                                                            palette.tabHeight)];
    tab.active = index == 0;
    [stack addSubview:tab];
    [tabs addObject:tab];
  }
  [controller setValue:tabs forKey:@"tabViews"];
  [controller updateSelectionIndicatorAnimated:NO];
  tabs.firstObject.active = NO;
  tabs.lastObject.active = YES;
  [controller setValue:[NSValue valueWithRect:tabs.firstObject.frame] forKey:@"pendingSelectionStartFrame"];
  [controller setValue:@0 forKey:@"pendingSelectionStartIndex"];
  [controller setValue:@4 forKey:@"pendingSelectionTargetIndex"];
  [controller setValue:@YES forKey:@"hasPendingSelectionAnimation"];
  [controller updateSeparatorVisibility];
  if (!tabs[2].showsLeadingSeparator || !tabs[3].showsLeadingSeparator) {
    NSLog(@"FAIL separators disappear inside the selection transition path");
    exit(1);
  }

  [controller performPendingSelectionAnimation];
  TLChromeTabSelectionView *selectionView = [controller valueForKey:@"selectionView"];
  if (selectionView.layer.zPosition <= tabs[2].layer.zPosition ||
      selectionView.layer.zPosition >= tabs.lastObject.layer.zPosition) {
    NSLog(@"FAIL selection background must cover inactive separators beneath selected content");
    exit(1);
  }
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMidX(selectionView.selectionFrame), NSMidX(tabs[3].frame),
                @"long selection jump starts one tab away from its destination");
  }
  [timeline finishAllTransitions];
  [window close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    for (NSNumber *themeValue in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      TLThemePreference theme = themeValue.integerValue;
      TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 36)];
      tab.palette = [TLThemePalette paletteForPreference:theme];
      tab.icon = @"\U0001F310";
      AssertOffset(tab, tab.palette.space2, @"Emoji fallback keeps its offset");

      tab.image = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
      AssertOffset(tab, tab.palette.space0, @"Loaded favicon is vertically centered");
      tab.active = YES;
      AssertOffset(tab, tab.palette.space0, @"Active favicon stays centered");
      tab.palette = [TLThemePalette paletteForPreference:theme];
      AssertOffset(tab, tab.palette.space0, @"Theme refresh preserves favicon alignment");

      tab.image = nil;
      AssertOffset(tab, tab.palette.space2, @"Removing favicon restores emoji positioning");
      tab.systemIconName = @"clock";
      AssertOffset(tab, tab.palette.space0, @"System icon positioning is unchanged");
      NSRect activeRect = [tab activeTabRectInRect:tab.bounds];
      AssertClose(NSMinY(activeRect), NSMinY(tab.bounds), @"shorter active tab stays attached to content");
      AssertClose(NSHeight(activeRect),
                  NSHeight(tab.bounds) - tab.palette.tabActiveHeightReduction,
                  @"active tab height uses the theme reduction");
      TestSharedFlareSpace(tab.palette);
      TestHoveredTabSeparators(tab.palette);
      TestTabContextMenu(tab.palette);
      TestCloseOtherTabsDispatchesExistingActions(tab.palette);
      TestMouseDownSelectsBeforeMouseUpAndPreservesDragView(tab.palette);
      TestClosingActiveTabAnimatesToFallback(tab.palette);
      TestTabRemovalUsesClipMaskAndClosesLayoutGap(tab.palette);
      TestDraggedTabOpensInsertionGap(tab.palette);
      TestInactiveFirstTabPadding(tab.palette);
      TestInactiveSeparatorCentering(tab.palette);
      TestInactiveDecorationFades(tab.palette);
      TestSelectionSlabSlidesBetweenTabs(tab.palette);
      TestLongSelectionJumpStartsNearDestination(tab.palette);

      NSLayoutConstraint *leading = [tab valueForKey:@"iconLeadingConstraint"];
      tab.leadingFlareOutset = tab.palette.space0;
      [tab layoutSubtreeIfNeeded];
      AssertClose(leading.constant,
                  tab.palette.tabIconLeadingInset - tab.palette.tabFlareRadius,
                  @"edge-connected first tab keeps the standard body-to-content padding");

      TLChromeTabView *neighbor = [[TLChromeTabView alloc] init];
      neighbor.active = YES;
      AssertClose(neighbor.layer.zPosition, 1.0, @"selected tab draws above overlapping neighbors");
      neighbor.active = NO;
      AssertClose(neighbor.layer.zPosition, 0.0, @"inactive tab returns to the strip plane");
    }
    NSLog(@"TabLayoutTests passed");
  }
  return 0;
}
