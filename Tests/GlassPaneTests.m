#import <AppKit/AppKit.h>
#import "design_system/UIComponents.h"
#import "InputSuggestions.h"
#import "WorkspaceTabRuntime.h"
#import "ChromiumRunLoop.h"
#import "design_system/TLBrowserChatPane.h"
#import "BrowserPageContext.h"
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>

static void Check(BOOL condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

@interface TLCommandTarget : NSObject
@property (nonatomic) NSUInteger activationCount;
- (void)activate:(id)sender;
@end
@implementation TLCommandTarget
- (void)activate:(id)sender { self.activationCount += 1; }
@end

@interface TLFocusTestApplication : NSApplication
@property (nonatomic, strong) NSEvent *focusTestEvent;
@end
@implementation TLFocusTestApplication
- (NSEvent *)currentEvent { return self.focusTestEvent ?: super.currentEvent; }
@end

static id Evaluate(WKWebView *view, NSString *script) {
  __block BOOL done = NO;
  __block id value;
  __block NSError *failure;
  [view evaluateJavaScript:script completionHandler:^(id result, NSError *error) { value = result; failure = error; done = YES; }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (!done && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  Check(done && !failure, [NSString stringWithFormat:@"JavaScript completed: %@", failure]);
  return value;
}

static void TestBrowserChatPane(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLBrowserChatPane *pane = [[TLBrowserChatPane alloc] init];
  pane.title = @"Summarize this page and its detailed historical background";
  [window.contentView addSubview:pane];
  [NSLayoutConstraint activateConstraints:@[
    [pane.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [pane.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [pane.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [pane.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
  ]];
  [window orderFront:nil];
  [pane setPresented:YES animated:NO];
  [pane showMarkdown:@"" loading:YES];
  [window.contentView layoutSubtreeIfNeeded];
  NSProgressIndicator *spinner = [pane valueForKey:@"spinner"];
  Check(fabs(NSMidX(spinner.frame) - NSMidX(pane.bounds)) < 1 && fabs(NSMidY(spinner.frame) - NSMidY(pane.bounds)) < 1, @"loader is centered in pane");
  [pane showMarkdown:@"# Page summary\n\nA **streaming** response with [a link](https://example.com)." loading:NO];
  WKWebView *web = [[pane valueForKey:@"markdownView"] valueForKey:@"webView"];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (web.loading && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
  Check([Evaluate(web, @"document.querySelector('h1')?.textContent") isEqual:@"Page summary"], @"pane renders Markdown heading");
  Check([Evaluate(web, @"document.querySelector('strong')?.textContent") isEqual:@"streaming"], @"pane renders streamed emphasis");
  Evaluate(web, @"window.documentIdentity = 'preserved'");
  [pane showMarkdown:@"# Updated\n\nNext token" loading:NO];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
  Check([Evaluate(web, @"document.querySelector('h1')?.textContent") isEqual:@"Updated"], @"pane updates existing Markdown view");
  Check([Evaluate(web, @"window.documentIdentity") isEqual:@"preserved"], @"streaming never reloads the web document");
  for (NSNumber *width in @[@200, @320, @700]) {
    [window setContentSize:NSMakeSize(width.doubleValue, 500)];
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSWidth(pane.frame) == width.doubleValue && NSMaxX(pane.minimizeButton.frame) <= width.doubleValue, @"response pane and controls fit narrow windows");
    NSTextField *title = [pane valueForKey:@"titleLabel"];
    Check([title.stringValue isEqualToString:pane.title], @"pane header shows conversation title");
    Check(NSMaxX(title.frame) < NSMinX(pane.minimizeButton.frame), @"long title never overlaps minimize control");
    Check(fabs(NSMidY(title.frame) - NSMidY(pane.minimizeButton.frame)) < 1, @"header title is centered opposite minimize control");
  }
  [window setContentSize:NSMakeSize(700, 500)];
  [window.contentView layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
  [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-browser-chat-pane.png" atomically:YES];

  NSString *source = [NSString stringWithContentsOfFile:@"Vendor/readability/Readability.js" encoding:NSUTF8StringEncoding error:nil];
  Check(source.length > 0, @"Readability is vendored");
  NSString *paragraph = @"This is the main article about a forest stream. Its water passes through the valley, nourishing the surrounding landscape. Scientists observe seasonal changes and record their findings in detail. ";
  NSString *text = [paragraph stringByPaddingToLength:2000 withString:paragraph startingAtIndex:0];
  NSString *fixture = [NSString stringWithFormat:@"<!doctype html><title>Article fixture</title><nav>Navigation junk</nav><main><article><h1>Forest stream</h1><p>%@</p><p>%@</p><input value='Secret input'><div hidden>Hidden secret</div></article></main><footer>Footer junk</footer>", text, text];
  [web loadHTMLString:fixture baseURL:[NSURL URLWithString:@"https://example.com/article"]];
  deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (web.loading && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  NSString *URL = Evaluate(web, @"location.href");
  NSDictionary *page = Evaluate(web, TLBrowserReadabilityScript(source, URL));
  Check([page[@"text"] containsString:@"main article"], @"Readability keeps main article text");
  Check(![page[@"text"] containsString:@"Navigation junk"] && ![page[@"text"] containsString:@"Footer junk"], @"Readability removes navigation and footer");
  Check(![page[@"text"] containsString:@"Secret input"] && ![page[@"text"] containsString:@"Hidden secret"], @"extraction excludes form and hidden data");
  Check([Evaluate(web, @"!!document.querySelector('nav') && !!document.querySelector('input')") boolValue], @"extraction never mutates live page");
  [pane setPresented:NO animated:NO];
  Check(pane.hidden && pane.alphaValue == 0, @"immediate dismissal hides pane");
  [pane setPresented:YES animated:YES];
  Check(pane.presented && !pane.hidden, @"appearance reveals pane before animation");
  NSUInteger generation = [[pane valueForKey:@"presentationGeneration"] unsignedIntegerValue];
  [pane setPresented:YES animated:YES];
  Check([[pane valueForKey:@"presentationGeneration"] unsignedIntegerValue] == generation, @"streaming updates do not restart appearance");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CAAnimationGroup *transition = (CAAnimationGroup *)[pane.layer animationForKey:@"browser-chat-presentation"];
    Check(transition.animations.count == 2 && transition.duration == pane.palette.browserChatPaneTransitionDuration, @"appearance combines fade and slide at themed duration");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    CALayer *visible = pane.layer.presentationLayer;
    Check(visible && visible.opacity > 0 && visible.opacity < 1, @"fade has a visible intermediate state");
    Check(fabs([[visible valueForKeyPath:@"transform.translation.y"] doubleValue]) > 0, @"pane slides during fade");
  }
  [pane setPresented:NO animated:YES];
  Check(!pane.presented, @"dismissal updates target immediately");
  [pane setPresented:YES animated:YES];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:pane.palette.browserChatPaneTransitionDuration + 0.1]];
  Check(!pane.hidden && pane.alphaValue == 1, @"rapid reversal ends visible without stale hide completion");
  [pane setPresented:NO animated:YES];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:pane.palette.browserChatPaneTransitionDuration + 0.1]];
  Check(pane.hidden && pane.alphaValue == 0, @"dismissal hides pane after transition finishes");
  [pane setPresented:YES animated:YES];
  [pane setPresented:NO animated:NO];
  Check(pane.hidden && ![pane.layer animationForKey:@"browser-chat-presentation"], @"immediate state change cancels ongoing animation");
  [window orderOut:nil];
}

static void TestURLSuggestions(void) {
  for (NSString *input in @[@"https://example.com/path?q=1#top", @"example.com", @"www.example.com",
                            @"localhost:3000", @"127.0.0.1:8080/path", @"HTTP://EXAMPLE.COM", @"example.c"]) {
    NSArray *suggestions = [TLInputSuggestions webSuggestionsForInput:input];
    Check(suggestions.count == 2, [@"URL has two choices: " stringByAppendingString:input]);
    Check([suggestions[0][@"kind"] isEqualToString:@"web"] && [suggestions[0][@"icon"] isEqualToString:@"safari"], @"web choice has safari icon");
    Check([suggestions[1][@"kind"] isEqualToString:@"prompt"] && [suggestions[1][@"icon"] isEqualToString:@"text.bubble"], @"prompt choice has text bubble icon");
    Check([suggestions[0][@"URL"] length] > 0, @"complete address can be opened");
    Check([suggestions[1][@"value"] isEqualToString:input], @"prompt preserves original input");
    Check([suggestions[1][@"command"] isEqualToString:@"Send message"], @"prompt suggestion uses a fixed Send message label");
  }
  for (NSString *input in @[@"http", @"https", @"https:", @"http:/", @"https://", @"www", @"www.", @"example."]) {
    NSArray *suggestions = [TLInputSuggestions webSuggestionsForInput:input];
    Check(suggestions.count == 2, [@"URL prefix reveals choices: " stringByAppendingString:input]);
    Check([suggestions[0][@"URL"] length] == 0, @"incomplete address cannot be opened");
  }
  for (NSString *input in @[@"", @"hello", @"write a poem", @"go to example.com", @"user@example.com",
                            @"/example", @"javascript:alert(1)", @"file:///tmp/test", @"example..com"]) {
    Check([TLInputSuggestions webSuggestionsForInput:input].count == 0, [@"not a URL suggestion: " stringByAppendingString:input]);
  }
  Check([[[TLInputSuggestions browserURLForInput:@"example.com/path?q=1#top"] absoluteString]
    isEqualToString:@"https://example.com/path?q=1#top"], @"normalization preserves path, query and fragment");
}

static void TestBrowserComposer(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 420)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLBrowserAddressInput *input = [[TLBrowserAddressInput alloc] init];
  [window.contentView addSubview:input];
  NSLayoutConstraint *width = [input.widthAnchor constraintEqualToConstant:700];
  [NSLayoutConstraint activateConstraints:@[
    [input.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
    [input.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:20], width,
  ]];
  [input setDisplayedAddress:@"example.com/path"];
  input.chatVisible = YES;
  input.responseCount = 2;
  [window.contentView layoutSubtreeIfNeeded];
  CGFloat compactHeight = NSHeight(input.frame);
  Check(compactHeight == input.palette.composerButtonHeight, @"browser starts at chat composer height");
  Check(input.textView.editable && !input.textView.richText, @"browser uses editable plain multiline text");
  Check(input.sendButton.enabled, @"address enables send button");

  [window makeFirstResponder:nil];
  [input.textView setSelectedRange:NSMakeRange(input.textView.string.length, 0)];
  [window makeFirstResponder:input.textView];
  Check(NSEqualRanges(input.textView.selectedRange, NSMakeRange(0, input.textView.string.length)), @"keyboard or programmatic focus selects entire address");
  [input.textView setSelectedRange:NSMakeRange(3, 0)];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  Check(NSEqualRanges(input.textView.selectedRange, NSMakeRange(3, 0)), @"editing selection is not overwritten by deferred focus work");
  [window makeFirstResponder:nil];
  NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  [input.textView mouseDown:click];
  Check(NSEqualRanges(input.textView.selectedRange, NSMakeRange(0, input.textView.string.length)), @"first click selects entire address");
  [window makeFirstResponder:nil];
  ((TLFocusTestApplication *)NSApp).focusTestEvent = click;
  [window makeFirstResponder:input.textView];
  [input.textView mouseDown:click];
  ((TLFocusTestApplication *)NSApp).focusTestEvent = nil;
  Check(NSEqualRanges(input.textView.selectedRange, NSMakeRange(0, input.textView.string.length)), @"click preserves select-all when AppKit focuses editor before mouseDown");
  [input updateDisplayedAddress:@"example.com/redirect"];
  Check([input.textView.string isEqualToString:@"example.com/path"], @"redirect does not disturb focused address");
  [window makeFirstResponder:nil];
  Check([input.textView.string isEqualToString:@"example.com/redirect"], @"latest address appears after focus leaves");

  [input beginPromptEditing];
  Check(input.textView.string.length == 0 && window.firstResponder == input.textView, @"opening browser chat clears and focuses composer");
  Check(input.hasUserDraft && !input.sendButton.enabled, @"empty chat composer is an unsent draft and cannot submit");
  [window makeFirstResponder:nil];
  [input updateDisplayedAddress:@"example.com/current-page"];
  Check(input.textView.string.length == 0, @"page navigation does not overwrite an empty chat draft");
  [input setDisplayedAddress:@"example.com/current-page"];
  Check([input.textView.string isEqualToString:@"example.com/current-page"] && !input.hasUserDraft, @"minimizing restores current page address and exits draft mode");
  [input beginPromptEditing];
  Check(input.textView.string.length == 0 && window.firstResponder == input.textView, @"reopening chat clears and focuses input again");

  __block CGFloat reportedHeight = 0;
  input.heightChangeHandler = ^(CGFloat height) { reportedHeight = height; };
  input.textView.string = @"Summarize this page\nFocus on the important details\nThen suggest next steps";
  [input.textView didChangeText];
  [window.contentView layoutSubtreeIfNeeded];
  Check(input.hasUserDraft, @"typing records an unsent draft");
  Check(NSHeight(input.frame) > compactHeight && reportedHeight > compactHeight, @"multiline input expands and reports height");
  NSBitmapImageRep *preview = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:preview];
  [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-browser-composer.png" atomically:YES];
  input.reloadButton.enabled = YES;
  [input.reloadButton mouseEntered:click];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:preview];
  [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-browser-glass-hover.png" atomically:YES];
  [input.reloadButton mouseExited:click];
  Check(![TLInputSuggestions browserURLForInput:input.textView.string], @"multiline prompt is not navigation");
  NSString *draft = input.textView.string;
  [input updateDisplayedAddress:@"example.com/another-page"];
  Check([input.textView.string isEqualToString:draft], @"navigation does not overwrite unsent prompt");

  TLCommandTarget *target = [[TLCommandTarget alloc] init];
  input.sendButton.target = target;
  input.sendButton.action = @selector(activate:);
  Check([input textView:input.textView doCommandBySelector:@selector(insertNewline:)], @"return submits instead of inserting newline");
  Check(target.activationCount == 1, @"return dispatches send exactly once");
  Check(![input textView:input.textView doCommandBySelector:@selector(insertNewlineIgnoringFieldEditor:)], @"explicit newline remains editable");
  [window makeFirstResponder:input.textView];
  [input.textView setSelectedRange:NSMakeRange(input.textView.string.length, 0)];
  NSEvent *shiftReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
    modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:window.windowNumber context:nil
    characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
  [input.textView keyDown:shiftReturn];
  Check([input.textView.string hasSuffix:@"\n"] && target.activationCount == 1, @"Shift+Return inserts newline without sending");
  [input textView:input.textView doCommandBySelector:@selector(cancelOperation:)];
  [window.contentView layoutSubtreeIfNeeded];
  Check([input.textView.string isEqualToString:@"example.com/another-page"] && !input.hasUserDraft, @"escape restores latest address");
  Check(NSHeight(input.frame) == compactHeight, @"restoring address collapses composer");

  input.textView.string = @" \n ";
  [input.textView didChangeText];
  Check(!input.sendButton.enabled, @"whitespace cannot be sent");
  [input textView:input.textView doCommandBySelector:@selector(insertNewline:)];
  Check(target.activationCount == 1, @"empty input does not dispatch send");

  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    input.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    Check([input.backgroundView isKindOfClass:TLGlassPaneView.class], @"browser reuses native selector glass");
    Check(CGColorGetAlpha(input.layer.backgroundColor) == 0 && input.layer.borderWidth == 0, @"composer does not cover glass with opaque fill or border");
    TLGlassPaneView *glass = (TLGlassPaneView *)input.backgroundView;
    Check(glass.cornerRadius == input.palette.messageInputCornerRadius, @"glass has composer pill radius");
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView *effect = glass.subviews.firstObject;
      Check([effect.tintColor isEqual:input.palette.sidebarHoverSurface], @"browser tint matches agent selector");
    }
    [input setDisplayedAddress:@"example.com"];
    NSTextField *count = [input valueForKey:@"responseCountLabel"];
    Check(!count.drawsBackground && count.superview != input.chatButton, @"response count is plain text outside the chat button");
    Check([count.textColor isEqual:input.palette.controlText], @"response count follows toolbar text theme");
    input.chatVisible = NO;
    Check(count.hidden && input.chatButton.hidden, @"expanded chat hides both icon and count");
    input.chatVisible = YES;
    input.responseCount = 123;
    Check([count.stringValue isEqualToString:@"123"] && !count.hidden, @"minimized chat shows full response count");
    for (NSNumber *size in @[@700, @320, @200]) {
      width.constant = size.doubleValue;
      [window.contentView layoutSubtreeIfNeeded];
      NSRect textRect = [input convertRect:input.textView.visibleRect fromView:input.textView];
      NSRect sendRect = [input convertRect:input.sendButton.bounds fromView:input.sendButton];
      Check(NSWidth(textRect) > 0 && NSMaxX(textRect) < NSMinX(sendRect), @"text and send button fit without overlap");
      Check(!input.hasAmbiguousLayout, @"composer layout is determined at narrow widths");
      Check(NSMinX(count.frame) >= NSMaxX(input.chatButton.frame) && NSMaxX(count.frame) < NSMinX(input.heightToggleButton.frame), @"count fits beside chat icon without overlapping controls");
      Check(NSWidth(count.frame) >= count.intrinsicContentSize.width, @"response count is not clipped");
    }
    TLHoverIconButton *send = [input.sendButton valueForKey:@"button"];
    for (TLHoverIconButton *button in @[input.backButton, input.forwardButton, input.reloadButton, input.heightToggleButton, send]) {
      button.enabled = YES;
      [button mouseExited:click];
      Check(button.hoverSurfaceOnly && !button.bordered, @"browser button has no native bezel");
      Check(CGColorGetAlpha(button.layer.backgroundColor) == 0, @"idle button is transparent");
      [button mouseEntered:click];
      Check(CGColorEqualToColor(button.layer.backgroundColor, input.palette.chromeHoverSurface.CGColor), @"button hover matches notifications");
      Check(button.layer.cornerRadius == NSHeight(button.bounds) / 2.0,
        [NSString stringWithFormat:@"hover surface is circular: %@ %@ %g", button.toolTip, NSStringFromRect(button.bounds), button.layer.cornerRadius]);
      button.enabled = NO;
      Check(CGColorGetAlpha(button.layer.backgroundColor) == 0, @"disabled buttons do not highlight");
      [button mouseExited:click];
    }
  }
  [window close];
}

static void TestNativeMessageComposer(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 100)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLGlassMessageInput *input = [[TLGlassMessageInput alloc] init];
  [window.contentView addSubview:input];
  [NSLayoutConstraint activateConstraints:@[
    [input.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:30],
    [input.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-30],
    [input.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:20],
  ]];
  [window.contentView layoutSubtreeIfNeeded];
  Check([input.backgroundView isKindOfClass:TLGlassPaneView.class], @"message composer uses the native browser glass");
  TLHoverIconButton *send = [input.sendButton valueForKey:@"button"];
  Check(!send.hoverSurfaceOnly, @"message composer keeps its standalone send button");
  NSSize iconSize = input.sendButton.image.size;
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    input.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [window.contentView layoutSubtreeIfNeeded];
    TLGlassPaneView *glass = (TLGlassPaneView *)input.backgroundView;
    Check(glass.palette == input.palette, @"message composer reapplies its theme to native glass");
    Check(glass.cornerRadius == input.palette.messageInputCornerRadius, @"message composer uses the browser pill radius");
    Check([input.sendButton.solidSurfaceColor isEqual:input.palette.messageInputSendButtonSurface], @"message composer send button is white");
    Check([input.sendButton.disabledSolidSurfaceColor isEqual:input.palette.messageInputSendButtonDisabledSurface],
      @"message composer send button has a themed disabled surface");
    Check([input.sendButton.contentTintColor isEqual:input.palette.messageInputSendButtonText], @"message composer send icon has dark contrast");
    Check(NSWidth(input.sendButton.bounds) == input.palette.messageInputSendButtonSize &&
          NSHeight(input.sendButton.bounds) == input.palette.messageInputSendButtonSize,
      @"message composer uses the compact send button size");
    CGFloat topMargin = NSHeight(input.bounds) - NSMaxY(input.sendButton.frame);
    CGFloat rightMargin = NSWidth(input.bounds) - NSMaxX(input.sendButton.frame);
    CGFloat bottomMargin = NSMinY(input.sendButton.frame);
    Check(topMargin == rightMargin && rightMargin == bottomMargin,
      @"single-line composer keeps equal top, right, and bottom send button margins");
    CAShapeLayer *surface = [input.sendButton valueForKey:@"solidSurfaceLayer"];
    CGRect circleBounds = CGPathGetBoundingBox(surface.path);
    Check(NSWidth(circleBounds) == NSHeight(circleBounds) && NSWidth(circleBounds) == input.palette.messageInputSendButtonSize,
      @"message composer send surface is an exact circle");
    input.sendButton.enabled = NO;
    Check(CGColorEqualToColor(surface.fillColor, TLCGColor(input.palette.messageInputSendButtonDisabledSurface)),
      @"message composer send surface turns grey when disabled");
    input.sendButton.enabled = YES;
    Check(CGColorEqualToColor(surface.fillColor, TLCGColor(input.palette.messageInputSendButtonSurface)),
      @"message composer send surface returns to white when enabled");
    Check(NSEqualSizes(input.sendButton.image.size, iconSize), @"compact send button preserves the arrow icon size");
    Check(CGColorGetAlpha(input.layer.backgroundColor) == 0 && input.layer.borderWidth == 0,
      @"message composer leaves its native glass visible");
  }
  input.sendButton.enabled = NO;
  NSBitmapImageRep *preview = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:preview];
  [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:@"/tmp/talaria-native-message-composer.png" atomically:YES];
  [window close];
}

static void RunFor(NSTimeInterval duration) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:duration]];
}

static void TestBrowserHeightAnimation(void) {
  NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 500)];
  NSView *host = [[NSView alloc] init];
  host.translatesAutoresizingMaskIntoConstraints = NO;
  [content addSubview:host];
  NSLayoutConstraint *bottom = [host.bottomAnchor constraintEqualToAnchor:content.bottomAnchor];
  [NSLayoutConstraint activateConstraints:@[
    [host.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [host.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [host.topAnchor constraintEqualToAnchor:content.topAnchor], bottom,
  ]];
  [content layoutSubtreeIfNeeded];
  TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime runtimeWithContentView:content openAction:@selector(activate:) closeAction:@selector(activate:)];
  runtime.browserHostView = host;
  runtime.browserHostBottomConstraint = bottom;
  [runtime setBrowserBottomInset:-100 duration:0.4 overshoot:0.04];
  Check(bottom.constant == 0, @"resize does not jump immediately to destination");
  RunFor(0.10);
  Check(bottom.constant < 0 && bottom.constant > -100, @"resize has intermediate eased geometry");
  Check(NSHeight(host.frame) < 500 && NSHeight(host.frame) > 400 && NSWidth(host.frame) == 700, @"real browser host resizes without changing width");
  RunFor(0.21);
  Check(bottom.constant < -100 && bottom.constant >= -104.1, @"shrinking has a small bounded bounce");
  RunFor(0.2);
  Check(bottom.constant == -100 && NSHeight(host.frame) == 400, @"bounce settles at exact footer height");
  [runtime setBrowserBottomInset:0 duration:0.4 overshoot:0];
  RunFor(0.1);
  CGFloat intermediate = bottom.constant;
  [runtime setBrowserBottomInset:-120 duration:0.15 overshoot:0];
  Check(bottom.constant == intermediate, @"rapid toggle starts from current geometry");
  RunFor(0.25);
  Check(bottom.constant == -120, @"only newest transition completes");
  [runtime setBrowserBottomInset:0 duration:0.4 overshoot:0];
  RunFor(0.05);
  [runtime setBrowserBottomInset:-80 duration:0 overshoot:0];
  RunFor(0.45);
  Check(bottom.constant == -80, @"nonanimated update cancels stale animation");
}

static void TestCommandDescriptions(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 540, 120)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLGlassPaneView *pane = [[TLGlassPaneView alloc] init];
  pane.translatesAutoresizingMaskIntoConstraints = NO;
  [window.contentView addSubview:pane];
  [NSLayoutConstraint activateConstraints:@[
    [pane.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [pane.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [pane.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [pane.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
  ]];
  NSArray *commands = @[@"/example", @"/sample_two", @"/sample_three"];
  NSArray *descriptions = @[@"Example action", @"Second action", @"Third action"];
  NSMutableArray<TLSlashCommandItemView *> *rows = [NSMutableArray array];
  for (NSUInteger index = 0; index < commands.count; index++) {
    TLSlashCommandItemView *row = [[TLSlashCommandItemView alloc] init];
    row.command = commands[index];
    row.commandDescription = descriptions[index];
    row.systemIconName = @"pointer.arrow.rays";
    [pane addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
      [row.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:5],
      [row.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-5],
      [row.topAnchor constraintEqualToAnchor:pane.topAnchor constant:5 + index * 36],
      [row.heightAnchor constraintEqualToConstant:32],
    ]];
    [rows addObject:row];
  }
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    pane.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (TLSlashCommandItemView *row in rows) {
      row.palette = pane.palette;
      NSTextField *description = [row valueForKey:@"descriptionLabel"];
      Check([description.textColor isEqual:pane.palette.textMuted], @"description uses muted theme color");
      row.selected = YES;
      Check([description.textColor isEqual:pane.palette.textMuted], @"description stays grey when selected");
      row.selected = NO;
    }
    for (NSNumber *width in @[@240, @540]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 120)];
      [window.contentView layoutSubtreeIfNeeded];
      for (TLSlashCommandItemView *row in rows) {
        NSTextField *command = [row valueForKey:@"commandLabel"];
        NSTextField *description = [row valueForKey:@"descriptionLabel"];
        NSRect commandRect = [command alignmentRectForFrame:command.frame];
        NSRect descriptionRect = [description alignmentRectForFrame:description.frame];
        Check(NSMinX(descriptionRect) >= NSMaxX(commandRect) + pane.palette.space6 - 0.5, @"description follows command with a gap");
        Check(NSMaxX(descriptionRect) <= NSWidth(row.bounds) - pane.palette.space8 + 0.5, @"description stays inside row at narrow widths");
      }
    }
  }
  NSBitmapImageRep *preview = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
  [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:preview];
  [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-command-descriptions.png" atomically:YES];
  [window close];
}

int main(void) {
  @autoreleasepool {
    [TLFocusTestApplication sharedApplication];
    for (NSRunLoopMode mode in @[NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode]) {
      __block NSUInteger calls = 0;
      TLChromiumDeferToMainRunLoop(^{ calls++; });
      Check(calls == 0, @"CEF work is deferred beyond the current callback");
      [NSRunLoop.mainRunLoop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
      Check(calls == 1, @"CEF work runs once in normal, termination-modal, and event-tracking modes");
    }
    TestURLSuggestions();
    TestBrowserChatPane();
    TestNativeMessageComposer();
    TestBrowserComposer();
    TestBrowserHeightAnimation();
    TestCommandDescriptions();
    TLGlassPaneView *pane = [[TLGlassPaneView alloc] initWithFrame:NSMakeRect(0, 0, 240, 100)];
    TLSlashCommandItemView *row = [[TLSlashCommandItemView alloc] initWithFrame:NSMakeRect(5, 5, 230, 28)];
    row.command = @"/example";
    [pane addSubview:row];
    TLCommandTarget *target = [[TLCommandTarget alloc] init];
    row.target = target;
    row.action = @selector(activate:);
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSZeroPoint
      modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];

    for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      pane.palette = palette;
      row.palette = palette;
      Check([pane isKindOfClass:TLInputBlockingView.class], @"glass surface blocks click-through");
      NSView *effect = pane.subviews.firstObject;
      if (@available(macOS 26.0, *)) {
        Check([effect isKindOfClass:NSGlassEffectView.class], @"pane uses native glass");
        Check([((NSGlassEffectView *)effect).tintColor isEqual:palette.sidebarHoverSurface], @"glass tint matches agent selector");
        Check(((NSGlassEffectView *)effect).cornerRadius == palette.radiusMedium, @"glass radius matches agent selector");
      } else {
        Check([effect isKindOfClass:NSVisualEffectView.class], @"older systems use native visual effect");
      }
      row.selected = NO;
      Check(CGColorGetAlpha(row.layer.backgroundColor) == 0, @"idle row is transparent");
      Check(row.layer.cornerRadius == palette.radiusMedium && row.layer.cornerRadius > 0, @"row corners match menu items, not pills");
      Check(palette.slashCommandRowHeight < palette.fieldHeight, @"text rows are compact");
      row.selected = YES;
      Check(CGColorEqualToColor(row.layer.backgroundColor, palette.chromeHoverSurface.CGColor), @"keyboard selection uses menu highlight");
      row.selected = NO;
      [row mouseEntered:event];
      Check(CGColorEqualToColor(row.layer.backgroundColor, palette.chromeHoverSurface.CGColor), @"hover uses matching highlight");
      [row mouseExited:event];
      Check(CGColorGetAlpha(row.layer.backgroundColor) == 0, @"hover exit clears background");
      NSUInteger before = target.activationCount;
      [row mouseDown:event];
      Check(target.activationCount == before + 1, @"click activates command once");
      for (NSString *symbol in @[@"text.bubble", @"safari", @"pointer.arrow.rays"]) {
        row.systemIconName = symbol;
        NSImageView *icon = [row valueForKey:@"commandIcon"];
        Check(icon.image != nil, [@"suggestion symbol is available: " stringByAppendingString:symbol]);
        Check([icon.contentTintColor isEqual:palette.slashCommandItemText], @"icon follows text theme");
      }
      row.enabled = NO;
      [row mouseDown:event];
      Check(target.activationCount == before + 1, @"disabled web choice cannot activate");
      row.enabled = YES;
    }
    NSLog(@"GlassPaneTests passed");
  }
  return 0;
}
