#import "TLChromeTabView.h"
#import "TLTabIconView.h"
#import <QuartzCore/QuartzCore.h>

CGFloat TLChromeTabInterTabOverlapForWidth(CGFloat width, TLThemePalette *palette) {
  CGFloat flareOutset = MIN(palette.tabFlareRadius, width * 0.18);
  CGFloat tightening = MIN(palette.space2, flareOutset * 0.5);
  return flareOutset + tightening;
}

@interface TLChromeTabTextFieldCell : NSTextFieldCell
@end

@implementation TLChromeTabTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)rect {
  NSRect drawingRect = [super drawingRectForBounds:rect];
  NSSize cellSize = [self cellSizeForBounds:rect];
  CGFloat heightDelta = NSHeight(drawingRect) - ceil(cellSize.height);
  if (heightDelta > 0.0) {
    drawingRect.origin.y += floor(heightDelta * 0.5);
    drawingRect.size.height -= heightDelta;
  }
  return drawingRect;
}

@end

@interface TLChromeTabCloseButton : NSButton
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSColor *normalContentTintColor;
@property (nonatomic, strong) NSColor *hoverContentTintColor;
@end

@interface TLChromeTabCloseButton ()
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, strong) CALayer *hoverBackgroundLayer;
@property (nonatomic, strong) NSImageView *glyphView;
@property (nonatomic, strong) NSLayoutConstraint *glyphWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *glyphHeightConstraint;
@property (nonatomic, getter=isHovered) BOOL hovered;
@end

@implementation TLChromeTabCloseButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _normalContentTintColor = _palette.textMuted;
    _hoverContentTintColor = _palette.appText;
    self.bordered = NO;
    self.imagePosition = NSImageOnly;
    self.imageScaling = NSImageScaleNone;
    self.wantsLayer = YES;
    _hoverBackgroundLayer = [CALayer layer];
    [self.layer addSublayer:_hoverBackgroundLayer];
    _glyphView = [[NSImageView alloc] init];
    _glyphView.translatesAutoresizingMaskIntoConstraints = NO;
    _glyphView.imageAlignment = NSImageAlignCenter;
    _glyphView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_glyphView];
    _glyphWidthConstraint = [_glyphView.widthAnchor constraintEqualToConstant:[self glyphLength]];
    _glyphHeightConstraint = [_glyphView.heightAnchor constraintEqualToConstant:[self glyphLength]];
    [NSLayoutConstraint activateConstraints:@[
      [_glyphView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_glyphView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _glyphWidthConstraint,
      _glyphHeightConstraint,
    ]];
    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  CGFloat length = [self buttonLength];
  return NSMakeSize(length, length);
}

- (NSEdgeInsets)alignmentRectInsets {
  return NSEdgeInsetsMake(self.palette.space0, self.palette.space0, self.palette.space0, self.palette.space0);
}

- (NSView *)hitTest:(NSPoint)point {
  NSView *hitView = [super hitTest:point];
  return hitView == self.glyphView ? self : hitView;
}

- (void)layout {
  [super layout];
  [self updateHoverBackgroundLayer];
  [self applyCurrentState];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self invalidateIntrinsicContentSize];
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  NSImage *templateImage = image ? [image copy] : nil;
  templateImage.template = YES;
  self.glyphView.image = templateImage;
  [super setImage:nil];
}

- (void)setNormalContentTintColor:(NSColor *)normalContentTintColor {
  _normalContentTintColor = normalContentTintColor ?: self.palette.textMuted;
  [self applyCurrentState];
}

- (void)setHoverContentTintColor:(NSColor *)hoverContentTintColor {
  _hoverContentTintColor = hoverContentTintColor ?: self.palette.appText;
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  [self applyCurrentState];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) {
    self.hovered = NO;
  }
  [self applyCurrentState];
}

- (void)applyCurrentState {
  BOOL showHoverBackground = self.enabled && self.hovered;
  NSColor *tintColor = showHoverBackground
    ? (self.hoverContentTintColor ?: self.palette.appText)
    : (self.normalContentTintColor ?: self.palette.textMuted);
  self.contentTintColor = tintColor;
  self.glyphView.contentTintColor = tintColor;
  self.glyphView.alphaValue = showHoverBackground ? 1.0 : self.palette.roleOpacity;
  self.glyphWidthConstraint.constant = [self glyphLength];
  self.glyphHeightConstraint.constant = [self glyphLength];
  self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
    NSForegroundColorAttributeName: tintColor,
    NSFontAttributeName: self.font ?: self.palette.smallFont,
  }];
  self.layer.backgroundColor = TLCGColor(self.palette.transparentSurface);
  self.layer.masksToBounds = NO;
  self.hoverBackgroundLayer.backgroundColor = showHoverBackground
    ? TLCGColor(self.palette.secondaryActionSurface)
    : TLCGColor(self.palette.transparentSurface);
  [self updateHoverBackgroundLayer];
}

- (void)updateHoverBackgroundLayer {
  if (!self.layer) {
    return;
  }
  if (!self.hoverBackgroundLayer.superlayer) {
    [self.layer insertSublayer:self.hoverBackgroundLayer atIndex:0];
  }

  CGFloat availableWidth = MAX(self.palette.space0, NSWidth(self.bounds));
  CGFloat availableHeight = MAX(self.palette.space0, NSHeight(self.bounds));
  CGFloat length = MIN([self buttonLength], MIN(availableWidth, availableHeight));
  CGFloat originX = floor((availableWidth - length) * 0.5);
  CGFloat originY = floor((availableHeight - length) * 0.5);

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.hoverBackgroundLayer.frame = CGRectMake(originX, originY, length, length);
  self.hoverBackgroundLayer.cornerRadius = length * 0.5;
  self.hoverBackgroundLayer.masksToBounds = YES;
  [CATransaction commit];
}

- (CGFloat)buttonLength {
  return self.palette.space9 + self.palette.space2;
}

- (CGFloat)glyphLength {
  return self.palette.space6;
}

@end

@interface TLChromeTabView ()
@property (nonatomic, strong) TLTabIconView *tabIconView;
@property (nonatomic, strong) NSView *titleClipView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) TLChromeTabCloseButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *iconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconSpacingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleClipHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleClipTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeTrailingConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) NSPoint mouseDownWindowPoint;
@property (nonatomic) BOOL didDrag;
@property (nonatomic, readwrite, getter=isHovered) BOOL hovered;
@property (nonatomic, readwrite) CGFloat dragTranslationX;
@end

@implementation TLChromeTabView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _icon = @"";
    _systemIconName = @"";
    _closeable = YES;
    _leadingFlareOutset = -1.0;
    self.wantsLayer = YES;
    [self buildSubviews];
    [self applyCurrentState];
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (BOOL)mouseDownCanMoveWindow {
  return NO;
}

- (void)setTag:(NSInteger)tag {
  [super setTag:tag];
  self.closeButton.tag = tag;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setTitle:(NSString *)title {
  _title = [title copy] ?: @"";
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self applyCurrentState];
}

- (void)setIcon:(NSString *)icon {
  _icon = [icon copy] ?: @"";
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setActive:(BOOL)active {
  _active = active;
  self.layer.zPosition = active ? 1.0 : 0.0;
  [self applyCurrentState];
}

- (void)setCloseable:(BOOL)closeable {
  _closeable = closeable;
  [self applyCurrentState];
}

- (void)setShowsLeadingSeparator:(BOOL)showsLeadingSeparator {
  _showsLeadingSeparator = showsLeadingSeparator;
  [self setNeedsDisplay:YES];
}

- (void)setShowsTrailingSeparator:(BOOL)showsTrailingSeparator {
  _showsTrailingSeparator = showsTrailingSeparator;
  [self setNeedsDisplay:YES];
}

- (void)setLeadingFlareOutset:(CGFloat)leadingFlareOutset {
  _leadingFlareOutset = leadingFlareOutset;
  [self updateHorizontalContentInset];
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  self.closeButton.enabled = enabled && self.closeable;
  [self applyCurrentState];
}

- (void)buildSubviews {
  self.tabIconView = [[TLTabIconView alloc] init];
  self.tabIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabIconView.palette = self.palette;

  self.titleClipView = [[NSView alloc] init];
  self.titleClipView.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleClipView.wantsLayer = YES;
  self.titleClipView.layer.masksToBounds = YES;
  [self.titleClipView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.titleClipView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

  self.titleLabel = [self labelWithString:@""];
  self.titleLabel.lineBreakMode = NSLineBreakByClipping;

  self.closeButton = [[TLChromeTabCloseButton alloc] init];
  self.closeButton.title = @"x";
  self.closeButton.target = self;
  self.closeButton.action = @selector(closeTab:);
  self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.closeButton.toolTip = @"Close tab";
  if (@available(macOS 11.0, *)) {
    self.closeButton.title = @"";
    self.closeButton.image = [self closeButtonImageWithLength:self.palette.space6];
  }

  [self addSubview:self.tabIconView];
  [self addSubview:self.titleClipView];
  [self.titleClipView addSubview:self.titleLabel];
  [self addSubview:self.closeButton];

  self.iconLeadingConstraint = [self.tabIconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                               constant:self.palette.tabIconLeadingInset];
  self.iconWidthConstraint = [self.tabIconView.widthAnchor constraintEqualToConstant:self.palette.tabIconSize];
  self.iconHeightConstraint = [self.tabIconView.heightAnchor constraintEqualToConstant:self.palette.tabIconSize];
  self.iconCenterYConstraint = [self.tabIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
                                                                               constant:[self tabIconContainerVerticalOffset]];
  self.iconSpacingConstraint = [self.titleClipView.leadingAnchor constraintEqualToAnchor:self.tabIconView.trailingAnchor
                                                                                 constant:self.palette.tabIconTextSpacing];
  self.titleClipHeightConstraint = [self.titleClipView.heightAnchor constraintEqualToConstant:self.palette.tabHeight];
  self.titleClipTrailingConstraint = [self.titleClipView.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor
                                                                                       constant:self.palette.space0];
  self.closeWidthConstraint = [self.closeButton.widthAnchor constraintEqualToConstant:[self closeButtonLength]];
  self.closeHeightConstraint = [self.closeButton.heightAnchor constraintEqualToConstant:[self closeButtonLength]];
  self.closeTrailingConstraint = [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                                 constant:self.palette.space0];

  [NSLayoutConstraint activateConstraints:@[
    self.iconLeadingConstraint,
    self.iconWidthConstraint,
    self.iconHeightConstraint,
    self.iconCenterYConstraint,

    self.iconSpacingConstraint,
    self.titleClipTrailingConstraint,
    [self.titleClipView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.titleClipHeightConstraint,
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.titleClipView.leadingAnchor],
    [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.titleClipView.trailingAnchor],
    [self.titleLabel.topAnchor constraintEqualToAnchor:self.titleClipView.topAnchor],
    [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.titleClipView.bottomAnchor],

    self.closeTrailingConstraint,
    [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.closeWidthConstraint,
    self.closeHeightConstraint,
  ]];
}

- (NSTextField *)labelWithString:(NSString *)string {
  NSTextField *label = [[NSTextField alloc] init];
  label.cell = [[TLChromeTabTextFieldCell alloc] initTextCell:string ?: @""];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.bordered = NO;
  label.bezeled = NO;
  label.drawsBackground = NO;
  label.editable = NO;
  label.selectable = NO;
  label.lineBreakMode = NSLineBreakByClipping;
  label.maximumNumberOfLines = 1;
  label.cell.lineBreakMode = NSLineBreakByClipping;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
  [label setContentHuggingPriority:NSLayoutPriorityDefaultLow
                    forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}

- (void)layout {
  [super layout];
  [self updateHorizontalContentInset];
  [self updateTitleFadeMask];
}

- (void)applyCurrentState {
  if (!self.tabIconView || !self.titleLabel || !self.closeButton) {
    return;
  }

  BOOL highlighted = self.active || (self.hovered && self.enabled);
  NSColor *foreground = highlighted ? self.palette.appText : self.palette.labelText;
  BOOL hasSystemIcon = self.systemIconName.length > 0;
  BOOL hasEmojiIcon = self.icon.length > 0 && !hasSystemIcon;
  self.titleLabel.stringValue = self.title;
  self.titleLabel.font = self.palette.labelFont;
  self.titleLabel.textColor = foreground;
  self.tabIconView.palette = self.palette;
  self.tabIconView.image = self.image;
  self.tabIconView.icon = hasEmojiIcon ? self.icon : @"";
  self.tabIconView.systemIconName = hasSystemIcon ? self.systemIconName : @"";
  self.tabIconView.contentTintColor = foreground;
  [self updateHorizontalContentInset];
  self.iconWidthConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconSize : self.palette.space0;
  self.iconHeightConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconSize : self.palette.space0;
  self.iconCenterYConstraint.constant = [self tabIconContainerVerticalOffset];
  self.iconSpacingConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconTextSpacing : self.palette.space0;
  self.titleClipHeightConstraint.constant = self.palette.tabHeight;

  BOOL closeButtonVisible = self.closeable && self.hovered;
  self.closeButton.hidden = !closeButtonVisible;
  self.closeButton.enabled = self.enabled && closeButtonVisible;
  self.closeButton.alphaValue = closeButtonVisible ? 1.0 : 0.0;
  self.closeButton.palette = self.palette;
  self.closeButton.font = self.palette.smallFont;
  self.closeButton.normalContentTintColor = self.palette.textMuted;
  self.closeButton.hoverContentTintColor = foreground;
  if (@available(macOS 11.0, *)) {
    self.closeButton.image = [self closeButtonImageWithLength:self.palette.space6];
  }
  self.titleClipTrailingConstraint.constant = closeButtonVisible ? -self.palette.space3 : -(self.palette.space5 + self.palette.space3);
  self.closeWidthConstraint.constant = closeButtonVisible ? [self closeButtonLength] : self.palette.space0;
  self.closeHeightConstraint.constant = closeButtonVisible ? [self closeButtonLength] : self.palette.space0;
  self.closeTrailingConstraint.constant = closeButtonVisible ? -self.palette.space8 : self.palette.space0;

  self.layer.backgroundColor = TLCGColor(self.palette.transparentSurface);
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
  [self updateTitleFadeMask];
}

- (nullable NSImage *)closeButtonImageWithLength:(CGFloat)length {
  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close tab"];
    image.template = YES;
    NSImage *sizedImage = [image copy];
    sizedImage.size = NSMakeSize(length, length);
    return sizedImage;
  }
  return nil;
}

- (CGFloat)closeButtonLength {
  return self.palette.space9 + self.palette.space2;
}

- (CGFloat)tabIconContainerVerticalOffset {
  return self.image || self.systemIconName.length > 0 ? self.palette.space0 : self.palette.space2;
}

- (void)updateHorizontalContentInset {
  CGFloat width = NSWidth(self.bounds);
  CGFloat defaultFlareOutset = width > self.palette.space0
    ? MIN(self.palette.tabFlareRadius, width * 0.18)
    : self.palette.tabFlareRadius;
  CGFloat effectiveFlareOutset = self.leadingFlareOutset >= self.palette.space0
    ? MIN(defaultFlareOutset, self.leadingFlareOutset)
    : defaultFlareOutset;
  self.iconLeadingConstraint.constant = self.palette.tabIconLeadingInset -
    (defaultFlareOutset - effectiveFlareOutset);
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  if (self.hovered) {
    return;
  }
  self.hovered = YES;
  [self applyCurrentState];
  [self.dragDelegate chromeTabViewHoverStateDidChange:self];
}

- (void)mouseExited:(NSEvent *)event {
  if (!self.hovered) {
    return;
  }
  self.hovered = NO;
  [self applyCurrentState];
  [self.dragDelegate chromeTabViewHoverStateDidChange:self];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window && self.hovered) {
    self.hovered = NO;
    [self.dragDelegate chromeTabViewHoverStateDidChange:self];
  }
  [self applyCurrentState];
}

- (void)updateTitleFadeMask {
  if (!self.titleClipView.layer) {
    return;
  }

  CGFloat clipWidth = NSWidth(self.titleClipView.bounds);
  CGFloat labelWidth = self.titleLabel.intrinsicContentSize.width;
  if (clipWidth <= 0.0 || labelWidth <= clipWidth + self.palette.space2) {
    self.titleClipView.layer.mask = nil;
    return;
  }

  CGFloat preferredFadeWidth = self.closeable && self.hovered
    ? self.palette.space12
    : self.palette.space12 - self.palette.space2;
  CGFloat fadeWidth = MIN(preferredFadeWidth, clipWidth * 0.5);
  CGFloat solidStop = MAX(0.0, MIN(1.0, (clipWidth - fadeWidth) / clipWidth));
  CAGradientLayer *mask = [CAGradientLayer layer];
  mask.frame = self.titleClipView.bounds;
  mask.startPoint = CGPointMake(0.0, 0.5);
  mask.endPoint = CGPointMake(1.0, 0.5);
  mask.colors = @[
    (__bridge id)TLCGColor(self.palette.appText),
    (__bridge id)TLCGColor(self.palette.appText),
    (__bridge id)TLCGColor(self.palette.transparentSurface),
  ];
  mask.locations = @[@0.0, @(solidStop), @1.0];
  self.titleClipView.layer.mask = mask;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if (!self.active) {
    if ([self shouldDrawInactiveHoverPill]) {
      [self drawInactiveHoverPillInRect:self.bounds];
    } else {
      [self drawInactiveSeparatorsInRect:self.bounds];
    }
    return;
  }

  NSBezierPath *path = [self tabPathInRect:[self activeTabRectInRect:self.bounds]];
  [self.palette.tabBackground setFill];
  [path fill];
}

- (NSRect)activeTabRectInRect:(NSRect)rect {
  rect.size.height = MAX(self.palette.space0,
                         NSHeight(rect) - self.palette.tabActiveHeightReduction);
  return rect;
}

- (BOOL)shouldDrawInactiveHoverPill {
  return self.enabled && self.hovered;
}

- (void)drawInactiveHoverPillInRect:(NSRect)rect {
  NSRect pillRect = [self inactiveHoverPillRectInRect:rect];
  if (NSWidth(pillRect) <= self.palette.space0 || NSHeight(pillRect) <= self.palette.space0) {
    return;
  }

  CGFloat radius = MIN(self.palette.tabFlareRadius, NSHeight(pillRect) * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pillRect
                                                       xRadius:radius
                                                       yRadius:radius];
  [self.palette.secondaryActionSurface setFill];
  [path fill];
}

- (NSRect)inactiveHoverPillRectInRect:(NSRect)rect {
  CGFloat flareOutset = MIN(self.palette.tabFlareRadius, NSWidth(rect) * 0.18);
  return NSMakeRect(NSMinX(rect) + flareOutset,
                    NSMinY(rect) + self.palette.space2,
                    MAX(self.palette.space0, NSWidth(rect) - flareOutset * 2.0),
                    MAX(self.palette.space0, NSHeight(rect) - self.palette.space2 * 2.0));
}

- (void)drawInactiveSeparatorsInRect:(NSRect)rect {
  if (!self.showsLeadingSeparator && !self.showsTrailingSeparator) {
    return;
  }

  [self.palette.tabBorder setFill];
  CGFloat width = self.palette.borderWidth;
  CGFloat insetY = self.palette.space5;
  CGFloat height = MAX(0.0, rect.size.height - insetY * 2.0);
  if (self.showsLeadingSeparator) {
    CGFloat centerX = [self inactiveLeadingSeparatorCenterXInRect:rect];
    NSRectFill(NSMakeRect(centerX - width * 0.5, NSMinY(rect) + insetY, width, height));
  }
  if (self.showsTrailingSeparator) {
    NSRectFill(NSMakeRect(NSMaxX(rect) - width, NSMinY(rect) + insetY, width, height));
  }
}

- (CGFloat)inactiveLeadingSeparatorCenterXInRect:(NSRect)rect {
  CGFloat overlap = TLChromeTabInterTabOverlapForWidth(NSWidth(rect), self.palette);
  return NSMinX(rect) + overlap * 0.5;
}

- (NSBezierPath *)tabPathInRect:(NSRect)rect {
  CGFloat radius = MIN(self.palette.radiusMedium, NSHeight(rect) * 0.45);
  CGFloat flareOutset = MIN(self.palette.tabFlareRadius, rect.size.width * 0.18);
  CGFloat flareHeight = MIN(self.palette.tabFlareRadius, rect.size.height * 0.5);
  CGFloat leadingFlareOutset = self.leadingFlareOutset >= 0.0 ? MIN(flareOutset, self.leadingFlareOutset) : flareOutset;
  CGFloat leadingFlareRadius = MIN(leadingFlareOutset, flareHeight);
  CGFloat trailingFlareRadius = MIN(flareOutset, flareHeight);
  CGFloat minX = NSMinX(rect);
  CGFloat maxX = NSMaxX(rect);
  CGFloat minY = NSMinY(rect);
  CGFloat maxY = NSMaxY(rect);
  CGFloat leftBodyX = minX + leadingFlareOutset;
  CGFloat rightBodyX = maxX - flareOutset;
  CGFloat leftFlareX = leftBodyX - leadingFlareRadius;
  CGFloat rightFlareX = rightBodyX + trailingFlareRadius;

  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint(leftFlareX, minY)];
  [path lineToPoint:NSMakePoint(rightFlareX, minY)];
  [path appendBezierPathWithArcWithCenter:NSMakePoint(rightFlareX, minY + trailingFlareRadius)
                                   radius:trailingFlareRadius
                               startAngle:270.0
                                 endAngle:180.0
                                clockwise:YES];
  [path lineToPoint:NSMakePoint(rightBodyX, maxY - radius)];
  [path curveToPoint:NSMakePoint(rightBodyX - radius, maxY)
       controlPoint1:NSMakePoint(rightBodyX, maxY - radius * 0.45)
       controlPoint2:NSMakePoint(rightBodyX - radius * 0.45, maxY)];
  [path lineToPoint:NSMakePoint(leftBodyX + radius, maxY)];
  [path curveToPoint:NSMakePoint(leftBodyX, maxY - radius)
       controlPoint1:NSMakePoint(leftBodyX + radius * 0.45, maxY)
       controlPoint2:NSMakePoint(leftBodyX, maxY - radius * 0.45)];
  [path lineToPoint:NSMakePoint(leftBodyX, minY + leadingFlareRadius)];
  if (leadingFlareRadius > 0.0) {
    [path appendBezierPathWithArcWithCenter:NSMakePoint(leftFlareX, minY + leadingFlareRadius)
                                     radius:leadingFlareRadius
                                 startAngle:0.0
                                   endAngle:270.0
                                  clockwise:YES];
  } else {
    [path lineToPoint:NSMakePoint(leftFlareX, minY)];
  }
  [path closePath];
  return path;
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.mouseDownWindowPoint = event.locationInWindow;
  self.didDrag = NO;
  self.dragTranslationX = 0.0;
  self.layer.zPosition = 2.0;
}

- (void)mouseDragged:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  CGFloat proposedHorizontalTranslation = event.locationInWindow.x - self.mouseDownWindowPoint.x;
  CGFloat deltaX = fabs(proposedHorizontalTranslation);
  CGFloat deltaY = fabs(event.locationInWindow.y - self.mouseDownWindowPoint.y);
  if (deltaX < 4.0 && deltaY < 4.0 && !self.didDrag) {
    return;
  }

  self.didDrag = YES;
  CGFloat horizontalTranslation = [self.dragDelegate chromeTabView:self
                      constrainedHorizontalTranslationForEvent:event
                                           proposedTranslation:proposedHorizontalTranslation];
  self.dragTranslationX = horizontalTranslation;
  [self.dragDelegate chromeTabView:self didDragWithEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  if (self.didDrag) {
    [self.dragDelegate chromeTabViewDidEndDragging:self];
    self.dragTranslationX = 0.0;
    self.layer.zPosition = self.active ? 1.0 : 0.0;
    return;
  }

  self.layer.zPosition = self.active ? 1.0 : 0.0;
  if (self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)setDragTranslationX:(CGFloat)dragTranslationX {
  _dragTranslationX = dragTranslationX;
  [self updateDragTransform];
}

- (void)updateDragTransform {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.layer.transform = CATransform3DMakeTranslation(self.dragTranslationX, 0.0, 0.0);
  [CATransaction commit];
}

- (void)closeTab:(id)sender {
  if (self.closeAction) {
    self.closeButton.tag = self.tag;
    [NSApp sendAction:self.closeAction to:self.target from:self.closeButton];
  }
}

@end
