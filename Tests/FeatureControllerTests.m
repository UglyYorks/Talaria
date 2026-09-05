#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import "TLBrowserTabController.h"
#import "TLSettingsTabController.h"
#import "AgentOrchestrator.h"
#import "AssistantTurnRunner.h"
#import "ModelPickerView.h"
#import "UIComponents.h"
#import "TalariaWindowController.h"
#import "TLAgentCreationWindowController.h"
#import "TLAgentFolderAccessWindowController.h"
#import "design_system/TLEmojiPicker.h"
#import "design_system/TLFolderAccessPicker.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLButton.h"
#import "design_system/TLWorkspaceOutlineView.h"
#import "design_system/TLChromeTabView.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void TestUnifiedWorkspaceOutline(void) {
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 280)];
  root.wantsLayer = YES;
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  root.layer.backgroundColor = TLCGColor(palette.sidebarSurface);
  TLTokenView *content = [[TLTokenView alloc] init];
  content.frame = NSMakeRect(20, 20, 360, 200);
  content.cornerRadius = palette.space5;
  content.fillColor = palette.tabBackground;
  [root addSubview:content];
  TLChromeTabSelectionView *selection = [[TLChromeTabSelectionView alloc] initWithFrame:root.bounds];
  selection.palette = palette;
  [root addSubview:selection];
  TLWorkspaceOutlineView *outline = [[TLWorkspaceOutlineView alloc] initWithFrame:root.bounds];
  outline.contentView = content;
  outline.selectionView = selection;
  [root addSubview:outline];
  outline.palette = palette;
  __weak TLWorkspaceOutlineView *weakOutline = outline;
  selection.geometryChanged = ^{ [weakOutline updateOutline]; };
  NSRect selectedRect = NSMakeRect(100, 220, 160, palette.tabHeight);
  [selection setSelectionFrame:selectedRect leadingFlareOutset:palette.tabFlareRadius
    animated:NO fromFrame:selectedRect duration:0];
  CAShapeLayer *layer = [outline valueForKey:@"outlineLayer"];
  CALayer *shadow = [outline valueForKey:@"shadowLayer"];
  CAShapeLayer *shadowMask = [outline valueForKey:@"shadowMask"];
  Check(CGPathEqualToPath(shadow.shadowPath, layer.path), @"shadow follows the unified workspace silhouette");
  Check(!CGPathContainsPoint(shadowMask.path, NULL, CGPointMake(180, 220), true), @"shadow cannot shade the tab/content join");
  Check(CGPathContainsPoint(shadowMask.path, NULL, CGPointMake(10, 100), true), @"shadow remains visible outside content");
  Check(shadow.shadowRadius == palette.workspaceShadowRadius, @"workspace shadow uses tight themed blur");
  Check(fabs(layer.opacity - 1.0 / 3.0) < 0.0001,
        @"workspace outline is one-third opacity without changing shared border colors");
  CGPathRef stroke = CGPathCreateCopyByStrokingPath(layer.path, NULL, layer.lineWidth,
    kCGLineCapButt, kCGLineJoinRound, 0);
  Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(180, 220), false), @"joined border has no seam below selected tab");
  Check(CGPathContainsPoint(stroke, NULL, CGPointMake(60, 220), false), @"content top border remains outside selection");
  Check(CGPathContainsPoint(stroke, NULL, CGPointMake(180, 220 + palette.tabHeight - palette.tabActiveHeightReduction), false), @"border follows selected tab top");
  Check(CGPathContainsPoint(stroke, NULL, CGPointMake(20, 100), false), @"border wraps content side");
  Check(!CGPathContainsPoint(layer.path, NULL, CGPointMake(20.5, 20.5), false), @"content corner remains rounded");
  CGPathRelease(stroke);
  Check([outline hitTest:NSMakePoint(50, 50)] == nil, @"outline never intercepts content or tab clicks");
  NSBitmapImageRep *preview = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
  [root cacheDisplayInRect:root.bounds toBitmapImageRep:preview];
  [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:@"/tmp/talaria-workspace-outline.png" atomically:YES];
  selectedRect.origin.x = 200;
  [selection setSelectionFrame:selectedRect leadingFlareOutset:palette.tabFlareRadius
    animated:NO fromFrame:selectedRect duration:0];
  Check(CGPathEqualToPath(shadow.shadowPath, layer.path), @"shadow moves with the selected tab on the same tick");
  stroke = CGPathCreateCopyByStrokingPath(layer.path, NULL, layer.lineWidth, kCGLineCapButt, kCGLineJoinRound, 0);
  Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(140, 254), false), @"moving selection removes old tab outline");
  Check(CGPathContainsPoint(stroke, NULL, CGPointMake(280, 220 + palette.tabHeight - palette.tabActiveHeightReduction), false), @"moving selection updates outline on the same tick");
  CGPathRelease(stroke);
  selection.hidden = YES;
  Check(CGRectGetMaxY(CGPathGetBoundingBox(layer.path)) == 220, @"hidden selection leaves only the content perimeter");
  outline.palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
  Check(CGColorEqualToColor(shadow.shadowColor, TLCGColor(outline.palette.contentShadow)), @"unified shadow follows theme changes");
  Check(CGColorEqualToColor(layer.strokeColor, TLCGColor(outline.palette.controlBorder)), @"outline follows theme border color");
  content.topLeftCornerRadius = 0;
  [outline updateOutline];
  Check(CGPathContainsPoint(layer.path, NULL, CGPointMake(20.5, 219.5), false), @"outline respects connected first-tab corner geometry");
  selection.hidden = NO;
  NSRect edgeTab = NSMakeRect(20, 220 + 0.000001, 160, palette.tabHeight);
  [selection setSelectionFrame:edgeTab leadingFlareOutset:0 animated:NO fromFrame:edgeTab duration:0];
  [outline updateOutline];
  stroke = CGPathCreateCopyByStrokingPath(layer.path, NULL, layer.lineWidth,
    kCGLineCapButt, kCGLineJoinRound, 0);
  Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(100, 220), false),
        @"subpixel layout rounding must not create an internal seam under the first selected tab");
  CGPathRelease(stroke);
  // Sidebar layout changes move content and the tab strip together. Rebuilding
  // after both frames settle must leave no outline at their previous position.
  selection.hidden = NO;
  for (NSNumber *leading in @[@80, @140, @80, @20]) {
    CGFloat x = leading.doubleValue;
    content.frame = NSMakeRect(x, 20, 380 - x, 200);
    selection.frame = NSMakeRect(x, 0, 400 - x, 280);
    NSRect localTab = NSMakeRect(0, 220, 160, palette.tabHeight);
    [selection setSelectionFrame:localTab leadingFlareOutset:0 animated:NO fromFrame:localTab duration:0];
    [outline updateOutline];
    stroke = CGPathCreateCopyByStrokingPath(layer.path, NULL, layer.lineWidth,
      kCGLineCapButt, kCGLineJoinRound, 0);
    Check(CGPathContainsPoint(stroke, NULL, CGPointMake(x, 100), false),
          @"sidebar tick keeps outline on the current content edge");
    Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(x - 10, 100), false),
          @"sidebar tick does not leave a stale content border");
    Check(!CGPathContainsPoint(stroke, NULL, CGPointMake(x + 80, 220), false),
          @"sidebar tick preserves the seamless selected-tab join");
    CGPathRelease(stroke);
  }
}

@interface TLButtonPointerWindow : NSWindow
@property (nonatomic) NSPoint testPointer;
@property (nonatomic) BOOL testVisible;
@end
@implementation TLButtonPointerWindow
- (NSPoint)mouseLocationOutsideOfEventStream { return self.testPointer; }
- (BOOL)isVisible { return self.testVisible; }
@end

static void TestCompactButtonHitAreaAndMovingHover(void) {
  TLButtonPointerWindow *window = [[TLButtonPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testVisible = YES;
  TLButton *button = [[TLButton alloc] init];
  button.translatesAutoresizingMaskIntoConstraints = YES;
  button.style = TLButtonStyleCompactMinimal;
  NSImage *icon = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"New chat"];
  button.image = icon;
  button.frame = NSMakeRect(20, 20, button.intrinsicContentSize.width, button.intrinsicContentSize.height);
  [window.contentView addSubview:button];
  [window.contentView layoutSubtreeIfNeeded];
  NSButton *clickTarget = [button valueForKey:@"button"];
  CALayer *surface = [button valueForKey:@"hoverBackgroundLayer"];
  Check(NSWidth(surface.frame) == button.palette.compactButtonSurfaceSize &&
        NSHeight(surface.frame) == NSWidth(surface.frame), @"compact surface is a smaller square");
  Check(surface.cornerRadius == button.palette.compactButtonCornerRadius, @"compact surface has rounded corners");
  Check(NSWidth(surface.frame) == 25 && NSMidX(surface.frame) == NSMidX(button.bounds) - 2,
        @"visible square is 25 points and shifted two points left without moving the hit target");
  Check(NSContainsRect(clickTarget.frame, button.bounds) && NSWidth(surface.frame) < NSWidth(button.bounds),
        [NSString stringWithFormat:@"click target remains larger than the visible background: target %@ bounds %@ surface %@",
          NSStringFromRect(clickTarget.frame), NSStringFromRect(button.bounds), NSStringFromRect(surface.frame)]);
  Check(clickTarget.image == icon && clickTarget.imageScaling == NSImageScaleNone, @"plus icon is not resized");
  Check([[clickTarget.cell valueForKey:@"imageOffsetX"] doubleValue] == button.palette.compactButtonSurfaceOffsetX,
        @"plus artwork follows the compact surface offset without moving the click target");
  button.style = TLButtonStyleMinimal;
  Check([[clickTarget.cell valueForKey:@"imageOffsetX"] doubleValue] == 0,
        @"regular buttons retain centered artwork");
  button.style = TLButtonStyleCompactMinimal;

  __block BOOL hovered = NO;
  button.hoverChanged = ^(BOOL value) { hovered = value; };
  NSPoint outerHitPoint = NSMakePoint(NSWidth(button.bounds) - 1, NSMidY(button.bounds));
  Check(!NSPointInRect(outerHitPoint, surface.frame), @"test pointer is outside the visible square");
  window.testPointer = [button convertPoint:outerHitPoint toView:nil];
  [button updateTrackingAreas];
  Check(hovered && surface.opacity == 1, @"invisible margin still activates hover");
  Check(CGColorEqualToColor(surface.backgroundColor, TLCGColor(button.palette.secondaryActionSurface)),
        @"button hover uses the same surface color as tabs");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *fade = (CABasicAnimation *)[surface animationForKey:@"tab-decoration-fade"];
    Check(fade && fade.duration == button.palette.tabHoverFadeDuration && [fade.toValue doubleValue] == 1,
          @"button hover fades in with the tab hover duration");
    Check([fade.timingFunction isEqual:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]],
          @"button hover matches tab easing");
  }
  Check([button hitTest:[button convertPoint:outerHitPoint toView:button.superview]] == clickTarget,
        @"invisible margin still receives clicks");
  button.hoverSuppressed = YES;
  Check(!hovered && surface.opacity == 0 && ![surface animationForKey:@"tab-decoration-fade"],
        @"animation suppression clears hover immediately, including its fade");
  Check(clickTarget.enabled, @"hover suppression keeps the plus button clickable");
  [button updateTrackingAreas];
  Check(!hovered && surface.opacity == 0, @"pointer events cannot restore suppressed hover");
  button.hoverSuppressed = NO;
  Check(hovered && surface.opacity == 1, @"hover resumes from the current pointer after animation");

  [button setFrameOrigin:NSMakePoint(100, 20)];
  Check(!hovered && surface.opacity == 0,
    [NSString stringWithFormat:@"moving away during tab closure clears cached hover: frame %@ pointer %@ local %@ hover %d alpha %g",
      NSStringFromRect(button.frame), NSStringFromPoint(window.testPointer),
      NSStringFromPoint([button convertPoint:window.testPointer fromView:nil]), hovered, surface.opacity]);
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    CABasicAnimation *fade = (CABasicAnimation *)[surface animationForKey:@"tab-decoration-fade"];
    Check(fade && fade.duration == button.palette.tabHoverFadeDuration && [fade.toValue doubleValue] == 0,
          @"moving away fades hover out with the tab hover duration");
  }
  NSEvent *staleEntry = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered
    location:window.testPointer modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
    context:nil eventNumber:0 trackingNumber:0 userData:NULL];
  [button mouseEntered:staleEntry];
  Check(!hovered, @"stale entry event cannot restore hover at an old position");
  button.frame = NSMakeRect(20, 20, NSWidth(button.frame), NSHeight(button.frame));
  Check(hovered, @"frame replacement also refreshes hover as the button moves under the pointer");
  [button mouseExited:staleEntry];
  Check(hovered, @"stale exit event cannot clear hover at the current position");
  window.testPointer = [button convertPoint:outerHitPoint toView:nil];
  [button updateTrackingAreas];
  Check(hovered, @"rebuilt tracking area recovers hover at the new position");
  window.testPointer = NSMakePoint(190, 90);
  [button updateTrackingAreas];
  Check(!hovered, @"rebuilt tracking area clears hover without an exit event");
  window.testPointer = [button convertPoint:outerHitPoint toView:nil];
  [button updateTrackingAreas];
  window.testVisible = NO;
  [button updateTrackingAreas];
  Check(!hovered, @"hidden window cannot retain button hover");
  [window close];
}

@interface TalariaWindowController (FeatureControllerTests)
- (NSStackView *)buildSidebarTileGrid;
- (void)rebuildSidebarAgents;
- (void)installAppStateBindings;
- (void)renderWorkspaceTabs;
- (void)updateWorkspaceMode;
- (void)updateControlStates;
- (void)activateComposerButton:(id)sender;
- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting;
- (void)loadChatWithID:(NSInteger)chatID;
- (void)applySavedChatSummary:(TLChatSummary *)summary;
- (NSString *)displayTitleForWorkspaceTab:(TLWorkspaceTab *)tab;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)renderMessages;
- (void)resetMessageRowCache;
- (void)workspaceTabsController:(nullable TLWorkspaceTabsController *)controller
                       moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index;
@end

@interface TLMessageStackRecorder : NSStackView
@property (nonatomic) NSUInteger removalCount;
@end
@implementation TLMessageStackRecorder
- (void)removeView:(NSView *)view {
  self.removalCount++;
  [super removeView:view];
}
@end

static id EvaluateChatScript(WKWebView *web, NSString *script) {
  __block BOOL done = NO;
  __block id value = nil;
  __block NSError *failure = nil;
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    value = result; failure = error; done = YES;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!done && deadline.timeIntervalSinceNow > 0) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  Check(done && !failure, [NSString stringWithFormat:@"chat JavaScript completes: %@", failure]);
  return value;
}

static void TestStreamingKeepsMessageViewsAttached(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 600)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TalariaWindowController *controller = [[TalariaWindowController alloc] initWithWindow:window];
  [controller setValue:[TLThemePalette paletteForPreference:TLThemePreferenceDark] forKey:@"palette"];
  [controller resetMessageRowCache];
  TLMessageStackRecorder *stack = [[TLMessageStackRecorder alloc] initWithFrame:window.contentView.bounds];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeWidth;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
  scroll.documentView = stack;
  [window.contentView addSubview:scroll];
  [controller setValue:scroll forKey:@"messageScrollView"];
  [controller setValue:stack forKey:@"messageStack"];
  [controller setValue:stack forKey:@"messageDocumentView"];
  TLChatMessage *user = [TLChatMessage messageWithRole:TLRoleUser content:@"Write a long answer" thinking:nil];
  TLChatMessage *assistant = [TLChatMessage messageWithRole:TLRoleAssistant content:@"First paragraph.\n\n" thinking:nil];
  NSMutableArray *messages = [NSMutableArray arrayWithObjects:user, assistant, nil];
  [controller setValue:messages forKey:@"messages"];
  [controller renderMessages];
  NSArray *rows = stack.arrangedSubviews.copy;
  NSMapTable *markdownViews = [controller valueForKey:@"messageMarkdownViews"];
  NSView *markdown = [markdownViews objectForKey:assistant];
  WKWebView *web = [markdown valueForKey:@"webView"];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (![[markdown valueForKey:@"documentReady"] boolValue] && deadline.timeIntervalSinceNow > 0) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  Check([[markdown valueForKey:@"documentReady"] boolValue], @"initial chat document loads");
  EvaluateChatScript(web, @"window.streamingTestMarker = 42");
  NSUInteger constraintCount = stack.constraints.count;
  for (NSString *chunk in @[@"Another ", @"sentence.\n\n```swift\n", @"print(\"hi\")", @"\n```\n\nDone."]) {
    assistant.content = [assistant.content stringByAppendingString:chunk];
    [controller renderMessages];
    Check([stack.arrangedSubviews isEqual:rows] && stack.removalCount == 0,
          @"streaming keeps every message row attached instead of tearing down the conversation");
    Check([markdownViews objectForKey:assistant] == markdown && [markdown valueForKey:@"webView"] == web,
          @"deltas reuse the loaded Markdown view and WebKit document");
    Check([[markdown valueForKey:@"text"] isEqual:assistant.content], @"each delta reaches the existing renderer");
    Check(stack.constraints.count == constraintCount, @"streaming does not accumulate width constraints");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    Check([EvaluateChatScript(web, @"window.streamingTestMarker") integerValue] == 42,
          @"rendering new text never reloads the web document");
    Check([EvaluateChatScript(web, @"document.body.innerText") containsString:@"First paragraph."],
          @"already visible answer text remains present throughout the stream");
  }
  Check([EvaluateChatScript(web, @"document.body.innerText") containsString:@"Done."], @"final streamed text is rendered");
  TLStoredChatMessage *saved = [TLStoredChatMessage messageWithRole:assistant.role content:assistant.content thinking:assistant.thinking];
  saved.messageID = 7;
  messages[1] = saved;
  [controller renderMessages];
  Check([stack.arrangedSubviews isEqual:rows] && [markdownViews objectForKey:saved] == markdown && stack.removalCount == 0,
        @"saving the completed answer preserves its visible row and renderer");
  [messages removeObjectAtIndex:1];
  [controller renderMessages];
  Check(stack.arrangedSubviews.count == 1 && stack.arrangedSubviews.firstObject == rows.firstObject &&
        ![markdownViews objectForKey:saved], @"deleting an answer removes only its own row and renderer");
  [controller resetMessageRowCache];
  Check(stack.arrangedSubviews.count == 0 && [[controller valueForKey:@"messageMarkdownViews"] count] == 0,
        @"theme and conversation resets discard the old renderers");
  [window close];
}

/// Keep service/rendering side effects out of this navigation/state regression.
@interface TLSendingNavigationController : TalariaWindowController
@end
@implementation TLSendingNavigationController
- (void)addChatToSessionIfNeeded:(NSInteger)chatID activate:(BOOL)activate {}
- (void)showChatWorkspace {}
- (void)resetMessageRowCache {}
- (void)selectActiveChatInHistory {}
- (void)renderMessages {}
- (void)styleSidebarActionButtons {}
- (void)updateAgentControlStates {}
- (void)hideSlashCommandList {}
- (BOOL)isChatWorkspaceActive { return YES; }
@end

@interface TLStopTestRunner : TLAssistantTurnRunner
@property NSUInteger stopCount;
@end
@implementation TLStopTestRunner
- (BOOL)running { return self.stopCount == 0; }
- (void)cancel { self.stopCount++; }
@end

static void TestStreamingComposerStopButton(void) {
  TLSendingNavigationController *controller = [[TLSendingNavigationController alloc] initWithWindow:nil];
  TLGlassMessageInput *input = [[TLGlassMessageInput alloc] init];
  TLStopTestRunner *runner = [[TLStopTestRunner alloc] initWithMessageStore:(id)[[NSObject alloc] init] streaming:(id)[[NSObject alloc] init]];
  TLChatRecord *chat = [[TLChatRecord alloc] init]; chat.chatID = 17;
  [controller setValue:input forKey:@"messageInput"];
  [controller setValue:input.textView forKey:@"promptTextView"];
  [controller setValue:input.sendButton forKey:@"sendButton"];
  [controller setValue:input.palette forKey:@"palette"];
  [controller setValue:[NSMutableDictionary dictionaryWithObject:runner forKey:@17] forKey:@"turnRunners"];
  [controller setValue:chat forKey:@"activeChat"];

  [controller updateControlStates];
  Check(input.showsStopButton && input.sendButton.image != nil && input.sendButton.enabled && input.sendButton.alphaValue == 1 &&
    [input.sendButton.toolTip isEqual:@"Stop response"], @"empty streaming composer has an active Stop button");
  for (NSString *draft in @[@"Next question", @" "]) {
    input.textView.string = draft;
    [controller updateControlStates];
    Check(!input.showsStopButton && !input.sendButton.enabled && [input.sendButton.toolTip isEqual:@"Send"],
      @"any draft restores Send and cannot accidentally stop the response");
  }
  input.textView.string = @"";
  chat.chatID = 18;
  [controller updateControlStates];
  Check(!input.showsStopButton, @"another chat cannot stop the originating chat's response");
  chat.chatID = 17;
  [controller updateControlStates];
  Check(input.showsStopButton, @"clearing the draft restores Stop");
  [controller activateComposerButton:input.sendButton];
  Check(runner.stopCount == 1, @"the composer Stop action cancels generation");
  [[controller valueForKey:@"turnRunners"] removeAllObjects];
  [controller updateControlStates];
  Check(!input.showsStopButton && !input.sendButton.enabled, @"finished empty composer returns to disabled Send");
  input.textView.string = @"Next question";
  [controller updateControlStates];
  Check(input.sendButton.enabled && !input.showsStopButton, @"draft can be sent after stopping");
}

static void TestNavigationWhileSendingPreservesTurn(void) {
  TLSendingNavigationController *controller = [[TLSendingNavigationController alloc] initWithWindow:nil];
  NSMutableArray *originalMessages = [NSMutableArray arrayWithObject:@"in-flight response"];
  [controller setValue:originalMessages forKey:@"messages"];
  [controller setValue:[NSMutableDictionary dictionaryWithObject:originalMessages forKey:@17] forKey:@"turnMessagesByChat"];
  [controller setValue:[NSMutableDictionary dictionaryWithObject:[[NSObject alloc] init] forKey:@17] forKey:@"turnRunners"];
  [controller setValue:@(-2) forKey:@"nextDraftChatID"];
  [controller setValue:[TLThemePalette paletteForPreference:TLThemePreferenceDark] forKey:@"palette"];
  NSArray *headerKeys = @[@"createChatButton", @"sidebarToggleButton"];
  for (NSString *key in headerKeys) {
    TLButton *button = [[TLButton alloc] init];
    button.enabled = NO;
    [controller setValue:button forKey:key];
  }
  NSTextView *prompt = [[NSTextView alloc] init];
  [controller setValue:prompt forKey:@"promptTextView"];
  TLButton *send = [[TLButton alloc] init];
  [controller setValue:send forKey:@"sendButton"];
  [controller startNewChatWithModel:@"test-model" focus:NO];
  Check([[controller valueForKeyPath:@"activeChat.chatID"] integerValue] == -2,
        @"new tab can open while a response is running");
  Check([controller valueForKey:@"messages"] != originalMessages && originalMessages.count == 1,
        @"navigation replaces the display buffer without clearing the running turn");
  Check([[controller valueForKey:@"turnMessagesByChat"] objectForKey:@17] == originalMessages,
        @"running turn keeps its own buffer");
  for (NSString *key in headerKeys) {
    Check([[controller valueForKey:key] isEnabled], @"header remains enabled while sending");
  }
  prompt.string = @"next draft";
  [controller updateControlStates];
  Check(prompt.editable && send.enabled, @"a new chat can send while another chat is streaming");
  Check([[controller valueForKey:@"hasSendingTurns"] boolValue] && ![[controller valueForKey:@"isSending"] boolValue],
    @"navigation keeps the original turn running without marking the new chat busy");
}

@interface TLConcurrentTestRequest : NSObject
@property NSString *requestID;
@property NSString *sessionID;
@property (copy) TLAgentStreamDeltaHandler delta;
@property (copy) TLAgentStreamCompletionHandler completion;
@end
@implementation TLConcurrentTestRequest
@end

@interface TLConcurrentTestStream : NSObject <TLAssistantTurnStreaming>
@property NSMutableArray<TLConcurrentTestRequest *> *requests;
@property NSMutableArray<NSString *> *cancelledRequests;
@end
@implementation TLConcurrentTestStream
- (instancetype)init {
  if ((self = [super init])) { _requests = [NSMutableArray array]; _cancelledRequests = [NSMutableArray array]; }
  return self;
}
- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID sessionID:(NSString *)sessionID
  token:(NSString *)token model:(NSString *)model messages:(NSArray<TLChatMessage *> *)messages
  delta:(TLAgentStreamDeltaHandler)delta completion:(TLAgentStreamCompletionHandler)completion {
  TLConcurrentTestRequest *request = [[TLConcurrentTestRequest alloc] init];
  request.requestID = requestID; request.sessionID = sessionID; request.delta = delta; request.completion = completion;
  [self.requests addObject:request];
}
- (void)cancelChatWithRequestID:(NSString *)requestID { [self.cancelledRequests addObject:requestID]; }
@end

@interface TLConcurrentTestStore : NSObject <TLAssistantTurnMessageStore>
@property NSMutableDictionary<NSNumber *, TLChatRecord *> *chats;
@property NSInteger nextMessageID;
@end
@implementation TLConcurrentTestStore
- (instancetype)init {
  if ((self = [super init])) _chats = [NSMutableDictionary dictionary];
  return self;
}
- (TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error {
  TLStoredChatMessage *saved = [TLStoredChatMessage messageWithRole:message.role content:message.content thinking:message.thinking];
  saved.messageID = ++self.nextMessageID;
  TLChatRecord *chat = self.chats[@(chatID)];
  chat.messages = [(chat.messages ?: @[]) arrayByAddingObject:saved];
  return saved;
}
- (TLChatRecord *)chatWithID:(NSInteger)chatID error:(NSError **)error { return self.chats[@(chatID)]; }
@end

@interface TLConcurrentChatController : TLSendingNavigationController
@property TLConcurrentTestStore *store;
@property TLConcurrentTestStream *stream;
@end
@implementation TLConcurrentChatController
- (TLAssistantTurnRunner *)newAssistantTurnRunner {
  return [[TLAssistantTurnRunner alloc] initWithMessageStore:self.store streaming:self.stream];
}
- (void)refreshChatsKeepingActiveSelection {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (void)presentErrorMessage:(NSString *)message { Check(NO, [@"unexpected concurrent chat error: " stringByAppendingString:message]); }
@end

static void TestConcurrentChatStreams(void) {
  TLConcurrentChatController *controller = [[TLConcurrentChatController alloc] initWithWindow:nil];
  controller.store = [[TLConcurrentTestStore alloc] init];
  controller.stream = [[TLConcurrentTestStream alloc] init];
  [controller setValue:controller.store forKey:@"database"];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"test-token"; settings.selectedModel = @"test-model";
  [controller setValue:settings forKey:@"settings"];
  TLGlassMessageInput *input = [[TLGlassMessageInput alloc] init];
  [controller setValue:input forKey:@"messageInput"];
  [controller setValue:input.textView forKey:@"promptTextView"];
  [controller setValue:input.sendButton forKey:@"sendButton"];
  [controller setValue:input.palette forKey:@"palette"];
  for (NSNumber *chatID in @[@17, @18]) {
    TLChatRecord *chat = [[TLChatRecord alloc] init];
    chat.chatID = chatID.integerValue; chat.hermesSessionID = chatID.stringValue; chat.messages = @[];
    controller.store.chats[chatID] = chat;
  }
  [controller loadChatWithID:17];
  input.textView.string = @"Question A";
  [controller sendMessage:nil allowAutomaticRouting:NO];
  TLConcurrentTestRequest *a = controller.stream.requests.lastObject;
  a.delta(a.requestID, TLAgentStreamDeltaKindContent, @"Answer A");
  NSMutableArray *messagesA = [controller valueForKey:@"messages"];
  [controller loadChatWithID:18];
  input.textView.string = @"Question B";
  [controller updateControlStates];
  Check(input.sendButton.enabled && !input.showsStopButton, @"chat B can send while A streams");
  [controller sendMessage:nil allowAutomaticRouting:NO];
  TLConcurrentTestRequest *b = controller.stream.requests.lastObject;
  NSMutableArray *messagesB = [controller valueForKey:@"messages"];
  Check(controller.stream.requests.count == 2 && [a.sessionID isEqual:@"17"] && [b.sessionID isEqual:@"18"],
    @"two independent runners dispatch separate Hermes sessions");
  a.delta(a.requestID, TLAgentStreamDeltaKindContent, @" continues");
  b.delta(b.requestID, TLAgentStreamDeltaKindContent, @"Answer B");
  Check([((TLChatMessage *)messagesA.lastObject).content isEqual:@"Answer A continues"] &&
    [((TLChatMessage *)messagesB.lastObject).content isEqual:@"Answer B"], @"interleaved deltas stay in their own chats");
  input.textView.string = @"do not duplicate B";
  [controller sendMessage:nil allowAutomaticRouting:NO];
  Check(controller.stream.requests.count == 2, @"a second turn in the same busy chat is still blocked");
  [controller loadChatWithID:17];
  Check([controller valueForKey:@"messages"] == messagesA && input.showsStopButton,
    @"returning to a streaming chat restores its live buffer and Stop button");
  [controller loadChatWithID:18];
  [controller activateComposerButton:input.sendButton];
  Check([controller.stream.cancelledRequests isEqual:@[b.requestID]] &&
    [[controller valueForKey:@"turnRunners"] count] == 1, @"Stop B leaves A running");
  input.textView.string = @"Another question B";
  [controller sendMessage:nil allowAutomaticRouting:NO];
  TLConcurrentTestRequest *b2 = controller.stream.requests.lastObject;
  input.textView.string = @"unsent draft";
  b.delta(b.requestID, TLAgentStreamDeltaKindContent, @"stale B");
  b.completion(nil);
  a.delta(a.requestID, TLAgentStreamDeltaKindContent, @" finished");
  a.completion(nil);
  Check([[controller valueForKey:@"isSending"] boolValue] && [[controller valueForKey:@"turnRunners"] count] == 1 &&
    [input.textView.string isEqual:@"unsent draft"], @"background completion cannot unlock B or replace its draft");
  input.textView.string = @"";
  [controller updateControlStates];
  Check(input.showsStopButton && input.sendButton.enabled, @"B's Stop remains active after A finishes");
  b2.delta(b2.requestID, TLAgentStreamDeltaKindContent, @"Second B answer");
  b2.completion(nil);
  [controller loadChatWithID:17];
  Check([((TLChatMessage *)[[controller valueForKey:@"messages"] lastObject]).content isEqual:@"Answer A continues finished"],
    @"completed background output persists to its original conversation");
  [controller loadChatWithID:18];
  Check([((TLChatMessage *)[[controller valueForKey:@"messages"] lastObject]).content isEqual:@"Second B answer"] &&
    ![[controller valueForKey:@"hasSendingTurns"] boolValue], @"all chats finish independently without stale callbacks");
}

// Real database and tab metadata paths, with only unrelated UI/services suppressed.
@interface TLChatTitleTestController : TalariaWindowController
@property TLConcurrentTestStream *stream;
@end
@implementation TLChatTitleTestController
- (TLAssistantTurnRunner *)newAssistantTurnRunner {
  return [[TLAssistantTurnRunner alloc] initWithMessageStore:[self valueForKey:@"database"] streaming:self.stream];
}
- (void)renderMessages {}
- (void)resetMessageRowCache {}
- (void)showChatWorkspace {}
- (void)reloadWorkspaceTabs {}
- (void)updateControlStates {}
- (void)selectActiveChatInHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (void)presentErrorMessage:(NSString *)message { Check(NO, message); }
@end

static TLChatTitleTestController *TitleController(TLDatabase *database) {
  TLChatTitleTestController *controller = [[TLChatTitleTestController alloc] initWithWindow:nil];
  controller.stream = [[TLConcurrentTestStream alloc] init];
  [controller setValue:database forKey:@"database"];
  [controller setValue:[[TLAppStateManager alloc] init] forKey:@"appStateManager"];
  [controller setValue:[[NSView alloc] init] forKey:@"chatWorkspace"];
  [controller setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [controller setValue:[NSMutableArray array] forKey:@"chats"];
  [controller setValue:@(-1) forKey:@"nextDraftChatID"];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"test-token"; settings.selectedModel = @"test-model";
  [controller setValue:settings forKey:@"settings"];
  TLGlassMessageInput *input = [[TLGlassMessageInput alloc] init];
  [controller setValue:input forKey:@"messageInput"];
  [controller setValue:input.textView forKey:@"promptTextView"];
  [controller setValue:input.palette forKey:@"palette"];
  return controller;
}

static void CheckChatTabTitle(TLChatTitleTestController *controller, NSInteger chatID, NSString *title) {
  TLAppStateManager *state = [controller valueForKey:@"appStateManager"];
  TLWorkspaceTab *tab = [state workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
  Check([tab.title isEqual:title] && [tab.toolTip isEqual:title] &&
    [[controller displayTitleForWorkspaceTab:tab] isEqual:title], @"saved chat title stays consistent in tab, tooltip, and display");
}

static void TestStreamingChatTitlesPersist(void) {
  NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
  NSURL *url = [directory URLByAppendingPathComponent:@"titles.sqlite3"];
  id credentials = [[NSObject alloc] init]; // No credentials are accessed by these database operations.
  TLDatabase *database = [[TLDatabase alloc] initWithURL:url credentialStore:credentials error:nil];
  Check(database != nil, @"title fixture database opens");
  TLChatTitleTestController *controller = TitleController(database);
  NSTextView *prompt = [controller valueForKey:@"promptTextView"];
  NSMutableArray<NSNumber *> *chatIDs = [NSMutableArray array];
  NSArray<NSString *> *titles = @[@"Write a long essay", @"Explain the stars"];
  for (NSString *title in titles) {
    [controller startNewChatWithModel:@"test-model" focus:NO];
    prompt.string = title;
    [controller sendMessage:nil allowAutomaticRouting:NO];
    NSInteger chatID = [[controller valueForKeyPath:@"activeChat.chatID"] integerValue];
    [chatIDs addObject:@(chatID)];
    CheckChatTabTitle(controller, chatID, title);
    Check([[[database chatWithID:chatID error:nil] title] isEqual:title], @"title is durable before the first stream delta");
  }
  Check([[controller valueForKey:@"turnRunners"] count] == 2, @"both naming fixtures are still streaming");
  for (NSUInteger pass = 0; pass < 3; pass++) {
    for (NSNumber *chatID in chatIDs) {
      [controller loadChatWithID:chatID.integerValue];
      for (NSUInteger index = 0; index < chatIDs.count; index++) CheckChatTabTitle(controller, chatIDs[index].integerValue, titles[index]);
    }
  }
  // Simulate a missing history entry when a background icon request finishes.
  [controller setValue:[NSMutableArray array] forKey:@"chats"];
  CheckChatTabTitle(controller, chatIDs[0].integerValue, titles[0]);
  TLChatSummary *saved = [database saveChatIcon:@"📝" chatID:chatIDs[0].integerValue error:nil];
  [controller applySavedChatSummary:saved];
  CheckChatTabTitle(controller, chatIDs[0].integerValue, titles[0]);
  Check([[controller valueForKey:@"chats"] count] == 1, @"background metadata fills a missing cache entry");
  TLConcurrentTestRequest *first = controller.stream.requests[0];
  first.delta(first.requestID, TLAgentStreamDeltaKindContent, @"Partial answer");
  [controller loadChatWithID:chatIDs[0].integerValue];
  [controller activateComposerButton:nil];
  TLConcurrentTestRequest *second = controller.stream.requests[1];
  second.delta(second.requestID, TLAgentStreamDeltaKindContent, @"Completed answer");
  second.completion(nil);
  for (NSUInteger index = 0; index < chatIDs.count; index++) CheckChatTabTitle(controller, chatIDs[index].integerValue, titles[index]);
  TLDatabase *reopened = [[TLDatabase alloc] initWithURL:url credentialStore:credentials error:nil];
  TLChatTitleTestController *restored = TitleController(reopened);
  for (NSNumber *chatID in chatIDs) [restored loadChatWithID:chatID.integerValue];
  for (NSUInteger index = 0; index < chatIDs.count; index++) CheckChatTabTitle(restored, chatIDs[index].integerValue, titles[index]);
  [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

/// Exercise the real state subscriptions and drag delegate without constructing app services or UI.
@interface TLWorkspaceRenderRecorder : TalariaWindowController
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *renderedOrders;
@end
@implementation TLWorkspaceRenderRecorder
- (void)renderWorkspaceTabs {
  TLAppStateManager *state = [self valueForKey:@"appStateManager"];
  [self.renderedOrders addObject:[state.snapshot.workspaceTabs valueForKey:@"tabID"]];
}
- (void)updateWorkspaceMode {}
- (void)updateControlStates {}
@end

static void TestDragCommitRendersBeforeDeferredReload(void) {
  TLAppStateManager *state = [[TLAppStateManager alloc] init];
  for (NSInteger tabID = 1; tabID <= 4; tabID += 1) {
    TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:tabID
      title:@"Browser" toolTip:@"Browser" URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
    [state addWorkspaceTab:tab activate:tabID == 1];
  }
  TLWorkspaceRenderRecorder *controller = [[TLWorkspaceRenderRecorder alloc] initWithWindow:nil];
  controller.renderedOrders = [NSMutableArray array];
  [controller setValue:state forKey:@"appStateManager"];
  [controller setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [controller installAppStateBindings];

  TLWorkspaceTab *movedTab = [state workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:1];
  movedTab.title = @"Updated title";
  [state upsertWorkspaceTab:movedTab activate:NO];
  [state sendSignal:TLAppSignalWorkspaceTabsChanged payload:nil];
  Check(controller.renderedOrders.count == 0, @"ordinary tab notifications defer their render");

  [controller workspaceTabsController:nil moveTab:movedTab toIndex:3];
  NSArray<NSNumber *> *expectedOrder = @[@2, @3, @4, @1];
  Check(controller.renderedOrders.count == 1, @"drop delegate renders once before returning to the drag controller");
  Check([controller.renderedOrders.firstObject isEqual:expectedOrder], @"synchronous drop render sees the committed tab order");
  Check([[controller valueForKey:@"workspaceRenderScheduled"] boolValue], @"drop preserves the pending coalesced state refresh");

  __block BOOL queueDrained = NO;
  dispatch_async(dispatch_get_main_queue(), ^{ queueDrained = YES; });
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
  while (!queueDrained && deadline.timeIntervalSinceNow > 0) {
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
  }
  Check(queueDrained, @"deferred workspace refresh completes");
  Check(controller.renderedOrders.count == 2, @"title, tab-change and move notifications coalesce into one deferred render");
  Check([controller.renderedOrders.lastObject isEqual:expectedOrder], @"deferred refresh preserves the committed drop order");
  Check(![[controller valueForKey:@"workspaceRenderScheduled"] boolValue], @"deferred refresh clears its scheduling state");
}

static NSWindow *HostController(TLFeatureTabController *controller) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSView *content = window.contentView;
  [content addSubview:controller.view];
  [NSLayoutConstraint activateConstraints:@[
    [controller.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [controller.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [controller.view.topAnchor constraintEqualToAnchor:content.topAnchor],
    [controller.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
  ]];
  [content layoutSubtreeIfNeeded];
  return window;
}

@interface TLFeatureCatalogueMock : NSObject
@property (nonatomic, copy) TLAgentModelCatalogueHandler pendingCatalogue;
- (void)fetchModelCatalogueWithToken:(NSString *)token completion:(TLAgentModelCatalogueHandler)completion;
@end
@implementation TLFeatureCatalogueMock
- (void)fetchModelCatalogueWithToken:(NSString *)token completion:(TLAgentModelCatalogueHandler)completion {
  self.pendingCatalogue = completion;
}
@end

@interface TLFeatureSettingsStoreMock : NSObject
@property (nonatomic, strong) TLAppSettings *savedSettings;
- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error;
@end
@implementation TLFeatureSettingsStoreMock
- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error {
  self.savedSettings = [settings copy];
  return self.savedSettings;
}
@end

@interface TLFeatureBrowserMock : TLChromiumBrowserController
@property (nonatomic) NSUInteger startCount;
@property (nonatomic) NSUInteger closeCount;
@property (nonatomic) NSUInteger backCount;
@property (nonatomic, copy) TLChromiumBrowserTitleHandler titleCallback;
@property (nonatomic, copy) TLChromiumBrowserURLHandler URLCallback;
@property (nonatomic, copy) TLChromiumBrowserFaviconHandler faviconCallback;
@property (nonatomic, copy) TLChromiumBrowserNavigationHandler navigationCallback;
@property (nonatomic, copy) TLChromiumBrowserLinkHandler linkCallback;
@end
@implementation TLFeatureBrowserMock
- (TLChromiumBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window
                       titleHandler:(TLChromiumBrowserTitleHandler)titleHandler
                        linkHandler:(TLChromiumBrowserLinkHandler)linkHandler
                         URLHandler:(TLChromiumBrowserURLHandler)URLHandler
                     faviconHandler:(TLChromiumBrowserFaviconHandler)faviconHandler
                  navigationHandler:(TLChromiumBrowserNavigationHandler)navigationHandler {
  self.startCount += 1;
  self.titleCallback = titleHandler;
  self.URLCallback = URLHandler;
  self.faviconCallback = faviconHandler;
  self.navigationCallback = navigationHandler;
  self.linkCallback = linkHandler;
  return [[TLChromiumBrowserSession alloc] init];
}
- (void)closeSession:(TLChromiumBrowserSession *)session { if (session) self.closeCount += 1; }
- (void)goBackInSession:(TLChromiumBrowserSession *)session { self.backCount += 1; }
@end

static void TestSettingsThemeAndLateCatalogue(void) {
  TLFeatureCatalogueMock *catalogue = [[TLFeatureCatalogueMock alloc] init];
  TLFeatureSettingsStoreMock *store = [[TLFeatureSettingsStoreMock alloc] init];
  TLSettingsTabController *controller = [[TLSettingsTabController alloc]
    initWithSettings:[TLAppSettings defaultSettings] database:(TLDatabase *)store
    orchestrator:(TLAgentOrchestrator *)catalogue
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = HostController(controller);
  NSSecureTextField *token = [controller valueForKey:@"tokenField"];
  TLModelPickerView *picker = [controller valueForKey:@"mainModelPicker"];
  NSSearchField *search = [picker valueForKey:@"searchField"];
  NSPopUpButton *theme = [controller valueForKey:@"themePopup"];
  NSMutableArray<TLOpenRouterModel *> *models = [NSMutableArray array];
  for (NSUInteger index = 0; index < 40; index += 1) {
    TLOpenRouterModel *model = [[TLOpenRouterModel alloc] init];
    model.modelID = [NSString stringWithFormat:@"test/model-%lu", (unsigned long)index];
    model.name = model.modelID;
    [models addObject:model];
  }
  [picker setModels:models];
  [window.contentView layoutSubtreeIfNeeded];
  NSTableView *modelTable = [picker valueForKey:@"tableView"];
  NSScrollView *modelScroll = modelTable.enclosingScrollView;
  [modelScroll.contentView scrollToPoint:NSMakePoint(0, 200)];
  NSPoint modelScrollOrigin = modelScroll.contentView.bounds.origin;
  token.stringValue = @"test-only-unsaved-token";
  search.stringValue = @"draft model search";
  [theme selectItemAtIndex:TLThemePreferenceDark];
  [window makeFirstResponder:search];
  NSResponder *responder = window.firstResponder;
  NSView *view = controller.view;
  TLThemePalette *dark = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [controller applyPalette:dark];
  Check(controller.view == view && [controller valueForKey:@"tokenField"] == token, @"settings theme keeps existing controls");
  Check([token.stringValue isEqualToString:@"test-only-unsaved-token"] && [search.stringValue isEqualToString:@"draft model search"], @"settings drafts survive theme change");
  Check(window.firstResponder == responder && theme.indexOfSelectedItem == TLThemePreferenceDark, @"settings focus and theme draft survive palette application");
  Check(NSEqualPoints(modelScroll.contentView.bounds.origin, modelScrollOrigin), @"model catalogue scroll position survives palette application");
  Check([token.textColor isEqual:dark.controlText] && [picker.fillColor isEqual:dark.controlSurface], @"settings controls and model pickers update theme");
  __block TLAppSettings *saved = nil;
  controller.settingsSavedHandler = ^(TLAppSettings *settings) { saved = settings; };
  NSButton *save = [controller valueForKey:@"saveButton"];
  [NSApp sendAction:save.action to:save.target from:save];
  Check([saved.openRouterToken isEqualToString:token.stringValue] && saved.theme == TLThemePreferenceDark, @"settings owner saves current control drafts");
  NSButton *reload = [controller valueForKey:@"reloadButton"];
  [NSApp sendAction:reload.action to:reload.target from:reload];
  Check(catalogue.pendingCatalogue != nil && !reload.enabled, @"settings owns catalogue loading state");
  NSTextField *status = [controller valueForKey:@"catalogueStatusLabel"];
  NSString *pendingStatus = status.stringValue;
  [controller close];
  catalogue.pendingCatalogue(@[], nil);
  Check([status.stringValue isEqualToString:pendingStatus] && !reload.enabled, @"late catalogue callback cannot mutate closed settings");
  [window close];
}

static void TestBrowserOwnsCallbacksAndSession(void) {
  TLFeatureBrowserMock *service = [[TLFeatureBrowserMock alloc] init];
  TLFeatureSettingsStoreMock *store = [[TLFeatureSettingsStoreMock alloc] init];
  TLFeatureCatalogueMock *orchestrator = [[TLFeatureCatalogueMock alloc] init];
  __weak TLBrowserTabController *releasedController;
  @autoreleasepool {
    TLBrowserTabController *controller = [[TLBrowserTabController alloc]
      initWithURL:[NSURL URLWithString:@"https://example.com/start"] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]
      database:(TLDatabase *)store orchestrator:(TLAgentOrchestrator *)orchestrator inputWidth:480 browserService:service];
    releasedController = controller;
    NSWindow *window = HostController(controller);
    __block NSUInteger metadataChanges = 0;
    __block NSString *title = nil;
    __block NSURL *currentURL = nil;
    controller.metadataChangedHandler = ^(NSString *nextTitle, NSURL *URL) {
      metadataChanges += 1; title = nextTitle; currentURL = URL;
    };
    [controller startInWindow:window];
    [controller startInWindow:window];
    Check(service.startCount == 1, @"browser session starts once");
    TLBrowserAddressInput *input = [controller valueForKey:@"browserAddressInput"];
    [input beginPromptEditing];
    input.textView.string = @"unfinished browser prompt";
    [window makeFirstResponder:input.textView];
    service.titleCallback(@"Example title");
    service.URLCallback([NSURL URLWithString:@"https://example.com/next"]);
    Check([title isEqualToString:@"Example title"] && [currentURL.path isEqualToString:@"/next"], @"browser callbacks publish tab metadata");
    Check([input.textView.string isEqualToString:@"unfinished browser prompt"], @"page navigation preserves an address draft");
    service.navigationCallback(YES, NO, NO);
    Check(input.backButton.enabled && !input.forwardButton.enabled, @"browser owns navigation control state");
    [NSApp sendAction:input.backButton.action to:input.backButton.target from:input.backButton];
    Check(service.backCount == 1, @"browser navigation targets its controller");
    NSView *content = controller.view;
    [controller applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
    Check(controller.view == content && window.firstResponder == input.textView &&
      [input.textView.string isEqualToString:@"unfinished browser prompt"], @"browser theme preserves content, draft and focus");
    TLChromiumBrowserTitleHandler lateTitle = service.titleCallback;
    NSUInteger changesBeforeClose = metadataChanges;
    [controller close];
    [controller close];
    lateTitle(@"late title");
    Check(service.closeCount == 1 && metadataChanges == changesBeforeClose, @"browser closing is idempotent and ignores late callbacks");
    Check(input.sendButton.target == nil && input.backButton.target == nil, @"closed browser detaches control actions");
    [window close];
  }
  Check(releasedController == nil, @"browser callbacks do not retain their controller");
}

@interface TLAgentSelectionStoreMock : NSObject
@property (nonatomic) NSInteger currentAgentID;
@end
@implementation TLAgentSelectionStoreMock
@end

static void TestRealSidebarAgents(void) {
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 64)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TalariaWindowController *controller = [[TalariaWindowController alloc] initWithWindow:window];
  [controller setValue:palette forKey:@"palette"];
  TLAgentSelectionStoreMock *store = [TLAgentSelectionStoreMock new];
  store.currentAgentID = 12;
  [controller setValue:store forKey:@"database"];
  NSMutableArray *agents = [NSMutableArray array];
  for (NSInteger index = 10; index < 15; index++) {
    TLAgentRecord *agent = [TLAgentRecord new];
    agent.agentID = index;
    agent.name = [NSString stringWithFormat:@"Agent %ld", (long)index];
    agent.avatar = @[@"🦊", @"🐼", @"🌙", @"🐙", @"🦉"][(NSUInteger)(index - 10)];
    [agents addObject:agent];
  }
  [controller setValue:agents forKey:@"agents"];
  NSStackView *grid = [controller buildSidebarTileGrid];
  [controller setValue:grid forKey:@"sidebarTileGrid"];
  [window.contentView addSubview:grid];
  [NSLayoutConstraint activateConstraints:@[
    [grid.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [grid.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [grid.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [grid.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
  ]];
  [window.contentView layoutSubtreeIfNeeded];
  [controller rebuildSidebarAgents];
  [window.contentView layoutSubtreeIfNeeded];
  NSScrollView *scroll = (NSScrollView *)grid.arrangedSubviews.firstObject;
  NSStackView *tiles = (NSStackView *)scroll.documentView;
  Check(tiles.arrangedSubviews.count == 5, @"sidebar contains only persisted agents");
  NSUInteger selected = 0;
  for (TLIconTileView *tile in tiles.arrangedSubviews) {
    if (tile.selected) selected++;
    Check(NSWidth(tile.bounds) > 0 && NSHeight(tile.bounds) > 0, @"agent tiles remain visible in scrolling sidebar");
  }
  Check(selected == 1 && ((TLIconTileView *)tiles.arrangedSubviews[2]).selected, @"sidebar marks actual selected agent");
  Check(NSWidth(tiles.bounds) > NSWidth(scroll.bounds), @"extra agents remain horizontally scrollable");
  NSString *preview = NSProcessInfo.processInfo.environment[@"TL_AGENT_SIDEBAR_PREVIEW"];
  if (preview.length) {
    NSBitmapImageRep *bitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
    [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:preview atomically:YES];
  }
  [controller setValue:@[] forKey:@"agents"];
  [controller rebuildSidebarAgents];
  scroll = (NSScrollView *)grid.arrangedSubviews.firstObject;
  tiles = (NSStackView *)scroll.documentView;
  Check(tiles.arrangedSubviews.count == 0, @"empty sidebar contains no placeholder or creation tiles");
  [window close];
}

static void TestNativeEmojiInput(void) {
  TLEmojiPicker *picker = [[TLEmojiPicker alloc] init];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window.contentView addSubview:picker];
  Check([window makeFirstResponder:picker] && window.firstResponder == picker && picker.inputContext.client == picker,
        @"native emoji input targets the avatar control instead of another form field");
  __block NSUInteger changes = 0;
  picker.emojiChangedHandler = ^(NSString *emoji) { changes++; };
  for (NSString *emoji in @[@"🥹", @"👩🏽‍💻", @"🏳️‍🌈", @"🇦🇺", @"1️⃣", @"👨‍👩‍👧‍👦"]) {
    [picker insertText:[[NSAttributedString alloc] initWithString:emoji] replacementRange:NSMakeRange(NSNotFound, 0)];
    Check([picker.emoji isEqual:emoji] && [picker.title isEqual:emoji], @"native picker commits a complete emoji, including compound sequences");
  }
  Check(changes == 6, @"native selection updates the avatar");
  NSString *previous = picker.emoji;
  for (NSString *invalid in @[@"", @"hello", @"1", @"#", @"*", @"🦊🐼"]) {
    [picker insertText:invalid replacementRange:picker.selectedRange];
  }
  Check([picker.emoji isEqual:previous] && changes == 6, @"non-emoji text and multiple emojis preserve the avatar");
  [picker setMarkedText:@"search" selectedRange:NSMakeRange(6, 0) replacementRange:picker.selectedRange];
  Check(picker.hasMarkedText && [picker.emoji isEqual:previous], @"composition does not replace the avatar before commit");
  [picker unmarkText];
  Check(!picker.hasMarkedText && [picker.emoji isEqual:previous], @"cancelled selection preserves the avatar");
  picker.enabled = NO;
  [picker insertText:@"🦊" replacementRange:picker.selectedRange];
  Check([picker.emoji isEqual:previous], @"disabled picker cannot change an agent during provisioning");
  [window close];
}

static void TestFolderAccessTable(void) {
  TLFolderAccessPicker *picker = [[TLFolderAccessPicker alloc] init];
  Check([picker.tableView isKindOfClass:NSTableView.class] && picker.folderPaths.count == 0,
        @"folder access starts with an empty native table");
  NSArray<NSButton *> *shortcuts = [picker valueForKey:@"shortcutButtons"];
  Check(shortcuts.count == 5, @"offers disk, home, desktop, documents and downloads shortcuts");
  [shortcuts[0] performClick:nil];
  [shortcuts[1] performClick:nil];
  [shortcuts[1] performClick:nil];
  NSString *home = NSFileManager.defaultManager.homeDirectoryForCurrentUser.path.stringByStandardizingPath;
  Check([picker.folderPaths isEqual:@[@"/", home]], @"disk and home shortcuts add real paths without duplicates");
  [shortcuts[2] performClick:nil];
  [shortcuts[3] performClick:nil];
  [shortcuts[4] performClick:nil];
  Check(picker.folderPaths.count == 5 && picker.tableView.numberOfRows == 5, @"common location shortcuts populate native rows");
  [picker.tableView selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)] byExtendingSelection:NO];
  [picker setPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  Check(picker.tableView.selectedRowIndexes.count == 3, @"theme changes preserve folder selection");
  NSButton *remove = [picker valueForKey:@"removeButton"];
  Check(remove.enabled, @"remove becomes available for selected folders");
  [remove performClick:nil];
  Check(picker.folderPaths.count == 2 && [picker.folderPaths.firstObject isEqual:@"/"], @"removes all selected rows while preserving remaining paths");
  NSArray *remaining = picker.folderPaths;
  picker.enabled = NO;
  [shortcuts[1] performClick:nil];
  Check([picker.folderPaths isEqual:remaining] && !remove.enabled && !shortcuts[1].enabled,
        @"folder permissions cannot be changed during provisioning");
  picker.enabled = YES;
  [picker.tableView selectAll:nil];
  [remove performClick:nil];
  Check(picker.folderPaths.count == 0 && !remove.enabled && ![[picker valueForKey:@"emptyLabel"] isHidden],
        @"removing every folder restores the empty state");
}

@interface TLAgentCreationStoreMock : NSObject
@property (nonatomic) NSUInteger creationCount;
@property (nonatomic, strong) TLAgentRecord *savedProfile;
@end
@implementation TLAgentCreationStoreMock
- (TLAgentRecord *)createAgentWithName:(NSString *)name avatar:(NSString *)avatar soul:(NSString *)soul
                         folderPaths:(NSArray<NSString *> *)paths error:(NSError **)error {
  if (!name.length) {
    if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Give your agent a name."}];
    return nil;
  }
  self.creationCount++;
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = 42;
  agent.name = name;
  return agent;
}
- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID name:(NSString *)name avatar:(NSString *)avatar soul:(NSString *)soul error:(NSError **)error {
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = agentID;
  agent.name = name;
  agent.avatar = avatar;
  agent.soul = soul;
  self.savedProfile = agent;
  return agent;
}
@end

static void TestAgentCreationForm(void) {
  TLThemePalette *dark = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  TLAgentCreationWindowController *controller = [[TLAgentCreationWindowController alloc] initWithPalette:dark orchestrator:(id)[TLAgentCreationStoreMock new]];
  NSWindow *window = controller.window;
  [window.contentView layoutSubtreeIfNeeded];
  NSTextField *name = [controller valueForKey:@"nameField"];
  NSTextView *soul = [controller valueForKey:@"soulView"];
  TLEmojiPicker *avatar = [controller valueForKey:@"avatarPicker"];
  name.stringValue = @"Atlas";
  soul.string = @"My agent's soul";
  avatar.emoji = @"🦊";
  [controller applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  Check([name.stringValue isEqual:@"Atlas"] && [soul.string isEqual:@"My agent's soul"] && [avatar.emoji isEqual:@"🦊"],
        @"theme changes preserve the agent profile draft");
  Check([[controller valueForKey:@"folderPaths"] count] == 0, @"agent creation defaults to no folder access");
  Check(NSWidth(name.bounds) > 0 && NSHeight(soul.bounds) > 0, @"profile fields are laid out");
  NSButton *create = [controller valueForKey:@"createButton"];
  NSRect buttonFrame = [create convertRect:create.bounds toView:window.contentView];
  Check(NSContainsRect(window.contentView.bounds, buttonFrame), @"creation action stays visible below the native form");
  TLFolderAccessPicker *folders = [controller valueForKey:@"folderPicker"];
  folders.folderPaths = @[@"/", NSFileManager.defaultManager.homeDirectoryForCurrentUser.path,
    [NSFileManager.defaultManager.homeDirectoryForCurrentUser.path stringByAppendingPathComponent:@"Documents"]];
  [window.contentView layoutSubtreeIfNeeded];
  NSRect tableFrame = [folders.tableView.enclosingScrollView convertRect:folders.tableView.enclosingScrollView.bounds toView:window.contentView];
  Check(NSContainsRect(window.contentView.bounds, tableFrame) && NSMinY(tableFrame) > NSMaxY(buttonFrame),
        @"folder table fits above the footer without an outer scrollbar");
  NSString *preview = NSProcessInfo.processInfo.environment[@"TL_AGENT_FORM_PREVIEW"];
  if (preview.length) {
    for (NSNumber *darkMode in @[@YES, @NO]) {
      [controller applyPalette:[TLThemePalette paletteForPreference:darkMode.boolValue ? TLThemePreferenceDark : TLThemePreferenceLight]];
      [window.contentView layoutSubtreeIfNeeded];
      NSBitmapImageRep *bitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
      [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
      NSString *path = darkMode.boolValue ? preview : [preview.stringByDeletingPathExtension stringByAppendingString:@"-light.png"];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
  }
  NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 700)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  parent.releasedWhenClosed = NO;
  [controller showFromWindow:parent];
  name.stringValue = @"";
  [create performClick:nil];
  Check([controller valueForKey:@"createdAgentID"] && [[controller valueForKey:@"createdAgentID"] integerValue] == 0,
        @"validation failure does not submit an agent");
  Check(window.sheetParent == parent, @"invalid profile stays in the creation sheet");
  name.stringValue = @"Atlas";
  __block NSUInteger submissions = 0;
  controller.agentCreatedHandler = ^(TLAgentRecord *agent) {
    submissions++;
    Check(!window.visible && agent.agentID == 42, @"creation sheet closes before background initialization is handed off");
  };
  [create performClick:nil];
  [create performClick:nil];
  Check(submissions == 1, @"creation hands off exactly once without waiting for an installer");
  [parent close];
  [window close];
}

static void TestAgentSettingsForm(void) {
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = 17;
  agent.name = @"Atlas";
  agent.avatar = @"🦊";
  agent.soul = @"Be thoughtful and curious.";
  TLAgentCreationStoreMock *store = [TLAgentCreationStoreMock new];
  TLAgentCreationWindowController *controller = [[TLAgentCreationWindowController alloc] initWithAgent:agent
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] orchestrator:(id)store];
  NSTextField *name = [controller valueForKey:@"nameField"];
  TLEmojiPicker *avatar = [controller valueForKey:@"avatarPicker"];
  NSTextView *soul = [controller valueForKey:@"soulView"];
  Check([name.stringValue isEqual:agent.name] && [avatar.emoji isEqual:agent.avatar] && [soul.string isEqual:agent.soul], @"settings preload the selected agent profile");
  [controller.window.contentView layoutSubtreeIfNeeded];
  NSString *preview = NSProcessInfo.processInfo.environment[@"TL_AGENT_SETTINGS_PREVIEW"];
  if (preview.length) {
    NSView *view = controller.window.contentView;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:preview atomically:YES];
  }
  name.stringValue = @"Nova";
  avatar.emoji = @"🌟";
  soul.string = @"";
  [controller applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSButton *cancel = [controller valueForKey:@"cancelButton"];
  [cancel performClick:nil];
  Check(store.savedProfile == nil, @"cancel does not mutate the profile");
  __block BOOL saved = NO;
  controller.agentUpdatedHandler = ^(TLAgentRecord *updated) { saved = YES; };
  NSButton *save = [controller valueForKey:@"createButton"];
  [save performClick:nil];
  Check(saved && store.savedProfile.agentID == 17 && store.creationCount == 0, @"editing saves the selected agent without provisioning another VM");
  Check([store.savedProfile.name isEqual:@"Nova"] && [store.savedProfile.avatar isEqual:@"🌟"] && store.savedProfile.soul.length == 0,
    @"profile draft survives theme changes and saves all three fields");
  [controller.window close];
}

@interface TLFolderAccessStoreMock : NSObject
@property (nonatomic, copy) NSArray<NSString *> *savedPaths;
@property (nonatomic) NSInteger savedAgentID;
@property (nonatomic) BOOL failSave;
@end
@implementation TLFolderAccessStoreMock
- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID folderPaths:(NSArray<NSString *> *)paths error:(NSError **)error {
  if (self.failSave) {
    if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Folder unavailable"}];
    return nil;
  }
  self.savedPaths = paths;
  self.savedAgentID = agentID;
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = agentID;
  return agent;
}
@end

static void TestAgentFolderEditing(void) {
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = 72;
  agent.name = @"Atlas";
  agent.avatar = @"🦊";
  agent.folderPaths = @[@"/", NSFileManager.defaultManager.homeDirectoryForCurrentUser.path];
  TLFolderAccessStoreMock *store = [TLFolderAccessStoreMock new];
  TLAgentFolderAccessWindowController *controller = [[TLAgentFolderAccessWindowController alloc]
    initWithAgent:agent palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] orchestrator:(id)store];
  TLFolderAccessPicker *picker = [controller valueForKey:@"folderPicker"];
  Check([picker.folderPaths isEqual:agent.folderPaths], @"folder editor opens the selected agent's saved folders");
  [controller.window.contentView layoutSubtreeIfNeeded];
  NSRect frame = [picker convertRect:picker.bounds toView:controller.window.contentView];
  Check(NSContainsRect(controller.window.contentView.bounds, frame), @"folder editor table fits inside its sheet");
  NSString *preview = NSProcessInfo.processInfo.environment[@"TL_AGENT_FOLDERS_PREVIEW"];
  if (preview.length) {
    [NSApp activateIgnoringOtherApps:YES];
    [controller.window makeKeyAndOrderFront:nil];
    for (NSNumber *dark in @[@YES, @NO]) {
      [controller applyPalette:[TLThemePalette paletteForPreference:dark.boolValue ? TLThemePreferenceDark : TLThemePreferenceLight]];
      [controller.window.contentView layoutSubtreeIfNeeded];
      [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
      NSView *view = controller.window.contentView;
      NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
      [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
      NSString *path = dark.boolValue ? preview : [preview.stringByDeletingPathExtension stringByAppendingString:@"-light.png"];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
  }
  picker.folderPaths = @[];
  [controller applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  Check(picker.folderPaths.count == 0 && agent.folderPaths.count == 2 && store.savedPaths == nil,
    @"theme changes preserve the draft without modifying saved agent folders");
  NSButton *cancel = [controller valueForKey:@"cancelButton"];
  [cancel performClick:nil];
  Check(store.savedPaths == nil, @"cancel leaves the saved folder list untouched");
  __block BOOL saved = NO;
  controller.savedHandler = ^{ saved = YES; };
  store.failSave = YES;
  NSButton *save = [controller valueForKey:@"saveButton"];
  [save performClick:nil];
  Check(!saved && [[controller valueForKey:@"statusLabel"] stringValue].length > 0, @"save failure reports an error and preserves the draft");
  store.failSave = NO;
  [save performClick:nil];
  Check(saved && store.savedAgentID == 72 && store.savedPaths.count == 0, @"save removes all folders only for the selected agent");
  [controller.window close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestNativeEmojiInput();
    TestFolderAccessTable();
    TestAgentCreationForm();
    TestAgentFolderEditing();
    TestAgentSettingsForm();
    TestRealSidebarAgents();
    TestSettingsThemeAndLateCatalogue();
    TestBrowserOwnsCallbacksAndSession();
    TestDragCommitRendersBeforeDeferredReload();
    TestStreamingChatTitlesPersist();
    TestConcurrentChatStreams();
    TestStreamingComposerStopButton();
    TestNavigationWhileSendingPreservesTurn();
    TestStreamingKeepsMessageViewsAttached();
    TestCompactButtonHitAreaAndMovingHover();
    TestUnifiedWorkspaceOutline();
    NSLog(@"FeatureControllerTests passed");
  }
  return 0;
}
