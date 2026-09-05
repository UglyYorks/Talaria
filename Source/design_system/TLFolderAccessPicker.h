#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLFolderAccessPicker : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSString *> *folderPaths;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, strong, readonly) NSTableView *tableView;
@end

NS_ASSUME_NONNULL_END
