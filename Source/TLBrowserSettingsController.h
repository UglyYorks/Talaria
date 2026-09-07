#import "TLFeatureTabController.h"
#import "TLBrowserPreferences.h"
NS_ASSUME_NONNULL_BEGIN
@interface TLBrowserSettingsController : TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette preferences:(id<TLBrowserPreferencesService>)preferences;
@property (nonatomic) NSInteger selectedCategoryIndex;
- (void)prepareInWindow:(nullable NSWindow *)window;
@end
NS_ASSUME_NONNULL_END
