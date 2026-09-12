#import "TLThinkingBubbleView.h"
#import <QuartzCore/QuartzCore.h>

@interface TLThinkingBubbleView ()
@property (nonatomic, copy) NSArray<CALayer *> *dots;
@end

@implementation TLThinkingBubbleView
- (instancetype)init {
  if ((self = [super init])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityImageRole;
    self.accessibilityLabel = @"Agent is thinking";
    NSMutableArray *dots = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
      CALayer *dot = [CALayer layer];
      [dots addObject:dot];
      [self.layer addSublayer:dot];
    }
    self.dots = dots;
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  }
  return self;
}
- (instancetype)initWithFrame:(NSRect)frame {
  self = [self init];
  if (self) self.frame = frame;
  return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(self.palette.space3 * 3 + self.palette.space2 * 2 + self.palette.space9 * 2, self.palette.space9 * 2 + self.palette.userMessageTailHeight); }
- (void)setPalette:(TLThemePalette *)palette {
  [super setPalette:palette];
  self.fillColor = palette.secondaryActionSurface;
  self.borderColor = palette.transparentSurface;
  self.borderEdges = TLBorderEdgeNone;
  self.cornerRadius = palette.userMessageCornerRadius;
  self.drawsOutgoingTail = NO;
  for (CALayer *dot in self.dots) dot.backgroundColor = palette.thinkingText.CGColor;
  [self invalidateIntrinsicContentSize];
  self.needsLayout = YES;
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  [self.palette.secondaryActionSurface setFill];
  [TLCreateIncomingMessageBubblePath(self.bounds, self.palette) fill];
}
- (void)layout {
  [super layout];
  CGFloat diameter = self.palette.space3;
  CGFloat gap = self.palette.space2;
  CGFloat start = (NSWidth(self.bounds) - diameter * 3 - gap * 2) / 2;
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  [self.dots enumerateObjectsUsingBlock:^(CALayer *dot, NSUInteger i, BOOL *stop) {
    dot.frame = CGRectMake(start + i * (diameter + gap), (NSHeight(self.bounds) + self.palette.userMessageTailHeight - diameter) / 2, diameter, diameter);
    dot.cornerRadius = diameter / 2;
  }];
  [CATransaction commit];
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self.dots enumerateObjectsUsingBlock:^(CALayer *dot, NSUInteger i, BOOL *stop) {
    [dot removeAllAnimations];
    if (!self.window || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    pulse.values = @[@0.35, @1, @0.35];
    pulse.duration = 1.2;
    pulse.beginTime = CACurrentMediaTime() + i * 0.2;
    pulse.repeatCount = HUGE_VALF;
    [dot addAnimation:pulse forKey:@"thinking"];
  }];
}
@end
