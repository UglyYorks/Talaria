#import "TLAttachmentChipView.h"

@interface TLAttachmentChipView ()
@property (nonatomic, strong) NSTrackingArea *hoverTracking;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
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


@implementation TLAttachmentChipView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _showsRemoveButton = YES;
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
    self.label.intrinsicContentSize.width + (self.showsRemoveButton ? self.palette.space4 + self.palette.space11 + self.palette.space3 : self.palette.space6);
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
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.closeButton.enabled = enabled; }
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
  [self updateInteraction];
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  CGFloat height = NSHeight(self.bounds);
  CGFloat inset = self.palette.space3;
  CGFloat diameter = height - inset * 2;
  self.layer.cornerRadius = height / 2;
  // Content keeps its full width while the outer pill reveals/clips it.
  CGFloat width = self.showsRemoveButton ? self.expandedWidth : NSWidth(self.bounds);
  self.chipContentView.frame = NSMakeRect(0, 0, width, height);
  self.chipContentView.layer.cornerRadius = height / 2;
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
    MAX(0, (self.showsRemoveButton ? NSMinX(self.closeButton.frame) - self.palette.space4 : width - self.palette.space6) - labelX), labelHeight)];
  [self updateInteraction];
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

- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return self.showsRemoveButton ? NSAccessibilityGroupRole : NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return self.showsRemoveButton ? self.title : [@"Preview " stringByAppendingString:self.title ?: @"attachment"]; }
- (NSArray *)accessibilityChildren { return self.showsRemoveButton ? @[self.label, self.closeButton] : @[]; }
- (BOOL)accessibilityPerformPress { if (self.activationHandler) self.activationHandler(); return self.activationHandler != nil; }
- (BOOL)acceptsFirstResponder { return !self.showsRemoveButton; }
- (BOOL)becomeFirstResponder { self.needsLayout = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsLayout = YES; return YES; }
- (void)setShowsRemoveButton:(BOOL)showsRemoveButton {
  _showsRemoveButton = showsRemoveButton; self.closeButton.hidden = !showsRemoveButton;
  [self invalidateIntrinsicContentSize]; self.needsLayout = YES;
}
- (void)invalidateIntrinsicContentSize {
  [super invalidateIntrinsicContentSize];
  if ([self.superview isKindOfClass:TLAttachmentChipRow.class]) {
    [self.superview invalidateIntrinsicContentSize]; self.superview.needsLayout = YES;
  }
}
- (NSView *)hitTest:(NSPoint)point {
  NSView *hit = [super hitTest:point];
  return hit && !self.showsRemoveButton ? self : hit;
}
- (void)mouseDown:(NSEvent *)event {
  if (!self.activationHandler) { [super mouseDown:event]; return; }
  [self.window makeFirstResponder:self]; self.pressed = YES; [self updateInteraction];
}
- (void)mouseUp:(NSEvent *)event {
  BOOL activate = self.pressed && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
  self.pressed = NO; [self updateInteraction]; if (activate) [self accessibilityPerformPress];
}
- (void)keyDown:(NSEvent *)event {
  if ([event.charactersIgnoringModifiers isEqual:@" "] || [event.charactersIgnoringModifiers isEqual:@"\r"]) [self accessibilityPerformPress];
  else [super keyDown:event];
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.hoverTracking) [self removeTrackingArea:self.hoverTracking];
  self.hoverTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTracking];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; [self updateInteraction]; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; [self updateInteraction]; }
- (void)updateInteraction {
  BOOL interactive = !self.showsRemoveButton;
  self.chipContentView.layer.backgroundColor = TLCGColor(interactive && (self.hovered || self.pressed) ? self.palette.chromeHoverSurface : self.palette.transparentSurface);
  self.layer.borderColor = TLCGColor(self.palette.controlFocus);
  self.layer.borderWidth = interactive && self.window.firstResponder == self ? self.palette.borderWidth : self.palette.space0;
}
- (void)resetCursorRects { if (!self.showsRemoveButton) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }

- (void)dealloc {
  if (_thumbnailRequest) [QLThumbnailGenerator.sharedGenerator cancelRequest:_thumbnailRequest];
  if (_previewSecurityScope) [_previewURL stopAccessingSecurityScopedResource];
}
@end


@implementation TLAttachmentChipRow
- (instancetype)initWithChips:(NSArray<TLAttachmentChipView *> *)chips palette:(TLThemePalette *)palette {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _palette = palette; self.translatesAutoresizingMaskIntoConstraints = NO;
    for (TLAttachmentChipView *chip in chips) { chip.translatesAutoresizingMaskIntoConstraints = YES; [self addSubview:chip]; }
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (CGFloat)preferredWidth {
  CGFloat width = 0;
  for (NSView *chip in self.subviews) width += chip.intrinsicContentSize.width + self.palette.space3;
  return MAX(0, width - self.palette.space3);
}
- (CGFloat)arrange:(BOOL)apply {
  CGFloat width = MAX(1, NSWidth(self.bounds)), x = 0, y = 0, height = self.palette.fieldHeight;
  for (NSView *chip in self.subviews) {
    CGFloat itemWidth = MIN(width, chip.intrinsicContentSize.width);
    if (x > 0 && x + itemWidth > width) { x = 0; y += height + self.palette.space3; }
    if (apply) chip.frame = NSMakeRect(x, y, itemWidth, height);
    x += itemWidth + self.palette.space3;
  }
  return self.subviews.count ? y + height : 0;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, [self arrange:NO]); }
- (void)setFrameSize:(NSSize)size {
  BOOL changed = size.width != NSWidth(self.frame); [super setFrameSize:size];
  if (changed) { [self invalidateIntrinsicContentSize]; self.needsLayout = YES; }
}
- (void)layout { [super layout]; [self arrange:YES]; }
@end
