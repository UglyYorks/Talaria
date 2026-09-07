#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLSkillsPicker : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary *> *skills;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *changes;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL enabled;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy, nullable) void (^reloadHandler)(void);
@property (nonatomic, copy, nullable) void (^changesHandler)(void);
@property (nonatomic, strong, readonly) NSTableView *tableView;
@end

NS_ASSUME_NONNULL_END
