#import <AppKit/AppKit.h>
#import "TLQuickInputWindowController.h"
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "NotchOverlayController.h"
#import "TLChatPresentation.h"
#import "design_system/TLInputSuggestionListView.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]]; }
static void SetText(TLQuickInputWindowController *controller, NSString *text) {
  controller.messageInput.textView.string = text;
  controller.messageInput.textChangeHandler();
  Drain();
}
static void Submit(TLQuickInputWindowController *controller) {
  [controller textView:controller.messageInput.textView doCommandBySelector:@selector(insertNewline:)];
}
static void Escape(TLQuickInputWindowController *controller) {
  [controller.messageInput.textView doCommandBySelector:@selector(cancelOperation:)];
}

@interface TalariaWindowController (QuickInputTesting)
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)openFromNotchOverlay:(id)sender;
- (void)handleFileURLsDroppedOnNotch:(NSArray<NSURL *> *)files;
@end

// Keep the real workspace and notch handoff, stopping only at network/VM boundaries.
@interface TLQuickInputTestOwner : TalariaWindowController
@property (nonatomic) NSUInteger sendCount;
@property (nonatomic, copy) NSString *submittedText;
@property (nonatomic, copy) NSArray<NSURL *> *submittedFiles;
@property (nonatomic, strong) NSURL *browserURL;
@end
@implementation TLQuickInputTestOwner
- (void)refreshHermesHistory {}
- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting {
  self.sendCount++;
  TLChatPresentation *presentation = [self valueForKey:@"chatPresentation"];
  self.submittedText = presentation.promptTextView.string;
  self.submittedFiles = presentation.messageInput.attachmentURLs;
}
- (void)openBrowserTabWithURL:(NSURL *)URL {
  self.browserURL = URL;
  TLAppStateManager *state = [self valueForKey:@"appStateManager"];
  [state addWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:1 title:@"Web"
    toolTip:URL.absoluteString URL:URL closeable:YES] activate:YES];
}
@end

static void TestPanel(void) {
  TLQuickInputWindowController *controller = [[TLQuickInputWindowController alloc]
    initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  __block NSUInteger submissions = 0;
  __block NSString *submittedText;
  __block BOOL automaticRouting;
  __weak TLQuickInputWindowController *weakController = controller;
  controller.submissionHandler = ^(NSString *text, NSArray<NSURL *> *files, BOOL allowRouting) {
    Check(!weakController.window.visible, @"panel closes before handing off the request");
    submissions++; submittedText = text; automaticRouting = allowRouting;
  };
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette];
    NSScreen *screen = NSScreen.mainScreen;
    NSRect notch = NSMakeRect(NSMidX(screen.visibleFrame) - 160, NSMaxY(screen.visibleFrame) - 40, 200, 40);
    [controller presentBelowRect:notch onScreen:screen];
    Drain();
    Check(fabs(NSMaxY(controller.window.frame) - (NSMinY(notch) - palette.space5)) < 1 &&
      fabs(NSMidX(controller.window.frame) - NSMidX(notch)) < 1,
      @"popup is centered immediately below the clicked notch");
    Check(controller.window.canBecomeKeyWindow && !controller.window.canBecomeMainWindow, @"popup accepts keyboard without becoming the main window");
    Check((controller.window.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0, @"opening the popup cannot activate other app windows");
    Check(controller.window.firstResponder == controller.messageInput.textView, @"typing focuses the composer immediately");
    SetText(controller, @"   \n"); Submit(controller);
    Check(submissions == 0 && controller.window.visible && !controller.messageInput.sendButton.enabled, @"blank submission stays in popup");
    SetText(controller, @"A draft to keep");
    CGFloat top = NSMaxY(controller.window.frame);
    SetText(controller, @"A multi-line draft\nSecond line\nThird line\nFourth line");
    Check(fabs(NSMaxY(controller.window.frame) - top) < 1, @"typing expands down without moving the top edge");
    Check(NSHeight(controller.window.frame) + 1 >= NSHeight(controller.messageInput.frame),
      [NSString stringWithFormat:@"expanded composer fits the panel: window %@, input %@", NSStringFromRect(controller.window.frame), NSStringFromRect(controller.messageInput.frame)]);
    NSBitmapImageRep *bitmap = [controller.messageInput bitmapImageRepForCachingDisplayInRect:controller.messageInput.bounds];
    [controller.messageInput cacheDisplayInRect:controller.messageInput.bounds toBitmapImageRep:bitmap];
    Check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, @"real shared composer renders in each theme");
    NSString *path = theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-quick-input-light.png" : @"/tmp/talaria-quick-input-dark.png";
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    Check(controller.messageInput.palette == palette && [controller.messageInput.textView.textColor isEqual:palette.controlText], @"theme reaches existing popup text and controls");
    Escape(controller);
    Check(!controller.window.visible && submissions == 0, @"Escape closes without submitting");
    [controller presentOnScreen:NSScreen.mainScreen];
    Check([controller.messageInput.textView.string hasPrefix:@"A multi-line"], @"dismissed draft is available on reopening");
    SetText(controller, @"example.com");
    TLInputSuggestionListView *list = [controller valueForKey:@"suggestionList"];
    Check(list.suggestions.count == 2, @"URL suggestions match the app's browser/message choices");
    NSView *suggestions = [controller valueForKey:@"suggestionPanel"];
    Check(NSMaxY(suggestions.frame) < NSMinY(controller.messageInput.frame), @"suggestions sit below the input without overlap");
    NSBitmapImageRep *full = [controller.window.contentView bitmapImageRepForCachingDisplayInRect:controller.window.contentView.bounds];
    [controller.window.contentView cacheDisplayInRect:controller.window.contentView.bounds toBitmapImageRep:full];
    [[full representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:
      theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-quick-suggestions-light.png" : @"/tmp/talaria-quick-suggestions-dark.png" atomically:YES];
    Escape(controller);
    Check(!controller.window.visible, @"Escape dismisses the whole popup even with suggestions visible");
  }
  [controller presentOnScreen:NSScreen.mainScreen];
  SetText(controller, @"  Start a new request  ");
  Submit(controller); Submit(controller);
  Check(submissions == 1 && [submittedText isEqual:@"Start a new request"], @"Return submits once and trims whitespace");
  [controller presentOnScreen:NSScreen.mainScreen];
  Check(controller.messageInput.textView.string.length == 0, @"submitted draft is cleared");
  SetText(controller, @"example.com");
  TLInputSuggestionListView *list = [controller valueForKey:@"suggestionList"];
  list.selectedIndex = 1;
  TLGlassButton *send = controller.messageInput.sendButton;
  [NSApp sendAction:send.action to:send.target from:send];
  Check(submissions == 2 && !automaticRouting, @"Send message suggestion bypasses URL routing");
  [controller presentOnScreen:NSScreen.mainScreen];
  controller.commands = @[@{@"kind":@"hermes", @"command":@"/help", @"title":@"Help", @"icon":@"terminal", @"description":@"Help"}];
  SetText(controller, @"/he");
  [controller textView:controller.messageInput.textView doCommandBySelector:@selector(insertTab:)];
  Check([controller.messageInput.textView.string isEqual:@"/help "] && submissions == 2, @"Tab completes discovered commands without opening workspace");
  Submit(controller);
  Check(submissions == 3 && [submittedText isEqual:@"/help"], @"completed command submits normally");
  [controller presentOnScreen:NSScreen.mainScreen];
  SetText(controller, @"line one");
  [controller.messageInput.textView setSelectedRange:NSMakeRange(8, 0)];
  NSEvent *shiftReturn = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift
    timestamp:0 windowNumber:controller.window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
  [controller.messageInput.textView keyDown:shiftReturn];
  Check([controller.messageInput.textView.string containsString:@"\n"] && submissions == 3, @"Shift Return inserts a newline");
  [controller.window makeFirstResponder:controller.messageInput.settingsButton];
  [controller.window cancelOperation:nil];
  Check(!controller.window.visible, @"Escape also works when a composer button has focus");
  [controller presentOnScreen:NSScreen.mainScreen];
  NSPanel *sheet = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,300,180)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  __block NSModalResponse response = NSModalResponseOK;
  [controller.window beginSheet:sheet completionHandler:^(NSModalResponse result) { response = result; }];
  [controller dismiss]; Drain();
  Check(!sheet.visible && !controller.window.attachedSheet && response == NSModalResponseCancel,
    @"dismissal cancels attached dialogs so they cannot strand the popup");
  [controller presentOnScreen:NSScreen.mainScreen];
  Check(controller.window.visible, @"popup reopens after dismissing an attached dialog");
  [controller dismiss];
  controller.submissionHandler = nil;
}

static void TestWorkspaceHandoff(void) {
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,700)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
    backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLQuickInputTestOwner *owner = [[TLQuickInputTestOwner alloc] initWithWindow:window];
  TLAppStateManager *state = [TLAppStateManager new];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  TLAppSettings *settings = TLAppSettings.defaultSettings;
  [owner setValue:settings forKey:@"settings"];
  [owner setValue:[TLThemePalette paletteForPreference:settings.theme] forKey:@"palette"];
  [owner setValue:[NSMutableArray array] forKey:@"agents"];
  [owner setValue:[NSMutableArray array] forKey:@"chats"];
  [owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [owner buildInterface]; [owner installAppStateBindings];
  TLNotchOverlayController *notch = [[TLNotchOverlayController alloc] initWithPalette:[owner valueForKey:@"palette"]
    target:owner action:@selector(openFromNotchOverlay:)];
  [owner setValue:notch forKey:@"notchOverlayController"];
  [notch startTracking];
  [owner startNewChatWithModel:@"existing-model" focus:NO];
  TLChatPresentation *existing = [owner valueForKey:@"chatPresentation"];
  existing.promptTextView.string = @"Existing unsent draft";
  NSURL *file = [NSURL fileURLWithPath:@"/tmp/quick-input-attachment.txt"];
  existing.messageInput.attachmentURLs = @[file];
  [window orderOut:nil];
  [owner openFromNotchOverlay:nil]; Drain();
  TLQuickInputWindowController *quick = [owner valueForKey:@"quickInputController"];
  Check([notch valueForKey:@"trackingTimer"] == nil && NSIsEmptyRect(notch.presentationFrame),
    @"opening quick input hides the notch and stops hover tracking");
  Check(!window.visible && quick.window.visible && state.snapshot.workspaceTabs.count == 1, @"notch opens only the popup and creates no tab");
  SetText(quick, @"New request"); Escape(quick);
  Check([notch valueForKey:@"trackingTimer"] != nil, @"Escape restores normal notch tracking");
  Check(!window.visible && state.snapshot.workspaceTabs.count == 1 && owner.sendCount == 0, @"Escape leaves the main window hidden and workspace untouched");
  [owner openFromNotchOverlay:nil];
  quick.model = @"chosen-large"; quick.supportingModel = @"chosen-small";
  Submit(quick); Drain();
  Check([notch valueForKey:@"trackingTimer"] != nil, @"submission restores normal notch tracking");
  Check(window.visible && !quick.window.visible && state.snapshot.workspaceTabs.count == 2 && owner.sendCount == 1, @"submission opens the main window and a new chat");
  TLChatPresentation *fresh = [owner valueForKey:@"chatPresentation"];
  Check(fresh != existing && [owner.submittedText isEqual:@"New request"], @"handoff sends the entered text in a separate chat");
  Check([fresh.chat.model isEqual:@"chosen-large"] && [fresh.chat.supportingModel isEqual:@"chosen-small"], @"model selection follows the new chat");
  Check([existing.promptTextView.string isEqual:@"Existing unsent draft"] && existing.messageInput.attachmentURLs.count == 1,
    @"existing chat draft and attachments remain intact");
  [window orderOut:nil];
  [owner openFromNotchOverlay:nil]; SetText(quick, @"example.com"); Submit(quick); Drain();
  Check(window.visible && [owner.browserURL.absoluteString isEqual:@"https://example.com"] && state.snapshot.workspaceTabs.count == 3 && owner.sendCount == 1,
    @"URL submission opens one browser tab without an extra empty chat");
  [window orderOut:nil];
  [owner handleFileURLsDroppedOnNotch:@[file]];
  Check(!window.visible && quick.window.visible && quick.messageInput.attachmentURLs.count == 1, @"file drop stages attachments without opening main");
  SetText(quick, @"example.com"); Submit(quick); Drain();
  Check(owner.sendCount == 2 && [owner.submittedFiles isEqualToArray:@[file]], @"attachments force a new chat even when the text is a URL");
  [owner openFromNotchOverlay:nil];
  [quick.messageInput addAttachmentURLs:@[file]]; Submit(quick);
  Check(owner.sendCount == 3 && owner.submittedText.length == 0 && owner.submittedFiles.count == 1, @"file-only request reaches the existing attachment send pipeline");
  [owner openFromNotchOverlay:nil];
  [owner showWindow:nil];
  Check(!quick.window.visible, @"opening the main app elsewhere dismisses the popup");
  Check([notch valueForKey:@"trackingTimer"] != nil, @"opening the main app restores notch tracking");
  [notch stopTracking];
  [window orderOut:nil];
}

static void TestFocusAndDraftRestoration(void) {
  TLQuickInputWindowController *quick = [[TLQuickInputWindowController alloc]
    initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  __block BOOL reportedVisible = NO;
  quick.visibilityChangeHandler = ^(BOOL visible) { reportedVisible = visible; };
  NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,400,300)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  other.releasedWhenClosed = NO;
  NSArray<NSURL *> *files = @[[NSURL fileURLWithPath:@"/tmp/quick-draft-one.txt"],
                            [NSURL fileURLWithPath:@"/tmp/quick-draft-two.png"]];
  [quick presentOnScreen:NSScreen.mainScreen];
  SetText(quick, @"Keep this draft\nand its attachments");
  [quick.messageInput addAttachmentURLs:files];
  [other makeKeyAndOrderFront:nil]; Drain();
  Check(!quick.window.visible && !reportedVisible, [NSString stringWithFormat:
    @"moving focus hides quick input and releases notch suppression (visible %d, reported %d, key %d, other key %d)",
    quick.window.visible, reportedVisible, quick.window.keyWindow, other.keyWindow]);
  [quick presentOnScreen:NSScreen.mainScreen]; Drain();
  Check([quick.messageInput.textView.string isEqual:@"Keep this draft\nand its attachments"] &&
    [quick.messageInput.attachmentURLs isEqualToArray:files], @"focus dismissal restores exact text and attachments on reopening");
  Escape(quick);
  [quick presentOnScreen:NSScreen.mainScreen]; Drain();
  Check([quick.messageInput.attachmentURLs isEqualToArray:files] &&
    [quick.messageInput.textView.string hasPrefix:@"Keep this draft"], @"Escape preserves the same draft and attachments");

  NSOpenPanel *picker = NSOpenPanel.openPanel;
  __block BOOL pickerFinished = NO;
  [picker beginSheetModalForWindow:quick.window completionHandler:^(NSModalResponse result) { pickerFinished = YES; }];
  Drain();
  Check(quick.window.visible && reportedVisible && quick.window.attachedSheet == picker, @"opening the native file picker keeps the popup visible and notch suppressed");
  [picker cancel:nil];
  for (NSUInteger attempt = 0; attempt < 30 && !pickerFinished; attempt++) Drain();
  Drain();
  Check(pickerFinished && quick.window.visible && [quick.messageInput.attachmentURLs isEqualToArray:files],
    @"closing the file picker keeps the popup and its draft available");

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Draft options"];
  [menu addItemWithTitle:@"Keep editing" action:nil keyEquivalent:@""];
  __block BOOL inspectedMenu = NO;
  __block BOOL survivedMenu = NO;
  __weak TLQuickInputWindowController *weakQuick = quick;
  quick.settingsHandler = ^{
    NSTimer *check = [NSTimer timerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *timer) {
      inspectedMenu = YES;
      survivedMenu = weakQuick.window.visible;
      [menu cancelTrackingWithoutAnimation];
    }];
    [NSRunLoop.mainRunLoop addTimer:check forMode:NSEventTrackingRunLoopMode];
    [NSRunLoop.mainRunLoop addTimer:check forMode:NSDefaultRunLoopMode];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 0) inView:weakQuick.messageInput.settingsButton];
    [check invalidate];
  };
  TLGlassButton *settings = quick.messageInput.settingsButton;
  [NSApp sendAction:settings.action to:settings.target from:settings]; Drain();
  Check(inspectedMenu && survivedMenu && quick.window.visible && reportedVisible, @"native dropdown tracking keeps the popup open and notch suppressed");
  quick.settingsHandler = nil;
  [other makeKeyAndOrderFront:nil]; Drain();
  Check(!quick.window.visible, @"outside focus still dismisses after a picker and menu have closed");
  [quick presentOnScreen:NSScreen.mainScreen]; Drain();
  Check([quick.messageInput.attachmentURLs isEqualToArray:files] &&
    [quick.messageInput.textView.string isEqual:@"Keep this draft\nand its attachments"], @"repeated focus changes preserve the complete draft");
  [quick dismiss];
  [other orderOut:nil];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    Check(NSScreen.mainScreen != nil, @"native tests require access to the macOS window server");
    TestPanel();
    TestWorkspaceHandoff();
    TestFocusAndDraftRestoration();
    NSLog(@"QuickInputTests passed");
  }
  return 0;
}
