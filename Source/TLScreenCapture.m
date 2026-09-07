#import "TLScreenCapture.h"

NSRect TLScreenCaptureRect(NSRect screenRect, NSRect primaryScreenFrame) {
  return NSIntegralRect(NSMakeRect(NSMinX(screenRect), NSMaxY(primaryScreenFrame) - NSMaxY(screenRect),
    NSWidth(screenRect), NSHeight(screenRect)));
}

@interface TLScreenCapture ()
@property (nonatomic, strong) NSURL *directory;
@property (nonatomic, strong) NSTask *task;
@end

@implementation TLScreenCapture
- (void)dealloc {
  if (_task.running) [_task terminate];
  if (_directory) [NSFileManager.defaultManager removeItemAtURL:_directory error:nil];
}
- (void)cancel {
  if (self.task.running) [self.task terminate];
  self.task = nil;
}
- (void)captureRect:(NSRect)screenRect completion:(void (^)(NSURL *, NSError *))completion {
  [self cancel];
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
  NSURL *folder = [self.directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
  NSURL *URL = [folder URLByAppendingPathComponent:@"Screen capture.png"];
  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
    completion(nil, error);
    return;
  }
  NSRect rect = TLScreenCaptureRect(screenRect, NSScreen.screens.firstObject.frame);
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
  task.arguments = @[@"-x", @"-t", @"png", [NSString stringWithFormat:@"-R%.0f,%.0f,%.0f,%.0f",
    NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect)], URL.path];
  task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
  task.standardError = NSFileHandle.fileHandleWithNullDevice;
  self.task = task;
  __weak typeof(self) weakSelf = self;
  task.terminationHandler = ^(NSTask *finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.task != finished) {
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
        return;
      }
      owner.task = nil;
      NSImage *image = [[NSImage alloc] initWithContentsOfURL:URL];
      if (finished.terminationStatus == 0 && image.isValid) completion(URL, nil);
      else {
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
        completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
          NSLocalizedDescriptionKey:@"The selected area could not be captured.",
          NSLocalizedRecoverySuggestionErrorKey:@"Check Talaria's Screen Recording permission in System Settings and try again."}]);
      }
    });
  };
  if (![task launchAndReturnError:&error]) {
    self.task = nil;
    [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
    completion(nil, error);
  }
}
@end
