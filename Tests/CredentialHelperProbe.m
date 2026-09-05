#import "TLCredentialHelperProtocol.h"

// Integration probe intentionally supports only ping: never reads user secrets.
int main(int argc, const char **argv) { @autoreleasepool {
  BOOL expectAllowed = argc == 2 && strcmp(argv[1], "allow") == 0;
  NSString *requirement = TLCredentialPeerRequirement(TL_CREDENTIAL_HELPER_IDENTIFIER);
  if (!requirement) return 2;
  dispatch_queue_t queue = dispatch_queue_create("com.talaria.helper-probe", DISPATCH_QUEUE_SERIAL);
  xpc_connection_t connection = xpc_connection_create_mach_service(TL_CREDENTIAL_HELPER_SERVICE, queue, 0);
  if (xpc_connection_set_peer_code_signing_requirement(connection, requirement.UTF8String)) return 2;
  xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
  xpc_connection_resume(connection);
  xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
  xpc_dictionary_set_string(request, "operation", "ping");
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  __block BOOL allowed = NO;
  __block BOOL rejected = NO;
  xpc_connection_send_message_with_reply(connection, request, queue, ^(xpc_object_t reply) {
    allowed = xpc_get_type(reply) == XPC_TYPE_DICTIONARY && xpc_dictionary_get_bool(reply, "success");
    // A listener-side requirement rejection is reported as interrupted on some
    // macOS versions. Run an authorized ping afterward to distinguish downtime.
    rejected = reply == XPC_ERROR_PEER_CODE_SIGNING_REQUIREMENT || reply == XPC_ERROR_CONNECTION_INVALID || reply == XPC_ERROR_CONNECTION_INTERRUPTED;
    if (xpc_get_type(reply) == XPC_TYPE_ERROR) NSLog(@"Probe transport error: %s", xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION));
    dispatch_semaphore_signal(ready);
  });
  BOOL timeout = dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0;
  xpc_connection_cancel(connection);
  BOOL passed = !timeout && (expectAllowed ? allowed : rejected);
  NSLog(@"Credential helper %@ probe: %@", expectAllowed ? @"authorized" : @"unauthorized", passed ? @"passed" : @"FAILED");
  return passed ? 0 : 1;
} }
