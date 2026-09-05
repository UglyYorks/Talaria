#import <Foundation/Foundation.h>
#import "TLCredentialStore.h"
#import "TLCredentialHelperProtocol.h"

int main(void) {
  @autoreleasepool {
    NSString *requirement = TLCredentialPeerRequirement(@"com.talaria.chat");
    if (!requirement) return 1;
    dispatch_queue_t queue = dispatch_queue_create(TL_CREDENTIAL_HELPER_SERVICE, DISPATCH_QUEUE_SERIAL);
    xpc_connection_t listener = xpc_connection_create_mach_service(TL_CREDENTIAL_HELPER_SERVICE,
      queue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!listener || xpc_connection_set_peer_code_signing_requirement(listener, requirement.UTF8String)) return 1;
    TLKeychainCredentialStore *store = [[TLKeychainCredentialStore alloc] init];
    xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
      if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) return;
      xpc_connection_set_target_queue(peer, queue);
      if (xpc_connection_set_peer_code_signing_requirement(peer, requirement.UTF8String)) {
        xpc_connection_cancel(peer);
        return;
      }
      xpc_connection_set_event_handler(peer, ^(xpc_object_t request) {
        @autoreleasepool {
          if (xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
          xpc_object_t reply = xpc_dictionary_create_reply(request);
          if (!reply) return;
          const char *operation = xpc_dictionary_get_string(request, "operation");
          NSError *error = nil;
          BOOL success = NO;
          // No service/account supplied by the caller can expand this scope.
          if (operation && strcmp(operation, "ping") == 0) {
            success = YES;
          } else if (operation && strcmp(operation, "read") == 0) {
            NSString *value = [store credentialForAccount:TLOpenRouterTokenCredentialAccount error:&error];
            success = error == nil;
            if (value) xpc_dictionary_set_string(reply, "value", value.UTF8String);
          } else if (operation && strcmp(operation, "write") == 0) {
            const char *value = xpc_dictionary_get_string(request, "value");
            if (value && strnlen(value, 65537) <= 65536) {
              NSString *credential = [NSString stringWithUTF8String:value];
              if (credential) success = [store setCredential:credential forAccount:TLOpenRouterTokenCredentialAccount error:&error];
            }
          } else if (operation && strcmp(operation, "delete") == 0) {
            success = [store removeCredentialForAccount:TLOpenRouterTokenCredentialAccount error:&error];
          }
          xpc_dictionary_set_bool(reply, "success", success);
          if (!success) {
            xpc_dictionary_set_int64(reply, "code", error ? error.code : errSecParam);
            xpc_dictionary_set_string(reply, "error", error.localizedDescription.UTF8String ?: "Invalid credential request.");
          }
          xpc_connection_send_message(peer, reply);
        }
      });
      xpc_connection_resume(peer);
    });
    xpc_connection_resume(listener);
    dispatch_main();
  }
}
