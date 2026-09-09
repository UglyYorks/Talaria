#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// Presents the selected agent's durable notification feed; the owner handles I/O.
@interface TLNotificationsController : NSViewController
- (instancetype)initWithPalette:(TLThemePalette *)palette;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary *> *notifications;
@property (nonatomic, copy, nullable) void (^openHandler)(NSDictionary *notification);
@property (nonatomic, copy, nullable) void (^readHandler)(NSDictionary *notification, BOOL read);
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic) BOOL loading;
@end

NS_ASSUME_NONNULL_END
