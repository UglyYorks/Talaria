#import "AgentClient.h"
#import "AgentVMService.h"
#import "AgentModel.h"
#import <Virtualization/Virtualization.h>

static NSString * const TLAgentClientErrorDomain = @"Talaria.AgentClient";
static uint32_t const TLAgentWorkerPort = 7047;
static NSTimeInterval const TLAgentWorkerConnectionTimeout = 30.0;

static NSError *TLAgentClientError(NSString *message) {
  return [NSError errorWithDomain:TLAgentClientErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

typedef void (^TLBundledAgentRequestReleaseHandler)(id request);

@interface TLBundledAgentRequest : NSObject

@property (nonatomic, strong) VZVirtioSocketConnection *connection;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSMutableData *outputBuffer;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy, nullable) TLAgentStreamDeltaHandler deltaHandler;
@property (nonatomic, copy, nullable) TLAgentStreamCompletionHandler streamCompletion;
@property (nonatomic, copy, nullable) TLAgentModelCatalogueHandler modelCompletion;
@property (nonatomic, copy) TLBundledAgentRequestReleaseHandler releaseHandler;
@property (nonatomic) BOOL finished;
@property (nonatomic) BOOL receivedTerminalEvent;

- (BOOL)startWithConnection:(VZVirtioSocketConnection *)connection
                    payload:(NSDictionary *)payload
                  operation:(NSString *)operation
                      error:(NSError **)error;
- (void)finishWithError:(NSError *)error models:(NSArray<TLAgentModel *> *)models;

@end

@interface TLBundledAgentClient ()

@property (nonatomic, strong) TLAgentVMService *vmService;
@property (nonatomic, strong) NSMutableSet<TLBundledAgentRequest *> *activeRequests;

@end

@implementation TLBundledAgentRequest

- (instancetype)init {
  self = [super init];
  if (self) {
    _outputBuffer = [NSMutableData data];
    _operation = @"";
  }
  return self;
}

- (BOOL)startWithConnection:(VZVirtioSocketConnection *)connection
                    payload:(NSDictionary *)payload
                  operation:(NSString *)operation
                      error:(NSError **)error {
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
  if (!payloadData) {
    return NO;
  }
  if (connection.fileDescriptor < 0) {
    if (error) {
      *error = TLAgentClientError(@"Agent VM socket is closed.");
    }
    return NO;
  }

  self.operation = operation;
  self.connection = connection;
  self.fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:connection.fileDescriptor closeOnDealloc:NO];

  __weak typeof(self) weakSelf = self;
  self.fileHandle.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    TLBundledAgentRequest *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if (data.length == 0) {
      if (!strongSelf.receivedTerminalEvent) {
        [strongSelf finishWithError:TLAgentClientError(@"Agent VM closed the socket before completing the request.") models:nil];
      }
      return;
    }

    [strongSelf appendOutputData:data];
  };

  NSMutableData *inputData = [payloadData mutableCopy];
  [inputData appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  @try {
    [self.fileHandle writeData:inputData];
  } @catch (NSException *exception) {
    if (error) {
      *error = TLAgentClientError(exception.reason ?: @"Could not write to the agent VM socket.");
    }
    [self closeConnection];
    return NO;
  }

  return YES;
}

- (void)appendOutputData:(NSData *)data {
  @synchronized (self) {
    [self.outputBuffer appendData:data];
    [self processOutputBuffer];
  }
}

- (void)processOutputBuffer {
  while (true) {
    const unsigned char *bytes = self.outputBuffer.bytes;
    NSUInteger length = self.outputBuffer.length;
    NSUInteger newlineIndex = NSNotFound;

    for (NSUInteger index = 0; index < length; index += 1) {
      if (bytes[index] == '\n') {
        newlineIndex = index;
        break;
      }
    }

    if (newlineIndex == NSNotFound) {
      break;
    }

    NSData *lineData = [self.outputBuffer subdataWithRange:NSMakeRange(0, newlineIndex)];
    [self.outputBuffer replaceBytesInRange:NSMakeRange(0, newlineIndex + 1) withBytes:NULL length:0];
    if (lineData.length == 0) {
      continue;
    }

    [self processOutputLineData:lineData];
    if (self.finished) {
      break;
    }
  }
}

- (void)processOutputLineData:(NSData *)lineData {
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:&error];
  if (![json isKindOfClass:NSDictionary.class]) {
    [self finishWithError:TLAgentClientError(error.localizedDescription ?: @"Agent VM returned an invalid response.") models:nil];
    return;
  }

  NSDictionary *event = (NSDictionary *)json;
  NSString *type = [event[@"type"] isKindOfClass:NSString.class] ? event[@"type"] : @"";
  if ([type isEqualToString:@"delta"]) {
    [self emitDelta:event];
    return;
  }

  if ([type isEqualToString:@"models"]) {
    NSArray<TLAgentModel *> *models = [self modelsFromEvent:event error:&error];
    [self finishWithError:error models:models];
    return;
  }

  if ([type isEqualToString:@"complete"]) {
    [self finishWithError:nil models:nil];
    return;
  }

  if ([type isEqualToString:@"error"]) {
    NSString *message = [event[@"message"] isKindOfClass:NSString.class] ? event[@"message"] : @"Agent VM request failed.";
    [self finishWithError:TLAgentClientError(message) models:nil];
    return;
  }
}

- (void)emitDelta:(NSDictionary *)event {
  NSString *requestID = [event[@"request_id"] isKindOfClass:NSString.class] ? event[@"request_id"] : @"";
  NSString *kindString = [event[@"kind"] isKindOfClass:NSString.class] ? event[@"kind"] : @"";
  NSString *text = [event[@"text"] isKindOfClass:NSString.class] ? event[@"text"] : @"";
  if (requestID.length == 0 || !self.deltaHandler) {
    return;
  }

  TLAgentStreamDeltaKind kind;
  if ([kindString isEqualToString:@"thinking"]) kind = TLAgentStreamDeltaKindThinking;
  else if ([kindString isEqualToString:@"status"]) kind = TLAgentStreamDeltaKindStatus;
  else if ([kindString isEqualToString:@"approval"]) kind = TLAgentStreamDeltaKindApproval;
  else if ([kindString isEqualToString:@"tool_activity"]) kind = TLAgentStreamDeltaKindToolActivity;
  else if ([kindString isEqualToString:@"content"]) kind = TLAgentStreamDeltaKindContent;
  else return;
  if (text.length == 0 && kind != TLAgentStreamDeltaKindStatus) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.deltaHandler(requestID, kind, text);
  });
}

- (NSArray<TLAgentModel *> *)modelsFromEvent:(NSDictionary *)event error:(NSError **)error {
  NSDictionary *response = [event[@"response"] isKindOfClass:NSDictionary.class] ? event[@"response"] : nil;
  if (!response) {
    if (error) {
      *error = TLAgentClientError(@"Agent VM returned a model catalogue response without data.");
    }
    return nil;
  }

  NSData *responseData = [NSJSONSerialization dataWithJSONObject:response options:0 error:error];
  if (!responseData) {
    return nil;
  }

  return TLParseHermesModelOptions(responseData, error);
}

- (void)finishWithError:(NSError *)error models:(NSArray<TLAgentModel *> *)models {
  @synchronized (self) {
    if (self.finished) {
      return;
    }

    self.finished = YES;
    self.receivedTerminalEvent = YES;
    [self closeConnection];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.modelCompletion) {
      self.modelCompletion(models, error);
    } else if (self.streamCompletion) {
      self.streamCompletion(error);
    }
    if (self.releaseHandler) {
      self.releaseHandler(self);
    }
  });
}

- (void)closeConnection {
  self.fileHandle.readabilityHandler = nil;
  [self.connection close];
  self.fileHandle = nil;
  self.connection = nil;
}

@end

@implementation TLBundledAgentClient

- (instancetype)initWithVMService:(TLAgentVMService *)vmService {
  self = [super init];
  if (self) {
    _vmService = vmService;
    _activeRequests = [NSMutableSet set];
  }
  return self;
}

- (void)hermesProvidersWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                   completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent
                    payload:@{@"operation": @"hermes_providers", @"request_id": requestID,
                              @"params": parameters}
                  operation:@"hermes_providers"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID]) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id result = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                               options:0 error:&parseError];
    if (![result isKindOfClass:NSDictionary.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned invalid provider data."));
      return;
    }
    completion(result, nil);
  } modelCompletion:nil];
}

- (void)hermesAutomationsWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                        token:(NSString *)token model:(NSString *)model
                   completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent
                    payload:@{@"operation": @"hermes_automations", @"request_id": requestID,
                              @"params": parameters,
                              @"token": token ?: @"", @"model": model ?: @""}
                  operation:@"hermes_automations"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID]) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id result = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                               options:0 error:&parseError];
    if (![result isKindOfClass:NSDictionary.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned invalid automation data."));
      return;
    }
    completion(result, nil);
  } modelCompletion:nil];
}

- (void)hermesCredentialsWithAgent:(TLAgentRecord *)agent action:(NSString *)action
                              key:(NSString *)key value:(NSString *)value token:(NSString *)token
                   completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent
                    payload:@{@"operation": @"hermes_credentials", @"request_id": requestID,
                              @"action": action, @"key": key ?: @"", @"value": value ?: @"",
                              @"token": token ?: @""}
                  operation:@"hermes_credentials"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID]) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id result = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                               options:0 error:&parseError];
    if (![result isKindOfClass:NSDictionary.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned invalid credential data."));
      return;
    }
    completion(result, nil);
  } modelCompletion:nil];
}

- (void)hermesSkillsWithAgent:(TLAgentRecord *)agent changes:(NSDictionary<NSString *, NSNumber *> *)changes
                  completion:(void (^)(NSDictionary *, NSError *))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableDictionary *payload = [@{@"operation": @"hermes_skills", @"request_id": requestID} mutableCopy];
  if (changes) payload[@"changes"] = changes;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent payload:payload operation:@"hermes_skills"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID] && kind == TLAgentStreamDeltaKindContent) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id result = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                               options:0 error:&parseError];
    if (![result isKindOfClass:NSDictionary.class] || ![result[@"skills"] isKindOfClass:NSArray.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned an invalid skill catalogue."));
      return;
    }
    for (id skill in result[@"skills"]) {
      if (![skill isKindOfClass:NSDictionary.class] || ![skill[@"name"] isKindOfClass:NSString.class] ||
          ![skill[@"name"] length] || ![skill[@"enabled"] isKindOfClass:NSNumber.class] ||
          ![skill[@"locked_reason"] isKindOfClass:NSString.class] ||
          ![skill[@"description"] isKindOfClass:NSString.class]) {
        completion(nil, TLAgentClientError(@"Hermes returned an invalid skill catalogue."));
        return;
      }
    }
    completion(result, nil);
  } modelCompletion:nil];
}

- (void)hermesHistoryWithAgent:(TLAgentRecord *)agent action:(NSString *)action sessionID:(NSString *)sessionID
                        token:(NSString *)token model:(NSString *)model
                   completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent
                    payload:@{@"operation": @"hermes_history", @"request_id": requestID,
                              @"action": action, @"session_id": sessionID ?: @"",
                              @"token": token ?: @"", @"model": model ?: @""}
                  operation:@"hermes_history"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID]) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id result = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                               options:0 error:&parseError];
    if (![result isKindOfClass:NSDictionary.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned invalid history data."));
      return;
    }
    completion(result, nil);
  } modelCompletion:nil];
}

- (void)fetchHermesCommandsWithAgent:(TLAgentRecord *)agent
                              token:(NSString *)token
                              model:(NSString *)model
                         completion:(void (^)(NSDictionary *, NSError *))completion {
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent
                    payload:@{@"operation": @"hermes_commands", @"request_id": requestID,
                              @"token": token ?: @"", @"model": model ?: @""}
                  operation:@"hermes_commands"
                      delta:^(NSString *deltaID, TLAgentStreamDeltaKind kind, NSString *text) {
    if ([deltaID isEqualToString:requestID]) [response appendString:text];
  } streamCompletion:^(NSError *error) {
    if (error) { completion(nil, error); return; }
    NSError *parseError = nil;
    id catalogue = [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding]
                                                 options:0 error:&parseError];
    if (![catalogue isKindOfClass:NSDictionary.class] || ![catalogue[@"pairs"] isKindOfClass:NSArray.class]) {
      completion(nil, parseError ?: TLAgentClientError(@"Hermes returned an invalid command catalogue."));
      return;
    }
    completion(catalogue, nil);
  } modelCompletion:nil];
}

- (void)streamHermesSessionWithAgent:(TLAgentRecord *)agent
                           requestID:(NSString *)requestID
                           sessionID:(NSString *)sessionID
                               token:(NSString *)token
                               model:(NSString *)model
                              prompt:(NSString *)prompt
                               delta:(TLAgentStreamDeltaHandler)delta
                          completion:(TLAgentStreamCompletionHandler)completion {
  [self streamHermesSessionWithAgent:agent requestID:requestID sessionID:sessionID token:token model:model
                            prompt:prompt approvalResponse:nil delta:delta completion:completion];
}

- (void)streamHermesSessionWithAgent:(TLAgentRecord *)agent requestID:(NSString *)requestID
                          sessionID:(NSString *)sessionID token:(NSString *)token model:(NSString *)model
                             prompt:(NSString *)prompt approvalResponse:(NSDictionary *)approvalResponse
                              delta:(TLAgentStreamDeltaHandler)delta completion:(TLAgentStreamCompletionHandler)completion {
  NSMutableDictionary *payload = [@{
    @"operation": @"hermes_session_chat",
    @"wait_for_previous_turn": @YES,
    @"request_id": requestID ?: @"",
    @"session_id": sessionID ?: @"",
    @"token": token ?: @"",
    @"model": model ?: @"",
    @"prompt": prompt ?: @"",
    @"soul": agent.soul ?: @"",
  } mutableCopy];
  if (approvalResponse) payload[@"approval_response"] = approvalResponse;
  [self startWorkerWithAgent:agent payload:payload operation:@"hermes_session_chat"
                       delta:delta streamCompletion:completion modelCompletion:nil];
}

- (void)selectHermesModelWithAgent:(TLAgentRecord *)agent sessionID:(NSString *)sessionID
                           token:(NSString *)token model:(NSString *)model
                      completion:(TLAgentStreamCompletionHandler)completion {
  NSDictionary *payload = @{@"operation": @"hermes_select_model", @"request_id": NSUUID.UUID.UUIDString,
    @"session_id": sessionID, @"token": token, @"model": model};
  [self startWorkerWithAgent:agent payload:payload operation:@"hermes_select_model"
    delta:^(NSString *requestID, TLAgentStreamDeltaKind kind, NSString *text) {}
    streamCompletion:completion modelCompletion:nil];
}

- (void)installHermesWithAgent:(TLAgentRecord *)agent
                     requestID:(NSString *)requestID
                      progress:(TLAgentStreamDeltaHandler)progress
                    completion:(TLAgentStreamCompletionHandler)completion {
  NSDictionary *payload = @{
    @"operation": @"install_hermes",
    @"soul": agent.soul ?: @"",
    @"request_id": requestID ?: @"install",
  };
  [self startWorkerWithAgent:agent payload:payload operation:@"install_hermes"
                       delta:progress streamCompletion:completion modelCompletion:nil];
}

- (void)runShellCommandWithAgent:(TLAgentRecord *)agent
                       requestID:(NSString *)requestID
                       sessionID:(NSString *)sessionID
                         command:(NSString *)command
                          output:(TLAgentStreamDeltaHandler)output
                      completion:(TLAgentStreamCompletionHandler)completion {
  NSDictionary *payload = @{
    @"operation": @"shell_command",
    @"request_id": requestID ?: @"",
    @"session_id": sessionID ?: @"",
    @"command": command ?: @"",
  };
  [self startWorkerWithAgent:agent payload:payload operation:@"shell_command"
                       delta:output streamCompletion:completion modelCompletion:nil];
}

- (void)generateHermesTextWithAgent:(TLAgentRecord *)agent
                          requestID:(NSString *)requestID
                              token:(NSString *)token
                              model:(NSString *)model
                       instructions:(NSString *)instructions
                              input:(NSString *)input
                              delta:(TLAgentStreamDeltaHandler)delta
                         completion:(TLAgentStreamCompletionHandler)completion {
  NSDictionary *payload = @{@"operation": @"hermes_generate_text", @"request_id": requestID ?: @"",
                            @"token": token ?: @"", @"model": model ?: @"",
                            @"instructions": instructions ?: @"", @"input": input ?: @""};
  [self startWorkerWithAgent:agent payload:payload operation:@"hermes_generate_text"
                      delta:delta streamCompletion:completion modelCompletion:nil];
}

- (void)cancelChatWithRequestID:(NSString *)requestID {
  for (TLBundledAgentRequest *request in self.activeRequests.copy) {
    if ([request.requestID isEqualToString:requestID]) {
      // Closing this request's socket signals cancellation to the guest worker.
      [request finishWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil] models:nil];
    }
  }
}

- (void)fetchModelCatalogueWithAgent:(TLAgentRecord *)agent
                                token:(NSString *)token
                           completion:(TLAgentModelCatalogueHandler)completion {
  NSDictionary *payload = @{
    @"operation": @"models",
    @"token": token ?: @"",
    @"agent": [self dictionaryForAgent:agent],
  };

  [self startWorkerWithAgent:agent
                     payload:payload
                   operation:@"models"
                       delta:nil
            streamCompletion:nil
             modelCompletion:completion];
}

- (void)startWorkerWithAgent:(TLAgentRecord *)agent
                     payload:(NSDictionary *)payload
                   operation:(NSString *)operation
                       delta:(TLAgentStreamDeltaHandler)delta
            streamCompletion:(TLAgentStreamCompletionHandler)streamCompletion
             modelCompletion:(TLAgentModelCatalogueHandler)modelCompletion {
  if (!agent) {
    [self completeStreamCompletion:streamCompletion
                   modelCompletion:modelCompletion
                            models:nil
                             error:TLAgentClientError(@"Agent VM is missing.")];
    return;
  }

  // Register before connecting so Stop also cancels a request waiting for its socket.
  TLBundledAgentRequest *request = [[TLBundledAgentRequest alloc] init];
  request.requestID = payload[@"request_id"];
  request.deltaHandler = delta;
  request.streamCompletion = streamCompletion;
  request.modelCompletion = modelCompletion;
  __weak typeof(self) weakSelf = self;
  request.releaseHandler = ^(id finishedRequest) {
    [weakSelf.activeRequests removeObject:finishedRequest];
  };
  [self.activeRequests addObject:request];
  [self.vmService connectToAgent:agent port:TLAgentWorkerPort timeout:TLAgentWorkerConnectionTimeout completion:^(VZVirtioSocketConnection *connection, NSError *error) {
    if (request.finished) { [connection close]; return; }
    if (!connection) {
      [request finishWithError:error ?: TLAgentClientError(@"Could not connect to the agent VM.") models:nil];
      return;
    }
    NSError *startError = nil;
    if (![request startWithConnection:connection payload:payload operation:operation error:&startError]) {
      [request finishWithError:startError ?: TLAgentClientError(@"Could not start the agent VM request.") models:nil];
    }
  }];
}

- (void)completeStreamCompletion:(TLAgentStreamCompletionHandler)streamCompletion
                 modelCompletion:(TLAgentModelCatalogueHandler)modelCompletion
                          models:(NSArray<TLAgentModel *> *)models
                           error:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (modelCompletion) {
      modelCompletion(models, error);
    } else if (streamCompletion) {
      streamCompletion(error);
    }
  });
}

- (NSDictionary *)dictionaryForAgent:(TLAgentRecord *)agent {
  return @{
    @"id": @(agent.agentID),
    @"name": agent.name ?: @"",
    @"guest_kind": agent.guestKind ?: @"",
    @"runtime": agent.runtime ?: @"",
    @"status": agent.status ?: @"",
    @"vm_directory": agent.vmDirectory ?: @"",
  };
}

@end
