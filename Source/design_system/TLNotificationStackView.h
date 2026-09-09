#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// One task's notifications, with a compact card stack and an expanded inbox.
@interface TLNotificationStackView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary *> *notifications;
@property (nonatomic, getter=isExpanded) BOOL expanded;
@property (nonatomic, copy, nullable) void (^openHandler)(NSDictionary *notification);
@property (nonatomic, copy, nullable) void (^readHandler)(NSDictionary *notification, BOOL read);
@property (nonatomic, copy, nullable) void (^expansionChanged)(BOOL expanded);
@property (nonatomic, readonly) NSUInteger unreadCount;
/// Shared ordering keeps collapsed representatives and expanded items consistent.
+ (NSArray<NSDictionary *> *)orderedNotifications:(NSArray<NSDictionary *> *)notifications;
@end

NS_ASSUME_NONNULL_END
