#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const TLApplicationPreferencesDidChangeNotification;

@protocol TLLoginItemService <NSObject>
@property (readonly) SMAppServiceStatus status;
- (BOOL)registerAndReturnError:(NSError **)error;
- (BOOL)unregisterAndReturnError:(NSError **)error;
@end

@protocol TLGlobalShortcutRegistration <NSObject>
@property (nonatomic, copy, nullable) void (^handler)(void);
- (BOOL)registerShortcut:(nullable NSDictionary *)shortcut error:(NSError **)error;
@end

@interface TLApplicationPreferences : NSObject
@property (class, nonatomic, readonly) TLApplicationPreferences *sharedPreferences;
@property (nonatomic) BOOL notchEnabled;
@property (nonatomic) BOOL shortcutRecording;
@property (nonatomic, readonly) SMAppServiceStatus loginItemStatus;
@property (nonatomic, copy, readonly, nullable) NSDictionary *quickInputShortcut;
@property (nonatomic, copy, readonly, nullable) NSString *shortcutError;
@property (nonatomic, copy, nullable) void (^quickInputHandler)(void);
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults loginItem:(id<TLLoginItemService>)loginItem
           shortcutRegistration:(id<TLGlobalShortcutRegistration>)registration;
- (BOOL)setLaunchAtLogin:(BOOL)enabled error:(NSError **)error;
- (BOOL)setQuickInputShortcut:(nullable NSDictionary *)shortcut error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
