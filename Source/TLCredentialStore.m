#import "TLCredentialStore.h"
#import <Security/Security.h>
#import "TLCredentialHelperProtocol.h"

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

- (BOOL)usesCredentialHelper {
#ifdef TL_CREDENTIAL_HELPER_BUILD
  return NO;
#else
  return [self.service isEqualToString:@"com.talaria.chat.credentials"];
#endif
}

- (NSDictionary *)helperRequest:(const char *)operation credential:(NSString *)credential error:(NSError **)error {
  NSString *requirement = TLCredentialPeerRequirement(TL_CREDENTIAL_HELPER_IDENTIFIER);
  if (!requirement) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.CredentialHelper" code:1 userInfo:@{
      NSLocalizedDescriptionKey:@"Credential access requires a certificate-signed Talaria build."}];
    return nil;
  }
  dispatch_queue_t queue = dispatch_queue_create("com.talaria.chat.credentials-client", DISPATCH_QUEUE_SERIAL);
  xpc_connection_t connection = xpc_connection_create_mach_service(TL_CREDENTIAL_HELPER_SERVICE, queue, 0);
  if (xpc_connection_set_peer_code_signing_requirement(connection, requirement.UTF8String)) {
    xpc_connection_cancel(connection);
    TLCheckKeychainStatus(errSecCSReqFailed, error);
    return nil;
  }
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
  xpc_connection_resume(connection);
  xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
  xpc_dictionary_set_string(request, "operation", operation);
  if (credential) xpc_dictionary_set_string(request, "value", credential.UTF8String);
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  __block xpc_object_t response;
  xpc_connection_send_message_with_reply(connection, request, queue, ^(xpc_object_t reply) {
    response = reply;
    dispatch_semaphore_signal(ready);
  });
  // Leave time for the user to approve the helper in the native Keychain UI.
  BOOL timedOut = dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) != 0;
  xpc_connection_cancel(connection);
  if (timedOut || !response || xpc_get_type(response) != XPC_TYPE_DICTIONARY) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.CredentialHelper" code:2 userInfo:@{
      NSLocalizedDescriptionKey:timedOut ? @"Credential helper timed out. Approve access in the macOS Keychain dialog, then retry."
        : @"Could not connect to the trusted credential helper. Run make install-credential-helper with the app's signing identity."}];
    return nil;
  }
  if (!xpc_dictionary_get_bool(response, "success")) {
    const char *message = xpc_dictionary_get_string(response, "error");
    if (error) *error = [NSError errorWithDomain:@"Talaria.CredentialHelper"
      code:xpc_dictionary_get_int64(response, "code") userInfo:@{
        NSLocalizedDescriptionKey:message ? [NSString stringWithUTF8String:message] : @"Credential helper failed."}];
    return nil;
  }
  const char *value = xpc_dictionary_get_string(response, "value");
  return value ? @{@"value":[NSString stringWithUTF8String:value]} : @{};
}

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
  if ([self usesCredentialHelper]) {
    if (![account isEqualToString:TLOpenRouterTokenCredentialAccount]) { TLCheckKeychainStatus(errSecParam, error); return nil; }
    return [self helperRequest:"read" credential:nil error:error][@"value"];
  }
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
  if ([self usesCredentialHelper]) {
    if (![account isEqualToString:TLOpenRouterTokenCredentialAccount]) return TLCheckKeychainStatus(errSecParam, error);
    return [self helperRequest:"write" credential:credential error:error] != nil;
  }
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
  if ([self usesCredentialHelper]) {
    if (![account isEqualToString:TLOpenRouterTokenCredentialAccount]) return TLCheckKeychainStatus(errSecParam, error);
    return [self helperRequest:"delete" credential:nil error:error] != nil;
  }
  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self queryForAccount:account]);
  return status == errSecItemNotFound || TLCheckKeychainStatus(status, error);
}

@end
