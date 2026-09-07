#import "TLFeatureTabController.h"
#import "TLApplicationPreferences.h"
NS_ASSUME_NONNULL_BEGIN
@interface TLApplicationSettingsController : TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette preferences:(TLApplicationPreferences *)preferences;
- (void)refresh;
- (void)cancelShortcutRecording;
@end
NS_ASSUME_NONNULL_END
