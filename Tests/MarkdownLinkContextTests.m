#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "MarkdownRenderer.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLMarkdownContentWebView.h"
#import "Theme.h"
#import "TalariaWindowController.h"
#import "TLChatPresentation.h"
#import <objc/runtime.h>

@interface TalariaWindowController (ContextMenuTests)
- (void)installMessageContextMenuMonitor;
@end
@interface TLContextMenuTestController : TalariaWindowController
@property BOOL sending;
@end
@implementation TLContextMenuTestController
- (BOOL)isChatWorkspaceActive { return YES; }
- (BOOL)isSending { return self.sending; }
@end

static NSEvent *(^MessageMonitor)(NSEvent *);
static NSMenu *PoppedMessageMenu;
@interface NSEvent (ContextMenuTests)
+ (id)testAddMonitor:(NSEventMask)mask handler:(NSEvent *(^)(NSEvent *))handler;
@end
@implementation NSEvent (ContextMenuTests)
+ (id)testAddMonitor:(NSEventMask)mask handler:(NSEvent *(^)(NSEvent *))handler {
  MessageMonitor = [handler copy];
  return [self testAddMonitor:mask handler:handler];
}
@end
@interface NSMenu (ContextMenuTests)
+ (void)testPopUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view;
@end
@implementation NSMenu (ContextMenuTests)
+ (void)testPopUpContextMenu:(NSMenu *)menu withEvent:(NSEvent *)event forView:(NSView *)view {
  PoppedMessageMenu = menu;
}
@end

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

static void TestMessageMenuRouting(NSWindow *window, NSView *row, TLMarkdownContentWebView *web) {
  TLContextMenuTestController *controller = [[TLContextMenuTestController alloc] initWithWindow:window];
  TLChatPresentation *presentation = [TLChatPresentation new];
  presentation.chat = [TLChatRecord new]; presentation.chat.chatID = 42;
  presentation.chatWorkspace = window.contentView;
  TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleAssistant content:@"A message with a link" thinking:nil];
  presentation.messages = [NSMutableArray arrayWithObject:message];
  [presentation.messageRowViews setObject:row forKey:message];
  [controller setValue:presentation forKey:@"chatPresentation"];
  Method addMonitor = class_getClassMethod(NSEvent.class, @selector(addLocalMonitorForEventsMatchingMask:handler:));
  Method testAddMonitor = class_getClassMethod(NSEvent.class, @selector(testAddMonitor:handler:));
  method_exchangeImplementations(addMonitor, testAddMonitor);
  [controller installMessageContextMenuMonitor];
  method_exchangeImplementations(addMonitor, testAddMonitor);
  Method popup = class_getClassMethod(NSMenu.class, @selector(popUpContextMenu:withEvent:forView:));
  Method testPopup = class_getClassMethod(NSMenu.class, @selector(testPopUpContextMenu:withEvent:forView:));
  method_exchangeImplementations(popup, testPopup);

  NSDictionary *bounds = Eval(web, @"(()=>{const r=document.querySelector('a').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()");
  NSPoint point = NSMakePoint([bounds[@"x"] doubleValue], web.isFlipped ? [bounds[@"y"] doubleValue] : NSHeight(web.bounds)-[bounds[@"y"] doubleValue]);
  for (NSNumber *controlClick in @[@NO, @YES]) {
    NSEvent *event = [NSEvent mouseEventWithType:controlClick.boolValue ? NSEventTypeLeftMouseDown : NSEventTypeRightMouseDown
      location:[web convertPoint:point toView:nil] modifierFlags:controlClick.boolValue ? NSEventModifierFlagControl : 0
      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    PoppedMessageMenu = nil;
    Check(MessageMonitor(event) == event && !PoppedMessageMenu,
      @"message monitor forwards right-click and Control-click to WebKit without opening the row menu");
    Check([web.fallbackContextMenu itemWithTitle:@"Copy message"] != nil, @"forwarded click retains the message fallback");
    [web setValue:@{@"url":@"https://example.com/one", @"x":bounds[@"x"], @"y":bounds[@"y"]} forKey:@"linkContext"];
    [web setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"linkContextTime"];
    NSMenu *menu = [NSMenu new];
    [web willOpenMenu:menu withEvent:event];
    Check([menu itemWithTitle:@"Open Link in New Tab"] != nil && [menu itemWithTitle:@"Copy message"] == nil,
      @"link menu takes priority over the real controller's message menu");
    Check(!web.fallbackContextMenu, @"link menu consumes the pending message fallback");
    [web didCloseMenu:menu withEvent:event];

    controller.sending = controlClick.boolValue;
    Check(MessageMonitor(event) == event, @"ordinary message content also reaches WebKit");
    [web setValue:@{@"url":@"", @"x":bounds[@"x"], @"y":bounds[@"y"]} forKey:@"linkContext"];
    [web willOpenMenu:menu withEvent:event];
    NSMenuItem *copy = [menu itemWithTitle:@"Copy message"];
    NSMenuItem *delete = [menu itemWithTitle:@"Delete message"];
    Check(copy.target == controller && copy.representedObject[@"message"] == message &&
      [copy.representedObject[@"chatID"] integerValue] == 42, @"non-link menu retains the correct message, chat, and action target");
    Check(delete && delete.enabled == !controller.sending && !menu.autoenablesItems,
      @"ordinary message menu preserves Delete availability during streaming");
    Check(![menu itemWithTitle:@"Open Link in New Tab"] && !web.fallbackContextMenu,
      @"ordinary content does not retain actions from the previous link");
    [web didCloseMenu:menu withEvent:event];
  }
  method_exchangeImplementations(popup, testPopup);

  // Deliver an actual native click through WebKit as well: no injected URL or
  // direct willOpenMenu call, so the trusted DOM event and native menu must agree.
  __block NSArray<NSString *> *nativeTitles;
  id tracking = [NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification
    object:nil queue:nil usingBlock:^(NSNotification *note) {
      NSMenu *menu = note.object;
      dispatch_async(dispatch_get_main_queue(), ^{
        nativeTitles = [menu.itemArray valueForKey:@"title"];
        [menu cancelTracking];
      });
    }];
  NSEvent *nativeEvent = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown
    location:[web convertPoint:point toView:nil] modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
    windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  Check(MessageMonitor(nativeEvent) == nativeEvent, @"real contextual click reaches the renderer");
  [NSApp postEvent:nativeEvent atStart:YES];
  NSEvent *queuedEvent = [NSApp nextEventMatchingMask:NSEventMaskRightMouseDown untilDate:[NSDate dateWithTimeIntervalSinceNow:2] inMode:NSDefaultRunLoopMode dequeue:YES];
  Check(queuedEvent != nil, @"AppKit dequeues the native contextual click");
  [NSApp sendEvent:queuedEvent];
  Wait(^BOOL { return nativeTitles != nil; });
  [NSNotificationCenter.defaultCenter removeObserver:tracking];
  Check([nativeTitles containsObject:@"Open Link in New Tab"] && ![nativeTitles containsObject:@"Copy message"],
    @"native WebKit click opens the shared link menu through the trusted DOM event");
  MessageMonitor = nil;
}
static void TestTrailingListLinks(void) {
  NSString *fixture = @"- [Wikipedia](https://wikipedia.org)\n- [NASA](https://nasa.gov)\n"
    "- [Internet Archive](https://archive.org)\n- [Project Gutenberg](https://gutenberg.org)\n"
    "- [OpenStreetMap](https://openstreetmap.org)";
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSView *view = [renderer viewForMarkdown:fixture textColor:palette.assistantMessageText baseFont:palette.messageBodyFont];
    [window.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
      [view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
      [view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor]]];
    WKWebView *web = [view valueForKey:@"webView"];
    Wait(^BOOL { return [[view valueForKey:@"documentReady"] boolValue]; });
    for (NSNumber *width in @[@700, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 500)];
      [window.contentView layoutSubtreeIfNeeded];
      for (NSString *text in @[fixture, [fixture stringByAppendingString:@"\n  - [A nested link with a long wrapping title](https://example.com)"]]) {
        [renderer updateMarkdown:text inView:view];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        Check([Eval(web, @"(()=>{const box=document.querySelector('#content').getBoundingClientRect();"
          "return box.top>=0 && box.bottom<=innerHeight+1 && [...document.querySelectorAll('a')].every(a=>"
          "a.getBoundingClientRect().bottom<=innerHeight && getComputedStyle(a).textDecorationLine==='underline');})()") boolValue],
          @"list margins, trailing links, and underlines fit inside the measured message at both widths and themes");
      }
    }
    [window close];
  }
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TestTrailingListLinks();
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
  TestMessageMenuRouting(window, content, web);
  if (NSProcessInfo.processInfo.environment[@"TL_CONTEXT_MENU_INTERACTIVE"]) { [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp run]; }
  [window close];
} return 0; }
