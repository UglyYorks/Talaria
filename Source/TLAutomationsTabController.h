#import "TLFeatureTabController.h"
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^TLAutomationReply)(NSDictionary *_Nullable result, NSError *_Nullable error);
typedef void (^TLAutomationRequest)(NSInteger agentID, NSDictionary *parameters, TLAutomationReply reply);

@interface TLAutomationsTabController : TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette
                         agents:(NSArray<TLAgentRecord *> *)agents
                        agentID:(NSInteger)agentID
                        request:(TLAutomationRequest)request;
- (void)refresh:(nullable id)sender;
@end
NS_ASSUME_NONNULL_END
