#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "TalariaWindowController.h"
#import "WorkspaceTabRuntime.h"
#import "TLBrowserTabController.h"
#import "design_system/TLFindBar.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface TLFindTestApplication : NSApplication
@property (nonatomic, strong) NSWindow *testKeyWindow, *testModalWindow;
@property (nonatomic, strong) NSEvent *testCurrentEvent;
@end
@implementation TLFindTestApplication
- (NSWindow *)keyWindow { return self.testKeyWindow; }
- (NSWindow *)modalWindow { return self.testModalWindow; }
- (NSEvent *)currentEvent { return self.testCurrentEvent ?: super.currentEvent; }
@end
@interface TLFindTestBrowser : TLChromiumBrowserController
@property (nonatomic, strong) TLChromiumBrowserSession *session;
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic) NSUInteger stopCount, focusCount;
@end
@implementation TLFindTestBrowser
- (instancetype)init { self = [super init]; if (self) _requests = [NSMutableArray array]; return self; }
- (TLChromiumBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window
    titleHandler:(TLChromiumBrowserTitleHandler)titleHandler linkHandler:(TLChromiumBrowserLinkHandler)linkHandler
    URLHandler:(TLChromiumBrowserURLHandler)URLHandler faviconHandler:(TLChromiumBrowserFaviconHandler)faviconHandler
    navigationHandler:(TLChromiumBrowserNavigationHandler)navigationHandler {
  self.session = [TLChromiumBrowserSession new];
  return self.session;
}
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(TLChromiumBrowserSession *)session completion:(void (^)(BOOL))completion {
  if (completion) completion(YES);
}
- (void)findText:(NSString *)text inSession:(TLChromiumBrowserSession *)session forward:(BOOL)forward findNext:(BOOL)findNext {
  [self.requests addObject:@{@"text":text, @"forward":@(forward), @"next":@(findNext)}];
}
- (void)stopFindingInSession:(TLChromiumBrowserSession *)session { self.stopCount++; }
- (void)focusSession:(TLChromiumBrowserSession *)session { self.focusCount++; }
- (void)closeSession:(TLChromiumBrowserSession *)session {}
@end
@interface TalariaWindowController (FindTests)
- (void)setRuntime:(TLWorkspaceTabRuntime *)runtime forTab:(TLWorkspaceTab *)tab;
@end

static NSEvent *Key(NSString *key, NSEventModifierFlags flags) {
  return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
    windowNumber:0 context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:0];
}
static void Query(TLFindBar *bar, NSString *query) {
  bar.searchField.stringValue = query;
  [bar controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:bar.searchField]];
}
static TLBrowserTabController *Browser(TLFindTestBrowser *service) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  return [[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:@"https://example.com"]
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:160 browserService:service];
#pragma clang diagnostic pop
}
static NSBitmapImageRep *RenderButton(TLThemedButton *button) {
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:NSWidth(button.bounds) * 2
    pixelsHigh:NSHeight(button.bounds) * 2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  NSAffineTransform *scale = [NSAffineTransform transform]; [scale scaleBy:2]; [scale concat];
  [button.palette.tabBackground setFill]; NSRectFill(button.bounds);
  [button.cell drawWithFrame:button.bounds inView:button];
  [NSGraphicsContext restoreGraphicsState];
  return bitmap;
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

static void CheckRendering(TLFindBar *bar, NSWindow *window) {
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    bar.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *width in @[@200, @640]) {
      bar.frame = NSMakeRect(0, 0, width.doubleValue, bar.palette.fieldHeight + bar.palette.space4 * 2);
      [bar layoutSubtreeIfNeeded];
      Check(NSWidth(bar.searchField.frame) >= 40, @"query remains usable at the minimum window width");
      Check(NSMaxX([bar convertRect:bar.searchField.bounds fromView:bar.searchField]) <= NSMinX(bar.resultLabel.frame) &&
        NSMaxX(bar.resultLabel.frame) <= NSMinX(bar.previousButton.frame) &&
        NSMaxX(bar.closeButton.frame) <= NSWidth(bar.bounds), @"find controls fit without overlap");
      NSBitmapImageRep *preview = [bar bitmapImageRepForCachingDisplayInRect:bar.bounds];
      [bar cacheDisplayInRect:bar.bounds toBitmapImageRep:preview];
      [[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"/tmp/talaria-find-%@-%@.png", theme, width] atomically:YES];
    }
    for (TLThemedButton *button in @[bar.previousButton, bar.nextButton, bar.closeButton]) {
      for (NSString *state in @[@"normal", @"hover", @"pressed", @"disabled", @"focus"]) {
        button.enabled = ![state isEqual:@"disabled"];
        [button setValue:@([state isEqual:@"hover"]) forKey:@"hovered"];
        [button highlight:[state isEqual:@"pressed"]];
        [window makeFirstResponder:[state isEqual:@"focus"] ? button : nil];
        NSBitmapImageRep *bitmap = RenderButton(button);
        CGFloat alpha = button.enabled ? 1 : bar.palette.disabledOpacity;
        CGFloat surface[3], unusedAlpha;
        RGBComponents(bar.palette.tabBackground, surface, &unusedAlpha);
        CompositeColor(bar.palette.secondaryActionSurface, alpha, surface);
        if ([state isEqual:@"hover"] || [state isEqual:@"pressed"]) CompositeColor(bar.palette.chromeHoverSurface, 1, surface);
        Check(PixelMatches(bitmap, 10, 32, surface), @"find buttons render themed surfaces in each interaction state");
        CGFloat foreground[3] = {surface[0], surface[1], surface[2]};
        CompositeColor(bar.palette.secondaryActionText, alpha, foreground);
        NSUInteger ink = 0;
        for (NSInteger y = 16; y < 48; y++) for (NSInteger x = 16; x < 40; x++)
          if (PixelMatches(bitmap, x, y, foreground)) ink++;
        Check(ink > 1, [NSString stringWithFormat:@"find symbols render paired foreground: %@ %@ %@", theme, state, button.toolTip]);
      }
      button.enabled = YES; [button highlight:NO]; [button setValue:@NO forKey:@"hovered"];
    }
  }
}
int main(void) {
  @autoreleasepool {
    TLFindTestApplication *app = [TLFindTestApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 500)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    app.testKeyWindow = window;
    TLFindTestBrowser *service = [TLFindTestBrowser new];
    TLBrowserTabController *browser = Browser(service);
    window.contentView = browser.view;
    [browser startInWindow:window];
    TLFindBar *bar = [browser valueForKey:@"findBar"];
    Check(!browser.findBarVisible, @"find starts closed");
    [browser showFindBar];
    Check(browser.findBarVisible && bar.searchField.currentEditor == window.firstResponder, @"show find focuses its native field");
    Query(bar, @"talaria");
    Check([service.requests.lastObject isEqual:@{@"text":@"talaria", @"forward":@YES, @"next":@NO}], @"typing starts a fresh search");
    service.session.findResultsChangedHandler(3, 1, YES);
    Check([bar.resultLabel.stringValue isEqual:@"1/3"] && bar.nextButton.enabled, @"Chromium results update count and controls");
    [browser showFindBar];
    Check(service.requests.count == 1 && [(NSTextView *)window.firstResponder selectedRange].length == 7, @"repeated command-F selects the query without moving the match");
    [bar.nextButton performClick:nil];
    Check([service.requests.lastObject[@"next"] boolValue] && [service.requests.lastObject[@"forward"] boolValue], @"next continues the search");
    [bar.previousButton performClick:nil];
    Check(![service.requests.lastObject[@"forward"] boolValue], @"previous searches backward");
    app.testCurrentEvent = Key(@"\r", 0);
    Check([bar control:bar.searchField textView:(NSTextView *)window.firstResponder doCommandBySelector:@selector(insertNewline:)] &&
      [service.requests.lastObject[@"forward"] boolValue], @"Return finds the next match without editing the query");
    app.testCurrentEvent = Key(@"\r", NSEventModifierFlagShift);
    [bar control:bar.searchField textView:(NSTextView *)window.firstResponder doCommandBySelector:@selector(insertNewline:)];
    Check(![service.requests.lastObject[@"forward"] boolValue], @"Shift-Return finds the previous match");
    app.testCurrentEvent = nil;
    Query(bar, @"missing"); service.session.findResultsChangedHandler(0, 0, YES);
    Check([bar.resultLabel.stringValue isEqual:@"0 matches"] && !bar.nextButton.enabled, @"no matches is explicit and disables navigation");
    NSUInteger stops = service.stopCount;
    Query(bar, @"");
    Check(service.stopCount == stops + 1 && !bar.resultLabel.stringValue.length, @"clearing the query removes highlights and count");
    Query(bar, @"saved");
    [browser hideFindBar];
    Check(!browser.findBarVisible && service.focusCount == 1, @"closing restores browser focus");
    service.session.findResultsChangedHandler(9, 2, YES);
    Check(![bar.resultLabel.stringValue isEqual:@"2/9"], @"closed find ignores late replies");
    [browser showFindBar];
    Check([service.requests.lastObject[@"text"] isEqual:@"saved"] && ![service.requests.lastObject[@"next"] boolValue], @"reopen retains query and starts fresh");
    service.session.documentStartedHandler();
    Check(!browser.findBarVisible && !bar.searchField.currentEditor, @"navigation dismisses find and releases field focus");

    TalariaWindowController *workspace = [[TalariaWindowController alloc] initWithWindow:window];
    TLAppStateManager *state = [TLAppStateManager new];
    [workspace setValue:state forKey:@"appStateManager"];
    [workspace setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
    TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:1 title:@"Page" toolTip:@"" URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
    TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime runtimeWithContentView:browser.view openAction:@selector(description) closeAction:@selector(description)];
    runtime.featureController = browser;
    [workspace setRuntime:runtime forTab:tab]; [state addWorkspaceTab:tab activate:YES];
    TLAppDelegate *delegate = [TLAppDelegate new]; [delegate setValue:workspace forKey:@"windowController"];
    Check([delegate handleBrowserFindShortcutEvent:Key(@"F", NSEventModifierFlagCommand | NSEventModifierFlagCapsLock)] && browser.findBarVisible, @"command-F routes to the active browser");
    Check(![delegate handleBrowserFindShortcutEvent:Key(@"f", NSEventModifierFlagCommand | NSEventModifierFlagOption)], @"unrelated modifier combinations pass through");
    Check([delegate handleBrowserFindShortcutEvent:Key(@"g", NSEventModifierFlagCommand | NSEventModifierFlagShift)] && ![service.requests.lastObject[@"forward"] boolValue], @"command-shift-G routes backward");
    Check([delegate handleBrowserFindShortcutEvent:Key(@"\e", 0)] && !browser.findBarVisible, @"Escape dismisses find from page focus");
    Check(![delegate handleBrowserFindShortcutEvent:Key(@"\e", 0)], @"Escape passes through when find is closed");
    app.testModalWindow = window;
    Check(![delegate handleBrowserFindShortcutEvent:Key(@"f", NSEventModifierFlagCommand)], @"modal windows block find shortcuts");
    app.testModalWindow = nil; app.testKeyWindow = nil;
    Check(![delegate handleBrowserFindShortcutEvent:Key(@"f", NSEventModifierFlagCommand)], @"other windows keep their own find behavior");
    app.testKeyWindow = window;
    TLFindTestBrowser *otherService = [TLFindTestBrowser new];
    TLBrowserTabController *other = Browser(otherService);
    TLWorkspaceTab *otherTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:2 title:@"Second" toolTip:@"" URL:tab.URL closeable:YES];
    TLWorkspaceTabRuntime *otherRuntime = [TLWorkspaceTabRuntime runtimeWithContentView:other.view openAction:@selector(description) closeAction:@selector(description)];
    otherRuntime.featureController = other; [workspace setRuntime:otherRuntime forTab:otherTab];
    [state addWorkspaceTab:otherTab activate:YES];
    [delegate handleBrowserFindShortcutEvent:Key(@"f", NSEventModifierFlagCommand)];
    Check(other.findBarVisible && !browser.findBarVisible, @"active pane owns find independently of the other browser");
    TLWorkspaceTab *chat = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:3 title:@"Chat" toolTip:@"" URL:nil closeable:YES];
    [state addWorkspaceTab:chat activate:YES];
    Check(![delegate handleBrowserFindShortcutEvent:Key(@"f", NSEventModifierFlagCommand)], @"chat does not open browser find");
    TLFindBar *preview = [[TLFindBar alloc] initWithFrame:NSMakeRect(0, 0, 640, 46)];
    [window.contentView addSubview:preview]; preview.searchField.stringValue = @"needle";
    [preview setMatchCount:3 activeMatch:1 searching:NO];
    CheckRendering(preview, window);
    preview.frame = NSMakeRect(0, 0, 200, 46);
    [preview setMatchCount:0 activeMatch:0 searching:NO]; [preview layoutSubtreeIfNeeded];
    Check([preview.resultLabel.stringValue isEqual:@"0/0"] && NSWidth(preview.searchField.frame) >= 40,
      @"empty results keep the query usable in a narrow pane");
    [browser close]; [other close];
    Check(!service.session.findResultsChangedHandler && !service.session.documentStartedHandler, @"closing clears session callbacks");
    app.testKeyWindow = nil;
    [window close];
    NSLog(@"BrowserFindTests passed");
  }
  return 0;
}
