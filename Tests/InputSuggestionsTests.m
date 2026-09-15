#import <Foundation/Foundation.h>
#import "InputSuggestions.h"
static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSArray *Rows(NSString *text, NSArray *candidates) {
  NSArray *rows = [TLInputSuggestions suggestionsForInput:text commands:@[] localCandidates:candidates
    searchURL:[NSURL URLWithString:@"https://search.example/?q=exact"] hasAttachments:NO];
  if (rows.count) Check([rows[0][@"kind"] isEqual:@"prompt"] || [rows[1][@"kind"] isEqual:@"prompt"],
    @"Ask agent always stays in the first two actions");
  return rows;
}
int main(void) { @autoreleasepool {
  NSString *draft = @"  find cats & dogs  ";
  NSArray *rows = Rows(draft, @[]);
  Check(rows.count == 2 && [rows[1][@"kind"] isEqual:@"search"], @"empty history offers exact search after Ask agent");
  Check([rows[1][@"command"] isEqual:@"Google Search"], @"search displays a constant Google Search label");
  Check([rows[0][@"value"] isEqual:draft], @"Ask agent preserves the exact draft");
  Check(Rows(@" \n", @[]).count == 0, @"blank input has no invented queries");
  for (NSString *input in @[@"http", @"https://", @"www.", @"example..com", @"javascript:alert(1)", @"user@example.com", @"file:///tmp/private", @"hello world"]) {
    rows = Rows(input, @[]);
    Check(rows.count == 2 && [rows[1][@"kind"] isEqual:@"search"], [@"search fallback: " stringByAppendingString:input]);
  }
  for (NSString *input in @[@"example.com", @"https://example.com/path?q=a#part", @"localhost:3000", @"127.0.0.1:8080"]) {
    rows = Rows(input, @[]);
    Check(rows.count == 3 && [rows[0][@"kind"] isEqual:@"web"] && [rows[2][@"kind"] isEqual:@"search"], @"URL offers navigation first and exact search third");
  }
  NSString *now = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];
  NSArray *candidates = @[
    @{@"URL":@"https://alpha.test/", @"title":@"Alpha", @"visits":@2, @"visitedAt":now},
    @{@"URL":@"https://alpha.test", @"title":@"Saved Alpha", @"bookmark":@YES},
    @{@"URL":@"https://alpha.test:443/", @"title":@"Alpha tab", @"tabID":@42},
    @{@"URL":@"https://prefix.test/", @"title":@"Alphabet", @"visits":@900},
    @{@"URL":@"https://substring.test/", @"title":@"An alpha guide", @"visits":@9999}];
  rows = Rows(@"alpha", candidates);
  Check([rows[0][@"kind"] isEqual:@"tab"] && [rows[0][@"tabID"] isEqual:@"42"], @"exact match outranks frequent prefixes and switches to the existing tab");
  Check(rows.count == 5, @"history, bookmark and open tab are deduplicated by destination");
  Check([rows[3][@"URL"] isEqual:@"https://prefix.test/"], @"prefix ranks above frequent substring match");
  Check([rows[0][@"description"] length] && [rows[0][@"match"] isEqual:@"alpha"], @"local rows expose their URL and highlight query");
  Check([Rows(@"alpha", [TLInputSuggestions prepareLocalCandidates:candidates]) isEqual:rows], @"background-prepared history ranks identically to fresh local candidates");
  Check([Rows(@"al", candidates)[0][@"kind"] isEqual:@"tab"], @"domain fragments promote the saved destination");
  Check([Rows(@"pha", candidates)[0][@"kind"] isEqual:@"tab"], @"a match inside a domain also promotes its destination");
  Check([Rows(@"/unknown", @[])[1][@"kind"] isEqual:@"search"], @"unknown slash text keeps the exact search fallback");
  rows = Rows(@"alpha.test", candidates);
  Check([rows[0][@"kind"] isEqual:@"tab"] && rows.count == 3, @"direct URL and existing local destination appear once");
  rows = Rows(@"guide", candidates);
  Check([rows[1][@"kind"] isEqual:@"search"] && [rows[2][@"strong"] isEqual:@"no"], @"search ranks ahead of weak local substrings");
  rows = Rows(@"plan", @[@{@"URL":@"https://old.test", @"title":@"Planning", @"visits":@1, @"visitedAt":@"2000-01-01 00:00:00"},
    @{@"URL":@"https://recent.test", @"title":@"Planning", @"visits":@1, @"visitedAt":now}]);
  Check([rows[1][@"URL"] isEqual:@"https://recent.test"], @"recent visits boost equally matching destinations");
  rows = Rows(@"plan", @[@{@"URL":@"https://once.test", @"title":@"Planning", @"visits":@1},
    @{@"URL":@"https://frequent.test", @"title":@"Planning", @"visits":@20}]);
  Check([rows[1][@"URL"] isEqual:@"https://frequent.test"], @"frequency boosts equally matching destinations");
  NSArray *commands = @[@{@"kind":@"hermes", @"command":@"/help"}, @{@"kind":@"hermes", @"command":@"/history"}];
  rows = [TLInputSuggestions suggestionsForInput:@"/h" commands:commands localCandidates:@[] searchURL:[NSURL URLWithString:@"https://search.test"] hasAttachments:NO];
  Check([rows[0][@"command"] isEqual:@"Ask agent"] && [rows[1][@"kind"] isEqual:@"hermes"] && [rows[2][@"kind"] isEqual:@"search"], @"discovered commands follow Ask agent with exact search alongside them");
  rows = [TLInputSuggestions suggestionsForInput:@"attached document" commands:@[] localCandidates:@[] searchURL:[NSURL URLWithString:@"https://search.test"] hasAttachments:YES];
  Check([rows[0][@"kind"] isEqual:@"prompt"] && [rows[0][@"command"] isEqual:@"Ask agent"], @"attachments keep Ask agent the default");
  NSData *icon = [@"saved icon" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSString *title in @[@"", @"  ", @"https://www.example.com/path"]) {
    rows = Rows(@"example", @[@{@"URL":@"https://www.example.com/path", @"title":title, @"faviconData":icon}]);
    Check([rows[0][@"title"] isEqual:@"example.com"], @"missing and URL-only titles use the domain without www");
    Check([rows[0][@"faviconData"] isEqual:icon], @"local suggestions preserve saved favicon data");
  }
  rows = Rows(@"example", @[@{@"URL":@"https://www.example.com/path", @"title":@"Example page"},
    @{@"URL":@"https://www.example.com/path", @"title":@"", @"tabID":@42}]);
  Check([rows[0][@"title"] isEqual:@"Example page"], @"a titleless open tab preserves the known page title");
  rows = Rows(@"Planning", @[@{@"URL":@"https://other.test/planning", @"title":@"Planning"}]);
  Check([rows[0][@"kind"] isEqual:@"prompt"], @"title and path matches keep Ask agent first");
  rows = [TLInputSuggestions suggestionsForInput:@"alpha.test" commands:@[] localCandidates:candidates searchURL:nil hasAttachments:YES];
  Check([rows[0][@"kind"] isEqual:@"prompt"], @"attachments retain the agent default for domain inputs");
  rows = Rows(@"https://www.example.com/path?q=one#section", @[]);
  Check([rows[0][@"command"] isEqual:@"Go to example.com"] &&
    [rows[0][@"URL"] isEqual:@"https://www.example.com/path?q=one#section"], @"navigation label uses the domain while preserving the full destination");
  NSLog(@"InputSuggestionsTests passed");
} return 0; }
