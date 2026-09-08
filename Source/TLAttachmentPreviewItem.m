#import "TLAttachmentPreviewItem.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation TLAttachmentPreviewItem
- (NSURL *)previewItemURL { return self.URLResolver ? self.URLResolver() : nil; }
- (NSString *)previewItemTitle { return self.name; }
- (NSString *)detail {
  NSURL *URL = self.previewItemURL;
  if (!URL) return @"File unavailable";
  if (self.directory) return @"Folder";
  UTType *type = [UTType typeWithFilenameExtension:self.name.pathExtension];
  NSString *kind = type.localizedDescription ?: (self.name.pathExtension.length ? self.name.pathExtension.uppercaseString : @"File");
  NSNumber *size;
  [URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
  return size ? [NSString stringWithFormat:@"%@ · %@", kind, [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]] : kind;
}
- (BOOL)saveCopyToURL:(NSURL *)destination error:(NSError **)error {
  NSURL *source = self.previewItemURL;
  NSString *sourcePath = source.URLByResolvingSymlinksInPath.path;
  NSString *destinationPath = destination.URLByResolvingSymlinksInPath.path;
  NSString *failure = nil;
  if (!source) failure = @"The saved attachment is no longer available.";
  else if (!destination.isFileURL || [sourcePath isEqual:destinationPath] ||
           [destinationPath hasPrefix:[sourcePath stringByAppendingString:@"/"]]) failure = @"Choose a location outside the saved attachment.";
  if (failure) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.Attachments" code:1 userInfo:@{NSLocalizedDescriptionKey:failure}];
    return NO;
  }
  NSFileManager *manager = NSFileManager.defaultManager;
  NSURL *temporary = [destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".talaria-copy-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  BOOL success = [manager copyItemAtURL:source toURL:temporary error:error];
  if (success) {
    if ([manager fileExistsAtPath:destination.path]) success = [manager replaceItemAtURL:destination withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:error];
    else success = [manager moveItemAtURL:temporary toURL:destination error:error];
  }
  [manager removeItemAtURL:temporary error:nil];
  return success;
}
@end
