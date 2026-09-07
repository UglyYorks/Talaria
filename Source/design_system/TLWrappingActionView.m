#import "TLWrappingActionView.h"
@implementation TLWrappingActionView
- (instancetype)initWithViews:(NSArray<NSView *> *)views palette:(TLThemePalette *)palette {
  self = [super initWithFrame:NSZeroRect];
  if (!self) return nil;
  _palette = palette;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  for (NSView *view in views) { view.translatesAutoresizingMaskIntoConstraints = YES; [self addSubview:view]; }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (CGFloat)arrange:(BOOL)apply {
  CGFloat width = MAX(1, NSWidth(self.bounds)), x = 0, y = 0, rowHeight = self.palette.settingsActionHeight;
  for (NSView *view in self.subviews) {
    CGFloat itemWidth = MIN(width, MAX(0, view.intrinsicContentSize.width));
    if (x > 0 && x + itemWidth > width) { x = 0; y += rowHeight + self.palette.space5; }
    if (apply) view.frame = NSMakeRect(x, y, itemWidth, rowHeight);
    x += itemWidth + self.palette.space5;
  }
  return y + rowHeight;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, [self arrange:NO]); }
- (void)setFrameSize:(NSSize)size {
  BOOL changed = size.width != NSWidth(self.frame);
  [super setFrameSize:size];
  if (changed) { [self invalidateIntrinsicContentSize]; self.needsLayout = YES; }
}
- (void)layout { [super layout]; [self arrange:YES]; }
@end
