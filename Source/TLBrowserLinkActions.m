#import "TLBrowserLinkActions.h"
#import "TLBrowserImageActions.h"
#import "design_system/TLActionMenuItem.h"

static void TLLinkError(NSError *error, NSWindow *window) {
  if (error) [NSApp presentError:error modalForWindow:window delegate:nil didPresentSelector:NULL contextInfo:NULL];
}
static NSMenuItem *TLLinkAction(NSString *title, dispatch_block_t action) {
  return [TLActionMenuItem itemWithTitle:title action:^{ dispatch_async(dispatch_get_main_queue(), action); }];
}
static NSMenuItem *TLLinkSubmenu(NSString *title, NSMenu *submenu) {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]; item.submenu = submenu; return item;
}
static void TLLinkEmptyItem(NSMenu *menu, NSString *title) {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]; item.enabled = NO; [menu addItem:item];
}
@implementation TLBrowserLinkActions
+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard {
  [pasteboard declareTypes:@[NSPasteboardTypeString, NSPasteboardTypeURL] owner:nil];
  for (NSString *type in @[NSPasteboardTypeString, NSPasteboardTypeURL]) [pasteboard setString:URL.absoluteString forType:type];
}
+ (void)promptForName:(NSString *)title initialValue:(NSString *)value window:(NSWindow *)window completion:(void (^)(NSString *))completion {
  NSAlert *alert = [NSAlert new]; alert.messageText = title;
  NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,24)]; name.stringValue = value;
  name.accessibilityLabel = @"Name"; alert.accessoryView = name;
  [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Cancel"];
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    completion(response == NSAlertFirstButtonReturn ? name.stringValue : nil);
  }];
  [alert.window makeFirstResponder:name];
}
+ (NSMenu *)menuForURL:(NSURL *)URL title:(NSString *)title view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open download:(void (^)(BOOL))download inspect:(dispatch_block_t)inspect {
  TLBrowserLinkStore *store = TLBrowserLinkStore.sharedStore;
  NSWindow *window = view.window;
  NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
  BOOL navigable = TLBrowserLinkURLIsNavigable(URL);
  [menu addItem:TLLinkAction(@"Open Link in New Tab", ^{ open(URL, TLBrowserLinkNewTab, nil); })];
  [menu addItem:TLLinkAction(@"Open Link in New Window", ^{ open(URL, TLBrowserLinkNewWindow, nil); })];
  NSMenu *groups = [NSMenu new]; groups.autoenablesItems = NO;
  [groups addItem:TLLinkAction(@"New Tab Group…", ^{
    [self promptForName:@"New Tab Group" initialValue:@"" window:window completion:^(NSString *name) {
      if (!name) return;
      NSError *error = nil; NSString *groupID = [store createGroupNamed:name error:&error];
      if (groupID && [store addURL:URL title:title collection:groupID error:&error]) open(URL, TLBrowserLinkTabGroup, groupID);
      TLLinkError(error, window);
    }];
  })];
  if (store.groups.count) [groups addItem:NSMenuItem.separatorItem];
  for (NSDictionary *group in store.groups) {
    [groups addItem:TLLinkAction(group[@"title"], ^{
      NSError *error = nil;
      if ([store addURL:URL title:title collection:group[@"id"] error:&error]) open(URL, TLBrowserLinkTabGroup, group[@"id"]);
      TLLinkError(error, window);
    })];
  }
  [menu addItem:TLLinkSubmenu(@"Open Link in Tab Group", groups)];
  [menu addItem:NSMenuItem.separatorItem];
  [menu addItem:TLLinkAction(@"Download Linked File", ^{ download(NO); })];
  [menu addItem:TLLinkAction(@"Download Linked File As…", ^{ download(YES); })];
  // Non-web links still support copying, sharing, Services and inspection.
  for (NSMenuItem *item in menu.itemArray) if (!item.separatorItem) item.enabled = navigable;
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *copy = TLLinkAction(@"Copy Link", ^{
    [self copyURL:URL toPasteboard:NSPasteboard.generalPasteboard];
  }); copy.image = [NSImage imageWithSystemSymbolName:@"link" accessibilityDescription:nil]; [menu addItem:copy];
  [menu addItem:NSMenuItem.separatorItem];
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
+ (void)appendLibraryMenusToMenu:(NSMenu *)menu window:(NSWindow *)window open:(TLBrowserLinkOpenHandler)open {
  TLBrowserLinkStore *store = TLBrowserLinkStore.sharedStore;
  NSMenu *groups = [NSMenu new]; groups.autoenablesItems = NO;
  for (NSDictionary *group in store.groups) {
    NSMenu *actions = [NSMenu new]; actions.autoenablesItems = NO;
    NSArray *links = [store linksInCollection:group[@"id"]];
    NSMenuItem *openGroup = TLLinkAction(@"Open Tab Group", ^{
      for (NSDictionary *link in links) open([NSURL URLWithString:link[@"url"]], TLBrowserLinkTabGroup, group[@"id"]);
    }); openGroup.enabled = links.count > 0; [actions addItem:openGroup];
    for (NSDictionary *link in links) [actions addItem:TLLinkAction(link[@"title"], ^{ open([NSURL URLWithString:link[@"url"]], TLBrowserLinkTabGroup, group[@"id"]); })];
    [actions addItem:NSMenuItem.separatorItem];
    [actions addItem:TLLinkAction(@"Remove Saved Group", ^{ NSError *error = nil; [store removeGroup:group[@"id"] error:&error]; TLLinkError(error, window); })];
    [groups addItem:TLLinkSubmenu(group[@"title"], actions)];
  }
  if (!groups.numberOfItems) TLLinkEmptyItem(groups, @"No tab groups yet");
  NSMenuItem *item = TLLinkSubmenu(@"Tab Groups", groups); item.image = [NSImage imageWithSystemSymbolName:@"square.on.square" accessibilityDescription:nil]; [menu addItem:item];
}
@end
