#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSTimeInterval (^TLTransitionClock)(void);
typedef void (^TLTransitionUpdate)(CGFloat progress);
typedef void (^TLTransitionCompletion)(BOOL finished);

// One clock owns all tracks and cancellation. Renderers receive eased progress
// and update geometry/opacity together, without scheduling their own cleanup.
// Use on the main thread. Reentrant replacements win over older requests;
// completion reports cancellation once, and never later reports success.
@interface TLTransitionCoordinator : NSObject
@property (nonatomic, readonly) BOOL hasTransitions;
- (instancetype)initWithClock:(TLTransitionClock)clock automaticallyAdvances:(BOOL)automaticallyAdvances;
- (void)startTransitionForKey:(NSString *)key
                    duration:(NSTimeInterval)duration
                      update:(TLTransitionUpdate)update
                  completion:(nullable TLTransitionCompletion)completion;
- (BOOL)hasTransitionForKey:(NSString *)key;
- (void)cancelTransitionForKey:(NSString *)key;
// Bulk operations apply to the tracks present when called. New transitions
// started by callbacks remain independent of the bulk operation.
- (void)finishAllTransitions;
- (void)cancelAllTransitions;
// Explicit ticks let tests verify exact progress without a window or real sleeps.
- (void)advance;
@end

NS_ASSUME_NONNULL_END
