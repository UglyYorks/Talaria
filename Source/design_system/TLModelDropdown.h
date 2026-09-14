#import "TLThemedButton.h"
#import "AgentModel.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLModelDropdown : TLThemedButton
@property (nonatomic, copy) NSArray<TLAgentModel *> *models;
@property (nonatomic, copy) NSString *selectedModelID;
@property (nonatomic, readonly, nullable) TLAgentModel *selectedModel;
@property (nonatomic, copy, nullable) void (^selectionHandler)(void);
@end
NS_ASSUME_NONNULL_END
