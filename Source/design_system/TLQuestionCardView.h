#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN
// Shared renderer for questions, command approvals and their options.
// request: title, description, optional literal command preview, options
// ({id, title, primary}), submitted and optional status. allows_text adds a
// typed answer; multi_select collects options until Send answer. choiceHandler
// receives an option ID, or the answer text when allows_text is enabled.
@interface TLQuestionCardView : TLTokenView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy, nullable) BOOL (^choiceHandler)(NSString *choice);
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
