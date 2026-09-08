#import "UIComponents.h"
#import "TLBrowserDownloadManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLDownloadRowView : TLTokenView
@property (nonatomic, copy, nullable) void (^actionHandler)(NSString *action);
- (void)configureWithDownload:(TLBrowserDownload *)download palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
