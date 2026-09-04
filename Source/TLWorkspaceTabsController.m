#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"

@interface TLWorkspaceTabsController () <TLChromeTabViewDelegate>

@property (nonatomic, strong) NSStackView *tabStack;
@property (nonatomic, strong) NSMutableArray<TLChromeTabView *> *tabViews;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *tabWidthConstraints;
@property (nonatomic, strong, nullable) TLWorkspaceTab *draggedTab;
@property (nonatomic) NSUInteger draggedStartIndex;
@property (nonatomic) NSUInteger draggedCurrentIndex;

@end

@implementation TLWorkspaceTabsController

static CGFloat TLTabFlareOverlapForWidth(CGFloat width, TLThemePalette *palette) {
  return MIN(palette.tabFlareRadius, width * 0.18);
}

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
    _tabStack.spacing = -TLTabFlareOverlapForWidth(palette.tabMaxWidth, palette);
    _draggedStartIndex = NSNotFound;
    _draggedCurrentIndex = NSNotFound;
  }
  return self;
}

- (void)reloadTabs {
  for (NSView *view in self.tabStack.arrangedSubviews.copy) {
    [self.tabStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }

  [self.tabViews removeAllObjects];
  [self.tabWidthConstraints removeAllObjects];
  self.draggedTab = nil;
  self.draggedStartIndex = NSNotFound;
  self.draggedCurrentIndex = NSNotFound;
  NSArray<TLWorkspaceTab *> *tabs = [self.delegate workspaceTabsForTabsController:self];
  for (NSUInteger index = 0; index < tabs.count; index += 1) {
    [self.tabStack addArrangedSubview:[self workspaceTabViewForTab:tabs[index] index:index tabs:tabs]];
  }
  [self updateEdgeAttachmentState];
}

- (void)setControlsEnabled:(BOOL)enabled disabledOpacity:(CGFloat)disabledOpacity {
  for (TLChromeTabView *tabView in self.tabViews) {
    tabView.enabled = enabled;
    tabView.alphaValue = enabled ? 1.0 : disabledOpacity;
  }
}

- (TLChromeTabView *)workspaceTabViewForTab:(TLWorkspaceTab *)tab index:(NSUInteger)index tabs:(NSArray<TLWorkspaceTab *> *)tabs {
  BOOL active = [self.delegate workspaceTabsController:self isTabActive:tab];
  BOOL previousActive = index > 0 && [self.delegate workspaceTabsController:self isTabActive:tabs[index - 1]];
  BOOL last = index == tabs.count - 1;
  TLChromeTabView *tabView = [[TLChromeTabView alloc] init];
  tabView.translatesAutoresizingMaskIntoConstraints = NO;
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
  tabView.active = active;
  tabView.showsLeadingSeparator = !active && index > 0 && !previousActive;
  tabView.showsTrailingSeparator = !active && last;
  tabView.dragDelegate = self;
  tabView.representedObject = [tab copy];
  [tabView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
  [tabView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];

  NSLayoutConstraint *width = [tabView.widthAnchor constraintEqualToConstant:self.palette.tabMaxWidth];
  width.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    width,
    [tabView.heightAnchor constraintEqualToConstant:self.palette.tabHeight],
  ]];

  [self.tabViews addObject:tabView];
  [self.tabWidthConstraints addObject:width];
  return tabView;
}

- (void)updateTabWidthsForAvailableWidth:(CGFloat)availableWidth {
  if (self.tabWidthConstraints.count == 0 || availableWidth <= self.palette.space0) {
    return;
  }

  CGFloat tabCount = (CGFloat)self.tabWidthConstraints.count;
  CGFloat sharedBoundaryCount = MAX(self.palette.space0, tabCount - 1.0);
  CGFloat maximumOverlap = TLTabFlareOverlapForWidth(self.palette.tabMaxWidth, self.palette);
  CGFloat equalWidth = (availableWidth + sharedBoundaryCount * maximumOverlap) / tabCount;
  CGFloat overlap = TLTabFlareOverlapForWidth(equalWidth, self.palette);
  if (overlap < maximumOverlap) {
    equalWidth = availableWidth / (tabCount - 0.18 * sharedBoundaryCount);
  }
  equalWidth = MIN(self.palette.tabMaxWidth, MAX(self.palette.borderWidth, equalWidth));
  overlap = TLTabFlareOverlapForWidth(equalWidth, self.palette);
  self.tabStack.spacing = -overlap;
  for (NSLayoutConstraint *constraint in self.tabWidthConstraints) {
    constraint.constant = equalWidth;
  }
  [self.tabStack invalidateIntrinsicContentSize];
  [self.tabStack setNeedsLayout:YES];
}

- (void)updateEdgeAttachmentState {
  [self resetTabLeadingFlares];

  CGFloat contentRadius = self.palette.space5;
  TLChromeTabView *firstTabView = self.tabViews.firstObject;
  if (firstTabView.active && [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]) {
    firstTabView.leadingFlareOutset = self.palette.space0;
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
  }

  [self.tabStack layoutSubtreeIfNeeded];
  NSUInteger targetIndex = [self targetIndexForDraggedTabView:tabView];
  if (targetIndex != NSNotFound) {
    self.draggedCurrentIndex = targetIndex;
  }
  [self updateDragEdgeGeometryForDraggedTabView:tabView targetIndex:self.draggedCurrentIndex];
}

- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView {
  [self resetDragEdgeGeometry];

  if (self.draggedTab && self.draggedCurrentIndex != NSNotFound && self.draggedStartIndex != self.draggedCurrentIndex) {
    [self.delegate workspaceTabsController:self moveTab:self.draggedTab toIndex:self.draggedCurrentIndex];
  }

  self.draggedTab = nil;
  self.draggedStartIndex = NSNotFound;
  self.draggedCurrentIndex = NSNotFound;
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
  for (TLChromeTabView *view in self.tabViews) {
    if (view == draggedTabView) {
      continue;
    }

    if (draggedMidX > NSMidX(view.frame)) {
      targetIndex += 1;
    }
  }

  return MIN(targetIndex, self.tabViews.count - 1);
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
  } else if (draggedTabView != firstTabView &&
             firstTabView.active &&
             [self.delegate workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:self]) {
    firstTabView.leadingFlareOutset = self.palette.space0;
    contentRadius = self.palette.space0;
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
