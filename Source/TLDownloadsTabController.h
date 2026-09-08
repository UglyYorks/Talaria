#import "TLFeatureTabController.h"
#import "TLBrowserDownloadManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLDownloadsTabController : TLFeatureTabController
- (instancetype)initWithManager:(TLBrowserDownloadManager *)manager palette:(TLThemePalette *)palette;
- (void)refresh;
@end
NS_ASSUME_NONNULL_END
