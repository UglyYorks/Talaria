#import "TLScreenCapture.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>

NSRect TLScreenCaptureRect(NSRect screenRect, NSRect primaryScreenFrame) {
  return NSIntegralRect(NSMakeRect(NSMinX(screenRect), NSMaxY(primaryScreenFrame) - NSMaxY(screenRect),
    NSWidth(screenRect), NSHeight(screenRect)));
}

@interface TLScreenCapture ()
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic) NSUInteger generation;
@end

@implementation TLScreenCapture
- (void)dealloc {
  if (_directory) [NSFileManager.defaultManager removeItemAtURL:_directory error:nil];
}
- (void)cancel {
  self.generation++;
}
- (void)captureRect:(NSRect)screenRect excludingWindowIDs:(NSArray<NSNumber *> *)windowIDs
         completion:(void (^)(NSURL *, NSError *))completion {
  [self cancel];
  NSUInteger generation = self.generation;
  if (NSIsEmptyRect(screenRect)) {
    completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError
      userInfo:@{NSLocalizedDescriptionKey:@"Select an area to capture."}]);
    return;
  }
  if (!CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess()) {
    completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:@{
      NSLocalizedDescriptionKey:@"Allow Talaria to capture your screen.",
      NSLocalizedRecoverySuggestionErrorKey:@"Enable Talaria in System Settings → Privacy & Security → Screen Recording, then try dragging an area again."}]);
    return;
  }
  if (!self.directory) self.directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
    URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
  NSRect rect = TLScreenCaptureRect(screenRect, NSScreen.screens.firstObject.frame);
  __weak typeof(self) weakSelf = self;
  [self captureImageInRect:rect excludingWindowIDs:windowIDs generation:generation
    completion:^(CGImageRef image, NSError *captureError) {
    NSData *data = image ? [[[NSBitmapImageRep alloc] initWithCGImage:image]
      representationUsingType:NSBitmapImageFileTypePNG properties:@{}] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.generation != generation) return;
      if (!data) {
        completion(nil, captureError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
          NSLocalizedDescriptionKey:@"The selected area could not be captured.",
          NSLocalizedRecoverySuggestionErrorKey:@"Check Talaria's Screen Recording permission in System Settings and try again."}]);
        return;
      }
      NSURL *folder = [owner.directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
      NSURL *URL = [folder URLByAppendingPathComponent:@"Screen capture.png"];
      NSError *error = nil;
      if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error] ||
          ![data writeToURL:URL options:NSDataWritingAtomic error:&error]) {
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
        completion(nil, error);
      } else completion(URL, nil);
    });
  }];
}

- (void)captureImageInRect:(NSRect)rect excludingWindowIDs:(NSArray<NSNumber *> *)windowIDs
               generation:(NSUInteger)generation completion:(void (^)(CGImageRef, NSError *))completion {
  NSSet<NSNumber *> *excludedIDs = [NSSet setWithArray:windowIDs];
  if (@available(macOS 14.0, *)) {
    __weak typeof(self) weakSelf = self;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
      completionHandler:^(SCShareableContent *content, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (!owner || owner.generation != generation) return;
        if (error) { completion(NULL, error); return; }
        SCDisplay *display = nil;
        for (SCDisplay *candidate in content.displays) {
          if (NSContainsRect(candidate.frame, rect)) { display = candidate; break; }
        }
        if (!display) { completion(NULL, nil); return; }
        NSMutableArray<SCWindow *> *excluded = [NSMutableArray array];
        for (SCWindow *window in content.windows) {
          if ([excludedIDs containsObject:@(window.windowID)]) [excluded addObject:window];
        }
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:excluded];
        SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
        configuration.sourceRect = NSOffsetRect(rect, -NSMinX(display.frame), -NSMinY(display.frame));
        configuration.width = MAX(1, lround(NSWidth(rect) * filter.pointPixelScale));
        configuration.height = MAX(1, lround(NSHeight(rect) * filter.pointPixelScale));
        configuration.showsCursor = NO;
        [SCScreenshotManager captureImageWithFilter:filter configuration:configuration completionHandler:completion];
      });
    }];
  } else {
    // macOS 13 predates SCScreenshotManager; composite the same window exclusions.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
      // Quartz expects raw window IDs in a CFArray with no object callbacks.
      CFMutableArrayRef included = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
      for (NSDictionary *window in windows) {
        NSNumber *identifier = window[(id)kCGWindowNumber];
        if (identifier && ![excludedIDs containsObject:identifier]) {
          CFArrayAppendValue(included, (const void *)(uintptr_t)identifier.unsignedIntValue);
        }
      }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      CGImageRef image = CGWindowListCreateImageFromArray(rect, included, kCGWindowImageBestResolution);
#pragma clang diagnostic pop
      CFRelease(included);
      completion(image, nil);
      if (image) CGImageRelease(image);
    });
  }
}
@end
