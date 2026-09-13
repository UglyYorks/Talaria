#import "TLFeatureTabController.h"
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^TLNotesReply)(NSDictionary *_Nullable result, NSError *_Nullable error);
typedef void (^TLNotesRequest)(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply);

@interface TLNotesTabController : TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette agents:(NSArray<TLAgentRecord *> *)agents
                        agentID:(NSInteger)agentID request:(TLNotesRequest)request;
- (void)refresh:(nullable id)sender;
- (void)updateAgents:(NSArray<TLAgentRecord *> *)agents preferredAgentID:(NSInteger)agentID;
- (BOOL)prepareToClose;
@end
NS_ASSUME_NONNULL_END
