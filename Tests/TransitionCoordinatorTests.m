#import <Foundation/Foundation.h>
#import "design_system/TLTransitionCoordinator.h"
#include <math.h>

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL %@", message); exit(1); }
}
static void TestBasicLifecycle(void) {
    __block NSTimeInterval now = 10;
    TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
      initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
    __block CGFloat progress = -1;
    __block NSUInteger finished = 0, cancelled = 0;
    TLTransitionCompletion completion = ^(BOOL success) { if (success) finished++; else cancelled++; };
    [timeline startTransitionForKey:@"tab" duration:2 update:^(CGFloat p) { progress = p; } completion:completion];
    Check(progress == 0, @"initial state is applied synchronously");
    now = 11; [timeline advance];
    Check(fabs(progress - 0.5) < 0.0001, @"one shared clock gives exact halfway progress");
    [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat p) { progress = p; } completion:completion];
    Check(cancelled == 1 && finished == 0, @"replacement cancels the old completion exactly once");
    now = 12; [timeline advance]; [timeline advance];
    Check(finished == 1 && cancelled == 1 && progress == 1, @"replacement finishes once");
    Check(!timeline.hasTransitions, @"finished tracks are released");
    [timeline startTransitionForKey:@"instant" duration:0 update:^(CGFloat p) { progress = p; } completion:completion];
    Check(progress == 1 && finished == 2 && !timeline.hasTransitions, @"Reduce Motion applies final state synchronously");
    [timeline startTransitionForKey:@"cancel" duration:10 update:^(CGFloat p) {} completion:completion];
    [timeline cancelAllTransitions]; now = 100; [timeline advance];
    Check(cancelled == 2 && finished == 2, @"cancelled tracks cannot finish later");
    [timeline startTransitionForKey:@"finish" duration:10 update:^(CGFloat p) { progress = p; } completion:completion];
    [timeline finishAllTransitions];
    Check(progress == 1 && finished == 3 && !timeline.hasTransitions, @"finish flushes final geometry and cleanup");
}

static void TestSharedClock(void) {
  __block NSTimeInterval now = 0;
  __block NSUInteger clockReads = 0;
  __block BOOL mutateClockDuringUpdate = NO;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { clockReads++; return now; } automaticallyAdvances:NO];
  NSMutableDictionary<NSString *, NSNumber *> *progress = [NSMutableDictionary dictionary];
  for (NSString *key in @[@"background", @"mask", @"neighbor"]) {
    if ([key isEqualToString:@"neighbor"]) now = 0.5;
    NSTimeInterval duration = [key isEqualToString:@"mask"] ? 4.0 : 2.0;
    [timeline startTransitionForKey:key duration:duration update:^(CGFloat p) {
      progress[key] = @(p);
      if (mutateClockDuringUpdate) now = 100;
    } completion:nil];
  }
  now = 1;
  mutateClockDuringUpdate = YES;
  NSUInteger previousClockReads = clockReads;
  [timeline advance];
  Check(clockReads == previousClockReads + 1, @"one tick samples its clock once for every track");
  Check(fabs(progress[@"background"].doubleValue - 0.5) < 0.0001, @"background uses the tick's shared time");
  Check(fabs(progress[@"mask"].doubleValue - 0.15625) < 0.0001, @"different duration uses the same sampled time");
  Check(fabs(progress[@"neighbor"].doubleValue - 0.15625) < 0.0001, @"staggered track retains its own start on the shared clock");
  [timeline cancelAllTransitions];
}

static void TestBoundaries(void) {
  __block NSTimeInterval now = 10;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  for (NSNumber *duration in @[@0, @(-1), @(NAN), @(INFINITY)]) {
    __block NSUInteger updates = 0, finishes = 0;
    [timeline startTransitionForKey:@"instant" duration:duration.doubleValue update:^(CGFloat p) {
      updates++;
      Check(p == 1, @"nonpositive or nonfinite duration applies final state");
    } completion:^(BOOL finished) { Check(finished, @"instant transition succeeds"); finishes++; }];
    Check(updates == 1 && finishes == 1 && !timeline.hasTransitions, @"instant transition cleans up synchronously once");
  }
  __block CGFloat progress = -1;
  __block NSUInteger finishes = 0;
  [timeline startTransitionForKey:@"bounded" duration:2 update:^(CGFloat p) { progress = p; }
    completion:^(BOOL finished) { if (finished) finishes++; }];
  now = 9; [timeline advance];
  Check(progress == 0 && finishes == 0, @"time before start clamps to initial geometry");
  now = 10.5; [timeline advance];
  Check(fabs(progress - 0.15625) < 0.0001, @"quarter progress uses smooth easing");
  now = 50; [timeline advance]; [timeline advance];
  Check(progress == 1 && finishes == 1 && !timeline.hasTransitions, @"late tick clamps to final state and finishes once");
}

static void TestReplacementDuringInitialUpdate(void) {
  for (NSNumber *duration in @[@0, @2]) {
    __block NSTimeInterval now = 0;
    TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
      initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
    __block NSUInteger oldFinished = 0, oldCancelled = 0, replacementFinished = 0;
    __block CGFloat replacementProgress = -1;
    [timeline startTransitionForKey:@"tab" duration:duration.doubleValue update:^(CGFloat p) {
      [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat next) { replacementProgress = next; }
        completion:^(BOOL finished) { if (finished) replacementFinished++; }];
    } completion:^(BOOL finished) { if (finished) oldFinished++; else oldCancelled++; }];
    Check(oldCancelled == 1 && oldFinished == 0 && replacementProgress == 0,
      @"initial update replacement cancels original without stale success, including zero duration");
    now = 1; [timeline advance]; [timeline advance];
    Check(replacementFinished == 1 && oldFinished == 0 && !timeline.hasTransitions,
      @"replacement survives initial callback and completes once");
  }
}

static void TestReplacementDuringFinalUpdate(void) {
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  __block NSUInteger oldFinished = 0, oldCancelled = 0, replacementFinished = 0;
  __block CGFloat replacementProgress = -1;
  [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat p) {
    if (p == 1) {
      [timeline startTransitionForKey:@"tab" duration:2 update:^(CGFloat next) { replacementProgress = next; }
        completion:^(BOOL finished) { if (finished) replacementFinished++; }];
    }
  } completion:^(BOOL finished) { if (finished) oldFinished++; else oldCancelled++; }];
  now = 1; [timeline advance];
  Check(oldCancelled == 1 && oldFinished == 0 && replacementProgress == 0 && timeline.hasTransitions,
    @"replacing inside final update does not finish original or tick replacement with stale time");
  now = 3; [timeline advance];
  Check(replacementFinished == 1 && oldFinished == 0 && !timeline.hasTransitions, @"replacement completes independently");
}

static void TestReentrantCancellationCompletion(void) {
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  __block NSUInteger originalCancelled = 0, supersededCancelled = 0, supersededUpdates = 0, newestFinished = 0;
  [timeline startTransitionForKey:@"tab" duration:10 update:^(CGFloat p) {} completion:^(BOOL finished) {
    Check(!finished, @"original transition is cancelled");
    originalCancelled++;
    [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat p) {}
      completion:^(BOOL newestSuccess) { if (newestSuccess) newestFinished++; }];
  }];
  [timeline startTransitionForKey:@"tab" duration:5 update:^(CGFloat p) { supersededUpdates++; }
    completion:^(BOOL finished) { Check(!finished, @"newer callback start supersedes outer request"); supersededCancelled++; }];
  Check(originalCancelled == 1 && supersededCancelled == 1 && supersededUpdates == 0,
    @"latest start from cancellation callback wins and superseded request cannot update");
  now = 1; [timeline advance];
  Check(newestFinished == 1 && !timeline.hasTransitions, @"newest transition is not silently overwritten");
}

static void TestReentrantSuccessCompletion(void) {
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  __block NSUInteger originalFinished = 0, nextFinished = 0;
  [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat p) {} completion:^(BOOL finished) {
    Check(finished, @"first chained transition finishes"); originalFinished++;
    [timeline startTransitionForKey:@"tab" duration:1 update:^(CGFloat p) {}
      completion:^(BOOL nextSuccess) { if (nextSuccess) nextFinished++; }];
  }];
  now = 1; [timeline advance];
  Check(originalFinished == 1 && nextFinished == 0 && timeline.hasTransitions, @"completion may start a new transition under the same key");
  now = 2; [timeline advance]; [timeline advance];
  Check(originalFinished == 1 && nextFinished == 1 && !timeline.hasTransitions, @"completion-created transition receives exactly one completion");
}

static void TestBulkOperationsPreserveNewTracks(void) {
  for (NSNumber *finish in @[@NO, @YES]) {
    TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
      initWithClock:^NSTimeInterval { return 0; } automaticallyAdvances:NO];
    __block BOOL replaced = NO;
    __block NSUInteger originalFinished = 0, originalCancelled = 0, newFinished = 0, newCancelled = 0;
    for (NSString *key in @[@"a", @"b"]) {
      [timeline startTransitionForKey:key duration:1 update:^(CGFloat p) {} completion:^(BOOL finished) {
        if (finished) originalFinished++; else originalCancelled++;
        if (!replaced) {
          replaced = YES;
          for (NSString *newKey in @[@"a", @"b"]) {
            [timeline startTransitionForKey:newKey duration:1 update:^(CGFloat p) {} completion:^(BOOL success) {
              if (success) newFinished++; else newCancelled++;
            }];
          }
        }
      }];
    }
    if (finish.boolValue) [timeline finishAllTransitions]; else [timeline cancelAllTransitions];
    Check(originalFinished == (finish.boolValue ? 1 : 0) && originalCancelled == (finish.boolValue ? 1 : 2),
      @"bulk operation terminates original tracks once, respecting callback replacement");
    Check([timeline hasTransitionForKey:@"a"] && [timeline hasTransitionForKey:@"b"] && newCancelled == 0 && newFinished == 0,
      @"bulk snapshot does not cancel or finish new tracks created by completion callbacks");
    [timeline finishAllTransitions];
    Check(newFinished == 2 && !timeline.hasTransitions, @"new tracks finish in a later operation");
  }
}

static void TestReentrantTicksAndFinish(void) {
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc]
    initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  __block BOOL requestFinish = NO;
  __block NSUInteger updates = 0, finishes = 0;
  [timeline startTransitionForKey:@"tab" duration:2 update:^(CGFloat p) {
    updates++;
    if (requestFinish) {
      [timeline advance];
      [timeline finishAllTransitions];
    }
  } completion:^(BOOL finished) { if (finished) finishes++; }];
  requestFinish = YES;
  now = 1; [timeline advance];
  Check(updates == 3 && finishes == 1 && !timeline.hasTransitions,
    @"nested ticks and finish defer final update without recursion or repeated completion");
}

static void TestTimerDoesNotRetainOwner(void) {
  __weak TLTransitionCoordinator *weakTimeline;
  __weak NSObject *weakPayload;
  @autoreleasepool {
    TLTransitionCoordinator *timeline = [[TLTransitionCoordinator alloc] init];
    NSObject *payload = [[NSObject alloc] init];
    weakTimeline = timeline;
    weakPayload = payload;
    [timeline startTransitionForKey:@"tab" duration:100 update:^(CGFloat p) { (void)[payload description]; } completion:nil];
    Check(weakTimeline != nil && weakPayload != nil, @"active track retains its update data");
  }
  Check(weakTimeline == nil && weakPayload == nil, @"automatic timer does not retain coordinator or its completed lifetime's tracks");
}

int main(void) {
  @autoreleasepool {
    TestBasicLifecycle();
    TestSharedClock();
    TestBoundaries();
    TestReplacementDuringInitialUpdate();
    TestReplacementDuringFinalUpdate();
    TestReentrantCancellationCompletion();
    TestReentrantSuccessCompletion();
    TestBulkOperationsPreserveNewTracks();
    TestReentrantTicksAndFinish();
    TestTimerDoesNotRetainOwner();
    NSLog(@"TransitionCoordinatorTests passed");
  }
  return 0;
}
