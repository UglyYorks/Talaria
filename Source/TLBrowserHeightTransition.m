#import "TLBrowserHeightTransition.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface TLBrowserHeightTransition ()
@property (nonatomic, weak) NSView *contentView;
@property (nonatomic, weak) NSView *browserHostView;
@property (nonatomic, strong) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong) NSTimer *browserHeightTimer;
@property (nonatomic) CGFloat startInset, targetInset;
@property (nonatomic) CFTimeInterval started, duration;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, copy) dispatch_block_t completion;
@end

@implementation TLBrowserHeightTransition
- (instancetype)initWithContentView:(NSView *)contentView bottomConstraint:(NSLayoutConstraint *)constraint {
  if ((self = [super init])) {
    _contentView = contentView;
    _browserHostBottomConstraint = constraint;
    _browserHostView = constraint.firstItem;
    _browserHostView.wantsLayer = YES;
  }
  return self;
}
- (void)dealloc { [self cancel]; }
- (BOOL)isAnimating { return self.browserHeightTimer != nil; }
- (void)cancel {
  self.generation++;
  [self.browserHeightTimer invalidate]; self.browserHeightTimer = nil;
  self.completion = nil;
}
- (void)applyBrowserBottomInset:(CGFloat)inset {
  // Commit actual view geometry. Implicit layer animations would scale the
  // old WebKit surface while the renderer lays out its new viewport.
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  self.browserHostBottomConstraint.constant = inset;
  [self.contentView layoutSubtreeIfNeeded];
  if (self.insetChanged) self.insetChanged(inset);
  [CATransaction commit];
}
- (void)advance {
  NSUInteger generation = self.generation;
  double progress = MIN(1, MAX(0, (CACurrentMediaTime()-self.started)/self.duration));
  // Monotonic easing: overshooting a viewport would cause an extra reflow and
  // reverse the motion of fixed-position content near the end of the animation.
  double eased = progress*progress*(3-2*progress);
  CGFloat inset = self.startInset+(self.targetInset-self.startInset)*eased;
  // Keep intermediate native viewport steps aligned to whole points; apply
  // the exact requested inset when the transition finishes.
  inset = progress == 1 ? self.targetInset : round(inset);
  if (inset != self.browserHostBottomConstraint.constant) [self applyBrowserBottomInset:inset];
  if (generation != self.generation) return;
  if (progress == 1) {
    dispatch_block_t completion = self.completion;
    [self cancel];
    if (completion) completion();
  }
}
- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot {
  [self setBrowserBottomInset:inset duration:duration overshoot:overshoot completion:nil];
}
- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot completion:(dispatch_block_t)completion {
  if (!isfinite(inset)) return;
  if (!completion && self.isAnimating && self.targetInset == inset && duration > 0) return;
  // Reversals start from the last committed viewport, never stale presentation
  // layers. Every tick uses an absolute inset, including during window resizing.
  [self cancel];
  NSUInteger generation = self.generation;
  CGFloat start = self.browserHostBottomConstraint.constant;
  if (!isfinite(duration) || duration <= 0 || fabs(start-inset)<0.5 || NSHeight(self.contentView.bounds)+inset<=0) {
    [self applyBrowserBottomInset:inset];
    if (generation == self.generation && completion) completion();
    return;
  }
  self.startInset=start; self.targetInset=inset; self.started=CACurrentMediaTime(); self.duration=duration;
  self.completion=completion;
  __weak typeof(self) weakSelf=self;
  // Only the short transition runs a timer. Late frames advance directly to
  // elapsed time; they never queue a backlog of renderer resizes.
  self.browserHeightTimer=[NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) {
    TLBrowserHeightTransition *owner=weakSelf;
    if (owner.browserHeightTimer == timer) [owner advance];
  }];
  [NSRunLoop.mainRunLoop addTimer:self.browserHeightTimer forMode:NSRunLoopCommonModes];
}
@end
