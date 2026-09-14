#import "TLBrowserChatPane.h"
#import "TLApprovalCardView.h"
#import "TLGlassButton.h"
#import "TLToolActivityView.h"
#import <QuartzCore/QuartzCore.h>

// Uses the same native bubble and typography as the main chat transcript.
@interface TLBrowserUserMessageRow : NSView
@property TLMessageBubbleView *bubble;
@property NSTextField *label;
@property TLThemePalette *palette;
@property NSLayoutConstraint *bubbleWidth;
- (instancetype)initWithText:(NSString *)text palette:(TLThemePalette *)palette;
@end
@implementation TLBrowserUserMessageRow
- (instancetype)initWithText:(NSString *)text palette:(TLThemePalette *)palette {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _palette = palette;
    _bubble = [TLMessageBubbleView new];
    _bubble.translatesAutoresizingMaskIntoConstraints = NO;
    _bubble.palette = palette;
    _bubble.drawsOutgoingTail = YES;
    _bubble.fillColor = palette.userMessageSurface;
    _bubble.borderColor = palette.transparentSurface;
    _bubble.borderEdges = TLBorderEdgeNone;
    _bubble.cornerRadius = palette.userMessageCornerRadius;
    _label = [NSTextField wrappingLabelWithString:text];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = palette.messageBodyFont;
    _label.textColor = palette.userMessageText;
    _label.selectable = YES;
    _label.maximumNumberOfLines = 0;
    [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_bubble addSubview:_label];
    [self addSubview:_bubble];
    _bubbleWidth = [_bubble.widthAnchor constraintEqualToConstant:palette.userMessageMinWidth];
    _bubbleWidth.priority = NSLayoutPriorityWindowSizeStayPut - 1;
    [NSLayoutConstraint activateConstraints:@[
      _bubbleWidth,
      [_bubble.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor],
      [_bubble.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_bubble.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_label.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:palette.userMessageHorizontalPadding],
      [_label.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-palette.userMessageHorizontalPadding],
      [_label.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:palette.userMessageVerticalPadding],
      [_label.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-(palette.userMessageVerticalPadding + palette.userMessageTailHeight)],
    ]];
  }
  return self;
}
- (void)layout {
  CGFloat maximum = MAX(self.palette.userMessageMinWidth, NSWidth(self.bounds) * self.palette.userMessageMaxWidthMultiplier);
  CGFloat natural = ceil([self.label.stringValue sizeWithAttributes:@{NSFontAttributeName:self.label.font}].width);
  CGFloat width = MIN(maximum, MAX(self.palette.userMessageMinWidth, natural + self.palette.userMessageHorizontalPadding * 2));
  self.bubbleWidth.constant = width;
  self.label.preferredMaxLayoutWidth = MAX(1, width - self.palette.userMessageHorizontalPadding * 2);
  [super layout];
}
@end

@interface TLBrowserChatPane ()
@property NSDictionary *approvalRequest;
@property NSArray<TLQuestionRequest *> *questions;
@property NSArray<TLQuestionCardView *> *questionCards;
@property NSArray<NSDictionary *> *questionPresentations;
@property TLApprovalCardView *approvalCard;
@property NSStackView *contentStack;
@property NSStackView *transcriptStack;
@property NSArray<NSDictionary<NSString *, NSString *> *> *transcript;
@property NSMutableArray<NSView *> *transcriptViews;
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
    // Preserve the preferred pill width over the title's hugging constraint,
    // while still allowing the input and narrow window to constrain it.
    [self setContentCompressionResistancePriority:NSLayoutPriorityWindowSizeStayPut - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
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
  self.transcriptStack = [NSStackView new];
  self.transcriptStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.transcriptStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.transcriptStack.alignment = NSLayoutAttributeWidth;
  self.transcriptStack.spacing = palette.messageVerticalSpacing;
  [self.contentStack addArrangedSubview:self.transcriptStack];
  [self.transcriptStack.widthAnchor constraintEqualToAnchor:self.contentStack.widthAnchor].active = YES;
  NSArray *transcript = self.transcript;
  self.transcript = nil;
  self.transcriptViews = [NSMutableArray array];
  [self showTranscript:transcript ?: @[] errorText:self.markdown loading:self.loading];
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
  self.titleLabel.stringValue = self.busy && self.collapsed
    ? (self.activityText.length ? self.activityText : @"Thinking…") : (title.length ? title : @"💬 New chat");
  self.titleLabel.toolTip = self.titleLabel.stringValue;
  [self invalidateIntrinsicContentSize];
}
- (void)setActivityText:(NSString *)activityText {
  _activityText = [activityText copy];
  self.title = self.title;
  [self updateHeaderSpinner];
}
- (void)showTranscript:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages errorText:(NSString *)errorText loading:(BOOL)loading {
  BOOL followsBottom = !self.transcript.count || self.loading ||
    NSMaxY(self.scrollView.documentVisibleRect) >= NSHeight(self.document.bounds) - self.palette.space8;
  BOOL rebuild = messages.count < self.transcript.count;
  for (NSUInteger index = 0; index < MIN(messages.count, self.transcript.count); index++) {
    if (![messages[index][@"role"] isEqual:self.transcript[index][@"role"]]) rebuild = YES;
  }
  if (rebuild) {
    for (NSView *row in self.transcriptViews) { [self.transcriptStack removeArrangedSubview:row]; [row removeFromSuperview]; }
    [self.transcriptViews removeAllObjects];
  }
  for (NSUInteger index = 0; index < messages.count; index++) {
    NSDictionary *message = messages[index];
    BOOL user = [message[@"role"] isEqual:@"user"];
    NSView *view = index < self.transcriptViews.count ? self.transcriptViews[index] : nil;
    if (!view) {
      view = user ? [[TLBrowserUserMessageRow alloc] initWithText:message[@"content"] palette:self.palette] :
        [self.renderer viewForMarkdown:message[@"content"] textColor:self.palette.assistantMessageText baseFont:self.palette.messageBodyFont];
      [self.transcriptViews addObject:view];
      [self.transcriptStack addArrangedSubview:view];
      [view.widthAnchor constraintEqualToAnchor:self.transcriptStack.widthAnchor].active = YES;
    } else if (user) {
      NSTextField *label = ((TLBrowserUserMessageRow *)view).label;
      if (![label.stringValue isEqual:message[@"content"]]) {
        label.stringValue = message[@"content"];
        view.needsLayout = YES;
      }
    } else {
      [self.renderer updateMarkdown:message[@"content"] inView:view];
    }
  }
  self.transcript = [messages copy];
  self.transcriptStack.hidden = !messages.count;
  [self showMarkdown:errorText loading:loading];
  self.followsBottom = followsBottom;
  if (followsBottom) {
    [self.document layoutSubtreeIfNeeded];
    [self.scrollView.contentView scrollToPoint:NSMakePoint(0, MAX(0, NSHeight(self.document.bounds) - NSHeight(self.scrollView.contentView.bounds)))];
  }
}
- (BOOL)showsEmptyLoader { return self.loading && !self.transcript.count; }
- (void)showMarkdown:(NSString *)markdown loading:(BOOL)loading {
  self.followsBottom = self.loading || (!self.markdown.length && !self.transcript.count) ||
    NSMaxY(self.scrollView.documentVisibleRect) >= NSHeight(self.document.bounds) - self.palette.space8;
  self.markdown = markdown ?: @"";
  self.markdownView.hidden = !self.markdown.length;
  self.loading = loading;
  self.scrollView.hidden = self.collapsed || self.showsEmptyLoader;
  if (self.showsEmptyLoader && !self.hidden && !self.collapsed) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
  [self updateHeaderSpinner];
  [self.renderer updateMarkdown:self.markdown inView:self.markdownView];
}
- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  [self updateHeaderSpinner];
  if (hidden) [self.spinner stopAnimation:nil];
  else if (self.showsEmptyLoader && !self.collapsed) [self.spinner startAnimation:nil];
}

- (void)setCollapsed:(BOOL)collapsed {
  _collapsed = collapsed;
  [self updateCornerRadius];
  [self invalidateIntrinsicContentSize];
  self.scrollView.hidden = collapsed || self.showsEmptyLoader;
  self.minimizeButton.image = [NSImage imageWithSystemSymbolName:collapsed ? @"chevron.up" : @"chevron.down"
    accessibilityDescription:collapsed ? @"Expand chat" : @"Collapse chat"];
  self.minimizeButton.toolTip = collapsed ? @"Expand chat" : @"Collapse chat";
  self.title = self.title;
  if (collapsed) [self.spinner stopAnimation:nil];
  else if (self.showsEmptyLoader && !self.hidden) [self.spinner startAnimation:nil];
}
- (void)setBusy:(BOOL)busy {
  _busy = busy;
  self.title = self.title;
  [self updateHeaderSpinner];
}
- (NSSize)intrinsicContentSize {
  if (!self.collapsed) return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
  CGFloat titleWidth = [self.titleLabel.stringValue sizeWithAttributes:@{NSFontAttributeName:self.titleLabel.font ?: self.palette.labelFont}].width;
  CGFloat width = self.titleLeading.constant + titleWidth +
    self.palette.space4 * 2 + self.palette.browserToolbarButtonSize * 3;
  return NSMakeSize(MAX(self.palette.browserPromptWidth, ceil(width)), NSViewNoIntrinsicMetric);
}
- (void)updateCornerRadius {
  self.cornerRadius = self.collapsed ? (self.palette.browserToolbarButtonSize + self.palette.space4 * 2) / 2 : self.palette.messageInputCornerRadius;
}
- (void)updateHeaderSpinner {
  BOOL working = self.busy || self.loading;
  self.headerSpinner.hidden = !working;
  self.headerSpinner.accessibilityLabel = self.activityText.length ? self.activityText : @"Thinking…";
  self.headerSpinner.toolTip = self.headerSpinner.accessibilityLabel;
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
