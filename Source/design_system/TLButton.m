#import "TLButton.h"
#import <QuartzCore/QuartzCore.h>

@interface TLButton ()
@property (nonatomic, strong) NSButton *button;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, getter=isHovered) BOOL hovered;
@property (nonatomic, strong) CALayer *hoverBackgroundLayer;
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
  self.hoverBackgroundLayer = [CALayer layer];
  [self.layer addSublayer:self.hoverBackgroundLayer];
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

- (void)setFrameOrigin:(NSPoint)origin {
  [super setFrameOrigin:origin];
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self updateHoverStateFromCurrentMouseLocation];
  [self applyCurrentState];
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
  // Moving tabs can relocate the button without a mouse-exit event.
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)mouseEntered:(NSEvent *)event {
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)mouseExited:(NSEvent *)event {
  [self updateHoverStateFromCurrentMouseLocation];
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
  if (self.window.isVisible && ![self isHiddenOrHasHiddenAncestor] && !NSIsEmptyRect(self.visibleRect)) {
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    hovered = NSPointInRect(point, NSIntersectionRect(self.bounds, self.visibleRect));
  }

  if (self.hovered != hovered) {
    self.hovered = hovered;
  }
}

- (void)applyCurrentState {
  self.button.enabled = self.enabled;
  self.button.image = self.image;
  self.button.contentTintColor = self.contentTintColor ?: self.palette.labelText;

  BOOL showHoverBackground = self.enabled && self.hovered;
  NSRect surface = self.bounds;
  BOOL compact = self.style == TLButtonStyleCompactMinimal;
  if (compact) {
    CGFloat length = MIN(self.palette.compactButtonSurfaceSize, MIN(NSWidth(surface), NSHeight(surface)));
    surface = NSMakeRect(NSMidX(surface) - length * 0.5, NSMidY(surface) - length * 0.5, length, length);
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.hoverBackgroundLayer.frame = surface;
  self.hoverBackgroundLayer.backgroundColor = showHoverBackground
    ? TLCGColor(self.palette.secondaryActionSurface)
    : TLCGColor(self.palette.transparentSurface);
  self.hoverBackgroundLayer.cornerRadius = compact ? self.palette.compactButtonCornerRadius
    : MIN(NSWidth(surface), NSHeight(surface)) * 0.5;
  [CATransaction commit];
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
