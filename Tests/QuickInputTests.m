#import <AppKit/AppKit.h>
#import "TLQuickInputWindowController.h"
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "NotchOverlayController.h"
#import "TLChatTabController.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLScreenRegionSelectionView.h"
#import "TLScreenCapture.h"
#import "design_system/TLTransitionCoordinator.h"

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

@interface TLNotchOverlayController (QuickInputTesting)
- (void)showOverlayForNotchRect:(NSRect)rect screen:(NSScreen *)screen
  presentation:(NSUInteger)presentation progress:(CGFloat)progress virtualNotch:(BOOL)virtualNotch;
- (void)updateFrameAnimationAtTimestamp:(NSTimeInterval)timestamp;
@end

@interface TLTestScreenCapture : TLScreenCapture
@property (nonatomic) NSRect capturedRect;
@property (nonatomic, copy) NSArray<NSNumber *> *excludedWindowIDs;
@property (nonatomic, copy) void (^pendingCompletion)(NSURL *, NSError *);
@end
@implementation TLTestScreenCapture
- (void)captureRect:(NSRect)screenRect excludingWindowIDs:(NSArray<NSNumber *> *)windowIDs
         completion:(void (^)(NSURL *, NSError *))completion {
  self.capturedRect = screenRect;
  self.excludedWindowIDs = windowIDs;
  self.pendingCompletion = completion;
}
- (void)cancel {}
@end

// Keep real display geometry while exercising both camera configurations.
@interface TLQuickInputTestScreen : NSObject
@property (nonatomic, strong) NSScreen *screen;
@property (nonatomic) NSEdgeInsets safeAreaInsets;
@end
@implementation TLQuickInputTestScreen
- (id)forwardingTargetForSelector:(SEL)selector { return self.screen; }
@end

static NSEvent *SelectionEvent(TLScreenRegionSelectionView *view, NSEventType type, NSPoint point) {
  return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
    windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

static void InvalidateSnapshot(NSView *view) {
  view.needsDisplay = YES;
  for (NSView *child in view.subviews) InvalidateSnapshot(child);
}

static BOOL WindowReceivesMouseAtPoint(NSWindow *window, NSPoint point) {
  // AppKit can report a window visible before its frame reaches the window server.
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  while ([NSWindow windowNumberAtPoint:point belowWindowWithWindowNumber:0] != window.windowNumber && deadline.timeIntervalSinceNow > 0) Drain();
  return [NSWindow windowNumberAtPoint:point belowWindowWithWindowNumber:0] == window.windowNumber;
}

static void TestNotchExpansion(void) {
  NSScreen *screen = NSScreen.mainScreen;
  NSRect start = NSMakeRect(NSMidX(screen.frame) - 150, NSMaxY(screen.frame) - 21, 189, 21);
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    TLQuickInputWindowController *quick = [[TLQuickInputWindowController alloc] initWithPalette:palette];
    __block NSTimeInterval now = 100;
    TLTransitionCoordinator *transition = [[TLTransitionCoordinator alloc]
      initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
    [quick setValue:transition forKey:@"notchTransition"];
    __weak TLQuickInputWindowController *weakQuick = quick;
    __block BOOL coveredBeforeHandoff = NO;
    quick.visibilityChangeHandler = ^(BOOL visible) {
      if (visible) coveredBeforeHandoff = weakQuick.window.visible && NSEqualRects(weakQuick.window.frame, start);
    };
    [quick presentInNotchOnScreen:screen fromFrame:start];
    NSRect target = [[quick valueForKey:@"notchTargetFrame"] rectValue];
    NSView *content = [quick valueForKey:@"inputContainer"];
    Check(coveredBeforeHandoff && transition.hasTransitions && NSEqualRects(quick.window.frame, start),
      @"input notch covers the compact frame before the old overlay is hidden");
    Check(content.alphaValue == 0 && fabs(NSWidth(quick.messageInput.frame) - 600) < 1,
      @"input starts hidden and laid out at the narrower final width");
    now += palette.notchInputExpansionDuration * 0.5;
    [transition advance];
    NSRect middle = quick.window.frame;
    Check(NSWidth(middle) > NSWidth(start) && NSWidth(middle) < NSWidth(target) &&
      NSHeight(middle) > NSHeight(start) && NSHeight(middle) < NSHeight(target),
      @"notch passes through intermediate widths and heights");
    Check(fabs(NSMaxY(middle) - NSMaxY(screen.frame)) < 1 &&
      NSMidX(middle) > NSMidX(start) && NSMidX(middle) < NSMidX(target),
      @"notch slides smoothly to its new center while staying pinned to the top");
    [quick applyPalette:palette];
    [quick presentInNotchOnScreen:screen fromFrame:start];
    SetText(quick, @"A draft typed while the notch expands");
    Check(NSEqualRects(quick.window.frame, middle) && fabs(NSWidth(quick.messageInput.frame) - 600) < 1,
      @"layout, typing, and repeated presentation do not snap or restart expansion");
    now += palette.notchInputExpansionDuration * 0.25;
    [transition advance];
    Check(content.alphaValue == 0 && quick.window.firstResponder == quick.messageInput.textView,
      @"input accepts typing immediately but remains hidden until the controls fit");
    now += palette.notchInputExpansionDuration;
    [transition advance];
    NSRect overshoot = quick.window.frame;
    Check(![transition hasTransitionForKey:@"notchExpansion"] && NSWidth(overshoot) > NSWidth(target) &&
      NSHeight(overshoot) > NSHeight(target) && NSWidth(overshoot) < NSWidth(target) * 1.06,
      @"fast expansion ends with a small size overshoot");
    Check(fabs(NSMaxY(overshoot) - NSMaxY(screen.frame)) < 1 && fabs(NSMidX(overshoot) - NSMidX(target)) < 1,
      @"bounce stays centered and pinned to the screen top");
    now += palette.notchInputRevealDuration * 0.5;
    [transition advance];
    Check(content.alphaValue > 0 && content.alphaValue < 1,
      @"input fades in while the bounce settles around the whole row");
    NSRect settling = quick.window.frame;
    Check(NSWidth(settling) < NSWidth(overshoot) && NSWidth(settling) > NSWidth(target),
      @"bounce smoothly returns toward the final width");
    [quick applyPalette:palette];
    Check(NSEqualRects(quick.window.frame, settling) && fabs(NSWidth(quick.messageInput.frame) - 600) < 1,
      @"layout updates do not interrupt the bounce or resize its input");
    InvalidateSnapshot(quick.window.contentView);
    NSBitmapImageRep *image = [quick.window.contentView bitmapImageRepForCachingDisplayInRect:quick.window.contentView.bounds];
    [quick.window.contentView cacheDisplayInRect:quick.window.contentView.bounds toBitmapImageRep:image];
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:
      [NSString stringWithFormat:@"/tmp/talaria-notch-expanding-%@.png", theme] atomically:YES];
    now += palette.notchInputRevealDuration;
    [transition advance];
    Check(!transition.hasTransitions && content.alphaValue == 1, @"input reveal finishes fully visible");
    // AppKit rounds fractional window origins and sizes to display coordinates.
    Check(fabs(NSMinX(quick.window.frame) - NSMinX(target)) < 1 &&
      fabs(NSMinY(quick.window.frame) - NSMinY(target)) < 1 &&
      fabs(NSWidth(quick.window.frame) - NSWidth(target)) < 1 &&
      fabs(NSHeight(quick.window.frame) - NSHeight(target)) < 1,
      @"bounce settles at the intended final frame without residual overshoot");
    [quick dismiss];
    [quick presentInNotchOnScreen:screen fromFrame:start];
    now += palette.notchInputExpansionDuration * 0.25;
    [transition advance];
    [quick dismiss];
    NSRect dismissed = quick.window.frame;
    now += palette.notchInputExpansionDuration;
    [transition advance];
    Check(!transition.hasTransitions && !quick.window.visible && NSEqualRects(quick.window.frame, dismissed),
      @"dismissing mid-expansion cancels all later frame updates");
    [quick presentInNotchOnScreen:screen fromFrame:start];
    now += palette.notchInputExpansionDuration * 1.1;
    [transition advance];
    now += palette.notchInputRevealDuration * 0.5;
    [transition advance];
    [quick dismiss];
    dismissed = quick.window.frame;
    now += palette.notchInputRevealDuration;
    [transition advance];
    Check(!transition.hasTransitions && !quick.window.visible && NSEqualRects(quick.window.frame, dismissed),
      @"dismissing during the bounce cancels its settling and reveal");
    [quick presentInNotchOnScreen:screen];
    Check(content.alphaValue == 1 && [quick.messageInput.textView.string hasPrefix:@"A draft typed"],
      @"reopening after interrupted expansion restores the visible draft");
    [quick dismiss];
  }
}

static void TestNotchPresentationAndCapture(void) {
  TLQuickInputWindowController *quick = [[TLQuickInputWindowController alloc]
    initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  TLTestScreenCapture *capture = [[TLTestScreenCapture alloc] init];
  [quick setValue:capture forKey:@"screenCapture"];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [quick applyPalette:palette];
    TLQuickInputTestScreen *screen = [[TLQuickInputTestScreen alloc] init];
    screen.screen = NSScreen.mainScreen;
    // Reuse the composer across displays to catch stale camera padding too.
    for (NSNumber *cameraInset in @[@0, @32, @48, @0]) {
      screen.safeAreaInsets = NSEdgeInsetsMake(cameraInset.doubleValue, 0, 0, 0);
      [quick presentInNotchOnScreen:(NSScreen *)screen];
      CGFloat top = NSHeight(quick.window.contentView.bounds) - NSMaxY(quick.messageInput.frame);
      CGFloat bottom = NSMinY(quick.messageInput.frame);
      if (cameraInset.doubleValue == 0) {
        Check(fabs(top - bottom) < 1 && fabs(top - palette.notchInputVerticalPadding) < 1,
              @"screens without a physical notch use equal normal padding above and below the input");
      } else {
        Check(top >= cameraInset.doubleValue && top >= palette.notchOverlayMinimumHeight,
              @"notched displays retain enough clearance for the physical camera area");
      }
      [quick dismiss];
    }
    [quick presentInNotchOnScreen:NSScreen.mainScreen];
    SetText(quick, @"Describe the area I capture");
    Check(fabs(NSMaxY(quick.window.frame) - NSMaxY(NSScreen.mainScreen.frame)) < 1,
          @"expanded notch is pinned to the physical top of the display");
    Check(NSWidth(quick.window.frame) > palette.notchOverlayMinimumWidth &&
          NSHeight(quick.window.frame) > NSHeight(quick.messageInput.frame),
          @"notch grows around the input");
    Check(NSContainsRect(quick.window.contentView.bounds, quick.messageInput.frame) &&
          NSHeight(quick.window.contentView.bounds) - NSMaxY(quick.messageInput.frame) >= NSScreen.mainScreen.safeAreaInsets.top,
          @"composer is inside the notch and below the camera area");
    Check(!quick.messageInput.showsBackground && quick.messageInput.backgroundView.hidden && quick.messageInput.layer.borderWidth == 0,
          @"embedded input has no glass background or border");
    Check(quick.messageInput.palette.dark && !quick.window.hasShadow, @"notch content stays readable on its black surface in both themes");
    NSView *surface = quick.window.contentView;
    // AppKit otherwise reuses clean layer-backed children from the previous snapshot.
    InvalidateSnapshot(surface);
    NSBitmapImageRep *bitmap = [surface bitmapImageRepForCachingDisplayInRect:surface.bounds];
    [surface cacheDisplayInRect:surface.bounds toBitmapImageRep:bitmap];
    NSColor *header = [[bitmap colorAtX:bitmap.pixelsWide / 2 y:5] colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    Check(header.alphaComponent > 0.99 && header.redComponent < 0.01 && header.greenComponent < 0.01 && header.blueComponent < 0.01,
          @"expanded notch renders a solid black header");
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:
      theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-expanded-notch-light.png" : @"/tmp/talaria-expanded-notch-dark.png" atomically:YES];
    NSWindow *selectionWindow = [quick valueForKey:@"selectionWindow"];
    Check(selectionWindow.visible && NSEqualRects(selectionWindow.frame, NSScreen.mainScreen.frame) &&
          selectionWindow.level < quick.window.level && !selectionWindow.canBecomeKeyWindow,
          @"selection covers the whole screen around the notch while leaving its input above it and focused");
    TLScreenRegionSelectionView *selection = [quick valueForKey:@"selectionView"];
    for (NSNumber *side in @[@(-1), @1]) {
      CGFloat x = side.intValue < 0 ? NSMinX(quick.window.frame) - palette.space5 : NSMaxX(quick.window.frame) + palette.space5;
      NSPoint screenPoint = NSMakePoint(x, NSMidY(quick.window.frame));
      Check(WindowReceivesMouseAtPoint(selectionWindow, screenPoint),
            @"fully transparent capture window receives mouse-downs beside the notch");
      Check(WindowReceivesMouseAtPoint(selectionWindow, NSMakePoint(x, NSMaxY(selectionWindow.frame) - 2)),
            @"capture drags can also start along the top edge beside the notch");
      NSPoint point = [selectionWindow convertPointFromScreen:screenPoint];
      [selection mouseDown:SelectionEvent(selection, NSEventTypeLeftMouseDown, point)];
      NSPoint end = NSMakePoint(point.x + side.intValue * 40, point.y - 30);
      [selection mouseDragged:SelectionEvent(selection, NSEventTypeLeftMouseDragged, end)];
      Check(NSWidth(selection.selectionRect) == 40 && NSHeight(selection.selectionRect) == 30,
            @"capture drags can start on either side of the notch above its bottom edge");
      [selection resetSelection];
    }
    Check(fabs(NSMinY(quick.messageInput.frame) - palette.notchInputVerticalPadding) < 1,
          @"notch ends below the composer without an extra instructional text row");
    InvalidateSnapshot(selection);
    NSBitmapImageRep *clear = [selection bitmapImageRepForCachingDisplayInRect:selection.bounds];
    [selection cacheDisplayInRect:selection.bounds toBitmapImageRep:clear];
    Check([clear colorAtX:10 y:10].alphaComponent == 0 &&
          [clear colorAtX:clear.pixelsWide / 2 y:clear.pixelsHigh / 2].alphaComponent == 0,
          @"idle capture surface renders fully transparent in both themes");
    Escape(quick);
    Check(!selectionWindow.visible, @"Escape removes the capture surface");
  }
  [quick presentInNotchOnScreen:NSScreen.mainScreen];
  TLScreenRegionSelectionView *selection = [quick valueForKey:@"selectionView"];
  // Drag in reverse to exercise normalization and the real event-to-attachment handoff.
  [selection mouseDown:SelectionEvent(selection, NSEventTypeLeftMouseDown, NSMakePoint(240, 180))];
  [selection mouseDragged:SelectionEvent(selection, NSEventTypeLeftMouseDragged, NSMakePoint(40, 30))];
  Check(NSEqualRects(selection.selectionRect, NSMakeRect(40, 30, 200, 150)), @"reverse dragging defines the same rectangular capture");
  NSBitmapImageRep *selectionBitmap = [selection bitmapImageRepForCachingDisplayInRect:selection.bounds];
  [selection cacheDisplayInRect:selection.bounds toBitmapImageRep:selectionBitmap];
  CGFloat scale = selectionBitmap.pixelsWide / NSWidth(selection.bounds);
  Check([selectionBitmap colorAtX:10 y:10].alphaComponent == 0 &&
        [selectionBitmap colorAtX:(NSInteger)(100 * scale) y:(NSInteger)((NSHeight(selection.bounds) - 80) * scale)].alphaComponent == 0,
        @"dragging leaves the inside and outside of the selection transparent");
  [[selectionBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-capture-selection.png" atomically:YES];
  NSRect expected = [selection.window convertRectToScreen:selection.selectionRect];
  NSRect notchBeforeCapture = quick.window.frame;
  NSInteger notchWindowNumber = quick.window.windowNumber;
  [selection mouseUp:SelectionEvent(selection, NSEventTypeLeftMouseUp, NSMakePoint(40, 30))];
  Check(!selection.window.visible && quick.window.visible && quick.window.alphaValue == 1 &&
        NSEqualRects(quick.window.frame, notchBeforeCapture) && !quick.messageInput.attachmentsEditable,
        @"capture removes the selection border while keeping the notch visible in place");
  for (NSUInteger attempt = 0; attempt < 10 && !capture.pendingCompletion; attempt++) Drain();
  Check(NSEqualRects(capture.capturedRect, expected), @"capture receives only the dragged area in global screen coordinates");
  Check([capture.excludedWindowIDs containsObject:@(notchWindowNumber)] &&
        [capture.excludedWindowIDs containsObject:@(selection.window.windowNumber)],
        @"capture excludes the notch and selection windows without hiding the composer");
  Check(quick.window.visible && quick.window.alphaValue == 1 && NSEqualRects(quick.window.frame, notchBeforeCapture),
        @"notch stays visible and stationary while the screenshot is pending");
  __block NSUInteger submissions = 0;
  __block NSArray<NSURL *> *submittedFiles;
  quick.submissionHandler = ^(NSString *text, NSArray<NSURL *> *files, BOOL routing) { submissions++; submittedFiles = files; };
  Submit(quick);
  Check(submissions == 0, @"capture cannot submit an incomplete attachment");
  NSURL *fixture = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"assets/Talaria-icon.png"]];
  capture.pendingCompletion(fixture, nil);
  capture.pendingCompletion = nil;
  Drain();
  Check([quick.messageInput.attachmentURLs isEqualToArray:@[fixture]] && quick.messageInput.attachmentsEditable &&
        selection.window.visible && quick.window.alphaValue == 1 && quick.window.firstResponder == quick.messageInput.textView,
        @"completed capture attaches its image to the visible composer and restores selection");
  Check(quick.window.windowNumber == notchWindowNumber && fabs(NSMaxY(quick.window.frame) - NSMaxY(notchBeforeCapture)) < 1 &&
        fabs(NSMidX(quick.window.frame) - NSMidX(notchBeforeCapture)) < 1,
        @"new attachment grows the same notch downwards without moving its top or center");
  Check([quick.messageInput.textView.string isEqual:@"Describe the area I capture"], @"capture preserves the prompt draft");
  Submit(quick);
  Check(submissions == 1 && [submittedFiles isEqualToArray:@[fixture]] && !selection.window.visible,
        @"captured image reaches the regular submission pipeline");
  [quick presentInNotchOnScreen:NSScreen.mainScreen];
  SetText(quick, @"Keep this cancelled draft");
  [selection mouseDown:SelectionEvent(selection, NSEventTypeLeftMouseDown, NSMakePoint(10, 10))];
  [selection mouseUp:SelectionEvent(selection, NSEventTypeLeftMouseUp, NSMakePoint(100, 100))];
  for (NSUInteger attempt = 0; attempt < 10 && !capture.pendingCompletion; attempt++) Drain();
  Check(capture.pendingCompletion != nil, @"second capture starts independently");
  Escape(quick);
  [quick presentInNotchOnScreen:NSScreen.mainScreen];
  capture.pendingCompletion(fixture, nil);
  capture.pendingCompletion = nil;
  Check(quick.messageInput.attachmentURLs.count == 0 && [quick.messageInput.textView.string isEqual:@"Keep this cancelled draft"],
        @"late completion from a cancelled capture never attaches to a reopened draft");
  [selection mouseDown:SelectionEvent(selection, NSEventTypeLeftMouseDown, NSMakePoint(10, 10))];
  [selection mouseUp:SelectionEvent(selection, NSEventTypeLeftMouseUp, NSMakePoint(11, 11))];
  Check(!quick.window.visible && !selection.window.visible && !capture.pendingCompletion, @"a click or tiny drag dismisses without capturing");
  [quick presentOnScreen:NSScreen.mainScreen];
  Check(quick.messageInput.showsBackground && !quick.messageInput.backgroundView.hidden && !selection.window.visible,
        @"ordinary quick input restores its optional glass background and removes capture mode");
  [quick dismiss];
  Check(NSEqualRects(TLScreenCaptureRect(NSMakeRect(40, 30, 200, 150), NSMakeRect(0, 0, 1440, 900)), NSMakeRect(40, 720, 200, 150)),
        @"screen capture converts AppKit's bottom-up coordinates");
  Check(NSEqualRects(TLScreenCaptureRect(NSMakeRect(-800, -200, 100, 80), NSMakeRect(0, 0, 1440, 900)), NSMakeRect(-800, 1020, 100, 80)),
        @"screen capture handles displays to the left and below the primary display");
  Check(NSEqualRects(TLScreenCaptureRect(NSMakeRect(50, 1000, 100, 80), NSMakeRect(0, 0, 1440, 900)), NSMakeRect(50, -180, 100, 80)),
        @"screen capture handles displays above the primary display");
}

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
  TLChatTabController *presentation = [self valueForKey:@"chatPresentation"];
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
  TLChatTabController *existing = [owner valueForKey:@"chatPresentation"];
  existing.promptTextView.string = @"Existing unsent draft";
  NSURL *file = [NSURL fileURLWithPath:@"/tmp/quick-input-attachment.txt"];
  existing.messageInput.attachmentURLs = @[file];
  [window orderOut:nil];
  NSScreen *screen = NSScreen.mainScreen;
  NSRect compact = NSMakeRect(NSMidX(screen.frame) - 100, NSMaxY(screen.frame) - 21, 200, 21);
  [notch showOverlayForNotchRect:compact screen:screen presentation:0 progress:0 virtualNotch:YES];
  [notch updateFrameAnimationAtTimestamp:[[notch valueForKey:@"frameAnimationStartedAt"] doubleValue] + 0.06];
  [[notch valueForKey:@"frameAnimationTimer"] invalidate];
  [[notch valueForKey:@"trackingTimer"] invalidate];
  NSRect clickedFrame = notch.visibleFrame;
  [owner openFromNotchOverlay:nil];
  TLQuickInputWindowController *quick = [owner valueForKey:@"quickInputController"];
  Check(NSEqualRects(quick.window.frame, clickedFrame),
    @"clicking an opening notch transfers its current frame to the expanding input");
  Drain();
  Check([notch valueForKey:@"trackingTimer"] == nil && NSIsEmptyRect(notch.presentationFrame),
    @"opening quick input hides the notch and stops hover tracking");
  Check(!window.visible && quick.window.visible && state.snapshot.workspaceTabs.count == 1, @"notch opens only the popup and creates no tab");
  Check(!quick.messageInput.showsBackground && fabs(NSMaxY(quick.window.frame) - NSMaxY(quick.window.screen.frame)) < 1,
        @"clicking the notch opens the embedded composer at the screen's top edge");
  SetText(quick, @"New request"); Escape(quick);
  Check([notch valueForKey:@"trackingTimer"] != nil, @"Escape restores normal notch tracking");
  Check(!window.visible && state.snapshot.workspaceTabs.count == 1 && owner.sendCount == 0, @"Escape leaves the main window hidden and workspace untouched");
  [owner openFromNotchOverlay:nil];
  quick.model = @"chosen-large"; quick.supportingModel = @"chosen-small";
  Submit(quick); Drain();
  Check([notch valueForKey:@"trackingTimer"] != nil, @"submission restores normal notch tracking");
  Check(window.visible && !quick.window.visible && state.snapshot.workspaceTabs.count == 2 && owner.sendCount == 1, @"submission opens the main window and a new chat");
  TLChatTabController *fresh = [owner valueForKey:@"chatPresentation"];
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
  notch.enabled = NO;
  Check([notch valueForKey:@"trackingTimer"] == nil && NSIsEmptyRect(notch.presentationFrame), @"disabling the notch stops and hides its overlay immediately");
  [notch startTracking];
  Check([notch valueForKey:@"trackingTimer"] == nil, @"disabled notch cannot restart through another caller");
  [window orderOut:nil]; Drain();
  [owner openFromNotchOverlay:nil]; Drain();
  Check(quick.window.visible, @"quick input still opens while the notch is disabled");
  Escape(quick);
  Check([notch valueForKey:@"trackingTimer"] == nil, @"dismissing quick input never re-enables a disabled notch");
  notch.enabled = YES; [notch startTracking];
  Check([notch valueForKey:@"trackingTimer"] != nil, @"re-enabling the notch restores tracking");
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
    TestNotchExpansion();
    TestNotchPresentationAndCapture();
    TestWorkspaceHandoff();
    TestFocusAndDraftRestoration();
    NSLog(@"QuickInputTests passed");
  }
  return 0;
}
