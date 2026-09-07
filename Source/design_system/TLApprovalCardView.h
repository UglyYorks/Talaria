#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN
NSArray<NSString *> *TLApprovalChoices(NSDictionary *request);
NSString *TLApprovalChoiceTitle(NSString *choice);

@interface TLApprovalCardView : TLTokenView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy, nullable) BOOL (^choiceHandler)(NSString *choice);
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
