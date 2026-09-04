#import "TLButton.h"

@interface TLButton ()
@property (nonatomic, strong) NSButton *button;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, getter=isHovered) BOOL hovered;
@end

@implementation TLButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _enabled = YES;
    _style = TLButtonStyleMinimal;
    _size = TLButtonSizeMedium;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    [self buildInterface];
    [self applyCurrentState];
  }
  return self;
}

- (void)buildInterface {
  self.button = [[NSButton alloc] init];
  self.button.translatesAutoresizingMaskIntoConstraints = NO;
  self.button.bordered = NO;
  self.button.imagePosition = NSImageOnly;
  self.button.imageScaling = NSImageScaleNone;
  self.button.target = self;
  self.button.action = @selector(performAction:);
  [self addSubview:self.button];

  [NSLayoutConstraint activateConstraints:@[
    [self.button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.button.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
  ]];
}

- (void)layout {
  [super layout];
  [self updateHoverStateFromCurrentMouseLocation];
  [self applyCurrentState];
}

- (NSSize)intrinsicContentSize {
  CGFloat length = [self buttonLength];
  return NSMakeSize(length, length);
}

- (CGFloat)buttonLength {
  switch (self.size) {
    case TLButtonSizeMedium:
    default:
      return self.palette.space12 + self.palette.space4;
  }
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
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self updateHoverStateFromCurrentMouseLocation];
  [self applyCurrentState];
}

- (void)performAction:(id)sender {
  if (!self.enabled || !self.target || !self.action) {
    return;
  }

  [NSApp sendAction:self.action to:self.target from:self];
  [self updateHoverStateFromCurrentMouseLocation];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateHoverStateFromCurrentMouseLocation];
    [self applyCurrentState];
  });
}

- (void)updateHoverStateFromCurrentMouseLocation {
  BOOL hovered = NO;
  if (self.window && ![self isHiddenOrHasHiddenAncestor] && !NSIsEmptyRect(self.bounds)) {
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    hovered = NSPointInRect(point, self.bounds);
  }

  if (self.hovered != hovered) {
    self.hovered = hovered;
  }
}

- (void)applyCurrentState {
  self.button.enabled = self.enabled;
  self.button.image = self.image;
  self.button.contentTintColor = self.contentTintColor ?: self.palette.labelText;

  BOOL showHoverBackground = self.enabled && self.hovered && self.style == TLButtonStyleMinimal;
  self.layer.backgroundColor = showHoverBackground
    ? TLCGColor(self.palette.secondaryActionSurface)
    : TLCGColor(self.palette.transparentSurface);
  self.layer.cornerRadius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) * 0.5;
  self.layer.masksToBounds = YES;
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self applyCurrentState];
}

- (void)setContentTintColor:(NSColor *)contentTintColor {
  _contentTintColor = contentTintColor;
  [self applyCurrentState];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self invalidateIntrinsicContentSize];
  [self applyCurrentState];
}

- (void)setStyle:(TLButtonStyle)style {
  _style = style;
  [self applyCurrentState];
}

- (void)setSize:(TLButtonSize)size {
  _size = size;
  [self invalidateIntrinsicContentSize];
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  BOOL wasEffectivelyHovered = self.enabled && self.hovered;
  _enabled = enabled;
  [self applyCurrentState];
  BOOL effectivelyHovered = self.enabled && self.hovered;
  if (wasEffectivelyHovered != effectivelyHovered && self.hoverChanged) {
    self.hoverChanged(effectivelyHovered);
  }
}

- (void)setHovered:(BOOL)hovered {
  if (_hovered == hovered) {
    return;
  }

  _hovered = hovered;
  [self applyCurrentState];
  if (self.hoverChanged) {
    self.hoverChanged(self.enabled && hovered);
  }
}

- (void)setHoverChanged:(void (^)(BOOL))hoverChanged {
  _hoverChanged = [hoverChanged copy];
  if (_hoverChanged) {
    _hoverChanged(self.enabled && self.hovered);
  }
}

- (void)setToolTip:(NSString *)toolTip {
  [super setToolTip:toolTip];
  self.button.toolTip = toolTip;
}

- (NSString *)toolTip {
  return super.toolTip;
}

@end
