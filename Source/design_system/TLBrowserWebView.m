#import "TLBrowserWebView.h"
@implementation TLBrowserWebView
- (void)autofillPassword:(id)sender { if (self.passwordAutofillHandler) self.passwordAutofillHandler(); }
- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  if (item.action == @selector(autofillPassword:)) return self.passwordAutofillAvailable && self.passwordAutofillAvailable();
  // WKWebView validates its editing commands through NSUserInterfaceValidations.
  return [super validateUserInterfaceItem:item];
}
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  [super willOpenMenu:menu withEvent:event];
  if (self.contextMenuHandler) self.contextMenuHandler(menu, event);
}
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  if (self.contextMenuClosedHandler) self.contextMenuClosedHandler();
  [super didCloseMenu:menu withEvent:event];
}
@end
