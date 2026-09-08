#import <AppKit/AppKit.h>
#import "TLBrowserDownloadManager.h"
#import "TLDownloadsTabController.h"
#import "design_system/TLDownloadRowView.h"
#import "design_system/TLThemedButton.h"
#import "TalariaWindowController.h"
#import "WorkspaceTabRuntime.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Update(TLBrowserDownloadManager *manager, NSUInteger identifier, TLBrowserDownloadState state, NSString *path, TLBrowserDownloadControl control) {
  [manager updateDownloadWithID:identifier browserIdentifier:7 URLString:@"https://example.com/report.pdf" fileName:@"Quarterly report.pdf" path:path
    receivedBytes:512000 totalBytes:1024000 bytesPerSecond:128000 state:state failureReason:state == TLBrowserDownloadStateFailed ? @"Network disconnected" : @"" control:control];
}
static NSButton *Button(TLDownloadRowView *row, NSString *title) {
  for (NSButton *button in [(NSView *)[row valueForKey:@"actions"] subviews]) if ([button.title isEqual:title]) return button;
  return nil;
}
static BOOL ContainsColor(NSBitmapImageRep *image, NSColor *color) {
  NSColor *expected = [color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  NSUInteger count = 0;
  for (NSInteger y = 0; y < image.pixelsHigh; y++) for (NSInteger x = 0; x < image.pixelsWide; x++) {
    NSColor *actual = [[image colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    if (fabs(actual.redComponent - expected.redComponent) < 0.04 && fabs(actual.greenComponent - expected.greenComponent) < 0.04 &&
        fabs(actual.blueComponent - expected.blueComponent) < 0.04 && ++count > 12) return YES;
  }
  return NO;
}
@interface TalariaWindowController (DownloadTests)
- (void)showDownloads:(id)sender;
- (void)closeDownloadsTab:(id)sender;
- (TLWorkspaceTabRuntime *)runtimeForTab:(TLWorkspaceTab *)tab;
- (void)hydrateWorkspaceTabsFromAppState;
@end
@interface TLDownloadTabTestOwner : TalariaWindowController
@end
@implementation TLDownloadTabTestOwner
- (void)reloadWorkspaceTabs {}
- (void)renderWorkspaceTabs {}
- (void)updateWorkspaceMode {}
- (void)updateControlStates {}
@end
static void TestWorkspaceDownloads(void) {
  TLAppStateManager *state = [[TLAppStateManager alloc] init];
  [state addWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindHistory tabID:0 title:@"History" toolTip:nil URL:nil closeable:YES] activate:YES];
  TLDownloadTabTestOwner *owner = [[TLDownloadTabTestOwner alloc] initWithWindow:nil];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  NSUInteger windowCount = NSApp.windows.count;
  [owner showDownloads:nil];
  TLWorkspaceTab *tab = [state workspaceTabWithKind:TLWorkspaceTabKindDownloads tabID:0];
  TLWorkspaceTabRuntime *runtime = [owner runtimeForTab:tab];
  Check(tab && state.snapshot.activeTabKind == TLWorkspaceTabKindDownloads && [runtime.featureController isKindOfClass:TLDownloadsTabController.class],
    @"avatar-menu action creates and activates a native downloads tab");
  Check(NSApp.windows.count == windowCount, @"opening downloads does not create a separate window");
  [owner showDownloads:nil];
  Check(state.snapshot.workspaceTabs.count == 2 && [owner runtimeForTab:tab] == runtime, @"opening downloads again selects the existing tab");
  [owner hydrateWorkspaceTabsFromAppState];
  Check([owner runtimeForTab:tab] == runtime, @"hydration does not duplicate the downloads controller");
  TLBrowserDownloadManager *manager = TLBrowserDownloadManager.sharedManager;
  Update(manager, 50, TLBrowserDownloadStateDownloading, @"", ^(TLBrowserDownloadAction action) {});
  TLBrowserDownload *active = manager.downloads.firstObject;
  [owner closeDownloadsTab:nil];
  Check(![state hasWorkspaceTabWithKind:TLWorkspaceTabKindDownloads tabID:0] && runtime.featureController.closed && active.active,
    @"closing the downloads tab releases its view while transfers continue");
  [owner performTabCommand:TLTabCommandReopen];
  TLWorkspaceTab *reopened = [state workspaceTabWithKind:TLWorkspaceTabKindDownloads tabID:0];
  Check(reopened && state.snapshot.activeTabKind == TLWorkspaceTabKindDownloads && [owner runtimeForTab:reopened] != runtime && active.active,
    @"reopen restores downloads in the workspace without restarting transfers");
  [owner closeDownloadsTab:nil];
  [manager finishSession];
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  setenv("TL_CHROMIUM_PROFILE_DIR", folder.UTF8String, 1);
  TestWorkspaceDownloads();
  NSURL *history = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"history.json"]];
  TLBrowserDownloadManager *manager = [[TLBrowserDownloadManager alloc] initWithHistoryURL:history];
  Check(manager.downloads.count == 0, @"missing history starts empty");
  __block NSInteger lastAction = -1;
  TLBrowserDownloadControl control = ^(TLBrowserDownloadAction action) { lastAction = action; };
  Update(manager, 1, TLBrowserDownloadStateDownloading, @"", control);
  TLBrowserDownload *first = manager.downloads.firstObject;
  NSString *firstID = first.identifier;
  Check([first.statusText isEqual:@"Starting download…"] && first.active && first.controllable, @"early engine events create a controllable entry");
  NSString *firstPath = [manager reserveDestinationForDownloadID:1 directory:folder fileName:@"report.pdf"];
  NSString *secondPath = [manager reserveDestinationForDownloadID:2 directory:folder fileName:@"../../report.pdf"];
  Check(![firstPath isEqual:secondPath] && [secondPath.lastPathComponent isEqual:@"report (1).pdf"], @"concurrent files reserve distinct sanitized paths before files exist");
  Update(manager, 1, TLBrowserDownloadStateDownloading, firstPath, nil);
  Check(manager.downloads.count == 1 && first.controllable, @"before-download events preserve the update callback and identity");
  [manager performAction:TLBrowserDownloadActionPause forDownload:first];
  Check(lastAction == TLBrowserDownloadActionPause && first.state == TLBrowserDownloadStateDownloading, @"pause reaches the engine and awaits its confirmation");
  Update(manager, 1, TLBrowserDownloadStatePaused, firstPath, control);
  [manager performAction:TLBrowserDownloadActionResume forDownload:first];
  Check(lastAction == TLBrowserDownloadActionResume && [first.statusText hasPrefix:@"Paused"], @"paused state exposes resume");
  TLBrowserDownloadManager *restored = [[TLBrowserDownloadManager alloc] initWithHistoryURL:history];
  Check(restored.downloads.firstObject.state == TLBrowserDownloadStateFailed && restored.downloads.firstObject.canRetry && !restored.downloads.firstObject.controllable,
    @"unfinished downloads become retryable after restart without stale callbacks");
  [@"fixture" writeToFile:firstPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  Update(manager, 1, TLBrowserDownloadStateComplete, firstPath, control);
  Check(first.fileAvailable && !first.controllable, @"completed files can be opened and release engine callbacks");
  NSString *thirdPath = [manager reserveDestinationForDownloadID:3 directory:folder fileName:@"report.pdf"];
  Check([thirdPath.lastPathComponent isEqual:@"report (2).pdf"], @"completed files and active reservations are both protected");
  Update(manager, 2, TLBrowserDownloadStateDownloading, secondPath, control);
  [manager performAction:TLBrowserDownloadActionCancel forDownload:manager.downloads.firstObject];
  Check(lastAction == TLBrowserDownloadActionCancel, @"cancel reaches the engine");
  Update(manager, 2, TLBrowserDownloadStateCancelled, @"", control);
  Check(manager.downloads.firstObject.canRetry, @"cancelled network downloads can retry");
  Update(manager, 3, TLBrowserDownloadStateDownloading, thirdPath, control);
  TLBrowserDownload *active = manager.downloads.firstObject;
  [manager removeDownload:active]; Check(manager.downloads.count == 3, @"active downloads cannot be removed");
  TLDownloadsTabController *controller = [[TLDownloadsTabController alloc] initWithManager:manager palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,640) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSView *host = window.contentView;
  [host addSubview:controller.view];
  [NSLayoutConstraint activateConstraints:@[
    [controller.view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
    [controller.view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
    [controller.view.topAnchor constraintEqualToAnchor:host.topAnchor],
    [controller.view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
  ]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette];
    for (NSNumber *width in @[@760, @494, @200, @160, @1200]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 640)];
      [window.contentView layoutSubtreeIfNeeded];
      Check(fabs(NSWidth(controller.view.frame) - width.doubleValue) < 1, [NSString stringWithFormat:@"downloads content fits width %@ (window %@, view %@)", width, NSStringFromRect(window.contentView.frame), NSStringFromRect(controller.view.frame)]);
      NSStackView *rows = [controller valueForKey:@"rows"];
      Check(rows.arrangedSubviews.count == 3, @"download list includes all states");
      for (TLDownloadRowView *row in rows.arrangedSubviews) {
        Check(NSWidth(row.frame) > width.doubleValue - 40 && NSHeight(row.frame) > 100, @"download rows have readable layout at minimum width");
        for (NSButton *button in [(NSView *)[row valueForKey:@"actions"] subviews]) {
          NSRect rect = [button convertRect:button.bounds toView:row];
          Check(NSMaxX(rect) <= NSWidth(row.bounds) && NSMinX(rect) >= -0.5 && NSMinY(rect) >= -0.5 && NSMaxY(rect) <= NSHeight(row.bounds) + 0.5, @"all action buttons fit within the row");
          Check([button isKindOfClass:TLThemedButton.class], @"download actions use the shared themed control");
        }
      }
      TLDownloadRowView *completedRow = [[controller valueForKey:@"rowViews"] objectForKey:firstID];
      Check(Button(completedRow,@"Open").enabled && Button(completedRow,@"Show in Finder").enabled, @"finished download offers file actions");
      NSView *root = window.contentView;
      NSBitmapImageRep *bitmap = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
      [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
      Check(ContainsColor(bitmap, palette.secondaryActionText) && ContainsColor(bitmap, palette.secondaryActionSurface), @"download buttons render paired foreground and surface in both themes");
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/downloads-%@-%@.png",theme,width] atomically:YES];
    }
  }
  [NSFileManager.defaultManager removeItemAtPath:firstPath error:nil];
  [controller applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  TLDownloadRowView *completedRow = [[controller valueForKey:@"rowViews"] objectForKey:firstID];
  Check(!Button(completedRow,@"Open").enabled && [first.statusText containsString:@"moved or deleted"], @"missing files disable file actions without corrupting history");
  [manager clearFinishedDownloads];
  Check(manager.downloads.count == 1 && manager.downloads.firstObject == active, @"clear finished preserves active transfers");
  Update(manager, 1, TLBrowserDownloadStateComplete, firstPath, control);
  Check(manager.downloads.count == 1, @"late callbacks cannot resurrect cleared history");
  [manager browserClosed:7];
  Check(active.state == TLBrowserDownloadStateFailed && !active.controllable, @"browser teardown resolves orphaned transfers");
  Update(manager, 4, TLBrowserDownloadStateDownloading, @"", control);
  [manager finishSession];
  Check(!manager.downloads.firstObject.active, @"shutdown releases callbacks and saves interrupted state");
  restored = [[TLBrowserDownloadManager alloc] initWithHistoryURL:history];
  NSString *oldIdentifier = restored.downloads.firstObject.identifier;
  Update(restored, 4, TLBrowserDownloadStateDownloading, @"", control);
  Check(restored.downloads.count == 3 && ![restored.downloads.firstObject.identifier isEqual:oldIdentifier], @"reused Chromium IDs cannot overwrite previous-session history");
  [@"[null,42,{\"state\":\"bad\"}]" writeToURL:history atomically:YES encoding:NSUTF8StringEncoding error:nil];
  Check([[TLBrowserDownloadManager alloc] initWithHistoryURL:history].downloads.count == 0, @"malformed history is ignored safely");
  [controller close];
  Check(active.state == TLBrowserDownloadStateFailed, @"closing the view does not mutate transfer history");
  [window close];
  [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
  NSLog(@"BrowserDownloadTests passed");
  return 0;
}}
