#import <AppKit/AppKit.h>
#import "TLQuestionRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLHostCommandOperation : NSObject
@property (atomic, readonly) BOOL cancelled;
- (void)cancel;
@end

// Permissions live on the Mac, outside the guest's mounted profile. No request
// or tool argument can grant access; only a native consent action can do so.
@interface TLHostCommandBridge : NSObject
+ (instancetype)sharedBridge;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (NSString *)policyForAgent:(NSString *)agentKey;
- (void)setPolicy:(NSString *)policy forAgent:(NSString *)agentKey;
- (BOOL)isAllowedForAgent:(NSString *)agentKey chat:(NSString *)chatID privateScope:(NSString *)privateScope;
- (void)allowChat:(NSString *)chatID agent:(NSString *)agentKey privateScope:(NSString *)privateScope;
- (void)clearPrivateScope:(NSString *)privateScope;
- (TLHostCommandOperation *)runRequest:(NSDictionary *)request agent:(NSString *)agentKey name:(NSString *)agentName
                                 chat:(NSString *)chatID privateScope:(NSString *)privateScope
                      presentQuestion:(nullable void (^)(TLQuestionRequest *question))presentQuestion
                           completion:(void (^)(NSDictionary *result))completion;
@end

// Bounded synchronous runner; the bridge calls this off the main thread.
NSDictionary *TLExecuteHostCommand(NSDictionary *request, TLHostCommandOperation *operation);
BOOL TLValidateHostCommand(NSDictionary *request);

NS_ASSUME_NONNULL_END
