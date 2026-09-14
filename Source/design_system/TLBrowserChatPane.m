#import "TLBrowserChatPane.h"
#import "TLApprovalCardView.h"
#import "TLGlassButton.h"
#import "TLToolActivityView.h"
#import <QuartzCore/QuartzCore.h>

@interface TLBrowserChatPane ()
@property NSDictionary *approvalRequest;
@property NSArray<TLQuestionRequest *> *questions;
@property NSArray<TLQuestionCardView *> *questionCards;
@property NSArray<NSDictionary *> *questionPresentations;
@property TLApprovalCardView *approvalCard;
@property NSStackView *contentStack;
@property TLToolActivityView *activityView;
@property (nonatomic, readwrite) NSButton *minimizeButton;
@property (nonatomic, readwrite) NSButton *closeButton;
@property (nonatomic, readwrite) NSButton *splitButton;
@property NSTextField *titleLabel;
@property NSProgressIndicator *spinner;
@property NSProgressIndicator *headerSpinner;
@property NSLayoutConstraint *titleLeading;
@property NSScrollView *scrollView;
@property TLFlippedView *document;
@property NSView *markdownView;
@property TLMarkdownRenderer *renderer;
@property NSString *markdown;
@property BOOL loading;
@property BOOL followsBottom;
@property (nonatomic, readwrite, getter=isPresented) BOOL presented;
@property NSUInteger presentationGeneration;
@end

@implementation TLBrowserChatPane
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    TLHoverIconButton *button = [[TLHoverIconButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.hoverSurfaceOnly = YES;
    button.image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Minimize chat"];
    button.toolTip = @"Minimize chat";
    button.refusesFirstResponder = YES;
    _minimizeButton = button;
    [self addSubview:button];
    TLHoverIconButton *close = [TLHoverIconButton new];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.hoverSurfaceOnly = YES;
    close.refusesFirstResponder = YES;
    close.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close chat"];
    close.toolTip = @"Close chat";
    _closeButton = close;
    [self addSubview:close];
    TLHoverIconButton *split = [TLHoverIconButton new];
    split.translatesAutoresizingMaskIntoConstraints = NO;
    split.hoverSurfaceOnly = YES;
    split.refusesFirstResponder = YES;
    split.image = [NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:@"Open in split view"];
    split.toolTip = @"Open in split view";
    _splitButton = split;
    [self addSubview:split];
    _titleLabel = [NSTextField labelWithString:@"New chat"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_titleLabel];
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _document = [[TLFlippedView alloc] init];
    _document.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = _document;
    _contentStack = [[NSStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _contentStack.alignment = NSLayoutAttributeLeading;
    [_document addSubview:_contentStack];
    _activityView = [[TLToolActivityView alloc] init];
    [self addSubview:_scrollView];
    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.indeterminate = YES;
    _spinner.displayedWhenStopped = NO;
    [self addSubview:_spinner];
    _headerSpinner = [NSProgressIndicator new];
    _headerSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _headerSpinner.style = NSProgressIndicatorStyleSpinning;
    _headerSpinner.controlSize = NSControlSizeSmall;
    _headerSpinner.indeterminate = YES;
    _headerSpinner.displayedWhenStopped = NO;
    _headerSpinner.accessibilityLabel = @"Working on your request";
    [self addSubview:_headerSpinner];
    _titleLeading = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8];
    NSLayoutConstraint *scrollTop = [_scrollView.topAnchor constraintEqualToAnchor:button.bottomAnchor constant:palette.space4];
    // Hidden content can shrink to zero when only the status header is shown.
    scrollTop.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
      [button.topAnchor constraintEqualToAnchor:self.topAnchor constant:palette.space4],
      [close.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space4],
      [split.trailingAnchor constraintEqualToAnchor:close.leadingAnchor],
      [button.trailingAnchor constraintEqualToAnchor:split.leadingAnchor],
      [close.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      [split.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      [close.widthAnchor constraintEqualToAnchor:button.widthAnchor],
      [close.heightAnchor constraintEqualToAnchor:button.heightAnchor],
      [split.widthAnchor constraintEqualToAnchor:button.widthAnchor],
      [split.heightAnchor constraintEqualToAnchor:button.heightAnchor],
      [button.widthAnchor constraintEqualToConstant:palette.browserToolbarButtonSize],
      [button.heightAnchor constraintEqualToConstant:palette.browserToolbarButtonSize],
      _titleLeading,
      [_headerSpinner.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8],
      [_headerSpinner.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      [_headerSpinner.widthAnchor constraintEqualToConstant:palette.space8],
      [_headerSpinner.heightAnchor constraintEqualToConstant:palette.space8],
      [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:button.leadingAnchor constant:-palette.space4],
      [_titleLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      scrollTop,
      [_scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:0],
      [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8],
      [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space8],
      [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-palette.space8],
      [_document.widthAnchor constraintEqualToAnchor:_scrollView.contentView.widthAnchor],
      [_contentStack.leadingAnchor constraintEqualToAnchor:_document.leadingAnchor],
      [_contentStack.trailingAnchor constraintEqualToAnchor:_document.trailingAnchor],
      [_contentStack.topAnchor constraintEqualToAnchor:_document.topAnchor],
      [_contentStack.bottomAnchor constraintEqualToAnchor:_document.bottomAnchor],
      [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    self.palette = palette;
    self.wantsLayer = YES;
    self.hidden = YES;
    self.alphaValue = 0;
    [self updateHeaderSpinner];
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  [super setPalette:palette];
  [self updateCornerRadius];
  for (TLHoverIconButton *button in self.subviews) {
    if (![button isKindOfClass:TLHoverIconButton.class]) continue;
    button.palette = palette;
    button.contentTintColor = palette.controlText;
  }
  self.titleLabel.font = palette.labelFont;
  self.titleLabel.textColor = palette.controlText;
  [self updateHeaderSpinner];
  if (!self.document) return;
  self.contentStack.spacing = palette.space5;
  self.activityView.palette = palette;
  for (NSView *view in [self.contentStack.arrangedSubviews copy]) {
    [self.contentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  [self.approvalCard removeFromSuperview];
  self.approvalCard = nil;
  [self.markdownView removeFromSuperview];
  self.renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
  __weak typeof(self) weakSelf = self;
  self.renderer.linkContextMenuHandler = ^dispatch_block_t(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point) {
    return weakSelf.linkContextMenuHandler ? weakSelf.linkContextMenuHandler(URL, menu, view, point) : nil;
  };
  self.renderer.linkHandler = ^(NSURL *URL, NSEventModifierFlags flags) {
    if (weakSelf.linkHandler) weakSelf.linkHandler(URL, flags);
  };
  self.renderer.heightChangeHandler = ^{
    TLBrowserChatPane *pane = weakSelf;
    if (pane.followsBottom) {
      [pane.scrollView.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(pane.document.bounds) - NSHeight(pane.scrollView.contentView.bounds)))];
      [pane.scrollView reflectScrolledClipView:pane.scrollView.contentView];
    }
  };
  self.markdownView = [self.renderer viewForMarkdown:self.markdown ?: @"" textColor:palette.assistantMessageText baseFont:palette.messageBodyFont];
  self.markdownView.hidden = !self.markdown.length;
  [self.contentStack addArrangedSubview:self.activityView];
  [self.contentStack addArrangedSubview:self.markdownView];
  [self.markdownView.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor].active = YES;
  [self.activityView.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor].active = YES;
  NSDictionary *approval = self.approvalRequest;
  self.approvalRequest = nil;
  [self showApprovalRequest:approval];
  self.questionPresentations = nil;
  [self showQuestions:self.questions ?: @[]];
}
- (void)showQuestions:(NSArray<TLQuestionRequest *> *)questions {
  NSArray *presentations = [questions valueForKey:@"presentation"];
  if ([self.questions isEqual:questions] && [self.questionPresentations isEqual:presentations]) return;
  self.questions = [questions copy];
  self.questionPresentations = presentations;
  for (NSView *card in self.questionCards) {
    [self.contentStack removeArrangedSubview:card];
    [card removeFromSuperview];
  }
  NSMutableArray *cards = [NSMutableArray array];
  for (TLQuestionRequest *question in questions) {
    TLQuestionCardView *card = [[TLQuestionCardView alloc] initWithRequest:question.presentation palette:self.palette];
    card.choiceHandler = ^BOOL(NSString *choice) { return [question respondWithOption:choice]; };
    [self.contentStack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor].active = YES;
    [cards addObject:card];
  }
  self.questionCards = cards;
}
- (void)showApprovalRequest:(NSDictionary *)request {
  if ([(self.approvalRequest ?: @{}) isEqual:request ?: @{}]) return;
  self.approvalRequest = request;
  if (self.approvalCard) [self.contentStack removeArrangedSubview:self.approvalCard];
  [self.approvalCard removeFromSuperview];
  self.approvalCard = nil;
  if (!request) return;
  self.approvalCard = [[TLApprovalCardView alloc] initWithRequest:request palette:self.palette];
  __weak typeof(self) weakSelf = self;
  self.approvalCard.choiceHandler = ^BOOL(NSString *choice) {
    return weakSelf.approvalHandler ? weakSelf.approvalHandler(request[@"request_id"], choice) : NO;
  };
  [self.contentStack addArrangedSubview:self.approvalCard];
  [self.approvalCard.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor].active = YES;
}
- (void)showToolActivities:(NSArray<NSDictionary<NSString *, NSString *> *> *)activities {
  if ([self.activityView.activities isEqual:activities]) return;
  BOOL followsBottom = self.loading ||
    NSMaxY(self.scrollView.documentVisibleRect) >= NSHeight(self.document.bounds) - self.palette.space8;
  self.activityView.activities = activities;
  [self.document layoutSubtreeIfNeeded];
  if (followsBottom) {
    [self.scrollView.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(self.document.bounds) - NSHeight(self.scrollView.contentView.bounds)))];
    [self.scrollView reflectScrolledClipView:self.scrollView.contentView];
  }
}
- (void)setTitle:(NSString *)title {
  _title = [title copy];
  self.titleLabel.stringValue = title.length ? title : @"💬 New chat";
  self.titleLabel.toolTip = self.titleLabel.stringValue;
  [self invalidateIntrinsicContentSize];
}
- (void)showMarkdown:(NSString *)markdown loading:(BOOL)loading {
  self.followsBottom = self.loading || !self.markdown.length ||
    NSMaxY(self.scrollView.documentVisibleRect) >= NSHeight(self.document.bounds) - self.palette.space8;
  self.markdown = markdown ?: @"";
  self.markdownView.hidden = !self.markdown.length;
  self.loading = loading;
  self.scrollView.hidden = self.collapsed || loading;
  if (loading && !self.hidden && !self.collapsed) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
  [self updateHeaderSpinner];
  [self.renderer updateMarkdown:self.markdown inView:self.markdownView];
}
- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  [self updateHeaderSpinner];
  if (hidden) [self.spinner stopAnimation:nil];
  else if (self.loading && !self.collapsed) [self.spinner startAnimation:nil];
}

- (void)setCollapsed:(BOOL)collapsed {
  _collapsed = collapsed;
  [self updateCornerRadius];
  [self invalidateIntrinsicContentSize];
  self.scrollView.hidden = collapsed || self.loading;
  self.minimizeButton.image = [NSImage imageWithSystemSymbolName:collapsed ? @"chevron.up" : @"chevron.down"
    accessibilityDescription:collapsed ? @"Expand chat" : @"Collapse chat"];
  self.minimizeButton.toolTip = collapsed ? @"Expand chat" : @"Collapse chat";
  self.title = self.title;
  if (collapsed) [self.spinner stopAnimation:nil];
  else if (self.loading && !self.hidden) [self.spinner startAnimation:nil];
}
- (void)setBusy:(BOOL)busy {
  _busy = busy;
  self.title = self.title;
  [self updateHeaderSpinner];
}
- (NSSize)intrinsicContentSize {
  if (!self.collapsed) return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
  CGFloat width = self.titleLeading.constant + self.titleLabel.intrinsicContentSize.width +
    self.palette.space4 * 2 + self.palette.browserToolbarButtonSize * 3;
  return NSMakeSize(ceil(width), NSViewNoIntrinsicMetric);
}
- (void)updateCornerRadius {
  self.cornerRadius = self.collapsed ? (self.palette.browserToolbarButtonSize + self.palette.space4 * 2) / 2 : self.palette.messageInputCornerRadius;
}
- (void)updateHeaderSpinner {
  BOOL working = self.busy || self.loading;
  self.headerSpinner.hidden = !working;
  self.headerSpinner.accessibilityLabel = @"Working on your request";
  self.headerSpinner.toolTip = @"Working on your request…";
  self.titleLeading.constant = self.palette.space8 + (working ? self.palette.space8 + self.palette.space4 : 0);
  [self invalidateIntrinsicContentSize];
  if (working && !self.hidden) [self.headerSpinner startAnimation:nil];
  else [self.headerSpinner stopAnimation:nil];
}
- (NSRect)headerRect {
  return NSMakeRect(0, NSMinY(self.minimizeButton.frame) - self.palette.space4,
    NSWidth(self.bounds), NSHeight(self.minimizeButton.frame) + self.palette.space4 * 2);
}
- (NSView *)hitTest:(NSPoint)point {
  NSView *hit = [super hitTest:point];
  if (!hit || !NSPointInRect([self convertPoint:point fromView:self.superview], self.headerRect)) return hit;
  for (NSButton *button in @[self.minimizeButton, self.closeButton, self.splitButton])
    if (hit == button || [hit isDescendantOf:button]) return hit;
  return self;
}
- (void)mouseDown:(NSEvent *)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  if (NSPointInRect(point, self.headerRect)) {
    [NSApp sendAction:self.minimizeButton.action to:self.minimizeButton.target from:self.minimizeButton];
  } else [super mouseDown:event];
}

- (void)setPresented:(BOOL)presented animated:(BOOL)animated {
  if (self.presented == presented && animated) return;
  self.presented = presented;
  NSUInteger generation = ++self.presentationGeneration;
  CGFloat offset = self.palette.browserChatPaneSlideDistance * (self.superview.isFlipped ? 1 : -1);
  CALayer *visibleLayer = self.layer.presentationLayer ?: self.layer;
  CGFloat fromOpacity = self.hidden ? 0 : visibleLayer.opacity;
  CGFloat fromOffset = self.hidden ? offset : [[visibleLayer valueForKeyPath:@"transform.translation.y"] doubleValue];
  [self.layer removeAnimationForKey:@"browser-chat-presentation"];

  BOOL shouldAnimate = animated && self.window && self.palette.browserChatPaneTransitionDuration > 0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.hidden = shouldAnimate ? NO : !presented;
  self.alphaValue = presented ? 1 : 0;
  self.layer.transform = CATransform3DMakeTranslation(0, presented ? 0 : offset, 0);
  if (shouldAnimate) {
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(fromOpacity);
    fade.toValue = @(presented ? 1 : 0);
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    slide.fromValue = @(fromOffset);
    slide.toValue = @(presented ? 0 : offset);
    CAAnimationGroup *transition = [CAAnimationGroup animation];
    transition.animations = @[fade, slide];
    transition.duration = self.palette.browserChatPaneTransitionDuration;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    __weak typeof(self) weakSelf = self;
    [CATransaction setCompletionBlock:^{
      TLBrowserChatPane *pane = weakSelf;
      if (pane && pane.presentationGeneration == generation) pane.hidden = !presented;
    }];
    [self.layer addAnimation:transition forKey:@"browser-chat-presentation"];
  }
  [CATransaction commit];
}
@end
