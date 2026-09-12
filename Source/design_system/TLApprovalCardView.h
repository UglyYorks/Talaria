#import "TLQuestionCardView.h"

NS_ASSUME_NONNULL_BEGIN
NSArray<NSString *> *TLApprovalChoices(NSDictionary *request);
NSString *TLApprovalChoiceTitle(NSString *choice);

@interface TLApprovalCardView : TLQuestionCardView
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
