#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TLOpenRouterTokenCredentialAccount;

@protocol TLCredentialStore <NSObject>

// A missing credential returns nil without an error. Removal is idempotent.
- (nullable NSString *)credentialForAccount:(NSString *)account error:(NSError **)error;
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error;
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error;

@end

@interface TLKeychainCredentialStore : NSObject <TLCredentialStore>

- (instancetype)init;
- (instancetype)initWithService:(NSString *)service NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
