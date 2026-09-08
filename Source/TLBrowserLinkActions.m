#import "TLBrowserLinkActions.h"
#import "TLBrowserImageActions.h"
#import "design_system/TLActionMenuItem.h"

static NSMenuItem *TLLinkAction(NSString *title, dispatch_block_t action) {
  return [TLActionMenuItem itemWithTitle:title action:^{ dispatch_async(dispatch_get_main_queue(), action); }];
}
static NSMenuItem *TLLinkSubmenu(NSString *title, NSMenu *submenu) {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]; item.submenu = submenu; return item;
}
BOOL TLBrowserLinkURLIsNavigable(NSURL *URL) {
  return URL.host.length && [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString];
}
@implementation TLBrowserLinkActions
+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard {
  [pasteboard declareTypes:@[NSPasteboardTypeString, NSPasteboardTypeURL] owner:nil];
  for (NSString *type in @[NSPasteboardTypeString, NSPasteboardTypeURL]) [pasteboard setString:URL.absoluteString forType:type];
}
+ (NSMenu *)menuForURL:(NSURL *)URL canSplit:(BOOL)canSplit view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open inspect:(dispatch_block_t)inspect imageMenu:(NSMenu *)imageMenu {
  NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
  BOOL navigable = TLBrowserLinkURLIsNavigable(URL);
  [menu addItem:TLLinkAction(@"Open Link in New Tab", ^{ open(URL, TLBrowserLinkNewTab); })];
  [menu addItem:TLLinkAction(@"Open Link in New Window", ^{ open(URL, TLBrowserLinkNewWindow); })];
  NSMenuItem *split = TLLinkAction(@"Open Link in Split View", ^{ open(URL, TLBrowserLinkSplitView); });
  [menu addItem:split];
  // Non-web links still support copying, sharing, Services and inspection.
  for (NSMenuItem *item in menu.itemArray) if (!item.separatorItem) item.enabled = navigable;
  split.enabled = navigable && canSplit;
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *copy = TLLinkAction(@"Copy Link", ^{
    [self copyURL:URL toPasteboard:NSPasteboard.generalPasteboard];
  }); copy.image = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:nil]; [menu addItem:copy];
  [menu addItem:NSMenuItem.separatorItem];
  if (imageMenu) {
    // Linked images expose both sets of actions directly. Keep the original
    // image targets, enabled states and command IDs, including its Share/Inspect.
    for (NSMenuItem *item in imageMenu.itemArray) {
      [imageMenu removeItem:item]; [menu addItem:item];
    }
    return menu;
  }
  NSMenuItem *share = TLLinkAction(@"Share…", ^{ [TLBrowserImageActions shareURL:URL fromView:view atPoint:point]; });
  share.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:nil]; [menu addItem:share];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItem:TLLinkAction(@"Inspect Element", inspect)];
  [menu addItem:NSMenuItem.separatorItem];
  NSMenu *services = [NSMenu new]; services.title = @"Services";
  NSMenuItem *serviceItem = TLLinkSubmenu(@"Services", services);
  serviceItem.image = [NSImage imageWithSystemSymbolName:@"gearshape.2" accessibilityDescription:nil]; [menu addItem:serviceItem];
  return menu;
}
@end
