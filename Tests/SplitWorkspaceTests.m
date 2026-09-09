#import <AppKit/AppKit.h>
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLChatPresentation.h"
#import "TLWorkspaceSplitState.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLSplitWorkspaceView.h"
#import "design_system/TLChromeTabView.h"
#import "WorkspaceTabRuntime.h"
#import "AppStateManager.h"
#import "TLBrowserLinkActions.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]]; }
static TLWorkspaceTab *Tab(NSInteger n) {
  return [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:n title:@"Chat" toolTip:nil URL:nil closeable:YES];
}

@interface TalariaWindowController (SplitTests)
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)size;
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)installEffectiveAppearanceObserver;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)left;
- (void)focusSplitPane:(BOOL)right;
- (void)loadChatWithID:(NSInteger)chatID;
- (void)updateWorkspaceMode;
- (void)updateControlStates;
- (void)applyTheme;
- (void)closeChatTabWithID:(NSInteger)chatID;
- (BOOL)persistActiveDraftChatWithModel:(NSString *)model;
- (void)withChatPresentation:(TLChatPresentation *)presentation perform:(void (^)(void))block;
- (void)scheduleStreamingMessageRender;
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom;
- (void)updateMessageScrollInsets;
- (void)restoreAttachmentDraft:(NSArray<NSURL *> *)URLs prompt:(NSString *)prompt chatID:(NSInteger)chatID;
- (void)openBrowserTab:(id)sender;
- (void)openBrowserTabWithURL:(NSURL *)URL;
- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting;
- (BOOL)performInputSuggestionAtIndex:(NSUInteger)index;
- (void)updateSlashCommandList;
- (void)flushSlashCommandUpdate;
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab;
- (void)openLinkURL:(NSURL *)URL inSplitBesideBrowserTabID:(NSInteger)tabID;
- (void)handleContextLinkURL:(NSURL *)URL destination:(TLBrowserLinkDestination)destination sourceIdentity:(NSString *)identity;
- (void)closeBrowserTab:(id)sender;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller willSelectTab:(TLWorkspaceTab *)tab;
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller dragTab:(TLWorkspaceTab *)tab atWindowPoint:(NSPoint)point;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller endDraggingTab:(TLWorkspaceTab *)tab cancelled:(BOOL)cancelled;
@end

// Real native workspace and action routing, with no VM, network, credentials or user data.
@interface TLSplitTestController : TalariaWindowController
@property (nonatomic, strong) TLChatPresentation *lastScrollPresentation;
@end
@implementation TLSplitTestController
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab {
  NSMutableDictionary *runtimes = [self valueForKey:@"workspaceTabRuntimes"];
  NSString *key = TLWorkspaceTabRuntimeKey(tab.kind, tab.tabID);
  if (!runtimes[key]) runtimes[key] = [TLWorkspaceTabRuntime runtimeWithContentView:[NSView new]
    openAction:@selector(openBrowserTab:) closeAction:@selector(closeBrowserTab:)];
}
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (void)updateMessageScrollInsets {
  self.lastScrollPresentation = [self valueForKey:@"chatPresentation"];
  [super updateMessageScrollInsets];
}
@end
@interface TLSplitTestDatabase : NSObject
@end
@implementation TLSplitTestDatabase
- (NSInteger)currentAgentID { return 0; }
- (TLChatRecord *)createChatWithModel:(NSString *)model supportingModel:(NSString *)supporting error:(NSError **)error {
  TLChatRecord *chat = [TLChatRecord new]; chat.chatID = 123; chat.model = model; chat.title = @"Saved chat"; chat.messages = @[]; return chat;
}
@end

static void TestGrouping(void) {
  TLWorkspaceSplitState *state = [TLWorkspaceSplitState new];
  TLWorkspaceTab *a = Tab(-1), *b = Tab(-2), *c = Tab(-3), *d = Tab(-4);
  [state splitTab:a besideTab:a onLeft:YES]; Check(state.groups.count == 0, @"cannot split a tab with itself");
  [state splitTab:a besideTab:b onLeft:YES];
  TLWorkspaceSplitGroup *group = [state groupForTab:a];
  Check(group == [state groupForTab:b] && [group.leftIdentity isEqual:TLWorkspaceTabIdentity(a)], @"both tabs resolve to the ordered pair");
  group.fraction = 0.7;
  [state splitTab:a besideTab:b onLeft:NO];
  Check([state groupForTab:a].fraction == 0.7 && [[state groupForTab:a].rightIdentity isEqual:TLWorkspaceTabIdentity(a)], @"moving a member preserves the divider preference");
  [state splitTab:c besideTab:d onLeft:YES];
  [state splitTab:a besideTab:c onLeft:YES];
  Check(state.groups.count == 1 && ![state groupForTab:b] && ![state groupForTab:d], @"regrouping releases old companions without closing tabs");
  TLWorkspaceTab *saved = Tab(123); saved.presentationIdentity = TLWorkspaceTabIdentity(a);
  [state reconcileTabs:@[saved,b,c,d]];
  Check([state groupForTab:saved] != nil, @"saving a draft keeps its split");
  [state reconcileTabs:@[saved,b,d]];
  Check(state.groups.count == 0, @"closing either member dissolves its pair");
}
static void TestPointerCancellation(void) {
  TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0,0,180,36)];
  NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(20,20)
    modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
  NSEvent *drag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(80,200)
    modifierFlags:0 timestamp:1 windowNumber:0 context:nil eventNumber:2 clickCount:1 pressure:1];
  [tab mouseDown:down]; [tab mouseDragged:drag];
  Check([[tab valueForKey:@"didDrag"] boolValue], @"pointer movement begins the drag");
  [tab cancelPointerDrag]; [tab mouseDragged:drag];
  Check(![[tab valueForKey:@"didDrag"] boolValue], @"Escape prevents held-pointer movement from restarting a cancelled drag");
  [tab mouseDown:down]; [tab mouseDragged:drag];
  Check([[tab valueForKey:@"didDrag"] boolValue], @"a fresh pointer press can drag after cancellation");
  [tab finishPointerDrag];
}
static void TestPaneGeometry(void) {
  TLSplitWorkspaceView *view = [[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
  NSLayoutConstraint *widthConstraint = [view.widthAnchor constraintEqualToConstant:1000];
  widthConstraint.active = YES;
  [view.heightAnchor constraintEqualToConstant:600].active = YES;
  view.split = YES; view.leftTitle = @"Research"; view.rightTitle = @"Notes";
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    view.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *width in @[@200,@480,@1000,@1800]) {
      widthConstraint.constant = width.doubleValue;
      view.frame = NSMakeRect(0,0,width.doubleValue,600); view.fraction = 0.95; [view layoutSubtreeIfNeeded];
      Check(NSWidth(view.leftHost.frame) > 0 && NSWidth(view.rightHost.frame) > 0, @"both panes survive narrow widths");
      Check(NSMaxX(view.rightHost.frame) <= width.doubleValue + 0.01, @"pane stays inside the window at all widths");
      Check(NSMaxX(view.leftHost.frame) < NSMinX(view.rightHost.frame), @"divider separates nonoverlapping panes");
      Check(NSMaxY(view.leftHost.frame) <= NSHeight(view.bounds) - view.palette.tabHeight + 0.01,
        @"pane content stays below its header");
    }
    widthConstraint.constant = 1000;
    view.frame = NSMakeRect(0,0,1000,600); view.fraction = 0.5; [view layoutSubtreeIfNeeded];
    Check([view dropSideAtPoint:NSMakePoint(100,300)] == TLSplitDropSideLeft, @"left edge selects left split");
    Check([view dropSideAtPoint:NSMakePoint(900,300)] == TLSplitDropSideRight, @"right edge selects right split");
    Check([view dropSideAtPoint:NSMakePoint(500,300)] == TLSplitDropSideNone && [view dropSideAtPoint:NSMakePoint(-1,300)] == TLSplitDropSideNone, @"center and outside are safe cancellation areas");
    [view showDropSide:TLSplitDropSideLeft title:@"Notes" point:NSMakePoint(100,300)];
    [view layoutSubtreeIfNeeded];
    NSView *preview = [view valueForKey:@"preview"];
    Check(!preview.hidden && [preview hitTest:NSMakePoint(100,300)] == nil, @"preview does not intercept the drag");
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-split-light.png" : @"/tmp/talaria-split-dark.png" atomically:YES];
    Check(CGColorEqualToColor(view.layer.backgroundColor, view.palette.tabBackground.CGColor), @"split surface follows the current theme");
    [view clearDropPreview]; Check(preview.hidden, @"cancellation removes the preview");
  }
  view.split = NO; [view layoutSubtreeIfNeeded];
  Check(NSWidth(view.leftHost.frame) == 1000 && view.rightHost.hidden, @"unsplit restores full content width");
}

static void TestChatInputNavigation(TLSplitTestController *owner, TLAppStateManager *state) {
  [owner setValue:@1000 forKey:@"nextBrowserTabID"];
  NSURL *URL = [NSURL URLWithString:@"https://www.example.com/page?q=hello#section"];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *neighbor = state.snapshot.workspaceTabs.lastObject;
  TLChatPresentation *neighborPresentation = [owner valueForKey:@"chatPresentation"];
  neighborPresentation.promptTextView.string = @"Keep this draft";
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *empty = state.snapshot.workspaceTabs.lastObject;
  TLChatPresentation *retired = [owner valueForKey:@"chatPresentation"];
  [state moveWorkspaceTabWithKind:empty.kind tabID:empty.tabID toIndex:1];
  [owner splitTab:empty besideTab:neighbor onLeft:YES];
  [owner focusSplitPane:NO];
  TLWorkspaceSplitState *splits = [owner valueForKey:@"splitState"];
  [splits groupForTab:empty].fraction = 0.6;
  NSUInteger count = state.snapshot.workspaceTabs.count;
  retired.promptTextView.string = URL.absoluteString;
  [owner sendMessage:nil allowAutomaticRouting:YES]; Drain();
  TLWorkspaceTab *browser = state.snapshot.workspaceTabs[1];
  Check(state.snapshot.workspaceTabs.count == count && browser.kind == TLWorkspaceTabKindBrowser &&
    [browser.URL isEqual:URL] && state.snapshot.activeTabID == browser.tabID,
    @"Enter replaces the empty chat at the same index and preserves the full URL");
  Check([TLWorkspaceTabIdentity(browser) isEqual:TLWorkspaceTabIdentity(empty)] &&
    [[splits groupForTab:browser].leftIdentity isEqual:TLWorkspaceTabIdentity(browser)] &&
    [[splits groupForTab:browser].rightIdentity isEqual:TLWorkspaceTabIdentity(neighbor)] &&
    [splits groupForTab:browser].fraction == 0.6, @"conversion preserves split identity, side and divider");
  TLSplitWorkspaceView *workspace = [owner valueForKey:@"splitWorkspace"];
  TLWorkspaceTabRuntime *runtime = [owner valueForKey:@"workspaceTabRuntimes"][TLWorkspaceTabRuntimeKey(browser.kind,browser.tabID)];
  Check(runtime.contentView.superview == workspace.leftHost &&
    neighborPresentation.chatWorkspace.superview == workspace.rightHost &&
    [neighborPresentation.promptTextView.string isEqual:@"Keep this draft"],
    @"the browser replaces only its pane and retains the neighboring draft");
  Check(![state workspaceTabWithKind:empty.kind tabID:empty.tabID] && !retired.chatWorkspace.superview &&
    ![owner valueForKey:@"workspaceTabRuntimes"][TLWorkspaceTabRuntimeKey(empty.kind,empty.tabID)] &&
    ![owner valueForKey:@"modelDraftChats"][@(empty.tabID)], @"conversion retires the empty draft and runtime");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  Check(![owner valueForKey:@"modelDraftChats"][@(empty.tabID)], @"opening another chat does not resurrect the converted draft");
  empty = state.snapshot.workspaceTabs.lastObject;
  TLChatPresentation *presentation = [owner valueForKey:@"chatPresentation"];
  presentation.promptTextView.string = URL.absoluteString;
  [owner updateSlashCommandList]; [owner flushSlashCommandUpdate];
  count = state.snapshot.workspaceTabs.count;
  Check([owner performInputSuggestionAtIndex:0], @"Open suggestion accepts the URL"); Drain();
  browser = state.snapshot.workspaceTabs.lastObject;
  Check(state.snapshot.workspaceTabs.count == count && browser.kind == TLWorkspaceTabKindBrowser &&
    [browser.URL isEqual:URL] && [TLWorkspaceTabIdentity(browser) isEqual:TLWorkspaceTabIdentity(empty)],
    @"Open suggestion also converts an empty chat without adding a tab");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *nonempty = state.snapshot.workspaceTabs.lastObject;
  presentation = [owner valueForKey:@"chatPresentation"];
  [presentation.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Keep this conversation" thinking:nil]];
  presentation.promptTextView.string = URL.absoluteString;
  count = state.snapshot.workspaceTabs.count;
  [owner sendMessage:nil allowAutomaticRouting:YES]; Drain();
  Check(state.snapshot.workspaceTabs.count == count + 1 &&
    [state workspaceTabWithKind:nonempty.kind tabID:nonempty.tabID] && presentation.messages.count == 1,
    @"URL submission preserves chats that already contain messages");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  empty = state.snapshot.workspaceTabs.lastObject;
  count = state.snapshot.workspaceTabs.count;
  [owner openBrowserTabWithURL:URL]; Drain();
  Check(state.snapshot.workspaceTabs.count == count + 1 && [state workspaceTabWithKind:empty.kind tabID:empty.tabID],
    @"explicit new-tab actions still retain an empty chat");
}

static void TestRealWorkspace(void) {
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,700)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLSplitTestController *owner = [[TLSplitTestController alloc] initWithWindow:window];
  window.delegate = (id<NSWindowDelegate>)owner;
  window.minSize = NSMakeSize(200,400); window.contentMinSize = NSMakeSize(200,400);
  window.maxSize = NSMakeSize(100000,100000); window.contentMaxSize = NSMakeSize(100000,100000);
  TLAppStateManager *state = [TLAppStateManager new];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:[TLSplitTestDatabase new] forKey:@"database"];
  TLAppSettings *settings = [TLAppSettings defaultSettings]; settings.theme = TLThemePreferenceLight;
  [owner setValue:settings forKey:@"settings"];
  [owner setValue:[TLThemePalette paletteForPreference:settings.theme] forKey:@"palette"];
  [owner setValue:[NSMutableArray array] forKey:@"agents"];
  [owner setValue:[NSMutableArray array] forKey:@"chats"];
  [owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [owner buildInterface]; [owner installAppStateBindings];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *a = state.snapshot.workspaceTabs.lastObject;
  TLChatPresentation *pa = [owner valueForKey:@"chatPresentation"];
  pa.promptTextView.string = @"Unsent left draft";
  pa.messageInput.attachmentURLs = @[[NSURL fileURLWithPath:@"/tmp/left.txt"]];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *b = state.snapshot.workspaceTabs.lastObject;
  TLChatPresentation *pb = [owner valueForKey:@"chatPresentation"];
  pb.promptTextView.string = @"Unsent right draft";
  Check(pa != pb && pa.chatWorkspace != pb.chatWorkspace && pa.promptTextView != pb.promptTextView, @"chats own independent live views and composers");
  [owner splitTab:a besideTab:b onLeft:YES]; Drain();
  TLSplitWorkspaceView *workspace = [owner valueForKey:@"splitWorkspace"];
  TLWorkspaceSplitState *splits = [owner valueForKey:@"splitState"];
  Check(workspace.split && pa.chatWorkspace.superview == workspace.leftHost && pb.chatWorkspace.superview == workspace.rightHost, @"chat pair mounts both real workspaces");
  Check(!pa.chatWorkspace.hidden && !pb.chatWorkspace.hidden, @"both chats remain visible");
  Check(fabs(NSWidth(pa.chatWorkspace.frame) - NSWidth(workspace.leftHost.bounds)) < 1 &&
    fabs(NSWidth(pb.chatWorkspace.frame) - NSWidth(workspace.rightHost.bounds)) < 1, @"each transcript fills its pane");
  Check(fabs(NSMidX(pa.messageInput.frame) - NSMidX(pa.chatWorkspace.bounds)) < 1, @"composer stays centered inside its pane");
  Check(pa.promptTextView.editable, @"visible chat composer is editable");
  [window makeFirstResponder:pa.promptTextView];
  [owner updateWorkspaceMode];
  Check(window.firstResponder == pa.promptTextView, @"metadata refresh keeps the focused editor attached");
  [owner focusSplitPane:YES];
  Check(state.snapshot.activeTabID == b.tabID && [owner valueForKey:@"chatPresentation"] == pb, @"pane click routes shortcuts and composer actions to its chat");
  Check([pa.promptTextView.string isEqual:@"Unsent left draft"] && [pb.promptTextView.string isEqual:@"Unsent right draft"] && pa.messageInput.attachmentURLs.count == 1, @"focus changes preserve both drafts and attachments");
  pa.messages = [NSMutableArray arrayWithObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Background transcript" thinking:nil]];
  [owner withChatPresentation:pa perform:^{ [owner scheduleStreamingMessageRender]; }]; Drain();
  Check([owner valueForKey:@"chatPresentation"] == pb && state.snapshot.activeTabID == b.tabID && pa.renderedMessages.count == 1, @"background render targets the originating pane without changing focus");
  [owner withChatPresentation:pa perform:^{ [owner renderMessagesScrollingToBottom:NO]; }];
  owner.lastScrollPresentation = nil; Drain();
  Check(owner.lastScrollPresentation == pa && [owner valueForKey:@"chatPresentation"] == pb,
    @"deferred scroll layout belongs to the rendered chat after focus changes");
  [owner restoreAttachmentDraft:@[] prompt:@"Restored left draft" chatID:a.tabID];
  Check([pa.promptTextView.string isEqual:@"Restored left draft"] && [pb.promptTextView.string isEqual:@"Unsent right draft"],
    @"failed background attachment preparation restores its own visible composer");
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *c = state.snapshot.workspaceTabs.lastObject;
  Check(!workspace.split, @"unrelated tab uses full width");
  [pa.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Update while hidden" thinking:nil]];
  [owner loadChatWithID:a.tabID]; Check(workspace.split && [splits groupForTab:b], @"selecting either member restores its pair");
  Check(pa.renderedMessages.count == 2, @"returning to a cached chat displays updates received while hidden");
  workspace.swapPanes();
  Check(pa.chatWorkspace.superview == workspace.rightHost, @"swap moves existing views without recreating content");
  [owner focusSplitPane:YES];
  Check([owner persistActiveDraftChatWithModel:@"test-model"], @"draft can be saved while split");
  Drain();
  TLWorkspaceTab *saved = [state workspaceTabWithKind:TLWorkspaceTabKindChat tabID:123];
  Check([splits groupForTab:saved] && [owner valueForKey:@"chatPresentation"] == pa, @"saving preserves pair and live chat presentation");
  [owner loadChatWithID:c.tabID];
  [owner closeChatTabWithID:b.tabID]; Drain();
  Check(state.snapshot.activeTabID == c.tabID && !workspace.split, @"closing a background pair does not steal focus");
  [owner splitTab:saved besideTab:c onLeft:YES];
  [owner closeChatTabWithID:123]; Drain();
  Check(state.snapshot.activeTabID == c.tabID && !workspace.split, @"closing the focused half expands and focuses its companion");
  // A cancelled drag never changes tab order or commits a split.
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *d = state.snapshot.workspaceTabs.lastObject;
  [owner loadChatWithID:c.tabID];
  [owner workspaceTabsController:nil willSelectTab:d]; [owner loadChatWithID:d.tabID];
  NSPoint drop = [workspace convertPoint:NSMakePoint(50,200) toView:nil];
  [owner workspaceTabsController:nil dragTab:d atWindowPoint:drop];
  Check(![[workspace valueForKey:@"preview"] isHidden], @"dragging from tabs shows a split preview");
  [owner workspaceTabsController:nil endDraggingTab:d cancelled:YES];
  Check(!workspace.split && state.snapshot.activeTabID == c.tabID, @"cancel restores the prior tab without grouping");
  [owner workspaceTabsController:nil willSelectTab:d]; [owner loadChatWithID:d.tabID];
  [owner workspaceTabsController:nil dragTab:d atWindowPoint:drop];
  [owner workspaceTabsController:nil endDraggingTab:d cancelled:NO];
  Check(workspace.split && [[splits groupForTab:d].leftIdentity isEqual:TLWorkspaceTabIdentity(d)], @"dropping commits the previewed left split");
  NSAppearance *originalAppearance = NSApp.appearance;
  [owner installEffectiveAppearanceObserver];
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    NSApp.appearance = [NSAppearance appearanceNamed:theme.integerValue == TLThemePreferenceDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    Drain();
    Check(window.appearance == nil, @"the app window inherits the system color scheme without a manual override");
    Check(workspace.palette.dark == (theme.integerValue == TLThemePreferenceDark), @"system appearance changes reach existing split chrome despite a legacy theme preference");
    for (TLChatPresentation *presentation in [[owner valueForKey:@"chatPresentations"] allValues])
      Check(presentation.messageInput.palette.dark == workspace.palette.dark, @"theme reaches every cached composer");
  }
  NSApp.appearance = originalAppearance; Drain();
  [[[owner valueForKey:@"workspaceTabsController"] transitionCoordinator] finishAllTransitions];
  Drain();
  for (NSNumber *width in @[@200,@500,@1100]) {
    [owner windowWillResize:window toSize:NSMakeSize(width.doubleValue,700)];
    [window setContentSize:NSMakeSize(width.doubleValue,700)]; [window.contentView layoutSubtreeIfNeeded]; Drain();
    Check(NSWidth(window.contentView.bounds) == width.doubleValue, [NSString stringWithFormat:@"split preserves window width %@ (actual %g)", width, NSWidth(window.contentView.bounds)]);
  }
  workspace.expandPane(YES); Check(!workspace.split && state.snapshot.workspaceTabs.count == 2, @"expand retains both tabs");
  TLWorkspaceTab *browser = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:99 title:@"Browser" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
  TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[NSView new] openAction:@selector(openBrowserTab:) closeAction:@selector(closeBrowserTab:)];
  [[owner valueForKey:@"workspaceTabRuntimes"] setObject:runtime forKey:TLWorkspaceTabRuntimeKey(browser.kind,browser.tabID)];
  [state addWorkspaceTab:browser activate:YES]; Drain();
  [owner splitTab:browser besideTab:c onLeft:YES]; Drain();
  [owner focusSplitPane:YES]; Drain();
  TLChatPresentation *chat = [owner valueForKey:@"chatPresentation"];
  Check(chat.promptTextView.editable && [window makeFirstResponder:chat.promptTextView], @"chat beside browser accepts keyboard focus");
  NSPoint editorPoint = [chat.promptTextView convertPoint:NSMakePoint(NSMidX(chat.promptTextView.bounds),NSMidY(chat.promptTextView.bounds)) toView:window.contentView.superview];
  NSView *hit = [window.contentView hitTest:editorPoint];
  Check(hit == chat.promptTextView || [hit isDescendantOf:chat.promptTextView], [NSString stringWithFormat:@"pane editor receives pointer hit (got %@)",hit.class]);
  NSUInteger beforeSplitLink = state.snapshot.workspaceTabs.count;
  NSURL *linkedURL = [NSURL URLWithString:@"https://example.com/linked-page"];
  [owner openLinkURL:linkedURL inSplitBesideBrowserTabID:browser.tabID]; Drain();
  TLWorkspaceTab *linked = state.snapshot.workspaceTabs.lastObject;
  TLWorkspaceSplitGroup *linkedGroup = [splits groupForTab:browser];
  Check(state.snapshot.workspaceTabs.count == beforeSplitLink + 1 && [linked.URL isEqual:linkedURL], @"split link creates a browser tab for the clicked URL");
  Check([linkedGroup.leftIdentity isEqual:TLWorkspaceTabIdentity(browser)] &&
    [linkedGroup.rightIdentity isEqual:TLWorkspaceTabIdentity(linked)], @"split link uses its source browser even when the other pane was focused");
  Check(state.snapshot.activeTabID == linked.tabID && workspace.rightFocused, @"split link focuses the new right pane");
  Check(![splits groupForTab:c] && [[state.snapshot.workspaceTabs valueForKey:@"tabID"] containsObject:@(c.tabID)], @"replacing a split retains the previous companion tab");
  [owner openLinkURL:linkedURL inSplitBesideBrowserTabID:99999];
  [owner openLinkURL:[NSURL URLWithString:@"javascript:alert(1)"] inSplitBesideBrowserTabID:browser.tabID];
  Check(state.snapshot.workspaceTabs.count == beforeSplitLink + 1, @"closed sources and unsupported URLs cannot create split tabs");
  [owner handleContextLinkURL:linkedURL destination:TLBrowserLinkSplitView sourceIdentity:TLWorkspaceTabIdentity(c)]; Drain();
  TLWorkspaceTab *chatLink = state.snapshot.workspaceTabs.lastObject;
  Check([[splits groupForTab:c].rightIdentity isEqual:TLWorkspaceTabIdentity(chatLink)] &&
    [[splits groupForTab:c].leftIdentity isEqual:TLWorkspaceTabIdentity(c)], @"chat answers use the same split routing beside their originating chat");
  TestChatInputNavigation(owner, state);
  [window close];
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TestGrouping(); TestPointerCancellation(); TestPaneGeometry(); TestRealWorkspace();
  NSLog(@"SplitWorkspaceTests passed");
} return 0; }
