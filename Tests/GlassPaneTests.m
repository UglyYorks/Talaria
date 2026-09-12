#import <AppKit/AppKit.h>
#import "design_system/UIComponents.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLTransitionCoordinator.h"
#import "InputSuggestions.h"
#import "TLBrowserHeightTransition.h"
#import "design_system/TLBrowserChatPane.h"
#import "design_system/TLToolActivityView.h"
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

static void TestAvatarInitialCentering(void) {
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    NSImage *avatar = TLAvatarImageForDisplayName(@"Yaroslav", palette);
    NSInteger pixels = (NSInteger)(avatar.size.width * 2);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
      pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [avatar drawInRect:NSMakeRect(0, 0, pixels, pixels)];
    [NSGraphicsContext restoreGraphicsState];
    NSColor *text = [palette.userMessageText colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    NSInteger minX = pixels, minY = pixels, maxX = -1, maxY = -1;
    for (NSInteger y = 0; y < pixels; y++) {
      for (NSInteger x = 0; x < pixels; x++) {
        NSColor *pixel = [bitmap colorAtX:x y:y];
        CGFloat difference = fabs(pixel.redComponent - text.redComponent) +
          fabs(pixel.greenComponent - text.greenComponent) + fabs(pixel.blueComponent - text.blueComponent);
        if (pixel.alphaComponent > 0.9 && difference < 0.3) {
          minX = MIN(minX, x); maxX = MAX(maxX, x);
          minY = MIN(minY, y); maxY = MAX(maxY, y);
        }
      }
    }
    Check(maxX >= minX && maxY >= minY, @"avatar renders its initial");
    Check(fabs((minX + maxX + 1) * 0.5 - pixels * 0.5) <= 1 &&
          fabs((minY + maxY + 1) * 0.5 - pixels * 0.5) <= 1,
          @"visible avatar initial is centered within one retina pixel");
  }
}

static void TestGlassAccountButtonSizing(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLGlassButton *button = [[TLGlassButton alloc] initWithUsesGlassEffect:YES];
  button.title = @"Yaroslav";
  [window.contentView addSubview:button];
  [NSLayoutConstraint activateConstraints:@[
    [button.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [button.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
  ]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    button.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    button.image = TLAvatarImageForDisplayName(button.title, button.palette);
    [window.contentView layoutSubtreeIfNeeded];
    NSTextField *label = [button valueForKey:@"contentLabel"];
    NSImageView *avatar = [button valueForKey:@"contentImageView"];
    Check(NSWidth(label.frame) >= label.intrinsicContentSize.width - 0.5,
          @"glass account button reserves enough width for the full name");
    Check(NSWidth(button.frame) < NSWidth(window.contentView.bounds),
          @"glass account button fits its content rather than the sidebar width");
    Check(avatar.image != nil && !avatar.image.isTemplate && avatar.contentTintColor == nil,
          @"account avatar preserves its own colors in both themes");
  }
  [window close];
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
  NSArray *activities = @[
    @{@"name":@"terminal", @"state":@"running", @"detail":@"Running the project test suite"},
    @{@"name":@"web_search", @"state":@"completed", @"detail":@"Hermes gateway tool callbacks", @"summary":@"Did 1 search"}];
  [pane showToolActivities:activities];
  TLToolActivityView *activityView = [pane valueForKey:@"activityView"];
  NSButton *disclosure = (id)activityView.arrangedSubviews.firstObject;
  Check(!activityView.expanded && activityView.arrangedSubviews.count == 1,
    @"tool activity starts collapsed with only its disclosure visible");
  NSStackView *contentStack = [pane valueForKey:@"contentStack"];
  Check(contentStack.arrangedSubviews.firstObject == activityView,
    @"browser tool activity appears above the answer");
  [pane showMarkdown:@"" loading:NO];
  Check(!activityView.hidden && ![[pane valueForKey:@"scrollView"] isHidden], @"tools are visible before answer text arrives");
  [pane showApprovalRequest:@{@"request_id":@"approval", @"command":@"make test", @"choices":@[@"once", @"deny"]}];
  [window.contentView layoutSubtreeIfNeeded];
  Check([[pane valueForKey:@"approvalCard"] superview] == activityView.superview, @"approval and live tools share the visible transcript");
  [pane showApprovalRequest:nil];
  [pane showMarkdown:@"# Working on your request\n\nI’m checking the results." loading:NO];
  [window.contentView layoutSubtreeIfNeeded];
  CGFloat collapsedHeight = NSHeight(activityView.frame);
  [disclosure performClick:nil];
  [window.contentView layoutSubtreeIfNeeded];
  Check(activityView.expanded && NSHeight(activityView.frame) > collapsedHeight,
    @"expanding tool activity grows the transcript to reveal its details");
  [pane showToolActivities:[activities arrayByAddingObject:@{@"name":@"web_extract", @"state":@"failed", @"detail":@"Page unavailable"}]];
  Check(activityView.expanded && activityView.arrangedSubviews.firstObject == disclosure,
    @"live tool updates preserve expansion and the focused disclosure control");
  [pane showToolActivities:activities];
  for (NSNumber *width in @[@200, @320, @700]) {
    [window setContentSize:NSMakeSize(width.doubleValue, 500)];
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSWidth(pane.frame) == width.doubleValue && NSMaxX(pane.minimizeButton.frame) <= width.doubleValue, @"response pane and controls fit narrow windows");
    NSTextField *title = [pane valueForKey:@"titleLabel"];
    Check([title.stringValue isEqualToString:pane.title], @"pane header shows conversation title");
    Check(NSMaxX(title.frame) < NSMinX(pane.minimizeButton.frame), @"long title never overlaps minimize control");
    Check(fabs(NSMidY(title.frame) - NSMidY(pane.minimizeButton.frame)) < 1, @"header title is centered opposite minimize control");
    Check(NSWidth(activityView.frame) <= NSWidth(pane.frame) && NSHeight(activityView.frame) > 0,
      @"tool activity stays visible and fits at 200px and wider");
    for (NSView *label in activityView.arrangedSubviews) {
      Check(NSMaxX([label alignmentRectForFrame:label.frame]) <= NSWidth(activityView.frame) + 1,
        @"tool labels keep their text within the pane, accounting for AppKit text-field optical insets");
    }
  }
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    pane.palette = [TLThemePalette paletteForPreference:preference.integerValue];
    window.appearance = [NSAppearance appearanceNamed:pane.palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    NSView *themedMarkdown = [pane valueForKey:@"markdownView"];
    NSDate *renderDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![[themedMarkdown valueForKey:@"documentReady"] boolValue] && renderDeadline.timeIntervalSinceNow > 0)
      [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    [window.contentView layoutSubtreeIfNeeded];
    Check([activityView.activities isEqual:activities], @"theme switching preserves live activity");
    Check(activityView.expanded, @"theme switching preserves disclosure state");
    NSTextField *heading = (id)activityView.arrangedSubviews[1];
    Check([heading.textColor isEqual:pane.palette.labelText], @"existing activity labels reapply semantic theme colors");
    NSBitmapImageRep *preview = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
    [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:preview];
    NSString *path = [NSString stringWithFormat:@"/tmp/talaria-tool-activity-%@.png", pane.palette.dark ? @"dark" : @"light"];
    [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
  }
  [disclosure performClick:nil];
  [window.contentView layoutSubtreeIfNeeded];
  Check(!activityView.expanded && activityView.arrangedSubviews.count == 1 && NSHeight(activityView.frame) <= collapsedHeight + 1,
    @"collapsing removes activity details and reclaims their transcript height");
  [window setContentSize:NSMakeSize(700, 500)];
  [window.contentView layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
  [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-browser-chat-pane.png" atomically:YES];
  [disclosure performClick:nil];
  [pane showToolActivities:@[]];
  Check(activityView.hidden && !activityView.expanded, @"clearing a turn hides and resets its disclosure");
  [pane showToolActivities:activities];
  Check(!activityView.hidden && !activityView.expanded, @"the next turn starts collapsed again");

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

static void TestHermesSuggestions(void) {
  NSDictionary *catalogue = @{
    @"pairs": @[@[@"/help", @"Help"], @[@"/model", @"Switch model"], @[@"/new-skill", @"Installed skill"],
                @[@"/help", @"Duplicate"], @[@"invalid", @"Malformed"], @[@42, @"Malformed"], @[]],
    @"canon": @{@"/h": @"/help", @"/help": @"/help", @"/missing": @"/absent"},
    @"commands": @{@"/model": @{@"argument_mode": @"mixed"}, @"/help": @{@"argument_mode": NSNull.null}}
  };
  NSArray *commands = [TLInputSuggestions hermesCommandsFromCatalogue:catalogue];
  Check([[[TLInputSuggestions slashCommandsForInput:@"/h" commands:commands] firstObject][@"command"] isEqualToString:@"/h"], @"exact alias ranks before longer prefix matches");
  Check(commands.count == 4, @"dynamic catalogue includes skills and aliases, ignores malformed and duplicate rows");
  Check([commands[1][@"argument_mode"] isEqualToString:@"mixed"], @"retains Hermes argument metadata");
  Check([TLInputSuggestions slashCommandsForInput:@"/" commands:commands].count == 4, @"slash shows every discovered command");
  Check([TLInputSuggestions slashCommandsForInput:@"/MO" commands:commands].count == 1, @"case-insensitive command filtering");
  Check([TLInputSuggestions slashCommandsForInput:@"/model " commands:commands].count == 0, @"space enters arguments without reselecting a command");
  Check([TLInputSuggestions slashCommandsForInput:@"/model openai/test" commands:commands].count == 0, @"arguments never trigger URL suggestions or replace command text");
  Check([TLInputSuggestions slashCommandsForInput:@"hello" commands:commands].count == 0, @"normal messages are not slash commands");
  Check([TLInputSuggestions hermesCommandsFromCatalogue:@{}].count == 0, @"missing catalogue has no invented commands");
}

static void TestURLSuggestions(void) {
  NSDictionary *labels = @{
    @"https://www.example.com/path?q=1#top": @"Open example.com",
    @"www.example.com": @"Open example.com",
    @"HTTP://WWW.EXAMPLE.COM:8080/page": @"Open example.com",
    @"https://docs.example.com/guide": @"Open docs.example.com",
    @"https://www2.example.com": @"Open www2.example.com",
    @"localhost:3000/path": @"Open localhost",
    @"127.0.0.1:8080/path": @"Open 127.0.0.1",
  };
  for (NSString *input in labels) {
    NSDictionary *suggestion = [TLInputSuggestions webSuggestionsForInput:input].firstObject;
    Check([suggestion[@"command"] isEqualToString:labels[input]], @"Open label shows only the host without a leading www.");
    Check([suggestion[@"URL"] isEqualToString:[TLInputSuggestions browserURLForInput:input].absoluteString] &&
      [suggestion[@"value"] isEqualToString:input], @"shortening the label preserves the full navigation destination and input");
  }
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
  [window orderFront:nil];
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    input.palette = [TLThemePalette paletteForPreference:preference.integerValue];
    [input layoutSubtreeIfNeeded];
    [input setLoading:YES progress:0.25];
    CAShapeLayer *line = [input valueForKey:@"loadingLine"];
    Check(!line.hidden && CGColorEqualToColor(line.strokeColor, TLCGColor(input.palette.browserLoadingProgress)), @"input loading line uses the active blue theme token");
    CGFloat inset = line.lineWidth / 2;
    CGPathRef stroke = CGPathCreateCopyByStrokingPath(line.path, NULL, line.lineWidth, kCGLineCapRound, kCGLineJoinRound, 0);
    Check(CGPathContainsPoint(stroke, NULL, CGPointMake(inset, NSMidY(input.bounds)), NO), @"progress begins at the inner left midpoint");
    Check(CGPathContainsPoint(stroke, NULL, CGPointMake(NSMidX(input.bounds), inset), NO), @"progress follows the lower inner edge");
    Check(CGPathContainsPoint(stroke, NULL, CGPointMake(NSWidth(input.bounds)-inset, NSMidY(input.bounds)), NO), @"progress ends at the inner right midpoint");
    Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(NSMidX(input.bounds), NSHeight(input.bounds)-inset), NO), @"input top edge stays clear");
    CGPathRelease(stroke);
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
      CABasicAnimation *first = (CABasicAnimation *)[line animationForKey:@"loadingProgress"];
      Check(first && [first.fromValue doubleValue] == 0, @"first progress update animates from the start");
      [CATransaction flush];
      [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:input.palette.browserLoadingProgressDuration * 0.5]];
      CGFloat visible = ((CAShapeLayer *)line.presentationLayer).strokeEnd;
      Check(visible > 0 && visible < 0.25, @"displayed progress advances between reported values");
      [input setLoading:YES progress:0.8];
      CABasicAnimation *next = (CABasicAnimation *)[line animationForKey:@"loadingProgress"];
      Check(fabs([next.fromValue doubleValue] - visible) < 0.03, @"new progress continues from the visible animation position");
      [input setLoading:YES progress:0.8];
      Check([line animationForKey:@"loadingProgress"] != nil, @"duplicate updates preserve the running animation");
    }
    [input setLoading:NO progress:1];
    Check(!line.hidden && line.strokeEnd == 1, @"completion finishes the entire input outline");
    CAKeyframeAnimation *completion = (CAKeyframeAnimation *)[line animationForKey:@"loadingCompletion"];
    double holdEnd = [completion.keyTimes[1] doubleValue] * completion.duration;
    double finishDuration = [line animationForKey:@"loadingProgress"].duration;
    Check(fabs(holdEnd - finishDuration - 0.2) < 0.001 && fabs(completion.duration - holdEnd - 0.2) < 0.001, @"full progress holds for 200ms then fades for 200ms");
    [CATransaction flush];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:holdEnd + 0.1]];
    CGFloat fadingOpacity = ((CALayer *)line.presentationLayer).opacity;
    Check(fadingOpacity > 0 && fadingOpacity < 1, @"completion visibly fades instead of disappearing");
    [input setLoading:YES progress:0.1];
    Check(!line.hidden && line.opacity == 1 && ![line animationForKey:@"loadingCompletion"], @"a new load cancels the previous fade");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    Check(!line.hidden, @"old completion cannot hide a newer navigation");
    [input setLoading:NO progress:1];
    completion = (CAKeyframeAnimation *)[line animationForKey:@"loadingCompletion"];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:completion.duration + 0.05]];
    Check(line.hidden && ![line animationForKey:@"loadingCompletion"], @"completion removes the faded indicator");
  }
  [window makeFirstResponder:nil];
  CGFloat compactHeight = NSHeight(input.frame);
  Check(compactHeight == input.palette.composerButtonHeight, @"browser starts at chat composer height");
  Check(input.textView.editable && !input.textView.richText && input.singleLine, @"URL uses editable single-line plain text");
  Check([input.textView.string isEqual:@"example.com"], @"idle address shows only its domain");
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
  Check([input.textView.string isEqualToString:@"example.com"], @"latest domain appears after focus leaves");

  [input beginPromptEditing];
  Check(input.textView.string.length == 0 && window.firstResponder == input.textView, @"opening browser chat clears and focuses composer");
  Check(input.hasUserDraft && !input.sendButton.enabled, @"empty chat composer is an unsent draft and cannot submit");
  [window makeFirstResponder:nil];
  [input updateDisplayedAddress:@"example.com/current-page"];
  Check(input.textView.string.length == 0, @"page navigation does not overwrite an empty chat draft");
  [input setDisplayedAddress:@"example.com/current-page"];
  Check([input.textView.string isEqualToString:@"example.com"] && !input.hasUserDraft, @"minimizing restores current domain and exits draft mode");
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
  Check([input.textView.string isEqualToString:@"example.com"] && !input.hasUserDraft, @"escape restores latest domain");
  Check(NSHeight(input.frame) == compactHeight, @"restoring address collapses composer");

  input.textView.string = @" \n ";
  [input.textView didChangeText];
  Check(!input.sendButton.enabled, @"whitespace cannot be sent");
  [input textView:input.textView doCommandBySelector:@selector(insertNewline:)];
  Check(target.activationCount == 1, @"empty input does not dispatch send");

  [window makeFirstResponder:nil];
  NSString *longURL = [@"https://www.example.com/" stringByAppendingString:[@"long-path/" stringByPaddingToLength:900 withString:@"long-path/" startingAtIndex:0]];
  [input setDisplayedAddress:longURL];
  width.constant = 700;
  [window.contentView layoutSubtreeIfNeeded];
  NSTextField *domain = [input valueForKey:@"domainLabel"];
  Check([domain.stringValue isEqual:@"example.com"] && fabs(NSMidX(domain.frame)-NSMidX(input.bounds))<1,
    @"idle domain omits www and is centered in the address bar");
  Check(NSHeight(input.frame)==compactHeight, @"long idle URL never expands the footer");
  [window makeFirstResponder:input.textView];
  Check([input.textView.string isEqual:longURL] && input.singleLine, @"focus exposes the entire original URL including scheme and www");
  if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
    Check([domain.layer animationForKey:@"talaria.domainFocus"]!=nil, @"domain animates left on focus");
  [window.contentView layoutSubtreeIfNeeded];
  Check(NSHeight(input.frame)==compactHeight && input.textView.textContainer.maximumNumberOfLines==1,
    @"long focused URL remains one line at fixed height");
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:input.palette.browserHeightTransitionDuration + 0.02]];
  NSBitmapImageRep *focusedPreview=[input bitmapImageRepForCachingDisplayInRect:input.bounds];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:focusedPreview];
  [[focusedPreview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-domain-focused.png" atomically:YES];
  [input.textView setSelectedRange:NSMakeRange(input.textView.string.length,0)];
  [input.textView insertText:@"\n" replacementRange:input.textView.selectedRange];
  Check([input.textView.string isEqual:longURL], @"URL editing rejects inserted newlines");
  [window makeFirstResponder:nil];
  Check([input.textView.string isEqual:@"example.com"], @"blur restores the compact domain");
  NSBitmapImageRep *domainPreview=[input bitmapImageRepForCachingDisplayInRect:input.bounds];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:domainPreview];
  [[domainPreview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-domain-idle.png" atomically:YES];

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
      Check(NSMinX(count.frame) >= NSMaxX(input.chatButton.frame) && NSMaxX(count.frame) <= NSWidth(input.bounds), @"count fits beside chat icon without overlapping controls");
      Check(NSWidth(count.frame) >= count.intrinsicContentSize.width, @"response count is not clipped");
    }
    TLHoverIconButton *send = [input.sendButton valueForKey:@"button"];
    for (TLHoverIconButton *button in @[input.backButton, input.forwardButton, input.reloadButton, send]) {
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
    if (input.palette.dark) {
      Check([input.palette.messageInputSendButtonDisabledSurface isEqual:input.palette.gray600],
        @"dark theme uses the darker disabled send surface");
    }
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
  input.palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
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
  TLBrowserHeightTransition *runtime = [[TLBrowserHeightTransition alloc] initWithContentView:content bottomConstraint:bottom];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:content.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = content;
  [window orderFront:nil];
  RunFor(0.05);
  __block NSUInteger resizes = 0;
  __block BOOL fractionalResize = NO;
  host.postsFrameChangedNotifications = YES;
  id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:host queue:nil usingBlock:^(NSNotification *note) { resizes++; fractionalResize |= fabs(NSHeight(host.frame)-round(NSHeight(host.frame)))>0.001; }];
  __block NSUInteger completions=0;
  [runtime setBrowserBottomInset:-100 duration:0.4 overshoot:0.04 completion:^{completions++;}];
  Check(bottom.constant==0 && runtime.isAnimating, @"resize starts from the existing viewport");
  RunFor(0.10);
  Check(NSHeight(host.frame)>400 && NSHeight(host.frame)<500 && resizes>=2, @"actual viewport height moves through intermediate layouts");
  Check(fabs(NSMaxY(host.frame)-NSHeight(content.bounds))<0.5, @"resizing keeps the page top fixed");
  Check(!host.layer.mask && CATransform3DIsIdentity(host.layer.transform), @"viewport resizing never masks or scales page content");
  RunFor(0.41);
  Check(NSHeight(host.frame)==400 && !runtime.isAnimating && completions==1, @"resize commits exact destination and completes once");
  Check(resizes<=26, @"viewport animation stays bounded to 60 updates per second");
  Check(!fractionalResize, @"viewport animation uses whole-point steps to prevent WebKit compositor rounding drift on Retina screens");
  [runtime setBrowserBottomInset:0 duration:0.4 overshoot:0]; RunFor(0.1);
  CGFloat intermediate=NSHeight(host.frame);
  Check(intermediate>400 && intermediate<500, @"expansion also lays out intermediate viewport sizes");
  [runtime setBrowserBottomInset:-120 duration:0.15 overshoot:0 completion:^{completions++;}];
  Check(NSHeight(host.frame)==intermediate, @"reversal begins at the current real viewport without jumping");
  RunFor(0.25);
  Check(bottom.constant==-120 && !runtime.isAnimating && completions==2, @"only newest transition completes");
  [runtime setBrowserBottomInset:0 duration:0.4 overshoot:0 completion:^{completions++;}]; RunFor(0.05);
  [runtime setBrowserBottomInset:-80 duration:0 overshoot:0]; RunFor(0.45);
  Check(bottom.constant==-80 && !runtime.isAnimating && completions==2, @"immediate update cancels pending animation and its completion");
  NSUInteger settledResizes=resizes;RunFor(0.08);
  Check(resizes==settledResizes, @"settled viewport performs no animation work");
  for (NSUInteger i=0;i<12;i++) {
    [runtime setBrowserBottomInset:-86 duration:0.08 overshoot:0];
    [window setContentSize:NSMakeSize(700,500+(i%2)*40)];
    [content layoutSubtreeIfNeeded];
    [runtime setBrowserBottomInset:0 duration:0.04 overshoot:0];
    [runtime setBrowserBottomInset:-86 duration:0.04 overshoot:0];
    RunFor(0.06);
    Check(fabs(NSHeight(host.bounds)-(NSHeight(content.bounds)-86))<0.5 && !host.layer.mask,
      @"window resizing and rapid reversals never accumulate a footer gap");
  }
  [NSNotificationCenter.defaultCenter removeObserver:observer];
  [window close];

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

static void TestSendStopImageTransition(void) {
  TLGlassMessageInput *input = [[TLGlassMessageInput alloc] init];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 80)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = input;
  [input layoutSubtreeIfNeeded];
  TLGlassButton *button = input.sendButton;
  NSButton *native = [button valueForKey:@"button"];
  TLCommandTarget *target = [[TLCommandTarget alloc] init];
  button.target = target;
  button.action = @selector(activate:);
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *transitions = [[TLTransitionCoordinator alloc] initWithClock:^{ return now; }
    automaticallyAdvances:NO];
  [button setValue:transitions forKey:@"imageTransitions"];
  NSImage *send = button.image;
  input.showsStopButton = YES;
  NSImage *stop = button.image;
  Check(stop != send && [button.toolTip isEqual:@"Stop response"], @"logical action switches immediately");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    Check(native.image == send, @"outgoing Send remains visible at animation start");
    now = button.palette.buttonImageReplacementDuration * .25;
    [transitions advance];
    Check(native.image == send && native.alphaValue > 0 && native.alphaValue < 1 &&
      native.layer.transform.m11 < 1, @"Send shrinks and fades before the replacement");
    [native performClick:nil];
    Check(target.activationCount == 1, @"the action remains clickable while animating");
    now = button.palette.buttonImageReplacementDuration * .5;
    [transitions advance];
    Check(native.image == stop && native.alphaValue == 0, @"icon switches only after fading out fully");
    now = button.palette.buttonImageReplacementDuration * .75;
    [transitions advance];
    Check(native.image == stop && native.alphaValue > 0 && native.alphaValue < 1 &&
      native.layer.transform.m11 < 1, @"Stop grows and fades in after replacement");
    // Reverse mid-animation, as happens when the user types and immediately clears a draft.
    input.showsStopButton = NO;
    input.showsStopButton = YES;
    button.palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
    Check([button.toolTip isEqual:@"Stop response"], @"rapid replacements keep the latest action");
    [transitions finishAllTransitions];
  }
  Check(native.image == button.image && native.alphaValue == 1 &&
    CATransform3DIsIdentity(native.layer.transform) && !transitions.hasTransitions,
    @"animation settles on the latest icon at full opacity and size");
  [input removeFromSuperview];
  input.showsStopButton = NO;
  Check(native.image == button.image && native.alphaValue == 1 && !transitions.hasTransitions,
    @"detached composers swap immediately without leaving an invisible button");
  [window close];
}

int main(void) {
  @autoreleasepool {
    [TLFocusTestApplication sharedApplication];
    TestHermesSuggestions();
    TestURLSuggestions();
    TestBrowserChatPane();
    TestNativeMessageComposer();
    TestSendStopImageTransition();
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
    TestAvatarInitialCentering();
    TestGlassAccountButtonSizing();
    NSLog(@"GlassPaneTests passed");
  }
  return 0;
}
