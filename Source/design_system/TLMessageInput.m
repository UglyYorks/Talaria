#import "TLMessageInput.h"
#import "TLTransitionCoordinator.h"
#import <math.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>

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

// Draw the cross around the control's center, without NSButtonCell's native
// image/bezel offsets, so its visible strokes align with the circular surface.
@interface TLAttachmentCloseButtonCell : NSButtonCell
@property (nonatomic) CGFloat strokeWidth;
@end
@implementation TLAttachmentCloseButtonCell
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
  NSButton *button = (NSButton *)view;
  CGFloat halfSize = button.font.pointSize / 2;
  NSPoint center = NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds));
  NSBezierPath *cross = [NSBezierPath bezierPath];
  cross.lineWidth = self.strokeWidth;
  cross.lineCapStyle = NSLineCapStyleRound;
  [cross moveToPoint:NSMakePoint(center.x - halfSize, center.y - halfSize)];
  [cross lineToPoint:NSMakePoint(center.x + halfSize, center.y + halfSize)];
  [cross moveToPoint:NSMakePoint(center.x - halfSize, center.y + halfSize)];
  [cross lineToPoint:NSMakePoint(center.x + halfSize, center.y - halfSize)];
  [button.contentTintColor setStroke];
  [cross stroke];
}
@end

@interface TLAttachmentCloseButton : TLHoverIconButton
@end
@implementation TLAttachmentCloseButton
+ (Class)cellClass { return TLAttachmentCloseButtonCell.class; }
@end

@interface TLAttachmentChipView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL enabled;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) TLHoverIconButton *closeButton;
@property (nonatomic, strong) QLThumbnailGenerationRequest *thumbnailRequest;
@property (nonatomic, strong) NSURL *previewURL;
@property (nonatomic) BOOL previewSecurityScope;
@property (nonatomic) BOOL hasContentPreview;
@property (nonatomic, strong) NSView *chipContentView;
@property (nonatomic, strong) NSURL *attachmentURL;
@property (nonatomic, copy) NSString *transitionKey;
@property (nonatomic) CGFloat revealProgress;
@property (nonatomic) BOOL removing;
@property (nonatomic) BOOL closingTransition;
@end
@implementation TLAttachmentChipView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _revealProgress = 1;
    _transitionKey = NSUUID.UUID.UUIDString;
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    _chipContentView = [[NSView alloc] init];
    _chipContentView.wantsLayer = YES;
    [self addSubview:_chipContentView];
    _imageView = [[NSImageView alloc] init];
    _imageView.imageScaling = NSImageScaleProportionallyDown;
    _imageView.wantsLayer = YES;
    _imageView.layer.masksToBounds = YES;
    _label = [NSTextField labelWithString:@""];
    _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _label.usesSingleLineMode = YES;
    _closeButton = [[TLAttachmentCloseButton alloc] init];
    _closeButton.hoverSurfaceOnly = YES;
    _closeButton.imagePosition = NSImageOnly;
    _closeButton.title = @"";
    [self.chipContentView addSubview:_imageView];
    [self.chipContentView addSubview:_label];
    [self.chipContentView addSubview:_closeButton];
  }
  return self;
}
- (CGFloat)imageLeadingInset {
  return self.image && !self.image.template ? self.palette.space2 * 2 : self.palette.space6;
}
- (CGFloat)expandedWidth {
  CGFloat width = self.imageLeadingInset + self.image.size.width + self.palette.space4 +
    self.label.intrinsicContentSize.width + self.palette.space4 + self.palette.space11 + self.palette.space3;
  return MIN(ceil(width), self.palette.messageInputMaxWidth / 3);
}
- (NSSize)intrinsicContentSize {
  return NSMakeSize(self.expandedWidth * self.revealProgress, self.palette.fieldHeight);
}
- (void)setRevealProgress:(CGFloat)progress {
  _revealProgress = progress;
  self.chipContentView.alphaValue = progress;
  [self invalidateIntrinsicContentSize];
  self.needsLayout = YES;
}
- (void)setImage:(NSImage *)image {
  _image = image;
  self.imageView.image = image;
  [self invalidateIntrinsicContentSize];
  self.needsLayout = YES;
}
- (void)setTitle:(NSString *)title {
  _title = [title copy];
  self.label.stringValue = title ?: @"";
  [self invalidateIntrinsicContentSize];
  self.needsLayout = YES;
}
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; self.closeButton.enabled = enabled; }
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.wantsLayer = YES;
  self.layer.backgroundColor = TLCGColor(palette.controlSurface);
  self.layer.borderWidth = palette.space0;
  self.label.font = palette.smallFont;
  self.label.textColor = palette.controlText;
  self.imageView.contentTintColor = palette.controlText;
  self.closeButton.palette = palette;
  self.closeButton.contentTintColor = palette.controlText;
  self.closeButton.layer.borderWidth = palette.space0;
  self.closeButton.idleSurfaceColor = nil;
  self.closeButton.font = [NSFont systemFontOfSize:palette.space2 * 2];
  ((TLAttachmentCloseButtonCell *)self.closeButton.cell).strokeWidth = palette.borderWidth;
  self.closeButton.needsDisplay = YES;
  [self invalidateIntrinsicContentSize];
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  CGFloat height = NSHeight(self.bounds);
  CGFloat inset = self.palette.space3;
  CGFloat diameter = height - inset * 2;
  self.layer.cornerRadius = height / 2;
  // Content keeps its full width while the outer pill reveals/clips it.
  self.chipContentView.frame = NSMakeRect(0, 0, self.expandedWidth, height);
  self.closeButton.frame = NSMakeRect(self.expandedWidth - inset - diameter, inset, diameter, diameter);
  self.closeButton.layer.cornerRadius = diameter / 2;
  BOOL hasPreview = self.hasContentPreview;
  CGFloat imageHeight = self.image && !self.image.template ? self.image.size.height : self.palette.space11;
  // Fit the clipping view to the thumbnail itself so landscape PDFs and images
  // also get rounded corners, without letterboxed space above or below them.
  self.imageView.frame = NSMakeRect(self.imageLeadingInset, (height - imageHeight) / 2,
    self.image.size.width, imageHeight);
  self.imageView.layer.cornerRadius = hasPreview ? self.palette.radiusMedium / 2 : self.palette.space0;
  CGFloat labelX = NSMaxX(self.imageView.frame) + self.palette.space4;
  CGFloat labelHeight = self.label.intrinsicContentSize.height;
  self.label.frame = [self.label frameForAlignmentRect:NSMakeRect(labelX, (height - labelHeight) / 2,
    MAX(0, NSMinX(self.closeButton.frame) - self.palette.space4 - labelX), labelHeight)];
}
- (void)loadPreviewForURL:(NSURL *)URL {
  // Let Quick Look choose the provider for every file type, including videos,
  // documents and formats supported by installed thumbnail extensions.
  self.previewURL = URL;
  self.previewSecurityScope = [URL startAccessingSecurityScopedResource];
  CGFloat size = self.palette.space11 - self.palette.borderWidth * 2;
  CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor ?: 1.0;
  QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:URL
    size:CGSizeMake(size, size) scale:scale representationTypes:QLThumbnailGenerationRequestRepresentationTypeAll];
  self.thumbnailRequest = request;
  __weak typeof(self) weakSelf = self;
  [QLThumbnailGenerator.sharedGenerator generateBestRepresentationForRequest:request
    completionHandler:^(QLThumbnailRepresentation *thumbnail, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        TLAttachmentChipView *button = weakSelf;
        if (!button || button.thumbnailRequest != request) return;
        button.thumbnailRequest = nil;
        if (button.previewSecurityScope) {
          [button.previewURL stopAccessingSecurityScopedResource];
          button.previewSecurityScope = NO;
        }
        // Quick Look supplies a system file icon when no thumbnail is available;
        // keep the existing generic icon if the request itself fails.
        if (!thumbnail) return;
        NSImage *image = [thumbnail.NSImage copy];
        CGFloat longestSide = MAX(image.size.width, image.size.height);
        if (longestSide <= 0) return;
        image.size = NSMakeSize(image.size.width * size / longestSide, image.size.height * size / longestSide);
        image.template = NO;
        button.hasContentPreview = thumbnail.type != QLThumbnailRepresentationTypeIcon;
        button.image = image;
        [button invalidateIntrinsicContentSize];
        button.needsDisplay = YES;
      });
    }];
}
- (void)dealloc {
  if (_thumbnailRequest) [QLThumbnailGenerator.sharedGenerator cancelRequest:_thumbnailRequest];
  if (_previewSecurityScope) [_previewURL stopAccessingSecurityScopedResource];
}
@end

@interface TLMessageInput ()

@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) TLGlassButton *attachButton;
@property (nonatomic, strong) NSScrollView *attachmentScrollView;
@property (nonatomic, strong) NSStackView *attachmentStack;
@property (nonatomic, strong) TLTransitionCoordinator *attachmentTransitions;
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

- (void)setShowsStopButton:(BOOL)showsStopButton {
  if (_showsStopButton == showsStopButton) return;
  _showsStopButton = showsStopButton;
  NSString *label = showsStopButton ? @"Stop response" : @"Send";
  [self.sendButton setImage:[NSImage imageWithSystemSymbolName:showsStopButton ? @"stop.fill" : @"arrow.up"
                                   accessibilityDescription:label] animated:YES];
  self.sendButton.toolTip = label;
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
  return self.attachmentsEnabled && self.attachmentStack.arrangedSubviews.count ? self.palette.composerButtonHeight + self.palette.space3 : self.palette.space0;
}

- (void)setAttachmentsEnabled:(BOOL)enabled {
  _attachmentsEnabled = enabled;
  if (enabled && !self.attachButton) {
    [self buildAttachmentInterface];
    NSArray *pendingURLs = _attachmentURLs;
    _attachmentURLs = @[];
    [self setAttachmentURLs:pendingURLs animated:NO];
  }
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
  for (TLAttachmentChipView *chip in self.attachmentStack.arrangedSubviews) chip.enabled = editable && !chip.removing;
}

- (void)buildAttachmentInterface {
  self.attachmentTransitions = [[TLTransitionCoordinator alloc] init];
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
  // The original symbol inherited TLGlassButton's smallFont. Increase that
  // point size by 30%; resizing NSImage alone does not scale an SF Symbol.
  NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration
    configurationWithPointSize:self.palette.smallFont.pointSize * 1.3 weight:NSFontWeightRegular];
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
  self.attachmentScrollView.hidden = !self.attachmentsEnabled || !self.attachmentStack.arrangedSubviews.count;
  for (TLAttachmentChipView *chip in self.attachmentStack.arrangedSubviews) chip.palette = self.palette;
}

- (void)setAttachmentURLs:(NSArray<NSURL *> *)URLs {
  [self setAttachmentURLs:URLs animated:self.window != nil];
}

- (void)transitionAttachment:(TLAttachmentChipView *)chip visible:(BOOL)visible animated:(BOOL)animated {
  CGFloat start = chip.revealProgress;
  CGFloat end = visible ? 1 : 0;
  NSTimeInterval duration = animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion
    ? (visible ? self.palette.tabLifecycleTransitionDuration : self.palette.tabClosingTransitionDuration) : 0;
  __weak typeof(self) weakSelf = self;
  __weak TLAttachmentChipView *weakChip = chip;
  [self.attachmentTransitions startTransitionForKey:chip.transitionKey duration:duration
    update:^(CGFloat progress) {
      weakChip.revealProgress = start + (end - start) * progress;
      [weakSelf layoutSubtreeIfNeeded];
    } completion:^(BOOL finished) {
      TLMessageInput *input = weakSelf;
      TLAttachmentChipView *view = weakChip;
      if (!finished || !input || !view || !view.removing) return;
      [input.attachmentStack removeArrangedSubview:view];
      [view removeFromSuperview];
      [input applyAttachmentPalette];
      [input recalculateHeight];
      [input layoutSubtreeIfNeeded];
    }];
}

- (void)setAttachmentURLs:(NSArray<NSURL *> *)URLs animated:(BOOL)animated {
  NSArray<NSURL *> *next = [URLs copy] ?: @[];
  if ([next isEqualToArray:_attachmentURLs]) {
    if (!animated) [self.attachmentTransitions finishAllTransitions];
    return;
  }
  _attachmentURLs = next;
  if (!self.attachmentStack) return;
  // Match individual occurrences so duplicate URLs and reversing an in-flight
  // removal reuse the same view, decoded image and Quick Look request.
  NSMutableArray<TLAttachmentChipView *> *unmatched = [self.attachmentStack.arrangedSubviews mutableCopy];
  NSMutableArray<TLAttachmentChipView *> *active = [NSMutableArray array];
  NSMutableArray<TLAttachmentChipView *> *entering = [NSMutableArray array];
  for (NSURL *URL in next) {
    NSUInteger match = [unmatched indexOfObjectPassingTest:^BOOL(TLAttachmentChipView *chip, NSUInteger index, BOOL *stop) {
      return [chip.attachmentURL isEqual:URL];
    }];
    TLAttachmentChipView *chip;
    if (match != NSNotFound) {
      chip = unmatched[match];
      [unmatched removeObjectAtIndex:match];
      if (chip.removing) [entering addObject:chip];
    } else {
      chip = [[TLAttachmentChipView alloc] init];
      chip.palette = self.palette;
      chip.attachmentURL = URL;
      BOOL directory = URL.hasDirectoryPath;
      [NSFileManager.defaultManager fileExistsAtPath:URL.path isDirectory:&directory];
      chip.image = [NSImage imageWithSystemSymbolName:directory ? @"folder" : @"doc" accessibilityDescription:nil];
      chip.translatesAutoresizingMaskIntoConstraints = NO;
      chip.title = URL.lastPathComponent;
      chip.toolTip = URL.path;
      chip.closeButton.toolTip = [@"Remove " stringByAppendingString:URL.lastPathComponent];
      chip.closeButton.accessibilityLabel = [@"Remove attachment " stringByAppendingString:URL.lastPathComponent];
      chip.closeButton.target = self;
      chip.closeButton.action = @selector(removeAttachment:);
      [chip.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth / 3].active = YES;
      chip.revealProgress = animated ? 0 : 1;
      [entering addObject:chip];
      [chip loadPreviewForURL:URL];
    }
    chip.removing = NO;
    chip.enabled = self.attachmentsEditable;
    chip.closeButton.tag = active.count;
    [active addObject:chip];
  }
  for (TLAttachmentChipView *chip in unmatched) {
    chip.removing = YES;
    chip.enabled = NO;
    chip.closeButton.tag = -1;
  }
  // Keep exiting pills in their slots until they finish shrinking. Only move
  // retained views if the caller actually changes the file order.
  NSUInteger cursor = 0;
  for (TLAttachmentChipView *chip in active) {
    NSArray<TLAttachmentChipView *> *views = self.attachmentStack.arrangedSubviews;
    while (cursor < views.count && views[cursor].removing) cursor++;
    if ([views indexOfObjectIdenticalTo:chip] != cursor) {
      if (chip.superview) {
        [self.attachmentStack removeArrangedSubview:chip];
        [chip removeFromSuperview];
      }
      [self.attachmentStack insertArrangedSubview:chip atIndex:MIN(cursor, self.attachmentStack.arrangedSubviews.count)];
    }
    cursor++;
  }
  [self applyAttachmentPalette];
  [self recalculateHeight];
  [self layoutSubtreeIfNeeded];
  // Controller callbacks can do substantial layout work. Finish that before
  // starting the clock so the first presented frame is still collapsed.
  if (self.attachmentsChangeHandler) self.attachmentsChangeHandler();
  if (![_attachmentURLs isEqualToArray:next]) return;
  [self.window.contentView layoutSubtreeIfNeeded];
  [self.window displayIfNeeded];
  for (TLAttachmentChipView *chip in entering) [self transitionAttachment:chip visible:YES animated:animated];
  for (TLAttachmentChipView *chip in unmatched) {
    if (!animated || ![self.attachmentTransitions hasTransitionForKey:chip.transitionKey])
      [self transitionAttachment:chip visible:NO animated:animated];
    else {
      // An entering pill can be removed before its opening animation completes.
      // Retarget only when its existing track was opening, not on every update.
      if (!chip.closingTransition) [self transitionAttachment:chip visible:NO animated:animated];
    }
    chip.closingTransition = YES;
  }
  for (TLAttachmentChipView *chip in active) chip.closingTransition = NO;
  if (!animated) [self.attachmentTransitions finishAllTransitions];
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
    [self completeAttachmentSelection:panel response:result];
  }];
}

- (void)completeAttachmentSelection:(NSOpenPanel *)panel response:(NSModalResponse)response {
  NSArray<NSURL *> *URLs = response == NSModalResponseOK ? panel.URLs.copy : @[];
  // The sheet completion can run while the picker is still on screen. Hide it
  // and leave its completion stack before beginning the pill reveal.
  [panel orderOut:nil];
  if (!URLs.count) return;
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf addAttachmentURLs:URLs];
  });
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
