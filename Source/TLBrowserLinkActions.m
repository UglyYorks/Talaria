#import "TLBrowserLinkActions.h"
#import "TLBrowserImageActions.h"
#import "design_system/TLLinkServicesView.h"
#import "design_system/TLActionMenuItem.h"

static NSMenuItem *TLLinkAction(NSString *title, dispatch_block_t action) {
  return [TLActionMenuItem itemWithTitle:title action:^{ dispatch_async(dispatch_get_main_queue(), action); }];
}
BOOL TLBrowserLinkURLIsNavigable(NSURL *URL) {
  return URL.host.length && [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString];
}
@implementation TLBrowserLinkActions
+ (dispatch_block_t)prepareMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view {
  NSWindow *window = view.window;
  TLLinkServicesView *requestor = [[TLLinkServicesView alloc] initWithFrame:NSZeroRect];
  requestor.URL = URL;
  NSResponder *previous = window.firstResponder;
  [view addSubview:requestor];
  [window makeFirstResponder:requestor];
  [NSApp registerServicesMenuSendTypes:requestor.writablePasteboardTypes returnTypes:@[]];
  // AppKit supplies the contextual Services submenu using this selection.
  // Do not insert the application's global Services menu into a context menu.
  return ^{
    if (window.firstResponder == requestor) [window makeFirstResponder:previous];
    [requestor removeFromSuperview];
  };
}
+ (dispatch_block_t)configureNativeMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view atPoint:(NSPoint)point open:(TLBrowserLinkOpenHandler)open {
  // Preserve WebKit's inspector command and target while its native menu is live.
  NSMenuItem *inspector = nil;
  for (NSMenuItem *item in menu.itemArray) {
    if ([item.identifier containsString:@"InspectElement"] || [item.title isEqual:@"Inspect Element"]) { inspector = item; break; }
  }
  NSMenu *shared = [self menuForURL:URL canSplit:YES view:view point:point open:open inspect:nil imageMenu:nil];
  if (inspector) {
    NSInteger index = [shared indexOfItemWithTitle:@"Inspect Element"];
    [menu removeItem:inspector]; [shared removeItemAtIndex:index]; [shared insertItem:inspector atIndex:index];
  }
  [menu removeAllItems]; menu.autoenablesItems = NO;
  menu.allowsContextMenuPlugIns = YES;
  if (@available(macOS 15.2, *)) menu.automaticallyInsertsWritingToolsItems = NO;
  for (NSMenuItem *item in shared.itemArray) { [shared removeItem:item]; [menu addItem:item]; }
  return [self prepareMenu:menu forURL:URL inView:view];
}
+ (void)popUpMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view atPoint:(NSPoint)point {
  if (!view.window.isVisible) return;
  dispatch_block_t cleanup = [self prepareMenu:menu forURL:URL inView:view];
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
    location:[view convertPoint:point toView:nil] modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber
    context:nil eventNumber:0 clickCount:1 pressure:1];
  // Contextual Services reads the supplied view, not merely the key responder.
  NSView *contextView = (NSView *)view.window.firstResponder;
  @try { [NSMenu popUpContextMenu:menu withEvent:event forView:contextView]; }
  @finally { cleanup(); }
}
+ (void)showSelectedText:(NSString *)text inView:(NSView *)view atPoint:(NSPoint)point {
  NSWindow *window = view.window;
  if (!window.isVisible || !text.length) return;
  NSTextView *selection = [[NSTextView alloc] initWithFrame:NSMakeRect(point.x, point.y, 1, 1)];
  selection.editable = NO; selection.richText = NO; selection.drawsBackground = NO;
  selection.string = text; selection.selectedRange = NSMakeRange(0, text.length);
  [view addSubview:selection];
  NSResponder *previous = window.firstResponder;
  [window makeFirstResponder:selection];
  NSPoint location = [view convertPoint:point toView:nil];
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:location modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  NSMenu *menu = [selection menuForEvent:event];
  @try { [NSMenu popUpContextMenu:menu withEvent:event forView:selection]; }
  @finally {
    if (window.firstResponder == selection) [window makeFirstResponder:previous];
    [selection removeFromSuperview];
  }
}

+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard {
  [pasteboard declareTypes:@[NSPasteboardTypeString, NSPasteboardTypeURL] owner:nil];
  for (NSString *type in @[NSPasteboardTypeString, NSPasteboardTypeURL]) [pasteboard setString:URL.absoluteString forType:type];
}
+ (NSMenu *)menuForURL:(NSURL *)URL canSplit:(BOOL)canSplit view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open inspect:(dispatch_block_t)inspect imageMenu:(NSMenu *)imageMenu {
  NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
  menu.allowsContextMenuPlugIns = YES;
  if (@available(macOS 15.2, *)) menu.automaticallyInsertsWritingToolsItems = NO;
  BOOL navigable = TLBrowserLinkURLIsNavigable(URL);
  NSMenuItem *newTab = TLLinkAction(@"Open Link in New Tab", ^{ open(URL, TLBrowserLinkNewTab); });
  newTab.identifier = @"Talaria.Link.OpenNewTab"; [menu addItem:newTab];
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
  // Sidebar buttons retain their menu; do not let Share retain the button.
  __weak NSView *weakView = view;
  NSMenuItem *share = TLLinkAction(@"Share…", ^{
    NSView *anchor = weakView;
    if (anchor) [TLBrowserImageActions shareURL:URL fromView:anchor atPoint:point];
  });
  share.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:nil]; [menu addItem:share];
  [menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *inspector = [TLActionMenuItem itemWithTitle:@"Inspect Element" action:inspect ?: ^{}];
  inspector.enabled = inspect != nil; [menu addItem:inspector];
  return menu;
}
@end
