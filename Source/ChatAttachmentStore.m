#import "ChatAttachmentStore.h"

static BOOL TLAttachmentFailure(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"Talaria.Attachments" code:1
                                    userInfo:@{NSLocalizedDescriptionKey:message}];
  return NO;
}

static BOOL TLAttachmentSessionIsValid(NSString *sessionID) {
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" ];
  return sessionID.length > 0 && [sessionID rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

@interface TLChatAttachmentStore ()
@property (nonatomic, copy) NSURL *workspaceURL;
@end

@implementation TLChatAttachmentStore
- (instancetype)initWithWorkspaceURL:(NSURL *)workspaceURL {
  if ((self = [super init])) {
    NSURL *standard = workspaceURL.URLByStandardizingPath;
    _workspaceURL = [standard.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath URLByAppendingPathComponent:standard.lastPathComponent];
  }
  return self;
}

- (BOOL)ensureDirectory:(NSURL *)URL error:(NSError **)error {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSDictionary *attributes = [manager attributesOfItemAtPath:URL.path error:nil];
  if (attributes) {
    if (![attributes[NSFileType] isEqual:NSFileTypeDirectory])
      return TLAttachmentFailure(error, @"The attachment destination is not a regular directory.");
    return YES;
  }
  return [manager createDirectoryAtURL:URL withIntermediateDirectories:NO attributes:nil error:error];
}

// Walk rather than blindly copying directory trees: do not follow links or copy devices/sockets.
- (BOOL)copyItem:(NSURL *)source toURL:(NSURL *)destination error:(NSError **)error {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSDictionary *attributes = [manager attributesOfItemAtPath:source.path error:error];
  if (!attributes) return NO;
  NSString *type = attributes[NSFileType];
  if ([type isEqual:NSFileTypeRegular]) return [manager copyItemAtURL:source toURL:destination error:error];
  if (![type isEqual:NSFileTypeDirectory]) {
    return TLAttachmentFailure(error, [NSString stringWithFormat:@"“%@” is a symbolic link or special file. Attach regular files or folders instead.", source.lastPathComponent]);
  }
  if (![manager createDirectoryAtURL:destination withIntermediateDirectories:NO attributes:nil error:error]) return NO;
  NSArray<NSURL *> *children = [manager contentsOfDirectoryAtURL:source includingPropertiesForKeys:nil options:0 error:error];
  if (!children) return NO;
  for (NSURL *child in children) {
    if (![self copyItem:child toURL:[destination URLByAppendingPathComponent:child.lastPathComponent] error:error]) return NO;
  }
  return YES;
}

- (NSArray<NSDictionary<NSString *, id> *> *)copyURLs:(NSArray<NSURL *> *)URLs
                                           sessionID:(NSString *)sessionID error:(NSError **)error {
  if (!TLAttachmentSessionIsValid(sessionID)) {
    TLAttachmentFailure(error, @"A valid conversation is required before attaching files.");
    return nil;
  }
  if (URLs.count == 0) return @[];
  NSURL *root = [self.workspaceURL URLByAppendingPathComponent:@"attachments" isDirectory:YES];
  NSURL *session = [root URLByAppendingPathComponent:sessionID isDirectory:YES];
  // Check ancestors individually so a symlink cannot redirect writes outside the workspace.
  if (![self.workspaceURL.path isEqual:self.workspaceURL.URLByResolvingSymlinksInPath.path] ||
      ![self ensureDirectory:self.workspaceURL error:error] ||
      ![self ensureDirectory:root error:error] || ![self ensureDirectory:session error:error]) {
    if (error && !*error) TLAttachmentFailure(error, @"The attachment workspace contains a symbolic link.");
    return nil;
  }
  NSString *batchID = NSUUID.UUID.UUIDString;
  NSURL *pending = [session URLByAppendingPathComponent:[@".pending-" stringByAppendingString:batchID] isDirectory:YES];
  NSURL *final = [session URLByAppendingPathComponent:batchID isDirectory:YES];
  NSFileManager *manager = NSFileManager.defaultManager;
  if (![self ensureDirectory:pending error:error]) return nil;
  NSMutableArray *result = [NSMutableArray array];
  BOOL success = YES;
  for (NSURL *URL in URLs) {
    BOOL scoped = [URL startAccessingSecurityScopedResource];
    NSURL *source = URL.URLByStandardizingPath;
    NSString *sourcePath = source.URLByResolvingSymlinksInPath.path;
    // Copying a folder that contains the staging directory would recurse indefinitely.
    if (!URL.isFileURL || [pending.path hasPrefix:[sourcePath stringByAppendingString:@"/"]] || [sourcePath isEqual:@"/"]) {
      success = TLAttachmentFailure(error, @"This location contains the attachment workspace and cannot be attached.");
    } else {
      NSString *itemID = NSUUID.UUID.UUIDString;
      NSURL *itemDirectory = [pending URLByAppendingPathComponent:itemID isDirectory:YES];
      NSURL *destination = [itemDirectory URLByAppendingPathComponent:source.lastPathComponent];
      success = [self ensureDirectory:itemDirectory error:error] && [self copyItem:source toURL:destination error:error];
      if (success) {
        BOOL directory = NO;
        [manager fileExistsAtPath:destination.path isDirectory:&directory];
        NSString *guestPath = [NSString stringWithFormat:@"/workspace/attachments/%@/%@/%@/%@", sessionID, batchID, itemID, source.lastPathComponent];
        [result addObject:@{@"name":source.lastPathComponent, @"guestPath":guestPath, @"directory":@(directory)}];
      }
    }
    if (scoped) [URL stopAccessingSecurityScopedResource];
    if (!success) break;
  }
  if (success) success = [manager moveItemAtURL:pending toURL:final error:error];
  if (!success) {
    [manager removeItemAtURL:pending error:nil];
    return nil;
  }
  return result;
}

- (BOOL)removeAttachmentsForSessionID:(NSString *)sessionID error:(NSError **)error {
  if (!TLAttachmentSessionIsValid(sessionID)) return TLAttachmentFailure(error, @"Invalid attachment conversation.");
  NSURL *session = [[self.workspaceURL URLByAppendingPathComponent:@"attachments"] URLByAppendingPathComponent:sessionID];
  if (![session.path isEqual:session.URLByResolvingSymlinksInPath.path])
    return TLAttachmentFailure(error, @"The attachment directory contains a symbolic link.");
  if (![NSFileManager.defaultManager fileExistsAtPath:session.path]) return YES;
  return [NSFileManager.defaultManager removeItemAtURL:session error:error];
}
@end
