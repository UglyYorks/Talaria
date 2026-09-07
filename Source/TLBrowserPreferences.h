#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSNotificationName const TLBrowserPreferencesDidChangeNotification;
/// The settings catalogue is also the allowlist at the native/Chromium boundary.
@protocol TLBrowserPreferencesService <NSObject>
- (void)prepareInWindow:(nullable NSWindow *)window completion:(void (^)(NSError * _Nullable))completion;
- (NSDictionary *)stateForSetting:(NSDictionary *)setting;
- (BOOL)saveValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error;
- (void)clearData:(NSString *)kind completion:(void (^)(NSError * _Nullable))completion;
- (BOOL)resetDefaults:(NSError **)error;
@end
@interface TLBrowserPreferences : NSObject <TLBrowserPreferencesService>
+ (instancetype)sharedPreferences;
+ (NSArray<NSDictionary *> *)catalogue;
+ (NSArray<NSString *> *)categories;
+ (nullable NSDictionary *)settingWithID:(NSString *)identifier;
+ (NSURL *)profileURL;
- (instancetype)initWithProfileURL:(NSURL *)URL;
- (id)localValue:(NSString *)identifier;
- (BOOL)validateValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error;
- (nullable NSURL *)searchURLForText:(NSString *)text;
- (NSArray<NSURL *> *)startupURLs;
@end
NS_ASSUME_NONNULL_END
