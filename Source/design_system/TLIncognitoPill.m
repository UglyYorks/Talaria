#import "TLIncognitoPill.h"
@implementation TLIncognitoPill
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityStaticTextRole;
    self.accessibilityLabel = @"Incognito";
    self.toolTip = @"Private browsing and chats. Existing memory is read-only.";
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  [self invalidateIntrinsicContentSize];
  self.needsDisplay = YES;
}
- (NSSize)intrinsicContentSize {
  NSSize text = [@"Incognito" sizeWithAttributes:@{NSFontAttributeName: self.palette.labelFont}];
  return NSMakeSize(ceil(text.width) + 2 * self.palette.space4, self.palette.taskStatusPillHeight);
}
- (void)drawRect:(NSRect)dirtyRect {
  [self.palette.primaryActionSurface setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.palette.radiusPill yRadius:self.palette.radiusPill] fill];
  NSDictionary *attributes = @{NSFontAttributeName: self.palette.labelFont, NSForegroundColorAttributeName: self.palette.primaryActionText};
  NSSize size = [@"Incognito" sizeWithAttributes:attributes];
  [@"Incognito" drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2, (NSHeight(self.bounds) - size.height) / 2) withAttributes:attributes];
}
@end
