#import "TLFolderMounts.h"
#import <Virtualization/Virtualization.h>
#import <CommonCrypto/CommonDigest.h>

NSString *const TLFolderMountRoot = @"/mnt/mac";
NSString *const TLFolderMountTag = @"talaria-folders";

static NSString *TLFolderName(NSString *path) {
  NSString *name = [path isEqual:@"/"] ? @"root" : path.lastPathComponent;
  if ([path isEqual:NSHomeDirectory().stringByStandardizingPath]) name = @"home";
  name = [VZMultipleDirectoryShare canonicalizedNameFromName:name] ?: @"folder";
  // Reserve room for a collision suffix, including for long Unicode names.
  while ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 180)
    name = [name substringToIndex:[name rangeOfComposedCharacterSequenceAtIndex:name.length - 1].location];
  return name.length ? name : @"folder";
}

NSDictionary<NSString *, NSString *> *TLFolderMountPaths(NSArray<NSString *> *folders) {
  NSMutableSet *unique = [NSMutableSet set];
  for (id path in folders) if ([path isKindOfClass:NSString.class] && [path isAbsolutePath])
    [unique addObject:[path stringByStandardizingPath]];
  NSArray<NSString *> *paths = [unique.allObjects sortedArrayUsingSelector:@selector(compare:)];
  NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
  for (NSString *path in paths) {
    NSString *key = TLFolderName(path).lowercaseString;
    counts[key] = @([counts[key] unsignedIntegerValue] + 1);
  }
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  NSMutableSet *used = [NSMutableSet set];
  for (NSString *path in paths) {
    NSString *name = TLFolderName(path);
    if ([counts[name.lowercaseString] unsignedIntegerValue] > 1 || [used containsObject:name.lowercaseString]) {
      NSData *data = [path dataUsingEncoding:NSUTF8StringEncoding];
      unsigned char digest[CC_SHA256_DIGEST_LENGTH];
      CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
      NSMutableString *suffix = [NSMutableString string];
      for (NSUInteger i = 0; i < 6; i++) [suffix appendFormat:@"%02x", digest[i]];
      name = [name stringByAppendingFormat:@"-%@", suffix];
    }
    NSString *base = name;
    NSUInteger counter = 2;
    while ([used containsObject:name.lowercaseString]) name = [base stringByAppendingFormat:@"-%lu", (unsigned long)counter++];
    [used addObject:name.lowercaseString];
    result[path] = [TLFolderMountRoot stringByAppendingPathComponent:name];
  }
  return result;
}
