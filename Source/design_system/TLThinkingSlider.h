#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *TLThinkingLevelTitle(NSString *level);
FOUNDATION_EXPORT NSArray<NSString *> *TLThinkingSliderLevels(NSArray<NSString *> *levels, NSString *selected);
@interface TLThinkingSlider : NSSlider
@property (nonatomic, strong) TLThemePalette *palette;
@end
NS_ASSUME_NONNULL_END
