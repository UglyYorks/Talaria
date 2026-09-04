#import "TLMessageInput.h"
#import <math.h>

@interface TLComposerTextView : NSTextView
@property (nonatomic) BOOL selectsAllOnFocus;
@property (nonatomic, strong) NSEvent *focusMouseDownEvent;
@end

@implementation TLComposerTextView
- (BOOL)becomeFirstResponder {
  BOOL accepted = [super becomeFirstResponder];
  if (accepted && self.selectsAllOnFocus) {
    [self selectAll:nil];
    NSEvent *event = NSApp.currentEvent;
    self.focusMouseDownEvent = event.type == NSEventTypeLeftMouseDown ? event : nil;
  }
  return accepted;
}

- (BOOL)resignFirstResponder {
  BOOL resigned = [super resignFirstResponder];
  if (resigned) self.focusMouseDownEvent = nil;
  return resigned;
}

- (void)keyDown:(NSEvent *)event {
  NSEventModifierFlags modifiers = event.modifierFlags;
  BOOL shiftReturn = (event.keyCode == 36 || event.keyCode == 76) &&
    (modifiers & NSEventModifierFlagShift) &&
    !(modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption));
  if (shiftReturn && !self.hasMarkedText) {
    [self insertText:@"\n" replacementRange:self.selectedRange];
    return;
  }
  [super keyDown:event];
}

- (void)mouseDown:(NSEvent *)event {
  // AppKit can assign focus before delivering the click to the text view.
  BOOL focusClick = self.focusMouseDownEvent &&
    self.focusMouseDownEvent.eventNumber == event.eventNumber &&
    self.focusMouseDownEvent.timestamp == event.timestamp;
  self.focusMouseDownEvent = nil;
  if (self.selectsAllOnFocus && (self.window.firstResponder != self || focusClick) &&
      [self.window makeFirstResponder:self]) {
    [self selectAll:nil];
    self.focusMouseDownEvent = nil;
    return;
  }
  [super mouseDown:event];
}
@end

@interface TLMessageInput ()

@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSScrollView *textScrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSTextField *placeholderLabel;
@property (nonatomic, strong) TLGlassButton *sendButton;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *placeholderLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textTrailingConstraint;

@end

@implementation TLMessageInput

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _sendButtonSize = _palette.composerButtonHeight - (_palette.space3 * 2.0);
    _sendButtonInset = _palette.space3;
    _maximumExpandedHeight = _palette.messageInputMaxHeight;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    [self buildInterface];
    [self applyPalette];
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (void)buildInterface {
  self.heightConstraint = [self.heightAnchor constraintEqualToConstant:self.palette.composerButtonHeight];
  self.heightConstraint.active = YES;

  self.contentView = [[NSView alloc] init];
  self.contentView.translatesAutoresizingMaskIntoConstraints = NO;

  [self addSubview:self.contentView];
  [NSLayoutConstraint activateConstraints:@[
    [self.contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.contentView.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.contentView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
  ]];

  self.textScrollView = [NSTextView scrollableTextView];
  self.textScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.textScrollView.hasVerticalScroller = NO;
  self.textScrollView.hasHorizontalScroller = NO;
  self.textScrollView.drawsBackground = NO;
  self.textScrollView.borderType = NSNoBorder;

  self.textView = [[TLComposerTextView alloc] initWithFrame:self.textScrollView.documentView.frame];
  self.textScrollView.documentView = self.textView;
  self.textView.editable = YES;
  self.textView.selectable = YES;
  self.textView.richText = NO;
  self.textView.importsGraphics = NO;
  self.textView.allowsUndo = YES;
  self.textView.automaticQuoteSubstitutionEnabled = NO;
  self.textView.automaticDashSubstitutionEnabled = NO;
  self.textView.verticallyResizable = YES;
  self.textView.horizontallyResizable = NO;
  self.textView.autoresizingMask = NSViewWidthSizable;
  self.textView.textContainer.widthTracksTextView = YES;
  self.textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
  self.textView.textContainer.lineFragmentPadding = self.palette.space0;

  self.placeholderLabel = [NSTextField labelWithString:@"Give a task or enter a URL"];
  self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.placeholderLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.sendButton = [[TLGlassButton alloc] initWithUsesGlassEffect:NO];
  self.sendButton.image = [NSImage imageWithSystemSymbolName:@"arrow.up"
                                    accessibilityDescription:@"Send"];
  self.sendButton.toolTip = @"Send";

  [self.contentView addSubview:self.textScrollView];
  [self.contentView addSubview:self.placeholderLabel];
  [self.contentView addSubview:self.sendButton];

  self.sendButtonWidthConstraint = [self.sendButton.widthAnchor constraintEqualToConstant:self.sendButtonSize];
  self.sendButtonHeightConstraint = [self.sendButton.heightAnchor constraintEqualToConstant:self.sendButtonSize];
  self.sendButtonTrailingConstraint = [self.sendButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                                                   constant:-self.sendButtonInset];
  self.sendButtonBottomConstraint = [self.sendButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor
                                                                               constant:-self.sendButtonInset];
  self.placeholderLeadingConstraint = [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textScrollView.leadingAnchor
                                                                                          constant:self.palette.space3];
  self.textLeadingConstraint = [self.textScrollView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:self.palette.space6];
  self.textTrailingConstraint = [self.textScrollView.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-self.palette.space4];

  [NSLayoutConstraint activateConstraints:@[
    self.textLeadingConstraint,
    self.textTrailingConstraint,
    [self.textScrollView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:self.palette.space3],
    [self.textScrollView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-self.palette.space3],
    self.placeholderLeadingConstraint,
    [self.placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.textScrollView.trailingAnchor constant:-self.palette.space3],
    [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    self.sendButtonTrailingConstraint,
    self.sendButtonBottomConstraint,
    self.sendButtonWidthConstraint,
    self.sendButtonHeightConstraint,
  ]];

  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(composerTextDidChange:)
                                             name:NSTextDidChangeNotification
                                           object:self.textView];
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyPalette];
  [self recalculateHeight];
}

- (void)applyPalette {
  self.layer.backgroundColor = TLCGColor(self.backgroundView ? self.palette.transparentSurface : self.palette.composerSurface);
  self.layer.borderColor = TLCGColor(self.palette.composerBorder);
  self.layer.borderWidth = self.backgroundView ? self.palette.space0 : self.palette.borderWidth;
  self.layer.cornerRadius = self.palette.messageInputCornerRadius;
  self.layer.masksToBounds = YES;
  self.textView.font = self.palette.bodyFont;
  self.textView.textColor = self.palette.controlText;
  self.textView.backgroundColor = self.palette.transparentSurface;
  self.textView.insertionPointColor = self.palette.controlText;
  self.placeholderLabel.font = self.palette.bodyFont;
  self.placeholderLabel.textColor = self.palette.messageInputPlaceholderText;
  self.textView.textContainer.lineFragmentPadding = self.palette.space0;
  self.sendButton.palette = self.palette;
  self.sendButton.contentTintColor = self.palette.labelText;
  self.maximumExpandedHeight = self.palette.messageInputMaxHeight;
  self.heightConstraint.constant = MAX(self.palette.composerButtonHeight, self.heightConstraint.constant);
  self.sendButtonWidthConstraint.constant = self.sendButtonSize;
  self.sendButtonHeightConstraint.constant = self.sendButtonSize;
  self.sendButtonTrailingConstraint.constant = -self.sendButtonInset;
  self.sendButtonBottomConstraint.constant = -self.sendButtonInset;
  self.placeholderLeadingConstraint.constant = self.palette.space3;
  [self updateTextVerticalInsetForHeight:self.heightConstraint.constant textHeight:self.palette.bodyFont.ascender - self.palette.bodyFont.descender];
}

- (void)setSendButtonSize:(CGFloat)sendButtonSize {
  _sendButtonSize = sendButtonSize;
  self.sendButtonWidthConstraint.constant = sendButtonSize;
  self.sendButtonHeightConstraint.constant = sendButtonSize;
  [self setNeedsLayout:YES];
}

- (void)setSendButtonInset:(CGFloat)sendButtonInset {
  _sendButtonInset = sendButtonInset;
  self.sendButtonTrailingConstraint.constant = -sendButtonInset;
  self.sendButtonBottomConstraint.constant = -sendButtonInset;
  [self setNeedsLayout:YES];
}

- (void)setBackgroundView:(NSView *)backgroundView {
  [_backgroundView removeFromSuperview];
  _backgroundView = backgroundView;
  if (backgroundView) {
    backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:backgroundView positioned:NSWindowBelow relativeTo:self.contentView];
    [NSLayoutConstraint activateConstraints:@[
      [backgroundView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [backgroundView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [backgroundView.topAnchor constraintEqualToAnchor:self.topAnchor],
      [backgroundView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
  }
  [self applyPalette];
}

- (void)layout {
  [super layout];
  self.layer.cornerRadius = self.palette.messageInputCornerRadius;
  [self recalculateHeight];
}

- (void)composerTextDidChange:(NSNotification *)notification {
  [self updatePlaceholderVisibility];
  [self recalculateHeight];
  if (self.textChangeHandler) { self.textChangeHandler(); }
}

- (void)setSelectsAllOnFocus:(BOOL)selectsAllOnFocus {
  _selectsAllOnFocus = selectsAllOnFocus;
  ((TLComposerTextView *)self.textView).selectsAllOnFocus = selectsAllOnFocus;
}

- (void)setLeadingAccessoryView:(NSView *)leadingView trailingAccessoryView:(NSView *)trailingView {
  self.textLeadingConstraint.active = NO;
  self.textTrailingConstraint.active = NO;
  [self.contentView addSubview:leadingView];
  [self.contentView addSubview:trailingView];
  self.textLeadingConstraint = [self.textScrollView.leadingAnchor constraintEqualToAnchor:leadingView.trailingAnchor constant:self.palette.space3];
  self.textTrailingConstraint = [self.textScrollView.trailingAnchor constraintEqualToAnchor:trailingView.leadingAnchor constant:-self.palette.space3];
  [NSLayoutConstraint activateConstraints:@[
    [leadingView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:self.palette.space3],
    [leadingView.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    [trailingView.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-self.palette.space3],
    [trailingView.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    self.textLeadingConstraint,
    self.textTrailingConstraint,
  ]];
}

- (void)recalculateHeight {
  if (!self.textView || NSWidth(self.textScrollView.bounds) <= 0.0) {
    return;
  }

  NSLayoutManager *layoutManager = self.textView.layoutManager;
  NSTextContainer *textContainer = self.textView.textContainer;
  [layoutManager ensureLayoutForTextContainer:textContainer];
  CGFloat usedHeight = NSHeight([layoutManager usedRectForTextContainer:textContainer]);
  CGFloat chrome = self.palette.space3 * 2.0;
  CGFloat textHeight = MAX(usedHeight, self.palette.bodyFont.ascender - self.palette.bodyFont.descender);
  CGFloat textInset = textHeight <= (self.palette.bodyFont.ascender - self.palette.bodyFont.descender) + 1.0 ? self.palette.space3 : self.palette.space5;
  CGFloat targetHeight = MAX(self.palette.composerButtonHeight, MIN(self.maximumExpandedHeight, ceil(textHeight + (textInset * 2.0) + chrome)));

  [self updateTextVerticalInsetForHeight:targetHeight textHeight:textHeight];
  [self updatePlaceholderVisibility];

  if (fabs(self.heightConstraint.constant - targetHeight) > 0.5) {
    self.heightConstraint.constant = targetHeight;
    [self setNeedsLayout:YES];
    if (self.heightChangeHandler) { self.heightChangeHandler(targetHeight); }
  }
}

- (void)updateTextVerticalInsetForHeight:(CGFloat)height textHeight:(CGFloat)textHeight {
  CGFloat availableHeight = MAX(0.0, height - (self.palette.space3 * 2.0));
  CGFloat verticalInset = MAX(self.palette.space3, floor((availableHeight - textHeight) * 0.5));
  BOOL expanded = height > self.palette.composerButtonHeight + 0.5;
  self.textView.textContainerInset = NSMakeSize(self.palette.space3, expanded ? self.palette.space5 : verticalInset);
}

- (void)updatePlaceholderVisibility {
  self.placeholderLabel.hidden = self.textView.string.length > 0;
}

@end
