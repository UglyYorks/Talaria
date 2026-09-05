#import "TLThemedButton.h"

@interface TLThemedButtonCell : NSButtonCell
@end

@implementation TLThemedButtonCell

- (NSColor *)foregroundInView:(NSView *)view {
  TLThemedButton *button = (TLThemedButton *)view;
  if (!button.enabled) return button.palette.textMuted;
  return button.primary ? button.palette.primaryActionText : button.palette.secondaryActionText;
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
  if (!button.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, palette.disabledOpacity);
  [(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface) setFill];
  [surface fill];
  if (self.highlighted && button.enabled) {
    [palette.chromeHoverSurface setFill];
    [surface fill];
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
    [self applyTheme];
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyTheme]; }
- (void)setPrimary:(BOOL)primary { _primary = primary; [self applyTheme]; }
- (void)applyTheme {
  self.bezelColor = self.primary ? self.palette.primaryActionSurface : self.palette.secondaryActionSurface;
  self.needsDisplay = YES;
}
@end
