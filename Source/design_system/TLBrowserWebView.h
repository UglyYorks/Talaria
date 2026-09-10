#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Native browser surface; the controller supplies page-specific menu actions.
@interface TLBrowserWebView : WKWebView
@property (nonatomic, copy, nullable) void (^contextMenuHandler)(NSMenu *, NSEvent *);
@property (nonatomic, copy, nullable) dispatch_block_t contextMenuClosedHandler;
@end
NS_ASSUME_NONNULL_END
