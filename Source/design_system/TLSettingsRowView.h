#import "UIComponents.h"
NS_ASSUME_NONNULL_BEGIN
/// A settings row with description and controls in two columns, stacked at narrow widths.
@interface TLSettingsRowView : TLTokenView
- (instancetype)initWithSummary:(NSView *)summary controls:(NSView *)controls palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
