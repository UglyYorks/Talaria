#import <AppKit/AppKit.h>
#import "TLHistoryPanelController.h"
#import "design_system/TLInputSuggestionListView.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]]; }
@interface TLHistoryPanelController (QueryTests)
- (void)loadNextPage;
- (void)controlTextDidChange:(NSNotification *)notification;
@end
@interface TLDeferredHistory : NSObject <TLHistoryReading>
@property NSMutableArray *requests;
@end
@implementation TLDeferredHistory
- (instancetype)init { if ((self = [super init])) _requests = [NSMutableArray array]; return self; }
- (void)historyMatching:(NSString *)query before:(TLBrowserHistoryEntry *)cursor completion:(void (^)(NSArray<TLBrowserHistoryEntry *> * _Nullable, NSError * _Nullable))completion {
  [self.requests addObject:@{@"query":query, @"cursor":cursor ?: NSNull.null, @"completion":[completion copy]}];
}
- (void)faviconForVisit:(TLBrowserHistoryEntry *)visit completion:(void (^)(NSData *))completion { completion(nil); }
@end
static void Complete(NSDictionary *request, NSArray *rows) { void (^completion)(NSArray *, NSError *) = request[@"completion"]; completion(rows, nil); }
static TLBrowserHistoryEntry *Visit(NSInteger identity, NSString *title) {
  TLBrowserHistoryEntry *visit = [TLBrowserHistoryEntry new]; visit.visitID = identity;
  visit.title = title; visit.URLString = @"https://example.com"; visit.visitedAt = @"2026-09-09"; return visit;
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
    TLHistoryPanelController *panel = [[TLHistoryPanelController alloc] initWithPalette:palette];
    TLDeferredHistory *repository = [TLDeferredHistory new]; panel.repository = repository;
    [panel reloadData]; Drain();
    Check(repository.requests.count == 0, @"hidden history performs no queries");
    panel.visible = YES; Drain();
    Check(repository.requests.count == 1, @"opening dirty history loads one page");
    NSSearchField *search = [panel valueForKey:@"searchField"];
    search.stringValue = @"new";
    [panel controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
    Complete(repository.requests[0], @[Visit(1, @"old")]);
    Check([[panel valueForKey:@"filteredEntries"] count] == 0, @"stale results cannot replace a newer search");
    Drain();
    Check(repository.requests.count == 2 && [repository.requests[1][@"query"] isEqual:@"new"], @"latest search reaches the repository");
    NSMutableArray *page = [NSMutableArray array];
    for (NSInteger i = 0; i < 100; i++) [page addObject:Visit(i + 10, @"new")];
    Complete(repository.requests[1], page);
    Check([[panel valueForKey:@"filteredEntries"] count] == 100, @"page appears without issuing another query");
    [panel loadNextPage];
    Check(repository.requests.count == 3 && repository.requests[2][@"cursor"] == page.lastObject, @"next page starts at the last visit");
    panel.visible = NO;
    Complete(repository.requests[2], @[Visit(500, @"new")]);
    Check([[panel valueForKey:@"filteredEntries"] count] == 100, @"hidden panel rejects in-flight results");
    [panel reloadData]; Drain();
    Check(repository.requests.count == 3, @"hidden refresh only marks data dirty");
    panel.visible = YES; Drain();
    Check(repository.requests.count == 4 && repository.requests[3][@"cursor"] == NSNull.null, @"reopening restarts from the newest page");

    TLInputSuggestionListView *list = [TLInputSuggestionListView new]; list.palette = palette;
    list.suggestions = @[@{@"kind":@"status", @"title":@"Loading"}, @{@"kind":@"web", @"URL":@""}];
    Check(![list moveSelectionByOffset:1] && list.selectedIndex == -1, @"all-disabled suggestions have no selection");
    list.suggestions = @[@{@"kind":@"status", @"title":@"Loading"}, @{@"kind":@"prompt", @"title":@"Send"}, @{@"kind":@"status", @"title":@"Waiting"}];
    Check([list moveSelectionByOffset:-1] && list.selectedIndex == 1, @"reverse movement skips disabled rows");
    Check([list moveSelectionByOffset:1] && list.selectedIndex == 1, @"forward wrapping uses the same enabled-row policy");
    NSLog(@"HistoryQueryTests passed");
  }
}
