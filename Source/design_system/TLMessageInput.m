#import "TLMessageInput.h"
#import <math.h>

@interface TLComposerTextView : NSTextView
@property (nonatomic) BOOL selectsAllOnFocus;
@property (nonatomic, copy) BOOL (^filePasteHandler)(NSPasteboard *pasteboard);
@property (nonatomic, copy) BOOL (^fileDropEnabled)(void);
@property (nonatomic, strong) NSEvent *focusMouseDownEvent;
@end

@implementation TLComposerTextView
- (void)paste:(id)sender {
  if (self.filePasteHandler && self.filePasteHandler(NSPasteboard.generalPasteboard)) return;
  [super paste:sender];
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  if (self.filePasteHandler && [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class]
      options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}]) return self.fileDropEnabled() ? NSDragOperationCopy : NSDragOperationNone;
  return [super draggingEntered:sender];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return [self draggingEntered:sender]; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  if (self.filePasteHandler && [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class]
      options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}]) return self.fileDropEnabled();
  return [super prepareForDragOperation:sender];
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  if (self.filePasteHandler && !self.fileDropEnabled()) return NO;
  if (self.filePasteHandler && self.filePasteHandler(sender.draggingPasteboard)) return YES;
  return [super performDragOperation:sender];
}
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

// NSButton's intrinsic width does not inset its image/title drawing. Apply the
// same padding to the cell's content frame so neither edge touches the pill.
@interface TLAttachmentChipCell : NSButtonCell
@property (nonatomic) CGFloat horizontalPadding;
@end
@implementation TLAttachmentChipCell
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
  [super drawInteriorWithFrame:NSInsetRect(cellFrame, self.horizontalPadding, 0) inView:controlView];
}
@end

@interface TLAttachmentChipButton : TLHoverIconButton
@property (nonatomic) BOOL attachmentHovered;
@end
@implementation TLAttachmentChipButton
+ (Class)cellClass { return TLAttachmentChipCell.class; }
- (NSSize)intrinsicContentSize {
  NSSize size = [super intrinsicContentSize];
  size.width += self.palette.space6 * 2;
  size.height = MAX(size.height, self.palette.fieldHeight);
  return size;
}
- (void)applyChipPalette {
  self.wantsLayer = YES;
  self.layer.cornerRadius = MIN(self.palette.radiusPill, NSHeight(self.bounds) / 2);
  ((TLAttachmentChipCell *)self.cell).horizontalPadding = self.palette.space6;
  self.layer.backgroundColor = TLCGColor(self.attachmentHovered && self.enabled ? self.palette.chromeHoverSurface : self.palette.controlSurface);
  self.layer.borderColor = TLCGColor(self.palette.composerBorder);
  self.layer.borderWidth = self.palette.borderWidth;
  self.font = self.palette.smallFont;
  self.contentTintColor = self.palette.controlText;
}
- (void)setPalette:(TLThemePalette *)palette { [super setPalette:palette]; [self applyChipPalette]; [self invalidateIntrinsicContentSize]; }
- (void)mouseEntered:(NSEvent *)event { self.attachmentHovered = YES; [self applyChipPalette]; }
- (void)mouseExited:(NSEvent *)event { self.attachmentHovered = NO; [self applyChipPalette]; }
- (void)layout { [super layout]; [self applyChipPalette]; }
@end

@interface TLMessageInput ()

@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) TLGlassButton *attachButton;
@property (nonatomic, strong) NSScrollView *attachmentScrollView;
@property (nonatomic, strong) NSStackView *attachmentStack;
@property (nonatomic, strong) NSLayoutConstraint *textTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachmentHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachmentTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachmentLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachmentTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attachHeightConstraint;
@property (nonatomic, strong) NSURL *clipboardDirectory;
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
    _attachmentURLs = @[];
    _attachmentsEditable = YES;
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
  self.textTopConstraint = [self.textScrollView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:self.palette.space3];
  self.textTrailingConstraint = [self.textScrollView.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-self.palette.space4];

  [NSLayoutConstraint activateConstraints:@[
    self.textLeadingConstraint,
    self.textTrailingConstraint,
    self.textTopConstraint,
    [self.textScrollView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-self.palette.space3],
    self.placeholderLeadingConstraint,
    [self.placeholderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.textScrollView.trailingAnchor constant:-self.palette.space3],
    [self.placeholderLabel.centerYAnchor constraintEqualToAnchor:self.textScrollView.centerYAnchor],
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
  if (_clipboardDirectory) [NSFileManager.defaultManager removeItemAtURL:_clipboardDirectory error:nil];
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
  [self applyAttachmentPalette];
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
  [self applyAttachmentPalette];
  [self setNeedsLayout:YES];
}

- (void)setSendButtonInset:(CGFloat)sendButtonInset {
  _sendButtonInset = sendButtonInset;
  self.sendButtonTrailingConstraint.constant = -sendButtonInset;
  self.sendButtonBottomConstraint.constant = -sendButtonInset;
  [self applyAttachmentPalette];
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
  CGFloat attachmentHeight = [self attachmentRowHeight];
  self.textTopConstraint.constant = self.palette.space3 + attachmentHeight;
  CGFloat targetHeight = attachmentHeight + MAX(self.palette.composerButtonHeight, MIN(self.maximumExpandedHeight, ceil(textHeight + (textInset * 2.0) + chrome)));

  [self updateTextVerticalInsetForHeight:targetHeight - attachmentHeight textHeight:textHeight];
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

- (CGFloat)attachmentRowHeight {
  return self.attachmentsEnabled && self.attachmentURLs.count ? self.palette.composerButtonHeight + self.palette.space3 : self.palette.space0;
}

- (void)setAttachmentsEnabled:(BOOL)enabled {
  _attachmentsEnabled = enabled;
  if (enabled && !self.attachButton) [self buildAttachmentInterface];
  self.attachButton.hidden = !enabled;
  __weak typeof(self) weakSelf = self;
  ((TLComposerTextView *)self.textView).fileDropEnabled = ^BOOL{ return weakSelf.attachmentsEnabled && weakSelf.attachmentsEditable; };
  ((TLComposerTextView *)self.textView).filePasteHandler = enabled ? ^BOOL(NSPasteboard *pasteboard) {
    return [weakSelf receiveAttachmentPasteboard:pasteboard];
  } : (BOOL (^)(NSPasteboard *))nil;
  if (enabled) {
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [self.textView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
  } else [self unregisterDraggedTypes];
  [self applyAttachmentPalette];
  [self recalculateHeight];
}

- (void)setAttachmentsEditable:(BOOL)editable {
  _attachmentsEditable = editable;
  self.attachButton.enabled = editable;
  for (NSButton *button in self.attachmentStack.arrangedSubviews) button.enabled = editable;
}

- (void)buildAttachmentInterface {
  self.attachButton = [[TLGlassButton alloc] initWithUsesGlassEffect:NO];
  self.attachButton.hoverSurfaceOnly = YES;
  self.attachButton.toolTip = @"Add files or folders";
  self.attachButton.target = self;
  self.attachButton.action = @selector(chooseAttachments:);
  [self.contentView addSubview:self.attachButton];
  self.attachmentScrollView = [[NSScrollView alloc] init];
  self.attachmentScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.attachmentScrollView.drawsBackground = NO;
  self.attachmentScrollView.hasHorizontalScroller = YES;
  self.attachmentScrollView.autohidesScrollers = YES;
  self.attachmentStack = [[NSStackView alloc] init];
  self.attachmentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.attachmentStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  self.attachmentStack.alignment = NSLayoutAttributeCenterY;
  self.attachmentScrollView.documentView = self.attachmentStack;
  [self.contentView addSubview:self.attachmentScrollView];
  self.attachLeadingConstraint = [self.attachButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor];
  self.attachWidthConstraint = [self.attachButton.widthAnchor constraintEqualToConstant:self.sendButtonSize];
  self.attachHeightConstraint = [self.attachButton.heightAnchor constraintEqualToConstant:self.sendButtonSize];
  self.attachmentHeightConstraint = [self.attachmentScrollView.heightAnchor constraintEqualToConstant:self.palette.composerButtonHeight];
  self.attachmentTopConstraint = [self.attachmentScrollView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor];
  self.attachmentLeadingConstraint = [self.attachmentScrollView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor];
  self.attachmentTrailingConstraint = [self.attachmentScrollView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor];
  [NSLayoutConstraint activateConstraints:@[
    self.attachLeadingConstraint, self.attachWidthConstraint, self.attachHeightConstraint,
    [self.attachButton.centerYAnchor constraintEqualToAnchor:self.sendButton.centerYAnchor],
    self.attachmentTopConstraint, self.attachmentLeadingConstraint, self.attachmentTrailingConstraint,
    self.attachmentHeightConstraint,
    [self.attachmentStack.leadingAnchor constraintEqualToAnchor:self.attachmentScrollView.contentView.leadingAnchor],
    [self.attachmentStack.topAnchor constraintEqualToAnchor:self.attachmentScrollView.contentView.topAnchor],
    [self.attachmentStack.heightAnchor constraintEqualToAnchor:self.attachmentScrollView.contentView.heightAnchor],
  ]];
}

- (void)applyAttachmentPalette {
  if (!self.attachButton) return;
  self.attachButton.palette = self.palette;
  self.attachButton.wantsLayer = YES;
  self.attachButton.layer.backgroundColor = TLCGColor(self.palette.chromeHoverSurface);
  self.attachButton.layer.cornerRadius = self.sendButtonSize / 2;
  NSImage *plus = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add files or folders"];
  NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:self.palette.space11
                                                                                           weight:NSFontWeightRegular];
  self.attachButton.image = [plus imageWithSymbolConfiguration:configuration] ?: plus;
  self.attachLeadingConstraint.constant = self.sendButtonInset;
  self.attachWidthConstraint.constant = self.sendButtonSize;
  self.attachHeightConstraint.constant = self.sendButtonSize;
  self.textLeadingConstraint.constant = self.attachmentsEnabled ? self.sendButtonInset + self.palette.space3 + self.sendButtonSize : self.palette.space6;
  self.attachmentTopConstraint.constant = self.palette.space3;
  self.attachmentLeadingConstraint.constant = self.palette.space5;
  self.attachmentTrailingConstraint.constant = -self.palette.space5;
  self.attachmentHeightConstraint.constant = self.palette.composerButtonHeight;
  self.attachmentStack.spacing = self.palette.space3;
  self.attachmentScrollView.hidden = !self.attachmentsEnabled || !self.attachmentURLs.count;
  for (TLHoverIconButton *button in self.attachmentStack.arrangedSubviews) {
    button.palette = self.palette;
    button.font = self.palette.smallFont;
    button.contentTintColor = self.palette.controlText;
  }
}

- (void)setAttachmentURLs:(NSArray<NSURL *> *)URLs {
  _attachmentURLs = [URLs copy] ?: @[];
  for (NSView *view in self.attachmentStack.arrangedSubviews.copy) {
    [self.attachmentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  NSUInteger index = 0;
  for (NSURL *URL in _attachmentURLs) {
    TLAttachmentChipButton *button = [[TLAttachmentChipButton alloc] init];
    button.palette = self.palette;
    BOOL directory = URL.hasDirectoryPath;
    [NSFileManager.defaultManager fileExistsAtPath:URL.path isDirectory:&directory];
    button.image = [NSImage imageWithSystemSymbolName:directory ? @"folder" : @"doc" accessibilityDescription:nil];
    button.imagePosition = NSImageLeft;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = [URL.lastPathComponent stringByAppendingString:@"  ×"];
    button.toolTip = [@"Remove " stringByAppendingString:URL.path];
    button.accessibilityLabel = [@"Remove attachment " stringByAppendingString:URL.lastPathComponent];
    button.bordered = NO;
    button.target = self;
    button.action = @selector(removeAttachment:);
    button.tag = index++;
    button.enabled = self.attachmentsEditable;
    button.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [button.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth / 3].active = YES;
    [self.attachmentStack addArrangedSubview:button];
  }
  [self applyAttachmentPalette];
  [self recalculateHeight];
  if (self.attachmentsChangeHandler) self.attachmentsChangeHandler();
}

- (void)addAttachmentURLs:(NSArray<NSURL *> *)URLs {
  if (!self.attachmentsEnabled || !self.attachmentsEditable) return;
  NSMutableArray *next = [self.attachmentURLs mutableCopy];
  for (NSURL *URL in URLs) if (URL.isFileURL && ![next containsObject:URL]) [next addObject:URL];
  self.attachmentURLs = next;
}

- (void)removeAttachment:(NSButton *)sender {
  if (!self.attachmentsEditable || sender.tag < 0 || (NSUInteger)sender.tag >= self.attachmentURLs.count) return;
  NSMutableArray *next = [self.attachmentURLs mutableCopy];
  [next removeObjectAtIndex:sender.tag];
  self.attachmentURLs = next;
}

- (void)chooseAttachments:(id)sender {
  if (!self.attachmentsEditable) return;
  NSOpenPanel *panel = NSOpenPanel.openPanel;
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = YES;
  panel.prompt = @"Attach";
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK) [self addAttachmentURLs:panel.URLs];
  }];
}

- (BOOL)receiveAttachmentPasteboard:(NSPasteboard *)pasteboard {
  NSArray *URLs = [pasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
  if (URLs.count) { [self addAttachmentURLs:URLs]; return YES; }
  NSData *imageData = [pasteboard dataForType:NSPasteboardTypePNG];
  if (!imageData) {
    NSData *tiff = [pasteboard dataForType:NSPasteboardTypeTIFF];
    if (tiff) imageData = [[NSBitmapImageRep imageRepWithData:tiff] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  }
  if (!imageData) return NO;
  if (!self.attachmentsEditable) return YES;
  NSError *error = nil;
  if (!self.clipboardDirectory) {
    self.clipboardDirectory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  }
  NSURL *URL = [self.clipboardDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"Pasted image %@.png", NSUUID.UUID.UUIDString]];
  if ([NSFileManager.defaultManager createDirectoryAtURL:self.clipboardDirectory withIntermediateDirectories:YES attributes:nil error:&error] &&
      [imageData writeToURL:URL options:NSDataWritingAtomic error:&error]) [self addAttachmentURLs:@[URL]];
  else if (error) [NSApp presentError:error];
  return YES;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  return self.attachmentsEnabled && self.attachmentsEditable &&
    [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}] ? NSDragOperationCopy : NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return [self draggingEntered:sender]; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  return [self draggingEntered:sender] != NSDragOperationNone && [self receiveAttachmentPasteboard:sender.draggingPasteboard];
}

@end
