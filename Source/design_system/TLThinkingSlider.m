#import "TLThinkingSlider.h"

NSString *TLThinkingLevelTitle(NSString *level) {
  if ([level isEqual:@"none"]) return @"Off";
  if ([level isEqual:@"xhigh"]) return @"Extra high";
  return level.capitalizedString;
}

NSArray<NSString *> *TLThinkingSliderLevels(NSArray<NSString *> *levels, NSString *selected) {
  if (levels.count <= 5) return levels;
  // Retain the endpoints and the current selection, then spread remaining stops
  // across the supported range. These are real values, never interpolated efforts.
  NSMutableIndexSet *indices = [NSMutableIndexSet indexSetWithIndex:0];
  [indices addIndex:levels.count - 1];
  NSUInteger current = [levels indexOfObject:selected];
  if (current != NSNotFound) [indices addIndex:current];
  for (NSString *common in @[@"medium", @"high", @"low"]) {
    NSUInteger index = [levels indexOfObject:common];
    if (index != NSNotFound && indices.count < 5) [indices addIndex:index];
  }
  while (indices.count < 5) {
    NSUInteger candidate = 0, largestDistance = 0;
    for (NSUInteger i = 1; i + 1 < levels.count; i++) {
      if ([indices containsIndex:i]) continue;
      NSUInteger left = [indices indexLessThanIndex:i], right = [indices indexGreaterThanIndex:i];
      NSUInteger distance = MIN(i - left, right - i);
      if (distance > largestDistance) { candidate = i; largestDistance = distance; }
    }
    [indices addIndex:candidate];
  }
  return [levels objectsAtIndexes:indices];
}

@interface TLThinkingSliderCell : NSSliderCell
@end
@implementation TLThinkingSliderCell
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
  TLThinkingSlider *slider = (TLThinkingSlider *)view;
  TLThemePalette *p = slider.palette;
  NSRect knob = [self knobRectFlipped:view.isFlipped];
  CGFloat inset = NSWidth(knob) / 2;
  CGFloat start = NSMinX(frame) + inset, end = NSMaxX(frame) - inset;
  CGFloat y = NSMidY(knob);
  CGFloat thickness = p.space2;
  [NSGraphicsContext saveGraphicsState];
  if (!slider.enabled) CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, p.disabledOpacity);
  [p.controlBorder setFill];
  [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(start, y - thickness / 2, end - start, thickness)
    xRadius:thickness / 2 yRadius:thickness / 2] fill];
  [p.primaryActionSurface setFill];
  [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(start, y - thickness / 2, MAX(0, NSMidX(knob) - start), thickness)
    xRadius:thickness / 2 yRadius:thickness / 2] fill];
  for (NSInteger i = 0; i < self.numberOfTickMarks; i++) {
    CGFloat x = self.numberOfTickMarks > 1 ? start + (end - start) * i / (self.numberOfTickMarks - 1) : start;
    [p.textMuted setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - thickness / 2, y - thickness / 2, thickness, thickness)] fill];
  }
  CGFloat diameter = p.space8;
  NSRect circle = NSMakeRect(NSMidX(knob) - diameter / 2, y - diameter / 2, diameter, diameter);
  [p.primaryActionSurface setFill];
  [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
  if (slider.enabled && slider.window.firstResponder == slider) {
    [p.controlFocus setStroke];
    NSBezierPath *focus = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle, -p.focusRingSize, -p.focusRingSize)];
    focus.lineWidth = p.focusRingSize;
    [focus stroke];
  }
  [NSGraphicsContext restoreGraphicsState];
}
@end

@implementation TLThinkingSlider
+ (Class)cellClass { return TLThinkingSliderCell.class; }
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.sliderType = NSSliderTypeLinear;
    self.allowsTickMarkValuesOnly = YES;
    self.continuous = YES;
    self.focusRingType = NSFocusRingTypeNone;
    self.accessibilityLabel = @"Thinking level";
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; self.needsDisplay = YES; }
- (BOOL)becomeFirstResponder { BOOL result = [super becomeFirstResponder]; self.needsDisplay = YES; return result; }
- (BOOL)resignFirstResponder { BOOL result = [super resignFirstResponder]; self.needsDisplay = YES; return result; }
@end
