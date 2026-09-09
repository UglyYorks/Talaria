#import <WebKit/WebKit.h>
#import "../MarkdownRenderer.h"
NS_ASSUME_NONNULL_BEGIN
@interface TLMarkdownContentWebView : WKWebView
@property (nonatomic, copy, nullable) TLMarkdownLinkContextMenuHandler linkContextMenuHandler;
// Set before forwarding a contextual click to WebKit. Consumed by the next menu;
// links take priority, while ordinary content keeps its containing view's menu.
@property (nonatomic, strong, nullable) NSMenu *fallbackContextMenu;
@end
NS_ASSUME_NONNULL_END
