#import <WebKit/WebKit.h>
#import "../MarkdownRenderer.h"
NS_ASSUME_NONNULL_BEGIN
@interface TLMarkdownContentWebView : WKWebView
@property (nonatomic, copy, nullable) TLMarkdownLinkContextMenuHandler linkContextMenuHandler;
@end
NS_ASSUME_NONNULL_END
