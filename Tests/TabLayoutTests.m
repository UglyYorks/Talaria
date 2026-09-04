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
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500.0, palette.tabHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSStackView *stack = [[NSStackView alloc] initWithFrame:window.contentView.bounds];
  stack.wantsLayer = YES;
  [window.contentView addSubview:stack];
  TLWorkspaceTab *firstTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                   tabID:71
                                                   title:@"First"
                                                 toolTip:@""
                                                      URL:nil
                                                closeable:YES];
  TLWorkspaceTab *secondTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                                    tabID:72
                                                    title:@"Second"
                                                  toolTip:@""
                                                       URL:nil
                                                 closeable:YES];
  TLTabContextMenuHarness *harness = [[TLTabContextMenuHarness alloc] init];
  harness.tabs = @[firstTab, secondTab];
  harness.activeTabID = firstTab.tabID;
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc]
    initWithTabStack:stack
              target:harness
            delegate:(id<TLWorkspaceTabsControllerDelegate>)harness
             palette:palette];
  harness.controller = controller;
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:NSWidth(stack.bounds)];
  [stack layoutSubtreeIfNeeded];
  TLChromeTabView *removedTabView = ((NSArray<TLChromeTabView *> *)[controller valueForKey:@"tabViews"])[0];
  TLChromeTabView *originalSurvivingTabView = ((NSArray<TLChromeTabView *> *)[controller valueForKey:@"tabViews"])[1];
  NSRect removedFrame = removedTabView.frame;
  NSRect survivingStartFrame = originalSurvivingTabView.frame;

  harness.tabs = @[secondTab];
  [controller reloadTabs];
  harness.activeTabID = secondTab.tabID;
  [controller reloadTabs];
  [controller updateTabWidthsForAvailableWidth:NSWidth(stack.bounds)];

  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    TLChromeTabView *survivingTabView = ((NSArray<TLChromeTabView *> *)[controller valueForKey:@"tabViews"])[0];
    id removalTransition = ((NSArray *)[controller valueForKey:@"removalTransitions"]).firstObject;
    NSView *removalPlaceholder = [removalTransition valueForKey:@"placeholderView"];
    if ([stack.subviews indexOfObjectIdenticalTo:removedTabView] <=
        [stack.subviews indexOfObjectIdenticalTo:survivingTabView]) {
      NSLog(@"FAIL an internal removed-tab overlay is covered by a surviving tab after refresh");
      exit(1);
    }
    if (removedTabView.superview != stack || removedTabView.drawsActiveBackground ||
        !NSEqualRects(removedTabView.frame, removedFrame)) {
      NSLog(@"FAIL removed tab duplicates the selected background while closing");
      exit(1);
    }
    TLChromeTabSelectionView *selectionView = [controller valueForKey:@"selectionView"];
    if (selectionView.layer.mask) {
      NSLog(@"FAIL shared selection slab is clipped during a lifecycle animation");
      exit(1);
    }
    CGFloat removalTargetWidth = MAX(palette.space0, -stack.spacing);
    NSView *removedContentContainer = [removedTabView valueForKey:@"contentContainer"];
    NSView *removedTitleClipView = [removedTabView valueForKey:@"titleClipView"];
    NSDate *transitionStartDeadline = [NSDate dateWithTimeIntervalSinceNow:
      MIN(0.05, palette.tabLifecycleTransitionDuration * 0.25)];
    while (![removedContentContainer.layer.mask animationForKey:@"tab-removal-clip"] &&
           [transitionStartDeadline timeIntervalSinceNow] > 0.0) {
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:transitionStartDeadline];
    }
    CABasicAnimation *removalFade = (CABasicAnimation *)[removedTitleClipView.layer
      animationForKey:@"tab-removal-content-fade"];
    CABasicAnimation *removalClip = (CABasicAnimation *)[removedContentContainer.layer.mask
      animationForKey:@"tab-removal-clip"];
    CGPathRef removalEndPath = removalClip ? (__bridge CGPathRef)removalClip.toValue : nil;
    CGRect removalEndBounds = removalEndPath ? CGPathGetBoundingBox(removalEndPath) : CGRectZero;
    if (!removalClip || removedTabView.layer.mask ||
        !removalFade ||
        fabs(removalFade.duration - palette.tabLifecycleTransitionDuration *
             palette.tabLifecycleContentFadeDurationRatio) > 0.001 ||
        [removedTabView.layer animationForKey:@"tab-removal-fade"] ||
        fabs(CGRectGetMinX(removalEndBounds) - NSMinX(removedContentContainer.bounds)) > 0.001 ||
        fabs(CGRectGetWidth(removalEndBounds) - removalTargetWidth) > 0.001 ||
        fabs(removedTabView.layer.opacity - 1.0) > 0.001) {
      NSLog(@"FAIL removed tab is not the content-only reverse of insertion");
      exit(1);
    }
    NSDate *sampleDeadline = [NSDate dateWithTimeIntervalSinceNow:
      palette.tabLifecycleTransitionDuration * 0.50];
    while ([sampleDeadline timeIntervalSinceNow] > 0.0) {
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:sampleDeadline];
    }
    CALayer *visiblePlaceholderLayer = removalPlaceholder.layer.presentationLayer ?: removalPlaceholder.layer;
    CGFloat visibleRemovalWidth = CGRectGetWidth(visiblePlaceholderLayer.frame);
    if (visibleRemovalWidth >= NSWidth(removedFrame) - 0.1 ||
        visibleRemovalWidth <= removalTargetWidth + 0.1) {
      NSLog(@"FAIL closing tab slot does not remain in flight for the lifecycle duration");
      exit(1);
    }
    CAShapeLayer *removalMask = (CAShapeLayer *)removedContentContainer.layer.mask;
    CAShapeLayer *visibleRemovalMask = (CAShapeLayer *)(removalMask.presentationLayer ?: removalMask);
    CGFloat visibleMaskWidth = visibleRemovalMask.path
      ? CGRectGetWidth(CGPathGetBoundingBox(visibleRemovalMask.path))
      : NSWidth(removedContentContainer.bounds);
    if (visibleMaskWidth > visibleRemovalWidth + 0.5) {
      NSLog(@"FAIL closing tab content mask does not stay behind the moving layout boundary");
      exit(1);
    }
    if (fabs(NSWidth(removedTabView.frame) - NSWidth(removedFrame)) > 0.001) {
      NSLog(@"FAIL closing tab content geometry shrinks faster than its lifecycle mask");
      exit(1);
    }
    CALayer *visibleSurvivingLayer = survivingTabView.layer.presentationLayer ?: survivingTabView.layer;
    if (CGRectGetMinX(visibleSurvivingLayer.frame) >= NSMinX(survivingStartFrame) - 0.1) {
      NSLog(@"FAIL tab to the right does not move with the contracting closing slot");
      exit(1);
    }
    if (!removedContentContainer.layer.masksToBounds) {
      NSLog(@"FAIL closing tab content can escape its contracting layout slot");
      exit(1);
    }
    CGFloat twoFrameTrackingTolerance = NSWidth(removedFrame) *
      ((2.0 / 60.0) / palette.tabLifecycleTransitionDuration) + 2.0;
    if (fabs(NSMinX(selectionView.selectionFrame) - CGRectGetMinX(visibleSurvivingLayer.frame)) >
        twoFrameTrackingTolerance) {
      NSLog(@"FAIL selected background does not track the moving fallback tab");
      exit(1);
    }
    if (!CATransform3DIsIdentity(removedTabView.layer.transform)) {
      NSLog(@"FAIL removal animation transforms the closing tab layer");
      exit(1);
    }
    TLChromeTabView *insertedTabView = [[TLChromeTabView alloc] initWithFrame:removedFrame];
    insertedTabView.palette = palette;
    [stack addSubview:insertedTabView];
    [insertedTabView layoutSubtreeIfNeeded];
    [insertedTabView prepareForInsertionAnimation];
    NSView *insertedContentContainer = [insertedTabView valueForKey:@"contentContainer"];
    NSView *insertedTitleClipView = [insertedTabView valueForKey:@"titleClipView"];
    CGPathRef preparedPath = ((CAShapeLayer *)insertedContentContainer.layer.mask).path;
    CGRect preparedBounds = preparedPath ? CGPathGetBoundingBox(preparedPath) : CGRectZero;
    if (insertedTabView.layer.mask ||
        fabs(CGRectGetWidth(preparedBounds) - NSWidth(removedFrame) *
             palette.tabLifecycleCollapsedWidthRatio) > 0.001 ||
        fabs(insertedTitleClipView.layer.opacity) > 0.001) {
      NSLog(@"FAIL inserted tab is visible at full width or opacity before its first animation frame");
      exit(1);
    }
    [insertedTabView animateInsertionWithDuration:palette.tabLifecycleTransitionDuration completion:^{}];
    CABasicAnimation *insertionClip = (CABasicAnimation *)[insertedContentContainer.layer.mask
      animationForKey:@"tab-insertion-clip"];
    CGPathRef insertionStartPath = insertionClip
      ? (__bridge CGPathRef)insertionClip.fromValue
      : nil;
    CGRect initialBounds = insertionStartPath ? CGPathGetBoundingBox(insertionStartPath) : CGRectZero;
    CABasicAnimation *insertionFade = (CABasicAnimation *)[insertedTitleClipView.layer
      animationForKey:@"tab-insertion-content-fade"];
    if (!insertionClip ||
        insertedTabView.layer.mask ||
        [insertedTabView.layer animationForKey:@"tab-insertion-fade"] ||
        !insertionFade ||
        fabs(insertionFade.duration - palette.tabLifecycleTransitionDuration *
             palette.tabLifecycleContentFadeDurationRatio) > 0.001 ||
        fabs(CGRectGetMinX(initialBounds) - NSMinX(insertedContentContainer.bounds)) > 0.001 ||
        fabs(CGRectGetWidth(initialBounds) - NSWidth(removedFrame) * palette.tabLifecycleCollapsedWidthRatio) > 0.001 ||
        fabs(insertedTabView.layer.opacity - 1.0) > 0.001 ||
        !NSEqualRects(insertedTabView.frame, removedFrame) ||
        !CATransform3DIsIdentity(insertedTabView.layer.transform)) {
      NSLog(@"FAIL inserted tab does not expand from the themed width while fading only its content");
      exit(1);
    }
  }
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
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
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
  if (!NSEqualRects(selectionView.selectionFrame, right.frame)) {
    NSLog(@"FAIL selection slab does not finish behind the newly active tab");
    exit(1);
  }
  CAShapeLayer *backgroundLayer = [selectionView valueForKey:@"backgroundLayer"];
  CABasicAnimation *slide = (CABasicAnimation *)[backgroundLayer animationForKey:@"tab-selection-slide"];
  if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    if (slide) {
      NSLog(@"FAIL selection slab animates when Reduce Motion is enabled");
      exit(1);
    }
  } else {
    if (!slide) {
      NSLog(@"FAIL selection slab transition has no animation");
      exit(1);
    }
    AssertClose(slide.duration, palette.tabSelectionSlideDuration,
                @"selection slab uses the themed slide duration");
    CGRect startBounds = CGPathGetBoundingBox((__bridge CGPathRef)slide.fromValue);
    CGRect endBounds = CGPathGetBoundingBox((__bridge CGPathRef)slide.toValue);
    AssertClose(NSMidX(startBounds), NSMidX(left.frame), @"selection slab animation begins at the previous tab");
    AssertClose(NSMidX(endBounds), NSMidX(right.frame), @"selection slab animation ends at the newly active tab");

    [controller updateSelectionIndicatorAnimated:NO];
    if (![backgroundLayer animationForKey:@"tab-selection-slide"]) {
      NSLog(@"FAIL duplicate active-tab reload cancels the in-flight selection slab animation");
      exit(1);
    }
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
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
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
  [controller setValue:@YES forKey:@"suppressesTransitionSeparators"];
  [controller updateSeparatorVisibility];
  if (tabs[2].showsLeadingSeparator) {
    NSLog(@"FAIL separator remains visible inside the selection transition path");
    exit(1);
  }

  [controller performPendingSelectionAnimation];
  TLChromeTabSelectionView *selectionView = [controller valueForKey:@"selectionView"];
  CAShapeLayer *backgroundLayer = [selectionView valueForKey:@"backgroundLayer"];
  CABasicAnimation *slide = (CABasicAnimation *)[backgroundLayer animationForKey:@"tab-selection-slide"];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CGRect startBounds = CGPathGetBoundingBox((__bridge CGPathRef)slide.fromValue);
    AssertClose(NSMidX(startBounds), NSMidX(tabs[3].frame),
                @"long selection jump starts one tab away from its destination");
  }
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
