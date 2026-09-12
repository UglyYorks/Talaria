#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const TLFolderMountRoot;
FOUNDATION_EXPORT NSString *const TLFolderMountTag;
// The same mapping drives the VM export and the folder picker preview.
NSDictionary<NSString *, NSString *> *TLFolderMountPaths(NSArray<NSString *> *folders);
NS_ASSUME_NONNULL_END
