#import "TLSidebarSelectionButton.h"

@interface TLSidebarSelectionButton ()
@property (nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@property (nonatomic) BOOL hovered;
@end

@interface TLSidebarSelectionButtonCell : NSButtonCell
@end

@implementation TLSidebarSelectionButtonCell
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
  TLSidebarSelectionButton *button = (TLSidebarSelectionButton *)view;
  [NSGraphicsContext saveGraphicsState];
  if (!button.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, button.palette.disabledOpacity);
  [super drawWithFrame:frame inView:view];
  [NSGraphicsContext restoreGraphicsState];
}
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)view {
  TLSidebarSelectionButton *button = (TLSidebarSelectionButton *)view;
  TLThemePalette *p = button.palette;
  NSColor *surface = button.isSelected ? p.sidebarActiveSurface :
    (button.hovered || self.highlighted ? p.sidebarHoverSurface : p.transparentSurface);
  NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:frame
    xRadius:p.radiusMedium yRadius:p.radiusMedium];
  [surface setFill];
  [shape fill];
  if (button.enabled && button.window.firstResponder == button) {
    shape.lineWidth = p.focusRingSize;
    [p.controlFocus setStroke];
    [shape stroke];
  }
}
- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)view {
  TLSidebarSelectionButton *button = (TLSidebarSelectionButton *)view;
  NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.alignment = button.alignment;
  paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
  NSAttributedString *styled = [[NSAttributedString alloc] initWithString:button.title ?: @"" attributes:@{
    NSFontAttributeName: button.font ?: button.palette.labelFont,
    NSForegroundColorAttributeName: button.isSelected || button.hovered ? button.palette.appText : button.palette.textMuted,
    NSParagraphStyleAttributeName: paragraph,
  }];
  NSRect textFrame = NSInsetRect(view.bounds, button.palette.space4, 0);
  textFrame.origin.y = floor((NSHeight(view.bounds) - styled.size.height) * 0.5);
  textFrame.size.height = ceil(styled.size.height);
  [styled drawInRect:textFrame];
  return textFrame;
}
@end

@implementation TLSidebarSelectionButton
+ (Class)cellClass { return TLSidebarSelectionButtonCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.bezelStyle = NSBezelStyleRounded;
    self.focusRingType = NSFocusRingTypeNone;
    [self applyTheme];
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyTheme]; }
- (void)setSelected:(BOOL)selected { _selected = selected; self.needsDisplay = YES; }
- (void)setCompact:(BOOL)compact { _compact = compact; [self applyTheme]; }
- (void)applyTheme {
  self.font = self.compact ? self.palette.smallFont : self.palette.labelFont;
  [self invalidateIntrinsicContentSize];
  self.needsDisplay = YES;
}
- (NSSize)intrinsicContentSize {
  NSSize size = [super intrinsicContentSize];
  CGFloat width = [self.title sizeWithAttributes:@{NSFontAttributeName:self.font ?: self.palette.labelFont}].width;
  return NSMakeSize(MAX(size.width, ceil(width + self.palette.space8 * 2)),
                    MAX(size.height, self.palette.settingsActionHeight));
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
- (BOOL)becomeFirstResponder { BOOL value = [super becomeFirstResponder]; self.needsDisplay = YES; return value; }
- (BOOL)resignFirstResponder { BOOL value = [super resignFirstResponder]; self.needsDisplay = YES; return value; }
@end
