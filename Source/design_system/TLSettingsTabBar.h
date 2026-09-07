#import "TLThemedButton.h"

NS_ASSUME_NONNULL_BEGIN
/// Native, keyboard-accessible tabs that scroll when their labels do not fit.
@interface TLSettingsTabBar : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy, readonly) NSArray<TLThemedButton *> *tabButtons;
@end
NS_ASSUME_NONNULL_END
