#import "AgentModel.h"
#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLModelPickerView : TLTokenView

@property (nonatomic, copy) NSString *selectedModelID;

- (instancetype)initWithTitle:(NSString *)title palette:(TLThemePalette *)palette selectedModelID:(NSString *)selectedModelID;
- (void)setModels:(NSArray<TLAgentModel *> *)models;
- (void)setStatusText:(NSString *)statusText;
- (void)updatePalette:(TLThemePalette *)palette;

@end

NS_ASSUME_NONNULL_END
