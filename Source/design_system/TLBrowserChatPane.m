#import "TLBrowserChatPane.h"
#import "TLGlassButton.h"
#import <QuartzCore/QuartzCore.h>

@interface TLBrowserChatPane ()
@property (nonatomic, readwrite) NSButton *minimizeButton;
@property NSTextField *titleLabel;
@property NSProgressIndicator *spinner;
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
    TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    TLHoverIconButton *button = [[TLHoverIconButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.hoverSurfaceOnly = YES;
    button.image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Minimize chat"];
    button.toolTip = @"Minimize chat";
    button.refusesFirstResponder = YES;
    _minimizeButton = button;
    [self addSubview:button];
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
    [self addSubview:_scrollView];
    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.indeterminate = YES;
    _spinner.displayedWhenStopped = NO;
    [self addSubview:_spinner];
    [NSLayoutConstraint activateConstraints:@[
      [button.topAnchor constraintEqualToAnchor:self.topAnchor constant:palette.space4],
      [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space4],
      [button.widthAnchor constraintEqualToConstant:palette.browserToolbarButtonSize],
      [button.heightAnchor constraintEqualToConstant:palette.browserToolbarButtonSize],
      [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8],
      [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:button.leadingAnchor constant:-palette.space4],
      [_titleLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
      [_scrollView.topAnchor constraintEqualToAnchor:button.bottomAnchor constant:palette.space4],
      [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8],
      [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space8],
      [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-palette.space8],
      [_document.widthAnchor constraintEqualToAnchor:_scrollView.contentView.widthAnchor],
      [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    self.palette = palette;
    self.wantsLayer = YES;
    self.hidden = YES;
    self.alphaValue = 0;
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  [super setPalette:palette];
  ((TLHoverIconButton *)self.minimizeButton).palette = palette;
  self.minimizeButton.contentTintColor = palette.controlText;
  self.titleLabel.font = palette.labelFont;
  self.titleLabel.textColor = palette.controlText;
  if (!self.document) return;
  [self.markdownView removeFromSuperview];
  self.renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
  __weak typeof(self) weakSelf = self;
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
  [self.document addSubview:self.markdownView];
  [NSLayoutConstraint activateConstraints:@[
    [self.markdownView.leadingAnchor constraintEqualToAnchor:self.document.leadingAnchor],
    [self.markdownView.trailingAnchor constraintEqualToAnchor:self.document.trailingAnchor],
    [self.markdownView.topAnchor constraintEqualToAnchor:self.document.topAnchor],
    [self.markdownView.bottomAnchor constraintEqualToAnchor:self.document.bottomAnchor],
  ]];
}
- (void)setTitle:(NSString *)title {
  _title = [title copy];
  self.titleLabel.stringValue = title.length ? title : @"New chat";
  self.titleLabel.toolTip = self.titleLabel.stringValue;
}
- (void)showMarkdown:(NSString *)markdown loading:(BOOL)loading {
  self.followsBottom = self.loading || !self.markdown.length ||
    NSMaxY(self.scrollView.documentVisibleRect) >= NSHeight(self.document.bounds) - self.palette.space8;
  self.markdown = markdown ?: @"";
  self.loading = loading;
  self.scrollView.hidden = loading;
  if (loading && !self.hidden) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
  [self.renderer updateMarkdown:self.markdown inView:self.markdownView];
}
- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  if (hidden) [self.spinner stopAnimation:nil];
  else if (self.loading) [self.spinner startAnimation:nil];
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
