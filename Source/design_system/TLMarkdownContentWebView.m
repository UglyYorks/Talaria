#import "TLMarkdownContentWebView.h"
@interface TLMarkdownContentWebView ()
@property NSDictionary *linkContext;
@property NSTimeInterval linkContextTime;
@property (copy) dispatch_block_t closeLinkMenu;
@end
@interface TLMarkdownContextHandler : NSObject <WKScriptMessageHandler>
@property (weak) TLMarkdownContentWebView *view;
@end
@implementation TLMarkdownContextHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  if (message.webView != self.view || !message.frameInfo.isMainFrame || !message.webView.URL.isFileURL ||
      ![message.body isKindOfClass:NSDictionary.class]) return;
  self.view.linkContext = message.body;
  self.view.linkContextTime = NSProcessInfo.processInfo.systemUptime;
}
@end
@implementation TLMarkdownContentWebView
- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration {
  // WKWebView has no public macOS API to create an Inspect Element action.
  // Enable WebKit's own action and keep its original menu target/selection.
  @try { [configuration.preferences setValue:@YES forKey:@"developerExtrasEnabled"]; }
  @catch (NSException *exception) { }
  TLMarkdownContextHandler *handler = [TLMarkdownContextHandler new];
  [configuration.userContentController addScriptMessageHandler:handler name:@"talariaLinkContext"];
  NSString *script = @"document.addEventListener('contextmenu', e => {"
    "if (!e.isTrusted) return;"
    "const a = e.target.closest ? e.target.closest('a[href]') : null;"
    "window.webkit.messageHandlers.talariaLinkContext.postMessage({url:a ? a.href : '', x:e.clientX, y:e.clientY});"
    "}, true);";
  [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script
    injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
  self = [super initWithFrame:frame configuration:configuration];
  if (self) handler.view = self;
  return self;
}
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  [super willOpenMenu:menu withEvent:event];
  NSDictionary *context = self.linkContext;
  self.linkContext = nil;
  NSMenu *fallbackMenu = self.fallbackContextMenu;
  self.fallbackContextMenu = nil;
  NSString *value = context[@"url"];
  NSURL *URL = [value isKindOfClass:NSString.class] && value.length ? [NSURL URLWithString:value] : nil;
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  CGFloat topY = self.isFlipped ? point.y : NSHeight(self.bounds) - point.y;
  BOOL clickedLink = self.linkContextMenuHandler && URL && NSProcessInfo.processInfo.systemUptime - self.linkContextTime <= 1 &&
    fabs(point.x - [context[@"x"] doubleValue]) <= 4 && fabs(topY - [context[@"y"] doubleValue]) <= 4;
  if (!clickedLink) {
    if (fallbackMenu) {
      [menu removeAllItems];
      menu.title = fallbackMenu.title;
      menu.autoenablesItems = fallbackMenu.autoenablesItems;
      for (NSMenuItem *item in fallbackMenu.itemArray) {
        [fallbackMenu removeItem:item];
        [menu addItem:item];
      }
      return;
    }
    // Keep the pre-existing selected-text/background menu. The extra developer
    // action above is exposed only through the shared link menu.
    for (NSMenuItem *item in menu.itemArray) {
      if ([item.identifier containsString:@"InspectElement"] || [item.title isEqual:@"Inspect Element"]) [menu removeItem:item];
    }
    if (menu.itemArray.lastObject.separatorItem) [menu removeItem:menu.itemArray.lastObject];
    return;
  }
  self.closeLinkMenu = self.linkContextMenuHandler(URL, menu, self, point);
}
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  if (self.closeLinkMenu) self.closeLinkMenu();
  self.closeLinkMenu = nil;
  [super didCloseMenu:menu withEvent:event];
}
- (void)scrollWheel:(NSEvent *)event {
  if (fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)) {
    for (NSView *parent = self.superview; parent; parent = parent.superview) {
      if ([parent isKindOfClass:NSScrollView.class]) { [parent scrollWheel:event]; return; }
    }
  }
  [super scrollWheel:event];
}
@end
