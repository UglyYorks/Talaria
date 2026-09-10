#import "TLBrowserWebView.h"
@implementation TLBrowserWebView
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  [super willOpenMenu:menu withEvent:event];
  if (self.contextMenuHandler) self.contextMenuHandler(menu, event);
}
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  if (self.contextMenuClosedHandler) self.contextMenuClosedHandler();
  [super didCloseMenu:menu withEvent:event];
}
@end
