#import "TLGlassButton.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface TLHoverIconButton ()
@property (nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLHoverIconButton
- (NSEdgeInsets)alignmentRectInsets {
  return self.hoverSurfaceOnly ? NSEdgeInsetsMake(0, 0, 0, 0) : super.alignmentRectInsets;
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.hoverTrackingArea) { [self removeTrackingArea:self.hoverTrackingArea]; }
  self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
    owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTrackingArea];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; [self updateHoverSurface]; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; [self updateHoverSurface]; }
- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) { return; }
  self.pressed = YES;
  [self updateHoverSurface];
  [super mouseDown:event];
  self.pressed = NO;
  [self updateHoverSurface];
}
- (void)layout { [super layout]; [self updateHoverSurface]; }
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  self.hovered = NO;
  self.pressed = NO;
  [self updateHoverSurface];
}
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self updateHoverSurface]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; [self updateHoverSurface]; }
- (void)setHoverSurfaceOnly:(BOOL)hoverSurfaceOnly {
  _hoverSurfaceOnly = hoverSurfaceOnly;
  if (hoverSurfaceOnly) {
    self.wantsLayer = YES;
    self.bordered = NO;
    ((NSButtonCell *)self.cell).highlightsBy = NSNoCellMask;
    ((NSButtonCell *)self.cell).showsStateBy = NSNoCellMask;
  }
  [self invalidateIntrinsicContentSize];
  [self updateHoverSurface];
}
- (void)updateHoverSurface {
  if (!self.hoverSurfaceOnly || !self.palette) { return; }
  self.layer.cornerRadius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2.0;
  self.layer.backgroundColor = TLCGColor(self.enabled && (self.hovered || self.pressed)
    ? (self.pressed ? self.palette.sidebarActiveSurface : self.palette.chromeHoverSurface)
    : self.palette.transparentSurface);
}
@end

@interface TLGlassButtonContentStackView : NSStackView
@end

@implementation TLGlassButtonContentStackView

- (NSView *)hitTest:(NSPoint)point {
  return nil;
}

@end

@interface TLGlassButton ()
@property (nonatomic, strong) NSButton *button;
@property (nonatomic, strong, nullable) NSView *glassView;
@property (nonatomic, strong) NSView *controlView;
@property (nonatomic, strong) TLGlassButtonContentStackView *contentStack;
@property (nonatomic, strong) NSImageView *contentImageView;
@property (nonatomic, strong) NSTextField *contentLabel;
@property (nonatomic, strong) NSLayoutConstraint *contentImageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentImageHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentTrailingConstraint;
@property (nonatomic, strong) CAShapeLayer *solidSurfaceLayer;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, getter=isHovered) BOOL hovered;
@end

@implementation TLGlassButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    [self configureWithUsesGlassEffect:YES];
  }
  return self;
}

- (instancetype)initWithUsesGlassEffect:(BOOL)usesGlassEffect {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    [self configureWithUsesGlassEffect:usesGlassEffect];
  }
  return self;
}

- (void)configureWithUsesGlassEffect:(BOOL)usesGlassEffect {
  if (self.button) {
    return;
  }

  _enabled = YES;
  _usesGlassEffect = usesGlassEffect;
  _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  _title = @"";
  self.translatesAutoresizingMaskIntoConstraints = NO;
  [self buildInterface];
}

- (void)buildInterface {
  self.button = [[TLHoverIconButton alloc] init];
  self.button.translatesAutoresizingMaskIntoConstraints = NO;
  self.button.alignment = NSTextAlignmentCenter;
  self.button.imagePosition = NSImageOnly;
  self.button.imageScaling = NSImageScaleProportionallyDown;
  self.button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
  self.button.target = self;
  self.button.action = @selector(performAction:);

  self.contentStack = [[TLGlassButtonContentStackView alloc] init];
  self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  self.contentStack.alignment = NSLayoutAttributeCenterY;
  self.contentStack.distribution = NSStackViewDistributionGravityAreas;
  self.contentStack.spacing = self.palette.space3;
  self.contentStack.hidden = YES;

  self.contentImageView = [[NSImageView alloc] init];
  self.contentImageView.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentImageView.imageAlignment = NSImageAlignCenter;
  self.contentImageView.imageScaling = NSImageScaleProportionallyDown;
  [self.contentStack addArrangedSubview:self.contentImageView];

  self.contentLabel = [NSTextField labelWithString:@""];
  self.contentLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.contentLabel.usesSingleLineMode = YES;
  [self.contentStack addArrangedSubview:self.contentLabel];

  self.controlView = self.button;
  if (self.usesGlassEffect) {
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView *glassView = [[NSGlassEffectView alloc] init];
      glassView.translatesAutoresizingMaskIntoConstraints = NO;
      glassView.style = NSGlassEffectViewStyleRegular;
      self.button.bordered = NO;
      self.glassView = glassView;
      self.controlView = glassView;
    } else {
      self.button.bordered = YES;
      self.button.bezelStyle = NSBezelStyleCircular;
    }
  } else {
    self.button.bordered = YES;
    self.button.bezelStyle = NSBezelStyleCircular;
  }

  [self addSubview:self.controlView];
  [self addSubview:self.contentStack positioned:NSWindowAbove relativeTo:self.controlView];
  if (self.glassView) {
    [self addSubview:self.button positioned:NSWindowAbove relativeTo:self.contentStack];
  }
  self.contentImageWidthConstraint = [self.contentImageView.widthAnchor constraintEqualToConstant:self.palette.space9];
  self.contentImageHeightConstraint = [self.contentImageView.heightAnchor constraintEqualToConstant:self.palette.space9];
  self.contentLeadingConstraint = [self.contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor
                                                                                               constant:self.palette.space5];
  self.contentTrailingConstraint = [self.contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                               constant:-self.palette.space5];
  [NSLayoutConstraint activateConstraints:@[
    [self.controlView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.controlView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.controlView.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.controlView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [self.contentStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [self.contentStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.contentLeadingConstraint,
    self.contentTrailingConstraint,
    self.contentImageWidthConstraint,
    self.contentImageHeightConstraint,
  ]];

  if (self.glassView) {
    [NSLayoutConstraint activateConstraints:@[
      [self.button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [self.button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [self.button.topAnchor constraintEqualToAnchor:self.topAnchor],
      [self.button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
  }
  [self applyGlassState];
  [self applyButtonContent];
}

- (void)layout {
  [super layout];
  CGFloat radius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / 2.0;
  if (@available(macOS 26.0, *)) {
    ((NSGlassEffectView *)self.glassView).cornerRadius = radius;
  }
  [self applyGlassState];
}

- (NSSize)intrinsicContentSize {
  NSString *title = self.title ?: @"";
  BOOL hasTitle = title.length > 0;
  BOOL hasImage = self.image != nil;
  NSFont *font = self.font ?: self.palette.smallFont;
  CGFloat horizontalPadding = (hasImage && hasTitle) ? self.palette.space5 : self.palette.space3;
  CGFloat verticalPadding = self.palette.space2;
  CGFloat width = self.palette.space0;
  CGFloat height = self.palette.space0;
  if (hasImage && hasTitle) {
    CGFloat iconLength = [self contentIconLengthForFont:font];
    NSSize titleSize = [title sizeWithAttributes:@{NSFontAttributeName: font}];
    width = iconLength + self.palette.space3 + ceil(titleSize.width);
    height = MAX(iconLength, ceil(titleSize.height));
  } else {
    NSSize buttonSize = self.button.intrinsicContentSize;
    width = buttonSize.width == NSViewNoIntrinsicMetric ? self.palette.space0 : buttonSize.width;
    height = buttonSize.height == NSViewNoIntrinsicMetric ? self.palette.space0 : buttonSize.height;
  }
  return NSMakeSize(ceil(width + (horizontalPadding * 2.0)),
                    ceil(MAX(height + verticalPadding, self.palette.space11)));
}

- (CGFloat)contentIconLengthForFont:(NSFont *)font {
  return ceil(font.pointSize + self.palette.space2);
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
  [self applyGlassState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  [self applyGlassState];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) {
    self.hovered = NO;
  }
  [self applyGlassState];
}

- (void)applyGlassState {
  if (self.hoverSurfaceOnly) {
    self.solidSurfaceLayer.hidden = YES;
    return;
  }
  if (self.solidSurfaceColor) {
    self.button.bordered = NO;
    self.wantsLayer = YES;
    if (!self.solidSurfaceLayer) {
      self.solidSurfaceLayer = [CAShapeLayer layer];
      [self.layer insertSublayer:self.solidSurfaceLayer atIndex:0];
    }
    CGFloat diameter = MIN(NSWidth(self.bounds), NSHeight(self.bounds));
    CGRect circleRect = CGRectMake(floor((NSWidth(self.bounds) - diameter) * 0.5),
                                   floor((NSHeight(self.bounds) - diameter) * 0.5),
                                   diameter,
                                   diameter);
    self.solidSurfaceLayer.frame = self.bounds;
    CGPathRef circlePath = CGPathCreateWithEllipseInRect(circleRect, NULL);
    self.solidSurfaceLayer.path = circlePath;
    CGPathRelease(circlePath);
    self.solidSurfaceLayer.fillColor = TLCGColor(self.solidSurfaceColor);
    self.solidSurfaceLayer.hidden = NO;
    return;
  }
  self.solidSurfaceLayer.hidden = YES;
  NSColor *tintColor = nil;
  if (self.enabled) {
    tintColor = self.hovered
      ? (self.glassHoverTintColor ?: self.glassTintColor)
      : self.glassTintColor;
  }

  if (@available(macOS 26.0, *)) {
    if (!self.glassView || !self.usesGlassEffect) {
      self.button.bezelColor = tintColor;
      return;
    }

    NSGlassEffectView *glassView = (NSGlassEffectView *)self.glassView;
    glassView.tintColor = tintColor ?: ((self.enabled && self.hovered)
      ? self.palette.glassButtonHoverTint
      : nil);
    return;
  }

  self.button.bezelColor = tintColor;
}

- (void)applyButtonContent {
  if (!self.button) {
    return;
  }

  NSString *title = self.title ?: @"";
  BOOL hasTitle = title.length > 0;
  BOOL hasImage = self.image != nil;
  NSColor *foregroundColor = self.contentTintColor ?: self.palette.labelText;
  NSFont *font = self.font ?: self.palette.smallFont;
  BOOL usesCustomContent = hasImage && hasTitle;

  self.contentStack.hidden = !usesCustomContent;
  self.contentStack.spacing = self.palette.space3;
  self.contentLeadingConstraint.constant = self.palette.space5;
  self.contentTrailingConstraint.constant = -self.palette.space5;
  self.contentLabel.stringValue = title;
  self.contentLabel.font = font;
  self.contentLabel.textColor = foregroundColor;
  self.contentLabel.alignment = NSTextAlignmentCenter;
  self.contentImageView.image = self.image;
  self.contentImageView.contentTintColor = foregroundColor;
  CGFloat iconLength = [self contentIconLengthForFont:font];
  self.contentImageWidthConstraint.constant = iconLength;
  self.contentImageHeightConstraint.constant = iconLength;

  self.button.title = usesCustomContent ? @"" : title;
  self.button.image = usesCustomContent ? nil : self.image;
  self.button.font = font;
  self.button.contentTintColor = foregroundColor;
  if (usesCustomContent) {
    self.button.imagePosition = NSNoImage;
  } else if (hasImage && hasTitle) {
    self.button.imagePosition = NSImageLeft;
  } else if (hasImage) {
    self.button.imagePosition = NSImageOnly;
  } else {
    self.button.imagePosition = NSNoImage;
  }

  if (usesCustomContent) {
    self.button.attributedTitle = [[NSAttributedString alloc] initWithString:@""];
    self.button.title = @"";
  } else {
    self.button.attributedTitle =
      [[NSAttributedString alloc] initWithString:title
                                      attributes:@{
                                        NSForegroundColorAttributeName: foregroundColor,
                                        NSFontAttributeName: font,
                                      }];
  }
  [self invalidateIntrinsicContentSize];
}

- (void)setUsesGlassEffect:(BOOL)usesGlassEffect {
  if (_usesGlassEffect == usesGlassEffect || self.button) {
    _usesGlassEffect = usesGlassEffect;
    return;
  }

  _usesGlassEffect = usesGlassEffect;
}

- (void)setHoverSurfaceOnly:(BOOL)hoverSurfaceOnly {
  _hoverSurfaceOnly = hoverSurfaceOnly;
  ((TLHoverIconButton *)self.button).palette = self.palette;
  ((TLHoverIconButton *)self.button).hoverSurfaceOnly = hoverSurfaceOnly;
  self.glassView.hidden = hoverSurfaceOnly;
  [self applyGlassState];
}

- (void)performAction:(id)sender {
  if (!self.enabled || !self.target || !self.action) {
    return;
  }
  [NSApp sendAction:self.action to:self.target from:self];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self applyButtonContent];
}

- (void)setTitle:(NSString *)title {
  _title = [title copy] ?: @"";
  [self applyButtonContent];
}

- (void)setFont:(NSFont *)font {
  _font = font;
  [self applyButtonContent];
}

- (void)setContentTintColor:(NSColor *)contentTintColor {
  _contentTintColor = contentTintColor;
  [self applyButtonContent];
}

- (void)setGlassTintColor:(NSColor *)glassTintColor {
  _glassTintColor = glassTintColor;
  [self applyGlassState];
}

- (void)setGlassHoverTintColor:(NSColor *)glassHoverTintColor {
  _glassHoverTintColor = glassHoverTintColor;
  [self applyGlassState];
}

- (void)setSolidSurfaceColor:(NSColor *)solidSurfaceColor {
  _solidSurfaceColor = solidSurfaceColor;
  [self applyGlassState];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  ((TLHoverIconButton *)self.button).palette = _palette;
  self.contentLeadingConstraint.constant = self.palette.space5;
  self.contentTrailingConstraint.constant = -self.palette.space5;
  [self applyButtonContent];
  [self applyGlassState];
}

- (void)setEnabled:(BOOL)enabled {
  _enabled = enabled;
  self.button.enabled = enabled;
  [self applyGlassState];
}

- (void)setToolTip:(NSString *)toolTip {
  [super setToolTip:toolTip];
  self.button.toolTip = toolTip;
}

- (NSString *)toolTip {
  return super.toolTip;
}

@end
