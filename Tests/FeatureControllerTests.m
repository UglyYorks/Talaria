#import "TLBrowserContentColor.h"
#import "TLChatControllerTestSupport.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLMessageInput.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import "TLBrowserTabController.h"
#import "TLBrowserContentColor.h"
#import "TLSettingsTabController.h"
#import "TLBrowserSettingsController.h"
#import "TLBrowserPreferences.h"
#import "design_system/TLSettingsWorkspaceView.h"
#import "design_system/TLShortcutRecorder.h"
#import "TLApplicationSettingsController.h"
#import "TLGlobalShortcut.h"
#import <Carbon/Carbon.h>
#import "TLModelSelectionWindowController.h"
#import "TLProviderSetupWindowController.h"
#import "AgentOrchestrator.h"
#import "AssistantTurnRunner.h"
#import "TLChatTabController.h"
#import "design_system/ModelPickerView.h"
#import "UIComponents.h"
#import "TalariaWindowController.h"
#import "TLQuickInputWindowController.h"
#import "TLAgentCreationWindowController.h"
#import "TLAgentFolderAccessWindowController.h"
#import "design_system/TLEmojiPicker.h"
#import "design_system/TLFolderAccessPicker.h"
#import "design_system/TLSkillsPicker.h"
#import "TLWorkspaceTabsController.h"
#import "TLWorkspaceSplitState.h"
#import "design_system/TLButton.h"
#import "design_system/TLThemedButton.h"
#import "TLHistoryPanelController.h"
#import "design_system/TLTabIconView.h"
#import "design_system/TLApprovalCardView.h"
#import "design_system/TLWorkspaceOutlineView.h"
#import "design_system/TLChromeTabView.h"
#import "design_system/TLToolActivityView.h"
#import "design_system/TLThinkingBubbleView.h"
#import "design_system/TLToolStatusPill.h"

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
  Check(CGColorEqualToColor(surface.backgroundColor, TLCGColor(button.palette.itemHighlightSurface)),
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
- (void)handleFileURLsDroppedOnNotch:(NSArray<NSURL *> *)URLs;
- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)selector;
- (void)sendMessage:(id)sender;
- (NSStackView *)buildSidebarTileGrid;
- (void)rebuildSidebarAgents;
- (NSView *)buildDebugTabContent;
- (void)refreshDebugTerminalAvailability;
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
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom;
- (void)scheduleStreamingMessageRender;
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

@interface TLChatTabController (RenderingProbe)
- (NSView *)cachedRowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail;
- (void)renderDirtyMessages;
@end
@interface TLCountingChatController : TLChatTabController
@property NSUInteger renderCount;
@property NSUInteger rowVisits;
@end
@implementation TLCountingChatController
- (NSView *)cachedRowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail {
  self.rowVisits++;
  return [super cachedRowForMessage:message showsOutgoingTail:tail];
}
- (void)renderDirtyMessages {
  NSUInteger before = self.renderCount;
  [super renderDirtyMessages];
  if (self.renderCount == before) self.renderCount++;
}
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom {
  self.renderCount++;
  [super renderMessagesScrollingToBottom:scrollToBottom];
}
@end
@interface TLStreamingRenderRecorder : TalariaWindowController
@property (readonly) NSUInteger renderCount;
@end
@implementation TLStreamingRenderRecorder
- (TLChatTabController *)newChatTabController { return [TLCountingChatController new]; }
- (NSUInteger)renderCount { return [(TLCountingChatController *)[self valueForKey:@"chatPresentation"] renderCount]; }
@end

static void TestStreamingKeepsMessageViewsAttached(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 600)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLStreamingRenderRecorder *controller = [[TLStreamingRenderRecorder alloc] initWithWindow:window];
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
  TLChatMessage *assistant = [TLChatMessage messageWithRole:TLRoleAssistant content:@"" thinking:nil];
  [assistant applyToolActivity:@{@"id":@"tool-1", @"name":@"terminal", @"state":@"running", @"detail":@"make test"}];
  NSMutableArray *messages = [NSMutableArray arrayWithObjects:user, assistant, nil];
  [controller setValue:messages forKey:@"messages"];
  [controller renderMessages];
  NSMapTable *activityViews = [[controller valueForKey:@"chatPresentation"] valueForKey:@"messageActivityViews"];
  Check(![activityViews objectForKey:assistant], @"tools are presented outside the transcript");
  assistant.content = @"First paragraph.\n\n";
  [controller renderMessages];
  stack.removalCount = 0;
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
  [assistant applyToolActivity:@{@"id":@"tool-1", @"name":@"terminal", @"state":@"completed", @"summary":@"Tests passed"}];
  [controller renderMessages];
  Check([markdownViews objectForKey:assistant] == markdown, @"tool completion preserves the streamed answer renderer");
  EvaluateChatScript(web, @"window.domRenderCount = 0; const render = window.talariaRender; window.talariaRender = source => { window.domRenderCount++; render(source); }; true;");
  [controller renderMessages];
  [controller renderMessages];
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  Check([EvaluateChatScript(web, @"window.domRenderCount") integerValue] == 0,
        @"unchanged messages do not reparse Markdown or replace the DOM");
  NSUInteger renderCount = controller.renderCount;
  TLCountingChatController *chatRenderer = [controller valueForKey:@"chatPresentation"];
  NSUInteger rowVisits = chatRenderer.rowVisits;
  for (NSUInteger i = 0; i < 100; i++) {
    assistant.content = [assistant.content stringByAppendingString:@" x"];
    [chatRenderer markMessageDirty:assistant];
    [controller scheduleStreamingMessageRender];
  }
  Check(controller.renderCount == renderCount, @"a burst of tokens defers native layout");
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
  Check(controller.renderCount == renderCount + 1, @"a burst of tokens performs one native transcript update");
  Check(chatRenderer.rowVisits == rowVisits + 1, @"streaming updates visit only the dirty message row");
  Check([[markdown valueForKey:@"text"] isEqual:assistant.content] &&
        [EvaluateChatScript(web, @"window.domRenderCount") integerValue] == 1,
        @"batched rendering preserves the entire response in the same document");
  [controller scheduleStreamingMessageRender];
  [controller renderMessagesScrollingToBottom:NO];
  renderCount = controller.renderCount;
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  Check(controller.renderCount == renderCount, @"immediate navigation or completion invalidates an older pending render");
  TLStoredChatMessage *saved = [TLStoredChatMessage messageWithRole:assistant.role content:assistant.content thinking:assistant.thinking];
  saved.toolActivities = assistant.toolActivities;
  saved.messageID = 7;
  messages[1] = saved;
  [controller renderMessages];
  Check([stack.arrangedSubviews isEqual:rows] && [markdownViews objectForKey:saved] == markdown && stack.removalCount == 0,
        @"saving the completed answer preserves its visible row and renderer");
  Check(![activityViews objectForKey:saved], @"saving does not restore inline tool activity");
  [messages removeObjectAtIndex:1];
  [controller renderMessages];
  Check(stack.arrangedSubviews.count == 1 && stack.arrangedSubviews.firstObject == rows.firstObject &&
        ![markdownViews objectForKey:saved], @"deleting an answer removes only its own row and renderer");
  Check(![activityViews objectForKey:saved], @"deleting an answer releases its tool activity view");
  [controller scheduleStreamingMessageRender];
  [controller resetMessageRowCache];
  renderCount = controller.renderCount;
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  Check(controller.renderCount == renderCount, @"closing a transcript cancels its pending render");
  Check(stack.arrangedSubviews.count == 0 && [[controller valueForKey:@"messageMarkdownViews"] count] == 0,
        @"theme and conversation resets discard the old renderers");
  chatRenderer.chat = [TLChatRecord new];
  chatRenderer.chat.title = @"AWS Oregon Outage";
  TLChatMessage *outage = [TLChatMessage messageWithRole:TLRoleAssistant
    content:@"AWS is reporting an outage in the Oregon region." thinking:nil];
  TLChatMessage *later = [TLChatMessage messageWithRole:TLRoleAssistant content:@"" thinking:@"Checking status"];
  chatRenderer.messages = [NSMutableArray arrayWithObjects:outage, user, later, nil];
  [controller renderMessages];
  NSArray *intentRows = stack.arrangedSubviews.copy;
  Check(intentRows.count == 4, @"an intent widget occupies its own transcript row");
  later.content = @"Status checked";
  [chatRenderer markMessageDirty:later];
  [chatRenderer renderDirtyMessages];
  Check(stack.arrangedSubviews.count == 4 && stack.arrangedSubviews[1] == intentRows[1] &&
    stack.arrangedSubviews[2] == intentRows[2] &&
    stack.arrangedSubviews[3] == [chatRenderer.messageRowViews objectForKey:later],
    @"a dirty row changing display mode keeps its position after an earlier intent widget");
  [window close];
}

static NSButton *FindResetButton(NSView *view) {
  if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).action == NSSelectorFromString(@"resetApp:")) return (NSButton *)view;
  for (NSView *child in view.subviews) {
    NSButton *button = FindResetButton(child);
    if (button) return button;
  }
  return nil;
}

static void RGBComponents(NSColor *color, CGFloat rgb[3], CGFloat *alpha) {
  [[color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] getRed:&rgb[0] green:&rgb[1] blue:&rgb[2] alpha:alpha];
}

static void CompositeColor(NSColor *color, CGFloat opacity, CGFloat rgb[3]) {
  CGFloat foreground[3], alpha;
  RGBComponents(color, foreground, &alpha);
  alpha *= opacity;
  for (NSUInteger i = 0; i < 3; i++) rgb[i] = foreground[i] * alpha + rgb[i] * (1 - alpha);
}

static BOOL PixelMatches(NSBitmapImageRep *bitmap, NSInteger x, NSInteger y, CGFloat expected[3]) {
  CGFloat actual[3], alpha;
  RGBComponents([bitmap colorAtX:x y:y], actual, &alpha);
  return fabs(actual[0] - expected[0]) < 0.04 && fabs(actual[1] - expected[1]) < 0.04 && fabs(actual[2] - expected[2]) < 0.04;
}

static NSBitmapImageRep *RenderThemedButton(TLThemedButton *button) {
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:ceil(NSWidth(button.bounds)) pixelsHigh:ceil(NSHeight(button.bounds)) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  [button.palette.tabBackground setFill];
  NSRectFill(button.bounds);
  [button.cell drawWithFrame:button.bounds inView:button];
  [NSGraphicsContext restoreGraphicsState];
  return bitmap;
}

static void TestItemHoverRenderedColors(void) {
  TLButtonPointerWindow *window = [[TLButtonPointerWindow alloc] initWithContentRect:NSMakeRect(0, 0, 260, 50)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.testVisible = YES;
  TLButton *plus = [TLButton new];
  plus.translatesAutoresizingMaskIntoConstraints = YES;
  plus.style = TLButtonStyleCompactMinimal;
  plus.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];
  plus.frame = NSMakeRect(0, 0, 40, 40);
  TLSidebarNavigationButton *row = [TLSidebarNavigationButton new];
  row.translatesAutoresizingMaskIntoConstraints = YES;
  row.frame = NSMakeRect(50, 0, 200, 40);
  row.title = @"History";
  [window.contentView addSubview:plus];
  [window.contentView addSubview:row];
  window.testPointer = [plus convertPoint:NSMakePoint(20, 20) toView:nil];
  NSEvent *hoverEvent = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
  // Reuse both controls to exercise live theme switching while hovered.
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    plus.palette = palette;
    row.palette = palette;
    [plus updateTrackingAreas];
    [row mouseEntered:hoverEvent];
    [window.contentView layoutSubtreeIfNeeded];
    for (NSView *view in @[plus, row]) {
      CALayer *surface = view == plus ? [plus valueForKey:@"hoverBackgroundLayer"] : nil;
      [surface removeAllAnimations];
      NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
      [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
      CGFloat scale = bitmap.pixelsWide / NSWidth(view.bounds);
      CGFloat x = surface ? NSMinX(surface.frame) + 3 : NSWidth(view.bounds) - 10;
      NSColor *pixel = [[bitmap colorAtX:lrint(x * scale) y:bitmap.pixelsHigh / 2]
        colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      CGFloat ink = palette.dark ? 1 : 0, alpha = palette.dark ? 0.14 : 0.08;
      Check(fabs(pixel.redComponent - ink) < 0.02 && fabs(pixel.greenComponent - ink) < 0.02 &&
        fabs(pixel.blueComponent - ink) < 0.02 && fabs(pixel.alphaComponent - alpha) < 0.01,
        @"plus and sidebar hover render the shared translucent white/black surface");
      CGFloat foreground[3], foregroundAlpha;
      NSColor *textColor = view == plus ? palette.labelText : ((NSTextField *)[row valueForKey:@"titleLabel"]).textColor;
      RGBComponents(textColor, foreground, &foregroundAlpha);
      NSUInteger inkPixels = 0;
      for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
        if ([bitmap colorAtX:x y:y].alphaComponent > 0.9 && PixelMatches(bitmap, x, y, foreground)) inkPixels++;
      }
      Check(inkPixels > 2, @"plus glyph and sidebar text retain their rendered theme foreground");
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"build/hover-%@-%@.png", view == plus ? @"plus" : @"sidebar", theme] atomically:YES];
    }
  }
  [window close];
}

static void TestApprovalCard(void) {
  NSDictionary *request = @{@"request_id":@"approval", @"description":@"Search for volunteering roles and record the sources.",
    @"command":@"execute_code <<'PY'\nfrom hermes_tools import web_search\n\n# This comment must stay literal, not become a heading.\nfor region in ['Brisbane', 'Sunshine Coast', 'Gold Coast']:\n    print(web_search(region + ' volunteering'))\nPY",
    @"choices":@[@"once", @"session", @"always", @"deny"]};
  TLApprovalCardView *card = [[TLApprovalCardView alloc] initWithRequest:request palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 650) styleMask:NSWindowStyleMaskTitled
    backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window.contentView addSubview:card];
  NSLayoutConstraint *width = [card.widthAnchor constraintEqualToConstant:700];
  [NSLayoutConstraint activateConstraints:@[width,
    [card.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
    [card.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20]]];
  NSTextView *code = [card valueForKey:@"code"];
  Check([code.string isEqual:request[@"command"]] && !code.editable && !code.richText && code.selectable,
    @"approval code preserves newlines and literal Markdown characters in a selectable plain code view");
  NSStackView *actions = [card valueForKey:@"actions"];
  Check(actions.arrangedSubviews.count == 4, @"card shows the supplied approval choices");
  Check([TLApprovalChoices(@{@"choices":@[@"once", @"deny", @"unknown", @"once"]}) isEqual:@[@"once", @"deny"]],
    @"approval choices are filtered and deduplicated without adding wider permission scopes");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    card.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *size in @[@700, @200]) {
      width.constant = size.doubleValue;
      [window.contentView layoutSubtreeIfNeeded];
      [card setNeedsLayout:YES];
      [window.contentView layoutSubtreeIfNeeded];
      Check(fabs(NSWidth(card.frame) - size.doubleValue) < 1, @"approval fits narrow windows");
      for (NSView *button in actions.arrangedSubviews) {
        NSRect frame = [button convertRect:button.bounds toView:card];
        Check(NSMinX(frame) >= 0 && NSMaxX(frame) <= NSWidth(card.bounds) + 1, @"approval buttons stay inside the card");
      }
      NSBitmapImageRep *bitmap = [card bitmapImageRepForCachingDisplayInRect:card.bounds];
      [card cacheDisplayInRect:card.bounds toBitmapImageRep:bitmap];
      NSString *path = [NSString stringWithFormat:@"build/approval-card-%@-%@.png", theme, size];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
  }
  TLThemedButton *expand = [card valueForKey:@"expandButton"];
  CGFloat before = [[card valueForKey:@"codeHeight"] constant];
  [expand performClick:nil];
  Check([[card valueForKey:@"codeHeight"] constant] > before, @"code preview expands for review");
  [expand performClick:nil];
  Check([[card valueForKey:@"codeHeight"] constant] == before, @"code preview collapses without losing code");
  __block NSUInteger choices = 0;
  card.choiceHandler = ^BOOL(NSString *choice) { choices++; Check([choice isEqual:@"once"], @"button returns its exact choice"); return YES; };
  TLThemedButton *allow = (id)actions.arrangedSubviews.firstObject;
  [allow performClick:nil];
  [allow performClick:nil];
  Check(choices == 1, @"double clicking never submits an approval twice");
  for (NSButton *button in actions.arrangedSubviews) Check(!button.enabled, @"all choices disable after submission");
  [window close];
}

static void TestThemedButtonRenderedColors(void) {
  TLThemedButton *button = [TLThemedButton buttonWithTitle:@"Reset everything…" target:nil action:nil];
  button.frame = NSMakeRect(0, 0, 220, 44);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:button.bounds
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window.contentView addSubview:button];
  NSEvent *hoverEvent = [NSEvent enterExitEventWithType:NSEventTypeMouseEntered
    location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
    context:nil eventNumber:0 trackingNumber:0 userData:NULL];
  // Use the same control across theme changes, and render in an inactive window.
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    button.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    TLThemePalette *palette = button.palette;
    for (NSNumber *primary in @[@NO, @YES]) {
      button.primary = primary.boolValue;
      for (NSString *state in @[@"normal", @"hovered", @"pressed", @"disabled", @"focused", @"default"]) {
        button.enabled = ![state isEqualToString:@"disabled"];
        [button mouseExited:hoverEvent];
        if ([state isEqualToString:@"hovered"]) [button mouseEntered:hoverEvent];
        [button.cell setHighlighted:[state isEqualToString:@"pressed"]];
        button.keyEquivalent = [state isEqualToString:@"default"] ? @"\r" : @"";
        BOOL focused = [state isEqualToString:@"focused"];
        [window makeFirstResponder:focused ? button : nil];
        if (focused) Check(window.firstResponder == button, @"themed buttons retain native keyboard focus");
        NSBitmapImageRep *bitmap = RenderThemedButton(button);
        if (focused) {
          CGFloat focusColor[3], alpha;
          RGBComponents(palette.controlFocus, focusColor, &alpha);
          Check(PixelMatches(bitmap, 1, 22, focusColor), @"keyboard focus uses the theme focus token");
        }
        CGFloat surface[3], unusedAlpha;
        RGBComponents(palette.tabBackground, surface, &unusedAlpha);
        CGFloat opacity = button.enabled ? 1 : palette.disabledOpacity;
        CompositeColor(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface, opacity, surface);
        if ([state isEqualToString:@"hovered"] || [state isEqualToString:@"pressed"]) CompositeColor(palette.chromeHoverSurface, 1, surface);
        Check(PixelMatches(bitmap, 10, 22, surface), [NSString stringWithFormat:@"%@ button renders its theme surface", state]);
        CGFloat foreground[3] = {surface[0], surface[1], surface[2]};
        CompositeColor(button.primary ? palette.primaryActionText : palette.secondaryActionText, opacity, foreground);
        NSUInteger foregroundPixels = 0;
        for (NSInteger y = 8; y < 36; y++) {
          for (NSInteger x = 35; x < 185; x++) if (PixelMatches(bitmap, x, y, foreground)) foregroundPixels++;
        }
        Check(foregroundPixels > 10, [NSString stringWithFormat:@"%@ button renders the paired text color in theme %@", state, theme]);
        NSString *path = [NSString stringWithFormat:@"build/themed-button-%@-%@-%@.png", theme, primary, state];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
      }
    }
  }
  [window close];
}

@interface TLTerminalStateStore : NSObject
@property (nonatomic, copy) NSArray<TLAgentRecord *> *agents;
@property (nonatomic) NSInteger currentAgentID;
@end
@implementation TLTerminalStateStore
- (NSArray *)listAgents:(NSError **)error { return self.agents; }
@end

@interface TLTerminalStateVM : NSObject
@property (nonatomic) BOOL running;
@property (nonatomic) NSInteger connections;
@property (nonatomic, strong) TLAgentRecord *connectedAgent;
@end
@implementation TLTerminalStateVM
- (BOOL)isAgentRunning:(TLAgentRecord *)agent { return self.running; }
- (void)connectToAgent:(TLAgentRecord *)agent port:(uint32_t)port timeout:(NSTimeInterval)timeout completion:(TLAgentVMConnectionCompletionHandler)completion {
  Check(port == 7048, @"terminal connects to its interactive service");
  self.connections++;
  self.connectedAgent = agent;
  completion(nil, nil);
}
- (void)startAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion {
  Check(NO, @"opening a terminal must never start a VM");
}
@end

static void TestTerminalRequiresRunningVM(void) {
  TLTerminalStateStore *store = [TLTerminalStateStore new];
  TLTerminalStateVM *vm = [TLTerminalStateVM new];
  TLAgentOrchestrator *orchestrator = [[TLAgentOrchestrator alloc]
    initWithDatabase:(id)store agentClient:(id)[NSObject new] vmService:(id)vm];
  TalariaWindowController *controller = [[TalariaWindowController alloc] initWithWindow:nil];
  [controller setValue:orchestrator forKey:@"agentOrchestrator"];
  [controller setValue:[TLThemePalette paletteForPreference:TLThemePreferenceDark] forKey:@"palette"];
  NSView *content = [controller buildDebugTabContent];
  NSButton *button = [controller valueForKey:@"debugTerminalButton"];
  Check(content != nil && !button.enabled, @"terminal is disabled when there is no VM");
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = 42;
  store.currentAgentID = 42;
  TLAgentRecord *otherAgent = [TLAgentRecord new];
  otherAgent.agentID = 99;
  agent.status = TLAgentStatusRunning; // Persisted status alone must not enable it.
  for (NSNumber *state in @[@0, @1, @2, @1]) {
    store.agents = state.intValue ? @[agent, otherAgent] : @[];
    vm.running = state.intValue == 2;
    [controller refreshDebugTerminalAvailability];
    Check(button.enabled == vm.running, @"button follows actual VM state, including shutdown");
    NSInteger before = vm.connections;
    __block BOOL completed = NO;
    [orchestrator connectToDefaultAgentTerminal:^(VZVirtioSocketConnection *connection, NSError *error) {
      Check(vm.running ? error == nil : error != nil, @"stopped or missing VM rejects terminal connection");
      completed = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!completed && deadline.timeIntervalSinceNow > 0)
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(completed && vm.connections == before + (vm.running ? 1 : 0), @"only a running VM receives a connection");
    if (vm.running) Check(vm.connectedAgent.agentID == 42, @"terminal uses the existing default agent");
  }
}

static void TestDebugResetLayout(void) {
  TalariaWindowController *controller = [[TalariaWindowController alloc] initWithWindow:nil];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller setValue:palette forKey:@"palette"];
    NSScrollView *view = (NSScrollView *)[controller buildDebugTabContent];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
      styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    [window.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
      [view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
      [view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
      [view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
      [view.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
    ]];
    NSButton *resetButton = FindResetButton(view);
    Check(resetButton != nil && [resetButton.title isEqualToString:@"Reset everything…"], @"debug screen exposes the reset action");
    Check([resetButton isKindOfClass:TLThemedButton.class] &&
      [resetButton.bezelColor isEqual:palette.secondaryActionSurface], @"reset action uses the themed secondary button");
    for (NSNumber *width in @[@640, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 240)];
      [window.contentView layoutSubtreeIfNeeded];
      NSView *document = view.documentView;
      NSRect buttonRect = [resetButton convertRect:resetButton.bounds toView:document];
      Check(NSWidth(document.frame) <= width.doubleValue && NSWidth(document.frame) > 0, [NSString stringWithFormat:@"debug content fits a narrow window: window %@ scroll %@ document %@", NSStringFromRect(window.contentView.bounds), NSStringFromRect(view.frame), NSStringFromRect(document.frame)]);
      if (width.doubleValue == 640) Check(NSWidth(buttonRect) < 240, @"card actions fit their labels instead of filling the card");
      Check(NSContainsRect(document.bounds, buttonRect), @"reset button stays inside the scrollable document");
      [document scrollRectToVisible:buttonRect];
      Check(NSIntersectsRect(document.visibleRect, buttonRect), @"reset button is reachable by scrolling");
    }
    [window close];
  }
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
- (void)hideSlashCommandListForChat:(TLChatTabController *)chatContext {}
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext { return YES; }
@end

@interface TalariaWindowController (ApprovalTests)
- (BOOL)respondToApproval:(NSString *)requestID choice:(NSString *)choice chatID:(NSInteger)chatID;
@end
@interface TLApprovalSendRecorder : TLSendingNavigationController
@property NSDictionary *response;
@property NSUInteger submissions;
@end
@implementation TLApprovalSendRecorder
- (void)beginPreparedTurnWithChat:(TLChatRecord *)chat messages:(NSMutableArray<TLChatMessage *> *)messages
                          token:(NSString *)token model:(NSString *)model prompt:(NSString *)prompt
                    attachments:(NSArray *)attachments sourceURLs:(NSArray *)URLs approvalResponse:(NSDictionary *)response {
  self.response = response;
  self.submissions++;
  Check([prompt isEqual:@"Allow once"] && !attachments.count, @"approval response uses readable text and no composer attachments");
}
@end

static void TestApprovalRouting(void) {
  TLApprovalSendRecorder *controller = [[TLApprovalSendRecorder alloc] initWithWindow:nil];
  TLChatRecord *chat = [TLChatRecord new]; chat.chatID = 17;
  [controller setValue:chat forKey:@"activeChat"];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"token"; settings.selectedModel = @"model";
  [controller setValue:settings forKey:@"settings"];
  TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleAssistant content:@"Checking" thinking:nil];
  message.approvalRequest = @{@"request_id":@"exact", @"command":@"print('hello')", @"choices":@[@"once", @"deny"]};
  [controller setValue:[NSMutableArray arrayWithObject:message] forKey:@"messages"];
  Check(![controller respondToApproval:@"exact" choice:@"once" chatID:18], @"card cannot respond from a different chat");
  Check(![controller respondToApproval:@"stale" choice:@"once" chatID:17], @"card cannot submit a stale request");
  Check(![controller respondToApproval:@"exact" choice:@"always" chatID:17], @"card cannot expand the allowed scope");
  Check(controller.submissions == 0, @"invalid approval actions never start a request");
  Check([controller respondToApproval:@"exact" choice:@"once" chatID:17], @"valid approval starts continuation");
  Check([controller.response isEqual:@{@"request_id":@"exact", @"choice":@"once"}], @"controller sends exact structured response");
  Check(![controller respondToApproval:@"exact" choice:@"once" chatID:17] && controller.submissions == 1, @"submitted card cannot execute again");
}

@interface TLAttachmentPreparationRecorder : NSObject
@property (nonatomic, copy) void (^pendingCompletion)(NSArray *, NSError *);
@property (nonatomic, copy) NSArray<NSURL *> *receivedURLs;
@property (nonatomic, copy) NSString *receivedSessionID;
@property (nonatomic) NSInteger receivedAgentID;
@end
@implementation TLAttachmentPreparationRecorder
- (void)prepareAttachmentURLs:(NSArray<NSURL *> *)URLs sessionID:(NSString *)sessionID agentID:(NSInteger)agentID
                  completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *, NSError *))completion {
  self.receivedURLs = URLs;
  self.receivedSessionID = sessionID;
  self.receivedAgentID = agentID;
  self.pendingCompletion = completion;
}
@end

@interface TLAttachmentSendRecorder : TLSendingNavigationController
@property (nonatomic) NSUInteger startedTurns;
@property (nonatomic) NSUInteger routedCommands;
@property (nonatomic, copy) NSString *preparedPrompt;
@property (nonatomic, copy) NSArray *preparedAttachments;
@property (nonatomic, copy) NSString *reportedError;
@end
@implementation TLAttachmentSendRecorder
- (BOOL)performSelectedSlashCommand { self.routedCommands++; return YES; }
- (void)presentErrorMessage:(NSString *)message { self.reportedError = message; }
- (void)openFromNotchOverlay:(id)sender {}
- (void)beginPreparedTurnWithChat:(TLChatRecord *)chat messages:(NSMutableArray<TLChatMessage *> *)messages
                          token:(NSString *)token model:(NSString *)model prompt:(NSString *)prompt
                    attachments:(NSArray<NSDictionary<NSString *, id> *> *)attachments sourceURLs:(NSArray<NSURL *> *)URLs {
  self.startedTurns++;
  self.preparedPrompt = prompt;
  self.preparedAttachments = attachments;
}
@end

static void TestAttachmentSendPreparation(void) {
  TLAttachmentSendRecorder *controller = [[TLAttachmentSendRecorder alloc] initWithWindow:nil];
  TLMessageInput *input = [[TLMessageInput alloc] init];
  input.attachmentsEnabled = YES;
  [controller setValue:input forKey:@"messageInput"];
  [controller setValue:input.textView forKey:@"promptTextView"];
  [controller setValue:input.sendButton forKey:@"sendButton"];
  [controller setValue:input.palette forKey:@"palette"];
  TLChatRecord *chat = [[TLChatRecord alloc] init];
  chat.chatID = 8; chat.hermesSessionID = @"test-attachment-session"; chat.sourceAgentID = 9;
  chat.continuationSessionID = @"test-notification-continuation";
  [controller setValue:chat forKey:@"activeChat"];
  [controller setValue:[NSMutableArray array] forKey:@"messages"];
  TLAppSettings *settings = TLAppSettings.defaultSettings;
  settings.openRouterToken = @"test-token";
  [controller setValue:settings forKey:@"settings"];
  TLAttachmentPreparationRecorder *agent = [[TLAttachmentPreparationRecorder alloc] init];
  [controller setValue:agent forKey:@"agentOrchestrator"];
  NSArray *URLs = @[[NSURL fileURLWithPath:@"/tmp/report.pdf"]];
  TLQuickInputWindowController *quickInput = [[TLQuickInputWindowController alloc] initWithPalette:input.palette];
  [controller setValue:quickInput forKey:@"quickInputController"];
  [controller handleFileURLsDroppedOnNotch:URLs];
  Check(quickInput.messageInput.attachmentURLs.count == 1 && quickInput.messageInput.textView.string.length == 0 && input.attachmentURLs.count == 0,
        @"notch drops stage attachment chips in quick input and leave the current chat alone");
  // QuickInputTests covers the real submission handoff; exercise its send pipeline here.
  [input setAttachmentURLs:quickInput.messageInput.attachmentURLs animated:NO];
  [controller updateControlStates];
  Check(input.sendButton.enabled, @"attachment-only messages can be sent");
  [controller textView:input.textView doCommandBySelector:@selector(insertNewline:)];
  Check(controller.routedCommands == 0 && controller.startedTurns == 0 && agent.pendingCompletion != nil,
        @"Return waits for attachment copies and bypasses automatic command routing");
  Check(agent.receivedAgentID == 9 && [agent.receivedSessionID isEqual:chat.continuationSessionID],
        @"attachment preparation follows the chat's owning agent and active continuation session");
  Check([[controller valueForKey:@"preparingAttachments"] boolValue] && !input.attachmentsEditable,
        @"copying locks the submitted attachment selection");
  void (^failedCopy)(NSArray *, NSError *) = agent.pendingCompletion;
  agent.pendingCompletion = nil;
  failedCopy(nil, [NSError errorWithDomain:@"Test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Copy failed"}]);
  Check(controller.startedTurns == 0 && input.attachmentURLs.count == 1 && controller.reportedError.length > 0,
        @"failed copying preserves the draft without starting Hermes");
  Check(![[controller valueForKey:@"isSending"] boolValue] && input.attachmentsEditable, @"copy failure releases send state");
  input.textView.string = @"https://example.com";
  [controller sendMessage:nil];
  Check(controller.startedTurns == 0 && agent.receivedURLs.count == 1, @"URL with an attachment stays a Hermes request");
  void (^successfulCopy)(NSArray *, NSError *) = agent.pendingCompletion;
  agent.pendingCompletion = nil;
  successfulCopy(@[@{@"name":@"report.pdf", @"guestPath":@"/workspace/attachments/report.pdf", @"directory":@NO}], nil);
  Check(controller.startedTurns == 1 && controller.preparedAttachments.count == 1 &&
        [controller.preparedPrompt isEqual:@"https://example.com"], @"prepared files and original request reach the turn together");
}

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
    Check(!input.showsStopButton && input.sendButton.enabled == (draft.length > 1) && [input.sendButton.toolTip isEqual:@"Queue follow-up"],
      @"a nonblank streaming draft enables Queue and cannot accidentally stop the response");
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
@property NSArray<TLChatMessage *> *sentMessages;
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
  request.requestID = requestID; request.sessionID = sessionID; request.sentMessages = messages; request.delta = delta; request.completion = completion;
  [self.requests addObject:request];
}
- (void)cancelChatWithRequestID:(NSString *)requestID { [self.cancelledRequests addObject:requestID]; }
@end

@interface TLConcurrentTestStore : NSObject <TLAssistantTurnMessageStore>
@property NSMutableDictionary<NSNumber *, TLChatRecord *> *chats;
@property NSInteger nextMessageID;
@property BOOL failNextSave;
@end
@implementation TLConcurrentTestStore
- (instancetype)init {
  if ((self = [super init])) _chats = [NSMutableDictionary dictionary];
  return self;
}
- (TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error {
  if (self.failNextSave) {
    self.failNextSave = NO;
    if (error) *error = [NSError errorWithDomain:@"queue-test" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Save failed"}];
    return nil;
  }
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
  [controller setValue:[NSView new] forKey:@"contentHost"];
  [controller loadChatWithID:17];
  input = [controller valueForKey:@"messageInput"];
  input.textView.string = @"Question A";
  [controller sendMessage:nil allowAutomaticRouting:NO];
  TLConcurrentTestRequest *a = controller.stream.requests.lastObject;
  a.delta(a.requestID, TLAgentStreamDeltaKindContent, @"Answer A");
  NSMutableArray *messagesA = [controller valueForKey:@"messages"];
  [controller loadChatWithID:18];
  input = [controller valueForKey:@"messageInput"];
  input.textView.string = @"Question B";
  [controller updateControlStates];
  Check(input.sendButton.enabled && !input.showsStopButton, @"chat B can send while A streams");
  [controller sendMessage:nil allowAutomaticRouting:NO];
  TLConcurrentTestRequest *b = controller.stream.requests.lastObject;
  NSMutableArray *messagesB = [controller valueForKey:@"messages"];
  Check(controller.stream.requests.count == 2 && [a.sessionID isEqual:@"17"] && [b.sessionID isEqual:@"18"],
    @"two independent runners dispatch separate Hermes sessions");
  a.delta(a.requestID, TLAgentStreamDeltaKindContent, @" continues");
  a.delta(a.requestID, TLAgentStreamDeltaKindToolActivity, [NSJSONSerialization JSONObjectWithData:[@"{\"id\":\"a-tool\",\"name\":\"terminal\",\"state\":\"running\"}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
  b.delta(b.requestID, TLAgentStreamDeltaKindContent, @"Answer B");
  Check(((TLChatMessage *)messagesA.lastObject).toolActivities.count == 1 && !((TLChatMessage *)messagesB.lastObject).toolActivities.count,
    @"background tool updates stay in their originating chat");
  Check([((TLChatMessage *)messagesA.lastObject).content isEqual:@"Answer A continues"] &&
    [((TLChatMessage *)messagesB.lastObject).content isEqual:@"Answer B"], @"interleaved deltas stay in their own chats");
  input.textView.string = @"do not duplicate B";
  [controller sendMessage:nil allowAutomaticRouting:NO];
  Check(controller.stream.requests.count == 2, @"a follow-up waits for the busy chat to finish");
  [controller loadChatWithID:17];
  input = [controller valueForKey:@"messageInput"];
  Check([controller valueForKey:@"messages"] == messagesA && input.showsStopButton,
    @"returning to a streaming chat restores its live buffer and Stop button");
  [controller loadChatWithID:18];
  input = [controller valueForKey:@"messageInput"];
  Check(input.textView.string.length == 0 && [[controller valueForKeyPath:@"chatPresentation.queuedPrompts"] count] == 1,
    @"returning to a busy chat preserves its queued follow-up");
  [[controller valueForKeyPath:@"chatPresentation.queuedPrompts"] removeAllObjects];
  input.textView.string = @"";
  [controller updateControlStates];
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
  input = [controller valueForKey:@"messageInput"];
  Check([((TLChatMessage *)[[controller valueForKey:@"messages"] lastObject]).content isEqual:@"Answer A continues finished"],
    @"completed background output persists to its original conversation");
  [controller loadChatWithID:18];
  input = [controller valueForKey:@"messageInput"];
  Check([((TLChatMessage *)[[controller valueForKey:@"messages"] lastObject]).content isEqual:@"Second B answer"] &&
    ![[controller valueForKey:@"hasSendingTurns"] boolValue], @"all chats finish independently without stale callbacks");
}

@interface TalariaWindowController (QueueTests)
- (void)sendQueuedPromptNowAtIndex:(NSUInteger)index;
- (void)editQueuedPromptAtIndex:(NSUInteger)index;
- (void)removeQueuedPromptAtIndex:(NSUInteger)index;
- (void)finishQueuedPromptEditingSaving:(BOOL)save;
- (void)drainPromptQueue;
- (void)removeRuntimeForKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID;
@end

@interface TLQueueTestController : TLConcurrentChatController
@property NSString *reportedError;
@end
@implementation TLQueueTestController
- (void)presentErrorMessage:(NSString *)message { self.reportedError = message; }
@end

static void QueueDrain(void) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
}
static TLQueueTestController *QueueController(void) {
  TLQueueTestController *controller = [[TLQueueTestController alloc] initWithWindow:nil];
  controller.store = [TLConcurrentTestStore new];
  controller.stream = [TLConcurrentTestStream new];
  [controller setValue:controller.store forKey:@"database"];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"test-token"; settings.selectedModel = @"test-model";
  [controller setValue:settings forKey:@"settings"];
  [controller setValue:[TLThemePalette paletteForPreference:TLThemePreferenceDark] forKey:@"palette"];
  [controller setValue:[NSView new] forKey:@"contentHost"];
  for (NSNumber *chatID in @[@17, @18]) {
    TLChatRecord *chat = [TLChatRecord new]; chat.chatID = chatID.integerValue;
    chat.hermesSessionID = chatID.stringValue; chat.model = @"test-model"; chat.messages = @[];
    controller.store.chats[chatID] = chat;
  }
  [controller loadChatWithID:17];
  return controller;
}
static void QueueSend(TLQueueTestController *controller, NSString *text) {
  TLMessageInput *input = [controller valueForKey:@"messageInput"];
  input.textView.string = text;
  [controller sendMessage:nil allowAutomaticRouting:NO];
}
static void QueueComplete(TLConcurrentTestRequest *request) {
  request.delta(request.requestID, TLAgentStreamDeltaKindContent, @"Done");
  request.completion(nil);
  QueueDrain();
}
static void TestQueuedFollowUps(void) {
  TLQueueTestController *controller = QueueController();
  TLChatTabController *a = [controller valueForKey:@"chatPresentation"];
  QueueSend(controller, @"First");
  QueueSend(controller, @"Second");
  QueueSend(controller, @"Remove this");
  QueueSend(controller, @"Third");
  Check(a.queuedPrompts.count == 3 && controller.stream.requests.count == 1 && a.messages.count == 2,
    @"queued prompts remain outside transcript and gateway history until dispatched");
  [controller removeQueuedPromptAtIndex:1];
  a.messageInput.textView.string = @"Keep my draft";
  [controller editQueuedPromptAtIndex:0];
  a.messageInput.textView.string = @"Second revised";
  QueueComplete(controller.stream.requests.firstObject);
  Check(controller.stream.requests.count == 1 && a.queuedPrompts.count == 2, @"finishing a turn cannot dispatch a prompt being edited");
  [controller finishQueuedPromptEditingSaving:YES];
  Check(controller.stream.requests.count == 2 && [a.promptTextView.string isEqual:@"Keep my draft"] &&
    [a.queuedPromptInFlight.text isEqual:@"Second revised"], @"editing preserves FIFO position and restores an unrelated composer draft");
  Check([controller.stream.requests.lastObject.sentMessages.lastObject.content isEqual:@"Second revised"], @"the gateway receives the edited prompt");
  [controller loadChatWithID:18];
  TLChatTabController *b = [controller valueForKey:@"chatPresentation"];
  b.promptTextView.string = @"Other chat draft";
  QueueComplete(controller.stream.requests[1]);
  Check(controller.stream.requests.count == 3 && [controller.stream.requests.lastObject.sessionID isEqual:@"17"] &&
    [b.promptTextView.string isEqual:@"Other chat draft"] && [a.promptTextView.string isEqual:@"Keep my draft"],
    @"background queue dispatch keeps its session and never overwrites either chat draft");
  QueueComplete(controller.stream.requests.lastObject);
  Check(!a.queuedPrompts.count && !a.queuedPromptInFlight && !a.promptQueueView.preferredHeight,
    @"queue collapses after its final prompt starts");
  [controller loadChatWithID:17];
  QueueSend(controller, @"Running");
  QueueSend(controller, @"Stay queued");
  [controller updateControlStates];
  [controller activateComposerButton:a.sendButton];
  QueueDrain();
  Check(a.queuePaused && a.queuedPrompts.count == 1 && !a.queuedPromptInFlight, @"Stop pauses remaining follow-ups");
  NSUInteger requestCount = controller.stream.requests.count;
  [controller drainPromptQueue];
  Check(controller.stream.requests.count == requestCount, @"a paused queue never silently restarts");
  [controller editQueuedPromptAtIndex:0];
  a.promptTextView.string = @"Discard this edit";
  [controller finishQueuedPromptEditingSaving:NO];
  Check([a.queuedPrompts.firstObject.text isEqual:@"Stay queued"], @"cancel editing keeps original queued content");
  a.queuePaused = NO;
  [controller drainPromptQueue];
  TLConcurrentTestRequest *failed = controller.stream.requests.lastObject;
  failed.completion([NSError errorWithDomain:@"queue-test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Offline"}]);
  QueueDrain();
  Check(a.queuePaused && !a.queuedPromptInFlight && controller.reportedError.length, @"gateway failure pauses the queue and surfaces the error");

  // A failed user-message save must put the untouched prompt back at the front.
  [a.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Retry after save failure" attachmentURLs:@[]]];
  a.queuePaused = NO;
  controller.store.failNextSave = YES;
  a.promptTextView.string = @"Do not replace me";
  [controller drainPromptQueue];
  Check(a.queuePaused && a.queuedPrompts.count == 1 && !a.queuedPromptInFlight &&
    [a.promptTextView.string isEqual:@"Do not replace me"], @"synchronous persistence failure restores the queue without replacing the draft");
  a.queuePaused = NO;
  [controller drainPromptQueue];
  QueueComplete(controller.stream.requests.lastObject);

  TLAttachmentPreparationRecorder *attachments = [TLAttachmentPreparationRecorder new];
  [controller setValue:attachments forKey:@"agentOrchestrator"];
  QueueSend(controller, @"Before files");
  NSURL *file = [NSURL fileURLWithPath:@"/tmp/queued-example.txt"];
  a.messageInput.attachmentURLs = @[file];
  QueueSend(controller, @"Review this file");
  Check(a.queuedPrompts.firstObject.attachmentURLs.count == 1, @"queued prompts retain their attachment URLs");
  a.chat.sourceAgentID = 9;
  a.chat.continuationSessionID = @"queued-notification-continuation";
  QueueComplete(controller.stream.requests.lastObject);
  Check([attachments.receivedURLs isEqual:@[file]] && a.queuedPromptInFlight && [[controller valueForKey:@"preparingAttachments"] boolValue],
    @"attachments are prepared only when their queued prompt is ready");
  Check(attachments.receivedAgentID == 9 && [attachments.receivedSessionID isEqual:a.chat.continuationSessionID],
    @"queued attachments follow the notification conversation's owning agent and continuation");
  a.chat.sourceAgentID = 0;
  a.chat.continuationSessionID = @"";
  attachments.pendingCompletion(nil, [NSError errorWithDomain:@"queue-test" code:2 userInfo:nil]);
  Check(a.queuePaused && a.queuedPrompts.count == 1 && !a.queuedPromptInFlight, @"attachment preparation failure restores the queued prompt");
  a.queuePaused = NO;
  [controller drainPromptQueue];
  [controller removeRuntimeForKind:TLWorkspaceTabKindChat tabID:17];
  NSUInteger beforeClosedCopy = controller.stream.requests.count;
  attachments.pendingCompletion(@[], nil);
  Check(a.queuePaused && a.queuedPrompts.count == 1 && !a.queuedPromptInFlight && controller.stream.requests.count == beforeClosedCopy,
    @"closing a tab during attachment preparation pauses and restores its queued prompt");
  [controller loadChatWithID:18];
  [controller loadChatWithID:17];
  Check([controller valueForKey:@"chatPresentation"] == a && a.queuedPrompts.count == 1,
    @"reopening a closed chat retains its paused queue");
  a.queuePaused = NO;
  [controller drainPromptQueue];
  attachments.pendingCompletion(@[], nil);
  Check(a.queuedPromptInFlight != nil, @"retry starts exactly one prepared queued turn");
  TLConcurrentTestRequest *approval = controller.stream.requests.lastObject;
  approval.delta(approval.requestID, TLAgentStreamDeltaKindApproval,
    [NSJSONSerialization JSONObjectWithData:[@"{\"request_id\":\"queued-approval\",\"command\":\"echo hello\",\"choices\":[\"once\",\"deny\"]}" dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
  QueueSend(controller, @"Wait for approval");
  approval.completion(nil);
  QueueDrain();
  Check(a.queuePaused && a.queuedPrompts.count == 1, @"approval requests pause queued prompts");
  a.queuePaused = NO;
  requestCount = controller.stream.requests.count;
  [controller drainPromptQueue];
  Check(controller.stream.requests.count == requestCount, @"even Resume cannot bypass an unresolved approval");
}

static void TestSendQueuedPromptNow(void) {
  TLQueueTestController *controller = QueueController();
  TLChatTabController *chat = [controller valueForKey:@"chatPresentation"];
  QueueSend(controller, @"Original task");
  TLConcurrentTestRequest *original = controller.stream.requests.lastObject;
  original.delta(original.requestID, TLAgentStreamDeltaKindContent, @"Partial response");
  QueueSend(controller, @"First queued");
  QueueSend(controller, @"Selected queued");
  QueueSend(controller, @"Last queued");
  chat.promptTextView.string = @"Keep this draft";
  [controller sendQueuedPromptNowAtIndex:1];
  Check([controller.stream.cancelledRequests isEqual:@[original.requestID]] && controller.stream.requests.count == 1,
    @"Send now cancels the active response before submitting its replacement");
  [controller sendQueuedPromptNowAtIndex:2];
  Check(chat.queueInterruptPending && [chat.queuedPrompts.firstObject.text isEqual:@"Selected queued"],
    @"a second click cannot replace the pending Send now selection");
  QueueDrain();
  Check(controller.stream.requests.count == 2 && [controller.stream.requests.lastObject.sentMessages.lastObject.content isEqual:@"Selected queued"],
    @"Send now dispatches the selected prompt exactly once");
  Check([chat.queuedPrompts[0].text isEqual:@"First queued"] && [chat.queuedPrompts[1].text isEqual:@"Last queued"] &&
    [chat.promptTextView.string isEqual:@"Keep this draft"], @"Send now preserves the remaining queue order and composer draft");
  Check([chat.messages[1].content isEqual:@"Partial response"], @"interrupted output is retained in the transcript");
  original.delta(original.requestID, TLAgentStreamDeltaKindContent, @"stale output");
  original.completion(nil);
  Check(controller.stream.requests.count == 2 && [chat.messages[1].content isEqual:@"Partial response"],
    @"late events from the cancelled request cannot duplicate dispatch or overwrite its saved reply");
  QueueComplete(controller.stream.requests.lastObject);
  Check([chat.queuedPromptInFlight.text isEqual:@"First queued"], @"remaining prompts resume FIFO after the selected prompt finishes");
  [controller sendQueuedPromptNowAtIndex:0];
  QueueDrain();
  Check([chat.queuedPromptInFlight.text isEqual:@"Last queued"] && chat.queuedPrompts.count == 0,
    @"Send now can also interrupt an automatically dispatched queued turn");
  QueueComplete(controller.stream.requests.lastObject);

  [chat.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Paused first" attachmentURLs:@[]]];
  [chat.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Paused selected" attachmentURLs:@[]]];
  chat.queuePaused = YES;
  [controller sendQueuedPromptNowAtIndex:1];
  Check([chat.queuedPromptInFlight.text isEqual:@"Paused selected"] && !chat.queuePaused,
    @"Send now starts a selected prompt from a paused idle queue");
  QueueComplete(controller.stream.requests.lastObject);
  [controller editQueuedPromptAtIndex:0]; // No remaining item: safely ignored.
  QueueComplete(controller.stream.requests.lastObject);

  QueueSend(controller, @"Task with a save error");
  TLConcurrentTestRequest *saveFailure = controller.stream.requests.lastObject;
  saveFailure.delta(saveFailure.requestID, TLAgentStreamDeltaKindContent, @"Unsaved partial");
  QueueSend(controller, @"Keep queued on error");
  controller.store.failNextSave = YES;
  NSUInteger count = controller.stream.requests.count;
  [controller sendQueuedPromptNowAtIndex:0];
  QueueDrain();
  Check(chat.queuePaused && !chat.queueInterruptPending && chat.queuedPrompts.count == 1 && controller.stream.requests.count == count,
    @"a failure saving the interrupted response retains the selected prompt and pauses dispatch");

  TLChatMessage *approval = [TLChatMessage messageWithRole:TLRoleAssistant content:@"Approval needed" thinking:nil];
  approval.approvalRequest = @{@"request_id": @"pending", @"choices": @[@"once", @"deny"]};
  [chat.messages addObject:approval];
  [controller sendQueuedPromptNowAtIndex:0];
  Check(controller.stream.requests.count == count && chat.queuedPrompts.count == 1,
    @"Send now cannot bypass an unresolved approval");
  [chat.messages removeLastObject];
  [controller editQueuedPromptAtIndex:0];
  [controller sendQueuedPromptNowAtIndex:0];
  Check(controller.stream.requests.count == count && chat.editingQueuedPrompt != nil,
    @"Send now leaves an unfinished edit intact");
  [controller finishQueuedPromptEditingSaving:NO];
}

static void TestPromptQueueLayout(void) {
  TLPromptQueueView *queue = [TLPromptQueueView new];
  NSArray *prompts = @[
    [TLQueuedPrompt promptWithText:@"Add tests for the new flow" attachmentURLs:@[]],
    [TLQueuedPrompt promptWithText:@"Then check the layout in both themes" attachmentURLs:@[]],
    [TLQueuedPrompt promptWithText:@"Review the attached notes" attachmentURLs:@[[NSURL fileURLWithPath:@"/tmp/notes.txt"]]],
    [TLQueuedPrompt promptWithText:@"Summarize the changes" attachmentURLs:@[]]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 650, 260)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window.contentView addSubview:queue];
  [NSLayoutConstraint activateConstraints:@[
    [queue.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [queue.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [queue.topAnchor constraintEqualToAnchor:window.contentView.topAnchor]]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *width in @[@650, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 260)];
      [queue updatePrompts:prompts editing:nil paused:YES canResume:YES canSendNow:YES palette:palette];
      [window.contentView layoutSubtreeIfNeeded];
      Check(fabs(NSWidth(queue.frame) - width.doubleValue) < 1 && queue.preferredHeight < 220,
        @"queue fits narrow panes and bounds long queues with scrolling");
      NSScrollView *scroll = nil;
      for (NSView *view in [[queue valueForKey:@"body"] subviews]) if ([view isKindOfClass:NSScrollView.class]) scroll = (id)view;
      NSMutableArray<TLHoverIconButton *> *sendButtons = [NSMutableArray array];
      for (NSView *view in scroll.documentView.subviews) {
        if ([view isKindOfClass:TLHoverIconButton.class] && [(NSButton *)view action] == NSSelectorFromString(@"sendNow:"))
          [sendButtons addObject:(id)view];
      }
      Check(sendButtons.count == prompts.count, @"every queued prompt has an accessible Send now control");
      __block NSUInteger selected = NSNotFound;
      queue.sendNowHandler = ^(NSUInteger index) { selected = index; };
      [sendButtons[1] performClick:nil];
      Check(selected == 1, @"the Send now control targets its own queued prompt");
      TLHoverIconButton *send = sendButtons.firstObject;
      for (NSString *state in @[@"normal", @"hovered", @"pressed", @"disabled"]) {
        send.enabled = ![state isEqual:@"disabled"];
        [send setValue:@([state isEqual:@"hovered"]) forKey:@"hovered"];
        [send setValue:@([state isEqual:@"pressed"]) forKey:@"pressed"];
        NSBitmapImageRep *rendered = RenderThemedButton((id)send);
        CGFloat surface[3], foreground[3], alpha;
        RGBComponents(palette.tabBackground, surface, &alpha);
        RGBComponents(([state isEqual:@"hovered"] || [state isEqual:@"pressed"]) ? palette.appText : palette.textMuted, foreground, &alpha);
        NSUInteger glyphPixels = 0;
        for (NSInteger y = 0; y < rendered.pixelsHigh; y++) {
          for (NSInteger x = 0; x < rendered.pixelsWide; x++) {
            CGFloat actual[3], pixelAlpha;
            RGBComponents([rendered colorAtX:x y:y], actual, &pixelAlpha);
            CGFloat numerator = 0, denominator = 0;
            for (NSUInteger channel = 0; channel < 3; channel++) {
              numerator += (actual[channel] - surface[channel]) * (foreground[channel] - surface[channel]);
              denominator += pow(foreground[channel] - surface[channel], 2);
            }
            // Thin SF Symbols are antialiased: inspect coverage of the expected
            // foreground over the surface instead of requiring a solid pixel.
            CGFloat coverage = denominator > 0 ? numerator / denominator : 0;
            if (send.enabled ? coverage > 0.25 : !PixelMatches(rendered, x, y, surface)) glyphPixels++;
          }
        }
        Check(glyphPixels > 3, [NSString stringWithFormat:@"Send now renders a readable %@ symbol in theme %@", state, theme]);
      }
      send.enabled = YES;
      [send setValue:@NO forKey:@"hovered"];
      [send setValue:@NO forKey:@"pressed"];

      NSBitmapImageRep *bitmap = [queue bitmapImageRepForCachingDisplayInRect:queue.bounds];
      [queue cacheDisplayInRect:queue.bounds toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"build/prompt-queue-%@-%@.png", theme, width] atomically:YES];
    }
  }
  [queue updatePrompts:@[] editing:nil paused:NO canResume:YES canSendNow:YES palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  Check(queue.hidden && queue.preferredHeight == 0, @"an empty queue takes no transcript space");
  [window close];
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
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {}
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
  [controller setValue:[NSView new] forKey:@"contentHost"];
  for (NSString *title in titles) {
    [controller startNewChatWithModel:@"test-model" focus:NO];
    prompt = [controller valueForKey:@"promptTextView"];
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
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {}
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
@property (nonatomic) NSInteger currentAgentID;
- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error;
@end
@implementation TLFeatureSettingsStoreMock
- (NSInteger)recordBrowserVisitToURL:(NSURL *)URL title:(NSString *)title error:(NSError **)error { return 0; }
- (TLAppSettings *)appSettings:(NSError **)error { return self.savedSettings; }
- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error {
  self.savedSettings = [settings copy];
  return self.savedSettings;
}
@end

@interface TLLoadingWebView : WKWebView
@property (nonatomic) double reportedProgress;
@property (nonatomic) BOOL reportedLoading;
@end
@implementation TLLoadingWebView
- (double)estimatedProgress { return self.reportedProgress; }
- (BOOL)isLoading { return self.reportedLoading; }
@end

@interface TLWebKitBrowserController (LoadingTests)
- (void)updateSession:(TLWebKitBrowserSession *)session;
@end
@interface TLFeatureBrowserMock : TLWebKitBrowserController
@property NSURL *navigatedURL;
@property (nonatomic) NSUInteger startCount;
@property (nonatomic) NSUInteger closeCount;
@property (nonatomic) NSUInteger backCount;
@property (nonatomic) NSUInteger overlayCount;
@property (nonatomic, strong) TLWebKitBrowserSession *overlaySession;
@property (nonatomic) NSRect overlayRect;
@property (nonatomic) NSSize overlayViewport;
@property (nonatomic) BOOL overlayQuick;
@property (nonatomic, copy) void (^overlayCompletion)(NSDictionary *);
@property (nonatomic) BOOL deferColor, colorCapture;
@property (nonatomic) BOOL deferFooter;
@property (nonatomic, copy) NSDictionary *footerConfiguration;
@property (nonatomic, copy) void (^footerCompletion)(BOOL);
@property (nonatomic) NSUInteger colorCalls;
@property (nonatomic, copy) void (^colorCompletion)(NSDictionary *);
@property (nonatomic, copy) TLWebKitBrowserTitleHandler titleCallback;
@property (nonatomic, copy) TLWebKitBrowserURLHandler URLCallback;
@property (nonatomic, copy) TLWebKitBrowserFaviconHandler faviconCallback;
@property (nonatomic, copy) TLWebKitBrowserNavigationHandler navigationCallback;
@property (nonatomic, copy) TLWebKitBrowserLinkHandler linkCallback;
@end
@implementation TLFeatureBrowserMock
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(TLWebKitBrowserSession *)session completion:(void (^)(BOOL))completion {
  self.footerConfiguration=configuration;
  if(completion){if(self.deferFooter)self.footerCompletion=completion;else completion(YES);}
}
- (void)sampleFooterColorInSession:(TLWebKitBrowserSession *)session allowCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {
  self.colorCalls++; self.colorCapture = capture;
  if (self.deferColor) self.colorCompletion = completion; else completion(@{});
}
- (TLWebKitBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window
                       titleHandler:(TLWebKitBrowserTitleHandler)titleHandler
                        linkHandler:(TLWebKitBrowserLinkHandler)linkHandler
                         URLHandler:(TLWebKitBrowserURLHandler)URLHandler
                     faviconHandler:(TLWebKitBrowserFaviconHandler)faviconHandler
                  navigationHandler:(TLWebKitBrowserNavigationHandler)navigationHandler {
  self.startCount += 1;
  self.titleCallback = titleHandler;
  self.URLCallback = URLHandler;
  self.faviconCallback = faviconHandler;
  self.navigationCallback = navigationHandler;
  self.linkCallback = linkHandler;
  self.overlaySession = [[TLWebKitBrowserSession alloc] init];
  return self.overlaySession;
}
- (void)probeOverlayInSession:(TLWebKitBrowserSession *)session overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion {
  self.overlayQuick = quick;
  self.overlayCount++; self.overlayRect = rect; self.overlayViewport = viewport;
  self.overlayCompletion = completion;
}
- (void)closeSession:(TLWebKitBrowserSession *)session { if (session) self.closeCount += 1; }
- (void)goBackInSession:(TLWebKitBrowserSession *)session { self.backCount += 1; }
- (void)navigateSession:(TLWebKitBrowserSession *)session toURL:(NSURL *)URL { self.navigatedURL = URL; }
@end

@interface TLBrowserTabController (PageAppearanceTests)
- (void)samplePageAppearance;
@end

@interface TalariaWindowController (RestoredColorTests)
- (NSColor *)workspaceTabsController:(TLWorkspaceTabsController *)controller backgroundColorForTab:(TLWorkspaceTab *)tab;
@end
static void TestBrowserExtendedLayout(void) {
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLFeatureBrowserMock *service = [TLFeatureBrowserMock new];
    TLBrowserTabController *controller = [[TLBrowserTabController alloc]
      initWithURL:[NSURL URLWithString:@"https://example.com"]
      palette:[TLThemePalette paletteForPreference:preference.integerValue]
      database:(id)[TLFeatureSettingsStoreMock new] orchestrator:(id)[TLFeatureCatalogueMock new]
      inputWidth:480 browserService:service];
    NSColor *savedColor = [TLBrowserContentColor colorForRGB:@[@12,@34,@56]];
    TLWorkspaceTab *savedTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:77 title:@"Restored" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
    savedTab.browserHeaderRGB = @[@12,@34,@56];
    TalariaWindowController *shell = [[TalariaWindowController alloc] initWithWindow:nil];
    Check([[shell workspaceTabsController:nil backgroundColorForTab:savedTab] isEqual:savedColor], @"restored browser tab has color before a runtime exists");
    [controller restoreHeaderContentColor:savedColor];
    Check([controller.headerContentColor isEqual:savedColor], @"browser runtime starts with its restored page color");
    NSWindow *window = HostController(controller);
    [controller startInWindow:window];
    Check([controller.headerContentColor isEqual:savedColor], @"starting page loading does not erase restored color");
    NSTimer *timer = [controller valueForKey:@"pageAppearanceTimer"];
    NSLayoutConstraint *bottom = [controller valueForKey:@"browserHostBottomConstraint"];
    TLBrowserAddressInput *input = [controller valueForKey:@"browserAddressInput"];
    Check(![input respondsToSelector:NSSelectorFromString(@"heightToggleButton")], @"Footer toggle is removed");
    NSView *blur = [controller valueForKey:@"bottomBlur"];
    NSView *page = [controller valueForKey:@"browserHostView"];
    Check([blur hitTest:NSMakePoint(10,10)] == nil, @"native blur leaves page and input interactions intact");
    Check([controller.view.subviews indexOfObject:page] < [controller.view.subviews indexOfObject:blur] &&
      [controller.view.subviews indexOfObject:blur] < [controller.view.subviews indexOfObject:input], @"blur is over the page and under the input");
    TLLoadingWebView *webView = [[TLLoadingWebView alloc] initWithFrame:NSZeroRect];
    [service.overlaySession setValue:webView forKey:@"webView"];
    [service.overlaySession setValue:service.navigationCallback forKey:@"navigationHandler"];
    __block NSUInteger loadingUpdates = 0;
    controller.loadingChangedHandler = ^{ loadingUpdates++; };
    webView.reportedProgress = 0.2;
    webView.reportedLoading = YES;
    [service updateSession:service.overlaySession];
    Check(controller.isLoading && controller.loadingProgress == 0.2, @"navigation exposes WebKit's real estimated progress");
    webView.reportedProgress = 0.65;
    webView.reportedLoading = YES;
    [service updateSession:service.overlaySession];
    Check(controller.loadingProgress == 0.65 && loadingUpdates == 2, @"progress changes propagate even while loading stays true");
    webView.reportedLoading = NO;
    [service updateSession:service.overlaySession];
    Check(!controller.isLoading && controller.loadingProgress == 0, @"completed or stopped loads clear progress");
    webView.reportedProgress = 0.1;
    webView.reportedLoading = YES;
    [service updateSession:service.overlaySession];
    Check(controller.loadingProgress == 0.1, @"reload resets progress rather than preserving the previous load");
    CAShapeLayer *ink = [input valueForKey:@"loadingLine"];
    Check(!ink.hidden && fabs(ink.strokeEnd - 0.1) < 0.0001, @"browser progress is drawn in its own input");
    webView.reportedProgress = 0.7;
    [service updateSession:service.overlaySession];
    Check(fabs(ink.strokeEnd - 0.7) < 0.0001, @"WebKit progress updates the input line");

    for (NSNumber *inspecting in @[@NO, @YES, @NO]) {
      [service.overlaySession setValue:inspecting forKey:@"devToolsVisible"];
      [service.overlaySession setValue:@(service.overlaySession.documentGeneration + 1) forKey:@"documentGeneration"];
      [controller samplePageAppearance];
      Check(bottom.constant == 0, @"navigation and DevTools keep the full-height extended layout");
      Check([service.footerConfiguration[@"enabled"] boolValue], @"document extension remains enabled");
      Check(service.footerConfiguration[@"blurRadius"] == nil, @"page scroll code no longer owns the native blur overlay");
      Check(service.overlayCount == 0, @"page obstructions never trigger Footer placement probes");
    }
    [controller applyPalette:[TLThemePalette paletteForPreference:preference.integerValue]];
    Check(bottom.constant == 0, @"theme changes preserve extended layout");
    [controller close];
    Check(!timer.valid && service.closeCount == 1, @"closing stops appearance monitoring and closes the session");
    Check(!controller.isLoading && controller.loadingChangedHandler == nil, @"closing clears loading and its callback");
    [window close];
  }
}

@interface TLSettingsCredentialMock : TLFeatureCatalogueMock
@property (nonatomic, copy) void (^pendingCredentials)(NSDictionary *, NSError *);
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;
@end
@implementation TLSettingsCredentialMock
- (void)hermesCredentialsWithAction:(NSString *)action key:(NSString *)key value:(NSString *)value
                              token:(NSString *)token completion:(void (^)(NSDictionary *, NSError *))completion {
  self.action = action; self.key = key; self.value = value; self.pendingCredentials = completion;
}
@end

static void SettingsTick(NSWindow *window) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  [window.contentView layoutSubtreeIfNeeded];
}
static void SettingsSnapshot(TLSettingsTabController *controller, NSWindow *window, NSString *name) {
  SettingsTick(window);
  NSView *view = controller.view;
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:[@"build/" stringByAppendingString:name] atomically:YES];
}
@interface TLBrowserPreferencesMock : NSObject <TLBrowserPreferencesService>
@property NSMutableDictionary *values;
@property BOOL failSave;
@property NSUInteger writes;
@property NSDictionary *importedProfile;
@property NSDictionary *importedBrowser;
@property (copy) void (^importCompletion)(NSString *);
@end
@implementation TLBrowserPreferencesMock
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (void)prepareInWindow:(NSWindow *)window completion:(void (^)(NSError *))completion { completion(nil); }
- (NSDictionary *)stateForSetting:(NSDictionary *)setting { return @{@"available":@YES,@"value":self.values[setting[@"id"]] ?: setting[@"default"]}; }
- (BOOL)saveValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error {
  if (self.failSave) { if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Save failed"}]; return NO; }
  self.values[setting[@"id"]] = value; self.writes++; return YES;
}
- (void)clearData:(NSString *)kind completion:(void (^)(NSError *))completion { completion(nil); }
- (BOOL)resetDefaults:(NSError **)error { [self.values removeAllObjects]; return YES; }
- (void)importProfile:(NSDictionary *)profile fromBrowser:(NSDictionary *)browser completion:(void (^)(NSString *))completion { self.importedProfile = profile; self.importedBrowser = browser; self.importCompletion = completion; }
@end
@interface TLDefaultBrowserWorkspace : NSWorkspace
@property NSMutableSet<NSString *> *schemes;
@property NSMutableArray<NSString *> *requests;
@property BOOL fail;
@property (copy) void (^pending)(NSError *);
@end
@implementation TLDefaultBrowserWorkspace
- (instancetype)init { if ((self = [super init])) { _schemes = [NSMutableSet set]; _requests = [NSMutableArray array]; } return self; }
- (void)setDefaultApplicationAtURL:(NSURL *)URL toOpenURLsWithScheme:(NSString *)scheme completionHandler:(void (^)(NSError *))completion {
  [self.requests addObject:scheme];
  __weak typeof(self) weakSelf = self;
  self.pending = ^(NSError *error) { if (!error) [weakSelf.schemes addObject:scheme]; completion(error); };
}
@end
@interface TLDefaultBrowserSettingsFixture : TLBrowserSettingsController
@property TLDefaultBrowserWorkspace *workspace;
@end
@implementation TLDefaultBrowserSettingsFixture
- (NSWorkspace *)browserWorkspace { return self.workspace; }
- (BOOL)isDefaultForScheme:(NSString *)scheme { return [self.workspace.schemes containsObject:scheme]; }
@end
static void TestDefaultBrowserSettings(void) {
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLDefaultBrowserSettingsFixture *controller = [[TLDefaultBrowserSettingsFixture alloc] initWithPalette:[TLThemePalette paletteForPreference:theme.integerValue] preferences:[TLBrowserPreferencesMock new]];
    controller.workspace = [TLDefaultBrowserWorkspace new];
    NSWindow *window = HostController(controller);
    TLThemedButton *button = [controller valueForKey:@"defaultBrowserButton"];
    NSTextField *status = [controller valueForKey:@"defaultBrowserStatus"];
    Check(button.enabled && !button.isHiddenOrHasHiddenAncestor, @"default browser action is visible and independent of browser engine startup");
    Check([button.title isEqual:@"Make Talaria my default browser"], @"default browser action has the requested label");
    [button sizeToFit];
    NSBitmapImageRep *render = RenderThemedButton(button);
    CGFloat surface[3], alpha;
    RGBComponents(button.palette.tabBackground, surface, &alpha);
    CompositeColor(button.palette.secondaryActionSurface, 1, surface);
    Check(PixelMatches(render, 10, NSHeight(button.bounds)/2, surface), @"default browser action renders its themed surface");
    [NSApp sendAction:button.action to:button.target from:button];
    Check(!button.enabled && [controller.workspace.requests isEqual:@[@"http"]], @"default request starts once and waits for macOS confirmation");
    controller.workspace.pending(nil); SettingsTick(window);
    Check([controller.workspace.requests isEqual:@[@"http", @"https"]], @"both web schemes are requested sequentially");
    controller.workspace.pending(nil); SettingsTick(window);
    Check(!button.enabled && [status.stringValue isEqual:@"Talaria is your default browser."], @"success reflects actual handler state");
    [controller.workspace.schemes removeObject:@"https"];
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    Check(button.enabled, @"returning from system settings rechecks both URL schemes");
    [NSApp sendAction:button.action to:button.target from:button];
    Check(controller.workspace.requests.count == 3 && [controller.workspace.requests.lastObject isEqual:@"https"], @"already assigned scheme is not requested again");
    controller.workspace.pending([NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:@{NSLocalizedDescriptionKey:@"Cancelled"}]); SettingsTick(window);
    Check(button.enabled && [status.stringValue isEqual:@"Cancelled"], @"cancellation leaves a retryable action without claiming success");
    [controller close]; [window close];
  }
}

@interface TLImportSettingsFixture : TLBrowserSettingsController
@end
@implementation TLImportSettingsFixture
- (NSArray *)detectedImportBrowsers {
  return @[
    @{ @"name":@"Google Chrome", @"bundleID":@"test.chrome", @"engine":@"chromium", @"profiles":@[
      @{ @"name":@"Personal", @"URL":[NSURL fileURLWithPath:@"/tmp/import-ui-fixture/Default"] },
      @{ @"name":@"Work", @"URL":[NSURL fileURLWithPath:@"/tmp/import-ui-fixture/Profile 1"] }] },
    @{ @"name":@"Safari", @"bundleID":@"test.safari", @"engine":@"unsupported", @"profiles":@[] },
    @{ @"name":@"Chrome Beta", @"bundleID":@"test.chrome-denied", @"engine":@"chromium", @"profiles":@[],
       @"profileRootURL":[NSURL fileURLWithPath:@"/tmp/import-ui-fixture"],
       @"discoveryError":[NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:nil] },
    @{ @"name":@"Firefox", @"bundleID":@"test.firefox", @"engine":@"firefox", @"profiles":@[] }];
}
@end
@interface TLImportSettingsShellFixture : TLSettingsTabController
@end
@implementation TLImportSettingsShellFixture
- (NSView *)buildBrowserPage {
  TLImportSettingsFixture *page = [[TLImportSettingsFixture alloc] initWithPalette:self.palette preferences:self.browserPreferences];
  [self setValue:page forKey:@"browserSettingsController"];
  [self addChildViewController:page]; [page prepareInWindow:self.view.window]; return page.view;
}
@end
static void TestBrowserImportSettings(void) {
  TLBrowserPreferencesMock *preferences = [TLBrowserPreferencesMock new];
  TLFeatureSettingsStoreMock *store = [TLFeatureSettingsStoreMock new]; store.currentAgentID = 7;
  TLSettingsCredentialMock *service = [TLSettingsCredentialMock new];
  TLImportSettingsShellFixture *shell = [[TLImportSettingsShellFixture alloc] initWithSettings:TLAppSettings.defaultSettings database:(id)store orchestrator:(id)service palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  shell.browserPreferences = preferences;
  NSWindow *window = HostController(shell);
  NSSegmentedControl *sections = [[shell valueForKey:@"workspace"] sectionTabs];
  sections.selectedSegment = 1; [NSApp sendAction:sections.action to:sections.target from:sections]; SettingsTick(window);
  TLBrowserSettingsController *controller = [shell valueForKey:@"browserSettingsController"];
  controller.selectedCategoryIndex = [TLBrowserPreferences.categories indexOfObject:@"Import profiles"];
  [controller prepareInWindow:window]; SettingsTick(window);
  NSDictionary *pickers = [controller valueForKey:@"profilePickers"];
  Check(pickers.count == 1, @"Only browsers with supported profiles offer an import selector");
  NSPopUpButton *picker = pickers[@"test.chrome"]; [picker selectItemAtIndex:1];
  TLThemedButton *import = nil;
  for (TLThemedButton *button in [controller valueForKey:@"buttons"]) if ([button.identifier isEqual:@"test.chrome"]) import = button;
  Check(import && import.enabled, @"A supported browser gets a themed Import profile button");
  TLThemedButton *grant = nil;
  for (TLThemedButton *button in [controller valueForKey:@"buttons"]) if ([button.identifier isEqual:@"test.chrome-denied"]) grant = button;
  Check(grant && grant.enabled && [grant.title isEqual:@"Import"] && grant.action == NSSelectorFromString(@"importProfile:"), @"Access-denied browsers use Import without a separate permission action");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    window.appearance = [NSAppearance appearanceNamed:theme.integerValue == TLThemePreferenceDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [shell applyPalette:[TLThemePalette paletteForPreference:theme.integerValue]];
    for (NSNumber *width in @[@700,@200]) {
      [window setContentSize:NSMakeSize(width.doubleValue,900)]; SettingsTick(window);
      Check(fabs(NSWidth(window.contentView.bounds) - width.doubleValue) < 1 && NSWidth(controller.view.bounds) <= width.doubleValue, [NSString stringWithFormat:@"Import page respects width %@ (page %.0f, window %.0f)",width,NSWidth(controller.view.bounds),NSWidth(window.contentView.bounds)]);
      Check(NSWidth(import.frame) + 1 >= import.intrinsicContentSize.width && NSWidth(import.frame) <= width.doubleValue, @"Import label fits without truncation in narrow settings windows");
      Check(NSWidth(grant.frame) + 1 >= grant.intrinsicContentSize.width && NSWidth(grant.frame) <= width.doubleValue, @"Import for a protected browser fits narrow windows in both themes");
      NSBitmapImageRep *bitmap = [controller.view bitmapImageRepForCachingDisplayInRect:controller.view.bounds];
      [controller.view cacheDisplayInRect:controller.view.bounds toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/browser-import-%@-%@.png",theme,width] atomically:YES];
    }
  }
  [import performClick:nil];
  Check([preferences.importedProfile[@"name"] isEqual:@"Work"] && [preferences.importedBrowser[@"name"] isEqual:@"Google Chrome"], @"Import uses the explicitly selected browser profile");
  Check(!import.enabled && !picker.enabled, @"Import disables repeated actions and profile changes while busy");
  Check(!grant.enabled, @"Folder grants are disabled while importing");
  preferences.importCompletion(@"Imported cookies. Restart Talaria to apply local storage.");
  Check(import.enabled && [[[controller valueForKey:@"status"] stringValue] containsString:@"Restart Talaria"], @"Import completion restores controls and explains restart");
  [shell close]; [window close];
}
static void TestBrowserPreferencePersistenceAndValidation(void) {
  NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
  TLBrowserPreferences *preferences = [[TLBrowserPreferences alloc] initWithProfileURL:directory];
  NSError *error = nil;
  Check(![preferences saveValue:@"file:///tmp/{searchTerms}" forSetting:[TLBrowserPreferences settingWithID:@"customSearchURL"] error:&error], @"search templates reject non-web URLs");
  Check(![preferences saveValue:@"https://user:password@example.com/{searchTerms}" forSetting:[TLBrowserPreferences settingWithID:@"customSearchURL"] error:&error], @"search templates reject credentials");
  Check(![preferences saveValue:@999 forSetting:[TLBrowserPreferences settingWithID:@"zoom"] error:&error], @"zoom rejects out-of-range values");
  Check(![preferences saveValue:@"https://example.com\nfile:///tmp/test" forSetting:[TLBrowserPreferences settingWithID:@"startupPages"] error:&error], @"startup URLs are validated as a whole");
  Check([preferences saveValue:@"https://duckduckgo.com/?q={searchTerms}" forSetting:[TLBrowserPreferences settingWithID:@"searchEngine"] error:&error], @"search engine saves");
  Check([[preferences searchURLForText:@"a & b#東京"].absoluteString isEqual:@"https://duckduckgo.com/?q=a%20%26%20b%23%E6%9D%B1%E4%BA%AC"], @"search queries cannot inject extra URL parameters");
  Check([preferences saveValue:@"https://example.com/one\nhttps://example.org/two" forSetting:[TLBrowserPreferences settingWithID:@"startupPages"] error:&error], @"startup page list saves");
  Check([preferences saveValue:@"pages" forSetting:[TLBrowserPreferences settingWithID:@"startup"] error:&error], @"startup mode saves");
  Check([preferences saveValue:@125 forSetting:[TLBrowserPreferences settingWithID:@"zoom"] error:&error], @"zoom saves");
  TLBrowserPreferences *reopened = [[TLBrowserPreferences alloc] initWithProfileURL:directory];
  Check([[reopened localValue:@"zoom"] intValue] == 125 && reopened.startupURLs.count == 2, @"browser preferences survive reopening the profile");
  Check([preferences saveValue:@"empty" forSetting:[TLBrowserPreferences settingWithID:@"startup"] error:&error] && preferences.startupURLs.count == 0, @"startup pages only open in specific-pages mode");
  Check(![preferences validateValue:@"value" forSetting:@{@"id":@"unknownSetting"} error:&error], @"unknown browser settings are rejected");
  [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}

@interface TLLoginItemMock : NSObject <TLLoginItemService>
@property SMAppServiceStatus status;
@property BOOL fail;
@property NSUInteger registrations;
@end
@implementation TLLoginItemMock
- (BOOL)registerAndReturnError:(NSError **)error {
  self.registrations++;
  if (self.fail) { if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Login item failed"}]; return NO; }
  self.status = SMAppServiceStatusRequiresApproval; return YES;
}
- (BOOL)unregisterAndReturnError:(NSError **)error {
  if (self.fail) { if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Login item failed"}]; return NO; }
  self.status = SMAppServiceStatusNotRegistered; return YES;
}
@end
@interface TLShortcutRegistrationMock : NSObject <TLGlobalShortcutRegistration>
@property (nonatomic, copy) void (^handler)(void);
@property NSDictionary *registered;
@property BOOL fail;
@end
@implementation TLShortcutRegistrationMock
- (BOOL)registerShortcut:(NSDictionary *)shortcut error:(NSError **)error {
  if (self.fail) { if (error) *error = [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Shortcut in use"}]; return NO; }
  self.registered = shortcut; return YES;
}
@end

static void TestNativeGlobalShortcutRegistration(void) {
  TLGlobalShortcut *first = [[TLGlobalShortcut alloc] init], *second = [[TLGlobalShortcut alloc] init];
  NSDictionary *shortcut = @{@"keyCode":@80,@"modifiers":@(NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift),@"label":@"F19"};
  NSError *error = nil;
  Check([first registerShortcut:shortcut error:&error], @"macOS accepts an available global shortcut");
  Check(![second registerShortcut:shortcut error:&error] && error != nil, @"macOS reports a conflicting shortcut");
  __block NSUInteger invocations = 0;
  first.handler = ^{ invocations++; };
  EventRef event = NULL;
  EventHotKeyID identifier = { 'Tlqi', [[first valueForKey:@"identifier"] unsignedIntValue] };
  Check(CreateEvent(NULL, kEventClassKeyboard, kEventHotKeyPressed, 0, 0, &event) == noErr, @"create native hotkey event");
  SetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, sizeof(identifier), &identifier);
  SendEventToEventTarget(event, GetApplicationEventTarget()); ReleaseEvent(event);
  Check(invocations == 1, @"native hotkey event reaches the quick input callback once");
  [first registerShortcut:nil error:nil];
  Check([second registerShortcut:shortcut error:&error], @"clearing a global shortcut releases it to macOS");
  [second registerShortcut:nil error:nil];
}

@interface TLPluginsServiceMock : NSObject
@property (nonatomic, copy) void (^pending)(NSDictionary *, NSError *);
@property NSDictionary *parameters;
@property NSInteger agentID;
@end
@implementation TLPluginsServiceMock
- (void)hermesPluginsWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID token:(NSString *)token
  model:(NSString *)model completion:(void (^)(NSDictionary *, NSError *))completion {
  self.parameters = parameters; self.agentID = agentID; self.pending = completion;
}
@end
static NSArray<NSSwitch *> *PluginSwitches(NSView *view) {
  NSMutableArray *result = [NSMutableArray array];
  if ([view isKindOfClass:NSSwitch.class]) [result addObject:view];
  for (NSView *child in view.subviews) [result addObjectsFromArray:PluginSwitches(child)];
  return result;
}
static void WaitForPlugins(TLSettingsTabController *controller, NSWindow *window) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
  while ([[controller valueForKey:@"pluginsBusy"] boolValue] && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
  [window.contentView layoutSubtreeIfNeeded];
}
static void TestPluginsInSettingsWorkspace(void) {
  TLFeatureSettingsStoreMock *database = [TLFeatureSettingsStoreMock new]; database.currentAgentID = 7;
  TLPluginsServiceMock *service = [TLPluginsServiceMock new];
  TLSettingsTabController *controller = [[TLSettingsTabController alloc] initWithSettings:TLAppSettings.defaultSettings
    database:(id)database orchestrator:(id)service palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = HostController(controller);
  NSArray<TLSidebarNavigationButton *> *nav = [controller valueForKey:@"navigation"];
  Check(!service.pending, @"opening Model does not load plugins");
  [nav[3] accessibilityPerformPress];
  Check(service.agentID == 7 && [service.parameters[@"action"] isEqual:@"list"], @"Plugins loads its displayed agent through the orchestrator");
  NSMutableDictionary *notification = [@{@"id":@"talaria-notifications", @"name":@"Talaria Notifications", @"description":@"Useful findings from your automations.",
    @"version":@"1.0.0", @"source":@"user", @"enabled":@YES, @"active":@YES, @"error":@"", @"restart_required":@NO} mutableCopy];
  NSDictionary *second = @{@"id":@"example", @"name":@"Example Plugin", @"description":@"An installed plugin that is currently disabled.",
    @"version":@"2.0", @"source":@"bundled", @"enabled":@NO, @"active":@NO, @"error":@"", @"restart_required":@NO};
  NSDictionary *(^catalogue)(BOOL) = ^NSDictionary *(BOOL managed) { return @{@"plugins":@[[notification copy],second], @"managed":@(managed), @"restart_required":notification[@"restart_required"]}; };
  service.pending(catalogue(NO),nil); WaitForPlugins(controller,window);
  NSStackView *rows = [controller valueForKey:@"pluginRows"];
  Check(PluginSwitches(rows).count == 2 && PluginSwitches(rows)[0].state == NSControlStateValueOn &&
    PluginSwitches(rows)[1].state == NSControlStateValueOff, @"installed plugins show authoritative enabled states");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue]; [controller applyPalette:palette];
    for (NSNumber *width in @[@1100,@200]) {
      [window setContentSize:NSMakeSize(width.doubleValue,780)]; SettingsTick(window);
      for (NSSwitch *toggle in PluginSwitches(rows)) {
        NSView *row = toggle.superview.superview;
        NSRect rect = [toggle convertRect:toggle.bounds toView:row];
        Check(NSWidth(rect) > 0 && NSContainsRect(row.bounds,rect), @"plugin switches fit narrow and wide rows in both themes");
      }
      SettingsSnapshot(controller,window,[NSString stringWithFormat:@"plugins-%@-%@.png",palette.dark ? @"dark" : @"light",width]);
    }
  }
  [window setContentSize:NSMakeSize(1100,780)]; SettingsTick(window);
  NSSwitch *toggle = PluginSwitches(rows)[0]; toggle.state = NSControlStateValueOff;
  [NSApp sendAction:toggle.action to:toggle.target from:toggle];
  Check([service.parameters[@"id"] isEqual:@"talaria-notifications"] && [service.parameters[@"enabled"] isEqual:@NO] && service.agentID == 7,
    @"toggle saves the exact plugin for its owning agent");
  Check(!PluginSwitches(rows)[0].enabled, @"pending writes prevent duplicate toggle requests");
  service.pending(nil,[NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Write failed"}]); WaitForPlugins(controller,window);
  Check(PluginSwitches(rows)[0].state == NSControlStateValueOn && [[[controller valueForKey:@"pluginStatus"] stringValue] isEqual:@"Write failed"],
    @"a failed write restores the saved state and shows the error");
  toggle = PluginSwitches(rows)[0]; toggle.state = NSControlStateValueOff; [NSApp sendAction:toggle.action to:toggle.target from:toggle];
  notification[@"enabled"] = @NO; notification[@"restart_required"] = @YES;
  service.pending(catalogue(NO),nil); WaitForPlugins(controller,window);
  Check(PluginSwitches(rows)[0].state == NSControlStateValueOff && [[[controller valueForKey:@"pluginStatus"] stringValue] containsString:@"Restart"],
    @"successful toggle shows saved state and restart requirement");
  NSSearchField *search = [controller valueForKey:@"pluginSearch"]; search.stringValue = @"no matches";
  [(id<NSTextFieldDelegate>)controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  Check(PluginSwitches(rows).count == 0, @"plugin search filters the installed catalogue");
  search.stringValue = @""; [(id<NSTextFieldDelegate>)controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  [[controller valueForKey:@"refreshPluginsButton"] performClick:nil];
  void (^late)(NSDictionary *, NSError *) = service.pending;
  database.currentAgentID = 8; [controller refreshPluginsForSelectedAgent];
  Check(PluginSwitches(rows).count == 0 && service.agentID == 8, @"agent switch immediately clears the prior plugin list");
  late(catalogue(NO),nil); SettingsTick(window);
  Check(PluginSwitches(rows).count == 0, @"late responses cannot show another agent's plugins");
  service.pending(catalogue(YES),nil); WaitForPlugins(controller,window);
  Check(!PluginSwitches(rows)[0].enabled, @"managed plugin settings are visible and read-only");
  [[controller valueForKey:@"refreshPluginsButton"] performClick:nil]; late = service.pending;
  [controller close]; late(@{@"plugins":@[],@"managed":@NO},nil); SettingsTick(window);
  Check(PluginSwitches(rows).count == 2, @"closing invalidates pending plugin requests");
  [window close];
}

static void TestSettingsNavigationCredentialsAndResponsiveLayout(void) {
  TLSettingsCredentialMock *service = [[TLSettingsCredentialMock alloc] init];
  TLFeatureSettingsStoreMock *store = [[TLFeatureSettingsStoreMock alloc] init];
  store.currentAgentID = 7;
  TLSettingsTabController *controller = [[TLSettingsTabController alloc]
    initWithSettings:TLAppSettings.defaultSettings database:(TLDatabase *)store orchestrator:(TLAgentOrchestrator *)service
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  TLBrowserPreferencesMock *browserPreferences = [[TLBrowserPreferencesMock alloc] init];
  controller.browserPreferences = browserPreferences;
  NSString *suite = [@"Talaria.SettingsTests." stringByAppendingString:NSUUID.UUID.UUIDString];
  NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
  TLLoginItemMock *login = [[TLLoginItemMock alloc] init];
  login.status = SMAppServiceStatusNotFound;
  TLShortcutRegistrationMock *registration = [[TLShortcutRegistrationMock alloc] init];
  TLApplicationPreferences *appPreferences = [[TLApplicationPreferences alloc] initWithDefaults:defaults loginItem:login shortcutRegistration:registration];
  controller.applicationPreferences = appPreferences;
  NSWindow *window = HostController(controller);
  TLSettingsWorkspaceView *shell = [controller valueForKey:@"workspace"];
  NSArray<TLSidebarNavigationButton *> *nav = [controller valueForKey:@"navigation"];
  Check([[nav valueForKey:@"title"] isEqual:@[@"Model", @"Tools & Keys", @"Skills", @"Plugins"]], @"Agent exposes models, credentials, skills, and plugins in its sidebar");
  NSSegmentedControl *sections = shell.sectionTabs;
  Check(sections.segmentCount == 3 && [[sections labelForSegment:0] isEqual:@"Agent"] &&
    [[sections labelForSegment:1] isEqual:@"Browser"] && [[sections labelForSegment:2] isEqual:@"Application"], @"settings has three native system sections");
  Check(nav[0].isAccessibilityElement && [nav[0].accessibilityLabel isEqual:@"Model"], @"settings navigation is exposed to assistive technology");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@1100, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 780)]; SettingsTick(window);
      Check(fabs(NSWidth(window.contentView.bounds) - width.doubleValue) < 1, @"settings respects the 200px window minimum");
      Check(shell.sidebar.hidden == (width.doubleValue < palette.settingsCompactWidth), @"settings switches to a menu on narrow windows");
      Check(shell.pageMenu.hidden != shell.sidebar.hidden, @"one navigation surface remains available");
      if (width.doubleValue == 1100) {
        NSArray<NSButton *> *models = [controller valueForKey:@"modelButtons"];
        CGFloat firstX = NSMinX([models[0] convertRect:models[0].bounds toView:controller.view]);
        CGFloat secondX = NSMinX([models[1] convertRect:models[1].bounds toView:controller.view]);
        Check(fabs(firstX - secondX) < 1, @"model controls align in a consistent column");
      }
      SettingsSnapshot(controller, window, [NSString stringWithFormat:@"settings-model-%ld-%@.png", (long)theme.integerValue, width]);
    }
  }
  [window setContentSize:NSMakeSize(1100, 780)]; SettingsTick(window);
  sections.selectedSegment = 1; [NSApp sendAction:sections.action to:sections.target from:sections]; SettingsTick(window);
  nav = [controller valueForKey:@"navigation"];
  TLBrowserSettingsController *browser = [controller valueForKey:@"browserSettingsController"];
  NSDictionary *browserControls = [browser valueForKey:@"controls"];
  Check(browserControls.count == TLBrowserPreferences.catalogue.count && browserControls.count > 0, @"Browser has native controls for every supported setting");
  NSSwitch *tracking = browserControls[@"safeBrowsing"];
  tracking.state = NSControlStateValueOn; [NSApp sendAction:tracking.action to:tracking.target from:tracking];
  Check([browserPreferences.values[@"safeBrowsing"] boolValue], @"browser toggles save to the browser service");
  browserPreferences.failSave = YES;
  tracking.state = NSControlStateValueOff; [NSApp sendAction:tracking.action to:tracking.target from:tracking];
  Check(tracking.state == NSControlStateValueOn && [[[browser valueForKey:@"status"] stringValue] isEqual:@"Save failed"], @"failed saves restore the actual toggle state and display the error");
  browserPreferences.failSave = NO;
  [NSApp sendAction:tracking.action to:tracking.target from:tracking];
  NSTextField *template = browserControls[@"customSearchURL"]; template.stringValue = @"draft search template";
  NSSearchField *browserSearch = [browser valueForKey:@"search"]; browserSearch.stringValue = @"zoom";
  [(id<NSTextFieldDelegate>)browser controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:browserSearch]];
  Check(![[browser valueForKey:@"cards"][@"zoom"] isHidden] && [[browser valueForKey:@"cards"][@"cookies"] isHidden], @"browser search filters across categories");
  Check([[nav valueForKey:@"title"] isEqual:TLBrowserPreferences.categories], @"every browser category has a sidebar entry");
  for (NSUInteger index = 0; index < nav.count; index++) {
    TLSidebarNavigationButton *item = nav[index];
    [item accessibilityPerformPress]; SettingsTick(window);
    Check(browser.selectedCategoryIndex == (NSInteger)index && item.selected, @"sidebar selection updates the browser category");
    Check(!browserSearch.stringValue.length, @"category selection opens the category after searching");
    for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
      BOOL belongs = [setting[@"category"] isEqual:TLBrowserPreferences.categories[index]];
      Check([[browser valueForKey:@"cards"] [setting[@"id"]] isHidden] != belongs, @"sidebar entries show exactly the selected category's settings");
    }
    for (NSDictionary *row in [browser valueForKey:@"extraRows"])
      Check([row[@"row"] isHidden] != [row[@"category"] isEqual:TLBrowserPreferences.categories[index]], @"data actions follow the selected category");
  }
  NSEvent *activateCategory = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
    windowNumber:window.windowNumber context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
  [nav[1] keyDown:activateCategory];
  NSView *cameraCard = [browser valueForKey:@"cards"][@"media_stream_camera"];
  Check(browser.selectedCategoryIndex == 1 && cameraCard && !cameraCard.isHidden, @"keyboard activation opens a sidebar category");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@1100,@200]) {
      [window setContentSize:NSMakeSize(width.doubleValue,780)]; SettingsTick(window);
      Check(NSContainsRect(sections.superview.bounds, sections.frame), @"all three native sections fit within the top bar at every width");
      if (width.doubleValue == 200) {
        NSInteger lastCategory = (NSInteger)TLBrowserPreferences.categories.count - 1;
        [shell.pageMenu selectItemAtIndex:lastCategory]; [NSApp sendAction:shell.pageMenu.action to:shell.pageMenu.target from:shell.pageMenu];
        Check(browser.selectedCategoryIndex == lastCategory, @"compact navigation reaches the final browser category");
        [shell.pageMenu selectItemAtIndex:0]; [NSApp sendAction:shell.pageMenu.action to:shell.pageMenu.target from:shell.pageMenu];
      } else {
        [nav[0] accessibilityPerformPress]; SettingsTick(window);
        NSPoint center = [nav[0] convertPoint:NSMakePoint(NSMidX(nav[0].bounds), NSMidY(nav[0].bounds)) toView:window.contentView.superview];
        Check([window.contentView hitTest:center] == nav[0], @"browser sidebar receives native pointer events");
      }
      SettingsSnapshot(controller, window, [NSString stringWithFormat:@"settings-browser-%@-%@.png",theme,width]);
    }
  }
  Check([template.stringValue isEqual:@"draft search template"], @"browser theme and filter changes preserve text drafts");
  [browser setValue:@YES forKey:@"busy"];
  Check(!tracking.enabled && !template.enabled, @"browser controls cannot show unsaved changes during data operations");
  [browser setValue:@NO forKey:@"busy"];
  Check(tracking.enabled && template.enabled && [template.stringValue isEqual:@"draft search template"], @"browser data operations preserve drafts when controls resume");
  [window setContentSize:NSMakeSize(1100,780)]; SettingsTick(window);
  Check(NSWidth([[browser valueForKey:@"rows"] frame]) > 700, @"browser settings use the available width for aligned columns");
  SettingsSnapshot(controller, window, @"settings-browser.png");
  sections.selectedSegment = 2; [NSApp sendAction:sections.action to:sections.target from:sections]; SettingsTick(window);
  TLApplicationSettingsController *application = [controller valueForKey:@"applicationSettingsController"];
  Check(shell.sidebar.hidden && shell.pageMenu.hidden && shell.footer.hidden && NSMinX(shell.pageHost.frame) == 0, @"Application has no sidebar, submenu, or Save footer");
  NSSwitch *loginToggle = [application valueForKey:@"loginToggle"], *notchToggle = [application valueForKey:@"notchToggle"];
  Check(loginToggle.state == NSControlStateValueOff && [[application valueForKey:@"loginStatus"] isHidden], @"an unseen login item starts off without a misleading error");
  Check(notchToggle.state == NSControlStateValueOn && login.registrations == 0, @"notch defaults on and simply opening settings never registers a login item");
  loginToggle.state = NSControlStateValueOn; [NSApp sendAction:loginToggle.action to:loginToggle.target from:loginToggle];
  Check(login.status == SMAppServiceStatusRequiresApproval && ![[application valueForKey:@"reviewLoginButton"] isHidden], @"login registration exposes the macOS approval state");
  login.status = SMAppServiceStatusEnabled; [application refresh];
  Check([[application valueForKey:@"reviewLoginButton"] isHidden] && loginToggle.state == NSControlStateValueOn, @"login state refreshes after external approval");
  login.fail = YES; loginToggle.state = NSControlStateValueOff;
  [NSApp sendAction:loginToggle.action to:loginToggle.target from:loginToggle];
  Check(loginToggle.state == NSControlStateValueOn && [[[application valueForKey:@"loginStatus"] stringValue] isEqual:@"Login item failed"], @"failed login changes restore authoritative state and explain the failure");
  login.fail = NO; loginToggle.state = NSControlStateValueOff;
  [NSApp sendAction:loginToggle.action to:loginToggle.target from:loginToggle];
  Check(login.status == SMAppServiceStatusNotRegistered, @"login item can be disabled");
  __block NSUInteger notifications = 0, quickInputs = 0;
  id observation = [NSNotificationCenter.defaultCenter addObserverForName:TLApplicationPreferencesDidChangeNotification object:appPreferences queue:nil usingBlock:^(NSNotification *note) { notifications++; }];
  notchToggle.state = NSControlStateValueOff; [NSApp sendAction:notchToggle.action to:notchToggle.target from:notchToggle];
  Check(!appPreferences.notchEnabled && notifications == 1, @"notch changes persist and notify the live app immediately");
  TLShortcutRecorder *recorder = [application valueForKey:@"shortcutRecorder"];
  [window makeKeyAndOrderFront:nil]; [recorder performClick:nil];
  Check(recorder.recording && appPreferences.shortcutRecording, @"recording temporarily suspends the global binding");
  NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagOption timestamp:0
    windowNumber:window.windowNumber context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
  [recorder keyDown:key];
  Check(!recorder.recording && [recorder.title isEqual:@"⌥Space"] && [registration.registered isEqual:appPreferences.quickInputShortcut], @"recording saves and registers the chosen native combination");
  appPreferences.quickInputHandler = ^{ quickInputs++; }; registration.handler();
  Check(quickInputs == 1, @"the registered combination invokes quick input");
  NSDictionary *savedShortcut = appPreferences.quickInputShortcut;
  [recorder performClick:nil];
  NSEvent *cancel = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
    windowNumber:window.windowNumber context:nil characters:@"\x1b" charactersIgnoringModifiers:@"\x1b" isARepeat:NO keyCode:53];
  [recorder keyDown:cancel];
  Check(!recorder.recording && [registration.registered isEqual:savedShortcut], @"Escape cancels recording without changing the saved global shortcut");
  NSError *validationError = nil;
  Check(![appPreferences setQuickInputShortcut:@{@"keyCode":@40,@"modifiers":@0,@"label":@"K"} error:&validationError] &&
    [appPreferences.quickInputShortcut isEqual:savedShortcut], @"unmodified keys cannot intercept normal typing globally");
  registration.fail = YES;
  recorder.changeHandler(@{@"keyCode":@40,@"modifiers":@(NSEventModifierFlagCommand),@"label":@"K"});
  Check([appPreferences.quickInputShortcut isEqual:savedShortcut] && [registration.registered isEqual:savedShortcut] &&
    [[[application valueForKey:@"shortcutStatus"] stringValue] isEqual:@"Shortcut in use"], @"a conflicting replacement preserves the working shortcut and displays the error");
  registration.fail = NO;
  TLShortcutRegistrationMock *reopenedRegistration = [[TLShortcutRegistrationMock alloc] init];
  TLApplicationPreferences *reopened = [[TLApplicationPreferences alloc] initWithDefaults:[[NSUserDefaults alloc] initWithSuiteName:suite] loginItem:login shortcutRegistration:reopenedRegistration];
  Check(!reopened.notchEnabled && [reopenedRegistration.registered isEqual:savedShortcut], @"notch and global shortcut survive an application restart");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette]; [application refresh];
    for (NSNumber *width in @[@1100, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue,780)]; SettingsTick(window);
      Check(shell.sidebar.hidden && shell.pageMenu.hidden && !shell.pageTitle.hidden, @"Application never shows sidebar navigation, including at compact widths");
      SettingsSnapshot(controller, window, [NSString stringWithFormat:@"settings-application-%@-%@.png", theme, width]);
    }
  }
  [recorder performClick:nil];
  sections.selectedSegment = 1; [NSApp sendAction:sections.action to:sections.target from:sections];
  Check(!recorder.recording && !appPreferences.shortcutRecording && [registration.registered isEqual:savedShortcut], @"leaving Application ends recording and restores the global binding");
  Check(browser.selectedCategoryIndex == 0 && [template.stringValue isEqual:@"draft search template"], @"switching sections preserves browser category and unsaved text");
  sections.selectedSegment = 2; [NSApp sendAction:sections.action to:sections.target from:sections];
  TLThemedButton *clearShortcut = [application valueForKey:@"clearShortcutButton"]; [clearShortcut performClick:nil];
  Check(!appPreferences.quickInputShortcut && !registration.registered && !clearShortcut.enabled, @"clearing unregisters and removes the saved shortcut");
  [NSNotificationCenter.defaultCenter removeObserver:observation];
  [defaults removePersistentDomainForName:suite];
  sections.selectedSegment = 0; [NSApp sendAction:sections.action to:sections.target from:sections];
  nav = [controller valueForKey:@"navigation"]; [nav[1] accessibilityPerformPress];
  Check([service.action isEqual:@"list"], @"tools loads credentials from the active Hermes agent");
  NSArray *entries = @[@{@"key": @"BRAVE_API_KEY", @"description": @"Web search with Brave Search.", @"category": @"tool", @"is_password": @YES, @"is_set": @YES, @"url": @"https://brave.com/search/api/"},
    @{@"key": @"FIRECRAWL_API_KEY", @"description": @"Read and extract content from websites.", @"category": @"tool", @"is_password": @YES, @"is_set": @NO},
    @{@"key": @"WEBHOOK_SECRET", @"category": @"setting", @"is_password": @YES, @"is_set": @NO}];
  service.pendingCredentials(@{@"entries":entries}, nil); SettingsTick(window);
  NSMutableDictionary *fields = [controller valueForKey:@"credentialFields"];
  Check(fields.count == 2, @"tools and settings credential categories stay separate");
  Check([fields[@"BRAVE_API_KEY"] isKindOfClass:NSSecureTextField.class] && ![fields[@"BRAVE_API_KEY"] stringValue].length, @"saved keys remain masked and are never loaded into fields");
  [fields[@"BRAVE_API_KEY"] setStringValue:@"draft-test-key"];
  NSSearchField *search = [controller valueForKey:@"credentialSearch"];
  search.stringValue = @"firecrawl";
  [(id<NSTextFieldDelegate>)controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  Check(fields.count == 1, @"search filters the installed catalogue");
  search.stringValue = @"";
  [(id<NSTextFieldDelegate>)controller controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  Check([[fields[@"BRAVE_API_KEY"] stringValue] isEqual:@"draft-test-key"], @"filtering preserves unsaved key drafts");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@1100, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 780)];
      SettingsSnapshot(controller, window, [NSString stringWithFormat:@"settings-tools-%ld-%@.png", (long)theme.integerValue, width]);
    }
  }
  TLThemedButton *save = nil;
  for (TLThemedButton *button in [controller valueForKey:@"buttons"])
    if ([button.identifier isEqual:@"BRAVE_API_KEY"] && [button.title isEqual:@"Save"]) save = button;
  [NSApp sendAction:save.action to:save.target from:save];
  Check([service.action isEqual:@"set"] && [service.value isEqual:@"draft-test-key"], @"save sends only the entered key to Hermes");
  service.pendingCredentials(@{@"ok":@YES}, nil);
  // The completion deliberately hops to the main queue; a single 20ms layout
  // tick is not a guarantee that it has run on a busy native test process.
  NSDate *credentialDeadline = [NSDate dateWithTimeIntervalSinceNow:1];
  while (![service.action isEqual:@"list"] && credentialDeadline.timeIntervalSinceNow > 0)
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:credentialDeadline];
  [window.contentView layoutSubtreeIfNeeded];
  Check([service.action isEqual:@"list"], @"save refreshes authoritative credential status");
  store.currentAgentID = 8;
  service.pendingCredentials(@{@"entries":entries}, nil); SettingsTick(window);
  Check(fields.count == 0 && [[controller valueForKey:@"credentialDrafts"] count] == 0, @"changing agents clears old credentials and drafts before reloading");
  void (^late)(NSDictionary *, NSError *) = service.pendingCredentials;
  [controller close]; late(@{@"entries": entries}, nil); SettingsTick(window);
  Check(fields.count == 0, @"late credential callbacks cannot revive a closed settings page");
  [window close];
}

static void TestSettingsThemeAndLateCatalogue(void) {
  TLFeatureCatalogueMock *catalogue = [[TLFeatureCatalogueMock alloc] init];
  TLFeatureSettingsStoreMock *store = [[TLFeatureSettingsStoreMock alloc] init];
  TLSettingsTabController *controller = [[TLSettingsTabController alloc]
    initWithSettings:[TLAppSettings defaultSettings] database:(TLDatabase *)store
    orchestrator:(TLAgentOrchestrator *)catalogue
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = HostController(controller);
  TLAppSettings *draft = [controller valueForKey:@"draftSettings"];
  draft.openRouterToken = @"test-only-legacy-token";
  TLThemedButton *token = [controller valueForKey:@"saveButton"];
  [[controller valueForKey:@"draftSettings"] setTheme:TLThemePreferenceDark];
  [window makeFirstResponder:token];
  NSResponder *responder = window.firstResponder;
  NSView *view = controller.view;
  TLThemePalette *dark = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [controller applyPalette:dark];
  Check(controller.view == view && [controller valueForKey:@"saveButton"] == token, @"settings theme keeps existing controls");
  Check([draft.openRouterToken isEqualToString:@"test-only-legacy-token"], @"settings drafts survive theme change");
  Check(window.firstResponder == responder, @"settings focus survives system palette changes");
  Check(token.palette == dark, @"settings controls update theme");
  Check(catalogue.pendingCatalogue == nil, @"settings only fetches the model catalogue when the picker opens");
  store.savedSettings = [TLAppSettings defaultSettings];
  store.savedSettings.selectedModel = @"new/large";
  store.savedSettings.supportingModel = @"new/small";
  __block TLAppSettings *saved = nil;
  controller.settingsSavedHandler = ^(TLAppSettings *settings) { saved = settings; };
  NSButton *save = [controller valueForKey:@"saveButton"];
  [NSApp sendAction:save.action to:save.target from:save];
  Check([saved.openRouterToken isEqualToString:draft.openRouterToken] && saved.theme == TLThemePreferenceSystem, @"settings saves model drafts with the system color scheme");
  Check([saved.selectedModel isEqual:@"new/large"] && [saved.supportingModel isEqual:@"new/small"], @"stale settings draft cannot overwrite composer choices");
  [controller close];
  [window close];
}

static void TestComposerModelButtonLayout(void) {
  TLMessageInput *input = [[TLMessageInput alloc] init];
  Check(input.settingsButton == nil, @"non-chat inputs do not add model controls");
  input.attachmentsEnabled = YES;
  input.showsSettingsButton = YES;
  NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
  [host addSubview:input];
  NSLayoutConstraint *width = [input.widthAnchor constraintEqualToConstant:500];
  [NSLayoutConstraint activateConstraints:@[width, [input.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
    [input.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    input.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *size in @[@200, @500]) {
      width.constant = size.doubleValue;
      [host layoutSubtreeIfNeeded];
      NSRect gear = input.settingsButton.frame, send = input.sendButton.frame;
      Check(NSMaxX(gear) <= NSMinX(send) && NSMidY(gear) == NSMidY(send), @"model settings sits immediately left of Send at narrow and wide widths");
      Check(NSWidth(input.textView.enclosingScrollView.frame) > 0, @"composer keeps editable text space at minimum window width");
    }
    width.constant = 500;
    input.textView.string = @"Ask anything…";
    [host layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
    [input cacheDisplayInRect:input.bounds toBitmapImageRep:bitmap];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:[NSString stringWithFormat:@"build/model-composer-%@.png", theme] atomically:YES];
  }
}

static void TestComposerModelDialog(void) {
  TLFeatureCatalogueMock *catalogue = [[TLFeatureCatalogueMock alloc] init];
  TLThemePalette *light = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
  TLModelSelectionWindowController *controller = [[TLModelSelectionWindowController alloc]
    initWithSmallModel:NO selectedModel:@"test/large" token:@"test" orchestrator:(id)catalogue palette:light];
  TLModelPickerView *picker = [controller valueForKey:@"picker"];
  NSSearchField *search = [picker valueForKey:@"searchField"];
  NSTableView *table = [picker valueForKey:@"tableView"];
  TLThemedButton *reload = [controller valueForKey:@"reloadButton"];
  TLThemedButton *apply = [controller valueForKey:@"switchButton"];
  TLThemedButton *cancel = [controller valueForKey:@"cancelButton"];
  __block NSString *selected = nil;
  __block void (^modelCompletion)(NSError *);
  controller.selectionHandler = ^(NSString *model, void (^completion)(NSError *)) { selected = model; modelCompletion = completion; };
  [NSApp sendAction:reload.action to:reload.target from:reload];
  Check(!apply.enabled && !search.enabled, @"cannot switch while catalogue is loading");
  catalogue.pendingCatalogue(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Offline — try again"}]);
  Check(reload.enabled && !apply.enabled, @"catalogue failure offers retry without enabling stale choices");
  [NSApp sendAction:reload.action to:reload.target from:reload];
  TLAgentModel *large = [[TLAgentModel alloc] init]; large.modelID = @"test/large"; large.name = @"Large model";
  TLAgentModel *small = [[TLAgentModel alloc] init]; small.modelID = @"test/small"; small.name = @"Small model";
  catalogue.pendingCatalogue(@[large, small], nil);
  Check(apply.enabled && search.enabled, @"loaded catalogue enables current model");
  search.stringValue = @"small";
  [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
  Check(table.numberOfRows == 1, @"model search filters available choices");
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  Check([picker.selectedModelID isEqual:@"test/small"] && selected == nil, @"picking a row is a draft until confirmed");
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette];
    Check([search.stringValue isEqual:@"small"] && [picker.selectedModelID isEqual:@"test/small"], @"theme switch preserves model draft and search");
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSView *view = controller.window.contentView;
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSString *path = [NSString stringWithFormat:@"build/model-dialog-%@.png", theme];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    for (TLThemedButton *button in @[apply, cancel, reload]) {
      NSBitmapImageRep *render = RenderThemedButton(button);
      CGFloat surface[3], alpha;
      RGBComponents(palette.tabBackground, surface, &alpha);
      CompositeColor(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface, 1, surface);
      Check(PixelMatches(render, 10, NSHeight(button.bounds) / 2, surface), @"model dialog buttons render paired theme surfaces");
    }
  }
  [NSApp sendAction:apply.action to:apply.target from:apply];
  Check(modelCompletion && !apply.enabled && !cancel.enabled && ![[controller valueForKey:@"dismissed"] boolValue], @"switch waits for Hermes acknowledgement");
  modelCompletion([NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Hermes kept the old model"}]);
  Check(apply.enabled && cancel.enabled && ![[controller valueForKey:@"dismissed"] boolValue], @"failed Hermes switch stays open and permits retry");
  [NSApp sendAction:apply.action to:apply.target from:apply];
  modelCompletion(nil);
  Check([selected isEqual:@"test/small"] && [[controller valueForKey:@"dismissed"] boolValue], @"only a confirmed switch closes the dialog");
  // A dismissed modal must ignore a catalogue request that completes later.
  [controller setValue:@NO forKey:@"dismissed"];
  [NSApp sendAction:reload.action to:reload.target from:reload];
  NSString *status = [[picker valueForKey:@"statusLabel"] stringValue];
  [NSApp sendAction:cancel.action to:cancel.target from:cancel];
  catalogue.pendingCatalogue(@[], nil);
  Check([[[picker valueForKey:@"statusLabel"] stringValue] isEqual:status], @"cancelled dialog ignores late catalogues");
  [controller.window close];
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
    NSView *host = [controller valueForKey:@"browserHostView"];
    for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      [controller applyPalette:[TLThemePalette paletteForPreference:(TLThemePreference)theme.integerValue]];
      [window.contentView layoutSubtreeIfNeeded];
      NSRect bar = [input convertRect:input.bounds toView:controller.view];
      for (NSNumber *x in @[@(NSMinX(bar) / 2), @((NSMaxX(bar) + NSWidth(controller.view.bounds)) / 2)]) {
        NSPoint point = [controller.view convertPoint:NSMakePoint(x.doubleValue, NSMidY(bar)) toView:controller.view.superview];
        NSView *hit = [controller.view hitTest:point];
        Check(hit == host || [hit isDescendantOf:host], @"both sides of the address bar pass clicks to the page in either theme");
      }
      NSPoint buttonPoint = [input.reloadButton convertPoint:NSMakePoint(NSMidX(input.reloadButton.bounds),
        NSMidY(input.reloadButton.bounds)) toView:controller.view.superview];
      NSView *buttonHit = [controller.view hitTest:buttonPoint];
      Check(buttonHit == input.reloadButton || [buttonHit isDescendantOf:input.reloadButton],
        @"reload button stays interactive above the click-through backdrop");
      NSPoint textPoint = [input.textView convertPoint:NSMakePoint(NSMidX(input.textView.bounds), NSMidY(input.textView.bounds))
        toView:controller.view.superview];
      Check([[controller.view hitTest:textPoint] isDescendantOf:input], @"address field still receives clicks");
    }
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
    NSURL *profile = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    TLBrowserPreferences *preferences = [[TLBrowserPreferences alloc] initWithProfileURL:profile];
    [preferences saveValue:@"https://duckduckgo.com/?q={searchTerms}" forSetting:[TLBrowserPreferences settingWithID:@"searchEngine"] error:nil];
    [controller setValue:preferences forKey:@"browserPreferences"];
    [input beginPromptEditing]; input.textView.string = @"red & blue";
    [NSApp sendAction:input.sendButton.action to:input.sendButton.target from:input.sendButton];
    Check([service.navigatedURL.absoluteString isEqual:@"https://duckduckgo.com/?q=red%20%26%20blue"], @"the address bar uses the selected browser search engine");
    [NSFileManager.defaultManager removeItemAtURL:profile error:nil];
    TLWebKitBrowserTitleHandler lateTitle = service.titleCallback;
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
@property (nonatomic) NSInteger skillsAgentID;
@property (nonatomic, copy) NSDictionary *savedSkillChanges;
@property (nonatomic) BOOL failSkills;
@property (nonatomic) BOOL deferSkills;
@property (nonatomic, copy) void (^skillsCompletion)(NSDictionary *, NSError *);
@end
@implementation TLAgentCreationStoreMock
- (void)hermesSkillsForAgentWithID:(NSInteger)agentID changes:(NSDictionary *)changes
                      completion:(void (^)(NSDictionary *, NSError *))completion {
  self.skillsAgentID = agentID;
  if (self.deferSkills) { self.skillsCompletion = completion; return; }
  if (self.failSkills) {
    completion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Hermes unavailable"}]);
    return;
  }
  if (changes) self.savedSkillChanges = changes;
  completion(@{@"skills": @[
    @{@"name":@"alpha", @"enabled":changes[@"alpha"] ?: @YES, @"locked_reason":@"", @"description":@"Read documents and turn meeting notes into clear action items, with owners and due dates. Keeps the original context available when you need to review the next steps."},
    @{@"name":@"beta", @"enabled":changes[@"beta"] ?: @NO, @"locked_reason":@"", @"description":@"Search the web and compare sources."},
    @{@"name":@"grounded-citations", @"enabled":@NO, @"locked_reason":@"Managed by Talaria", @"description":@"Track source URLs and format numbered citations."},
    @{@"name":@"hermes-agent", @"enabled":@YES, @"locked_reason":@"Required by Hermes"},
  ]}, nil);
}
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

static NSSwitch *SkillSwitch(TLSkillsPicker *picker, NSInteger row) {
  NSView *cell = [picker.tableView viewAtColumn:0 row:row makeIfNecessary:YES];
  [cell layoutSubtreeIfNeeded];
  return [cell viewWithTag:1];
}

static void TestAgentSkillSettings(void) {
  TLAgentRecord *agent = [TLAgentRecord new];
  agent.agentID = 19;
  agent.name = @"Atlas";
  agent.avatar = @"🦊";
  agent.soul = @"Be thoughtful.";
  TLAgentCreationStoreMock *store = [TLAgentCreationStoreMock new];
  TLAgentCreationWindowController *controller = [[TLAgentCreationWindowController alloc] initWithAgent:agent
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] orchestrator:(id)store];
  TLSkillsPicker *picker = [controller valueForKey:@"skillsPicker"];
  Check(store.skillsAgentID == 0, @"opening general settings does not start a skills request");
  [[controller valueForKey:@"skillsTabButton"] performClick:nil];
  [controller.window.contentView layoutSubtreeIfNeeded];
  Check(store.skillsAgentID == 19 && picker.tableView.numberOfRows == 4, @"skills load for the edited agent, including disabled skills");
  Check(!SkillSwitch(picker, 2).enabled && !SkillSwitch(picker, 3).enabled, @"managed and required skills cannot be toggled");
  [SkillSwitch(picker, 0) performClick:nil];
  Check([picker.changes isEqual:@{@"alpha":@NO}] && !store.savedSkillChanges, @"skill toggles stay in the draft until Save");
  NSSearchField *search = [picker valueForKey:@"searchField"];
  search.stringValue = @"BETA";
  [(id<NSTextFieldDelegate>)picker controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  Check(picker.tableView.numberOfRows == 1, @"skill search ignores case");
  [SkillSwitch(picker, 0) performClick:nil];
  Check([picker.changes isEqual:@{@"alpha":@NO, @"beta":@YES}], @"filtered toggles change the correct skill");
  search.stringValue = @"compare sources";
  [(id<NSTextFieldDelegate>)picker controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];
  Check(picker.tableView.numberOfRows == 1 && [SkillSwitch(picker, 0).identifier isEqual:@"beta"],
    @"skill search includes Hermes descriptions");
  [[controller valueForKey:@"generalTabButton"] performClick:nil];
  [[controller valueForKey:@"skillsTabButton"] performClick:nil];
  Check(picker.changes.count == 2, @"switching sections preserves the skills draft");
  search.stringValue = @"";
  [(id<NSTextFieldDelegate>)picker controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:search]];

  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette];
    [controller.window.contentView layoutSubtreeIfNeeded];
    NSView *root = controller.window.contentView;
    NSRect pickerFrame = [picker convertRect:picker.bounds toView:root];
    NSView *save = [controller valueForKey:@"createButton"];
    NSRect saveFrame = [save convertRect:save.bounds toView:root];
    Check(NSContainsRect(root.bounds, pickerFrame) && NSMinY(pickerFrame) > NSMaxY(saveFrame), @"skills fit above the settings footer");
    for (NSInteger row = 0; row < 4; row++) {
      NSSwitch *toggle = SkillSwitch(picker, row);
      Check([toggle isKindOfClass:NSSwitch.class] && NSWidth(toggle.bounds) > 0 && NSHeight(toggle.bounds) > 0,
        @"skills use visible native switches");
      Check(toggle.state == (row == 1 || row == 3 ? NSControlStateValueOn : NSControlStateValueOff),
        @"native switch state reflects draft and locked values in both themes");
      NSTableCellView *cell = (NSTableCellView *)toggle.superview;
      NSTextField *detail = [cell viewWithTag:2];
      Check(detail.hidden == (row == 3), @"missing descriptions do not leave an empty label");
      if (!detail.hidden) {
        Check(NSMinY(detail.frame) >= NSMaxY(cell.textField.frame) && NSMaxY(detail.frame) <= NSHeight(cell.bounds),
          @"skill descriptions fit beneath their names without overlapping the next row");
        NSBitmapImageRep *bitmap = [cell bitmapImageRepForCachingDisplayInRect:cell.bounds];
        [cell cacheDisplayInRect:cell.bounds toBitmapImageRep:bitmap];
        CGFloat foreground[3], alpha;
        RGBComponents(palette.textMuted, foreground, &alpha);
        NSUInteger textPixels = 0;
        for (NSInteger y = 0; y < bitmap.pixelsHigh; y++)
          for (NSInteger x = 0; x < bitmap.pixelsWide; x++)
            if (PixelMatches(bitmap, x, y, foreground)) textPixels++;
        Check(textPixels > 5, @"skill descriptions render readable theme text");
      }
    }
    NSBitmapImageRep *preview = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:preview];
    [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:palette.dark ? @"build/agent-skills-dark.png" : @"build/agent-skills-light.png" atomically:YES];
  }
  [[controller valueForKey:@"cancelButton"] performClick:nil];
  Check(!store.savedSkillChanges && !store.savedProfile, @"Cancel leaves Hermes and the profile unchanged");
  [controller.window close];

  controller = [[TLAgentCreationWindowController alloc] initWithAgent:agent
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] orchestrator:(id)store];
  picker = [controller valueForKey:@"skillsPicker"];
  store.failSkills = YES;
  [[controller valueForKey:@"skillsTabButton"] performClick:nil];
  Check([picker.message isEqual:@"Hermes unavailable"] && !picker.loading, @"load errors are visible and retryable");
  store.failSkills = NO;
  [[picker valueForKey:@"reloadButton"] performClick:nil];
  [controller.window.contentView layoutSubtreeIfNeeded];
  [SkillSwitch(picker, 0) performClick:nil];
  store.failSkills = YES;
  [[controller valueForKey:@"createButton"] performClick:nil];
  Check(!store.savedProfile && picker.changes.count == 1 &&
        [[[controller valueForKey:@"statusLabel"] stringValue] isEqual:@"Hermes unavailable"], @"failed Save keeps the draft and sheet available");
  store.failSkills = NO;
  store.deferSkills = YES;
  [[controller valueForKey:@"createButton"] performClick:nil];
  Check(![[controller valueForKey:@"createButton"] isEnabled] && ![[controller valueForKey:@"cancelButton"] isEnabled] && !picker.enabled,
        @"pending Save prevents duplicate submissions and cancellation");
  store.deferSkills = NO;
  [store hermesSkillsForAgentWithID:19 changes:picker.changes completion:store.skillsCompletion];
  store.skillsCompletion = nil;
  Check([store.savedSkillChanges isEqual:@{@"alpha":@NO}] && store.savedProfile.agentID == 19 && picker.changes.count == 0,
        @"Save persists skill changes for this agent and then saves the profile");
  [controller.window close];
}

static void TestSkillsInSettingsWorkspace(void) {
  TLFeatureSettingsStoreMock *database = [TLFeatureSettingsStoreMock new];
  database.currentAgentID = 19;
  TLAgentCreationStoreMock *service = [TLAgentCreationStoreMock new];
  TLSettingsTabController *controller = [[TLSettingsTabController alloc] initWithSettings:TLAppSettings.defaultSettings
    database:(id)database orchestrator:(id)service palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  NSWindow *window = HostController(controller);
  [window setContentSize:NSMakeSize(1100, 780)];
  TLSettingsWorkspaceView *shell = [controller valueForKey:@"workspace"];
  NSArray<TLSidebarNavigationButton *> *nav = [controller valueForKey:@"navigation"];
  Check(service.skillsAgentID == 0, @"opening Model does not request skills");
  [nav[2] accessibilityPerformPress]; SettingsTick(window);
  TLSkillsPicker *picker = [controller valueForKey:@"skillsPicker"];
  TLThemedButton *save = [controller valueForKey:@"saveButton"];
  Check([shell.pageTitle.stringValue isEqual:@"Skills"] && !shell.footer.hidden &&
    service.skillsAgentID == 19 && picker.tableView.numberOfRows == 4, @"Settings > Agent > Skills loads the current agent's installed skills");
  Check(!SkillSwitch(picker, 2).enabled && !SkillSwitch(picker, 3).enabled, @"workspace respects managed and required skills");
  [SkillSwitch(picker, 0) performClick:nil];
  Check(save.enabled && !service.savedSkillChanges, @"workspace skill changes remain drafts until Save");
  [nav[0] accessibilityPerformPress]; [nav[2] accessibilityPerformPress]; SettingsTick(window);
  Check(picker.changes.count == 1, @"navigation keeps the skill draft");
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@1100, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 780)]; SettingsTick(window);
      Check([[shell.pageMenu titleOfSelectedItem] isEqual:@"Skills"], @"compact navigation includes Skills");
      NSRect pickerRect = [picker convertRect:picker.bounds toView:shell];
      Check(NSMinX(pickerRect) >= 0 && NSMaxX(pickerRect) <= NSWidth(shell.bounds) + 1,
        @"skills fit the available settings width");
      NSSwitch *toggle = SkillSwitch(picker, 0);
      NSRect toggleRect = [toggle convertRect:toggle.bounds toView:picker];
      Check(NSMinX(toggleRect) >= 0 && NSMaxX(toggleRect) <= NSWidth(picker.bounds) + 1,
        @"skill actions stay visible at narrow widths");
      NSTableCellView *cell = (NSTableCellView *)toggle.superview;
      Check(width.doubleValue > 200 || NSWidth(cell.textField.bounds) >= NSWidth(picker.bounds) / 2,
        @"narrow rows keep space for identifying the skill");
      NSTextField *detail = [cell viewWithTag:2];
      Check(NSMaxY(detail.frame) <= NSHeight(cell.bounds) && NSMaxX(detail.frame) <= NSWidth(cell.bounds),
        @"wrapped descriptions remain inside their rows at every window width");
      Check(width.doubleValue > 200 || NSHeight(detail.frame) > NSHeight(cell.textField.frame),
        @"narrow descriptions wrap onto multiple lines");
      Check([picker.palette.controlText isEqual:palette.controlText], @"skills follow the active settings theme");
      SettingsSnapshot(controller, window, [NSString stringWithFormat:@"settings-skills-%@-%@.png", palette.dark ? @"dark" : @"light", width]);
    }
  }
  [window setContentSize:NSMakeSize(1100, 780)]; SettingsTick(window);
  __block NSInteger savedAgentID = 0;
  controller.skillsSavedHandler = ^(NSInteger agentID) { savedAgentID = agentID; };
  service.failSkills = YES;
  [save performClick:nil]; SettingsTick(window);
  Check(picker.changes.count == 1 && save.enabled && !savedAgentID &&
    [[[controller valueForKey:@"footerLabel"] stringValue] isEqual:@"Hermes unavailable"], @"failed skill Save keeps the draft available for retry");
  service.failSkills = NO; service.deferSkills = YES;
  [save performClick:nil];
  Check(!save.enabled && !picker.enabled, @"pending skill Save prevents duplicate writes");
  service.deferSkills = NO;
  [service hermesSkillsForAgentWithID:19 changes:picker.changes completion:service.skillsCompletion]; SettingsTick(window);
  Check(savedAgentID == 19 && picker.changes.count == 0 && !database.savedSettings &&
    [service.savedSkillChanges isEqual:@{@"alpha":@NO}], @"workspace saves skills separately from model settings and refreshes the command catalogue");
  [SkillSwitch(picker, 1) performClick:nil];
  database.currentAgentID = 20;
  [save performClick:nil]; SettingsTick(window);
  Check(service.skillsAgentID == 20 && picker.changes.count == 0 &&
    [service.savedSkillChanges isEqual:@{@"alpha":@NO}], @"an agent switch reloads skills without writing another agent's draft");
  service.deferSkills = YES;
  [[picker valueForKey:@"reloadButton"] performClick:nil];
  void (^late)(NSDictionary *, NSError *) = service.skillsCompletion;
  database.currentAgentID = 21;
  late(@{@"skills":@[]}, nil); SettingsTick(window);
  Check(service.skillsAgentID == 21 && picker.loading, @"late results from the previous agent trigger a fresh catalogue request");
  late = service.skillsCompletion;
  [controller close]; late(@{@"skills":@[]}, nil); SettingsTick(window);
  Check(picker.loading, @"closing settings discards late skill callbacks");
  [window close];
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

@interface TalariaWindowController (SuggestionTypingTests)
- (NSView *)buildSlashCommandListView;
- (void)textDidChange:(NSNotification *)notification;
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)selector;
@end

@interface TLTypingPickerController : TalariaWindowController
@property (nonatomic) NSUInteger refreshCount;
@property (nonatomic) NSUInteger layoutCount;
@end
@implementation TLTypingPickerController
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext { self.layoutCount++; }
- (void)updateMessageScrollInsets { self.layoutCount++; }
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext { return YES; }
- (void)refreshHermesCommandsIfNeeded { self.refreshCount++; }
@end

static void DrainSuggestionTimer(void) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.06];
  while (deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:deadline];
}

@interface TalariaWindowController (QueuedSuggestionTests)
- (NSView *)buildChatWorkspace;
- (void)updateControlStates;
- (void)renderSlashCommandList;
- (void)hideSlashCommandList;
- (BOOL)performInputSuggestionAtIndex:(NSUInteger)index;
- (void)sendMessage:(id)sender;
@end

@interface TLQueuedSuggestionController : TalariaWindowController
@property (nonatomic, strong) NSURL *openedURL;
@property (nonatomic) NSUInteger openedCount;
@end
@implementation TLQueuedSuggestionController
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext { return YES; }
- (BOOL)isChatPresentationVisibleForChat:(TLChatTabController *)chatContext { return YES; }
- (void)styleSidebarActionButtons {}
- (void)updateAgentControlStates {}
- (void)refreshHermesCommandsIfNeeded {}
- (void)updateWorkspaceMode {}
- (void)reloadWorkspaceTabs {}
- (void)renderMessages {}
- (void)openBrowserURLFromChatInput:(NSURL *)URL { self.openedURL = URL; self.openedCount++; }
@end

static void TestSuggestionsWithQueuedPrompts(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 650, 600)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLQueuedSuggestionController *controller = [[TLQueuedSuggestionController alloc] initWithWindow:window];
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [controller setValue:palette forKey:@"palette"];
  [controller setValue:window.contentView forKey:@"rootView"];
  TLChatRecord *record = [TLChatRecord new]; record.chatID = 17;
  [controller setValue:record forKey:@"activeChat"];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"test-token"; settings.selectedModel = @"test-model";
  [controller setValue:settings forKey:@"settings"];
  NSView *workspace = [controller buildChatWorkspace];
  [controller setValue:workspace forKey:@"chatWorkspace"];
  [window.contentView addSubview:workspace];
  [NSLayoutConstraint activateConstraints:@[
    [workspace.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [workspace.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [workspace.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [workspace.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]]];
  TLChatTabController *chat = [controller valueForKey:@"chatPresentation"];
  [chat.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Summarize it" attachmentURLs:@[]]];
  [chat.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Summarize it again" attachmentURLs:@[]]];
  TLStopTestRunner *runner = [[TLStopTestRunner alloc] initWithMessageStore:(id)[NSObject new] streaming:(id)[NSObject new]];
  NSMutableDictionary *runners = [NSMutableDictionary dictionaryWithObject:runner forKey:@17];
  [controller setValue:runners forKey:@"turnRunners"];
  [window.contentView layoutSubtreeIfNeeded];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller setValue:palette forKey:@"palette"];
    chat.messageInput.palette = palette;
    for (NSNumber *width in @[@650, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 600)];
      chat.messageInputWidthConstraint.constant = width.doubleValue - palette.space5 * 2;
      [window.contentView layoutSubtreeIfNeeded];
      chat.promptTextView.string = @"netflix.com";
      [controller textDidChange:nil];
      DrainSuggestionTimer();
      Check(!chat.slashCommandListView.hidden && chat.visibleSlashCommands.count == 2 &&
        [chat.visibleSlashCommands[0][@"kind"] isEqual:@"web"] && [chat.visibleSlashCommands[1][@"kind"] isEqual:@"prompt"],
        @"a streaming chat with queued prompts still offers Open site and Send message");
      [controller updateControlStates];
      Check(!chat.slashCommandListView.hidden, @"streaming control updates cannot hide active suggestions");
      NSRect queueRect = chat.promptQueueView.frame;
      NSRect suggestions = chat.slashCommandListView.frame;
      Check(NSMinY(queueRect) >= NSMaxY(suggestions) && NSMinY(suggestions) >= NSMaxY(chat.messageInput.frame),
        @"queue, suggestions, and composer occupy separate vertical space at every width");
      Check(-chat.messageStackBottomConstraint.constant > NSMaxY(queueRect), @"transcript inset clears both the suggestions and queue");
      NSRect crop = NSMakeRect(0, 0, NSWidth(workspace.bounds), NSMaxY(queueRect) + palette.space5);
      NSBitmapImageRep *bitmap = [workspace bitmapImageRepForCachingDisplayInRect:crop];
      [workspace cacheDisplayInRect:crop toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"build/queued-suggestions-%@-%@.png", theme, width] atomically:YES];
      [controller hideSlashCommandList];
      Check(fabs(NSMinY(chat.promptQueueView.frame) - NSMaxY(chat.messageInput.frame) - palette.space3) < 1,
        @"dismissing suggestions returns the queue to the composer without an empty gap");
    }
  }
  chat.promptTextView.string = @"netflix.com";
  [controller textDidChange:nil];
  Check([controller textView:chat.promptTextView doCommandBySelector:@selector(insertNewline:)], @"Enter activates the pending website suggestion");
  Check([controller.openedURL.absoluteString isEqual:@"https://netflix.com"] && chat.queuedPrompts.count == 2 && runner.stopCount == 0,
    @"opening a site by keyboard leaves the running response and queue intact");
  chat.promptTextView.string = @"example.com";
  [controller renderSlashCommandList];
  chat.slashCommandScrollView.activationHandler(0);
  Check(controller.openedCount == 2 && [controller.openedURL.host isEqual:@"example.com"], @"clicking Open site works during generation");
  chat.promptTextView.string = @"netflix.com";
  [controller renderSlashCommandList];
  Check([controller performInputSuggestionAtIndex:1] && chat.queuedPrompts.count == 3 &&
    [chat.queuedPrompts.lastObject.text isEqual:@"netflix.com"] && controller.openedCount == 2,
    @"choosing Send message queues the URL as text instead of opening a browser");
  chat.promptTextView.string = @"another.example";
  [controller sendMessage:nil];
  Check([controller.openedURL.host isEqual:@"another.example"] && chat.queuedPrompts.count == 3,
    @"direct URL submission retains automatic browser routing while queued");
  [controller setValue:@[@{@"kind":@"hermes", @"command":@"/help", @"title":@"Help", @"icon":@"terminal"}] forKey:@"hermesCommands"];
  chat.promptTextView.string = @"/help";
  [controller renderSlashCommandList];
  Check([controller performInputSuggestionAtIndex:0] && [chat.queuedPrompts.lastObject.text isEqual:@"/help"],
    @"Hermes suggestions enqueue commands behind the current turn");
  [runners removeAllObjects]; chat.queuePaused = YES;
  chat.promptTextView.string = @"netflix.com";
  [controller renderSlashCommandList]; [controller updateControlStates];
  Check(!chat.slashCommandListView.hidden && [controller performInputSuggestionAtIndex:0], @"website suggestions also work with a paused queue");
  chat.editingQueuedPrompt = chat.queuedPrompts.firstObject;
  chat.promptTextView.string = @"netflix.com";
  [controller renderSlashCommandList];
  Check(chat.slashCommandListView.hidden && ![controller performInputSuggestionAtIndex:0], @"editing a queued prompt cannot accidentally navigate away");
  [window close];
}

static void TestSuggestionTypingAndVirtualization(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 600)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLTypingPickerController *controller = [[TLTypingPickerController alloc] initWithWindow:window];
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [controller setValue:palette forKey:@"palette"];
  [controller setValue:window.contentView forKey:@"rootView"];
  TLMessageInput *input = [[TLMessageInput alloc] initWithFrame:NSMakeRect(0, 0, 500, 60)];
  input.translatesAutoresizingMaskIntoConstraints = YES;
  [window.contentView addSubview:input];
  [controller setValue:input forKey:@"messageInput"];
  [controller setValue:input.textView forKey:@"promptTextView"];
  NSView *pane = [controller buildSlashCommandListView];
  [window.contentView addSubview:pane];
  [NSLayoutConstraint activateConstraints:@[
    [controller valueForKey:@"slashCommandListWidthConstraint"], [controller valueForKey:@"slashCommandListHeightConstraint"],
    [pane.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [pane.topAnchor constraintEqualToAnchor:window.contentView.topAnchor]]];
  NSMutableArray *commands = [NSMutableArray array];
  for (NSUInteger i = 0; i < 5000; i++) {
    [commands addObject:@{@"kind": @"hermes", @"command": [NSString stringWithFormat:@"/command%lu", (unsigned long)i],
                         @"description": @"Dynamic Hermes command", @"title": @"Command", @"icon": @"terminal"}];
  }
  [commands addObject:@{@"kind": @"hermes", @"command": @"/model", @"description": @"Choose model", @"icon": @"terminal"}];
  [controller setValue:commands forKey:@"hermesCommands"];
  input.textView.string = @"/";
  NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
  [controller textDidChange:nil];
  NSLog(@"Slash typing callback with %lu commands: %.3f ms", (unsigned long)commands.count,
    (NSProcessInfo.processInfo.systemUptime - start) * 1000);
  Check(controller.refreshCount == 0 && pane.hidden && controller.layoutCount == 0,
        @"typing returns before command lookup, view creation, or forced workspace layout");
  Check([input.textView.string isEqualToString:@"/"], @"slash is already in the composer while suggestions are pending");
  DrainSuggestionTimer();
  Check(controller.refreshCount == 1 && !pane.hidden, @"suggestions appear after the input event");
  TLInputSuggestionListView *list = [controller valueForKey:@"slashCommandScrollView"];
  NSTableView *table = [list valueForKey:@"table"];
  TLInputSuggestionListView *widthProbe = [[TLInputSuggestionListView alloc] init];
  widthProbe.suggestions = @[@{@"command": @"Open river.ai"}, @{@"command": @"Send message"}];
  CGFloat compactWidth = [widthProbe preferredWidthWithMaximum:700];
  Check(compactWidth > 0 && compactWidth < 300, @"short suggestions hug their contents");
  widthProbe.suggestions = @[@{@"command": @"Open river.ai", @"description": @"A description that needs additional room"}];
  Check([widthProbe preferredWidthWithMaximum:700] > compactWidth, @"descriptions contribute to preferred width");
  Check([widthProbe preferredWidthWithMaximum:100] == 100, @"content width stays within the available maximum");

  for (NSNumber *width in @[@200, @500]) {
    input.frame = NSMakeRect(0, 0, width.doubleValue, 60);
    [controller textDidChange:nil];
    DrainSuggestionTimer();
    [window.contentView layoutSubtreeIfNeeded];
    Check(table.numberOfRows == (NSInteger)commands.count, @"large catalogue remains complete");
    Check(list.scrollingEnabled && list.hasVerticalScroller, @"long catalogue scrolls after reaching the viewport limit");
    Check(NSWidth(pane.frame) <= width.doubleValue, [NSString stringWithFormat:@"suggestions fit composers: requested %@, input %.0f, pane %.0f", width, NSWidth(input.bounds), NSWidth(pane.frame)]);
    __block NSUInteger materialized = 0;
    [table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) { materialized++; }];
    Check(materialized > 0 && materialized < 30, @"only viewport rows are materialized, independent of catalogue size");
    list.selectedIndex = commands.count - 1;
    [window.contentView layoutSubtreeIfNeeded];
    Check(NSIntersectsRect(table.visibleRect, [table rectOfRow:commands.count - 1]), @"keyboard selection reaches commands beyond the viewport");
    TLSlashCommandItemView *last = [table viewAtColumn:0 row:commands.count - 1 makeIfNecessary:NO];
    Check(last.selected && [last.command isEqualToString:@"/model"], @"reused row reflects selection and current command");
  }
  list.selectedIndex = 0;
  [window.contentView layoutSubtreeIfNeeded];
  TLSlashCommandItemView *pointerRow = [table viewAtColumn:0 row:1 makeIfNecessary:YES];
  NSPoint pointerPoint = [table convertPoint:NSMakePoint(NSMidX(table.bounds), NSMidY([table rectOfRow:1])) toView:nil];
  NSEvent *move = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:pointerPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
  [list mouseMoved:move];
  Check(list.selectedIndex == 1 && [[controller valueForKey:@"selectedSlashCommandIndex"] integerValue] == 1, @"mouse selection updates the keyboard navigation index");
  [controller textView:input.textView doCommandBySelector:@selector(moveDown:)];
  [pointerRow mouseEntered:move];
  Check(list.selectedIndex == 2 && !pointerRow.selected, @"stationary hover cannot override the latest keyboard selection");
  Check(CGColorEqualToColor(pointerRow.layer.backgroundColor, TLCGColor(list.palette.slashCommandItemSurface)), @"hovered row does not retain a second highlight");
  [list mouseMoved:move];
  Check(list.selectedIndex == 1 && pointerRow.selected, @"actual mouse movement takes selection back from keyboard");
  __block NSUInteger selectedRows = 0;
  [table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) {
    TLSlashCommandItemView *cell = [table viewAtColumn:0 row:index makeIfNecessary:NO];
    if (cell.selected) selectedRows++;
  }];
  Check(selectedRows == 1, @"only one materialized suggestion is selected");
  NSUInteger previous = controller.refreshCount;
  input.textView.string = @"/co"; [controller textDidChange:nil];
  input.textView.string = @"/mod"; [controller textDidChange:nil];
  Check(controller.refreshCount == previous, @"rapid edits do not synchronously rebuild suggestions");
  DrainSuggestionTimer();
  Check(controller.refreshCount == previous + 1 && list.suggestions.count == 1, @"rapid edits coalesce to the latest prompt");
  input.textView.string = @"/mo"; [controller textDidChange:nil];
  Check([controller textView:input.textView doCommandBySelector:@selector(insertTab:)], @"Tab resolves a pending suggestion update");
  Check([input.textView.string isEqualToString:@"/model "], @"Tab uses current input rather than stale rows");
  input.textView.string = @"/"; [controller textDidChange:nil];
  previous = controller.refreshCount;
  Check([controller textView:input.textView doCommandBySelector:@selector(cancelOperation:)], @"Escape cancels a pending picker");
  DrainSuggestionTimer();
  Check(pane.hidden && controller.refreshCount == previous, @"cancelled updates cannot reopen the picker");
  pane.hidden = NO;
  ((NSLayoutConstraint *)[controller valueForKey:@"slashCommandListWidthConstraint"]).constant = 200;
  ((NSLayoutConstraint *)[controller valueForKey:@"slashCommandListHeightConstraint"]).constant = 100;
  list.suggestions = @[@{@"kind": @"status", @"command": @"Loading"}, @{@"kind": @"hermes", @"command": @"/help"}];
  Check(![list isSuggestionEnabledAtIndex:0] && [list isSuggestionEnabledAtIndex:1], @"status is inert and commands remain actionable");
  __block NSUInteger activated = NSNotFound;
  list.activationHandler = ^(NSUInteger index) { activated = index; };
  [window.contentView layoutSubtreeIfNeeded];
  TLSlashCommandItemView *retry = [table viewAtColumn:0 row:1 makeIfNecessary:YES];
  [retry sendAction:retry.action to:retry.target];
  Check(activated == 1, @"reused mouse targets activate the current row");
  list.suggestions = @[@{@"kind": @"status", @"command": @"Hermes is not installed"}];
  ((NSLayoutConstraint *)[controller valueForKey:@"slashCommandListHeightConstraint"]).constant = palette.slashCommandRowHeight + palette.space2 * 2;
  [window.contentView layoutSubtreeIfNeeded];
  NSTableCellView *single = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
  [single layoutSubtreeIfNeeded];
  NSTextField *label = single.textField;
  Check([single isKindOfClass:NSTableCellView.class] && !label.selectable && !label.editable, @"errors use plain non-selectable text, not command controls");
  list.selectedIndex = 0;
  Check(list.selectedIndex == -1, @"status text cannot be selected by keyboard");
  NSRect labelRect = [label convertRect:label.bounds toView:list.contentView];
  Check(NSMinY(labelRect) >= NSMinY(list.contentView.bounds) && NSMaxY(labelRect) <= NSMaxY(list.contentView.bounds),
        [NSString stringWithFormat:@"single row fits: label %@ clip %@ cell %@ table %@ row %@", NSStringFromRect(labelRect), NSStringFromRect(list.contentView.bounds), NSStringFromRect(single.frame), NSStringFromRect(table.frame), NSStringFromRect([table rectOfRow:0])]);
  list.palette = [TLThemePalette paletteForPreference:TLThemePreferenceLight];
  Check([label.textColor isEqual:list.palette.textMuted], @"theme changes update status text");
  [controller setValue:@[] forKey:@"hermesCommands"];
  [controller setValue:@"Hermes is not installed" forKey:@"hermesCommandsError"];
  input.textView.string = @"/";
  [controller textDidChange:nil];
  DrainSuggestionTimer();
  Check(list.suggestions.count == 1 && [list.suggestions[0][@"kind"] isEqualToString:@"status"], @"discovery failures render as status text");
  Check(![controller textView:input.textView doCommandBySelector:@selector(moveDown:)] &&
        [[controller valueForKey:@"selectedSlashCommandIndex"] integerValue] == -1,
        @"arrow keys cannot select the error message");
  Check(!list.scrollingEnabled && !list.hasVerticalScroller, @"one error message has no scrollbar");
  Check([pane isKindOfClass:TLInputSuggestionPanelView.class] && ![pane isKindOfClass:TLGlassPaneView.class], @"suggestions use background blur without glass treatment");
  TLInputSuggestionPanelView *backdrop = (TLInputSuggestionPanelView *)pane;
  Check(backdrop.blendingMode == NSVisualEffectBlendingModeWithinWindow, @"suggestions blur the content behind them");
  for (NSNumber *preference in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *theme = [TLThemePalette paletteForPreference:preference.integerValue];
    backdrop.palette = theme;
    NSColor *tint = [theme.suggestionBackdropTint colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    NSColor *expected = [theme.tabBackground colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    Check(fabs(tint.redComponent - expected.redComponent) < 0.01 && fabs(tint.greenComponent - expected.greenComponent) < 0.01 &&
          fabs(tint.blueComponent - expected.blueComponent) < 0.01 && tint.alphaComponent > 0 && tint.alphaComponent < 1,
          @"backdrop tint matches the chat background with reduced opacity in both themes");
  }
  [controller setValue:nil forKey:@"hermesCommandsError"];
  for (NSUInteger count = 1; count <= 9; count++) {
    [controller setValue:[commands subarrayWithRange:NSMakeRange(0, count)] forKey:@"hermesCommands"];
    [controller textDidChange:nil];
    DrainSuggestionTimer();
    [window.contentView layoutSubtreeIfNeeded];
    BOOL overflow = list.contentHeight > NSHeight(list.contentView.bounds) + 0.5;
    Check(list.hasVerticalScroller == overflow && list.scrollingEnabled == overflow, @"scrolling only appears when content exceeds the available height");
    if (!overflow) Check(NSHeight(list.contentView.bounds) >= list.contentHeight, @"short lists fit all rows without scrolling");
  }
  [window close];
}

@interface TalariaWindowController (AgentRepairTests)
- (TLAgentRecord *)selectedAgent;
- (void)updateAgentControlStates;
- (void)startSelectedAgent:(id)sender;
- (void)initializeAgentWithID:(NSInteger)agentID;
@end
@interface TLRepairController : TalariaWindowController
@property(nonatomic, strong) TLAgentRecord *testAgent;
@property(nonatomic) NSInteger repairAgentID;
@end
@implementation TLRepairController
- (TLAgentRecord *)selectedAgent { return self.testAgent; }
- (void)initializeAgentWithID:(NSInteger)agentID { self.repairAgentID = agentID; }
@end
@interface TLRepairOrchestrator : NSObject
@end
@implementation TLRepairOrchestrator
- (BOOL)isVMRunningForAgent:(TLAgentRecord *)agent { return YES; }
- (BOOL)hasHermesInstallationForAgent:(TLAgentRecord *)agent { return NO; }
@end
@interface TalariaWindowController (WarmupTests)
- (NSView *)buildSettingsTabContent;
- (void)prepareHermesCommands;
- (void)refreshAgents;
- (void)selectAgentWithID:(NSInteger)agentID;
- (void)closeSettingsTab:(id)sender;
- (void)applyTheme;
@end
@interface TLWarmupController : TLRepairController
@property NSUInteger warmupCount;
@end
@implementation TLWarmupController
- (void)prepareHermesCommands { self.warmupCount++; }
- (void)refreshAgents {}
- (void)selectAgentWithID:(NSInteger)agentID {}
- (void)closeSettingsTab:(id)sender {}
- (void)applyTheme {}
- (void)updateAgentControlStates {}
@end
@interface TLWarmupStore : TLFeatureSettingsStoreMock
@end
@implementation TLWarmupStore
@end
@interface TLWarmupOrchestrator : TLFeatureCatalogueMock
@property TLAgentRecord *agent;
@property NSError *startError;
@end
@implementation TLWarmupOrchestrator
- (BOOL)hasHermesInstallationForAgent:(TLAgentRecord *)agent { return YES; }
- (void)startAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion {
  completion(self.agent, self.startError);
}
@end
static void TestWarmupAfterSettingsAndManualStart(void) {
  TLWarmupController *controller = [[TLWarmupController alloc] initWithWindow:nil];
  TLWarmupStore *store = [[TLWarmupStore alloc] init];
  TLWarmupOrchestrator *orchestrator = [[TLWarmupOrchestrator alloc] init];
  TLAppSettings *settings = [TLAppSettings defaultSettings];
  settings.openRouterToken = @"old-token";
  [controller setValue:settings forKey:@"settings"];
  [controller setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  [controller setValue:store forKey:@"database"];
  [controller setValue:orchestrator forKey:@"agentOrchestrator"];
  [controller buildSettingsTabContent];
  TLSettingsTabController *tab = [controller valueForKey:@"settingsTabController"];
  TLAppSettings *saved = [settings copy];
  saved.rememberOpenRouterToken = YES;
  tab.settingsSavedHandler(saved);
  Check(controller.warmupCount == 0, @"credential-storage-only settings do not warm or restart inference");
  saved = [saved copy];
  saved.openRouterToken = @"new-token";
  tab.settingsSavedHandler(saved);
  Check(controller.warmupCount == 1, @"changed credentials prepare Hermes before the next send");
  saved = [saved copy];
  saved.selectedModel = @"other-model";
  tab.settingsSavedHandler(saved);
  Check(controller.warmupCount == 2, @"changed model settings refresh the prepared gateway");
  controller.testAgent = [[TLAgentRecord alloc] init];
  controller.testAgent.agentID = 42;
  controller.testAgent.status = TLAgentStatusStopped;
  orchestrator.agent = controller.testAgent;
  store.currentAgentID = 42;
  [controller startSelectedAgent:nil];
  Check(controller.warmupCount == 3, @"manual restart of the current VM also prepares Hermes");
  store.currentAgentID = 43;
  [controller startSelectedAgent:nil];
  Check(controller.warmupCount == 3, @"starting another VM does not wake the current agent");
  tab.skillsSavedHandler(42);
  Check(controller.warmupCount == 3, @"saving another agent's skills does not refresh the current catalogue");
  tab.skillsSavedHandler(43);
  Check(controller.warmupCount == 4, @"saving the current agent's skills refreshes the command catalogue");
}

static void TestRunningAgentRepairAction(void) {
  TLRepairController *controller = [[TLRepairController alloc] initWithWindow:nil];
  controller.testAgent = [[TLAgentRecord alloc] init];
  controller.testAgent.agentID = 42;
  controller.testAgent.status = TLAgentStatusRunning;
  [controller setValue:[[TLRepairOrchestrator alloc] init] forKey:@"agentOrchestrator"];
  [controller setValue:[[TLWorkspaceTab alloc] init] forKey:@"agentsTab"];
  NSButton *start = [[NSButton alloc] init];
  NSButton *stop = [[NSButton alloc] init];
  [controller setValue:start forKey:@"startAgentButton"];
  [controller setValue:stop forKey:@"stopAgentButton"];
  [controller updateAgentControlStates];
  Check(start.enabled && [start.title isEqualToString:@"Install Hermes"], @"missing Hermes can be installed while the VM is running");
  Check(stop.enabled, @"running VM can still be stopped before setup");
  [controller startSelectedAgent:nil];
  Check(controller.repairAgentID == 42, @"repair targets the selected existing agent");
  controller.testAgent.status = TLAgentStatusInitializing;
  [controller updateAgentControlStates];
  Check(!start.enabled && !stop.enabled, @"setup disables duplicate install and stop actions");
}

@interface TLHistorySelectionProbe : NSObject <TLHistoryPanelControllerDelegate>
@property NSInteger selected;
@property NSInteger deleted;
@property NSInteger deletedVisit;
@property NSURL *openedURL;
@end
@implementation TLHistorySelectionProbe
- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectBrowserURL:(NSURL *)URL { self.openedURL = URL; }
- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteBrowserVisitID:(NSInteger)visitID { self.deletedVisit = visitID; }
- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectChatID:(NSInteger)chatID { self.selected = chatID; }
- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteChatID:(NSInteger)chatID { self.deleted = chatID; }
@end

static void TestHermesHistorySearchAndLayout(void) {
  TLHistorySelectionProbe *probe = [[TLHistorySelectionProbe alloc] init];
  TLHistoryPanelController *controller = [[TLHistoryPanelController alloc] initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  controller.delegate = probe;
  TLChatSummary *first = [[TLChatSummary alloc] init];
  first.chatID = 10; first.title = @"Café research"; first.hermesSessionID = @"session-a"; first.updatedAt = @"2026-09-05 08:00:00";
  TLChatSummary *second = [[TLChatSummary alloc] init];
  second.chatID = 20; second.title = @"Browser project"; second.hermesSessionID = @"session-b"; second.updatedAt = first.updatedAt;
  controller.chats = @[first, second];
  controller.searchPreviews = @{@20: @"Investigate browser automation"};
  NSSearchField *search = [controller valueForKey:@"searchField"];
  NSTableView *table = [controller valueForKey:@"tableView"];
  NSTextField *status = [controller valueForKey:@"statusLabel"];
  [controller reloadData];
  Check(table.numberOfRows == 2, @"history lists all received Hermes sessions");
  search.stringValue = @"CAFE";
  [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:search];
  Check(table.numberOfRows == 1, @"history search ignores case and accents");
  search.stringValue = @"automation";
  [controller reloadData];
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  Check(probe.selected == 20, @"filtered selection opens its actual session");
  [table setValue:@0 forKey:@"contextMenuRow"];
  NSMenuItem *deleteItem = table.menu.itemArray.firstObject;
  [NSApp sendAction:deleteItem.action to:deleteItem.target from:deleteItem];
  Check(probe.deleted == 20, @"filtered deletion targets its actual session");
  search.stringValue = @"missing";
  [controller reloadData];
  Check(table.numberOfRows == 0 && [status.stringValue isEqualToString:@"No matching history"], @"search has an empty result state");
  controller.loading = YES;
  Check(table.enabled && [status.stringValue containsString:@"Loading"], @"loading chats leaves browsing accessible");
  controller.loading = NO;
  controller.statusMessage = @"Hermes unavailable";
  Check([status.stringValue isEqualToString:@"Hermes unavailable"], @"history exposes gateway errors");
  controller.statusMessage = @"";
  search.stringValue = @"";
  [controller reloadData];
  TLBrowserHistoryEntry *visit = [TLBrowserHistoryEntry new];
  visit.visitID = 10; visit.title = @"Café guide"; visit.URLString = @"https://example.com/caf%C3%A9";
  visit.visitedAt = @"2026-09-06 10:00:00";
  visit.faviconData = [NSData dataWithContentsOfFile:@"assets/browser-bookmarks/github.png"];
  controller.browsingHistory = @[visit];
  [controller reloadData];
  Check(table.numberOfRows == 3, @"All includes both chats and browsing visits");
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  Check([probe.openedURL.absoluteString isEqual:visit.URLString], @"newest browsing visit sorts before chats and opens its URL");
  [controller selectChatWithID:10];
  Check(table.selectedRow == 1, @"chat selection ignores colliding browser visit IDs");
  search.stringValue = @"CAFE";
  [controller reloadData];
  Check(table.numberOfRows == 2, @"shared search matches chat and browsing titles without case or accents");
  NSArray<TLThemedButton *> *filters = [controller valueForKey:@"filterButtons"];
  [filters[1] performClick:nil];
  Check(controller.filter == TLHistoryFilterChats && table.numberOfRows == 1, @"Chats filter retains the shared query");
  [filters[2] performClick:nil];
  Check(controller.filter == TLHistoryFilterBrowsing && table.numberOfRows == 1, @"Browsing filter retains the shared query");
  search.stringValue = @"EXAMPLE.COM";
  [controller reloadData];
  Check(table.numberOfRows == 1, @"browsing search matches URLs");
  controller.loading = YES;
  controller.statusMessage = @"Hermes unavailable";
  Check(status.hidden && table.enabled, @"Browsing hides chat loading/errors and stays interactive");
  probe.openedURL = nil;
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  Check(probe.openedURL != nil, @"browsing entries open while Hermes is loading");
  [table setValue:@0 forKey:@"contextMenuRow"];
  [table.menu update];
  Check([deleteItem.title isEqual:@"Delete Browsing Entry"], @"context action describes a browsing entry");
  [NSApp sendAction:deleteItem.action to:deleteItem.target from:deleteItem];
  Check(probe.deletedVisit == 10 && probe.deleted == 20, @"browsing deletion never targets a chat with the same ID");
  [filters[1] performClick:nil];
  search.stringValue = @"";
  [controller reloadData];
  probe.selected = 0;
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  Check(probe.selected == 0, @"chat actions remain blocked during a Hermes refresh");
  controller.loading = NO; controller.statusMessage = @"";
  [filters[0] performClick:nil];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 600)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSView *panel = controller.panelView;
  [window.contentView addSubview:panel];
  [NSLayoutConstraint activateConstraints:@[
    [panel.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [panel.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [panel.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [panel.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor],
  ]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@1200, @200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 600)];
      [window.contentView layoutSubtreeIfNeeded];
      Check(fabs(NSWidth(window.contentView.bounds) - width.doubleValue) < 1, @"history never constrains the window maximum width");
      NSView *column = panel.subviews.firstObject;
      Check(fabs(NSMidX(column.frame) - NSMidX(panel.bounds)) < 1, @"history column is horizontally centered");
      Check(NSWidth(column.frame) <= palette.messageInputMaxWidth + 1 && NSWidth(column.frame) <= width.doubleValue + 1,
            @"history column matches chat width and fits narrow windows");
      Check(NSWidth(search.frame) > 0 && NSMaxX([search convertRect:search.bounds toView:panel]) <= width.doubleValue,
            @"history search fits inside narrow windows");
      NSTableCellView *browserCell = [table viewAtColumn:0 row:0 makeIfNecessary:YES];
      TLTabIconView *browserIcon = (TLTabIconView *)browserCell.subviews.firstObject;
      Check(browserIcon.image != nil && browserIcon.palette == palette, @"history displays the persisted favicon in both themes");
      NSImageView *renderedIcon = [browserIcon valueForKey:@"systemIconView"];
      Check(!renderedIcon.hidden && !renderedIcon.contentTintColor && renderedIcon.image == browserIcon.image,
        @"favicon retains the site's original image colors");
      NSTableCellView *chatCell = [table viewAtColumn:0 row:1 makeIfNecessary:YES];
      TLTabIconView *chatIcon = (TLTabIconView *)chatCell.subviews.firstObject;
      Check(chatIcon.image == nil && chatIcon.icon.length, @"chat rows retain their conversation icons");
      for (TLThemedButton *button in filters) {
        NSRect frame = [button convertRect:button.bounds toView:panel];
        Check(NSMinX(frame) >= 0 && NSMaxX(frame) <= width.doubleValue, @"all three filters fit within the minimum window width");
        CGFloat textWidth = [button.title sizeWithAttributes:@{NSFontAttributeName:button.font}].width;
        Check(NSWidth(button.bounds) >= textWidth + 8, @"filter labels fit without truncation");
      }
      NSBitmapImageRep *image = [panel bitmapImageRepForCachingDisplayInRect:panel.bounds];
      [panel cacheDisplayInRect:panel.bounds toBitmapImageRep:image];
      [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"build/history-%@-%@.png", theme, width] atomically:YES];
      for (TLThemedButton *button in filters) {
        for (NSString *state in @[@"normal", @"hover", @"pressed", @"disabled", @"focused"]) {
          button.enabled = ![state isEqual:@"disabled"];
          [button setValue:@([state isEqual:@"hover"]) forKey:@"hovered"];
          [button highlight:[state isEqual:@"pressed"]];
          [window makeFirstResponder:[state isEqual:@"focused"] ? button : nil];
          NSBitmapImageRep *bitmap = RenderThemedButton(button);
          CGFloat surface[3], unusedAlpha;
          RGBComponents(palette.tabBackground, surface, &unusedAlpha);
          CGFloat opacity = button.enabled ? 1 : palette.disabledOpacity;
          CompositeColor(button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface, opacity, surface);
          if ([state isEqual:@"hover"] || [state isEqual:@"pressed"]) CompositeColor(palette.chromeHoverSurface, 1, surface);
          Check(PixelMatches(bitmap, 5, NSHeight(button.bounds) / 2, surface), @"history filter renders the selected/unselected theme surface");
          CGFloat foreground[3] = {surface[0], surface[1], surface[2]};
          CompositeColor(button.primary ? palette.primaryActionText : palette.secondaryActionText, opacity, foreground);
          NSUInteger ink = 0;
          for (NSInteger y = 4; y < bitmap.pixelsHigh - 4; y++) for (NSInteger x = 8; x < bitmap.pixelsWide - 8; x++)
            if (PixelMatches(bitmap, x, y, foreground)) ink++;
          Check(ink > 3, @"history filter renders paired label colors across themes and interaction states");
        }
        button.enabled = YES; [button highlight:NO]; [button setValue:@NO forKey:@"hovered"];
      }
      [window makeFirstResponder:nil];
    }
  }
  [window close];
}

@interface TLProviderSetupWindowController (Testing)
- (void)showProviders;
- (void)next:(id)sender;
- (void)back:(id)sender;
- (void)cancel:(id)sender;
- (void)login:(id)sender;
@end
@interface TLProviderServiceMock : NSObject
@property NSDictionary *params;
@property NSInteger agentID;
@property (copy) void (^pending)(NSDictionary *, NSError *);
@end
@implementation TLProviderServiceMock
- (void)hermesProvidersForAgentID:(NSInteger)agentID parameters:(NSDictionary *)params completion:(void (^)(NSDictionary *, NSError *))completion {
  self.agentID = agentID; self.params = params; self.pending = completion;
}
@end
static void ProviderTick(void) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
static void ProviderSnapshot(TLProviderSetupWindowController *controller, NSString *name) {
  [controller.window.contentView layoutSubtreeIfNeeded];
  NSView *root = controller.window.contentView;
  NSBitmapImageRep *bitmap = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
  [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:[NSString stringWithFormat:@"build/provider-%@.png", name] atomically:YES];
  NSView *next = [controller valueForKey:@"nextButton"];
  NSRect frame = [next convertRect:next.bounds toView:root];
  Check(NSMinX(frame) >= 0 && NSMaxX(frame) <= NSWidth(root.bounds), @"provider wizard actions remain in the window");
}
static void TestProviderSetupStages(void) {
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLProviderServiceMock *service = [TLProviderServiceMock new];
    TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 42; agent.name = @"Atlas";
    TLProviderSetupWindowController *controller = [[TLProviderSetupWindowController alloc]
      initWithAgent:agent orchestrator:(id)service palette:[TLThemePalette paletteForPreference:theme.integerValue]];
    [controller showProviders];
    Check(service.agentID == 42 && [service.params[@"action"] isEqual:@"list"], @"provider discovery stays pinned to the new agent");
    service.pending(@{@"providers":@[
      @{@"slug":@"openrouter", @"name":@"OpenRouter", @"auth_type":@"api_key", @"api_key_env_vars":@[@"OPENROUTER_API_KEY"]},
      @{@"slug":@"openai-codex", @"name":@"OpenAI login", @"auth_type":@"oauth_external"}]}, nil);
    ProviderTick(); ProviderSnapshot(controller, [NSString stringWithFormat:@"%@-1",theme]);
    [controller next:nil];
    Check([[controller valueForKey:@"stage"] integerValue] == 1, @"provider selection advances to credentials");
    NSDictionary *fields = [controller valueForKey:@"fields"];
    NSSecureTextField *key = fields[@"OPENROUTER_API_KEY"];
    Check([key isKindOfClass:NSSecureTextField.class], @"provider API keys use a secure field");
    key.stringValue = @"test-key";
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette];
    Check([key.stringValue isEqual:@"test-key"] && [key.textColor isEqual:palette.controlText], @"theme updates retain credential draft and use semantic text color");
    ProviderSnapshot(controller, [NSString stringWithFormat:@"%@-2",theme]);
    [controller next:nil];
    Check([service.params[@"action"] isEqual:@"configure"] && [service.params[@"slug"] isEqual:@"openrouter"], @"credentials sent only to selected provider");
    service.pending(@{@"ok":@YES}, nil); ProviderTick();
    Check(key.stringValue.length == 0 && [service.params[@"action"] isEqual:@"models"], @"saved credentials are cleared before model discovery");
    service.pending(@{@"providers":@[@{@"slug":@"openrouter", @"models":@[@"example/model"]}]},nil); ProviderTick();
    ProviderSnapshot(controller, [NSString stringWithFormat:@"%@-3",theme]);
    NSTextField *manual = [controller valueForKey:@"manualModel"]; manual.stringValue = @"custom-model";
    [controller next:nil];
    Check([service.params[@"selection"] isEqual:@"openrouter::custom-model"], @"model selection retains provider identity");
    service.pending(@{@"confirm_required":@YES, @"confirm_message":@"Review cost"},nil); ProviderTick();
    manual.stringValue = @"different-model";
    [controller next:nil];
    Check(![service.params[@"confirmed"] boolValue], @"confirmation for one model cannot approve another");
    service.pending(nil,[NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Retry"}]); ProviderTick();
    [controller back:nil]; [controller back:nil];
    void (^late)(NSDictionary *, NSError *) = service.pending;
    [controller cancel:nil]; late(@{@"providers":@[@{@"slug":@"stale", @"name":@"Stale"}]},nil); ProviderTick();
    Check([[[controller valueForKey:@"providerPicker"] itemTitles] count] == 0, @"late discovery cannot repopulate a dismissed wizard");
    [controller.window close];
  }
  TLProviderServiceMock *service = [TLProviderServiceMock new];
  TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 42; agent.name = @"Atlas";
  TLProviderSetupWindowController *controller = [[TLProviderSetupWindowController alloc] initWithAgent:agent orchestrator:(id)service palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  [controller showProviders];
  service.pending(@{@"providers":@[@{@"slug":@"openai-codex",@"name":@"OpenAI login",@"auth_type":@"oauth_external"}]},nil); ProviderTick();
  [controller next:nil]; [controller login:nil];
  service.pending(@{@"session_id":@"login-session",@"verification_url":@"https://example.com/login",@"user_code":@"ABC-123",@"poll_interval":@30},nil); ProviderTick();
  Check(![[controller valueForKey:@"nextButton"] isEnabled], @"model stage waits for account sign-in");
  [controller cancel:nil];
  Check([service.params[@"action"] isEqual:@"login.cancel"] && [service.params[@"session_id"] isEqual:@"login-session"] && service.agentID == 42, @"closing cancels this agent's pending login");
  [controller.window close];
}

@interface TalariaWindowController (LinkInsertionTests)
- (void)handleLinkURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)flags;
- (void)handleBrowserTabRequestURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)flags;
- (void)handleContextLinkURL:(NSURL *)URL destination:(TLBrowserLinkDestination)destination sourceIdentity:(NSString *)identity;
@end

// Keep real link routing and state mutations while omitting browser processes.
@interface TLLinkInsertionController : TalariaWindowController
@end
@implementation TLLinkInsertionController
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab {}
- (void)updateWorkspaceMode {}
- (void)reloadWorkspaceTabs {}
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {}
@end

static void TestLinkTabInsertion(void) {
  for (NSUInteger route = 0; route < 3; route++) {
    for (NSUInteger index = 0; index < 3; index++) {
      TLLinkInsertionController *controller = [[TLLinkInsertionController alloc] initWithWindow:nil];
      TLAppStateManager *state = [TLAppStateManager new];
      [controller setValue:state forKey:@"appStateManager"];
      [controller setValue:@100 forKey:@"nextBrowserTabID"];
      for (NSUInteger tabIndex = 0; tabIndex < 3; tabIndex++) {
        TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:route == 0 ? TLWorkspaceTabKindChat : TLWorkspaceTabKindBrowser
          tabID:tabIndex + 1 title:@"Existing" toolTip:nil URL:nil closeable:YES];
        [state addWorkspaceTab:tab activate:tabIndex == index];
      }
      TLWorkspaceTab *source = state.snapshot.workspaceTabs[index];
      NSURL *URL = [NSURL URLWithString:@"https://example.com/linked"];
      if (route == 0) [controller handleLinkURL:URL modifierFlags:0];
      else if (route == 1) [controller handleBrowserTabRequestURL:URL modifierFlags:NSEventModifierFlagCommand];
      else [controller handleContextLinkURL:URL destination:TLBrowserLinkNewTab sourceIdentity:TLWorkspaceTabIdentity(source)];
      TLWorkspaceTab *opened = state.snapshot.workspaceTabs[index + 1];
      Check(state.snapshot.workspaceTabs.count == 4 && opened.tabID == 100 && [opened.URL isEqual:URL],
        @"chat links, browser new-tab requests, and context-menu links open immediately right of the current tab");
      Check(state.snapshot.activeTabKind == TLWorkspaceTabKindBrowser && state.snapshot.activeTabID == opened.tabID,
        @"the adjacent linked tab becomes active");
      [controller handleBrowserTabRequestURL:URL modifierFlags:0];
      Check(state.snapshot.workspaceTabs[index + 2].tabID == 101,
        @"a subsequent link opens right of the newly current tab");
    }
  }
}

static void CaptureThinkingPreview(NSView *view, NSString *name) {
  if (!getenv("TL_THINKING_PREVIEW")) return;
  [view layoutSubtreeIfNeeded];
  NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
  [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:[@"/tmp/" stringByAppendingString:name] atomically:YES];
}

static void TestLiveThinkingPresentation(void) {
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    TLChatTabController *chat = [[TLChatTabController alloc] initWithPalette:palette];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 600)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSView *workspace = [chat buildChatWorkspace];
    chat.chatWorkspace = workspace;
    window.contentView = workspace;
    chat.messageInputWidthConstraint.constant = 520;
    [chat applyPalette:palette];
    [window orderFront:nil];
    chat.agentAvatar = @"🦊";
    __block BOOL running = YES;
    chat.streamingProvider = ^BOOL{ return running; };
    TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleAssistant content:@"" thinking:@"(face) musing..."];
    chat.messages = [NSMutableArray arrayWithObjects:[TLChatMessage messageWithRole:TLRoleUser content:@"Find the latest news" thinking:nil], message, nil];
    [chat renderMessagesScrollingToBottom:NO];
    [workspace layoutSubtreeIfNeeded];
    NSView *thinking = [chat valueForKey:@"thinkingRow"];
    TLThinkingBubbleView *bubble = [chat valueForKey:@"thinkingBubble"];
    TLToolStatusPill *pill = [chat valueForKey:@"toolStatusPill"];
    Check(thinking.superview && pill.hidden, @"waiting shows only the thinking bubble");
    Check(![chat.messageMarkdownViews objectForKey:message], @"Hermes status and reasoning text never become visible Markdown");
    NSArray<CALayer *> *dots = [bubble valueForKey:@"dots"];
    Check(dots.count == 3 && NSWidth(bubble.frame) > 0, @"thinking bubble contains three visible dots");
    Check(CGColorEqualToColor(dots.firstObject.backgroundColor, palette.thinkingText.CGColor), @"dots use current theme text color");
    Check(CGRectGetWidth(dots.firstObject.frame) == palette.space3, @"thinking dots use the compact size");
    Check(bubble.cornerRadius > 0 && [bubble.fillColor isEqual:palette.secondaryActionSurface], @"thinking has a visible rounded bubble surface");
    Check([bubble isKindOfClass:TLMessageBubbleView.class] && !bubble.drawsOutgoingTail, @"thinking uses the shared incoming agent message bubble");
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
      Check([dots.firstObject animationForKey:@"thinking"] != nil, @"dots animate in a window");
    CaptureThinkingPreview(workspace, [NSString stringWithFormat:@"thinking-%@.png", theme]);
    [message applyToolActivity:@{@"id":@"web", @"name":@"web_search", @"state":@"running"}];
    [chat markMessageDirty:message];
    [chat scheduleStreamingMessageRender];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    [workspace layoutSubtreeIfNeeded];
    Check(thinking.superview && !pill.hidden, @"thinking stays visible alongside the tool pill");
    NSTimer *shimmer = [pill valueForKey:@"shimmerTimer"];
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
      Check(shimmer.valid, @"active tool text shimmers");
    CAGradientLayer *mask = [pill valueForKey:@"shimmerMask"];
    NSArray *locations = mask.locations;
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
      Check(![mask.locations isEqual:locations], @"shimmer highlight moves across the text");
    Check([pill.accessibilityLabel isEqual:@"Browsing web"], @"web tool gets readable activity text");
    Check([[[pill valueForKey:@"avatarLabel"] stringValue] isEqual:@"🦊"], @"pill uses this chat's agent avatar");
    NSRect pillFrame = [pill convertRect:pill.bounds toView:workspace];
    NSRect inputFrame = [chat.messageInput convertRect:chat.messageInput.bounds toView:workspace];
    Check(fabs(NSMidX(pillFrame) - NSMidX(inputFrame)) < 1 && NSMinY(pillFrame) >= NSMaxY(inputFrame), @"pill is centered above the composer");
    Check(CGColorEqualToColor(pill.layer.backgroundColor, palette.secondaryActionSurface.CGColor), @"pill uses theme surface color");
    CaptureThinkingPreview(workspace, [NSString stringWithFormat:@"tool-pill-%@.png", theme]);
    [window setContentSize:NSMakeSize(200, 600)];
    chat.messageInputWidthConstraint.constant = 160;
    [workspace layoutSubtreeIfNeeded];
    Check(NSWidth(pill.frame) <= NSWidth(chat.messageInput.frame) + 1, @"pill fits the composer at minimum window width");
    [window setContentSize:NSMakeSize(600, 600)];
    chat.messageInputWidthConstraint.constant = 520;
    [message applyToolActivity:@{@"id":@"web", @"name":@"web_search", @"state":@"completed"}];
    [chat renderMessagesScrollingToBottom:NO];
    Check(thinking.superview && pill.hidden, @"thinking resumes after tool completion");
    Check(!shimmer.valid, @"hidden tool pills stop shimmering");
    message.content = @"Here are the results.";
    message.thinkingActive = NO;
    [chat renderMessagesScrollingToBottom:NO];
    Check(!thinking.superview && pill.hidden, @"answer streaming clears the activity indicators");
    message.thinkingActive = YES;
    [chat renderMessagesScrollingToBottom:NO];
    Check(thinking.superview != nil, @"later reasoning can show dots after response text");
    message.approvalRequest = @{@"request_id":@"approval", @"command":@"test"};
    [chat renderMessagesScrollingToBottom:NO];
    Check(!thinking.superview && pill.hidden, @"approval hides passive progress indicators");
    message.approvalRequest = nil;
    running = NO;
    [chat renderMessagesScrollingToBottom:NO];
    Check(!thinking.superview && pill.hidden, @"completion or cancellation clears progress even with stale thinking state");
    message.content = @"[{\"qid\":\"q0\",\"question\":\"Which dates?\",\"choices\":null,\"multi_select\":false}] Reply with your answer.";
    [chat renderMessagesScrollingToBottom:NO];
    NSView *questionView = [chat.messageMarkdownViews objectForKey:message];
    Check([[questionView valueForKey:@"text"] isEqual:@"Which dates?\n\nReply with your answer."], @"old question envelopes render readable text without protocol fields");
    [chat close];
    [window close];
  }
  Check([[TLToolStatusPill labelForToolName:@"custom_data_tool"] isEqual:@"Using custom data tool"], @"unknown tools retain a readable name");
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    if (getenv("TL_TEST_DEFAULT_BROWSER_ONLY")) {
      TestThemedButtonRenderedColors();
      TestDefaultBrowserSettings();
      NSLog(@"Default browser settings tests passed");
      return 0;
    }
    if (getenv("TL_TEST_BROWSER_EXTENDED_ONLY")) {
      TestBrowserOwnsCallbacksAndSession();
      TestBrowserExtendedLayout();
      TestUnifiedWorkspaceOutline();
      NSLog(@"Browser extended layout tests passed");
      return 0;
    }
    TestLiveThinkingPresentation();
    if (getenv("TL_TEST_THINKING_ONLY")) { NSLog(@"Thinking presentation tests passed"); return 0; }
    TestDefaultBrowserSettings();
    TestProviderSetupStages();
    TestLinkTabInsertion();
    if (getenv("TL_TEST_BROWSER_IMPORT_ONLY")) {
      TestThemedButtonRenderedColors();
      TestBrowserImportSettings();
      NSLog(@"Browser import UI tests passed");
      return 0;
    }
    TestQueuedFollowUps();
    TestSendQueuedPromptNow();
    TestPromptQueueLayout();
    TestSuggestionsWithQueuedPrompts();
    if (getenv("TL_QUEUE_TESTS_ONLY")) {
      TestThemedButtonRenderedColors();
      TestConcurrentChatStreams();
      TestStreamingComposerStopButton();
      NSLog(@"Queued follow-up tests passed");
      return 0;
    }
    TestItemHoverRenderedColors();
    TestHermesHistorySearchAndLayout();
    TestNativeEmojiInput();
    TestFolderAccessTable();
    TestAgentCreationForm();
    TestAgentFolderEditing();
    TestAgentSettingsForm();
    TestAgentSkillSettings();
    TestSkillsInSettingsWorkspace();
    TestPluginsInSettingsWorkspace();
    TestRealSidebarAgents();
    TestSuggestionTypingAndVirtualization();
    TestRunningAgentRepairAction();
    TestWarmupAfterSettingsAndManualStart();
    TestThemedButtonRenderedColors();
    TestApprovalCard();
    TestApprovalRouting();
    TestDebugResetLayout();
    TestTerminalRequiresRunningVM();
    TestSettingsThemeAndLateCatalogue();
    TestBrowserPreferencePersistenceAndValidation();
    TestBrowserImportSettings();
    TestSettingsNavigationCredentialsAndResponsiveLayout();
    TestNativeGlobalShortcutRegistration();
    TestComposerModelButtonLayout();
    TestComposerModelDialog();
    TestBrowserOwnsCallbacksAndSession();
    TestBrowserExtendedLayout();
    TestDragCommitRendersBeforeDeferredReload();
    TestStreamingChatTitlesPersist();
    TestConcurrentChatStreams();
    TestAttachmentSendPreparation();
    TestStreamingComposerStopButton();
    TestNavigationWhileSendingPreservesTurn();
    TestStreamingKeepsMessageViewsAttached();
    TestCompactButtonHitAreaAndMovingHover();
    TestUnifiedWorkspaceOutline();
    NSLog(@"FeatureControllerTests passed");
  }
  return 0;
}
