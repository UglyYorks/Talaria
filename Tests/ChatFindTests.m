#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "TalariaWindowController.h"
#import "TLChatPresentation.h"
#import "MarkdownRenderer.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSString *stage = @"initialization";
static void Wait(BOOL (^ready)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!ready() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  Check(ready(), [@"asynchronous search completes: " stringByAppendingString:stage]);
}
static id JS(WKWebView *web, NSString *script) {
  __block BOOL done = NO; __block id value; __block NSError *failure;
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) { value = result; failure = error; done = YES; }];
  Wait(^BOOL { return done; }); Check(!failure, failure.description); return value;
}
static void Query(TLChatPresentation *chat, NSString *query, NSString *result) {
  stage = [NSString stringWithFormat:@"query %@ expected %@", query, result];
  chat.findBar.searchField.stringValue = query;
  chat.findBar.queryChangedHandler();
  Wait(^BOOL { if (![chat.findBar.resultLabel.stringValue isEqual:result]) stage = [NSString stringWithFormat:@"query %@ expected %@ got %@", query, result, chat.findBar.resultLabel.stringValue]; return [chat.findBar.resultLabel.stringValue isEqual:result]; });
}
@interface TalariaWindowController (ChatFindTests)
- (NSView *)buildChatWorkspace;
- (void)renderMessagesScrollingToBottom:(BOOL)scroll;
- (void)resetMessageRowCache;
@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
      window.releasedWhenClosed = NO;
      TalariaWindowController *owner = [[TalariaWindowController alloc] initWithWindow:window];
      [owner setValue:palette forKey:@"palette"];
      TLChatPresentation *chat = [TLChatPresentation new];
      chat.chat = [TLChatRecord new]; chat.chat.title = @"Search fixture";
      [owner setValue:chat forKey:@"chatPresentation"];
      chat.chatWorkspace = [owner buildChatWorkspace];
      window.contentView = chat.chatWorkspace;
      TLChatMessage *user = [TLChatMessage messageWithRole:TLRoleUser content:@"Needle and NEEDLE in a user message" thinking:nil];
      TLChatMessage *assistant = [TLChatMessage messageWithRole:TLRoleAssistant
        content:@"A **nee**dle and [needle](https://example.com).\n\n```js\nconst needle = 'value';\n```\n\n| Name | Value |\n|---|---|\n| needle | a.*[b] |" thinking:nil];
      [chat.messages addObjectsFromArray:@[user, assistant]];
      [owner renderMessagesScrollingToBottom:NO];
      [window.contentView layoutSubtreeIfNeeded];
      NSView *markdown = [chat.messageMarkdownViews objectForKey:assistant];
      NSTextField *label = (id)[chat.messageMarkdownViews objectForKey:user];
      WKWebView *web = [markdown valueForKey:@"webView"];
      stage = @"first document ready";
      Wait(^BOOL { return [[markdown valueForKey:@"documentReady"] boolValue]; });
      Check([label isKindOfClass:NSTextField.class], @"real user rows participate in search");
      [chat showFindBar];
      Query(chat, @"needle", @"1/6");
      Check([chat.findBar.searchField.accessibilityLabel isEqual:@"Find in chat"], @"shared bar identifies the chat surface");
      Check(window.firstResponder == chat.findBar.searchField.currentEditor, @"search keeps keyboard focus in its field");
      Check([[label.attributedStringValue attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:palette.primaryActionSurface], @"native active highlight uses theme surface");
      Check([[label.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:palette.primaryActionText], @"native active highlight uses matching text");
      Check([JS(web,@"document.querySelectorAll('mark[data-talaria-find]').length") integerValue] == 5, @"Markdown highlights include inline-spanning match, link, code and table");
      Check([JS(web,@"document.querySelector('code').textContent") isEqual:@"const needle = 'value';\n"], @"highlighting preserves copyable code");
      [chat findNext:NO]; Check([chat.findBar.resultLabel.stringValue isEqual:@"6/6"], @"previous wraps to last message");
      [chat findNext:YES]; Check([chat.findBar.resultLabel.stringValue isEqual:@"1/6"], @"next wraps to first message");
      [chat findNext:YES]; [chat findNext:YES];
      Check([chat.findBar.resultLabel.stringValue isEqual:@"3/6"], @"navigation moves from native text into Markdown");
      [chat showFindBar]; Check([chat.findBar.resultLabel.stringValue isEqual:@"3/6"], @"reopening visible find preserves the selected match");
      [chat hideFindBar]; [chat showFindBar];
      Wait(^BOOL { return [chat.findBar.resultLabel.stringValue isEqual:@"1/6"]; });
      Query(chat,@"a.*[b]",@"1/1");
      Query(chat,@"not present",@"0 matches"); Check(!chat.findBar.nextButton.enabled,@"zero results disable navigation");
      Query(chat,@"",@"");
      Wait(^BOOL { return [JS(web,@"document.querySelectorAll('mark[data-talaria-find]').length") integerValue] == 0; });
      Check(![label.attributedStringValue attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL], @"clearing removes native highlights");
      Query(chat,@"needle",@"1/6");
      assistant.content = [assistant.content stringByAppendingString:@"\n\nAnother needle arrives."];
      [owner renderMessagesScrollingToBottom:YES];
      Wait(^BOOL { return [chat.findBar.resultLabel.stringValue isEqual:@"1/7"]; });
      NSString *longText = [[@"A line of conversation without the search term.\n\n" stringByPaddingToLength:8000 withString:@"A line of conversation without the search term.\n\n" startingAtIndex:0] stringByAppendingString:@"deep-result"];
      assistant.content = longText;
      [owner renderMessagesScrollingToBottom:NO];
      Query(chat,@"deep-result",@"1/1");
      stage = @"scroll to deep result";
      Wait(^BOOL { return chat.messageScrollView.contentView.bounds.origin.y > 500; });
      CGFloat searchOrigin = chat.messageScrollView.contentView.bounds.origin.y;
      assistant.content = [longText stringByAppendingString:@"\n\nA streamed addition"];
      [owner renderMessagesScrollingToBottom:YES];
      Wait(^BOOL { return [chat.findBar.resultLabel.stringValue isEqual:@"1/1"]; });
      Check(fabs(chat.messageScrollView.contentView.bounds.origin.y - searchOrigin) < 2, @"streaming preserves the search scroll position");
      assistant.content = @"needle";
      [owner resetMessageRowCache]; [owner renderMessagesScrollingToBottom:NO];
      markdown = [chat.messageMarkdownViews objectForKey:assistant];
      web = [markdown valueForKey:@"webView"];
      Query(chat,@"needle",@"1/3");
      Check([JS(web,@"document.querySelectorAll('mark[data-talaria-find]').length") integerValue] == 1,@"recreated rows refresh the open search");
      // Rapidly changing a query or closing while WebKit replies cannot resurrect stale results.
      chat.findBar.searchField.stringValue = @"no"; chat.findBar.queryChangedHandler();
      chat.findBar.searchField.stringValue = @"needle"; chat.findBar.queryChangedHandler();
      [chat findNext:YES];
      [chat hideFindBar];
      Check(window.firstResponder == chat.promptTextView, @"Escape restores the composer");
      [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
      Check(!chat.findBarVisible && !chat.findBar.nextButton.enabled,@"late replies do not reopen search");
      Check([JS(web,@"document.querySelectorAll('mark[data-talaria-find]').length") integerValue] == 0,@"close removes Markdown highlights");
      [chat showFindBar]; Wait(^BOOL { return [chat.findBar.resultLabel.stringValue isEqual:@"1/3"]; });
      [window setContentSize:NSMakeSize(200,550)]; [window.contentView layoutSubtreeIfNeeded];
      Check(NSWidth(window.contentView.bounds) == 200 && NSWidth(chat.findBar.searchField.frame) >= 40,@"chat search fits the minimum window width");
      [chat hideFindBar]; [window close];
    }
    NSLog(@"ChatFindTests passed");
  }
  return 0;
}
