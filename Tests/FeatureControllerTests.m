#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "TLBrowserTabController.h"
#import "TLNotesTabController.h"
#import "TLSettingsTabController.h"
#import "AgentOrchestrator.h"
#import "ModelPickerView.h"
#import "UIComponents.h"
#import "TalariaWindowController.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLButton.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
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
- (void)installAppStateBindings;
- (void)renderWorkspaceTabs;
- (void)updateWorkspaceMode;
- (void)updateControlStates;
- (void)workspaceTabsController:(nullable TLWorkspaceTabsController *)controller
                       moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index;
@end

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

static void TestNotesThemePreservesEditing(void) {
  TLNotesTabController *controller = [[TLNotesTabController alloc]
    initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = HostController(controller);
  [controller updateNotesMessageInputWidth];
  NSView *originalView = controller.view;
  NSTextView *editor = controller.notesPromptTextView;
  editor.string = @"An unfinished notes prompt";
  [window makeFirstResponder:editor];
  editor.selectedRange = NSMakeRange(3, 6);
  NSScrollView *article = [controller valueForKey:@"notesArticleView"];
  [article.contentView scrollToPoint:NSMakePoint(0, 40)];
  NSPoint origin = article.contentView.bounds.origin;
  NSRange selection = editor.selectedRange;
  TLThemePalette *dark = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  [controller applyPalette:dark];
  Check(controller.view == originalView && controller.notesPromptTextView == editor, @"notes theme keeps the same view and editor");
  Check([editor.string isEqualToString:@"An unfinished notes prompt"], @"notes draft survives theme change");
  Check(NSEqualRanges(editor.selectedRange, selection) && window.firstResponder == editor, @"notes focus and selection survive theme change");
  Check(NSEqualPoints(article.contentView.bounds.origin, origin), @"notes scroll position survives theme change");
  Check([((TLTokenView *)controller.view).fillColor isEqual:dark.tabBackground], @"notes root reapplies semantic theme");
  Check([editor.textColor isEqual:dark.controlText], @"notes editor reapplies semantic theme");
  __block NSString *sentPrompt = nil;
  controller.sendPromptHandler = ^(NSString *prompt) { sentPrompt = prompt; };
  [NSApp sendAction:controller.notesMessageInput.sendButton.action to:controller.notesMessageInput.sendButton.target from:editor];
  Check([sentPrompt isEqualToString:@"An unfinished notes prompt"] && editor.string.length == 0, @"notes controller owns prompt submission and clearing");
  [controller close];
  Check(editor.delegate == nil && controller.sendPromptHandler == nil, @"notes closing clears callbacks");
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

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestNotesThemePreservesEditing();
    TestSettingsThemeAndLateCatalogue();
    TestBrowserOwnsCallbacksAndSession();
    TestDragCommitRendersBeforeDeferredReload();
    TestCompactButtonHitAreaAndMovingHover();
    NSLog(@"FeatureControllerTests passed");
  }
  return 0;
}
