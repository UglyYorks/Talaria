#import <Foundation/Foundation.h>
#import "TLWorkspaceSessionStore.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static TLWorkspaceTab *Tab(TLWorkspaceTabKind kind, NSInteger tabID) {
  return [TLWorkspaceTab tabWithKind:kind tabID:tabID title:@"A tab" toolTip:@"Tab details"
    URL:kind == TLWorkspaceTabKindBrowser ? [NSURL URLWithString:@"https://example.com/first"] : nil closeable:YES];
}
static TLAppStateManager *Restore(NSURL *URL) {
  TLAppStateManager *state = [TLAppStateManager new];
  [[[TLWorkspaceSessionStore alloc] initWithURL:URL] restoreStateManager:state];
  return state;
}
static void Write(NSURL *URL, id session) {
  Check([[NSJSONSerialization dataWithJSONObject:session options:NSJSONWritingFragmentsAllowed error:nil]
    writeToURL:URL atomically:YES], @"write session fixture");
}

int main(void) {
  @autoreleasepool {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *URL = [directory URLByAppendingPathComponent:@"workspace-session.json"];
    Check(Restore(URL).snapshot.workspaceTabs.count == 0, @"first launch has no saved tabs");
    TLAppStateManager *state = [TLAppStateManager new];
    TLWorkspaceSessionStore *store = [[TLWorkspaceSessionStore alloc] initWithURL:URL];
    [store observeStateManager:state];
    NSArray *tabs = @[Tab(TLWorkspaceTabKindChat, 42), Tab(TLWorkspaceTabKindBrowser, 42),
      Tab(TLWorkspaceTabKindChat, -8), Tab(TLWorkspaceTabKindSettings, 0), Tab(TLWorkspaceTabKindHistory, 0),
      Tab(TLWorkspaceTabKindAgents, 0), Tab(TLWorkspaceTabKindAutomations, 0), Tab(TLWorkspaceTabKindDebug, 0), Tab(TLWorkspaceTabKindDownloads, 0)];
    for (TLWorkspaceTab *tab in tabs) [state addWorkspaceTab:tab activate:YES];
    [state moveWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42 toIndex:0];
    for (TLWorkspaceTab *tab in tabs) {
      [state activateWorkspaceTabKind:tab.kind tabID:tab.tabID];
      TLAppStateSnapshot *restored = Restore(URL).snapshot;
      Check(restored.workspaceTabs.count == tabs.count, @"all tab kinds survive a new session");
      Check(restored.activeTabKind == tab.kind && restored.activeTabID == tab.tabID,
        @"selection-only changes survive, including matching IDs with different kinds");
      Check(restored.workspaceTabs[0].kind == TLWorkspaceTabKindBrowser && restored.workspaceTabs[1].tabID == 42,
        @"dragged tab order survives");
      Check([restored.workspaceTabs[2].title isEqual:@"A tab"] && restored.workspaceTabs[2].tabID == -8,
        @"unsaved chat tabs retain their identity and title");
    }
    TLWorkspaceTab *browser = [state workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42];
    browser.title = @"Navigated page";
    browser.URL = [NSURL URLWithString:@"https://example.com/second?q=one#section"];
    browser.toolTip = browser.URL.absoluteString;
    [state upsertWorkspaceTab:browser activate:NO];
    TLWorkspaceTab *restoredBrowser = Restore(URL).snapshot.workspaceTabs.firstObject;
    Check([restoredBrowser.URL isEqual:browser.URL] && [restoredBrowser.title isEqual:browser.title] &&
      [restoredBrowser.toolTip isEqual:browser.toolTip], @"background navigation saves the latest page and title");
    [state setWorkspaceTabPinned:YES kind:TLWorkspaceTabKindBrowser tabID:42];
    [state setWorkspaceTabPinned:YES kind:TLWorkspaceTabKindChat tabID:-8];
    Check(Restore(URL).snapshot.workspaceTabs[0].pinned && Restore(URL).snapshot.workspaceTabs[1].pinned,
      @"pin state and leading order survive relaunch for browser and draft chat");
    [state upsertWorkspaceTab:Tab(TLWorkspaceTabKindBrowser,42) activate:NO];
    Check([Restore(URL) workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42].pinned, @"metadata refresh cannot unpin a browser");
    [state replaceWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:-8 withTab:Tab(TLWorkspaceTabKindChat,88) activate:NO];
    Check([Restore(URL) workspaceTabWithKind:TLWorkspaceTabKindChat tabID:88].pinned, @"saving a draft preserves its pin");
    [state moveWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42 toIndex:8];
    Check(Restore(URL).snapshot.workspaceTabs[1].pinned, @"dragging a pinned tab keeps it inside the leading group");
    [state moveWorkspaceTabWithKind:TLWorkspaceTabKindSettings tabID:0 toIndex:0];
    Check(Restore(URL).snapshot.workspaceTabs[0].pinned && Restore(URL).snapshot.workspaceTabs[1].pinned,
      @"regular tabs cannot be dragged ahead of pins");
    [state setWorkspaceTabPinned:NO kind:TLWorkspaceTabKindBrowser tabID:42];
    Check(![Restore(URL) workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42].pinned &&
      Restore(URL).snapshot.workspaceTabs[1].kind == TLWorkspaceTabKindBrowser, @"unpin survives relaunch and returns tab after pinned group");
    [state activateWorkspaceTabKind:TLWorkspaceTabKindBrowser tabID:42];
    [state removeWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:42];
    TLAppStateSnapshot *closed = Restore(URL).snapshot;
    Check(closed.workspaceTabs.count == tabs.count - 1 && closed.activeTabKind == state.snapshot.activeTabKind &&
      closed.activeTabID == state.snapshot.activeTabID, @"closing an active tab saves its removal and successor together");
    for (TLWorkspaceTab *tab in state.snapshot.workspaceTabs) [state removeWorkspaceTabWithKind:tab.kind tabID:tab.tabID];
    Check(Restore(URL).snapshot.workspaceTabs.count == 0, @"an empty workspace does not resurrect old tabs");

    NSDictionary *valid = @{@"kind":@(TLWorkspaceTabKindBrowser), @"tabID":@9, @"title":@"Valid",
      @"url":@"https://example.com/restored"};
    Write(URL, @{@"version":@1, @"activeKind":@(TLWorkspaceTabKindChat), @"activeID":@999,
      @"tabs":@[NSNull.null, @"bad", @{}, @{@"kind":@100, @"tabID":@1},
        @{@"kind":@0, @"tabID":@"1"}, @{@"kind":@0, @"tabID":@1.5},
        @{@"kind":@0, @"tabID":@(NSIntegerMin)}, @{@"kind":@2, @"tabID":@1, @"url":@"javascript:alert(1)"},
        @{@"kind":@2, @"tabID":@2, @"url":@"https://"}, valid, valid,
        @{@"kind":@0, @"tabID":@(-3), @"title":NSNull.null} ]});
    TLAppStateSnapshot *recovered = Restore(URL).snapshot;
    Check(recovered.workspaceTabs.count == 2 && recovered.activeTabKind == TLWorkspaceTabKindBrowser &&
      recovered.activeTabID == 9, @"invalid and duplicate entries are skipped and missing selection falls back");
    Check([recovered.workspaceTabs.lastObject.title isEqual:@""], @"invalid optional metadata has safe defaults");
    for (id invalid in @[@[], @"invalid", @{@"version":@2, @"tabs":@[valid]}, @{@"version":@1, @"tabs":@{}}]) {
      Write(URL, invalid);
      Check(Restore(URL).snapshot.workspaceTabs.count == 0, @"malformed and unsupported sessions are ignored");
    }
    [@"{truncated" writeToURL:URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check(Restore(URL).snapshot.workspaceTabs.count == 0, @"truncated session files do not prevent startup");
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    NSLog(@"Workspace session tests passed");
  }
  return 0;
}
