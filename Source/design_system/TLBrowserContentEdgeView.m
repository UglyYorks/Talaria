#import "TLBrowserContentEdgeView.h"
#import <QuartzCore/QuartzCore.h>

@interface TLBrowserContentEdgeView ()
@property (nonatomic, strong) CAShapeLayer *borderLine;
@property (nonatomic, strong) CAShapeLayer *loadingLine;
@property (nonatomic, strong) CAGradientLayer *loadingGradient;
@property (nonatomic) BOOL pageLoading;
@property (nonatomic) NSUInteger loadingAnimationGeneration;
@end

@implementation TLBrowserContentEdgeView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _borderLine = [CAShapeLayer layer];
    [self.layer addSublayer:_borderLine];
    _loadingLine = [CAShapeLayer layer];
    _loadingLine.hidden = YES;
    _loadingLine.strokeEnd = 0;
    _loadingGradient = [CAGradientLayer layer];
    _loadingGradient.startPoint = CGPointMake(0, 0.5);
    _loadingGradient.endPoint = CGPointMake(1, 0.5);
    _loadingGradient.mask = _loadingLine;
    [self.layer addSublayer:_loadingGradient];
    [self updateEdge];
  }
  return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self updateEdge]; }
- (void)layout { [super layout]; [self updateEdge]; }
- (void)updateEdge {
  if (!self.palette || NSIsEmptyRect(self.bounds)) return;
  CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
  CGFloat radius = MIN(self.palette.space5, MIN(width / 2, height));
  // Follow the same inverse cutout as TLBrowserFooterView, from left to right.
  CGMutablePathRef border = CGPathCreateMutable();
  CGPathMoveToPoint(border, NULL, 0, height);
  CGPathAddArc(border, NULL, radius, height, radius, M_PI, M_PI * 1.5, false);
  CGPathAddLineToPoint(border, NULL, width - radius, height - radius);
  CGPathAddArc(border, NULL, width - radius, height, radius, -M_PI_2, 0, false);
  CGFloat offset = (self.palette.borderWidth + self.palette.browserLoadingLineWidth) / 2;
  CGAffineTransform below = CGAffineTransformMakeTranslation(0, -offset);
  CGPathRef progress = CGPathCreateCopyByTransformingPath(border, &below);
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  self.borderLine.frame = self.bounds;
  self.borderLine.path = border;
  self.borderLine.fillColor = TLCGColor(self.palette.transparentSurface);
  self.borderLine.strokeColor = TLCGColor(self.palette.controlBorder);
  self.borderLine.lineWidth = self.palette.borderWidth;
  self.borderLine.opacity = self.palette.workspaceOutlineOpacity;
  self.loadingGradient.frame = self.bounds;
  self.loadingGradient.colors = @[(__bridge id)TLCGColor(self.palette.browserLoadingProgress),
                                 (__bridge id)TLCGColor(self.palette.browserLoadingProgressEnd)];
  self.loadingLine.frame = self.bounds;
  self.loadingLine.path = progress;
  self.loadingLine.fillColor = TLCGColor(self.palette.transparentSurface);
  self.loadingLine.strokeColor = TLCGColor(self.palette.browserLoadingProgress);
  self.loadingLine.lineWidth = self.palette.browserLoadingLineWidth;
  [CATransaction commit];
  CGPathRelease(progress);
  CGPathRelease(border);
}

- (void)setLoading:(BOOL)loading progress:(double)progress {
  CGFloat next = loading ? MIN(1, MAX(0, isfinite(progress) ? progress : 0)) : 1;
  BOOL wasLoading = self.pageLoading;
  CGFloat target = self.loadingLine.strokeEnd;
  if (wasLoading == loading && (!loading || target == next)) return;
  CGFloat previous = wasLoading && next >= target
    ? ((CAShapeLayer *)self.loadingLine.presentationLayer ?: self.loadingLine).strokeEnd : 0;
  self.pageLoading = loading;
  NSUInteger generation = ++self.loadingAnimationGeneration;
  BOOL animateProgress = next > previous && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  NSTimeInterval progressDuration = animateProgress ? self.palette.browserLoadingProgressDuration : 0;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self.loadingLine removeAllAnimations];
  self.loadingLine.hidden = NO;
  self.loadingLine.opacity = 1;
  self.loadingLine.strokeEnd = next;
  if (animateProgress) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = @(previous);
    animation.toValue = @(next);
    animation.duration = progressDuration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.loadingLine addAnimation:animation forKey:@"loadingProgress"];
  }
  if (!loading) {
    // Finish the stroke, hold the complete line, then fade. A new navigation
    // invalidates this completion so its line cannot be hidden by an old load.
    NSTimeInterval holdEnd = progressDuration + self.palette.browserLoadingCompletionHoldDuration;
    NSTimeInterval duration = holdEnd + self.palette.browserLoadingFadeDuration;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = @[@1, @1, @0];
    fade.keyTimes = @[@0, @(holdEnd / duration), @1];
    fade.duration = duration;
    self.loadingLine.opacity = 0;
    [self.loadingLine addAnimation:fade forKey:@"loadingCompletion"];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      TLBrowserContentEdgeView *input = weakSelf;
      if (!input || input.loadingAnimationGeneration != generation || input.pageLoading) return;
      [CATransaction begin]; [CATransaction setDisableActions:YES];
      input.loadingLine.hidden = YES;
      [input.loadingLine removeAllAnimations];
      [CATransaction commit];
    });
  }
  [CATransaction commit];
}

@end
