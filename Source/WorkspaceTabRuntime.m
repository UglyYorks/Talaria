#import "WorkspaceTabRuntime.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface TLWorkspaceTabRuntime ()
@property (nonatomic, strong) NSTimer *browserHeightTimer;
@property (nonatomic) CGFloat browserHeightTarget;
@end

@implementation TLWorkspaceTabRuntime

- (void)dealloc { [self.browserHeightTimer invalidate]; }

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
    TLWorkspaceTabRuntime *runtime = weakSelf;
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

+ (instancetype)runtimeWithContentView:(NSView *)contentView
                            openAction:(SEL)openAction
                           closeAction:(SEL)closeAction {
  TLWorkspaceTabRuntime *runtime = [[self alloc] init];
  runtime.contentView = contentView;
  runtime.openAction = openAction;
  runtime.closeAction = closeAction;
  return runtime;
}

@end

NSString *TLWorkspaceTabRuntimeKey(TLWorkspaceTabKind kind, NSInteger tabID) {
  return [NSString stringWithFormat:@"%ld:%ld", (long)kind, (long)tabID];
}
