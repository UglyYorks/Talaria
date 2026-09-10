#import <AppKit/AppKit.h>
#import "Database.h"
#import "SQLiteConnection.h"
#import "DatabaseMigrator.h"
#import "TLBrowserTabController.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TLHistoryBrowserProbe : TLWebKitBrowserController
@property (nonatomic, copy) TLWebKitBrowserTitleHandler titleHandler;
@property (nonatomic, copy) TLWebKitBrowserURLHandler URLHandler;
@property (nonatomic, copy) TLWebKitBrowserNavigationHandler navigationHandler;
@property (nonatomic, copy) TLWebKitBrowserFaviconHandler faviconHandler;
@end
@implementation TLHistoryBrowserProbe
- (TLWebKitBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window
  titleHandler:(TLWebKitBrowserTitleHandler)titleHandler linkHandler:(TLWebKitBrowserLinkHandler)linkHandler
  URLHandler:(TLWebKitBrowserURLHandler)URLHandler faviconHandler:(TLWebKitBrowserFaviconHandler)faviconHandler
  navigationHandler:(TLWebKitBrowserNavigationHandler)navigationHandler {
  self.faviconHandler = faviconHandler;
  self.titleHandler = titleHandler; self.URLHandler = URLHandler; self.navigationHandler = navigationHandler;
  return [TLWebKitBrowserSession new];
}
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(TLWebKitBrowserSession *)session completion:(void (^)(BOOL))completion {
  if (completion) completion(YES);
}
- (void)closeSession:(TLWebKitBrowserSession *)session {}
- (void)stopFindingInSession:(TLWebKitBrowserSession *)session {}
@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *URL = [directory URLByAppendingPathComponent:@"history.sqlite"];
    NSError *error = nil;
    Check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error], @"creates disposable database directory");
    TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
    Check(TLDatabaseMigrate(fixture, 9, &error), @"creates the existing browsing-history schema");
    Check([fixture executeSQL:"INSERT INTO chats (title, model, hermes_session_id) VALUES ('Preserved chat', 'test', 'kept')" error:&error], @"creates existing chat history");
    Check([fixture executeSQL:"INSERT INTO browser_history (url, title) VALUES ('https://example.com/old', 'Existing visit')" error:&error], @"creates history recorded before favicons");
    fixture = nil;
    TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
    Check(database != nil && error == nil, @"migrates to browsing history without errors");
    Check([[database listChats:&error].firstObject.title isEqual:@"Preserved chat"], @"migration preserves chats");
    TLBrowserHistoryEntry *legacy = [database listBrowserHistory:&error].firstObject;
    Check([legacy.title isEqual:@"Existing visit"] && !legacy.faviconData, @"favicon migration preserves existing visits");
    Check([database deleteBrowserVisitWithID:legacy.visitID error:&error], @"removes migration fixture");
    Check([database recordBrowserVisitToURL:[NSURL URLWithString:@"file:///tmp/private.txt"] title:@"Private" error:&error] == 0 &&
      [database recordBrowserVisitToURL:[NSURL URLWithString:@"about:blank"] title:@"Blank" error:&error] == 0,
      @"internal and file pages are not browsing entries");
    __block NSUInteger changes = 0;
    TLHistoryBrowserProbe *service = [TLHistoryBrowserProbe new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    TLBrowserTabController *browser = [[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
      palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:database orchestrator:nil inputWidth:200 browserService:service];
#pragma clang diagnostic pop
    browser.historyChangedHandler = ^{ changes++; };
    [browser startInWindow:nil];
    Check([database listBrowserHistory:&error].count == 0, @"opening a tab alone does not record an unvisited address");
    NSURL *firstURL = [NSURL URLWithString:@"https://example.com/research?q=caf%C3%A9"];
    service.URLHandler(firstURL);
    NSImage *favicon = [[NSImage alloc] initWithContentsOfFile:@"assets/browser-bookmarks/github.png"];
    Check(favicon != nil, @"loads real favicon fixture");
    service.faviconHandler(favicon);
    service.titleHandler(@"Café research");
    service.titleHandler(@"Café research — updated");
    service.navigationHandler(NO, NO, YES);
    service.navigationHandler(NO, NO, NO);
    NSArray<TLBrowserHistoryEntry *> *entries = [database listBrowserHistory:&error];
    Check(entries.count == 1 && [entries.firstObject.title isEqual:@"Café research — updated"] &&
      [entries.firstObject.URLString isEqual:firstURL.absoluteString], @"title and loading changes update the original visit without duplicates");
    NSData *savedIcon = entries.firstObject.faviconData;
    Check(savedIcon.length && [[NSImage alloc] initWithData:savedIcon] != nil, @"downloaded favicon is persisted as a readable image");
    service.faviconHandler(nil);
    Check([[database listBrowserHistory:&error].firstObject.faviconData isEqual:savedIcon], @"temporary favicon clearing never erases saved icons");
    service.faviconHandler(favicon);
    NSInteger firstID = entries.firstObject.visitID;
    NSString *firstDate = entries.firstObject.visitedAt;
    NSURL *secondURL = [NSURL URLWithString:@"https://example.org/next"];
    service.URLHandler(secondURL);
    entries = [database listBrowserHistory:&error];
    Check(entries.count == 2 && [entries.firstObject.title isEqual:secondURL.absoluteString], @"a new page never inherits the previous page title");
    Check(!entries.firstObject.faviconData, @"cross-site navigation never inherits the previous site's favicon");
    service.faviconHandler([[NSImage alloc] initWithContentsOfFile:@"assets/browser-bookmarks/wikipedia.png"]);
    service.titleHandler(@"Next page");
    service.URLHandler(firstURL); // back navigation
    Check([[database listBrowserHistory:&error].firstObject.faviconData isEqual:savedIcon], @"returning to a URL reuses its persisted favicon before download");
    service.faviconHandler(favicon);
    service.titleHandler(@"Café research");
    service.URLHandler(firstURL); // reload
    service.titleHandler(@"Reloaded café");
    service.URLHandler([NSURL URLWithString:@"https://example.com/research#section"]); // same-document navigation
    service.titleHandler(@"Research section");
    entries = [database listBrowserHistory:&error];
    Check(entries.count == 5 && [entries.firstObject.title isEqual:@"Research section"], @"back, reload and same-document commits produce recent visits");
    Check([entries.firstObject.faviconData isEqual:savedIcon], @"same-site navigation keeps the favicon without requiring a new favicon callback");
    NSInteger fallbackID = [database recordBrowserVisitToURL:[NSURL URLWithString:@"https://example.com/older-page"] title:@"Other page" error:&error];
    Check([[database listBrowserHistory:&error].firstObject.faviconData isEqual:savedIcon], @"visits without icons use a saved favicon from the same website");
    [database deleteBrowserVisitWithID:fallbackID error:&error];
    NSInteger differentPort = [database recordBrowserVisitToURL:[NSURL URLWithString:@"https://example.com:8443/"] title:@"Separate origin" error:&error];
    Check(![database listBrowserHistory:&error].firstObject.faviconData, @"favicon fallback respects origin boundaries");
    [database deleteBrowserVisitWithID:differentPort error:&error];
    Check([entries.lastObject.visitedAt isEqual:firstDate], @"title updates preserve the original visit timestamp");
    service.URLHandler([NSURL URLWithString:@"about:blank"]);
    service.titleHandler(@"Internal page");
    Check([database listBrowserHistory:&error].count == 5 && [[database listBrowserHistory:&error].firstObject.title isEqual:@"Research section"],
      @"internal navigation cannot overwrite the last web visit");
    Check(changes >= 5, @"visits and metadata notify the history screen");
    [browser close];
    service.URLHandler([NSURL URLWithString:@"https://late.example"]);
    service.titleHandler(@"Late callback");
    Check([database listBrowserHistory:&error].count == 5, @"closed tabs ignore late navigation callbacks");
    browser = nil; database = nil;
    database = [[TLDatabase alloc] initWithURL:URL error:&error];
    entries = [database listBrowserHistory:&error];
    Check(entries.count == 5 && [entries.firstObject.title isEqual:@"Research section"], @"visits and page titles persist across database reopen");
    Check([entries.firstObject.faviconData isEqual:savedIcon], @"favicons survive tab close and database reopen");
    Check([database deleteBrowserVisitWithID:firstID error:&error], @"deletes one visit");
    entries = [database listBrowserHistory:&error];
    Check(entries.count == 4 && [database listChats:&error].count == 1, @"deleting a visit preserves chats and other visits to the same URL");
    Check([database updateBrowserVisitWithID:firstID title:@"Late title" error:&error] && [database listBrowserHistory:&error].count == 4,
      @"late title updates never resurrect deleted browsing history");
    Check([database updateBrowserVisitWithID:firstID faviconData:savedIcon error:&error] && [database listBrowserHistory:&error].count == 4,
      @"late favicon downloads never resurrect deleted visits");
    database = nil;
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    NSLog(@"BrowserHistoryTests passed");
  }
  return 0;
}
