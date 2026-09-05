#import "TLBrowserHeightTransition.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface TLBrowserHeightTransition ()
@property (nonatomic, weak) NSView *contentView;
@property (nonatomic, strong) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong) NSTimer *browserHeightTimer;
@property (nonatomic) CGFloat browserHeightTarget;
@end

@implementation TLBrowserHeightTransition
- (instancetype)initWithContentView:(NSView *)contentView bottomConstraint:(NSLayoutConstraint *)constraint {
  self = [super init];
  if (self) {
    _contentView = contentView;
    _browserHostBottomConstraint = constraint;
  }
  return self;
}
- (void)dealloc { [_browserHeightTimer invalidate]; }
- (void)cancel {
  [self.browserHeightTimer invalidate];
  self.browserHeightTimer = nil;
}
- (void)applyBrowserBottomInset:(CGFloat)inset {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.browserHostBottomConstraint.constant = inset;
  [self.contentView layoutSubtreeIfNeeded];
  [CATransaction commit];
}

- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot {
  if (self.browserHeightTimer && self.browserHeightTarget == inset && duration > 0) { return; }
  [self.browserHeightTimer invalidate];
  self.browserHeightTimer = nil;
  self.browserHeightTarget = inset;
  CGFloat start = self.browserHostBottomConstraint.constant;
  if (duration <= 0 || fabs(start - inset) < 0.5) {
    [self applyBrowserBottomInset:inset];
    return;
  }
  NSTimeInterval startedAt = NSProcessInfo.processInfo.systemUptime;
  __weak typeof(self) weakSelf = self;
  self.browserHeightTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *timer) {
    TLBrowserHeightTransition *runtime = weakSelf;
    if (!runtime) { [timer invalidate]; return; }
    CGFloat progress = MIN(1.0, (NSProcessInfo.processInfo.systemUptime - startedAt) / duration);
    CGFloat from = start;
    CGFloat to = inset;
    CGFloat phase = progress;
    // A single timeline drives real Chromium geometry, including the short settling phase.
    if (overshoot > 0) {
      CGFloat peak = inset + (inset - start) * overshoot;
      if (progress < 0.75) { to = peak; phase = progress / 0.75; }
      else { from = peak; phase = (progress - 0.75) / 0.25; }
    }
    CGFloat eased = phase * phase * (3.0 - 2.0 * phase);
    [runtime applyBrowserBottomInset:from + (to - from) * eased];
    if (progress >= 1.0) {
      [timer invalidate];
      runtime.browserHeightTimer = nil;
      [runtime applyBrowserBottomInset:inset];
    }
  }];
  [NSRunLoop.mainRunLoop addTimer:self.browserHeightTimer forMode:NSRunLoopCommonModes];
}


@end
