#import "TLThemedButton.h"

@interface TLThemedButton ()
@property (nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@property (nonatomic) BOOL hovered;
@end

@interface TLThemedButtonCell : NSButtonCell
@end

@implementation TLThemedButtonCell

- (NSColor *)foregroundInView:(NSView *)view {
  TLThemedButton *button = (TLThemedButton *)view;
  return button.primary ? button.palette.primaryActionText : button.palette.secondaryActionText;
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
  TLThemedButton *button = (TLThemedButton *)view;
  [NSGraphicsContext saveGraphicsState];
  // Dim the entire control together so the surface and title retain their pairing.
  if (!button.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, button.palette.disabledOpacity);
  [super drawWithFrame:frame inView:view];
  [NSGraphicsContext restoreGraphicsState];
}

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)view {
  TLThemedButton *button = (TLThemedButton *)view;
  TLThemePalette *palette = button.palette;
  // AppKit can also discard bezelColor for inactive/default buttons. Keep the paired
  // foreground and surface tokens together in every window state.
  NSBezierPath *surface = [NSBezierPath bezierPathWithRoundedRect:frame
    xRadius:MIN(palette.radiusMedium, NSHeight(frame) * 0.5)
    yRadius:MIN(palette.radiusMedium, NSHeight(frame) * 0.5)];
  [NSGraphicsContext saveGraphicsState];
  [(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface) setFill];
  [surface fill];
  if ((self.highlighted || button.hovered) && button.enabled) {
    [palette.chromeHoverSurface setFill];
    [surface fill];
  }
  if (button.enabled && button.window.firstResponder == button) {
    NSRect focusFrame = NSInsetRect(frame, palette.focusRingSize * 0.5, palette.focusRingSize * 0.5);
    NSBezierPath *focus = [NSBezierPath bezierPathWithRoundedRect:focusFrame
      xRadius:palette.radiusMedium yRadius:palette.radiusMedium];
    focus.lineWidth = palette.focusRingSize;
    [palette.controlFocus setStroke];
    [focus stroke];
  }
  [NSGraphicsContext restoreGraphicsState];
}

- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)view {
  // Bordered buttons ignore contentTintColor and may substitute their default-action text color.
  NSMutableAttributedString *coloredTitle = [title mutableCopy];
  [coloredTitle addAttribute:NSForegroundColorAttributeName value:[self foregroundInView:view]
                      range:NSMakeRange(0, coloredTitle.length)];
  [coloredTitle drawInRect:frame];
  return frame;
}

- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)view {
  if (!image.template) { [super drawImage:image withFrame:frame inView:view]; return; }
  NSColor *color = [self foregroundInView:view];
  NSImage *tinted = [NSImage imageWithSize:image.size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
    [image drawInRect:bounds];
    [color setFill];
    NSRectFillUsingOperation(bounds, NSCompositingOperationSourceIn);
    return YES;
  }];
  [super drawImage:tinted withFrame:frame inView:view];
}
@end

@implementation TLThemedButton
+ (Class)cellClass { return TLThemedButtonCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.bezelStyle = NSBezelStyleRounded;
    self.focusRingType = NSFocusRingTypeNone;
    [self applyTheme];
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyTheme];
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.hoverTrackingArea) [self removeTrackingArea:self.hoverTrackingArea];
  self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
    owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTrackingArea];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.needsDisplay = YES; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; self.hovered = NO; self.needsDisplay = YES; }
- (BOOL)becomeFirstResponder {
  BOOL accepted = [super becomeFirstResponder]; self.needsDisplay = YES; return accepted;
}
- (BOOL)resignFirstResponder {
  BOOL accepted = [super resignFirstResponder]; self.needsDisplay = YES; return accepted;
}
- (void)setPrimary:(BOOL)primary { _primary = primary; [self applyTheme]; }
- (NSSize)intrinsicContentSize {
  NSSize nativeSize = [super intrinsicContentSize];
  CGFloat titleWidth = [self.title sizeWithAttributes:@{NSFontAttributeName:self.font ?: self.palette.labelFont}].width;
  CGFloat imageWidth = self.image ? self.image.size.width + self.palette.space4 : 0;
  return NSMakeSize(MAX(nativeSize.width, ceil(titleWidth + imageWidth + self.palette.space8 * 2)),
                    MAX(nativeSize.height, self.palette.settingsActionHeight));
}
- (void)applyTheme {
  self.font = self.palette.labelFont;
  self.bezelColor = self.primary ? self.palette.primaryActionSurface : self.palette.secondaryActionSurface;
  [self invalidateIntrinsicContentSize];
  self.needsDisplay = YES;
}
@end
