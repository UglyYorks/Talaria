#import <AppKit/AppKit.h>
#import "Database.h"
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
- (void)openSidebarBookmark:(TLSidebarShortcutButton *)button;
- (void)removeBookmark:(NSMenuItem *)item;
- (TLBookmark *)bookmarkForCurrentPage;
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
      "DROP TABLE bookmarks;"
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
      Check([storedVersion step] == SQLITE_ROW && sqlite3_column_int(storedVersion.handle,0) == version.integerValue, @"never downgrade the other worktree's version");
      TLSQLiteStatement *history = [fixture prepareSQL:"SELECT url,title,visited_at FROM browser_history" error:&error];
      Check([history step] == SQLITE_ROW && [[history stringAtColumn:0] isEqual:@"https://example.com/kept"] &&
        [[history stringAtColumn:1] isEqual:@"Kept page"] && [[history stringAtColumn:2] isEqual:@"2026-09-09 00:00:00"], @"history row is untouched");
      if (version.integerValue == 10) {
        TLSQLiteStatement *icon = [fixture prepareSQL:"SELECT hex(favicon) FROM browser_history" error:&error];
        Check([icon step] == SQLITE_ROW && [[icon stringAtColumn:0] isEqual:@"012345"], @"favicon bytes remain intact");
      }
    }
    Check([fixture executeSQL:"PRAGMA user_version=11" error:&error], @"prepare unknown future version");
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
    NSMenuItem *remove = sidebar.shortcutButtons[0].menu.itemArray.firstObject;
    [owner removeBookmark:remove];
    Check([database listBookmarks:nil].count == 1, @"context menu removes only selected bookmark");
    Check([database deleteChatWithID:chat.chatID error:&error] && [database listBookmarks:nil].count == 0, @"deleted chat leaves no dangling bookmark");
    Check(![database saveBookmark:conversation error:&error], @"missing conversation cannot be bookmarked");
    TestEditor(website); TestEditor(conversation);
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
