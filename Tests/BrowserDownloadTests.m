#import <AppKit/AppKit.h>
#import "TLBrowserDownloadManager.h"
#import "TLDownloadsWindowController.h"
#import "design_system/TLDownloadRowView.h"
#import "design_system/TLThemedButton.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Update(TLBrowserDownloadManager *manager, NSUInteger identifier, TLBrowserDownloadState state, NSString *path, TLBrowserDownloadControl control) {
  [manager updateDownloadWithID:identifier browserIdentifier:7 URLString:@"https://example.com/report.pdf" fileName:@"Quarterly report.pdf" path:path
    receivedBytes:512000 totalBytes:1024000 bytesPerSecond:128000 state:state failureReason:state == TLBrowserDownloadStateFailed ? @"Network disconnected" : @"" control:control];
}
static NSButton *Button(TLDownloadRowView *row, NSString *title) {
  for (NSButton *button in [(NSStackView *)[row valueForKey:@"actions"] arrangedSubviews]) if ([button.title isEqual:title]) return button;
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
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
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
  TLDownloadsWindowController *window = [[TLDownloadsWindowController alloc] initWithManager:manager palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [window applyPalette:palette];
    for (NSNumber *width in @[@760, @494]) {
      [window.window setContentSize:NSMakeSize(width.doubleValue, 640)];
      [window.window.contentView layoutSubtreeIfNeeded];
      NSStackView *rows = [window valueForKey:@"rows"];
      Check(rows.arrangedSubviews.count == 3, @"download list includes all states");
      for (TLDownloadRowView *row in rows.arrangedSubviews) {
        Check(NSWidth(row.frame) > 400 && NSHeight(row.frame) > 100, @"download rows have readable layout at minimum width");
        for (NSButton *button in [(NSStackView *)[row valueForKey:@"actions"] arrangedSubviews]) {
          NSRect rect = [button convertRect:button.bounds toView:row];
          Check(NSMaxX(rect) <= NSWidth(row.bounds) && NSMinX(rect) >= 0 && NSMinY(rect) >= 0, @"all action buttons fit within the row");
          Check([button isKindOfClass:TLThemedButton.class], @"download actions use the shared themed control");
        }
      }
      TLDownloadRowView *completedRow = [[window valueForKey:@"rowViews"] objectForKey:firstID];
      Check(Button(completedRow,@"Open").enabled && Button(completedRow,@"Show in Finder").enabled, @"finished download offers file actions");
      NSView *root = window.window.contentView;
      NSBitmapImageRep *bitmap = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
      [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
      Check(ContainsColor(bitmap, palette.secondaryActionText) && ContainsColor(bitmap, palette.secondaryActionSurface), @"download buttons render paired foreground and surface in both themes");
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/downloads-%@-%@.png",theme,width] atomically:YES];
    }
  }
  [NSFileManager.defaultManager removeItemAtPath:firstPath error:nil];
  [window applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  TLDownloadRowView *completedRow = [[window valueForKey:@"rowViews"] objectForKey:firstID];
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
  [window.window close];
  [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
  NSLog(@"BrowserDownloadTests passed");
  return 0;
}}
