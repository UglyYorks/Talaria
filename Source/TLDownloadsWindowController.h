#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLBrowserDownloadManager.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLDownloadsWindowController : NSWindowController
- (instancetype)initWithManager:(TLBrowserDownloadManager *)manager palette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
