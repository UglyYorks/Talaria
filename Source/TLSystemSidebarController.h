#import <AppKit/AppKit.h>
#import "Theme.h"

@class TLNotificationsController;

NS_ASSUME_NONNULL_BEGIN

/// The sidebar's Projects and Notifications system tabs. The owner supplies Hermes data.
@interface TLSystemSidebarController : NSViewController
- (instancetype)initWithPalette:(TLThemePalette *)palette notifications:(TLNotificationsController *)notifications;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary *> *projects;
@property (nonatomic, copy, nullable) NSDictionary *selectedProject;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy, nullable) void (^projectHandler)(NSString *projectID);
@property (nonatomic, copy, nullable) void (^sessionHandler)(NSDictionary *session);
@end

NS_ASSUME_NONNULL_END
