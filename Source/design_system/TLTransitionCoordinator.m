#import "TLTransitionCoordinator.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@interface TLTransitionTrack : NSObject
@property (nonatomic) NSTimeInterval start;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic, copy) TLTransitionUpdate update;
@property (nonatomic, copy) TLTransitionCompletion completion;
@property (nonatomic) BOOL updating;
@property (nonatomic) BOOL finishRequested;
@end
@implementation TLTransitionTrack
@end

@interface TLTransitionCoordinator ()
@property (nonatomic, copy) TLTransitionClock clock;
@property (nonatomic) BOOL automaticallyAdvances;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLTransitionTrack *> *tracks;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL advancing;
@end

@implementation TLTransitionCoordinator
- (instancetype)init {
  return [self initWithClock:^NSTimeInterval { return CACurrentMediaTime(); } automaticallyAdvances:YES];
}
- (instancetype)initWithClock:(TLTransitionClock)clock automaticallyAdvances:(BOOL)automaticallyAdvances {
  NSParameterAssert(clock);
  self = [super init];
  if (self) {
    _clock = [clock copy];
    _automaticallyAdvances = automaticallyAdvances;
    _tracks = [NSMutableDictionary dictionary];
  }
  return self;
}
- (void)dealloc { [_timer invalidate]; }
- (BOOL)hasTransitions { return self.tracks.count > 0; }
- (BOOL)hasTransitionForKey:(NSString *)key { return self.tracks[key] != nil; }
- (void)startTransitionForKey:(NSString *)key duration:(NSTimeInterval)duration
                      update:(TLTransitionUpdate)update completion:(TLTransitionCompletion)completion {
  NSParameterAssert(key);
  NSParameterAssert(update);
  TLTransitionTrack *previous = self.tracks[key];
  TLTransitionTrack *track = [[TLTransitionTrack alloc] init];
  track.start = self.clock();
  track.duration = isfinite(duration) && duration > 0.0 ? duration : 0.0;
  track.update = update;
  track.completion = completion;
  // Register first so a newer start inside the previous cancellation callback
  // replaces this request instead of being silently overwritten by it.
  self.tracks[key] = track;
  if (previous.completion) previous.completion(NO);
  BOOL instantaneous = track.duration == 0.0;
  [self updateTrack:track forKey:key progress:instantaneous ? 1.0 : 0.0 finished:instantaneous];
  if (self.automaticallyAdvances && !self.timer && self.hasTransitions) {
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 120.0 repeats:YES block:^(NSTimer *timer) {
      TLTransitionCoordinator *owner = weakSelf;
      if (owner) [owner advance]; else [timer invalidate];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
  }
  [self stopTimerIfIdle];
}
- (void)cancelTransitionForKey:(NSString *)key {
  TLTransitionTrack *track = self.tracks[key];
  if (!track) return;
  [self.tracks removeObjectForKey:key];
  if (track.completion) track.completion(NO);
  [self stopTimerIfIdle];
}
- (void)cancelAllTransitions {
  NSDictionary *tracks = self.tracks.copy;
  for (NSString *key in tracks) {
    if (self.tracks[key] == tracks[key]) [self cancelTransitionForKey:key];
  }
}
- (void)finishAllTransitions {
  NSDictionary *tracks = self.tracks.copy;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (NSString *key in tracks) {
    [self updateTrack:tracks[key] forKey:key progress:1.0 finished:YES];
  }
  [CATransaction commit];
  [self stopTimerIfIdle];
}
- (void)advance {
  if (self.advancing) return;
  self.advancing = YES;
  NSTimeInterval now = self.clock();
  NSDictionary *tracks = self.tracks.copy;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (NSString *key in tracks) {
    TLTransitionTrack *track = tracks[key];
    if (self.tracks[key] != track) continue;
    CGFloat progress = track.duration == 0.0 ? 1.0 : MIN(1.0, MAX(0.0, (now - track.start) / track.duration));
    CGFloat eased = progress * progress * (3.0 - 2.0 * progress);
    [self updateTrack:track forKey:key progress:eased finished:progress == 1.0];
  }
  [CATransaction commit];
  self.advancing = NO;
  [self stopTimerIfIdle];
}
- (void)updateTrack:(TLTransitionTrack *)track forKey:(NSString *)key progress:(CGFloat)progress finished:(BOOL)finished {
  if (self.tracks[key] != track) return;
  if (track.updating) {
    // A callback may request finishing or another tick. Defer a final update
    // until the current callback returns instead of recursively invoking it.
    track.finishRequested |= finished;
    return;
  }
  track.updating = YES;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  track.update(progress);
  [CATransaction commit];
  track.updating = NO;
  if (self.tracks[key] != track) return;
  if (track.finishRequested && !finished) {
    track.finishRequested = NO;
    [self updateTrack:track forKey:key progress:1.0 finished:YES];
    return;
  }
  if (finished) {
    [self.tracks removeObjectForKey:key];
    if (track.completion) track.completion(YES);
  }
}
- (void)stopTimerIfIdle {
  if (!self.hasTransitions) {
    [self.timer invalidate];
    self.timer = nil;
  }
}
@end
