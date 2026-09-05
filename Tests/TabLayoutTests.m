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
- (void)mouseExited:(NSEvent *)event;
- (void)updateSelectionIndicatorAnimated:(BOOL)animated;
- (void)performPendingSelectionAnimation;
- (void)updateSeparatorVisibility;
- (void)chromeTabView:(TLChromeTabView *)tabView didDragWithEvent:(NSEvent *)event;
- (CGFloat)chromeTabView:(TLChromeTabView *)tabView constrainedHorizontalTranslationForEvent:(NSEvent *)event proposedTranslation:(CGFloat)translationX;
- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView;
- (void)chromeTabViewDidRequestCloseOtherTabs:(TLChromeTabView *)tabView;
@end

@interface TLTabPointerWindow : NSWindow
@property (nonatomic) NSPoint testPointer;
@end
@implementation TLTabPointerWindow
- (NSPoint)mouseLocationOutsideOfEventStream { return self.testPointer; }
- (BOOL)isVisible { return YES; }
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
@property (nonatomic) BOOL connectsContentEdge;
@property (nonatomic) BOOL commitsMoves;
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
  NSView *button = controller.createTabButtonSpacingConstraint.secondItem;
  if ([button isKindOfClass:NSView.class]) return [button convertRect:button.bounds toView:nil];
  return self.newTabButtonBounds;
}

- (BOOL)workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:(TLWorkspaceTabsController *)controller {
  return self.connectsContentEdge;
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller firstTabEdgeCornerRadiusDidChange:(CGFloat)cornerRadius {
  self.contentCornerRadius = cornerRadius;
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index {
  if (!self.commitsMoves) return;
  NSMutableArray *tabs = [self.tabs mutableCopy];
  NSUInteger source = [tabs indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *candidate, NSUInteger idx, BOOL *stop) {
    return candidate.tabID == tab.tabID;
  }];
  [tabs removeObjectAtIndex:source];
  [tabs insertObject:tab atIndex:index];
  self.tabs = tabs;
  [controller reloadTabs];
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
  expected -= tab.palette.tabContentVerticalOffset;
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
  AssertClose(stack.spacing, -(palette.tabFlareRadius + palette.tabInterTabTightening), @"neighboring tabs use the shared spacing token");
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 300.0, @"tightened tabs leave no unused strip width");

  [controller updateTabWidthsForAvailableWidth:20.0];
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 20.0, @"narrow tabs continue sharing their reduced flares");
}

static void TestHoveredTabSeparators(TLThemePalette *palette) {
  TLTabPointerWindow *window = [[TLTabPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, palette.tabHeight)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testPointer = NSMakePoint(-20, -20);
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *left = [[TLChromeTabView alloc] init];
  TLChromeTabView *middle = [[TLChromeTabView alloc] init];
  TLChromeTabView *right = [[TLChromeTabView alloc] init];
  middle.dragDelegate = (id<TLChromeTabViewDelegate>)controller;
  middle.frame = NSMakeRect(100, 0, 100, palette.tabHeight);
  [window.contentView addSubview:middle];
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

  window.testPointer = NSMakePoint(150, palette.tabHeight * 0.5);
  [middle mouseEntered:event];
  if (middle.showsLeadingSeparator || right.showsLeadingSeparator) {
    NSLog(@"FAIL hovered tab keeps an adjacent separator visible");
    exit(1);
  }

  window.testPointer = NSMakePoint(-20, -20);
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
  [window close];
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

static void TestManyTabsFitWithoutExpandingWindow(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  [window.contentView addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:window.contentView.trailingAnchor],
    [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [stack.heightAnchor constraintEqualToConstant:palette.tabHeight],
  ]];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return 0; } automaticallyAdvances:NO];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  [controller updateTabWidthsForAvailableWidth:400];
  NSMutableArray *models = [NSMutableArray array];
  NSSize originalWindowSize = window.frame.size;
  for (NSInteger index = 1; index <= 40; index++) {
    [models addObject:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:index
      title:@"A long tab title that must be clipped" toolTip:@"" URL:nil closeable:YES]];
    harness.tabs = models.copy;
    harness.activeTabID = index;
    [controller reloadTabs];
    if (NSWidth(stack.frame) > 400.001) {
      NSLog(@"FAIL insertion briefly expands the strip before its width update"); exit(1);
    }
    [controller updateTabWidthsForAvailableWidth:400];
    [timeline finishAllTransitions];
    [window.contentView layoutSubtreeIfNeeded];
    if (window.contentView.fittingSize.width > 400.001 || NSWidth(stack.frame) > 400.001) {
      NSLog(@"FAIL %ld tabs impose an oversized strip: fitting %@ actual %@", (long)index,
        NSStringFromSize(window.contentView.fittingSize), NSStringFromRect(stack.frame)); exit(1);
    }
    AssertClose(NSWidth(window.frame), originalWindowSize.width, @"adding tabs cannot widen the window");
  }
  NSArray<TLChromeTabView *> *views = [controller valueForKey:@"tabViews"];
  if (NSWidth(views.lastObject.frame) >= palette.tabMinWidth) {
    NSLog(@"FAIL crowded tab handlers must shrink below their preferred width"); exit(1);
  }
  for (TLChromeTabView *view in views) {
    view.icon = @"\U0001F41F";
    [view setValue:@YES forKey:@"hovered"];
    view.title = @"Crowded tab with an icon and close button";
  }
  [controller updateTabWidthsForAvailableWidth:200];
  [window.contentView layoutSubtreeIfNeeded];
  if (NSWidth(stack.frame) > 200.001) {
    NSLog(@"FAIL icon and close controls prevent crowded tabs from shrinking"); exit(1);
  }
  [controller updateTabWidthsForAvailableWidth:0];
  AssertClose(NSWidth(stack.frame), 0, @"no available width collapses the strip instead of expanding the window");
  [window close];
}

static void TestClosePreservesWidthsUntilPointerLeaves(TLThemePalette *palette) {
  TLTabPointerWindow *window = [[TLTabPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, palette.tabHeight)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:stack];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  NSMutableArray *models = [NSMutableArray array];
  for (NSInteger index = 1; index <= 4; index++) {
    [models addObject:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:index
      title:@"Tab" toolTip:@"" URL:nil closeable:YES]];
  }
  harness.tabs = models.copy;
  harness.activeTabID = 1;
  __block NSTimeInterval restorationTime = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return restorationTime; } automaticallyAdvances:NO];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  [controller reloadTabs];
  // Keep the initial equal widths pixel-aligned so preservation checks do not
  // compare different AppKit rounding of neighboring fractional-width frames.
  [controller updateTabWidthsForAvailableWidth:4 * 108 - 3 * TLChromeTabInterTabOverlapForWidth(palette.tabMaxWidth, palette)];
  NSArray<TLChromeTabView *> *views = [[controller valueForKey:@"tabViews"] copy];
  CGFloat width = NSWidth(views[1].frame);
  window.testPointer = [views[1] convertPoint:NSMakePoint(width * 0.5, palette.tabHeight * 0.5) toView:nil];
  [views[1] updateTrackingAreas];
  NSButton *close = [views[1] valueForKey:@"closeButton"];
  [views[1] layoutSubtreeIfNeeded];
  NSPoint closePoint = [close convertPoint:NSMakePoint(NSMidX(close.bounds), NSMidY(close.bounds)) toView:nil];
  window.testPointer = closePoint;
  harness.tabs = @[models[0], models[2], models[3]];
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:400];
  [timeline finishAllTransitions];
  AssertClose(NSWidth(views[2].frame), width, @"closing a tab preserves surviving widths under the pointer");
  NSButton *nextClose = [views[2] valueForKey:@"closeButton"];
  [views[2] layoutSubtreeIfNeeded];
  NSPoint nextClosePoint = [nextClose convertPoint:NSMakePoint(NSMidX(nextClose.bounds), NSMidY(nextClose.bounds)) toView:nil];
  AssertClose(nextClosePoint.x, closePoint.x, @"next close button arrives under the unchanged pointer");
  NSTrackingArea *area = [controller valueForKey:@"widthPreservationTrackingArea"];
  harness.tabs = @[models[0], models[3]];
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:400];
  AssertClose(NSWidth(views[3].frame), width, @"repeated close keeps the same widths");
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:400];
  AssertClose(NSWidth(views[3].frame), width, @"metadata refresh cannot expand held tabs");
  if (area != [controller valueForKey:@"widthPreservationTrackingArea"]) {
    NSLog(@"FAIL shrinking tabs must retain the original hover area"); exit(1);
  }
  window.testPointer = NSMakePoint(410, -10);
  NSEvent *exitEvent = [NSEvent enterExitEventWithType:NSEventTypeMouseExited location:window.testPointer
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
  [controller mouseExited:exitEvent];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    if (![timeline hasTransitionForKey:@"lifecycle"] || !views[2].superview) {
      NSLog(@"FAIL pointer exit must not finish the closing animation"); exit(1);
    }
    [controller updateTabWidthsForAvailableWidth:400];
    restorationTime += palette.tabClosingTransitionDuration * 0.5;
    [timeline advance];
    if (![timeline hasTransitionForKey:@"lifecycle"] || !views[2].superview) {
      NSLog(@"FAIL closing tab must remain visible until its duration elapses"); exit(1);
    }
    AssertClose(NSWidth(views[3].frame), width, @"width restoration waits for closing to finish");
    restorationTime += palette.tabClosingTransitionDuration * 0.5;
    [timeline advance];
    if ([timeline hasTransitionForKey:@"lifecycle"] || views[2].superview ||
        ![timeline hasTransitionForKey:@"width-restoration"]) {
      NSLog(@"FAIL closure must complete before starting deferred width restoration"); exit(1);
    }
    AssertClose(NSWidth(views[3].frame), width, @"leaving the strip does not jump widths");
    restorationTime += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    AssertClose(NSWidth(views[3].frame), (width + palette.tabMaxWidth) * 0.5,
                @"released widths interpolate over the lifecycle duration");
    [controller updateTabWidthsForAvailableWidth:400];
    AssertClose(NSWidth(views[3].frame), (width + palette.tabMaxWidth) * 0.5,
                @"layout refresh cannot snap an in-flight width restoration");
  }
  [timeline finishAllTransitions];
  AssertClose(NSWidth(views[3].frame), palette.tabMaxWidth, @"leaving the strip restores normal tab width calculation");
  if ([window.contentView.trackingAreas containsObject:area]) {
    NSLog(@"FAIL leaving strip must remove temporary width tracking"); exit(1);
  }
  // A keyboard/programmatic close outside the strip must not create a hold.
  harness.tabs = models.copy;
  [controller reloadTabs]; [timeline finishAllTransitions];
  [controller updateTabWidthsForAvailableWidth:400];
  harness.tabs = @[models[0], models[2], models[3]];
  [controller reloadTabs]; [controller updateTabWidthsForAvailableWidth:400];
  [timeline finishAllTransitions];
  NSArray *constraints = [controller valueForKey:@"tabWidthConstraints"];
  AssertClose(((NSLayoutConstraint *)constraints.firstObject).constant,
              (400 + 2 * TLChromeTabInterTabOverlapForWidth(palette.tabMaxWidth, palette)) / 3,
              @"closing outside the strip immediately recalculates widths");
  TLChromeTabView *beforeClosed = ((NSArray *)[controller valueForKey:@"tabViews"])[0];
  window.testPointer = [beforeClosed convertPoint:NSMakePoint(30, palette.tabHeight * 0.5) toView:nil];
  [beforeClosed updateTrackingAreas];
  if (!beforeClosed.hovered) { NSLog(@"FAIL pointer inside tab should hover it"); exit(1); }
  // Lose the exit event, then close a different, non-hovered tab.
  window.testPointer = NSMakePoint(390, -20);
  harness.tabs = @[models[0], models[3]];
  [controller reloadTabs]; [timeline finishAllTransitions];
  [beforeClosed updateTrackingAreas];
  [beforeClosed mouseEntered:exitEvent];
  NSButton *staleClose = [beforeClosed valueForKey:@"closeButton"];
  CALayer *staleHover = [beforeClosed valueForKey:@"inactiveHoverBackgroundLayer"];
  if (beforeClosed.hovered || !staleClose.hidden || staleHover.opacity != 0) {
    NSLog(@"FAIL closing a non-hovered tab must not leave its predecessor hovered after stale entry events"); exit(1);
  }
  NSTrackingArea *tabTracking = [beforeClosed valueForKey:@"trackingArea"];
  if (!NSContainsRect(beforeClosed.bounds, tabTracking.rect) ||
      (tabTracking.options & NSTrackingInVisibleRect)) {
    NSLog(@"FAIL tab tracking must not extend across the parent visible region"); exit(1);
  }
  [window close];
}

static void TestNewTabButtonMovesWithInsertion(TLThemePalette *palette) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 100)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  NSView *button = [[NSView alloc] init];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [window.contentView addSubview:stack];
  [window.contentView addSubview:button];
  NSLayoutConstraint *spacing = [stack.trailingAnchor constraintEqualToAnchor:button.leadingAnchor];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [stack.heightAnchor constraintEqualToConstant:palette.tabHeight], spacing,
    [button.topAnchor constraintEqualToAnchor:stack.topAnchor],
    [button.widthAnchor constraintEqualToConstant:31],
    [button.heightAnchor constraintEqualToConstant:31],
  ]];
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  TLWorkspaceTab *first = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:91
    title:@"First" toolTip:@"" URL:nil closeable:YES];
  TLWorkspaceTab *second = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:92
    title:@"Second" toolTip:@"" URL:nil closeable:YES];
  harness.tabs = @[first]; harness.activeTabID = 91;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  controller.createTabButtonSpacingConstraint = spacing;
  __block BOOL animating = NO;
  controller.animationActivityChanged = ^(BOOL value) { animating = value; };
  [controller reloadTabs];
  [window.contentView layoutSubtreeIfNeeded];
  [controller updateSelectionIndicatorAnimated:NO];
  CGFloat start = NSMinX(button.frame);
  CGFloat selectionStart = NSMinX(controller.selectionView.selectionFrame);
  harness.tabs = @[first, second]; harness.activeTabID = 92;
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMinX(button.frame), start, @"plus starts at its previous position without a jump");
    if (!animating) { NSLog(@"FAIL insertion must suppress plus hover"); exit(1); }
    NSArray<TLChromeTabView *> *tabViews = [controller valueForKey:@"tabViews"];
    CGFloat selectionTarget = NSMinX(tabViews.lastObject.frame);
    now = palette.tabLifecycleTransitionDuration * 0.25;
    [timeline advance];
    AssertClose(NSMinX(controller.selectionView.selectionFrame),
                selectionStart + (selectionTarget - selectionStart) * 0.578125,
                @"new-tab background uses the same ease-out as tab selection at quarter time");
    if (fabs(NSMinX(button.frame) - NSMaxX(controller.selectionView.selectionFrame)) > 0.5) {
      NSLog(@"FAIL plus must track the growing background's right edge"); exit(1);
    }
    AssertClose(tabViews.lastObject.lifecycleContentOpacity, 1, @"new content reveals at full opacity");
    now = palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    if (fabs(NSMinX(button.frame) - NSMaxX(controller.selectionView.selectionFrame)) > 0.5) {
      NSLog(@"FAIL plus loses the background edge at midpoint"); exit(1);
    }
    AssertClose(tabViews.lastObject.lifecycleContentOpacity, 1, @"creation does not fade content at midpoint");
    AssertClose(NSMinX(controller.selectionView.selectionFrame), selectionStart + (selectionTarget - selectionStart) * 0.875,
                @"new-tab background matches selection easing at half time");
    NSView *content = [tabViews.lastObject valueForKey:@"contentContainer"];
    CAShapeLayer *backgroundClip = (CAShapeLayer *)content.layer.mask.mask;
    if (!backgroundClip || controller.selectionView.layer.mask) {
      NSLog(@"FAIL insertion must clip content to the background without masking the background itself"); exit(1);
    }
    CGPathRef backgroundPath = [controller.selectionView newOutlinePath];
    NSRect expectedClip = [controller.selectionView convertRect:CGPathGetBoundingBox(backgroundPath) toView:content];
    CGPathRelease(backgroundPath);
    NSRect actualClip = CGPathGetBoundingBox(backgroundClip.path);
    AssertClose(NSMinX(actualClip), NSMinX(expectedClip), @"content mask follows moving background origin");
    AssertClose(NSWidth(actualClip), NSWidth(expectedClip), @"content mask follows resizing background width");
    [timeline finishAllTransitions];
    if (content.layer.mask) { NSLog(@"FAIL insertion leaves a content mask behind"); exit(1); }
    AssertClose(tabViews.lastObject.lifecycleContentOpacity, 1, @"content finishes fully visible");
  }
  [timeline finishAllTransitions];
  AssertClose(spacing.constant, 0, @"plus restores normal spacing after insertion");
  if (animating) { NSLog(@"FAIL finishing animations must release plus hover suppression"); exit(1); }
  AssertClose(NSMinX(button.frame), NSMaxX(stack.frame), @"plus ends at the new strip edge");
  NSRect beforeCloseSelection = controller.selectionView.selectionFrame;
  CGFloat beforeCloseButtonX = NSMinX(button.frame);
  harness.tabs = @[first]; harness.activeTabID = first.tabID;
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMinX(controller.selectionView.selectionFrame), NSMinX(beforeCloseSelection),
                @"closing reload never paints the fallback before the first animation tick");
    AssertClose(NSMinX(button.frame), beforeCloseButtonX,
                @"plus does not flash at its final position before last-tab closure starts");
    if (![timeline hasTransitionForKey:@"selection"]) {
      NSLog(@"FAIL closing selection animation must be armed before reload returns"); exit(1);
    }
  }
  [controller performPendingSelectionAnimation];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    for (NSNumber *fraction in @[@0.1, @0.3, @0.5]) {
      now += palette.tabSelectionSlideDuration * fraction.doubleValue;
      [timeline advance];
      if (fabs(NSMinX(button.frame) - NSMaxX(controller.selectionView.selectionFrame)) > 0.5) {
        NSLog(@"FAIL plus must stay attached to the background during last-tab removal"); exit(1);
      }
    }
  }
  [timeline finishAllTransitions];
  AssertClose(spacing.constant, 0, @"last-tab removal restores normal plus spacing");
  AssertClose(NSMinX(button.frame), NSMaxX(stack.frame), @"plus ends at the remaining tab edge");
  NSMutableArray *manyTabs = [NSMutableArray arrayWithObject:first];
  for (NSInteger identifier = 100; identifier < 104; identifier++) {
    [manyTabs addObject:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:identifier
      title:@"Tab" toolTip:@"" URL:nil closeable:YES]];
  }
  harness.tabs = manyTabs.copy;
  [controller reloadTabs];
  [timeline finishAllTransitions];
  [controller updateSelectionIndicatorAnimated:NO];
  harness.activeTabID = ((TLWorkspaceTab *)manyTabs[2]).tabID;
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    NSArray<TLChromeTabView *> *views = [controller valueForKey:@"tabViews"];
    CALayer *separator = [views[3] valueForKey:@"leadingSeparatorLayer"];
    CABasicAnimation *fade = (CABasicAnimation *)[separator animationForKey:@"tab-decoration-fade"];
    if (!fade) { NSLog(@"FAIL switching selected tabs must animate neighboring separators"); exit(1); }
    AssertClose(fade.duration, palette.tabSeparatorFadeDuration,
                @"selection separator fading uses the shared slowness multiplier");
  }
  harness.activeTabID = first.tabID;
  [controller reloadTabs];
  [timeline finishAllTransitions];
  [manyTabs addObject:second];
  harness.tabs = manyTabs.copy;
  harness.activeTabID = second.tabID;
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    NSArray<TLChromeTabView *> *views = [controller valueForKey:@"tabViews"];
    CGFloat destination = NSMinX(views.lastObject.frame);
    CGFloat neighbor = NSMinX(views[views.count - 2].frame);
    AssertClose(NSMinX(controller.selectionView.selectionFrame), destination + (neighbor - destination) * 1.3,
                @"distant new-tab creation starts near its destination like tab selection");
  }
  [timeline finishAllTransitions];
  [window close];
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
    now += palette.tabClosingTransitionDuration * 0.1;
    [timeline advance];
    if (closing.lifecycleContentOpacity >= 1.0 || closing.lifecycleContentOpacity <= 0.0) {
      NSLog(@"FAIL closing content should already be fading near the start"); exit(1);
    }
    now += palette.tabClosingTransitionDuration * 0.4;
    [timeline advance];
    AssertClose(closing.lifecycleContentOpacity, 0.0, @"closing content finishes fading before the slot finishes shrinking");
    id transition = ((NSArray *)[controller valueForKey:@"removalTransitions"]).firstObject;
    NSView *placeholder = [transition valueForKey:@"placeholderView"];
    CGFloat targetWidth = MAX(0, -stack.spacing);
    CGFloat expectedWidth = (NSWidth(closingFrame) + targetWidth) * 0.5;
    AssertClose([[transition valueForKey:@"widthConstraint"] constant], expectedWidth,
                @"closing slot contracts at shared progress");
    if (fabs(NSWidth(placeholder.frame) - expectedWidth) > 0.5) {
      NSLog(@"FAIL closing slot layout exceeds pixel rounding tolerance"); exit(1);
    }
    AssertClose(closing.lifecycleVisibleWidth, expectedWidth, @"mask exactly matches the moving layout boundary");
    NSView *closingContent = [closing valueForKey:@"contentContainer"];
    CAShapeLayer *backgroundClip = (CAShapeLayer *)closingContent.layer.mask.mask;
    if (!backgroundClip) { NSLog(@"FAIL active closing content must also be masked by the background"); exit(1); }
    CGPathRef selectionPath = [selection newOutlinePath];
    NSRect expectedBackgroundClip = [selection convertRect:CGPathGetBoundingBox(selectionPath) toView:closingContent];
    CGPathRelease(selectionPath);
    AssertClose(CGRectGetMinX(CGPathGetBoundingBox(backgroundClip.path)), NSMinX(expectedBackgroundClip),
                @"closing content mask tracks the selected background position");
    AssertClose(CGRectGetWidth(CGPathGetBoundingBox(backgroundClip.path)), NSWidth(expectedBackgroundClip),
                @"closing content mask tracks the selected background width");
    AssertClose(NSWidth(closing.frame), NSWidth(closingFrame), @"content geometry is not scaled");
    AssertClose(NSMinX(selection.selectionFrame), NSMinX(closingFrame), @"background stays in the closing slot");
    AssertClose(NSMinX(surviving.frame), survivingStartX - (NSWidth(closingFrame) - NSWidth(placeholder.frame)),
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
    now += palette.tabClosingTransitionDuration;
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
    AssertClose(inserted.lifecycleContentOpacity, 1.0, @"new tab starts fully opaque behind its reveal mask");
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
    AssertClose(appearing.lifecycleContentOpacity, 1.0, @"same-batch replacement reveals without fading");
    now += palette.tabLifecycleTransitionDuration * 0.5;
    [timeline advance];
    id removal = ((NSArray *)[controller valueForKey:@"removalTransitions"]).firstObject;
    NSLayoutConstraint *closingWidth = [removal valueForKey:@"widthConstraint"];
    CGFloat collapsedWidth = MAX(0, -stack.spacing);
    AssertClose(closingWidth.constant, (replacedWidth + collapsedWidth) * 0.5,
                @"same-batch replacement contracts the outgoing slot at shared midpoint");
    AssertClose(replaced.lifecycleVisibleWidth, closingWidth.constant,
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
    now += palette.tabClosingTransitionDuration * 0.5;
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
  if (selectionView.layer.zPosition <= tabs[2].layer.zPosition ||
      selectionView.layer.zPosition >= draggedTab.layer.zPosition) {
    NSLog(@"FAIL dragged background must cover neighboring tabs beneath dragged content");
    exit(1);
  }
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
  [(TLTransitionCoordinator *)[controller valueForKey:@"transitionCoordinator"] finishAllTransitions];
  if (selectionView.layer.zPosition >= tabs[2].layer.zPosition) {
    NSLog(@"FAIL dropping must restore the background below tabs and separators");
    exit(1);
  }
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
  AssertClose(lastTab.leadingFlareOutset, palette.tabActiveFlareRadius, @"tab flare restores away from the edge");
  [controller chromeTabViewDidEndDragging:lastTab];
}

static void TestDropSettlesFromVisiblePosition(TLThemePalette *palette) {
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
  harness.commitsMoves = YES;
  harness.tabs = @[
    [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:801 title:@"First" toolTip:@"" URL:nil closeable:YES],
    [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:802 title:@"Second" toolTip:@"" URL:nil closeable:YES]];
  harness.activeTabID = 801;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:500];
  NSArray *views = [controller valueForKey:@"tabViews"];
  TLChromeTabView *dragged = views[0];
  TLChromeTabView *neighbor = views[1];
  CGFloat translation = NSMinX(neighbor.frame) - NSMinX(dragged.frame) - 20;
  [dragged setValue:@(translation) forKey:@"dragTranslationX"];
  [dragged setValue:@YES forKey:@"didDrag"];
  [controller chromeTabView:dragged didDragWithEvent:nil];
  CGFloat releaseX = NSMinX(dragged.frame) + dragged.dragTranslationX;
  CGFloat neighborReleaseX = NSMinX(neighbor.frame) + (neighbor.layer.presentationLayer ?: neighbor.layer).transform.m41;
  NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  if ([dragged menuForEvent:rightClick] || [neighbor menuForEvent:rightClick]) {
    NSLog(@"FAIL all tab context menus must be suppressed during drag"); exit(1);
  }
  [dragged rightMouseDown:rightClick];
  [neighbor rightMouseDown:rightClick];
  AssertClose(NSMinX(dragged.frame) + dragged.dragTranslationX, releaseX,
              @"right-click leaves the active drag position intact");
  NSEvent *release = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
  [dragged mouseUp:release];
  if (harness.tabs.lastObject.tabID != 801) { NSLog(@"FAIL drop must commit the new order"); exit(1); }
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMinX(dragged.frame) + dragged.reorderTranslationX, releaseX, @"mouse-up preserves dragged artwork position");
    if ([neighbor menuForEvent:rightClick]) { NSLog(@"FAIL menus must wait for settling"); exit(1); }
    AssertClose(NSMinX(controller.selectionView.selectionFrame), releaseX, @"mouse-up preserves slab position");
    AssertClose(NSMinX(neighbor.frame) + neighbor.reorderTranslationX, neighborReleaseX,
                @"mouse-up preserves the neighbor's in-flight position");
    now = palette.tabReorderSlideDuration * 0.5;
    [timeline advance];
    AssertClose(NSMinX(dragged.frame) + dragged.reorderTranslationX, (releaseX + NSMinX(dragged.frame)) * 0.5,
                @"dragged tab settles halfway toward the committed slot");
    AssertClose(NSMinX(controller.selectionView.selectionFrame), NSMinX(dragged.frame) + dragged.reorderTranslationX,
                @"slab and dragged content settle together");
    AssertClose(NSMinX(neighbor.frame) + neighbor.reorderTranslationX, (neighborReleaseX + NSMinX(neighbor.frame)) * 0.5,
                @"neighbor settles on the same timeline");
  }
  [timeline finishAllTransitions];
  AssertClose(dragged.reorderTranslationX, 0, @"drop clears dragged offset after settling");
  AssertClose(neighbor.reorderTranslationX, 0, @"drop clears neighbor offset after settling");
  AssertClose(controller.selectionView.layer.zPosition, -1, @"drop restores normal slab depth after settling");
  if (![dragged menuForEvent:rightClick] || ![neighbor menuForEvent:rightClick]) {
    NSLog(@"FAIL tab context menus must return after drop settles"); exit(1);
  }
  [window close];
}

static void TestMetadataReusesTabAndAnimatesInPlace(TLThemePalette *palette) {
  TLTabPointerWindow *window = [[TLTabPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 80)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testPointer = NSMakePoint(-20, -20);
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  [window.contentView addSubview:stack];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  TLWorkspaceTab *draft = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:-1
    title:@"New chat" toolTip:@"" URL:nil closeable:YES];
  harness.tabs = @[draft]; harness.activeTabID = -1;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:nil delegate:(id)harness palette:palette];
  [controller reloadTabs];
  [stack layoutSubtreeIfNeeded];
  TLChromeTabView *view = ((NSArray *)[controller valueForKey:@"tabViews"]).firstObject;
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *metadata = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  [view setValue:metadata forKey:@"metadataTransitions"];
  TLWorkspaceTab *saved = [draft copy]; saved.tabID = 42; saved.presentationIdentity = @"0:-1";
  saved.title = @"Conversation";
  harness.tabs = @[saved]; harness.activeTabID = 42;
  [controller reloadTabs];
  if (((NSArray *)[controller valueForKey:@"tabViews"]).firstObject != view ||
      [controller.transitionCoordinator hasTransitionForKey:@"lifecycle"] ||
      [controller.transitionCoordinator hasTransitionForKey:@"selection"]) {
    NSLog(@"FAIL saving a draft must reuse the view without tab lifecycle or movement"); exit(1);
  }
  [view updateTitle:@"Conversation" image:nil icon:@"🐟" systemIconName:@"" animated:YES];
  NSTextField *label = [view valueForKey:@"titleLabel"];
  NSView *icon = [view valueForKey:@"tabIconView"];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    if (![label.stringValue isEqual:@"New chat"]) { NSLog(@"FAIL old title must remain at transition start"); exit(1); }
    now = palette.tabMetadataTransitionDuration * 0.5;
    [metadata advance];
    if (label.stringValue.length) { NSLog(@"FAIL old title must be untyped before typing its replacement"); exit(1); }
    AssertClose(icon.alphaValue, 0.5, @"new icon fades in while old icon fades out");
    now = palette.tabMetadataTransitionDuration * 0.75;
    [metadata advance];
    if (!label.stringValue.length || ![@"Conversation" hasPrefix:label.stringValue]) {
      NSLog(@"FAIL new title must type in as a prefix"); exit(1);
    }
  }
  [metadata finishAllTransitions];
  if (![label.stringValue isEqual:@"Conversation"]) { NSLog(@"FAIL metadata transition must finish with the new title"); exit(1); }
  AssertClose(icon.alphaValue, 1, @"new icon finishes fully visible");
  [window close];
}

static void TestHoverContentMaskRestores(TLThemePalette *palette) {
  TLTabPointerWindow *window = [[TLTabPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 80)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testPointer = NSMakePoint(-20, -20);
  TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  tab.palette = palette;
  tab.closeable = YES;
  tab.title = @"A very long tab title that should retain a visible right-edge fade";
  [window.contentView addSubview:tab];
  [tab layoutSubtreeIfNeeded];
  NSView *clip = [tab valueForKey:@"titleClipView"];
  CGFloat fullWidth = NSWidth(clip.bounds);
  window.testPointer = NSMakePoint(80, 15);
  [tab updateTrackingAreas];
  [tab layoutSubtreeIfNeeded];
  CAGradientLayer *mask = (CAGradientLayer *)clip.layer.mask;
  AssertClose(NSWidth(clip.bounds), fullWidth, @"hover keeps the underlying text layout width stable");
  if (NSWidth(mask.bounds) >= fullWidth || CGColorGetAlpha((__bridge CGColorRef)mask.colors.lastObject) != 0) {
    NSLog(@"FAIL hovered title must have a narrower mask and transparent fade endpoint"); exit(1);
  }
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *resize = (CABasicAnimation *)[mask animationForKey:@"tab-content-resize"];
    if (!resize) { NSLog(@"FAIL hover must animate content mask width"); exit(1); }
    AssertClose(resize.duration, palette.tabHoverFadeDuration, @"mask resize shares hover animation timing");
  }
  window.testPointer = NSMakePoint(-20, -20);
  [tab updateTrackingAreas];
  [tab layoutSubtreeIfNeeded];
  AssertClose(NSWidth(mask.bounds), fullWidth, @"unhover restores the entire title mask width");
  [window close];
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
  NSLayoutConstraint *titleTrailing = [first valueForKey:@"titleClipTrailingConstraint"];
  AssertClose(-titleTrailing.constant - palette.tabFlareRadius, leading.constant,
              @"unhovered content has equal visible padding at the first tab's left and right edges");

  NSRect hoverRect = [first inactiveHoverPillRectInRect:first.bounds];
  AssertClose(NSMinX(hoverRect), 0, @"first-tab hover reaches the left edge without reserving a nonexistent flare");
  AssertClose(NSMaxX(hoverRect), NSWidth(first.bounds) - palette.tabFlareRadius,
              @"inactive hover excludes the trailing flare width");
  first.leadingFlareOutset = -1;
  hoverRect = [first inactiveHoverPillRectInRect:first.bounds];
  AssertClose(NSMinX(hoverRect), palette.tabFlareRadius, @"regular tabs retain their leading hover inset");
  AssertClose(-titleTrailing.constant, leading.constant,
              @"regular unhovered tabs have symmetric content insets including the fade endpoint");
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

  for (NSNumber *tabWidth in @[@(width), @40.0]) {
    right.frame = NSMakeRect(0, 0, tabWidth.doubleValue, palette.tabHeight);
    [right layoutSubtreeIfNeeded];
    CALayer *trailingSeparator = [right valueForKey:@"trailingSeparatorLayer"];
    NSRect hoverRect = [right inactiveHoverPillRectInRect:right.bounds];
    CGFloat leadingGap = NSMinX(hoverRect) - [right inactiveLeadingSeparatorCenterXInRect:right.bounds];
    AssertClose(NSMidX(trailingSeparator.frame) - NSMaxX(hoverRect), leadingGap,
                @"last separator uses the same spacing from the tab body as internal separators");
  }
  right.frame = NSMakeRect(0, 0, width, palette.tabHeight);

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
  TLTabPointerWindow *window = [[TLTabPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.tabMaxWidth, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testPointer = NSMakePoint(-20, -20);
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
  window.testPointer = NSMakePoint(palette.tabMaxWidth * 0.5, palette.tabHeight * 0.5);
  [tab mouseEntered:event];
  AssertClose(hover.opacity, 1.0, @"hover background fade-in updates its final state");
  AssertClose(separator.opacity, 0.0, @"hover fades out the separator");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *fade = (CABasicAnimation *)[hover animationForKey:@"tab-decoration-fade"];
    CGFloat timingMultiplier = palette.tabHoverFadeDuration / 0.10;
    AssertClose(palette.tabSelectionSlideDuration, 0.16 * timingMultiplier, @"long selection uses 320ms at normal speed");
    AssertClose(palette.tabNeighborSelectionSlideDuration, 0.12 * timingMultiplier, @"neighbor selection uses 240ms at normal speed");
    AssertClose(palette.tabTeleportSelectionSlideDuration, 0.14 * timingMultiplier, @"teleport selection uses 280ms at normal speed");
    AssertClose(palette.tabReorderSlideDuration, 0.12 * timingMultiplier, @"reordering shares tab timing multiplier");
    AssertClose(palette.tabLifecycleTransitionDuration, 0.135 * timingMultiplier, @"creation uses 270ms at normal speed");
    AssertClose(palette.tabClosingTransitionDuration, 0.10 * timingMultiplier,
                @"closing retains its independent 200ms duration");
    AssertClose(palette.tabSeparatorFadeDuration, palette.tabHoverFadeDuration, @"separators match the 100ms hover timing and shared multiplier");
    AssertClose(fade.duration, palette.tabHoverFadeDuration, @"hover background fades in over the themed duration");
  }
  window.testPointer = NSMakePoint(-20, -20);
  [tab mouseExited:event];
  AssertClose(hover.opacity, 0.0, @"hover background fade-out updates its final state");
  AssertClose(separator.opacity, 1.0, @"hover exit fades the separator back in");
  [window close];
}

static void TestClosingFirstTabAnimatesSelectedNeighborCorners(TLThemePalette *palette) {
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
  harness.connectsContentEdge = YES;
  TLWorkspaceTab *first = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:901
    title:@"First" toolTip:@"" URL:nil closeable:YES];
  TLWorkspaceTab *second = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:902
    title:@"Second" toolTip:@"" URL:nil closeable:YES];
  harness.tabs = @[first, second];
  harness.activeTabID = second.tabID;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:harness delegate:(id)harness palette:palette transitionCoordinator:timeline];
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:500];
  TLChromeTabView *firstView = ((NSArray *)[controller valueForKey:@"tabViews"]).firstObject;
  CGFloat edge = NSMinX(firstView.frame);
  harness.tabs = @[second];
  [controller reloadTabs];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    BOOL sawPartialRadius = NO;
    for (NSUInteger tick = 0; tick < 100; tick++) {
      now = palette.tabClosingTransitionDuration * tick / 100.0;
      [timeline advance];
      CGFloat distance = MAX(0, NSMinX(controller.selectionView.selectionFrame) - edge);
      if (firstView.layer.zPosition >= controller.selectionView.layer.zPosition) {
        NSLog(@"FAIL selected background must cover its closing predecessor"); exit(1);
      }
      AssertClose(controller.selectionView.layer.zPosition, -1,
                  @"covering the closing predecessor does not raise the slab over live tabs");
      AssertClose(controller.selectionView.leadingFlareOutset, MIN(palette.tabActiveFlareRadius, distance),
                  @"closing first slot keeps the selected neighbor flare tied to the strip edge");
      AssertClose(harness.contentCornerRadius, MIN(palette.space5, distance),
                  @"content corner follows the selected neighbor as the preceding slot collapses");
      TLChromeTabView *survivor = ((NSArray *)[controller valueForKey:@"tabViews"]).firstObject;
      CGFloat defaultFlare = MIN(palette.tabFlareRadius, NSWidth(survivor.bounds) * 0.18);
      NSLayoutConstraint *iconLeading = [survivor valueForKey:@"iconLeadingConstraint"];
      AssertClose(iconLeading.constant, palette.tabIconLeadingInset - defaultFlare + MIN(defaultFlare, distance),
                  @"surviving tab padding follows its visible flare instead of snapping to first-tab padding");
      if (harness.contentCornerRadius > 0 && harness.contentCornerRadius < palette.space5) sawPartialRadius = YES;
    }
    if (!sawPartialRadius) { NSLog(@"FAIL closing first tab must interpolate the corner radius"); exit(1); }
  }
  [timeline finishAllTransitions];
  AssertClose(harness.contentCornerRadius, 0, @"selected neighbor ends attached to content");
  AssertClose(controller.selectionView.leadingFlareOutset, 0, @"selected neighbor ends without a leading flare");
  [window close];
}

static void TestSelectionEdgeFollowsVisibleBackground(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 400, palette.tabHeight)];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.connectsContentEdge = YES;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack target:nil delegate:(id)harness palette:palette];
  TLChromeTabView *first = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 160, palette.tabHeight)];
  [controller setValue:[NSMutableArray arrayWithObject:first] forKey:@"tabViews"];
  TLChromeTabSelectionView *selection = controller.selectionView;
  selection.hidden = NO;
  for (NSNumber *active in @[@YES, @NO]) {
    first.active = active.boolValue;
    for (NSNumber *offset in @[@0, @2, @20, @2, @0]) {
      NSRect frame = NSOffsetRect(first.frame, offset.doubleValue, 0);
      [selection setSelectionFrame:frame leadingFlareOutset:-1 animated:NO fromFrame:frame duration:0];
      [controller updateEdgeAttachmentState];
      AssertClose(selection.leadingFlareOutset, MIN(palette.tabActiveFlareRadius, offset.doubleValue),
                  @"selection flare follows distance from edge regardless of logical selection");
      AssertClose(harness.contentCornerRadius, MIN(palette.space5, offset.doubleValue),
                  @"content corner follows approaching and departing background");
    }
  }
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
  [controller setValue:@0 forKey:@"pendingSelectionStartIndex"];
  [controller setValue:@1 forKey:@"pendingSelectionTargetIndex"];
  [controller setValue:@YES forKey:@"hasPendingSelectionAnimation"];
  [controller performPendingSelectionAnimation];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMinX(selectionView.selectionFrame), NSMinX(left.frame), @"selection begins at previous tab");
    AssertClose(selectionView.leadingFlareOutset, 0, @"departing first tab starts attached to the edge");
    now = palette.tabNeighborSelectionSlideDuration * 0.001;
    [timeline advance];
    AssertClose(selectionView.leadingFlareOutset, NSMinX(selectionView.selectionFrame),
                @"selection tick gradually opens the flare near the edge");
    now = palette.tabNeighborSelectionSlideDuration * 0.5;
    [timeline advance];
    AssertClose(NSMinX(selectionView.selectionFrame), NSMinX(left.frame) + (NSMinX(right.frame) - NSMinX(left.frame)) * 0.875,
                @"selection eases out without a slow ease-in start");
    [controller updateSelectionIndicatorAnimated:NO];
    if (![timeline hasTransitionForKey:@"selection"]) {
      NSLog(@"FAIL duplicate reload cancels the selection transition"); exit(1);
    }
    now = palette.tabNeighborSelectionSlideDuration;
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
  if (selectionView.layer.zPosition >= tabs[2].layer.zPosition ||
      selectionView.layer.zPosition >= tabs.lastObject.layer.zPosition) {
    NSLog(@"FAIL click-to-select background must stay below tabs and separators");
    exit(1);
  }
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMidX(selectionView.selectionFrame), NSMidX(tabs[4].frame) - 1.3 * palette.tabMaxWidth,
                @"long selection jump starts thirty percent farther from its destination");
  }
  [timeline finishAllTransitions];
  tabs.lastObject.active = NO;
  tabs.firstObject.active = YES;
  [controller setValue:[NSValue valueWithRect:tabs.lastObject.frame] forKey:@"pendingSelectionStartFrame"];
  [controller setValue:@4 forKey:@"pendingSelectionStartIndex"];
  [controller setValue:@0 forKey:@"pendingSelectionTargetIndex"];
  [controller setValue:@YES forKey:@"hasPendingSelectionAnimation"];
  [controller performPendingSelectionAnimation];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    AssertClose(NSMidX(selectionView.selectionFrame), NSMidX(tabs[0].frame) + 1.3 * palette.tabMaxWidth,
                @"reverse long jumps use the same increased distance");
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
      AssertClose(tab.palette.tabContentVerticalOffset, 1, @"tab artwork moves up one point");
      AssertClose(tab.palette.tabActiveFlareRadius, 9.6, @"active tab flares are twenty percent larger");
      AssertClose(TLChromeTabInterTabOverlapForWidth(tab.palette.tabMaxWidth, tab.palette),
                  tab.palette.tabFlareRadius + tab.palette.space2, @"tabs use their original spacing without the extra half point");
      AssertClose(tab.palette.tabActiveHeightReduction, 1, @"selected background moves up one point");
      AssertClose([[tab valueForKey:@"titleCenterYConstraint"] constant], -1, @"title moves up with tab artwork");
      AssertClose([[tab valueForKey:@"closeCenterYConstraint"] constant], -1, @"close button moves up with tab artwork");
      [tab layoutSubtreeIfNeeded];
      for (NSString *key in @[@"titleClipView", @"closeButton"]) {
        NSView *content = [tab valueForKey:key];
        NSRect contentRect = [content convertRect:content.bounds toView:tab];
        AssertClose(NSMidY(contentRect), NSMidY(tab.bounds) + tab.palette.tabContentVerticalOffset,
                    @"laid-out content moves upward in the tab's unflipped coordinates");
      }
      CALayer *separator = [tab valueForKey:@"leadingSeparatorLayer"];
      AssertClose(NSMinY(separator.frame), tab.palette.space5 + 1, @"separator moves up without changing height");
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
      TestNewTabButtonMovesWithInsertion(tab.palette);
      TestClosePreservesWidthsUntilPointerLeaves(tab.palette);
      TestManyTabsFitWithoutExpandingWindow(tab.palette);
      TestDraggedTabOpensInsertionGap(tab.palette);
      TestDropSettlesFromVisiblePosition(tab.palette);
      TestInactiveFirstTabPadding(tab.palette);
      TestHoverContentMaskRestores(tab.palette);
      TestMetadataReusesTabAndAnimatesInPlace(tab.palette);
      TestInactiveSeparatorCentering(tab.palette);
      TestInactiveDecorationFades(tab.palette);
      TestSelectionSlabSlidesBetweenTabs(tab.palette);
      TestSelectionEdgeFollowsVisibleBackground(tab.palette);
      TestClosingFirstTabAnimatesSelectedNeighborCorners(tab.palette);
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
