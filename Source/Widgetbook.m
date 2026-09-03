#import "Widgetbook.h"

static NSString *TLWidgetbookMarkdown(void) {
  return @"# Markdown Widgetbook\n\n"
    @"This fixture covers the renderer surface used by assistant messages: **bold**, *italic*, ***bold italic***, "
    @"~~strikethrough~~, `inline code`, [links](https://example.com), and ordinary wrapping text that should stay in one readable column.\n\n"
    @"## Lists\n\n"
    @"- Short unordered item\n"
    @"- A long unordered item that wraps across multiple lines without splitting into separate columns or drifting away from its marker.\n"
    @"- Nested content should stay aligned:\n"
    @"  - Nested item A\n"
    @"  - Nested item B with `code`\n\n"
    @"1. Ordered item one\n"
    @"2. Ordered item two with enough text to wrap naturally and keep the number aligned with the item body.\n"
    @"3. Ordered item three\n\n"
    @"- [x] Render checked task items\n"
    @"- [ ] Render unchecked task items\n\n"
    @"## Table\n\n"
    @"| Feature | Expected rendering | Status |\n"
    @"| :--- | :--- | ---: |\n"
    @"| Tables | One coherent table, not a character stream | 100% |\n"
    @"| Wrapping | Cell text wraps inside the cell | 100% |\n"
    @"| Alignment | Right column is right aligned | 100% |\n\n"
    @"## Code\n\n"
    @"```objc\n"
    @"NSDictionary *payload = @{@\"role\": @\"assistant\", @\"content\": markdown};\n"
    @"NSLog(@\"%@\", payload[@\"content\"]);\n"
    @"```\n\n"
    @"Inline code such as `TLMarkdownRenderer` should not blow up line height.\n\n"
    @"## Blockquote\n\n"
    @"> A blockquote should be visually distinct, readable, and constrained to the same message width.\n"
    @">\n"
    @"> It should preserve paragraph rhythm inside the quote.\n\n"
    @"---\n\n"
    @"## Plain Numbered Prose\n\n"
    @"11. This line is intentionally a Markdown ordered-list item in assistant content.\n"
    @"12. It should render as a normal ordered list, without duplicate words, overlap, or strange columns.\n\n"
    @"Final paragraph after the ordered prose confirms the renderer returns to normal paragraph layout.";
}

static NSString *TLWidgetbookThinking(void) {
  return @"Thinking is displayed as plain text, not interpreted Markdown.\n"
    @"11. Analyze the request without turning this diagnostic text into a broken list layout.\n"
    @"12. Keep **literal markers** literal here so debug traces remain readable.\n"
    @"13. Long thinking lines should wrap in one column and should never duplicate tokens or drift across the bubble.";
}

static TLStoredChatMessage *TLWidgetbookMessage(NSInteger messageID, NSString *role, NSString *content, NSString *thinking) {
  TLStoredChatMessage *message = [[TLStoredChatMessage alloc] init];
  message.messageID = messageID;
  message.role = role;
  message.content = content;
  message.thinking = thinking;
  message.createdAt = @"Widgetbook";
  return message;
}

BOOL TLWidgetbookModeEnabled(void) {
  NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
  if ([arguments containsObject:@"--widgetbook"]) {
    return YES;
  }

  NSString *environmentValue = NSProcessInfo.processInfo.environment[@"TL_WIDGETBOOK"];
  return [environmentValue isEqualToString:@"1"] || [environmentValue.lowercaseString isEqualToString:@"true"];
}

NSURL *TLWidgetbookBrowserURL(void) {
  NSString *browserURLString = NSProcessInfo.processInfo.environment[@"TL_WIDGETBOOK_BROWSER_URL"] ?: @"";
  for (NSString *argument in NSProcessInfo.processInfo.arguments) {
    NSString *prefix = @"--widgetbook-browser-url=";
    if ([argument hasPrefix:prefix]) {
      browserURLString = [argument substringFromIndex:prefix.length];
      break;
    }
  }

  NSURL *URL = browserURLString.length > 0 ? [NSURL URLWithString:browserURLString] : nil;
  NSString *scheme = URL.scheme.lowercaseString;
  return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) ? URL : nil;
}

TLChatRecord *TLWidgetbookChat(void) {
  TLChatRecord *chat = [[TLChatRecord alloc] init];
  chat.chatID = 1;
  chat.title = @"Markdown Widgetbook";
  chat.model = @"widgetbook";
  chat.createdAt = @"Widgetbook";
  chat.updatedAt = @"Widgetbook";
  chat.messages = @[
    TLWidgetbookMessage(1, TLRoleUser, @"Render the markdown widgetbook.", nil),
    TLWidgetbookMessage(2, TLRoleAssistant, TLWidgetbookMarkdown(), TLWidgetbookThinking()),
  ];
  return chat;
}

NSArray<TLChatSummary *> *TLWidgetbookChats(void) {
  TLChatRecord *record = TLWidgetbookChat();
  TLChatSummary *summary = [[TLChatSummary alloc] init];
  summary.chatID = record.chatID;
  summary.title = record.title;
  summary.model = record.model;
  summary.createdAt = record.createdAt;
  summary.updatedAt = record.updatedAt;
  return @[summary];
}
