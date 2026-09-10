#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN
// A durable notification's visible source inside an assistant message.
@interface TLNotificationMessageCardView : TLTokenView
- (instancetype)initWithNotification:(NSDictionary *)notification palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
