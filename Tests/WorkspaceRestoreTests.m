#import "TLChatControllerTestSupport.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "TalariaWindowController.h"
#import "TLBrowserTabController.h"
#import "TLBrowserPreferences.h"
#import "TLWorkspaceSessionStore.h"
#import "TLDownloadsTabController.h"
#import "WorkspaceTabRuntime.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TalariaWindowController (RestoreTests)
- (void)loadInitialState;
- (void)hydrateWorkspaceTabsFromAppState;
- (void)loadChatWithID:(NSInteger)chatID;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)openBrowserTabWithURL:(NSURL *)URL;
- (BOOL)windowShouldClose:(NSWindow *)window;
- (TLWorkspaceTabRuntime *)runtimeForTab:(TLWorkspaceTab *)tab;
@end

// Keep the real startup, tab actions, runtime creation and metadata callbacks;
// omit unrelated rendering, gateway work and WebKit process creation.
@interface TLRestoreTestController : TalariaWindowController
@end
@implementation TLRestoreTestController
- (void)renderMessages {}
- (void)reloadWorkspaceTabs {}
- (void)updateWorkspaceMode {}
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {}
- (void)applyTheme {}
- (void)rebuildSidebarAgents {}
- (void)reloadHistoryPanel {}
- (void)selectActiveChatInHistory {}
- (void)prepareHermesCommands {}
- (void)refreshAgents {}
- (void)refreshDebugTerminalAvailability {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (NSView *)buildSettingsTabContent { return [NSView new]; }
- (NSView *)buildAgentsTabContent { return [NSView new]; }
- (NSView *)buildAutomationsContent { return [NSView new]; }
- (NSView *)buildDebugTabContent { return [NSView new]; }
@end

static NSUInteger browserStarts;
@interface TLBrowserTabController (RestoreTests)
- (void)testStartInWindow:(NSWindow *)window;
@end
@implementation TLBrowserTabController (RestoreTests)
- (void)testStartInWindow:(NSWindow *)window { browserStarts++; }
@end

@interface TLRestoreTestDatabase : NSObject
@end
@implementation TLRestoreTestDatabase
- (NSArray *)listBrowserHistory:(NSError **)error { return @[]; }
- (NSInteger)currentAgentID { return 0; }
- (TLAppSettings *)appSettings:(NSError **)error {
  TLAppSettings *settings = [TLAppSettings defaultSettings]; settings.onboardingCompleted = YES; return settings;
}
- (TLChatRecord *)chatWithID:(NSInteger)chatID error:(NSError **)error {
  if (chatID != 42) return nil;
  TLChatRecord *chat = [TLChatRecord new]; chat.chatID = 42; chat.title = @"Saved conversation";
  chat.model = @"test-model"; chat.messages = @[]; return chat;
}
- (NSArray *)listChats:(NSError **)error { return @[[self chatWithID:42 error:nil]]; }
- (NSArray *)listAgents:(NSError **)error { return @[]; }
@end

static TLAppStateManager *Seed(void) {
  TLAppStateManager *state = [TLAppStateManager new];
  NSArray *entries = @[@[@(TLWorkspaceTabKindChat),@42], @[@(TLWorkspaceTabKindBrowser),@8],
    @[@(TLWorkspaceTabKindChat),@(-6)], @[@(TLWorkspaceTabKindSettings),@0],
    @[@(TLWorkspaceTabKindAgents),@0], @[@(TLWorkspaceTabKindDebug),@0], @[@(TLWorkspaceTabKindAutomations),@0], @[@(TLWorkspaceTabKindDownloads),@0]];
  for (NSArray *entry in entries) [state addWorkspaceTab:[TLWorkspaceTab tabWithKind:[entry[0] integerValue]
    tabID:[entry[1] integerValue] title:@"Restored tab" toolTip:nil
    URL:[entry[0] integerValue] == TLWorkspaceTabKindBrowser ? [NSURL URLWithString:@"https://example.com/restore"] : nil
    closeable:YES] activate:NO];
  [state activateWorkspaceTabKind:TLWorkspaceTabKindBrowser tabID:8];
  return state;
}

static TLRestoreTestController *Load(TLAppStateManager *state) {
  TLRestoreTestController *owner = [[TLRestoreTestController alloc] initWithWindow:nil];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[TLRestoreTestDatabase new] forKey:@"database"];
  [owner setValue:[TLRestoreTestDatabase new] forKey:@"agentOrchestrator"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [owner setValue:@1 forKey:@"nextBrowserTabID"];
  [owner loadInitialState];
  return owner;
}

int main(void) {
  @autoreleasepool {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    setenv("TL_WEBKIT_PROFILE_DIR", directory.UTF8String, 1);
    Check([TLBrowserPreferences.profileURL.path isEqual:directory], @"browser preferences use the temporary test profile");
    [NSApplication sharedApplication];
    Method start = class_getInstanceMethod(TLBrowserTabController.class, @selector(startInWindow:));
    Method testStart = class_getInstanceMethod(TLBrowserTabController.class, @selector(testStartInWindow:));
    method_exchangeImplementations(start, testStart);
    NSURL *URL = [[NSURL fileURLWithPath:directory] URLByAppendingPathComponent:@"workspace-session.json"];
    TLWorkspaceSessionStore *store = [[TLWorkspaceSessionStore alloc] initWithURL:URL];
    TLAppStateManager *original = Seed();
    [store observeStateManager:original];
    TLAppStateManager *state = [TLAppStateManager new];
    [store restoreStateManager:state];
    TLRestoreTestController *owner = Load(state);
    [store observeStateManager:state];
    Check(state.snapshot.workspaceTabs.count == 8 && state.snapshot.activeTabKind == TLWorkspaceTabKindBrowser &&
      state.snapshot.activeTabID == 8, @"startup restores all tabs with the browser selected");
    TLWorkspaceTab *browser = [state workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:8];
    TLWorkspaceTabRuntime *runtime = [owner runtimeForTab:browser];
    Check(runtime.contentView && [runtime.featureController isKindOfClass:TLBrowserTabController.class] && browserStarts == 1,
      @"startup rebuilds and starts a browser view for the restored URL");
    TLWorkspaceTab *downloads = [state workspaceTabWithKind:TLWorkspaceTabKindDownloads tabID:0];
    Check([[owner runtimeForTab:downloads].featureController isKindOfClass:TLDownloadsTabController.class],
      @"restored downloads tab rebuilds its native feature controller");
    [owner hydrateWorkspaceTabsFromAppState];
    Check(browserStarts == 1, @"repeated hydration does not start duplicate browsers");
    TLBrowserTabController *controller = (id)runtime.featureController;
    NSURL *navigatedURL = [NSURL URLWithString:@"https://example.com/next"];
    controller.metadataChangedHandler(@"Next page", navigatedURL);
    TLAppStateManager *navigated = [TLAppStateManager new];
    [store restoreStateManager:navigated];
    Check([[navigated workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:8].URL isEqual:navigatedURL],
      @"restored browser navigation is wired to session persistence");
    [owner startNewChatWithModel:@"test-model" focus:NO];
    Check(state.snapshot.activeTabID == -7 && state.snapshot.workspaceTabs.count == 9,
      @"a new draft cannot overwrite a restored draft");
    [owner openBrowserTabWithURL:[NSURL URLWithString:@"https://example.com/new"]];
    Check(state.snapshot.activeTabID == 9 && state.snapshot.workspaceTabs.count == 10 && browserStarts == 2,
      @"a new browser cannot overwrite a restored browser");
    [owner loadChatWithID:42];
    Check([[owner valueForKey:@"activeChat"] chatID] == 42 && state.snapshot.activeTabKind == TLWorkspaceTabKindChat,
      @"restored saved chat loads its database record when selected");
    [owner windowShouldClose:nil];
    Check(state.snapshot.workspaceTabs.count == 10 && state.snapshot.activeTabID == 42,
      @"closing the app window retains tabs and selection");
    TLAppStateManager *reopened = [TLAppStateManager new];
    [store restoreStateManager:reopened];
    TLRestoreTestController *reopenedOwner = Load(reopened);
    Check([[reopenedOwner valueForKey:@"activeChat"] chatID] == 42, @"relaunch selects and loads the saved chat");

    TLAppStateManager *missing = Seed();
    [missing addWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:999 title:@"Deleted chat"
      toolTip:nil URL:nil closeable:YES] activate:YES];
    TLRestoreTestController *missingOwner = Load(missing);
    Check(![missing hasWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:999] && missing.snapshot.workspaceTabs.count == 8 &&
      [missing hasWorkspaceTabWithKind:missing.snapshot.activeTabKind tabID:missing.snapshot.activeTabID],
      @"deleted active chats are removed and a surviving tab is selected");
    Check([[missingOwner valueForKey:@"errorMessage"] length] == 0, @"deleted chat does not break startup");

    TLBrowserPreferences *preferences = TLBrowserPreferences.sharedPreferences;
    Check([preferences saveValue:@"empty" forSetting:[TLBrowserPreferences settingWithID:@"startup"] error:nil], @"set browser startup preference");
    TLAppStateManager *noBrowser = Seed();
    TLRestoreTestController *noBrowserOwner = Load(noBrowser);
    Check(![noBrowser hasWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:8] && noBrowser.snapshot.workspaceTabs.count == 7 &&
      noBrowser.snapshot.activeTabKind == TLWorkspaceTabKindChat && [[noBrowserOwner valueForKey:@"activeChat"] chatID] == -6,
      @"explicit no-browser preference is honored with a valid fallback selection");
    TLAppStateManager *pinnedBrowser = Seed();
    [pinnedBrowser setWorkspaceTabPinned:YES kind:TLWorkspaceTabKindBrowser tabID:8];
    TLRestoreTestController *pinnedOwner = Load(pinnedBrowser);
    Check([pinnedBrowser workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:8].pinned &&
      [pinnedOwner runtimeForTab:[pinnedBrowser workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:8]].contentView != nil,
      @"pinned browser restores even when startup preference skips ordinary browser tabs");
    method_exchangeImplementations(start, testStart);
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    NSLog(@"Workspace restore tests passed");
  }
  return 0;
}
