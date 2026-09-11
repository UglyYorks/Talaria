#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Discovery inspects installation/profile metadata only; secrets are read after Import.
@interface TLBrowserProfileImporter : NSObject
+ (NSArray<NSDictionary *> *)browserCatalogue;
+ (NSArray<NSDictionary *> *)installedBrowsers;
+ (NSArray<NSDictionary *> *)profilesForBrowser:(NSDictionary *)browser homeURL:(NSURL *)home;
+ (NSArray<NSDictionary *> *)profilesForBrowser:(NSDictionary *)browser homeURL:(NSURL *)home error:(NSError **)error;
/// Remember access explicitly granted through NSOpenPanel; never changes system permissions.
+ (BOOL)grantAccessToBrowser:(NSDictionary *)browser directoryURL:(NSURL *)URL error:(NSError **)error;
/// Synchronous IO; callers must use a background queue. Never modifies the source.
+ (nullable NSDictionary *)readProfile:(NSDictionary *)profile browser:(NSDictionary *)browser error:(NSError **)error;
+ (BOOL)stageLocalStorage:(NSDictionary<NSData *, NSData *> *)entries profileURL:(NSURL *)URL error:(NSError **)error;
+ (BOOL)stageLocalStorage:(NSDictionary<NSData *, NSData *> *)entries sessionCookies:(NSArray *)cookies profileURL:(NSURL *)URL error:(NSError **)error;
+ (nullable NSArray *)pendingSessionCookiesAtProfileURL:(NSURL *)URL error:(NSError **)error;
+ (BOOL)clearPendingSessionCookiesAtProfileURL:(NSURL *)URL error:(NSError **)error;
/// Decodes imported entries for document-start replay through WebKit's own storage API.
+ (nullable NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)pendingLocalStorageByOriginAtProfileURL:(NSURL *)URL error:(NSError **)error;
/// Acknowledge only after the matching origin's document has successfully applied its entries.
+ (BOOL)clearPendingLocalStorageForOrigin:(NSString *)origin profileURL:(NSURL *)URL error:(NSError **)error;
+ (BOOL)clearPendingLocalStorageAtProfileURL:(NSURL *)URL error:(NSError **)error;
/// Stages the previous Talaria profile once; source files are never modified.
+ (BOOL)prepareMigrationFromLegacyProfileAtProfileURL:(NSURL *)URL error:(NSError **)error;
/// Exposed for deterministic format tests; does not access Keychain.
+ (nullable NSData *)decryptCookie:(NSData *)encrypted password:(NSData *)password host:(NSString *)host version:(NSInteger)version;
@end
NS_ASSUME_NONNULL_END
