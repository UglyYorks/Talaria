#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
/// A system-rendered menu action with a lifetime bound to its menu item.
@interface TLActionMenuItem : NSMenuItem
+ (instancetype)itemWithTitle:(NSString *)title action:(dispatch_block_t)action;
@end
NS_ASSUME_NONNULL_END
