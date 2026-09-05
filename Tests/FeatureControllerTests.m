#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLMessageInput.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "TLBrowserTabController.h"
#import "TLSettingsTabController.h"
#import "AgentOrchestrator.h"
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
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting;
- (void)workspaceTabsController:(nullable TLWorkspaceTabsController *)controller
                       moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index;
@end

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

static void TestNavigationWhileSendingPreservesTurn(void) {
  TLSendingNavigationController *controller = [[TLSendingNavigationController alloc] initWithWindow:nil];
  NSMutableArray *originalMessages = [NSMutableArray arrayWithObject:@"in-flight response"];
  [controller setValue:originalMessages forKey:@"messages"];
  [controller setValue:originalMessages forKey:@"sendingMessages"];
  [controller setValue:@YES forKey:@"isSending"];
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
  Check([controller valueForKey:@"sendingMessages"] == originalMessages,
        @"running turn keeps its own buffer");
  for (NSString *key in headerKeys) {
    Check([[controller valueForKey:key] isEnabled], @"header remains enabled while sending");
  }
  prompt.string = @"next draft";
  [controller updateControlStates];
  Check(prompt.editable && !send.enabled, @"draft editing stays available but concurrent sends remain blocked");
  Check([[controller valueForKey:@"isSending"] boolValue], @"navigation does not cancel the turn");
  [controller setValue:@42 forKey:@"sendingChatID"];
  prompt.string = @"/stop";
  [controller updateControlStates];
  Check(!send.enabled, @"slash controls stay disabled in a different conversation during a turn");
  [controller sendMessage:nil allowAutomaticRouting:YES];
  Check([prompt.string isEqualToString:@"/stop"], @"keyboard submission cannot route slash control to another chat");
  TLChatRecord *origin = [[TLChatRecord alloc] init];
  origin.chatID = 42;
  [controller setValue:origin forKey:@"activeChat"];
  [controller updateControlStates];
  Check(send.enabled, @"returning to the running conversation enables slash controls");
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
  NSMutableArray<TLAgentModel *> *models = [NSMutableArray array];
  for (NSUInteger index = 0; index < 40; index += 1) {
    TLAgentModel *model = [[TLAgentModel alloc] init];
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
- (void)updateControlStates { self.layoutCount++; }
- (void)updateMessageScrollInsets { self.layoutCount++; }
- (BOOL)isChatWorkspaceActive { return YES; }
- (void)refreshHermesCommandsIfNeeded { self.refreshCount++; }
@end

static void DrainSuggestionTimer(void) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.06];
  while (deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:deadline];
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
  Check([pane isKindOfClass:TLTokenView.class] && ![pane isKindOfClass:TLGlassPaneView.class], @"suggestions use a plain surface without glass treatment");
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

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestNativeEmojiInput();
    TestFolderAccessTable();
    TestAgentCreationForm();
    TestAgentFolderEditing();
    TestAgentSettingsForm();
    TestRealSidebarAgents();
    TestSuggestionTypingAndVirtualization();
    TestNotesThemePreservesEditing();
    TestSettingsThemeAndLateCatalogue();
    TestBrowserOwnsCallbacksAndSession();
    TestDragCommitRendersBeforeDeferredReload();
    TestNavigationWhileSendingPreservesTurn();
    TestCompactButtonHitAreaAndMovingHover();
    TestUnifiedWorkspaceOutline();
    NSLog(@"FeatureControllerTests passed");
  }
  return 0;
}
