#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"
#import <QuartzCore/QuartzCore.h>

@interface TLTabRemovalTransition : NSObject
@property (nonatomic, strong) TLChromeTabView *tabView;
@property (nonatomic, strong) NSView *placeholderView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic) NSUInteger arrangedIndex;
@property (nonatomic) NSRect originalTabFrame;
@property (nonatomic, strong) TLChromeTabView *incomingSelectedTab;
@end

@implementation TLTabRemovalTransition
@end

@interface TLWorkspaceTabsController () <TLChromeTabViewDelegate>

@property (nonatomic, strong) NSStackView *tabStack;
@property (nonatomic, strong) NSMutableArray<TLChromeTabView *> *tabViews;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *tabWidthConstraints;
@property (nonatomic, strong) NSMutableArray<TLChromeTabView *> *removingTabViews;
@property (nonatomic, strong) NSMutableArray<TLTabRemovalTransition *> *removalTransitions;
@property (nonatomic, strong) TLChromeTabSelectionView *selectionView;
@property (nonatomic) NSRect pendingSelectionStartFrame;
@property (nonatomic) BOOL hasPendingSelectionAnimation;
@property (nonatomic) BOOL selectionAnimationScheduled;
@property (nonatomic) NSUInteger pendingSelectionStartIndex;
@property (nonatomic) NSUInteger pendingSelectionTargetIndex;
@property (nonatomic) NSUInteger selectionTransitionGeneration;
@property (nonatomic) NSUInteger removalSelectionTrackingGeneration;
@property (nonatomic, strong, nullable) NSTimer *removalSelectionTrackingTimer;
@property (nonatomic, strong, nullable) TLWorkspaceTab *draggedTab;
@property (nonatomic) NSUInteger draggedStartIndex;
@property (nonatomic) NSUInteger draggedCurrentIndex;
@property (nonatomic) BOOL newTabButtonHovered;

- (void)configureWorkspaceTabView:(TLChromeTabView *)tabView
                           forTab:(TLWorkspaceTab *)tab
                            index:(NSUInteger)index
                             tabs:(NSArray<TLWorkspaceTab *> *)tabs;
- (void)trackActiveSelectionDuringRemovalForDuration:(NSTimeInterval)duration;

@end

@implementation TLWorkspaceTabsController

- (instancetype)initWithTabStack:(NSStackView *)tabStack
                          target:(id)target
                        delegate:(id<TLWorkspaceTabsControllerDelegate>)delegate
                         palette:(TLThemePalette *)palette {
  self = [super init];
  if (self) {
    _tabStack = tabStack;
    _target = target;
    _delegate = delegate;
    _palette = palette;
    _tabViews = [NSMutableArray array];
    _tabWidthConstraints = [NSMutableArray array];
    _removingTabViews = [NSMutableArray array];
    _removalTransitions = [NSMutableArray array];
    _selectionView = [[TLChromeTabSelectionView alloc] init];
    // Inactive tabs (including their separators) sit at 0, selected content at 1,
    // and dragged content at 2. The slab covers separators as it passes them.
    _selectionView.layer.zPosition = 0.5;
    _selectionView.hidden = YES;
    [_tabStack addSubview:_selectionView positioned:NSWindowBelow relativeTo:nil];
    _tabStack.spacing = -TLChromeTabInterTabOverlapForWidth(palette.tabMaxWidth, palette);
    _draggedStartIndex = NSNotFound;
    _draggedCurrentIndex = NSNotFound;
    _pendingSelectionStartIndex = NSNotFound;
    _pendingSelectionTargetIndex = NSNotFound;
  }
  return self;
}

- (void)reloadTabs {
  [self.tabStack layoutSubtreeIfNeeded];
  NSArray<TLChromeTabView *> *previousTabViews = [self.tabViews copy];
  NSArray<NSLayoutConstraint *> *previousWidthConstraints = [self.tabWidthConstraints copy];
  NSMutableArray<TLChromeTabView *> *availableTabViews = [previousTabViews mutableCopy];
  NSMapTable<TLChromeTabView *, NSValue *> *previousFrames = [NSMapTable strongToStrongObjectsMapTable];
  for (TLChromeTabView *tabView in previousTabViews) {
    [previousFrames setObject:[NSValue valueWithRect:tabView.frame] forKey:tabView];
  }
  TLChromeTabView *previousActiveView = [self activeTabView];
  NSUInteger previousActiveIndex = [self.tabViews indexOfObject:previousActiveView];
  TLWorkspaceTab *previousActiveTab = [previousActiveView.representedObject isKindOfClass:TLWorkspaceTab.class]
    ? [previousActiveView.representedObject copy]
    : nil;
  NSRect previousSelectionFrame = [self visibleSelectionFrameWithFallback:previousActiveView.frame];

  for (NSView *view in self.tabStack.arrangedSubviews.copy) {
    [self.tabStack removeArrangedSubview:view];
  }

  [self.tabViews removeAllObjects];
  [self.tabWidthConstraints removeAllObjects];
  NSMutableArray<TLChromeTabView *> *insertedTabViews = [NSMutableArray array];
  NSArray<TLWorkspaceTab *> *tabs = [self.delegate workspaceTabsForTabsController:self];
  for (NSUInteger index = 0; index < tabs.count; index += 1) {
    TLWorkspaceTab *tab = tabs[index];
    TLChromeTabView *tabView = nil;
    for (TLChromeTabView *candidate in availableTabViews) {
      TLWorkspaceTab *representedTab = [candidate.representedObject isKindOfClass:TLWorkspaceTab.class]
        ? candidate.representedObject
        : nil;
      if (representedTab && representedTab.kind == tab.kind && representedTab.tabID == tab.tabID) {
        tabView = candidate;
        break;
      }
    }

    NSLayoutConstraint *width = nil;
    if (tabView) {
      NSUInteger previousIndex = [previousTabViews indexOfObjectIdenticalTo:tabView];
      width = previousIndex < previousWidthConstraints.count ? previousWidthConstraints[previousIndex] : nil;
      [availableTabViews removeObjectIdenticalTo:tabView];
    }
    BOOL inserted = tabView == nil;
    if (inserted) {
      tabView = [[TLChromeTabView alloc] init];
      tabView.translatesAutoresizingMaskIntoConstraints = NO;
      if (previousTabViews.count > 0) {
        [insertedTabViews addObject:tabView];
      }
    }
    if (!width) {
      width = [tabView.widthAnchor constraintEqualToConstant:self.palette.tabMaxWidth];
      width.priority = NSLayoutPriorityDefaultHigh;
      [NSLayoutConstraint activateConstraints:@[
        width,
        [tabView.heightAnchor constraintEqualToConstant:self.palette.tabHeight],
      ]];
    }

    width.constant = self.palette.tabMaxWidth;
    [self configureWorkspaceTabView:tabView forTab:tab index:index tabs:tabs];
    [self.tabViews addObject:tabView];
    [self.tabWidthConstraints addObject:width];
    [self.tabStack addArrangedSubview:tabView];
  }
  NSMutableArray<TLTabRemovalTransition *> *newRemovalTransitions = [NSMutableArray array];
  for (TLChromeTabView *removedTabView in availableTabViews) {
    NSUInteger previousIndex = [previousTabViews indexOfObjectIdenticalTo:removedTabView];
    if (previousIndex == NSNotFound || previousIndex >= previousWidthConstraints.count) {
      continue;
    }
    TLTabRemovalTransition *transition = [[TLTabRemovalTransition alloc] init];
    transition.tabView = removedTabView;
    transition.placeholderView = [[NSView alloc] init];
    transition.placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
    transition.placeholderView.wantsLayer = YES;
    transition.widthConstraint = [transition.placeholderView.widthAnchor constraintEqualToConstant:self.palette.tabMaxWidth];
    [NSLayoutConstraint activateConstraints:@[
      transition.widthConstraint,
      [transition.placeholderView.heightAnchor constraintEqualToConstant:self.palette.tabHeight],
    ]];
    transition.arrangedIndex = previousIndex;
    if (removedTabView == previousActiveView && previousIndex + 1 < previousTabViews.count) {
      TLChromeTabView *incomingTab = previousTabViews[previousIndex + 1];
      if ([self.tabViews containsObject:incomingTab]) {
        transition.incomingSelectedTab = incomingTab;
      }
    }
    NSValue *previousFrame = [previousFrames objectForKey:removedTabView];
    if (previousFrame) {
      transition.widthConstraint.constant = NSWidth(previousFrame.rectValue);
      transition.originalTabFrame = previousFrame.rectValue;
    }
    [self.removalTransitions addObject:transition];
    [newRemovalTransitions addObject:transition];
  }
  NSArray<TLTabRemovalTransition *> *orderedTransitions = [self.removalTransitions
    sortedArrayUsingComparator:^NSComparisonResult(TLTabRemovalTransition *left,
                                                   TLTabRemovalTransition *right) {
      if (left.arrangedIndex < right.arrangedIndex) return NSOrderedAscending;
      if (left.arrangedIndex > right.arrangedIndex) return NSOrderedDescending;
      return NSOrderedSame;
    }];
  for (TLTabRemovalTransition *transition in orderedTransitions) {
    NSUInteger insertionIndex = MIN(transition.arrangedIndex, self.tabStack.arrangedSubviews.count);
    [self.tabStack insertArrangedSubview:transition.placeholderView atIndex:insertionIndex];
  }
  [self animateRemovedTabTransitions:newRemovalTransitions];
  [self bringRemovingTabViewsToFront];
  [self animateInsertedTabViews:insertedTabViews previousFrames:previousFrames];
  TLChromeTabView *activeTabView = [self activeTabView];
  NSUInteger activeTabIndex = [self.tabViews indexOfObject:activeTabView];
  TLWorkspaceTab *activeTab = [activeTabView.representedObject isKindOfClass:TLWorkspaceTab.class]
    ? activeTabView.representedObject
    : nil;
  BOOL activeTabChanged = previousActiveTab && activeTab &&
    (previousActiveTab.kind != activeTab.kind || previousActiveTab.tabID != activeTab.tabID);
  BOOL activeTabClosed = previousActiveTab && !activeTab;
  BOOL pendingCloseFoundFallback = !previousActiveTab && activeTab &&
    self.hasPendingSelectionAnimation && self.pendingSelectionTargetIndex == NSNotFound;
  if (activeTabClosed) {
    if (!self.hasPendingSelectionAnimation) {
      self.pendingSelectionStartFrame = previousSelectionFrame;
      self.pendingSelectionStartIndex = previousActiveIndex;
    }
    self.pendingSelectionTargetIndex = NSNotFound;
    self.hasPendingSelectionAnimation = YES;
  } else if (activeTabChanged || pendingCloseFoundFallback) {
    if (!self.hasPendingSelectionAnimation) {
      self.pendingSelectionStartFrame = previousSelectionFrame;
      self.pendingSelectionStartIndex = previousActiveIndex;
    }
    self.pendingSelectionTargetIndex = activeTabIndex;
    self.hasPendingSelectionAnimation = YES;
    [self schedulePendingSelectionAnimation];
  } else if (!self.hasPendingSelectionAnimation) {
    [self updateSelectionIndicatorAnimated:NO];
  }
  [self updateSeparatorVisibilityWithoutAnimation];
  [self updateEdgeAttachmentState];
}

- (void)animateRemovedTabTransitions:(NSArray<TLTabRemovalTransition *> *)transitions {
  if (transitions.count == 0) {
    return;
  }

  BOOL shouldAnimate = self.tabStack.window && self.palette.tabLifecycleTransitionDuration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (!shouldAnimate) {
    for (TLTabRemovalTransition *transition in transitions) {
      TLChromeTabView *removedTabView = transition.tabView;
      [self.tabStack removeArrangedSubview:transition.placeholderView];
      [transition.placeholderView removeFromSuperview];
      [removedTabView removeFromSuperview];
      [self.removalTransitions removeObjectIdenticalTo:transition];
    }
    return;
  }

  for (TLTabRemovalTransition *transition in transitions) {
    TLChromeTabView *removedTabView = transition.tabView;
    removedTabView.frame = transition.originalTabFrame;
    removedTabView.enabled = NO;
    removedTabView.drawsActiveBackground = NO;
    [self.removingTabViews addObject:removedTabView];
    [self.tabStack addSubview:removedTabView positioned:NSWindowAbove relativeTo:nil];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    NSView *layoutRoot = self.tabStack.superview ?: self.tabStack;
    [layoutRoot layoutSubtreeIfNeeded];
    CGFloat collapsedSlotWidth = MAX(self.palette.space0, -self.tabStack.spacing);
    for (TLTabRemovalTransition *transition in transitions) {
      [transition.tabView animateRemovalWithDuration:self.palette.tabLifecycleTransitionDuration
                                    targetMaskWidth:collapsedSlotWidth
                                          completion:^{}];
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
      context.duration = self.palette.tabLifecycleTransitionDuration;
      context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      for (TLTabRemovalTransition *transition in transitions) {
        [[transition.widthConstraint animator] setConstant:collapsedSlotWidth];
      }
    } completionHandler:^{
      for (TLTabRemovalTransition *transition in transitions) {
        TLChromeTabView *removedTabView = transition.tabView;
        [self.tabStack removeArrangedSubview:transition.placeholderView];
        [transition.placeholderView removeFromSuperview];
        [removedTabView removeFromSuperview];
        [self.removingTabViews removeObjectIdenticalTo:removedTabView];
        [self.removalTransitions removeObjectIdenticalTo:transition];
      }
      [layoutRoot layoutSubtreeIfNeeded];
      [self updateSelectionIndicatorAnimated:NO];
      [self updateSeparatorVisibilityWithoutAnimation];
    }];
    [self trackActiveSelectionDuringRemovalForDuration:self.palette.tabLifecycleTransitionDuration];
  });
}

- (void)trackActiveSelectionDuringRemovalForDuration:(NSTimeInterval)duration {
  [self.removalSelectionTrackingTimer invalidate];
  self.removalSelectionTrackingTimer = nil;
  NSUInteger generation = ++self.removalSelectionTrackingGeneration;
  // The fallback tab moves for the entire lifecycle transition, so track its
  // presentation frame from the first display tick instead of waiting for the
  // independent selection-slide duration to elapse.
  NSTimeInterval selectionDelay = 0.0;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(selectionDelay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (generation != self.removalSelectionTrackingGeneration) {
      return;
    }
    __weak typeof(self) weakSelf = self;
    __block NSTimeInterval elapsed = selectionDelay;
    self.removalSelectionTrackingTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                                          repeats:YES
                                                                            block:^(NSTimer *timer) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || generation != strongSelf.removalSelectionTrackingGeneration) {
        [timer invalidate];
        return;
      }
      TLChromeTabView *activeTabView = [strongSelf activeTabView];
      if (!activeTabView) {
        [timer invalidate];
        strongSelf.removalSelectionTrackingTimer = nil;
        return;
      }
      CALayer *visibleTabLayer = activeTabView.layer.presentationLayer ?: activeTabView.layer;
      NSRect visibleFrame = NSRectFromCGRect(visibleTabLayer.frame);
      for (TLTabRemovalTransition *transition in strongSelf.removalTransitions) {
        if (transition.incomingSelectedTab == activeTabView) {
          visibleFrame.origin.x = NSMinX(transition.originalTabFrame);
        }
      }
      strongSelf.selectionView.frame = strongSelf.tabStack.bounds;
      [strongSelf.selectionView setSelectionFrame:visibleFrame
                                leadingFlareOutset:activeTabView.leadingFlareOutset
                                         animated:NO
                                        fromFrame:visibleFrame
                                          duration:0.0];
      elapsed += timer.timeInterval;
      if (elapsed + 0.001 >= duration) {
        [timer invalidate];
        strongSelf.removalSelectionTrackingTimer = nil;
        [strongSelf updateSelectionIndicatorAnimated:NO];
      }
    }];
  });
}

- (void)bringRemovingTabViewsToFront {
  for (TLChromeTabView *removedTabView in self.removingTabViews) {
    if (removedTabView.superview == self.tabStack) {
      [self.tabStack addSubview:removedTabView positioned:NSWindowAbove relativeTo:nil];
    }
  }
}

- (void)animateInsertedTabViews:(NSArray<TLChromeTabView *> *)insertedTabViews
                 previousFrames:(NSMapTable<TLChromeTabView *, NSValue *> *)previousFrames {
  BOOL shouldAnimate = insertedTabViews.count > 0 && self.tabStack.window &&
    self.palette.tabLifecycleTransitionDuration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (!shouldAnimate) {
    return;
  }

  [self.tabStack layoutSubtreeIfNeeded];
  for (TLChromeTabView *insertedTabView in insertedTabViews) {
    [insertedTabView prepareForInsertionAnimation];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.tabStack layoutSubtreeIfNeeded];
    [self animateSurvivingTabViewsFromPreviousFrames:previousFrames];
    for (TLChromeTabView *insertedTabView in insertedTabViews) {
      [insertedTabView animateInsertionWithDuration:self.palette.tabLifecycleTransitionDuration completion:^{
        insertedTabView.drawsActiveBackground = NO;
      }];
    }
  });
}

- (void)animateSurvivingTabViewsFromPreviousFrames:(NSMapTable<TLChromeTabView *, NSValue *> *)previousFrames {
  for (TLChromeTabView *survivingTabView in self.tabViews) {
    NSValue *previousFrame = [previousFrames objectForKey:survivingTabView];
    if (!previousFrame) {
      continue;
    }
    CGFloat translationX = NSMinX(previousFrame.rectValue) - NSMinX(survivingTabView.frame);
    if (fabs(translationX) < 0.001) {
      continue;
    }
    [survivingTabView setReorderTranslationX:translationX
                                    animated:NO
                                    duration:self.palette.tabLifecycleTransitionDuration];
    [survivingTabView setReorderTranslationX:0.0
                                    animated:YES
                                    duration:self.palette.tabLifecycleTransitionDuration];
  }
}

- (void)setControlsEnabled:(BOOL)enabled disabledOpacity:(CGFloat)disabledOpacity {
  for (TLChromeTabView *tabView in self.tabViews) {
    tabView.enabled = enabled;
    tabView.alphaValue = enabled ? 1.0 : disabledOpacity;
  }
  [self updateSeparatorVisibility];
}

- (void)setNewTabButtonHovered:(BOOL)hovered {
  if (_newTabButtonHovered == hovered) {
    return;
  }

  _newTabButtonHovered = hovered;
  [self updateSeparatorVisibility];
}

- (void)configureWorkspaceTabView:(TLChromeTabView *)tabView
                           forTab:(TLWorkspaceTab *)tab
                            index:(NSUInteger)index
                             tabs:(NSArray<TLWorkspaceTab *> *)tabs {
  BOOL active = [self.delegate workspaceTabsController:self isTabActive:tab];
  tabView.palette = self.palette;
  tabView.title = [self.delegate workspaceTabsController:self displayTitleForTab:tab];
  tabView.image = [self.delegate workspaceTabsController:self displayImageForTab:tab];
  tabView.icon = [self.delegate workspaceTabsController:self displayIconForTab:tab];
  tabView.systemIconName = [self.delegate workspaceTabsController:self displaySystemIconNameForTab:tab];
  tabView.toolTip = [self.delegate workspaceTabsController:self displayToolTipForTab:tab];
  tabView.tag = tab.tabID;
  tabView.target = self.target;
  tabView.action = [self.delegate workspaceTabsController:self openActionForTab:tab];
  tabView.closeAction = [self.delegate workspaceTabsController:self closeActionForTab:tab];
  tabView.closeable = tab.closeable;
  tabView.canCloseOtherTabs = [tabs indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *candidate, NSUInteger candidateIndex, BOOL *stop) {
    return candidateIndex != index && candidate.closeable;
  }] != NSNotFound;
  tabView.active = active;
  tabView.drawsActiveBackground = NO;
  tabView.dragDelegate = self;
  tabView.representedObject = [tab copy];
  [tabView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
  [tabView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
}

- (void)updateSeparatorVisibility {
  if (self.draggedTab &&
      self.draggedStartIndex < self.tabViews.count &&
      self.draggedCurrentIndex < self.tabViews.count) {
    [self updateSeparatorVisibilityForDrag];
    return;
  }

  for (NSUInteger index = 0; index < self.tabViews.count; index += 1) {
    TLChromeTabView *tabView = self.tabViews[index];
    BOOL hovered = tabView.enabled && tabView.isHovered;
    TLChromeTabView *previousTabView = index > 0 ? self.tabViews[index - 1] : nil;
    BOOL previousHovered = previousTabView.enabled && previousTabView.isHovered;
    tabView.showsLeadingSeparator = !tabView.active &&
      !hovered &&
      index > 0 &&
      !previousTabView.active &&
      !previousHovered;
    tabView.showsTrailingSeparator = !tabView.active &&
      !hovered &&
      !self.newTabButtonHovered &&
      index == self.tabViews.count - 1;
  }
}

- (void)updateSeparatorVisibilityForDrag {
  NSMutableArray *visualSlots = [NSMutableArray arrayWithCapacity:self.tabViews.count];
  for (NSUInteger index = 0; index < self.tabViews.count; index += 1) {
    [visualSlots addObject:NSNull.null];
  }

  for (NSUInteger index = 0; index < self.tabViews.count; index += 1) {
    if (index == self.draggedStartIndex) {
      continue;
    }

    NSUInteger visualSlot = index;
    if (self.draggedCurrentIndex > self.draggedStartIndex &&
        index > self.draggedStartIndex && index <= self.draggedCurrentIndex) {
      visualSlot = index - 1;
    } else if (self.draggedCurrentIndex < self.draggedStartIndex &&
               index >= self.draggedCurrentIndex && index < self.draggedStartIndex) {
      visualSlot = index + 1;
    }
    visualSlots[visualSlot] = self.tabViews[index];
  }

  for (TLChromeTabView *tabView in self.tabViews) {
    NSUInteger visualSlot = [visualSlots indexOfObjectIdenticalTo:tabView];
    if (visualSlot == NSNotFound) {
      tabView.showsLeadingSeparator = NO;
      tabView.showsTrailingSeparator = NO;
      continue;
    }

    id previousSlot = visualSlot > 0 ? visualSlots[visualSlot - 1] : nil;
    TLChromeTabView *previousTabView = [previousSlot isKindOfClass:TLChromeTabView.class]
      ? previousSlot
      : nil;
    BOOL hovered = tabView.enabled && tabView.isHovered;
    BOOL previousHovered = previousTabView.enabled && previousTabView.isHovered;
    tabView.showsLeadingSeparator = !tabView.active &&
      !hovered &&
      previousTabView != nil &&
      !previousTabView.active &&
      !previousHovered;
    tabView.showsTrailingSeparator = !tabView.active &&
      !hovered &&
      !self.newTabButtonHovered &&
      visualSlot == self.tabViews.count - 1;
  }
}

- (void)updateSeparatorVisibilityWithoutAnimation {
  for (TLChromeTabView *tabView in self.tabViews) {
    tabView.animatesDecorationChanges = NO;
  }
  [self updateSeparatorVisibility];
  for (TLChromeTabView *tabView in self.tabViews) {
    tabView.animatesDecorationChanges = YES;
  }
}

- (void)chromeTabViewHoverStateDidChange:(TLChromeTabView *)tabView {
  [self updateSeparatorVisibility];
}

- (void)chromeTabViewDidRequestCloseOtherTabs:(TLChromeTabView *)tabView {
  TLWorkspaceTab *retainedTab = [tabView.representedObject isKindOfClass:TLWorkspaceTab.class]
    ? [tabView.representedObject copy]
    : nil;
  if (!retainedTab) {
    return;
  }

  NSArray<TLWorkspaceTab *> *tabs = [[self.delegate workspaceTabsForTabsController:self] copy];
  SEL openAction = [self.delegate workspaceTabsController:self openActionForTab:retainedTab];
  if (openAction) {
    NSButton *sender = [[NSButton alloc] init];
    sender.tag = retainedTab.tabID;
    [NSApp sendAction:openAction to:self.target from:sender];
  }

  for (TLWorkspaceTab *tab in tabs) {
    BOOL isRetainedTab = tab.kind == retainedTab.kind && tab.tabID == retainedTab.tabID;
    if (isRetainedTab || !tab.closeable) {
      continue;
    }

    SEL closeAction = [self.delegate workspaceTabsController:self closeActionForTab:tab];
    if (!closeAction) {
      continue;
    }
    NSButton *sender = [[NSButton alloc] init];
    sender.tag = tab.tabID;
    [NSApp sendAction:closeAction to:self.target from:sender];
  }
}

- (void)updateTabWidthsForAvailableWidth:(CGFloat)availableWidth {
  if (self.tabWidthConstraints.count == 0 || availableWidth <= self.palette.space0) {
    return;
  }

  CGFloat tabCount = (CGFloat)self.tabWidthConstraints.count;
  CGFloat sharedBoundaryCount = MAX(self.palette.space0, tabCount - 1.0);
  CGFloat maximumOverlap = TLChromeTabInterTabOverlapForWidth(self.palette.tabMaxWidth, self.palette);
  CGFloat equalWidth = (availableWidth + sharedBoundaryCount * maximumOverlap) / tabCount;
  CGFloat overlap = TLChromeTabInterTabOverlapForWidth(equalWidth, self.palette);
  if (overlap < maximumOverlap) {
    equalWidth = availableWidth / (tabCount - 0.27 * sharedBoundaryCount);
  }
  equalWidth = MIN(self.palette.tabMaxWidth, MAX(self.palette.borderWidth, equalWidth));
  overlap = TLChromeTabInterTabOverlapForWidth(equalWidth, self.palette);
  self.tabStack.spacing = -overlap;
  for (NSLayoutConstraint *constraint in self.tabWidthConstraints) {
    constraint.constant = equalWidth;
  }
  [self.tabStack invalidateIntrinsicContentSize];
  [self.tabStack setNeedsLayout:YES];
  [self.tabStack layoutSubtreeIfNeeded];
  if (!self.hasPendingSelectionAnimation) {
    [self updateSelectionIndicatorAnimated:NO];
  }
}

- (void)schedulePendingSelectionAnimation {
  if (self.selectionAnimationScheduled) {
    return;
  }
  self.selectionAnimationScheduled = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.selectionAnimationScheduled = NO;
    [self performPendingSelectionAnimation];
  });
}

- (void)performPendingSelectionAnimation {
  if (!self.hasPendingSelectionAnimation) {
    return;
  }
  [self.tabStack layoutSubtreeIfNeeded];
  NSInteger distance = labs((NSInteger)self.pendingSelectionTargetIndex -
                            (NSInteger)self.pendingSelectionStartIndex);
  if (distance > 2 && self.pendingSelectionTargetIndex < self.tabViews.count) {
    NSUInteger nearbyIndex = self.pendingSelectionStartIndex < self.pendingSelectionTargetIndex
      ? self.pendingSelectionTargetIndex - 1
      : self.pendingSelectionTargetIndex + 1;
    if (nearbyIndex < self.tabViews.count) {
      self.pendingSelectionStartFrame = self.tabViews[nearbyIndex].frame;
    }
  }
  [self updateSelectionIndicatorAnimated:YES];
  self.hasPendingSelectionAnimation = NO;
  NSUInteger generation = ++self.selectionTransitionGeneration;
  NSTimeInterval delay = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
    ? 0.0
    : self.palette.tabSelectionSlideDuration;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (generation != self.selectionTransitionGeneration) {
      return;
    }
    self.pendingSelectionStartIndex = NSNotFound;
    self.pendingSelectionTargetIndex = NSNotFound;
    [self updateSeparatorVisibilityWithoutAnimation];
  });
}

- (TLChromeTabView *)activeTabView {
  for (TLChromeTabView *tabView in self.tabViews) {
    if (tabView.active) {
      return tabView;
    }
  }
  return nil;
}

- (NSRect)visibleSelectionFrameWithFallback:(NSRect)fallbackFrame {
  if (self.selectionView.hidden) {
    return fallbackFrame;
  }
  return self.selectionView.selectionFrame;
}

- (void)updateSelectionIndicatorAnimated:(BOOL)animated {
  TLChromeTabView *activeTabView = [self activeTabView];
  if (!activeTabView) {
    self.selectionView.hidden = YES;
    return;
  }

  NSRect targetFrame = activeTabView.frame;
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    if (transition.incomingSelectedTab == activeTabView) {
      targetFrame.origin.x = NSMinX(transition.originalTabFrame);
    }
  }
  NSRect startFrame = self.hasPendingSelectionAnimation
    ? self.pendingSelectionStartFrame
    : [self visibleSelectionFrameWithFallback:targetFrame];
  BOOL shouldAnimate = animated && !self.selectionView.hidden && self.tabStack.window &&
    self.palette.tabSelectionSlideDuration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion &&
    !NSEqualRects(startFrame, targetFrame);

  self.selectionView.frame = self.tabStack.bounds;
  self.selectionView.palette = self.palette;
  self.selectionView.hidden = NO;
  [self.selectionView layoutSubtreeIfNeeded];
  [self.selectionView setSelectionFrame:targetFrame
                     leadingFlareOutset:activeTabView.leadingFlareOutset
                              animated:shouldAnimate
                             fromFrame:startFrame
                               duration:self.palette.tabSelectionSlideDuration];
}

- (void)updateEdgeAttachmentState {
  [self resetTabLeadingFlares];

  CGFloat contentRadius = self.palette.space5;
  TLChromeTabView *firstTabView = self.tabViews.firstObject;
  firstTabView.leadingFlareOutset = self.palette.space0;
  if (firstTabView.active && [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]) {
    contentRadius = self.palette.space0;
  }

  [self.delegate workspaceTabsController:self firstTabEdgeCornerRadiusDidChange:contentRadius];
}

- (void)chromeTabView:(TLChromeTabView *)tabView didDragWithEvent:(NSEvent *)event {
  NSUInteger currentIndex = [self.tabViews indexOfObject:tabView];
  if (currentIndex == NSNotFound) {
    return;
  }

  if (!self.draggedTab) {
    self.draggedTab = [tabView.representedObject isKindOfClass:TLWorkspaceTab.class] ? [tabView.representedObject copy] : nil;
    self.draggedStartIndex = currentIndex;
    self.draggedCurrentIndex = currentIndex;
    self.hasPendingSelectionAnimation = NO;
    self.pendingSelectionStartIndex = NSNotFound;
    self.pendingSelectionTargetIndex = NSNotFound;
    self.selectionTransitionGeneration += 1;
    [self updateSeparatorVisibilityWithoutAnimation];
  }
  [self promoteSelectionAndDraggedTabView:tabView];

  [self.tabStack layoutSubtreeIfNeeded];
  NSUInteger targetIndex = [self targetIndexForDraggedTabView:tabView];
  if (targetIndex != NSNotFound) {
    self.draggedCurrentIndex = targetIndex;
  }
  [self updateReorderGapForDraggedTabView:tabView targetIndex:self.draggedCurrentIndex];
  [self updateSeparatorVisibilityWithoutAnimation];
  [self updateDragEdgeGeometryForDraggedTabView:tabView targetIndex:self.draggedCurrentIndex];
  if (tabView.active) {
    NSRect draggedFrame = NSOffsetRect(tabView.frame, tabView.dragTranslationX, 0.0);
    self.selectionView.frame = self.tabStack.bounds;
    [self.selectionView layoutSubtreeIfNeeded];
    [self.selectionView setSelectionFrame:draggedFrame
                       leadingFlareOutset:tabView.leadingFlareOutset
                                animated:NO
                               fromFrame:self.selectionView.selectionFrame
                                 duration:self.palette.tabSelectionSlideDuration];
  }
}

- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView {
  TLWorkspaceTab *movedTab = self.draggedTab;
  NSUInteger sourceIndex = self.draggedStartIndex;
  NSUInteger targetIndex = self.draggedCurrentIndex;
  [self resetReorderGap];
  [self resetDragEdgeGeometry];
  [self.tabStack addSubview:self.selectionView positioned:NSWindowBelow relativeTo:nil];
  self.draggedTab = nil;
  self.draggedStartIndex = NSNotFound;
  self.draggedCurrentIndex = NSNotFound;

  if (movedTab && targetIndex != NSNotFound && sourceIndex != targetIndex) {
    [self.delegate workspaceTabsController:self moveTab:movedTab toIndex:targetIndex];
  }

  [self.tabStack layoutSubtreeIfNeeded];
  [self updateSelectionIndicatorAnimated:NO];
  [self updateSeparatorVisibilityWithoutAnimation];
}

- (CGFloat)chromeTabView:(TLChromeTabView *)tabView
constrainedHorizontalTranslationForEvent:(NSEvent *)event
     proposedTranslation:(CGFloat)translationX {
  NSRect contentBounds = [self.delegate workspaceTabsControllerContentDragBoundsInWindow:self];
  if (NSIsEmptyRect(contentBounds) || !tabView.superview) {
    return translationX;
  }

  NSRect tabFrame = [tabView.superview convertRect:tabView.frame toView:nil];
  NSRect newTabButtonBounds = [self.delegate workspaceTabsControllerNewTabButtonBoundsInWindow:self];
  CGFloat maximumTabMaxX = NSMaxX(contentBounds);
  if (!NSIsEmptyRect(newTabButtonBounds)) {
    maximumTabMaxX = MIN(maximumTabMaxX, NSMinX(newTabButtonBounds) - self.palette.space2);
  }
  TLChromeTabView *lastTabView = self.tabViews.lastObject;
  if (lastTabView.superview) {
    NSRect lastTabFrame = [lastTabView.superview convertRect:lastTabView.frame toView:nil];
    maximumTabMaxX = MIN(NSMaxX(contentBounds), MAX(maximumTabMaxX, NSMaxX(lastTabFrame)));
  }
  CGFloat minimumTranslation = NSMinX(contentBounds) - NSMinX(tabFrame);
  CGFloat maximumTranslation = maximumTabMaxX - NSMaxX(tabFrame);
  if (minimumTranslation > maximumTranslation) {
    return 0.0;
  }

  return MIN(MAX(translationX, minimumTranslation), maximumTranslation);
}

- (NSUInteger)targetIndexForDraggedTabView:(TLChromeTabView *)draggedTabView {
  if (self.tabViews.count == 0) {
    return NSNotFound;
  }

  CGFloat draggedMidX = NSMidX(draggedTabView.frame) + draggedTabView.dragTranslationX;
  NSUInteger targetIndex = 0;
  CGFloat nearestDistance = CGFLOAT_MAX;
  for (NSUInteger index = 0; index < self.tabViews.count; index += 1) {
    CGFloat distance = fabs(draggedMidX - NSMidX(self.tabViews[index].frame));
    if (distance < nearestDistance) {
      nearestDistance = distance;
      targetIndex = index;
    }
  }

  return MIN(targetIndex, self.tabViews.count - 1);
}

- (void)promoteSelectionAndDraggedTabView:(TLChromeTabView *)draggedTabView {
  [self.tabStack addSubview:self.selectionView positioned:NSWindowAbove relativeTo:nil];
  [self.tabStack addSubview:draggedTabView positioned:NSWindowAbove relativeTo:self.selectionView];
  draggedTabView.layer.zPosition = 2.0;
}

- (void)updateReorderGapForDraggedTabView:(TLChromeTabView *)draggedTabView
                              targetIndex:(NSUInteger)targetIndex {
  if (self.draggedStartIndex == NSNotFound || targetIndex == NSNotFound) {
    return;
  }

  for (NSUInteger index = 0; index < self.tabViews.count; index += 1) {
    TLChromeTabView *tabView = self.tabViews[index];
    if (tabView == draggedTabView) {
      [tabView setReorderTranslationX:0.0 animated:NO];
      continue;
    }

    CGFloat translationX = 0.0;
    if (targetIndex > self.draggedStartIndex &&
        index > self.draggedStartIndex && index <= targetIndex) {
      translationX = NSMinX(self.tabViews[index - 1].frame) - NSMinX(tabView.frame);
    } else if (targetIndex < self.draggedStartIndex &&
               index >= targetIndex && index < self.draggedStartIndex) {
      translationX = NSMinX(self.tabViews[index + 1].frame) - NSMinX(tabView.frame);
    }
    [tabView setReorderTranslationX:translationX animated:YES];
  }
}

- (void)resetReorderGap {
  for (TLChromeTabView *tabView in self.tabViews) {
    [tabView setReorderTranslationX:0.0 animated:NO];
  }
}

- (void)updateDragEdgeGeometryForDraggedTabView:(TLChromeTabView *)draggedTabView targetIndex:(NSUInteger)targetIndex {
  [self resetTabLeadingFlares];

  CGFloat contentRadius = self.palette.space5;
  TLChromeTabView *firstTabView = self.tabViews.firstObject;
  if (targetIndex == 0 && draggedTabView.superview) {
    NSRect contentBounds = [self.delegate workspaceTabsControllerContentDragBoundsInWindow:self];
    if (!NSIsEmptyRect(contentBounds)) {
      NSRect tabFrame = [draggedTabView.superview convertRect:draggedTabView.frame toView:nil];
      CGFloat draggedMinX = NSMinX(tabFrame) + draggedTabView.dragTranslationX;
      CGFloat distanceToEdge = MAX(0.0, draggedMinX - NSMinX(contentBounds));
      contentRadius = MIN(self.palette.space5, distanceToEdge);
      draggedTabView.leadingFlareOutset = MIN(self.palette.tabFlareRadius, distanceToEdge);
    }
  } else if (draggedTabView != firstTabView) {
    firstTabView.leadingFlareOutset = self.palette.space0;
    if (firstTabView.active && [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]) {
      contentRadius = self.palette.space0;
    }
  }

  [self.delegate workspaceTabsController:self firstTabEdgeCornerRadiusDidChange:contentRadius];
}

- (void)resetDragEdgeGeometry {
  [self updateEdgeAttachmentState];
}

- (void)resetTabLeadingFlares {
  for (TLChromeTabView *tabView in self.tabViews) {
    tabView.leadingFlareOutset = -1.0;
  }
}

@end
