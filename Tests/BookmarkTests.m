#import <AppKit/AppKit.h>
#import "Database.h"
#import "TLWorkspaceTabsController.h"
#import "WorkspaceTabRuntime.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLChromeTabView.h"
#import "DatabaseMigrator.h"
#import "SQLiteConnection.h"
#import "TalariaWindowController.h"
#import "TLBookmarkEditorController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLEmojiPicker.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLButton.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface TLBookmarkEditorController (BookmarkTests)
- (void)controlTextDidChange:(NSNotification *)notification;
@end

@interface TalariaWindowController (BookmarkTests)
- (void)reloadBookmarks;
- (NSMenu *)menuForSidebarBookmark:(TLBookmark *)bookmark button:(TLSidebarShortcutButton *)button;
- (void)openBookmarkURLInNewWindow:(NSURL *)URL;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)source onLeft:(BOOL)left;
- (void)openSidebarBookmark:(TLSidebarShortcutButton *)button;
- (void)removeBookmark:(NSMenuItem *)item;
- (TLBookmark *)bookmarkForCurrentPage;
- (TLBookmark *)bookmarkForTab:(TLWorkspaceTab *)tab;
- (void)showBookmarkEditorForTab:(TLWorkspaceTab *)tab;
- (NSMenu *)workspaceTabsController:(TLWorkspaceTabsController *)controller contextMenuForTab:(TLWorkspaceTab *)tab;
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller dragTab:(TLWorkspaceTab *)tab atWindowPoint:(NSPoint)point;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller endDraggingTab:(TLWorkspaceTab *)tab cancelled:(BOOL)cancelled;
- (void)showAddBookmark:(id)sender;
@end
@interface TLBookmarkTestController : TalariaWindowController
@property (nonatomic, strong) NSURL *openedURL;
@property (nonatomic) NSInteger openedChatID;
@end
@implementation TLBookmarkTestController
- (void)showChatWorkspace {}
- (void)reloadWorkspaceTabs {}
- (void)updateControlStates {}
- (void)openBrowserTabWithURL:(NSURL *)URL { self.openedURL = URL; }
- (void)openChatTabWithID:(NSInteger)chatID { self.openedChatID = chatID; }
@end

// Exercise the real drag routing without opening a popover or changing focus.
@interface TLBookmarkDropTestController : TLBookmarkTestController
@property (nonatomic, strong) TLWorkspaceTab *editorTab;
@end
@implementation TLBookmarkDropTestController
- (void)showBookmarkEditorForTab:(TLWorkspaceTab *)tab { self.editorTab = tab; }
- (void)focusWorkspaceTab:(TLWorkspaceTab *)tab {}
@end

static void TestBookmarkDrop(void) {
  TLBookmarkDropTestController *owner = [[TLBookmarkDropTestController alloc] initWithWindow:nil];
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
  NSView *topbar = [[NSView alloc] initWithFrame:NSMakeRect(0,360,600,40)];
  TLSidebarShortcutsView *sidebar = [[TLSidebarShortcutsView alloc] initWithFrame:NSMakeRect(0,280,180,30)];
  [root addSubview:topbar]; [root addSubview:sidebar];
  [owner setValue:topbar forKey:@"topbar"];
  [owner setValue:sidebar forKey:@"sidebarShortcutsView"];
  [owner setValue:@YES forKey:@"sidebarVisible"];
  TLWorkspaceTab *chat = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:-8 title:@"Draft" toolTip:nil URL:nil closeable:YES];
  TLWorkspaceTab *page = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:8 title:@"Page" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
  for (TLWorkspaceTab *tab in @[chat,page]) {
    Check([owner workspaceTabsController:nil dragTab:tab atWindowPoint:NSMakePoint(80,295)] && sidebar.dropTargeted, @"empty bookmark header accepts chat and webpage drags");
    Check(!owner.editorTab, @"hover alone does not open the editor");
    [owner workspaceTabsController:nil endDraggingTab:tab cancelled:NO];
    Check(owner.editorTab == tab && !sidebar.dropTargeted, @"drop opens the editor for the dragged tab and clears feedback");
    owner.editorTab = nil;
    [owner workspaceTabsController:nil dragTab:tab atWindowPoint:NSMakePoint(80,295)];
    [owner workspaceTabsController:nil endDraggingTab:tab cancelled:YES];
    Check(!owner.editorTab && !sidebar.dropTargeted, @"Escape cancels bookmark drop");
    [owner workspaceTabsController:nil dragTab:tab atWindowPoint:NSMakePoint(80,295)];
    [owner workspaceTabsController:nil dragTab:tab atWindowPoint:NSMakePoint(300,380)];
    [owner workspaceTabsController:nil endDraggingTab:tab cancelled:NO];
    Check(!owner.editorTab && !sidebar.dropTargeted, @"leaving Bookmarks before release does not open the editor");
  }
  [owner setValue:@NO forKey:@"sidebarVisible"];
  [owner workspaceTabsController:nil dragTab:page atWindowPoint:NSMakePoint(80,295)];
  Check(!sidebar.dropTargeted, @"collapsed sidebar cannot accept a bookmark drop");
}

@interface TLTabReloadProbe : TLFeatureTabController
@property (nonatomic) NSUInteger reloads;
@end
@implementation TLTabReloadProbe
- (void)reloadBrowser:(id)sender { self.reloads++; }
@end

@interface TLBookmarkMenuTabView : TLChromeTabView
@end
@implementation TLBookmarkMenuTabView
// Menu composition is independent of the user's live mouse state.
- (BOOL)canOpenTabContextMenu { return YES; }
@end

static void TestTabMenu(TLBookmarkTestController *owner, TLAppStateManager *state, TLWorkspaceTab *browser, TLWorkspaceTab *chat) {
  TLWorkspaceTabsController *tabs = [[TLWorkspaceTabsController alloc] initWithTabStack:[NSStackView new] target:owner delegate:(id)owner palette:[owner valueForKey:@"palette"]];
  TLChromeTabView *view = [TLBookmarkMenuTabView new]; view.dragDelegate = (id)tabs; view.closeable = YES; view.canCloseOtherTabs = YES;
  for (TLWorkspaceTab *tab in @[browser,chat]) {
    view.representedObject = tab;
    NSMenu *menu = [view menuForEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]];
    NSMutableArray *labels = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) [labels addObject:item.separatorItem ? @"---" : item.title];
    NSMutableArray *expected = [NSMutableArray array];
    if (tab.kind == TLWorkspaceTabKindBrowser) [expected addObject:@"Reload"];
    [expected addObjectsFromArray:@[@"Pin tab", @"---", @"Open in Split View on Left", @"Open in Split View on Right", @"---", @"Add to bookmarks", @"---", @"Close", @"Close Other Tabs"]];
    Check([labels isEqual:expected], @"complete tab context menu follows requested order and separators");
    NSInteger selectedID = state.snapshot.activeTabID;
    NSMenuItem *pin = [menu itemWithTitle:@"Pin tab"];
    [NSApp sendAction:pin.action to:pin.target from:pin];
    TLWorkspaceTab *pinned = [state workspaceTabWithKind:tab.kind tabID:tab.tabID];
    Check(pinned.pinned && state.snapshot.activeTabID == selectedID, @"pin menu changes the targeted tab without selecting it");
    NSMenuItem *unpin = [[owner workspaceTabsController:nil contextMenuForTab:pinned] itemWithTitle:@"Unpin tab"];
    Check(unpin != nil, @"pin menu changes to Unpin tab");
    [NSApp sendAction:unpin.action to:unpin.target from:unpin];
    Check(![state workspaceTabWithKind:tab.kind tabID:tab.tabID].pinned, @"Unpin menu clears the flag");
  }
  TLTabReloadProbe *probe = [TLTabReloadProbe new];
  TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime new]; runtime.featureController = probe;
  [owner setValue:[NSMutableDictionary dictionaryWithObject:runtime forKey:TLWorkspaceTabRuntimeKey(browser.kind,browser.tabID)] forKey:@"workspaceTabRuntimes"];
  NSInteger activeID = state.snapshot.activeTabID;
  NSMenuItem *reload = [[owner workspaceTabsController:nil contextMenuForTab:browser] itemWithTitle:@"Reload"];
  [NSApp sendAction:reload.action to:reload.target from:reload];
  Check(probe.reloads == 1 && state.snapshot.activeTabID == activeID, @"Reload dispatches to the target browser without changing selection");
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
}

@interface TLBookmarkMenuTestController : TLBookmarkTestController
@property (nonatomic, strong) NSURL *openedWindowURL;
@property (nonatomic, strong) TLWorkspaceTab *splitSource;
@property (nonatomic, strong) TLWorkspaceTab *splitDestination;
@end
@implementation TLBookmarkMenuTestController
- (void)openBrowserTabWithURL:(NSURL *)URL {
  [super openBrowserTabWithURL:URL];
  [[self valueForKey:@"appStateManager"] upsertWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:123 title:@"Opened bookmark" toolTip:nil URL:URL closeable:YES] activate:YES];
}
- (void)openChatTabWithID:(NSInteger)chatID {
  [super openChatTabWithID:chatID];
  [[self valueForKey:@"appStateManager"] upsertWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:chatID title:@"Opened conversation" toolTip:nil URL:nil closeable:YES] activate:YES];
}
- (void)openBookmarkURLInNewWindow:(NSURL *)URL { self.openedWindowURL = URL; }
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)source onLeft:(BOOL)left {
  self.splitDestination = tab; self.splitSource = source;
}
@end

static void InvokeBookmarkItem(NSMenu *menu, NSString *title) {
  NSMenuItem *item = [menu itemWithTitle:title];
  Check(item && item.enabled, [@"bookmark menu enables " stringByAppendingString:title]);
  [NSApp sendAction:item.action to:item.target from:item];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

static void TestSidebarBookmarkMenus(TLBookmark *website, TLBookmark *conversation) {
  TLBookmarkMenuTestController *owner = [[TLBookmarkMenuTestController alloc] initWithWindow:nil];
  TLAppStateManager *state = [TLAppStateManager new]; [owner setValue:state forKey:@"appStateManager"];
  TLSidebarShortcutButton *button = [TLSidebarShortcutButton new];
  NSMenu *menu = [owner menuForSidebarBookmark:website button:button];
  NSMutableArray *labels = [NSMutableArray array];
  for (NSMenuItem *item in menu.itemArray) [labels addObject:item.separatorItem ? @"---" : item.title];
  Check([labels isEqual:@[@"Open Link in New Tab", @"Open Link in New Window", @"Open Link in Split View", @"---", @"Copy Link", @"---", @"Share…", @"---", @"Delete bookmark"]], @"sidebar website menu matches requested link actions and delete");
  Check([menu itemWithTitle:@"Copy Link"].enabled && [menu itemWithTitle:@"Share…"].enabled, @"copy and native sharing are available");
  InvokeBookmarkItem(menu, @"Open Link in New Tab");
  Check([owner.openedURL isEqual:website.URL], @"new-tab action opens the bookmarked URL even in an empty workspace");
  InvokeBookmarkItem(menu, @"Open Link in New Window");
  Check([owner.openedWindowURL isEqual:website.URL], @"new-window action targets the bookmarked URL");
  TLWorkspaceTab *source = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:42 title:@"Current chat" toolTip:nil URL:nil closeable:YES];
  [state addWorkspaceTab:source activate:YES];
  InvokeBookmarkItem(menu, @"Open Link in Split View");
  Check(owner.splitSource.tabID == 42 && [owner.splitDestination.URL isEqual:website.URL], @"split uses the page active at invocation, not menu construction");
  NSMenu *chatMenu = [owner menuForSidebarBookmark:conversation button:button];
  InvokeBookmarkItem(chatMenu, @"Open Conversation in New Tab");
  Check(owner.openedChatID == conversation.chatID, @"conversation bookmark opens the saved chat");
  [state activateWorkspaceTabKind:source.kind tabID:source.tabID];
  InvokeBookmarkItem(chatMenu, @"Open Conversation in Split View");
  Check(owner.splitSource.tabID == 42 && owner.splitDestination.tabID == conversation.chatID, @"conversation bookmark splits with the current tab");
  Check([chatMenu itemWithTitle:@"Delete bookmark"].tag == conversation.bookmarkID && ![chatMenu itemWithTitle:@"Copy Link"], @"conversation has delete without inventing a URL");
  __weak TLSidebarShortcutButton *releasedButton;
  @autoreleasepool {
    TLSidebarShortcutButton *temporary = [TLSidebarShortcutButton new]; releasedButton = temporary;
    temporary.menu = [owner menuForSidebarBookmark:website button:temporary];
  }
  Check(!releasedButton, @"bookmark menus do not retain removed sidebar buttons through Share");
}

static void SavePreview(NSView *view, NSString *name) {
  [view layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:[@"build/" stringByAppendingString:name] atomically:YES];
}

static void TestEditor(TLBookmark *bookmark) {
  TLBookmarkEditorController *editor = [[TLBookmarkEditorController alloc] initWithBookmark:bookmark
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 236)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = editor.view;
  [window setContentSize:editor.preferredContentSize];
  NSTextField *name = [editor valueForKey:@"nameField"];
  NSTextField *URL = [editor valueForKey:@"URLField"];
  TLThemedButton *save = [editor valueForKey:@"saveButton"];
  TLThemedButton *cancel = [editor valueForKey:@"cancelButton"];
  Check([name.stringValue isEqual:bookmark.name], @"name is prefilled");
  Check(save.enabled, @"prefilled bookmark is ready to save");
  TLEmojiPicker *picker = [editor valueForKey:@"emojiPicker"];
  if (bookmark.chatID) {
    Check(!URL && picker && [picker.emoji isEqual:bookmark.emoji], @"conversation has preselected emoji and no URL input");
    Check([[[editor valueForKey:@"destinationLabel"] stringValue] isEqual:@"conversation"], @"conversation destination label");
    [picker insertText:@"🌻" replacementRange:NSMakeRange(NSNotFound, 0)];
    Check([picker.emoji isEqual:@"🌻"], @"native emoji input updates selection");
  } else {
    Check(!picker && [URL.stringValue isEqual:bookmark.URL.absoluteString], @"website URL prefilled without emoji picker");
    URL.stringValue = @"https://";
    [editor controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:URL]];
    Check(!save.enabled, @"invalid URL cannot save");
    URL.stringValue = @"example.org/new";
  }
  name.stringValue = @"   ";
  [editor controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:name]];
  Check(!save.enabled, @"empty name cannot save");
  name.stringValue = @"My bookmark";
  [editor controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:name]];
  __block NSUInteger saves = 0, closes = 0;
  editor.saveHandler = ^BOOL(TLBookmark *entry, NSError **error) {
    saves++;
    if (saves == 1) { *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not save bookmark. Try again."}]; return NO; }
    Check([entry.name isEqual:@"My bookmark"], @"edited name passed to persistence");
    Check(entry.chatID ? [entry.emoji isEqual:@"🌻"] : [entry.URL.absoluteString isEqual:@"https://example.org/new"], @"edited destination/emoji saved");
    return YES;
  };
  editor.closeHandler = ^{ closes++; };
  [save performClick:nil];
  Check(saves == 1 && closes == 0 && ![[editor valueForKey:@"errorLabel"] isHidden], @"save errors keep the editor open");
  [save performClick:nil];
  Check(saves == 2 && closes == 1, @"successful save closes editor");
  [cancel performClick:nil];
  Check(saves == 2 && closes == 2, @"cancel never saves");
  [editor controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:name]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [editor applyPalette:palette];
    Check(!bookmark.chatID || [[[editor valueForKey:@"destinationLabel"] textColor] isEqual:palette.textMuted], @"conversation label tracks muted theme color");
    [window setContentSize:editor.preferredContentSize];
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSWidth(name.bounds) > 120, @"name field keeps a usable width");
    for (TLThemedButton *button in @[save, cancel]) {
      Check(NSWidth(button.bounds) >= button.intrinsicContentSize.width, @"action labels fit without clipping");
      NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:ceil(NSWidth(button.bounds)) pixelsHigh:ceil(NSHeight(button.bounds)) bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
      [NSGraphicsContext saveGraphicsState];
      NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
      [button.cell drawWithFrame:button.bounds inView:button];
      [NSGraphicsContext restoreGraphicsState];
      NSColor *expected = [(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface) colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      NSColor *actual = [[bitmap colorAtX:10 y:bitmap.pixelsHigh/2] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      Check(fabs(actual.redComponent - expected.redComponent) < 0.04, @"editor buttons render their paired theme surface");
    }
    SavePreview(editor.view, [NSString stringWithFormat:@"bookmark-%@-%@.png", bookmark.chatID ? @"chat" : @"website", theme]);
  }
  [window close];
}

static void TestPopover(TLBookmarkTestController *owner, TLAppStateManager *state, TLDatabase *database) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLSidebarShortcutsView *sidebar = [owner valueForKey:@"sidebarShortcutsView"];
  sidebar.translatesAutoresizingMaskIntoConstraints = YES;
  sidebar.frame = NSMakeRect(0, 200, 160, 80);
  [window.contentView addSubview:sidebar];
  [owner setWindow:window];
  [window.contentView layoutSubtreeIfNeeded];
  [window makeKeyAndOrderFront:nil];
  TLChatRecord *draft = [TLChatRecord new]; draft.chatID = -1; draft.title = @"New chat"; draft.icon = @"🧭"; draft.model = @"test";
  [owner setValue:draft forKey:@"activeChat"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"chatPresentations"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:-1 title:draft.title toolTip:nil URL:nil closeable:YES];
  [state addWorkspaceTab:tab activate:YES];
  TLWorkspaceTab *page = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:98 title:@"Background page" toolTip:nil URL:[NSURL URLWithString:@"https://example.org/background"] closeable:YES];
  [state addWorkspaceTab:page activate:NO];
  NSMenuItem *add = [[owner workspaceTabsController:nil contextMenuForTab:page] itemWithTitle:@"Add to bookmarks"];
  [NSApp sendAction:add.action to:add.target from:add];
  NSPopover *backgroundPopover = [owner valueForKey:@"bookmarkPopover"];
  TLBookmarkEditorController *backgroundEditor = [owner valueForKey:@"bookmarkEditor"];
  Check(backgroundPopover.shown && [[[backgroundEditor valueForKey:@"URLField"] stringValue] isEqual:page.URL.absoluteString], @"context menu opens the shared dropdown for an inactive webpage");
  Check(state.snapshot.activeTabID == tab.tabID, @"opening an inactive tab's bookmark editor preserves selection");
  backgroundPopover.animates = NO; [backgroundPopover close];
  NSUInteger count = [database listChats:nil].count;
  [owner showAddBookmark:nil];
  NSPopover *popover = [owner valueForKey:@"bookmarkPopover"];
  TLBookmarkEditorController *editor = [owner valueForKey:@"bookmarkEditor"];
  Check(popover.shown && popover.contentSize.height < 200, @"plus opens a compact native dropdown");
  Check([database listChats:nil].count == count, @"opening the dropdown does not persist a draft");
  [[editor valueForKey:@"cancelButton"] performClick:nil];
  NSDate *dismissed = [NSDate dateWithTimeIntervalSinceNow:2];
  while (popover.shown && dismissed.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  Check(!popover.shown && [database listChats:nil].count == count, [NSString stringWithFormat:@"cancelling the dropdown leaves draft untouched (shown=%d, chats=%lu/%lu)", popover.shown, (unsigned long)[database listChats:nil].count, (unsigned long)count]);
  [owner showAddBookmark:nil];
  editor = [owner valueForKey:@"bookmarkEditor"];
  popover = [owner valueForKey:@"bookmarkPopover"];
  NSDate *opened = [NSDate dateWithTimeIntervalSinceNow:0.4];
  while (opened.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  popover.animates = NO;
  BOOL (^saveHandler)(TLBookmark *, NSError **) = editor.saveHandler;
  editor.saveHandler = ^BOOL(TLBookmark *entry, NSError **error) {
    *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not save this bookmark. Please try again."}];
    return NO;
  };
  [[editor valueForKey:@"saveButton"] performClick:nil];
  Check(popover.shown && popover.contentSize.height >= editor.preferredContentSize.height, [NSString stringWithFormat:@"dropdown grows to keep save errors visible: %@ / %@", NSStringFromSize(popover.contentSize), NSStringFromSize(editor.preferredContentSize)]);
  editor.saveHandler = saveHandler;
  [[editor valueForKey:@"saveButton"] performClick:nil];
  Check([database listChats:nil].count == count + 1, @"saving a draft bookmark creates a durable conversation");
  TLBookmark *saved = [database listBookmarks:nil].lastObject;
  Check(saved.chatID > 0 && [database chatWithID:saved.chatID error:nil] != nil, @"draft bookmark resolves to the persisted conversation");
  Check([state workspaceTabWithKind:TLWorkspaceTabKindChat tabID:saved.chatID] != nil, @"draft tab follows its saved identity");
  [database deleteChatWithID:saved.chatID error:nil];
  [owner setWindow:nil];
  [window close];
}

static void TestBookmarkOnlySchemaCompatibility(void) {
  NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
  NSURL *URL = [directory URLByAppendingPathComponent:@"bookmarks.sqlite"];
  NSError *error = nil;
  TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
  TLBookmark *bookmark = [TLBookmark new]; bookmark.name = @"Keep bookmark"; bookmark.URL = [NSURL URLWithString:@"https://example.com/kept"];
  Check([database saveBookmark:bookmark error:&error], @"create existing bookmark");
  database = nil;
  TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
  Check([fixture executeSQL:"DROP TABLE browser_history; PRAGMA user_version=9;" error:&error], @"create bookmark-only version-9 fixture");
  database = [[TLDatabase alloc] initWithURL:URL error:&error];
  Check(database != nil && [[database listBookmarks:&error].firstObject.name isEqual:@"Keep bookmark"], @"merging feature schemas preserves existing bookmarks");
  Check([database recordBrowserVisitToURL:[NSURL URLWithString:@"https://example.com/new"] title:@"New visit" error:&error] > 0,
    @"bookmark-only installations gain working browser history");
  database = nil; fixture = nil;
  [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

static void TestBrowserHistoryCompatibility(void) {
  for (NSNumber *version in @[@9, @10]) {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *URL = [directory URLByAppendingPathComponent:@"history.sqlite"];
    NSError *error = nil;
    TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
    TLChatRecord *chat = [database createChatWithModel:@"test" error:&error];
    [database saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:@"Keep conversation" thinking:nil] chatID:chat.chatID error:&error];
    database = nil;
    TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
    Check([fixture executeSQL:
      "DROP TABLE bookmarks; DROP TABLE browser_history;"
      "CREATE TABLE browser_history (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL, title TEXT NOT NULL, visited_at TEXT NOT NULL DEFAULT (datetime('now')));"
      "CREATE INDEX browser_history_recent ON browser_history(visited_at DESC, id DESC);"
      "INSERT INTO browser_history(url,title,visited_at) VALUES('https://example.com/kept','Kept page','2026-09-09 00:00:00');"
      "PRAGMA user_version=9;" error:&error], @"create independent browser-history version-9 fixture without bookmarks");
    if (version.integerValue == 10) Check([fixture executeSQL:
      "ALTER TABLE browser_history ADD COLUMN favicon BLOB; UPDATE browser_history SET favicon=X'012345'; PRAGMA user_version=10;"
      error:&error], @"create version-10 history with favicon");
    for (NSUInteger attempt = 0; attempt < 2; attempt++) {
      database = [[TLDatabase alloc] initWithURL:URL error:&error];
      Check(database != nil, [NSString stringWithFormat:@"open browser-history schema %@: %@", version, error]);
      Check([[[database chatWithID:chat.chatID error:&error].messages.firstObject content] isEqual:@"Keep conversation"], @"preserve existing conversation");
      TLBookmark *bookmark = [TLBookmark new]; bookmark.name = @"Saved conversation"; bookmark.chatID = chat.chatID;
      Check([database saveBookmark:bookmark error:&error] && [database listBookmarks:&error].count == 1, @"bookmarks work alongside browser history and survive repeated opening");
      database = nil;
      TLSQLiteStatement *storedVersion = [fixture prepareSQL:"PRAGMA user_version" error:&error];
      Check([storedVersion step] == SQLITE_ROW && sqlite3_column_int(storedVersion.handle,0) == 11, @"upgrade both feature schemas without losing their data");
      TLSQLiteStatement *history = [fixture prepareSQL:"SELECT url,title,visited_at FROM browser_history" error:&error];
      Check([history step] == SQLITE_ROW && [[history stringAtColumn:0] isEqual:@"https://example.com/kept"] &&
        [[history stringAtColumn:1] isEqual:@"Kept page"] && [[history stringAtColumn:2] isEqual:@"2026-09-09 00:00:00"], @"history row is untouched");
      if (version.integerValue == 10) {
        TLSQLiteStatement *icon = [fixture prepareSQL:"SELECT hex(favicon) FROM browser_history" error:&error];
        Check([icon step] == SQLITE_ROW && [[icon stringAtColumn:0] isEqual:@"012345"], @"favicon bytes remain intact");
      }
    }
    Check([fixture executeSQL:"PRAGMA user_version=12" error:&error], @"prepare unknown future version");
    error = nil;
    Check([[TLDatabase alloc] initWithURL:URL error:&error] == nil && error, @"unknown future versions remain rejected");
    if (version.integerValue == 10) {
      Check([fixture executeSQL:"PRAGMA user_version=10; ALTER TABLE chats ADD COLUMN unknown_required TEXT NOT NULL DEFAULT 'x'" error:nil], @"prepare incompatible core schema");
      error = nil;
      Check([[TLDatabase alloc] initWithURL:URL error:&error] == nil && error, @"version-10 compatibility requires a recognized core schema");
      Check([fixture executeSQL:"ALTER TABLE chats DROP COLUMN unknown_required; ALTER TABLE browser_history DROP COLUMN favicon" error:nil], @"prepare unrecognized version-10 history schema");
      error = nil;
      Check([[TLDatabase alloc] initWithURL:URL error:&error] == nil && error, @"unrecognized version-10 history remains rejected");
    }
    fixture = nil;
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
  }
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestBrowserHistoryCompatibility();
    TestBookmarkOnlySchemaCompatibility();
    NSURL *base = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *URL = [base URLByAppendingPathComponent:@"bookmarks.sqlite"];
    NSError *error = nil;
    TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
    Check(TLDatabaseMigrate(fixture, 8, &error), @"create latest main database fixture");
    fixture = nil;
    TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
    Check(database && [database listBookmarks:&error].count == 0, @"migration starts with no hardcoded bookmarks");
    for (NSString *invalid in @[@"", @"https://", @"javascript:alert(1)", @"file:///tmp/file", @"two words", @"https://user:secret@example.com"]) {
      Check(![TLBookmark normalizedURL:invalid], [@"reject invalid URL: " stringByAppendingString:invalid]);
    }
    TLBookmark *website = [TLBookmark new]; website.name = @"Example";
    website.URL = [TLBookmark normalizedURL:@"example.com/path?q=1#section"];
    website.faviconData = [@"icon bytes" dataUsingEncoding:NSUTF8StringEncoding];
    Check([database saveBookmark:website error:&error], @"save website");
    website.name = @"Renamed";
    Check([database saveBookmark:website error:&error] && [database listBookmarks:nil].count == 1, @"duplicate destination updates bookmark");
    TLChatRecord *chat = [database createChatWithModel:@"test" error:&error];
    TLBookmark *conversation = [TLBookmark new]; conversation.name = @"Planning"; conversation.chatID = chat.chatID; conversation.emoji = @"🪴";
    Check([database saveBookmark:conversation error:&error], @"save chat bookmark");
    database = nil;
    database = [[TLDatabase alloc] initWithURL:URL error:&error];
    NSArray<TLBookmark *> *saved = [database listBookmarks:&error];
    Check(saved.count == 2 && [saved[0].name isEqual:@"Renamed"] && [saved[0].faviconData isEqual:website.faviconData], @"website title, URL and favicon survive reopen");
    Check(saved[1].chatID == chat.chatID && [saved[1].emoji isEqual:@"🪴"] && !saved[1].URL, @"chat identity and emoji survive reopen");
    TLBookmarkTestController *owner = [[TLBookmarkTestController alloc] initWithWindow:nil];
    TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
    [owner setValue:database forKey:@"database"]; [owner setValue:palette forKey:@"palette"];
    TLSidebarShortcutsView *sidebar = [TLSidebarShortcutsView new];
    [owner setValue:sidebar forKey:@"sidebarShortcutsView"];
    [owner reloadBookmarks];
    [owner openSidebarBookmark:sidebar.shortcutButtons[0]];
    [owner openSidebarBookmark:sidebar.shortcutButtons[1]];
    Check([owner.openedURL isEqual:website.URL] && owner.openedChatID == chat.chatID, @"buttons reopen their saved website and conversation");
    TLAppStateManager *state = [TLAppStateManager new]; [owner setValue:state forKey:@"appStateManager"];
    TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:1 title:@"Current page" toolTip:nil URL:website.URL closeable:YES];
    [state addWorkspaceTab:tab activate:YES];
    TLBookmark *candidate = [owner bookmarkForCurrentPage];
    Check([candidate.name isEqual:@"Current page"] && [candidate.URL isEqual:website.URL], @"prefills current browser metadata");
    TLWorkspaceTab *chatTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:chat.chatID title:chat.title toolTip:nil URL:nil closeable:YES];
    chat.icon = @"🧭"; [owner setValue:chat forKey:@"activeChat"]; [state addWorkspaceTab:chatTab activate:YES];
    candidate = [owner bookmarkForCurrentPage];
    Check(candidate.chatID == chat.chatID && [candidate.emoji isEqual:@"🧭"] && [candidate.name isEqual:chat.title], @"prefills current conversation title and emoji");
    [state addWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindSettings tabID:0 title:@"Settings" toolTip:nil URL:nil closeable:YES] activate:YES];
    Check(![owner bookmarkForCurrentPage], @"non-content tabs cannot accidentally bookmark a previous chat");
    candidate = [owner bookmarkForTab:tab];
    Check([candidate.name isEqual:@"Current page"] && [candidate.URL isEqual:website.URL], @"inactive webpage uses its own title and URL");
    TLChatRecord *different = [TLChatRecord new]; different.chatID = -99; different.title = @"Other chat";
    [owner setValue:different forKey:@"activeChat"];
    candidate = [owner bookmarkForTab:chatTab];
    Check(candidate.chatID == chat.chatID && [candidate.name isEqual:chat.title], @"inactive conversation uses its own database record");
    for (TLWorkspaceTab *source in @[tab,chatTab]) {
      NSMenu *menu = [owner workspaceTabsController:nil contextMenuForTab:source];
      NSMenuItem *add = [menu itemWithTitle:@"Add to bookmarks"];
      Check(add.enabled && add.representedObject == source && add.target == owner, @"chat and website context menus retain the correct source tab");
    }
    Check(![[owner workspaceTabsController:nil contextMenuForTab:state.snapshot.workspaceTabs.lastObject] itemWithTitle:@"Add to bookmarks"], @"settings menu does not offer bookmarking");
    TestTabMenu(owner, state, tab, chatTab);
    NSMenuItem *remove = [sidebar.shortcutButtons[0].menu itemWithTitle:@"Delete bookmark"];
    [owner removeBookmark:remove];
    Check([database listBookmarks:nil].count == 1, @"context menu removes only selected bookmark");
    Check([database deleteChatWithID:chat.chatID error:&error] && [database listBookmarks:nil].count == 0, @"deleted chat leaves no dangling bookmark");
    Check(![database saveBookmark:conversation error:&error], @"missing conversation cannot be bookmarked");
    TestSidebarBookmarkMenus(website, conversation);
    TestEditor(website); TestEditor(conversation); TestBookmarkDrop();
    TestPopover(owner, state, database);
    // At narrow sidebar widths, bookmarks wrap instead of shrinking to unusable hit targets.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 160, 300) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    sidebar.translatesAutoresizingMaskIntoConstraints = YES;
    window.contentView = sidebar;
    [sidebar removeAllShortcutButtons];
    for (NSUInteger i=0; i<12; i++) { TLSidebarShortcutButton *button = [TLSidebarShortcutButton new]; button.systemIconName = @"globe"; [sidebar addShortcutButton:button]; }
    [sidebar layoutSubtreeIfNeeded];
    Check(sidebar.intrinsicContentSize.height > 100, @"bookmark rows expand the sidebar content height");
    for (TLSidebarShortcutButton *button in sidebar.shortcutButtons) Check(NSWidth(button.bounds) == palette.sidebarBookmarkButtonSize, @"bookmarks retain full-size hit targets");
    SavePreview(sidebar, @"bookmark-sidebar.png");
    [window close];
    [NSFileManager.defaultManager removeItemAtURL:base error:nil];
    NSLog(@"Bookmark tests passed.");
  }
}
