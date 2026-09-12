#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLFolderAccessPicker : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSString *> *folderPaths;
// Preview paths use the same mapping as VM configuration.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *mountPaths;
// nil means stopped; an empty dictionary means running without shared folders.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *activeMountPaths;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, strong, readonly) NSTableView *tableView;
@end

NS_ASSUME_NONNULL_END
