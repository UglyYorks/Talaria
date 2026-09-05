#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TalariaWindowController.h"
#import "WorkspaceTabRuntime.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TalariaWindowController (TabShortcutTests)
- (void)openBrowserTab:(id)sender;
- (void)closeBrowserTab:(id)sender;
- (void)closeBrowserTabWithID:(NSInteger)tabID;
- (void)openBrowserTabWithURL:(NSURL *)URL;
- (void)showHistoryScreen:(id)sender;
- (void)closeHistoryTab:(id)sender;
- (void)setRuntime:(TLWorkspaceTabRuntime *)runtime forTab:(TLWorkspaceTab *)tab;
@end

// Supply focus deterministically: command-line test processes may not activate
// while another desktop app owns focus. The production routing remains real.
@interface TLShortcutTestApplication : NSApplication
@property (nonatomic, strong) NSWindow *shortcutKeyWindow;
@property (nonatomic, strong) NSWindow *shortcutModalWindow;
@end
@implementation TLShortcutTestApplication
- (NSWindow *)keyWindow { return self.shortcutKeyWindow; }
- (NSWindow *)modalWindow { return self.shortcutModalWindow; }
@end

@interface TLShortcutTestWindow : NSWindow
@property (nonatomic) NSUInteger closeCount;
@property (nonatomic, strong) NSWindow *shortcutSheet;
@end
@implementation TLShortcutTestWindow
- (void)performClose:(id)sender { self.closeCount++; }
- (NSWindow *)attachedSheet { return self.shortcutSheet; }
@end

// Use the real tab actions/state manager; omit rendering and browser processes.
@interface TLShortcutTestController : TalariaWindowController
@property (nonatomic, strong) NSURL *reopenedURL;
@end
@implementation TLShortcutTestController
- (void)renderWorkspaceTabs {}
- (void)reloadWorkspaceTabs {}
- (void)updateWorkspaceMode {}
- (void)updateControlStates {}
- (void)resetMessageRowCache {}
- (void)selectActiveChatInHistory {}
- (void)renderMessages {}
- (void)openBrowserTabWithURL:(NSURL *)URL {
  self.reopenedURL = URL;
  TLAppStateManager *state = [self valueForKey:@"appStateManager"];
  NSInteger tabID = [[self valueForKey:@"nextBrowserTabID"] integerValue];
  [self setValue:@(tabID + 1) forKey:@"nextBrowserTabID"];
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:tabID
    title:@"Browser" toolTip:URL.absoluteString URL:URL closeable:YES];
  [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:nil openAction:@selector(openBrowserTab:)
    closeAction:@selector(closeBrowserTab:)] forTab:tab];
  [state addWorkspaceTab:tab activate:YES];
}
@end

@interface TLShortcutWindowEvent : NSObject
@property (nonatomic, strong) NSEvent *event;
@property (nonatomic, strong) NSWindow *window;
@end
@implementation TLShortcutWindowEvent
- (NSEventType)type { return self.event.type; }
- (NSEventModifierFlags)modifierFlags { return self.event.modifierFlags; }
- (NSString *)charactersIgnoringModifiers { return self.event.charactersIgnoringModifiers; }
- (BOOL)isARepeat { return self.event.isARepeat; }
@end

static NSEvent *Key(NSWindow *window, NSString *key, NSEventModifierFlags flags, BOOL repeat) {
  NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
    windowNumber:window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:repeat keyCode:0];
  if (!window) return event;
  // Synthetic NSEvents do not resolve native window IDs in headless runs.
  TLShortcutWindowEvent *routed = [TLShortcutWindowEvent new];
  routed.event = event;
  routed.window = window;
  return (NSEvent *)routed;
}

static void TestEventMatching(void) {
  NSEventModifierFlags cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift;
  NSEventModifierFlags ctrl = NSEventModifierFlagControl, opt = NSEventModifierFlagOption;
  NSArray *cases = @[
    @[@"t", @(cmd), @(TLTabCommandNew)], @[@"w", @(cmd), @(TLTabCommandClose)],
    @[@"T", @(cmd | shift), @(TLTabCommandReopen)], @[@"W", @(cmd | shift), @(TLTabCommandCloseWindow)],
    @[@"\t", @(ctrl), @(TLTabCommandNext)], @[@"\x19", @(ctrl | shift), @(TLTabCommandPrevious)],
    @[@"}", @(cmd | shift), @(TLTabCommandNext)], @[@"{", @(cmd | shift), @(TLTabCommandPrevious)],
    @[@"]", @(cmd | shift), @(TLTabCommandNext)], @[@"[", @(cmd | shift), @(TLTabCommandPrevious)],
    @[@"\uF703", @(cmd | opt | NSEventModifierFlagFunction | NSEventModifierFlagNumericPad), @(TLTabCommandNext)],
    @[@"\uF702", @(cmd | opt), @(TLTabCommandPrevious)],
    @[@"\uF72C", @(ctrl | shift | NSEventModifierFlagFunction), @(TLTabCommandMoveLeft)],
    @[@"\uF72D", @(ctrl | shift), @(TLTabCommandMoveRight)],
    @[@"T", @(cmd | NSEventModifierFlagCapsLock), @(TLTabCommandNew)],
    @[@"t", @0, @0], @[@"t", @(cmd | ctrl), @0], @[@"[", @(cmd), @0], @[@"0", @(cmd), @0],
  ];
  for (NSArray *entry in cases) {
    Check(TLTabCommandForEvent(Key(nil, entry[0], [entry[1] unsignedIntegerValue], NO)) == [entry[2] integerValue],
      [NSString stringWithFormat:@"maps key %@ with modifiers %@", entry[0], entry[1]]);
  }
  for (NSInteger number = 1; number <= 9; number++) {
    Check(TLTabCommandForEvent(Key(nil, [NSString stringWithFormat:@"%ld", (long)number], cmd, NO)) == 100 + number,
      @"number shortcuts use displayed tab positions");
  }
  NSMenu *menu = TLCreateTabMenu([NSObject new], @selector(description));
  Check(menu.numberOfItems == 21, @"menu includes all commands and aliases");
  for (NSMenuItem *item in menu.itemArray) {
    Check(TLTabCommandForEvent(Key(nil, item.keyEquivalent, item.keyEquivalentModifierMask, NO)) == item.tag,
      @"menu equivalents and browser-focus routing agree");
  }
}

static TLShortcutTestController *Controller(void) {
  TLShortcutTestWindow *window = [[TLShortcutTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLShortcutTestController *controller = [[TLShortcutTestController alloc] initWithWindow:window];
  [controller setValue:[TLAppStateManager new] forKey:@"appStateManager"];
  [controller setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [controller setValue:[TLAppSettings new] forKey:@"settings"];
  [controller setValue:@1 forKey:@"nextBrowserTabID"];
  [controller setValue:@(-1) forKey:@"nextDraftChatID"];
  [controller setValue:[NSTextView new] forKey:@"promptTextView"];
  return controller;
}

static void TestNavigationAndRestore(void) {
  TLShortcutTestController *controller = Controller();
  TLAppStateManager *state = [controller valueForKey:@"appStateManager"];
  for (NSInteger i = 0; i < 11; i++) [controller openBrowserTabWithURL:[NSURL URLWithString:@"https://example.com/page"]];
  [controller showHistoryScreen:nil];
  Check(state.snapshot.workspaceTabs.count == 12, @"setup includes mixed tab kinds");
  [controller performTabCommand:TLTabCommandNext];
  Check(state.snapshot.activeTabID == 1 && state.snapshot.activeTabKind == TLWorkspaceTabKindBrowser, @"next wraps to first");
  [controller performTabCommand:TLTabCommandPrevious];
  Check(state.snapshot.activeTabKind == TLWorkspaceTabKindHistory, @"previous wraps to last across kinds");
  [controller performTabCommand:(TLTabCommand)108];
  Check(state.snapshot.activeTabID == 8, @"command-eight selects eighth position");
  [controller performTabCommand:TLTabCommandSelectLast];
  Check(state.snapshot.activeTabKind == TLWorkspaceTabKindHistory, @"command-nine selects last of more than nine tabs");
  [controller performTabCommand:TLTabCommandMoveLeft];
  Check(state.snapshot.workspaceTabs[10].kind == TLWorkspaceTabKindHistory && state.snapshot.activeTabKind == TLWorkspaceTabKindHistory,
    @"reordering moves selected tab without changing selection");
  [controller performTabCommand:TLTabCommandMoveRight];
  Check(![controller canPerformTabCommand:TLTabCommandMoveRight], @"cannot reorder past right edge");
  [controller performTabCommand:TLTabCommandSelectFirst];
  Check(![controller canPerformTabCommand:TLTabCommandMoveLeft], @"cannot reorder past left edge");
  [controller performTabCommand:TLTabCommandMoveLeft];
  Check(state.snapshot.workspaceTabs.firstObject.tabID == 1, @"out-of-bounds reorder is harmless");

  [controller closeBrowserTabWithID:3]; // Mouse-close a background tab.
  [controller closeHistoryTab:nil];
  [controller performTabCommand:TLTabCommandReopen];
  Check(state.snapshot.activeTabKind == TLWorkspaceTabKindHistory && state.snapshot.workspaceTabs.lastObject.kind == TLWorkspaceTabKindHistory,
    @"reopen restores last closed singleton to former position");
  [controller performTabCommand:TLTabCommandReopen];
  Check(state.snapshot.activeTabKind == TLWorkspaceTabKindBrowser && state.snapshot.workspaceTabs[2].tabID == state.snapshot.activeTabID,
    @"repeated reopen restores background browser at original position with new runtime identity");
  Check([controller.reopenedURL.absoluteString isEqual:@"https://example.com/page"], @"browser restores saved URL");
  Check(![controller canPerformTabCommand:TLTabCommandReopen], @"restore stack is exhausted");

  [controller performTabCommand:TLTabCommandNew];
  NSInteger draftID = state.snapshot.activeTabID;
  NSTextView *prompt = [controller valueForKey:@"promptTextView"];
  prompt.string = @"unsent draft";
  [controller setValue:@"test-model" forKeyPath:@"activeChat.model"];
  [controller performTabCommand:TLTabCommandClose];
  Check(![state hasWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:draftID], @"close removes draft tab");
  [controller performTabCommand:TLTabCommandReopen];
  Check(state.snapshot.activeTabID == draftID && state.snapshot.activeTabKind == TLWorkspaceTabKindChat && [prompt.string isEqual:@"unsent draft"],
    @"restore preserves draft identity and unsent input");
  Check([[controller valueForKeyPath:@"activeChat.model"] isEqual:@"test-model"], @"restore preserves draft model");
  [controller performTabCommand:TLTabCommandCloseWindow];
  Check(((TLShortcutTestWindow *)controller.window).closeCount == 1 && state.snapshot.workspaceTabs.count == 13,
    @"close-window leaves workspace tabs intact");
  [controller.window close];
}

static void TestRoutingAndBoundaries(void) {
  TLShortcutTestController *controller = Controller();
  TLAppStateManager *state = [controller valueForKey:@"appStateManager"];
  [controller performTabCommand:TLTabCommandNew];
  Check(![controller canPerformTabCommand:TLTabCommandNext] && ![controller canPerformTabCommand:(TLTabCommand)102],
    @"one tab disables cycling and missing positions");
  [controller performTabCommand:TLTabCommandClose];
  Check(((TLShortcutTestWindow *)controller.window).closeCount == 1 && state.snapshot.workspaceTabs.count == 1 &&
    ![controller canPerformTabCommand:TLTabCommandReopen], @"last-tab close preserves existing window behavior without fake history");
  TLAppDelegate *delegate = [TLAppDelegate new];
  [delegate setValue:controller forKey:@"windowController"];
  [(TLShortcutTestApplication *)NSApp setShortcutKeyWindow:controller.window];
  Check(NSApp.keyWindow == controller.window, @"test workspace owns keyboard focus");
  NSTextView *input = [controller valueForKey:@"promptTextView"];
  [controller.window.contentView addSubview:input];
  [controller.window makeFirstResponder:input];
  Check([delegate handleTabShortcutEvent:Key(controller.window, @"t", NSEventModifierFlagCommand, NO)] && state.snapshot.workspaceTabs.count == 2,
    @"new-tab works while an editor owns focus");
  [delegate handleTabShortcutEvent:Key(controller.window, @"t", NSEventModifierFlagCommand, YES)];
  Check(state.snapshot.workspaceTabs.count == 2, @"holding new-tab does not flood tabs");
  [delegate handleTabShortcutEvent:Key(controller.window, @"\t", NSEventModifierFlagControl, YES)];
  Check(state.snapshot.activeTabID == -1, @"cycling allows key repeat");
  Check([delegate handleTabShortcutEvent:Key(controller.window, @"8", NSEventModifierFlagCommand, NO)] && state.snapshot.activeTabID == -1,
    @"missing-position shortcut is consumed without changing selection");
  Check(![delegate handleTabShortcutEvent:Key(controller.window, @"x", NSEventModifierFlagCommand, NO)], @"editing shortcuts pass through");
  NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  other.releasedWhenClosed = NO;

  Check(![delegate handleTabShortcutEvent:Key(other, @"t", NSEventModifierFlagCommand, NO)], @"events for another window do not mutate workspace");
  [(TLShortcutTestApplication *)NSApp setShortcutKeyWindow:other];
  Check(![delegate handleTabShortcutEvent:Key(controller.window, @"t", NSEventModifierFlagCommand, NO)], @"inactive workspace rejects shortcuts");
  [(TLShortcutTestApplication *)NSApp setShortcutKeyWindow:controller.window];
  ((TLShortcutTestWindow *)controller.window).shortcutSheet = other;
  Check(![delegate handleTabShortcutEvent:Key(controller.window, @"w", NSEventModifierFlagCommand, NO)], @"sheets block workspace shortcuts");
  ((TLShortcutTestWindow *)controller.window).shortcutSheet = nil;
  ((TLShortcutTestApplication *)NSApp).shortcutModalWindow = other;
  Check(![delegate handleTabShortcutEvent:Key(controller.window, @"t", NSEventModifierFlagCommand, NO)], @"modal windows block workspace shortcuts");
  ((TLShortcutTestApplication *)NSApp).shortcutModalWindow = nil;
  [controller setValue:@YES forKey:@"widgetbookMode"];
  Check(![controller canPerformTabCommand:TLTabCommandNew], @"widgetbook does not create real tabs");
  [(TLShortcutTestApplication *)NSApp setShortcutKeyWindow:nil];
  [other close];
  [controller.window close];
}

int main(void) {
  @autoreleasepool {
    [TLShortcutTestApplication sharedApplication];
    TestEventMatching();
    TestNavigationAndRestore();
    TestRoutingAndBoundaries();
    NSLog(@"TabShortcutTests passed");
  }
  return 0;
}
