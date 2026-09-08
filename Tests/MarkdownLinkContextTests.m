#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "MarkdownRenderer.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLMarkdownContentWebView.h"
#import "Theme.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } NSLog(@"PASS: %@", message); }
static void Wait(BOOL (^ready)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!ready() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  Check(ready(), @"WebKit finishes loading");
}
static id Eval(WKWebView *web, NSString *script) {
  __block BOOL done = NO; __block id value; __block NSError *failure;
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) { value=result; failure=error; done=YES; }];
  Wait(^BOOL { return done; }); Check(!failure, @"fixture JavaScript succeeds"); return value;
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
  TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
  __block NSURL *opened; __block TLBrowserLinkDestination destination; __block NSUInteger contexts=0;
  renderer.linkContextMenuHandler = ^dispatch_block_t(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point) {
    contexts++;
    return [TLBrowserLinkActions configureNativeMenu:menu forURL:URL inView:view atPoint:point
      open:^(NSURL *URL, TLBrowserLinkDestination target) { opened=URL; destination=target; }];
  };
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,800,500) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
  window.title = @"Chat link menu test"; window.releasedWhenClosed=NO;
  NSView *content = [renderer viewForMarkdown:@"# Context menu fixture\n\n[Example link](https://example.com/one)\n\nSelect this ordinary text to use the system text menu.\n\n[Another link](https://example.com/two)" textColor:palette.assistantMessageText baseFont:palette.messageBodyFont];
  [window.contentView addSubview:content];
  [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor], [content.topAnchor constraintEqualToAnchor:window.contentView.topAnchor]]];
  [window makeKeyAndOrderFront:nil];
  TLMarkdownContentWebView *web = [content valueForKey:@"webView"];
  Wait(^BOOL { return !web.loading; });
  Check([Eval(web,@"document.querySelector('a').href") isEqual:@"https://example.com/one"], @"chat renders the fixture link");
  NSPoint point = NSMakePoint(30,30);
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:[web convertPoint:point toView:nil] modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  NSMenu *(^nativeMenu)(void) = ^NSMenu *{ NSMenu *menu=[NSMenu new]; [menu addItemWithTitle:@"Native item" action:nil keyEquivalent:@""]; return menu; };
  NSMenu *menu=nativeMenu();
  [web willOpenMenu:menu withEvent:event];
  Check(contexts==0 && menu.numberOfItems==1, @"background right-click leaves the native menu untouched");
  [web setValue:@{@"url":@"", @"x":@30, @"y":@(web.isFlipped ? 30 : NSHeight(web.bounds)-30)} forKey:@"linkContext"];
  [web setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"linkContextTime"];
  [web willOpenMenu:menu withEvent:event];
  Check(contexts==0, @"selected text without a clicked link retains WebKit's standard menu");
  [web setValue:@{@"url":@"https://example.com/one", @"x":@30, @"y":@(web.isFlipped ? 30 : NSHeight(web.bounds)-30)} forKey:@"linkContext"];
  [web setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"linkContextTime"];
  NSMenuItem *nativeInspector = [[NSMenuItem alloc] initWithTitle:@"Inspect Element" action:@selector(description) keyEquivalent:@""];
  nativeInspector.identifier = @"WKMenuItemIdentifierInspectElement";
  nativeInspector.target = web;
  [menu addItem:nativeInspector];
  NSResponder *originalResponder = window.firstResponder;
  [web willOpenMenu:menu withEvent:event];
  Check([menu itemWithTitle:@"Inspect Element"] == nativeInspector && nativeInspector.target == web,
    @"shared menu retains WebKit's original inspector action and target");
  Check([menu indexOfItemWithTitle:@"Services"] == -1, @"AppKit alone supplies contextual Services, avoiding duplicate menus");
  NSMenu *browserMenu=[TLBrowserLinkActions menuForURL:[NSURL URLWithString:@"https://example.com/one"] canSplit:YES view:web point:point open:^(NSURL *URL, TLBrowserLinkDestination target) {} inspect:nil imageMenu:nil];
  Check(contexts==1 && [[menu.itemArray valueForKey:@"title"] isEqual:[browserMenu.itemArray valueForKey:@"title"]], @"chat and browser use exactly the same link menu");
  [menu performActionForItemAtIndex:2];
  Wait(^BOOL { return opened != nil; });
  Check([opened.absoluteString isEqual:@"https://example.com/one"] && destination==TLBrowserLinkSplitView, @"chat split action preserves the clicked URL and destination");
  [web didCloseMenu:menu withEvent:event];
  Check(window.firstResponder == originalResponder, @"closing the shared link menu restores the original responder");
  if (NSProcessInfo.processInfo.environment[@"TL_CONTEXT_MENU_INTERACTIVE"]) { [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp run]; }
  [window close];
} return 0; }
