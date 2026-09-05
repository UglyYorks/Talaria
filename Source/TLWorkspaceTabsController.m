#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"
#import <QuartzCore/QuartzCore.h>

static NSString *TLTabIdentity(TLWorkspaceTab *tab) {
  return tab.presentationIdentity ?: [NSString stringWithFormat:@"%ld:%ld", (long)tab.kind, (long)tab.tabID];
}

static NSRect TLInterpolateTabFrame(NSRect start, NSRect end, CGFloat progress) {
  return NSMakeRect(start.origin.x + (end.origin.x - start.origin.x) * progress,
                    start.origin.y + (end.origin.y - start.origin.y) * progress,
                    start.size.width + (end.size.width - start.size.width) * progress,
                    start.size.height + (end.size.height - start.size.height) * progress);
}

@interface TLTabRemovalTransition : NSObject
@property (nonatomic, strong) TLChromeTabView *tabView;
@property (nonatomic, strong) NSView *placeholderView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic) NSUInteger arrangedIndex;
@property (nonatomic) NSRect originalTabFrame;
@property (nonatomic, strong) TLChromeTabView *incomingSelectedTab;
@property (nonatomic, strong) TLChromeTabView *selectedSuccessor;
@property (nonatomic) CGFloat initialMaskWidth;
@property (nonatomic) CGFloat initialOpacity;
@property (nonatomic) BOOL clipsToSelection;
@property (nonatomic) BOOL tracksTrailingButton;
@property (nonatomic) CGFloat buttonSpacing;
@end

@implementation TLTabRemovalTransition
@end

@interface TLWorkspaceTabsController () <TLChromeTabViewDelegate>

@property (nonatomic, strong) NSStackView *tabStack;
@property (nonatomic, strong) NSMutableArray<TLChromeTabView *> *tabViews;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *tabWidthConstraints;
@property (nonatomic, strong) NSMutableArray<TLChromeTabView *> *removingTabViews;
@property (nonatomic, strong) NSMutableArray<TLTabRemovalTransition *> *removalTransitions;
@property (nonatomic) BOOL settlingDrop;
@property (nonatomic, strong) TLChromeTabSelectionView *selectionView;
@property (nonatomic) NSRect pendingSelectionStartFrame;
@property (nonatomic) BOOL hasPendingSelectionAnimation;
@property (nonatomic) BOOL selectionAnimationScheduled;
@property (nonatomic) NSUInteger pendingSelectionStartIndex;
@property (nonatomic) NSUInteger pendingSelectionTargetIndex;
@property (nonatomic, strong) TLTransitionCoordinator *transitionCoordinator;
@property (nonatomic, copy) NSArray<TLChromeTabView *> *insertingTabViews;
@property (nonatomic, strong, nullable) TLWorkspaceTab *draggedTab;
@property (nonatomic) NSUInteger draggedStartIndex;
@property (nonatomic) NSUInteger draggedCurrentIndex;
@property (nonatomic) BOOL newTabButtonHovered;
@property (nonatomic) NSRect previousNewTabButtonFrame;
@property (nonatomic) CGFloat preservedTabWidth;
@property (nonatomic) BOOL restoringTabWidths;
@property (nonatomic) BOOL completingTabLifecycle;
@property (nonatomic) CGFloat latestAvailableWidth;
@property (nonatomic) BOOL hasAvailableWidth;
@property (nonatomic, strong) NSTrackingArea *widthPreservationTrackingArea;
@property (nonatomic, weak) NSView *widthPreservationHost;

- (void)configureWorkspaceTabView:(TLChromeTabView *)tabView
                           forTab:(TLWorkspaceTab *)tab
                            index:(NSUInteger)index
                             tabs:(NSArray<TLWorkspaceTab *> *)tabs;
- (void)updateSelectionForLifecycle;

@end

@implementation TLWorkspaceTabsController

- (instancetype)initWithTabStack:(NSStackView *)tabStack
                          target:(id)target
                        delegate:(id<TLWorkspaceTabsControllerDelegate>)delegate
                         palette:(TLThemePalette *)palette {
  return [self initWithTabStack:tabStack target:target delegate:delegate palette:palette
         transitionCoordinator:[[TLTransitionCoordinator alloc] init]];
}

- (instancetype)initWithTabStack:(NSStackView *)tabStack target:(id)target
                        delegate:(id<TLWorkspaceTabsControllerDelegate>)delegate
                         palette:(TLThemePalette *)palette
           transitionCoordinator:(TLTransitionCoordinator *)transitionCoordinator {
  self = [super init];
  if (self) {
    _tabStack = tabStack;
    _target = target;
    _delegate = delegate;
    _palette = palette;
    _transitionCoordinator = transitionCoordinator;
    _tabViews = [NSMutableArray array];
    _tabWidthConstraints = [NSMutableArray array];
    _removingTabViews = [NSMutableArray array];
    _removalTransitions = [NSMutableArray array];
    _selectionView = [[TLChromeTabSelectionView alloc] init];
    // Keep click-to-select motion below tabs and separators. Only dragging
    // raises the slab above neighboring content, below the dragged tab itself.
    _selectionView.layer.zPosition = -1.0;
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
  NSArray<TLWorkspaceTab *> *tabs = [self.delegate workspaceTabsForTabsController:self];
  NSMutableSet *incomingIDs = [NSMutableSet set];
  NSMutableSet *previousIDs = [NSMutableSet set];
  for (TLWorkspaceTab *tab in tabs) [incomingIDs addObject:TLTabIdentity(tab)];
  for (TLChromeTabView *view in self.tabViews) [previousIDs addObject:TLTabIdentity(view.representedObject)];
  BOOL hasInsertion = ![incomingIDs isSubsetOfSet:previousIDs];
  BOOL hasRemoval = ![previousIDs isSubsetOfSet:incomingIDs];
  if (hasInsertion || tabs.count == 0) {
    [self clearPreservedTabWidth];
  } else if (hasRemoval) {
    [self preserveTabWidthWhileHovered];
  }
  BOOL structureChanged = tabs.count != self.tabViews.count;
  for (NSUInteger index = 0; !structureChanged && index < tabs.count; index += 1) {
    structureChanged = ![TLTabIdentity(tabs[index]) isEqual:TLTabIdentity(self.tabViews[index].representedObject)];
  }
  NSMapTable<TLChromeTabView *, NSArray<NSNumber *> *> *visibleAppearances = [NSMapTable strongToStrongObjectsMapTable];
  for (TLChromeTabView *view in self.tabViews) {
    [visibleAppearances setObject:@[@(view.lifecycleVisibleWidth), @(view.lifecycleContentOpacity)] forKey:view];
  }
  NSRect previousButtonFrame = [self.delegate workspaceTabsControllerNewTabButtonBoundsInWindow:self];
  if (structureChanged) [self.transitionCoordinator finishAllTransitions];
  self.previousNewTabButtonFrame = previousButtonFrame;
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

  [self.tabViews removeAllObjects];
  [self.tabWidthConstraints removeAllObjects];
  NSMutableArray<TLChromeTabView *> *insertedTabViews = [NSMutableArray array];
  NSMutableDictionary<NSString *, TLChromeTabView *> *viewsByID = [NSMutableDictionary dictionary];
  for (TLChromeTabView *view in previousTabViews) viewsByID[TLTabIdentity(view.representedObject)] = view;
  for (NSUInteger index = 0; index < tabs.count; index += 1) {
    TLWorkspaceTab *tab = tabs[index];
    TLChromeTabView *tabView = viewsByID[TLTabIdentity(tab)];

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

    [self configureWorkspaceTabView:tabView forTab:tab index:index tabs:tabs];
    [self.tabViews addObject:tabView];
    [self.tabWidthConstraints addObject:width];
    if (![self.tabStack.arrangedSubviews containsObject:tabView]) [self.tabStack addArrangedSubview:tabView];
  }
  NSMutableArray<TLTabRemovalTransition *> *newRemovalTransitions = [NSMutableArray array];
  for (TLChromeTabView *removedTabView in availableTabViews) {
    NSUInteger previousIndex = [previousTabViews indexOfObjectIdenticalTo:removedTabView];
    if (previousIndex == NSNotFound || previousIndex >= previousWidthConstraints.count) {
      continue;
    }
    TLTabRemovalTransition *transition = [[TLTabRemovalTransition alloc] init];
    transition.tabView = removedTabView;
    if (previousIndex + 1 < previousTabViews.count &&
        previousTabViews[previousIndex + 1] == previousActiveView &&
        [self.tabViews containsObject:previousActiveView]) {
      transition.selectedSuccessor = previousActiveView;
    }
    transition.clipsToSelection = removedTabView == previousActiveView;
    transition.tracksTrailingButton = transition.clipsToSelection && removedTabView == previousTabViews.lastObject;
    transition.placeholderView = [[NSView alloc] init];
    transition.placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
    transition.placeholderView.wantsLayer = YES;
    transition.widthConstraint = [transition.placeholderView.widthAnchor constraintEqualToConstant:self.palette.tabMaxWidth];
    [NSLayoutConstraint activateConstraints:@[
      transition.widthConstraint,
      [transition.placeholderView.heightAnchor constraintEqualToConstant:self.palette.tabHeight],
    ]];
    transition.arrangedIndex = previousIndex;
    NSArray<NSNumber *> *appearance = [visibleAppearances objectForKey:removedTabView];
    transition.initialMaskWidth = appearance ? appearance[0].doubleValue : NSWidth(removedTabView.bounds);
    transition.initialOpacity = appearance ? appearance[1].doubleValue : 1.0;
    [self.tabStack removeArrangedSubview:removedTabView];
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
  NSMutableArray<NSView *> *desiredViews = [self.tabViews mutableCopy];
  for (TLTabRemovalTransition *transition in orderedTransitions) {
    [desiredViews insertObject:transition.placeholderView atIndex:MIN(transition.arrangedIndex, desiredViews.count)];
  }
  for (NSUInteger index = 0; index < desiredViews.count; index += 1) {
    NSView *view = desiredViews[index];
    NSArray *arranged = self.tabStack.arrangedSubviews;
    if (index < arranged.count && arranged[index] == view) continue;
    if ([arranged containsObject:view]) [self.tabStack removeArrangedSubview:view];
    [self.tabStack insertArrangedSubview:view atIndex:index];
  }
  // Fit additions before any lifecycle layout can propagate their default
  // widths up to the window's fitting size.
  TLChromeTabView *nextActiveView = [self activeTabView];
  if (hasRemoval && previousActiveView && nextActiveView != previousActiveView && nextActiveView) {
    // Reserve the old visual frame before the lifecycle's initial layout tick.
    // Otherwise that tick paints the fallback tab before its slide is scheduled.
    self.pendingSelectionStartFrame = previousSelectionFrame;
    self.pendingSelectionStartIndex = previousActiveIndex;
    self.pendingSelectionTargetIndex = [self.tabViews indexOfObject:nextActiveView];
    self.hasPendingSelectionAnimation = YES;
  }
  if (hasInsertion && self.hasAvailableWidth) [self applyTabWidthsForAvailableWidth:self.latestAvailableWidth];
  [self animateLifecycleWithRemovedTransitions:newRemovalTransitions
                             insertedTabViews:insertedTabViews
                                previousFrames:previousFrames
                           previousActiveIndex:previousActiveIndex];
  [self bringRemovingTabViewsToFront];
  TLChromeTabView *activeTabView = [self activeTabView];
  NSUInteger activeTabIndex = [self.tabViews indexOfObject:activeTabView];
  TLWorkspaceTab *activeTab = [activeTabView.representedObject isKindOfClass:TLWorkspaceTab.class]
    ? activeTabView.representedObject
    : nil;
  BOOL activeTabChanged = previousActiveTab && activeTab &&
    ![TLTabIdentity(previousActiveTab) isEqual:TLTabIdentity(activeTab)];
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
    if (hasRemoval) [self performPendingSelectionAnimation];
    else [self schedulePendingSelectionAnimation];
  } else if (!self.hasPendingSelectionAnimation) {
    [self updateSelectionIndicatorAnimated:NO];
  }
  if (structureChanged) {
    [self updateSeparatorVisibilityWithoutAnimation];
  } else {
    [self updateSeparatorVisibility];
  }
  [self updateEdgeAttachmentState];
}

- (NSTimeInterval)lifecycleDuration {
  return self.tabStack.window && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
    ? self.palette.tabLifecycleTransitionDuration : 0.0;
}

- (void)refreshAnimationActivity {
  if (self.animationActivityChanged) self.animationActivityChanged(self.transitionCoordinator.hasTransitions);
}

- (void)animateLifecycleWithRemovedTransitions:(NSArray<TLTabRemovalTransition *> *)transitions
                             insertedTabViews:(NSArray<TLChromeTabView *> *)insertedTabViews
                                previousFrames:(NSMapTable<TLChromeTabView *, NSValue *> *)previousFrames
                           previousActiveIndex:(NSUInteger)previousActiveIndex {
  if (transitions.count == 0 && insertedTabViews.count == 0) return;
  for (TLTabRemovalTransition *transition in transitions) {
    TLChromeTabView *view = transition.tabView;
    view.frame = transition.originalTabFrame;
    view.enabled = NO;
    view.drawsActiveBackground = NO;
    [self.removingTabViews addObject:view];
    [self.tabStack addSubview:view positioned:NSWindowAbove relativeTo:nil];
  }
  NSView *layoutRoot = self.tabStack.superview ?: self.tabStack;
  [layoutRoot layoutSubtreeIfNeeded];
  CGFloat buttonSpacing = self.createTabButtonSpacingConstraint.constant;
  for (TLTabRemovalTransition *transition in transitions) transition.buttonSpacing = buttonSpacing;
  NSRect targetButtonFrame = [self.delegate workspaceTabsControllerNewTabButtonBoundsInWindow:self];
  CGFloat buttonTranslation = insertedTabViews.count > 0 && !NSIsEmptyRect(self.previousNewTabButtonFrame)
    ? NSMinX(self.previousNewTabButtonFrame) - NSMinX(targetButtonFrame) : 0;
  NSRect startSelection = self.selectionView.selectionFrame;
  TLChromeTabView *insertedActive = [self activeTabView];
  if ([insertedTabViews containsObject:insertedActive]) {
    startSelection = [self selectionStartFrame:startSelection fromIndex:previousActiveIndex
                                      toIndex:[self.tabViews indexOfObject:insertedActive]];
  }
  self.insertingTabViews = insertedTabViews;
  for (TLChromeTabView *view in insertedTabViews) [view prepareForInsertionAnimation];
  __weak typeof(self) weakSelf = self;
  // One batch can remove and insert together (for example when persisting a
  // draft). Both halves share the track, so neither cancels the other's cleanup.
  BOOL openingOnly = insertedTabViews.count > 0 && transitions.count == 0;
  NSTimeInterval duration = [self lifecycleDuration];
  if (insertedTabViews.count == 0 && duration > 0) duration = self.palette.tabClosingTransitionDuration;
  [self.transitionCoordinator startTransitionForKey:@"lifecycle" duration:duration
    curve:openingOnly ? TLTransitionCurveEaseOut : TLTransitionCurveEaseInOut
    update:^(CGFloat progress) {
      TLWorkspaceTabsController *owner = weakSelf;
      if (!owner) return;
      CGFloat collapsedWidth = MAX(owner.palette.space0, -owner.tabStack.spacing);
      [owner refreshAnimationActivity];
      // Move the actual hit target and artwork together, not just its layer.
      owner.createTabButtonSpacingConstraint.constant = buttonSpacing - buttonTranslation * (1.0 - progress);
      for (TLTabRemovalTransition *transition in transitions) {
        CGFloat startWidth = NSWidth(transition.originalTabFrame);
        transition.widthConstraint.constant = startWidth + (collapsedWidth - startWidth) * progress;
      }
      NSView *layoutRoot = owner.tabStack.superview ?: owner.tabStack;
      [layoutRoot layoutSubtreeIfNeeded];
      for (TLTabRemovalTransition *transition in transitions) {
        NSRect contentFrame = transition.originalTabFrame;
        contentFrame.origin = transition.placeholderView.frame.origin;
        transition.tabView.frame = contentFrame;
        CGFloat width = transition.initialMaskWidth + (collapsedWidth - transition.initialMaskWidth) * progress;
        // The mask and neighboring layout use the same model frame on this tick.
        width = MIN(width, NSWidth(transition.placeholderView.frame));
        CGFloat fadeRatio = MAX(0.001, owner.palette.tabLifecycleContentFadeDurationRatio);
        // Fade during the opening part of closure, then finish shrinking the slot.
        CGFloat opacity = transition.initialOpacity * (1.0 - MIN(1.0, progress / fadeRatio));
        [transition.tabView setLifecycleVisibleWidth:width contentOpacity:opacity];
      }
      CGFloat ratio = owner.palette.tabLifecycleCollapsedWidthRatio;
      CGFloat widthRatio = ratio + (1.0 - ratio) * progress;
      for (TLChromeTabView *view in insertedTabViews) {
        [view setLifecycleVisibleWidth:NSWidth(view.bounds) * widthRatio contentOpacity:1.0];
      }
      if (insertedTabViews.count > 0) {
        for (TLChromeTabView *view in owner.tabViews) {
          NSValue *previous = [previousFrames objectForKey:view];
          if (previous) [view setReorderTranslationX:(NSMinX(previous.rectValue) - NSMinX(view.frame)) * (1.0 - progress) animated:NO];
        }
      }
      TLChromeTabView *active = [owner activeTabView];
      if ([insertedTabViews containsObject:active]) {
        NSRect target = active.frame;
        target.size.width *= widthRatio;
        // Keep travel synchronized with the + button on the lifecycle curve.
        NSRect frame = TLInterpolateTabFrame(startSelection, target, progress);
        owner.selectionView.frame = owner.tabStack.bounds;
        owner.selectionView.hidden = NO;
        [owner.selectionView setSelectionFrame:frame leadingFlareOutset:active.leadingFlareOutset
                                      animated:NO fromFrame:frame duration:0.0];
        if (active == owner.tabViews.lastObject) {
          // Follow the growing slab's trailing edge, not only its horizontal travel.
          CGFloat edgeSpacing = buttonSpacing + NSMaxX(active.frame) - NSMaxX(frame);
          // If the selection started earlier in the strip, don't pull + over
          // existing tabs; let the background catch up to the previous end first.
          owner.createTabButtonSpacingConstraint.constant = MIN(edgeSpacing, buttonSpacing - buttonTranslation);
          [layoutRoot layoutSubtreeIfNeeded];
        }
      } else {
        [owner updateSelectionForLifecycle];
      }
      [owner updateSelectionEdgeGeometry];
      if ([insertedTabViews containsObject:active]) {
        [active clipLifecycleContentToSelectionView:owner.selectionView];
      }
      [owner updateClosingContentBackgroundClips];
      [owner updateTrailingButtonForRemoval];
    } completion:^(BOOL finished) {
      TLWorkspaceTabsController *owner = weakSelf;
      if (!owner) return;
      owner.completingTabLifecycle = YES;
      owner.createTabButtonSpacingConstraint.constant = buttonSpacing;
      for (TLTabRemovalTransition *transition in transitions) {
        [owner.tabStack removeArrangedSubview:transition.placeholderView];
        [transition.placeholderView removeFromSuperview];
        [transition.tabView removeFromSuperview];
        [owner.removingTabViews removeObjectIdenticalTo:transition.tabView];
        [owner.removalTransitions removeObjectIdenticalTo:transition];
      }
      for (TLChromeTabView *view in insertedTabViews) [view resetLifecycleAppearance];
      owner.insertingTabViews = @[];
      for (TLChromeTabView *view in owner.tabViews) [view setReorderTranslationX:0.0 animated:NO];
      [(owner.tabStack.superview ?: owner.tabStack) layoutSubtreeIfNeeded];
      [owner updateSelectionForLifecycle];
      [owner updateSeparatorVisibilityWithoutAnimation];
      owner.completingTabLifecycle = NO;
      if (finished && owner.preservedTabWidth > 0 && ![owner isPointerInsidePreservedTabArea]) {
        [owner restoreNormalTabWidthsAnimated];
      }
      [owner refreshAnimationActivity];
    }];
}

- (void)updateSelectionForLifecycle {
  if (self.settlingDrop) return;
  if (self.hasPendingSelectionAnimation) return;
  if ([self.transitionCoordinator hasTransitionForKey:@"selection"]) return;
  TLChromeTabView *activeTabView = [self activeTabView];
  if (!activeTabView || [self.insertingTabViews containsObject:activeTabView]) return;
  NSRect frame = NSOffsetRect(activeTabView.frame, activeTabView.reorderTranslationX, 0.0);
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    if (transition.incomingSelectedTab == activeTabView) frame.origin.x = NSMinX(transition.originalTabFrame);
  }
  self.selectionView.frame = self.tabStack.bounds;
  self.selectionView.hidden = NO;
  [self.selectionView setSelectionFrame:frame leadingFlareOutset:activeTabView.leadingFlareOutset
                              animated:NO fromFrame:frame duration:0.0];
  [self updateSelectionEdgeGeometry];
}

- (void)updateClosingContentBackgroundClips {
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    if (transition.clipsToSelection) {
      [transition.tabView clipLifecycleContentToSelectionView:self.selectionView];
    }
  }
}

- (void)updateTrailingButtonForRemoval {
  if (self.selectionView.hidden || ![self activeTabView]) return;
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    if (!transition.tracksTrailingButton) continue;
    self.createTabButtonSpacingConstraint.constant = transition.buttonSpacing +
      NSMaxX(self.tabStack.bounds) - NSMaxX(self.selectionView.selectionFrame);
    [(self.tabStack.superview ?: self.tabStack) layoutSubtreeIfNeeded];
    break;
  }
}

- (void)bringRemovingTabViewsToFront {
  for (TLChromeTabView *view in self.removingTabViews) {
    if (view.superview == self.tabStack) [self.tabStack addSubview:view positioned:NSWindowAbove relativeTo:nil];
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
  [tabView updateTitle:[self.delegate workspaceTabsController:self displayTitleForTab:tab]
    image:[self.delegate workspaceTabsController:self displayImageForTab:tab]
    icon:[self.delegate workspaceTabsController:self displayIconForTab:tab]
    systemIconName:[self.delegate workspaceTabsController:self displaySystemIconNameForTab:tab]
    animated:tabView.representedObject != nil];
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

- (void)dealloc {
  [_widthPreservationHost removeTrackingArea:_widthPreservationTrackingArea];
}

- (void)clearPreservedTabWidth {
  if (self.widthPreservationTrackingArea) {
    [self.widthPreservationHost removeTrackingArea:self.widthPreservationTrackingArea];
  }
  self.widthPreservationTrackingArea = nil;
  self.widthPreservationHost = nil;
  self.preservedTabWidth = 0;
}

- (BOOL)isPointerInsidePreservedTabArea {
  NSView *host = self.widthPreservationHost;
  if (!host.window.isVisible || host.isHiddenOrHasHiddenAncestor) return NO;
  NSPoint point = [host convertPoint:host.window.mouseLocationOutsideOfEventStream fromView:nil];
  return NSPointInRect(point, self.widthPreservationTrackingArea.rect);
}

- (void)preserveTabWidthWhileHovered {
  if (self.preservedTabWidth > 0) return;
  NSView *host = self.tabStack.superview;
  if (!host.window.isVisible || self.tabStack.isHiddenOrHasHiddenAncestor || self.tabViews.count == 0) return;
  NSRect area = [self.tabStack convertRect:self.tabStack.bounds toView:host];
  NSPoint point = [host convertPoint:host.window.mouseLocationOutsideOfEventStream fromView:nil];
  if (!NSPointInRect(point, area)) return;
  self.preservedTabWidth = NSWidth(self.tabViews.firstObject.frame);
  self.widthPreservationHost = host;
  // Track the original strip on its stable parent, not the shrinking stack:
  // closing a tab must not itself count as the pointer leaving the area.
  self.widthPreservationTrackingArea = [[NSTrackingArea alloc] initWithRect:area
    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingAssumeInside
    owner:self userInfo:nil];
  [host addTrackingArea:self.widthPreservationTrackingArea];
}

- (void)mouseExited:(NSEvent *)event {
  if (!self.widthPreservationTrackingArea || [self isPointerInsidePreservedTabArea]) return;
  [self restoreNormalTabWidthsAnimated];
}

- (void)restoreNormalTabWidthsAnimated {
  // Keep the closing slot alive for its entire animation. The lifecycle
  // completion rechecks the pointer and releases the held widths afterward.
  if (self.completingTabLifecycle || self.hasPendingSelectionAnimation ||
      [self.transitionCoordinator hasTransitionForKey:@"lifecycle"] ||
      [self.transitionCoordinator hasTransitionForKey:@"selection"]) return;
  [self clearPreservedTabWidth];
  NSArray<NSLayoutConstraint *> *constraints = self.tabWidthConstraints.copy;
  NSArray<NSNumber *> *startWidths = [constraints valueForKey:@"constant"];
  CGFloat startSpacing = self.tabStack.spacing;
  if (![self applyTabWidthsForAvailableWidth:self.latestAvailableWidth]) return;
  NSArray<NSNumber *> *targetWidths = [constraints valueForKey:@"constant"];
  CGFloat targetSpacing = self.tabStack.spacing;
  self.restoringTabWidths = YES;
  __weak typeof(self) weakSelf = self;
  [self.transitionCoordinator startTransitionForKey:@"width-restoration" duration:[self lifecycleDuration]
    update:^(CGFloat progress) {
      TLWorkspaceTabsController *owner = weakSelf;
      if (!owner) return;
      for (NSUInteger index = 0; index < constraints.count; index++) {
        CGFloat start = startWidths[index].doubleValue;
        constraints[index].constant = start + (targetWidths[index].doubleValue - start) * progress;
      }
      [owner refreshAnimationActivity];
      owner.tabStack.spacing = startSpacing + (targetSpacing - startSpacing) * progress;
      // Layout the parent so tabs, separators, and the + hit target move together.
      [(owner.tabStack.superview ?: owner.tabStack) layoutSubtreeIfNeeded];
      [owner updateSelectionIndicatorAnimated:NO];
      [owner updateEdgeAttachmentState];
    } completion:^(BOOL finished) {
      weakSelf.restoringTabWidths = NO;
      [weakSelf refreshAnimationActivity];
    }];
}

- (BOOL)applyTabWidthsForAvailableWidth:(CGFloat)availableWidth {
  if (self.restoringTabWidths) {
    if (availableWidth == self.latestAvailableWidth) return NO;
    [self.transitionCoordinator cancelTransitionForKey:@"width-restoration"];
  }
  self.hasAvailableWidth = YES;
  self.latestAvailableWidth = availableWidth;
  if (self.preservedTabWidth > 0 && ![self isPointerInsidePreservedTabArea]) {
    [self restoreNormalTabWidthsAnimated];
    return NO;
  }
  if (self.tabWidthConstraints.count == 0) return NO;
  availableWidth = MAX(self.palette.space0, availableWidth);

  CGFloat tabCount = (CGFloat)self.tabWidthConstraints.count;
  CGFloat sharedBoundaryCount = MAX(self.palette.space0, tabCount - 1.0);
  // Solve against the actual overlap function, including its partially
  // compressed flare range, so spacing changes never expand the window.
  CGFloat lowerWidth = self.palette.space0;
  CGFloat upperWidth = self.palette.tabMaxWidth;
  for (NSUInteger iteration = 0; iteration < 48; iteration++) {
    CGFloat candidate = (lowerWidth + upperWidth) * 0.5;
    CGFloat occupiedWidth = tabCount * candidate - sharedBoundaryCount *
      TLChromeTabInterTabOverlapForWidth(candidate, self.palette);
    if (occupiedWidth <= availableWidth) lowerWidth = candidate;
    else upperWidth = candidate;
  }
  CGFloat equalWidth = lowerWidth;
  // A smaller window may still compress tabs, but closing tabs cannot grow them.
  if (self.preservedTabWidth > 0) equalWidth = MIN(equalWidth, self.preservedTabWidth);
  CGFloat overlap = TLChromeTabInterTabOverlapForWidth(equalWidth, self.palette);
  self.tabStack.spacing = -overlap;
  for (NSLayoutConstraint *constraint in self.tabWidthConstraints) {
    constraint.constant = equalWidth;
  }
  return YES;
}

- (void)updateTabWidthsForAvailableWidth:(CGFloat)availableWidth {
  if (![self applyTabWidthsForAvailableWidth:availableWidth]) return;
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
  self.pendingSelectionStartFrame = [self selectionStartFrame:self.pendingSelectionStartFrame
    fromIndex:self.pendingSelectionStartIndex toIndex:self.pendingSelectionTargetIndex];
  [self updateSelectionIndicatorAnimated:YES];
  self.hasPendingSelectionAnimation = NO;
  self.pendingSelectionStartIndex = NSNotFound;
  self.pendingSelectionTargetIndex = NSNotFound;
  if (self.preservedTabWidth > 0 && ![self isPointerInsidePreservedTabArea]) {
    [self restoreNormalTabWidthsAnimated];
  }
}

- (NSRect)selectionStartFrame:(NSRect)fallback fromIndex:(NSUInteger)source toIndex:(NSUInteger)destination {
  if (source == NSNotFound || destination >= self.tabViews.count ||
      labs((NSInteger)destination - (NSInteger)source) <= 2) return fallback;
  NSUInteger nearby = source < destination ? destination - 1 : destination + 1;
  if (nearby >= self.tabViews.count) return fallback;
  NSRect start = self.tabViews[nearby].frame;
  NSRect target = self.tabViews[destination].frame;
  start.origin.x = NSMinX(target) + (NSMinX(start) - NSMinX(target)) *
    self.palette.tabSelectionLongJumpDistanceMultiplier;
  return start;
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
  if (self.settlingDrop) {
    if (!animated) return;
    [self.transitionCoordinator cancelTransitionForKey:@"drop"];
  }
  TLChromeTabView *activeTabView = [self activeTabView];
  if (!activeTabView) {
    [self.transitionCoordinator cancelTransitionForKey:@"selection"];
    self.selectionView.hidden = YES;
    return;
  }
  if ([self.insertingTabViews containsObject:activeTabView]) return;
  if (!animated && (self.hasPendingSelectionAnimation ||
                   [self.transitionCoordinator hasTransitionForKey:@"selection"])) return;

  NSRect targetFrame = activeTabView.frame;
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    if (transition.incomingSelectedTab == activeTabView) {
      targetFrame.origin.x = NSMinX(transition.originalTabFrame);
    }
  }
  NSRect startFrame = self.hasPendingSelectionAnimation
    ? self.pendingSelectionStartFrame
    : [self visibleSelectionFrameWithFallback:targetFrame];
  BOOL neighboringTabs = self.hasPendingSelectionAnimation &&
    self.pendingSelectionStartIndex != NSNotFound && self.pendingSelectionTargetIndex != NSNotFound &&
    labs((NSInteger)self.pendingSelectionStartIndex - (NSInteger)self.pendingSelectionTargetIndex) == 1;
  NSTimeInterval duration = neighboringTabs ? self.palette.tabNeighborSelectionSlideDuration : self.palette.tabSelectionSlideDuration;
  BOOL teleports = self.hasPendingSelectionAnimation &&
    self.pendingSelectionStartIndex != NSNotFound && self.pendingSelectionTargetIndex < self.tabViews.count &&
    labs((NSInteger)self.pendingSelectionStartIndex - (NSInteger)self.pendingSelectionTargetIndex) > 2;
  if (teleports) duration = self.palette.tabTeleportSelectionSlideDuration;
  BOOL shouldAnimate = animated && !self.selectionView.hidden && self.tabStack.window &&
    self.palette.tabSelectionSlideDuration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion &&
    !NSEqualRects(startFrame, targetFrame);

  self.selectionView.frame = self.tabStack.bounds;
  self.selectionView.palette = self.palette;
  self.selectionView.hidden = NO;
  [self.selectionView layoutSubtreeIfNeeded];
  __weak typeof(self) weakSelf = self;
  [self.transitionCoordinator startTransitionForKey:@"selection"
    duration:shouldAnimate ? duration : 0.0
    curve:TLTransitionCurveEaseOut
    update:^(CGFloat progress) {
      TLWorkspaceTabsController *owner = weakSelf;
      if (!owner) return;
      NSRect frame = TLInterpolateTabFrame(startFrame, targetFrame, progress);
      [owner refreshAnimationActivity];
      [owner.selectionView setSelectionFrame:frame leadingFlareOutset:activeTabView.leadingFlareOutset
                                   animated:NO fromFrame:frame duration:0.0];
      [owner updateSelectionEdgeGeometry];
      [owner updateClosingContentBackgroundClips];
      [owner updateTrailingButtonForRemoval];
    } completion:^(BOOL finished) {
      if (finished) [weakSelf updateSelectionForLifecycle];
      if (finished && weakSelf.preservedTabWidth > 0 && ![weakSelf isPointerInsidePreservedTabArea]) {
        [weakSelf restoreNormalTabWidthsAnimated];
      }
      [weakSelf refreshAnimationActivity];
    }];
}

- (void)updateEdgeAttachmentState {
  [self resetTabLeadingFlares];

  CGFloat contentRadius = self.palette.space5;
  TLChromeTabView *firstTabView = self.tabViews.firstObject;
  firstTabView.leadingFlareOutset = self.palette.space0;
  if (!self.selectionView.hidden && self.tabViews.count > 0 && !self.draggedTab) {
    [self updateSelectionEdgeGeometry];
    return;
  }
  if (firstTabView.active && [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]) {
    contentRadius = self.palette.space0;
  }

  [self.delegate workspaceTabsController:self firstTabEdgeCornerRadiusDidChange:contentRadius];
}

- (void)updateSelectionEdgeGeometry {
  // Keep the slab below live tab content/separators, but above the closing
  // predecessor it is moving across. Restore normal layering if selection changes.
  TLChromeTabView *active = [self activeTabView];
  for (TLTabRemovalTransition *transition in self.removalTransitions) {
    transition.tabView.layer.zPosition = transition.selectedSuccessor && transition.selectedSuccessor == active ? -2.0 : 0.0;
  }
  if (self.draggedTab || self.selectionView.hidden || self.tabViews.count == 0) return;
  // The logical selection changes before the slab arrives. Derive attachment
  // from the visible slab instead, so entering and leaving the edge are symmetric.
  // Use the strip's fixed edge, not a tab whose position may itself be animating.
  CGFloat leadingEdge = NSMinX(self.tabStack.bounds) + self.tabStack.edgeInsets.left;
  // Content must approach its edge-connected inset with the tab, rather than
  // adopting first-tab padding as soon as its predecessor leaves the model.
  TLChromeTabView *firstTabView = self.tabViews.firstObject;
  CGFloat firstTabDistance = MAX(self.palette.space0,
    NSMinX(firstTabView.frame) + firstTabView.reorderTranslationX - leadingEdge);
  firstTabView.leadingFlareOutset = MIN(self.palette.tabFlareRadius, firstTabDistance);
  CGFloat distance = MAX(self.palette.space0, NSMinX(self.selectionView.selectionFrame) - leadingEdge);
  self.selectionView.leadingFlareOutset = MIN(self.palette.tabActiveFlareRadius, distance);
  CGFloat radius = [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]
    ? MIN(self.palette.space5, distance) : self.palette.space5;
  NSRect contentBounds = [self.delegate workspaceTabsControllerContentDragBoundsInWindow:self];
  if (self.tabStack.window && !NSIsEmptyRect(contentBounds)) {
    CGFloat contentEdge = NSMinX([self.tabStack convertRect:contentBounds fromView:nil]);
    radius = MIN(self.palette.space5, MAX(self.palette.space0,
      NSMinX(self.selectionView.selectionFrame) - contentEdge));
  }
  [self.delegate workspaceTabsController:self firstTabEdgeCornerRadiusDidChange:radius];
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
    [self.transitionCoordinator finishAllTransitions];
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
  NSMapTable<TLChromeTabView *, NSValue *> *visibleFrames = [NSMapTable strongToStrongObjectsMapTable];
  for (TLChromeTabView *view in self.tabViews) {
    CALayer *visible = view.layer.presentationLayer ?: view.layer;
    CGFloat offset = view == tabView ? view.dragTranslationX : visible.transform.m41;
    [visibleFrames setObject:[NSValue valueWithRect:NSOffsetRect(view.frame, offset, 0)] forKey:view];
  }
  NSRect selectionStart = self.selectionView.selectionFrame;
  [tabView finishPointerDrag];
  [self resetReorderGap];
  [self resetDragEdgeGeometry];
  self.draggedTab = nil;
  self.draggedStartIndex = NSNotFound;
  self.draggedCurrentIndex = NSNotFound;
  self.settlingDrop = YES;

  if (movedTab && targetIndex != NSNotFound && sourceIndex != targetIndex) {
    [self.delegate workspaceTabsController:self moveTab:movedTab toIndex:targetIndex];
  }

  [self.tabStack layoutSubtreeIfNeeded];
  [self updateSeparatorVisibilityWithoutAnimation];
  __weak typeof(self) weakSelf = self;
  NSTimeInterval duration = self.tabStack.window && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
    ? self.palette.tabReorderSlideDuration : 0;
  [self.transitionCoordinator startTransitionForKey:@"drop" duration:duration update:^(CGFloat progress) {
    TLWorkspaceTabsController *owner = weakSelf;
    if (!owner) return;
    for (TLChromeTabView *view in owner.tabViews) {
      NSValue *start = [visibleFrames objectForKey:view];
      if (start) [view setReorderTranslationX:(NSMinX(start.rectValue) - NSMinX(view.frame)) * (1 - progress) animated:NO];
    }
    [owner promoteSelectionAndDraggedTabView:tabView];
    TLChromeTabView *active = [owner activeTabView];
    NSRect frame = TLInterpolateTabFrame(selectionStart, active.frame, progress);
    [owner.selectionView setSelectionFrame:frame leadingFlareOutset:active.leadingFlareOutset animated:NO fromFrame:frame duration:0];
    [owner updateSelectionEdgeGeometry];
    [owner refreshAnimationActivity];
  } completion:^(BOOL finished) {
    TLWorkspaceTabsController *owner = weakSelf;
    if (!owner) return;
    owner.settlingDrop = NO;
    [owner resetReorderGap];
    tabView.layer.zPosition = tabView.active ? 1 : 0;
    [owner.tabStack addSubview:owner.selectionView positioned:NSWindowBelow relativeTo:nil];
    owner.selectionView.layer.zPosition = -1;
    [owner updateSelectionForLifecycle];
    [owner updateEdgeAttachmentState];
    [owner updateSeparatorVisibilityWithoutAnimation];
    [owner refreshAnimationActivity];
  }];
}

- (BOOL)chromeTabViewShouldOpenContextMenu:(TLChromeTabView *)tabView {
  return !self.draggedTab && !self.settlingDrop;
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
  self.selectionView.layer.zPosition = 1.5;
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
      draggedTabView.leadingFlareOutset = MIN(self.palette.tabActiveFlareRadius, distanceToEdge);
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
