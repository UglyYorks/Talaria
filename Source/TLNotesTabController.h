#import "TLFeatureTabController.h"
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^TLNotesReply)(NSDictionary *_Nullable result, NSError *_Nullable error);
typedef void (^TLNotesRequest)(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply);

@interface TLNotesTabController : TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette agentID:(NSInteger)agentID request:(TLNotesRequest)request;
- (void)refresh:(nullable id)sender;
- (BOOL)prepareToClose;
@end
NS_ASSUME_NONNULL_END
