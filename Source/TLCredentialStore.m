#import "TLCredentialStore.h"
#import <Security/Security.h>

NSString * const TLOpenRouterTokenCredentialAccount = @"openRouterToken";

static BOOL TLCheckKeychainStatus(OSStatus status, NSError **error) {
  if (status == errSecSuccess) {
    return YES;
  }
  if (error) {
    NSString *message = CFBridgingRelease(SecCopyErrorMessageString(status, NULL));
    *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{
      NSLocalizedDescriptionKey: message ?: @"Could not access the saved credential in Keychain."
    }];
  }
  return NO;
}

@interface TLKeychainCredentialStore ()
@property (nonatomic, copy) NSString *service;
@end

@implementation TLKeychainCredentialStore

- (instancetype)init {
  return [self initWithService:@"com.talaria.chat.credentials"];
}

- (instancetype)initWithService:(NSString *)service {
  self = [super init];
  if (self) {
    _service = [service copy];
  }
  return self;
}

- (NSDictionary *)queryForAccount:(NSString *)account {
  return @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService: self.service,
    (__bridge id)kSecAttrAccount: account,
    (__bridge id)kSecAttrSynchronizable: @NO
  };
}

- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error {
  NSMutableDictionary *query = [[self queryForAccount:account] mutableCopy];
  query[(__bridge id)kSecReturnData] = @YES;
  query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  NSData *data = CFBridgingRelease(result);
  if (status == errSecItemNotFound) {
    return nil;
  }
  if (!TLCheckKeychainStatus(status, error)) {
    return nil;
  }
  NSString *credential = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!credential) {
    TLCheckKeychainStatus(errSecDecode, error);
  }
  return credential;
}

- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error {
  NSDictionary *query = [self queryForAccount:account];
  NSDictionary *attributes = @{(__bridge id)kSecValueData: [credential dataUsingEncoding:NSUTF8StringEncoding]};
  OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
  if (status == errSecItemNotFound) {
    NSMutableDictionary *item = [query mutableCopy];
    [item addEntriesFromDictionary:attributes];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecDuplicateItem) {
      status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    }
  }
  return TLCheckKeychainStatus(status, error);
}

- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error {
  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self queryForAccount:account]);
  return status == errSecItemNotFound || TLCheckKeychainStatus(status, error);
}

@end
