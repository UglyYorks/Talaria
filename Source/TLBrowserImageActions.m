#import "TLBrowserImageActions.h"
#import "TLBrowserDownloadManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

BOOL TLBrowserImageURLIsSupported(NSURL *URL) {
  NSString *scheme = URL.scheme.lowercaseString;
  if ([scheme isEqual:@"http"] || [scheme isEqual:@"https"]) return URL.host.length > 0;
  NSString *value = URL.absoluteString.lowercaseString;
  return [value hasPrefix:@"data:image/"] || [value hasPrefix:@"blob:https://"] || [value hasPrefix:@"blob:http://"];
}
NSArray<NSString *> *TLBrowserImageMenuTitles(void) {
  return @[@"Open Image in New Tab", @"Open Image in New Window", @"Save Image to “Downloads”", @"Save Image As…",
    @"Add Image to Photos", @"Use Image as Desktop Wallpaper", @"Copy Image Address", @"Copy Image", @"Copy Subject", @"Look Up", @"Share…"];
}
@implementation TLBrowserImageResource
+ (instancetype)resourceWithData:(NSData *)data URL:(NSURL *)URL MIMEType:(NSString *)MIMEType {
  if (!data.length) return nil;
  NSImage *image = [[NSImage alloc] initWithData:data];
  UTType *type = [UTType typeWithMIMEType:MIMEType];
  if (!image && ![type conformsToType:UTTypeImage]) return nil;
  TLBrowserImageResource *resource = [self new]; resource.data = data; resource.image = image;
  NSString *name = ([URL.scheme.lowercaseString isEqual:@"http"] || [URL.scheme.lowercaseString isEqual:@"https"]) ? URL.lastPathComponent : @"image";
  name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\n\r\0"]] componentsJoinedByString:@"_"];
  if (!name.length || [name hasPrefix:@"."]) name = @"image";
  if (name.length > 180) name = [name substringToIndex:180];
  NSString *extension = type.preferredFilenameExtension;
  UTType *namedType = name.pathExtension.length ? [UTType typeWithFilenameExtension:name.pathExtension] : nil;
  if (extension.length && ![namedType isEqual:type]) name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
  resource.fileName = name;
  return resource;
}
@end

static void TLImagePresentError(NSError *error, NSWindow *window) {
  if (!error) return;
  if (window.isVisible) [NSApp presentError:error modalForWindow:window delegate:nil didPresentSelector:NULL contextInfo:NULL];
  else [NSApp presentError:error];
}
static NSError *TLImageActionError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.BrowserImage" code:2 userInfo:@{NSLocalizedDescriptionKey:message}];
}

// AppKit delegates are weak; keep the operation alive until the service finishes.
@interface TLImageSharingOperation : NSObject <NSSharingServiceDelegate, NSSharingServicePickerDelegate>
@property NSSharingService *service;
@property NSSharingServicePicker *picker;
@property NSWindow *window;
@end
static NSMutableSet<TLImageSharingOperation *> *TLImageSharingOperations(void) {
  static NSMutableSet *operations; static dispatch_once_t once; dispatch_once(&once, ^{ operations = [NSMutableSet set]; }); return operations;
}
@implementation TLImageSharingOperation
- (id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)picker delegateForSharingService:(NSSharingService *)service { return self; }
- (void)sharingServicePicker:(NSSharingServicePicker *)picker didChooseSharingService:(NSSharingService *)service {
  self.service = service; self.picker = nil;
  if (!service) [TLImageSharingOperations() removeObject:self];
}
- (NSWindow *)sharingService:(NSSharingService *)service sourceWindowForShareItems:(NSArray *)items sharingContentScope:(NSSharingContentScope *)scope { return self.window; }
- (void)sharingService:(NSSharingService *)service didShareItems:(NSArray *)items { [TLImageSharingOperations() removeObject:self]; }
- (void)sharingService:(NSSharingService *)service didFailToShareItems:(NSArray *)items error:(NSError *)error {
  TLImagePresentError(error, self.window); [TLImageSharingOperations() removeObject:self];
}
@end

@implementation TLBrowserImageActions
+ (BOOL)copyImage:(NSImage *)image toPasteboard:(NSPasteboard *)pasteboard {
  if (!image) return NO;
  [pasteboard clearContents]; return [pasteboard writeObjects:@[image]];
}
+ (void)copySubjectOfImage:(NSImage *)image completion:(void (^)(NSImage *, NSError *))completion {
  CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
  if (!cgImage) { completion(nil, TLImageActionError(@"This image could not be copied.")); return; }
  CGImageRetain(cgImage);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil; NSImage *subject = nil;
    if (@available(macOS 14.0, *)) {
      VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
      VNGenerateForegroundInstanceMaskRequest *request = [VNGenerateForegroundInstanceMaskRequest new];
      if ([handler performRequests:@[request] error:&error]) {
        VNInstanceMaskObservation *observation = request.results.firstObject;
        if (observation.allInstances.count) {
          CVPixelBufferRef pixels = [observation generateMaskedImageOfInstances:observation.allInstances fromRequestHandler:handler croppedToInstancesExtent:YES error:&error];
          if (pixels) {
            CIImage *output = [CIImage imageWithCVPixelBuffer:pixels];
            CGImageRef result = [[CIContext contextWithOptions:nil] createCGImage:output fromRect:output.extent];
            if (result) { subject = [[NSImage alloc] initWithCGImage:result size:NSZeroSize]; CGImageRelease(result); }
            CVPixelBufferRelease(pixels);
          }
        }
      }
    }
    CGImageRelease(cgImage);
    if (!subject && !error) error = TLImageActionError(@"No subject could be found in this image.");
    dispatch_async(dispatch_get_main_queue(), ^{ completion(subject, error); });
  });
}
+ (void)saveResource:(TLBrowserImageResource *)resource URL:(NSURL *)URL destination:(NSURL *)destination
          overwrite:(BOOL)overwrite manager:(TLBrowserDownloadManager *)manager completion:(void (^)(NSError *))completion {
  // CEF uses uint32 download IDs. Native cached-image saves occupy a separate range.
  static NSUInteger nextID = (NSUInteger)UINT32_MAX + 1;
  NSUInteger downloadID = nextID++;
  if (!overwrite) destination = [NSURL fileURLWithPath:[manager reserveDestinationForDownloadID:downloadID
    directory:destination.URLByDeletingLastPathComponent.path fileName:destination.lastPathComponent]];
  [manager updateDownloadWithID:downloadID browserIdentifier:-1 URLString:URL.absoluteString fileName:destination.lastPathComponent
    path:destination.path receivedBytes:0 totalBytes:resource.data.length bytesPerSecond:0 state:TLBrowserDownloadStateDownloading failureReason:@"" control:nil];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    BOOL saved = [NSFileManager.defaultManager createDirectoryAtURL:destination.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error] &&
      [resource.data writeToURL:destination options:overwrite ? NSDataWritingAtomic : NSDataWritingWithoutOverwriting error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      [manager updateDownloadWithID:downloadID browserIdentifier:-1 URLString:URL.absoluteString fileName:destination.lastPathComponent
        path:destination.path receivedBytes:saved ? resource.data.length : 0 totalBytes:resource.data.length bytesPerSecond:0
        state:saved ? TLBrowserDownloadStateComplete : TLBrowserDownloadStateFailed failureReason:error.localizedDescription ?: @"" control:nil];
      completion(error);
    });
  });
}
+ (void)performAction:(TLBrowserImageAction)action resource:(TLBrowserImageResource *)resource URL:(NSURL *)URL fromView:(NSView *)view atPoint:(NSPoint)point {
  NSWindow *window = view.window;
  if (action == TLBrowserImageSaveDownloads || action == TLBrowserImageSaveAs) {
    void (^save)(NSURL *, BOOL) = ^(NSURL *destination, BOOL overwrite) {
      [self saveResource:resource URL:URL destination:destination overwrite:overwrite manager:TLBrowserDownloadManager.sharedManager
        completion:^(NSError *error) { TLImagePresentError(error, window); }];
    };
    NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    if (action == TLBrowserImageSaveDownloads) save([downloads URLByAppendingPathComponent:resource.fileName], NO);
    else {
      NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = resource.fileName;
      panel.directoryURL = downloads; panel.canCreateDirectories = YES;
      void (^chosen)(NSModalResponse) = ^(NSModalResponse response) { if (response == NSModalResponseOK && panel.URL) save(panel.URL, YES); };
      if (window) [panel beginSheetModalForWindow:window completionHandler:chosen]; else [panel beginWithCompletionHandler:chosen];
    }
    return;
  }
  if (!resource.image) { TLImagePresentError(TLImageActionError(@"This image format cannot be used for this action."), window); return; }
  if (action == TLBrowserImageCopy) { [self copyImage:resource.image toPasteboard:NSPasteboard.generalPasteboard]; return; }
  if (action == TLBrowserImageCopySubject) {
    [self copySubjectOfImage:resource.image completion:^(NSImage *subject, NSError *error) {
      if (subject) [self copyImage:subject toPasteboard:NSPasteboard.generalPasteboard]; else TLImagePresentError(error, window);
    }]; return;
  }
  TLImageSharingOperation *operation = [TLImageSharingOperation new]; operation.window = window;
  NSArray *items = @[resource.image];
  if (action == TLBrowserImageShare) {
    operation.picker = [[NSSharingServicePicker alloc] initWithItems:items]; operation.picker.delegate = operation;
    [TLImageSharingOperations() addObject:operation];
    [operation.picker showRelativeToRect:NSMakeRect(point.x, point.y, 1, 1) ofView:view preferredEdge:NSRectEdgeMinY];
  } else if (action == TLBrowserImageAddToPhotos || action == TLBrowserImageWallpaper) {
    operation.service = [NSSharingService sharingServiceNamed:action == TLBrowserImageAddToPhotos ? NSSharingServiceNameAddToIPhoto : NSSharingServiceNameUseAsDesktopPicture];
    if (![operation.service canPerformWithItems:items]) { TLImagePresentError(TLImageActionError(@"This image action is unavailable on this Mac."), window); return; }
    [TLImageSharingOperations() addObject:operation]; operation.service.delegate = operation;
    [operation.service performWithItems:items];
  }
}
@end
