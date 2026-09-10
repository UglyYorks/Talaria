#import "AgentClient.h"
#import "TLAgentProtocol.h"
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
@property (nonatomic, strong) TLAgentFrameDecoder *decoder;
@property (nonatomic, strong) TLAgentJSONResult *JSONResult;
@property (nonatomic, copy) void (^resultCompletion)(NSDictionary *, NSError *);
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
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TLAgentRecord *> *incognitoAgents;
@property (nonatomic, strong) NSTimer *incognitoLeaseTimer;
@property (nonatomic) BOOL incognitoClosed;
@property (nonatomic, strong) NSMutableSet<TLBundledAgentRequest *> *activeRequests;

@end

@implementation TLBundledAgentRequest

- (instancetype)init {
  self = [super init];
  if (self) {
    _decoder = [TLAgentFrameDecoder new];
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
  self.decoder.requestID = self.requestID ?: @"";
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
    if (self.finished) return;
    NSError *error = nil;
    NSArray *events = [self.decoder appendData:data error:&error];
    if (!events) { [self finishWithError:error models:nil]; return; }
    for (NSDictionary *event in events) {
      [self processEvent:event];
      if (self.finished) break;
    }
  }
}

- (void)processEvent:(NSDictionary *)event {
  NSError *error = nil;
  NSString *type = [event[@"type"] isKindOfClass:NSString.class] ? event[@"type"] : @"";
  if ([type isEqualToString:@"result"]) {
    if (!self.JSONResult || self.JSONResult.result) {
      [self finishWithError:TLAgentClientError(@"Hermes returned an unexpected result.") models:nil];
      return;
    }
    self.JSONResult.result = event[@"result"];
    return;
  }
  if ([type isEqualToString:@"delta"]) {
    if (self.JSONResult && [event[@"kind"] isEqual:@"content"]) [self.JSONResult appendLegacyText:event[@"text"]];
    else [self emitDelta:event];
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
  id value = event[@"payload"] ?: text;
  if (text.length == 0 && kind != TLAgentStreamDeltaKindStatus && !event[@"payload"]) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.deltaHandler(requestID, kind, value);
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

  NSDictionary *result = nil;
  if (self.JSONResult && !error) result = [self.JSONResult finish:&error];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.resultCompletion) {
      self.resultCompletion(result, error);
    } else if (self.modelCompletion) {
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

- (void)closeIncognito {
  if (self.incognitoClosed || !self.incognitoID.length) return;
  self.incognitoClosed = YES;
  [self.incognitoLeaseTimer invalidate];
  for (TLBundledAgentRequest *request in self.activeRequests.copy)
    [request finishWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil] models:nil];
  for (TLAgentRecord *agent in self.incognitoAgents.allValues) {
    [self startWorkerWithAgent:agent payload:@{@"operation": @"incognito_close", @"request_id": NSUUID.UUID.UUIDString}
      operation:@"incognito_close" delta:nil streamCompletion:^(NSError *error) {} modelCompletion:nil];
  }
  [self.incognitoAgents removeAllObjects];
}

- (void)uploadIncognitoAttachments:(NSArray<NSDictionary *> *)files agent:(TLAgentRecord *)agent completion:(void (^)(NSArray *, NSError *))completion {
  NSMutableString *response = [NSMutableString string];
  [self startWorkerWithAgent:agent payload:@{@"operation": @"incognito_attachments", @"request_id": NSUUID.UUID.UUIDString, @"files": files}
    operation:@"incognito_attachments" delta:^(NSString *requestID, TLAgentStreamDeltaKind kind, NSString *text) { [response appendString:text]; }
    streamCompletion:^(NSError *error) {
      NSArray *rows = !error ? [NSJSONSerialization JSONObjectWithData:[response dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error] : nil;
      completion([rows isKindOfClass:NSArray.class] ? rows : nil, error);
    } modelCompletion:nil];
}

- (instancetype)initWithVMService:(TLAgentVMService *)vmService {
  self = [super init];
  if (self) {
    _vmService = vmService;
    _activeRequests = [NSMutableSet set];
  }
  return self;
}

- (void)performJSONOperation:(NSString *)operation agent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                    completion:(void (^)(NSDictionary *, NSError *))completion {
  NSMutableDictionary *payload = [parameters mutableCopy];
  payload[@"operation"] = operation;
  payload[@"request_id"] = NSUUID.UUID.UUIDString;
  [self startWorkerWithAgent:agent payload:payload operation:operation delta:nil streamCompletion:nil
            modelCompletion:nil resultCompletion:completion];
}

- (void)hermesProvidersWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                    completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_providers" agent:agent parameters:@{@"params":parameters} completion:completion];
}

- (void)hermesPluginsWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                        token:(NSString *)token model:(NSString *)model
                   completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_plugins" agent:agent
    parameters:@{@"params":parameters, @"token":token ?: @"", @"model":model ?: @""} completion:completion];
}

- (void)hermesNotificationsWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                        token:(NSString *)token model:(NSString *)model
                   completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_notifications" agent:agent
    parameters:@{@"params":parameters, @"token":token ?: @"", @"model":model ?: @""} completion:completion];
}

- (void)hermesAutomationsWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters
                           token:(NSString *)token model:(NSString *)model
                      completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_automations" agent:agent parameters:@{@"params":parameters,
    @"token":token ?: @"", @"model":model ?: @""} completion:completion];
}
- (void)hermesCredentialsWithAgent:(TLAgentRecord *)agent action:(NSString *)action key:(NSString *)key
                           value:(NSString *)value token:(NSString *)token
                      completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_credentials" agent:agent parameters:@{@"action":action,
    @"key":key ?: @"", @"value":value ?: @"", @"token":token ?: @""} completion:completion];
}
- (void)hermesSkillsWithAgent:(TLAgentRecord *)agent changes:(NSDictionary<NSString *, NSNumber *> *)changes
                  completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_skills" agent:agent parameters:changes ? @{@"changes":changes} : @{}
    completion:^(NSDictionary *result, NSError *error) {
      if (error) { completion(nil, error); return; }
      if (![result[@"skills"] isKindOfClass:NSArray.class]) {
        completion(nil, TLAgentClientError(@"Hermes returned an invalid skill catalogue.")); return;
      }
      for (id skill in result[@"skills"]) {
        if (![skill isKindOfClass:NSDictionary.class] || ![skill[@"name"] isKindOfClass:NSString.class] ||
            ![skill[@"name"] length] || ![skill[@"enabled"] isKindOfClass:NSNumber.class] ||
            ![skill[@"locked_reason"] isKindOfClass:NSString.class] || ![skill[@"description"] isKindOfClass:NSString.class]) {
          completion(nil, TLAgentClientError(@"Hermes returned an invalid skill catalogue.")); return;
        }
      }
      completion(result, nil);
    }];
}
- (void)hermesHistoryWithAgent:(TLAgentRecord *)agent action:(NSString *)action sessionID:(NSString *)sessionID
                        token:(NSString *)token model:(NSString *)model
                   completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_history" agent:agent parameters:@{@"action":action,
    @"session_id":sessionID ?: @"", @"token":token ?: @"", @"model":model ?: @""} completion:completion];
}
- (void)fetchHermesCommandsWithAgent:(TLAgentRecord *)agent token:(NSString *)token model:(NSString *)model
                         completion:(void (^)(NSDictionary *, NSError *))completion {
  [self performJSONOperation:@"hermes_commands" agent:agent parameters:@{@"token":token ?: @"", @"model":model ?: @""}
    completion:^(NSDictionary *result, NSError *error) {
      if (!error && ![result[@"pairs"] isKindOfClass:NSArray.class]) error = TLAgentClientError(@"Hermes returned an invalid command catalogue.");
      completion(error ? nil : result, error);
    }];
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
    delta:nil
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
  [self startWorkerWithAgent:agent payload:payload operation:operation delta:delta streamCompletion:streamCompletion
            modelCompletion:modelCompletion resultCompletion:nil];
}

- (void)startWorkerWithAgent:(TLAgentRecord *)agent
                     payload:(NSDictionary *)payload
                   operation:(NSString *)operation
                       delta:(TLAgentStreamDeltaHandler)delta
            streamCompletion:(TLAgentStreamCompletionHandler)streamCompletion
             modelCompletion:(TLAgentModelCatalogueHandler)modelCompletion
              resultCompletion:(void (^)(NSDictionary *, NSError *))resultCompletion {
  if (!agent) {
    if (resultCompletion) {
      dispatch_async(dispatch_get_main_queue(), ^{ resultCompletion(nil, TLAgentClientError(@"Agent VM is missing.")); });
      return;
    }
    [self completeStreamCompletion:streamCompletion
                   modelCompletion:modelCompletion
                            models:nil
                             error:TLAgentClientError(@"Agent VM is missing.")];
    return;
  }

  if (self.incognitoID.length) {
    if (self.incognitoClosed && ![payload[@"operation"] isEqual:@"incognito_close"]) {
      if (resultCompletion) {
        dispatch_async(dispatch_get_main_queue(), ^{ resultCompletion(nil, TLAgentClientError(@"This Incognito window is closed.")); });
      } else {
      [self completeStreamCompletion:streamCompletion modelCompletion:modelCompletion models:nil error:TLAgentClientError(@"This Incognito window is closed.")];
      }
      return;
    }
    NSMutableDictionary *privatePayload = [payload mutableCopy];
    // Old guest workers must reject the operation, never ignore a new flag and
    // accidentally run a private prompt through their normal persistent gateway.
    privatePayload[@"incognito_operation"] = payload[@"operation"];
    privatePayload[@"operation"] = @"incognito_request";
    privatePayload[@"incognito_id"] = self.incognitoID;
    payload = privatePayload;
    if (!self.incognitoAgents) self.incognitoAgents = [NSMutableDictionary dictionary];
    self.incognitoAgents[@(agent.agentID)] = agent;
    if (!self.incognitoLeaseTimer && !self.incognitoClosed) {
      __weak typeof(self) owner = self;
      self.incognitoLeaseTimer = [NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(NSTimer *timer) {
        typeof(self) strong = owner;
        if (!strong) { [timer invalidate]; return; }
        for (TLAgentRecord *usedAgent in strong.incognitoAgents.allValues)
          [strong startWorkerWithAgent:usedAgent payload:@{@"operation": @"incognito_keepalive", @"request_id": NSUUID.UUID.UUIDString}
            operation:@"incognito_keepalive" delta:nil streamCompletion:^(NSError *error) {} modelCompletion:nil];
      }];
    }
  }
  // Register before connecting so Stop also cancels a request waiting for its socket.
  TLBundledAgentRequest *request = [[TLBundledAgentRequest alloc] init];
  request.requestID = payload[@"request_id"];
  request.deltaHandler = delta;
  request.streamCompletion = streamCompletion;
  request.modelCompletion = modelCompletion;
  request.resultCompletion = resultCompletion;
  if (resultCompletion) request.JSONResult = [TLAgentJSONResult new];
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
