#import "AgentClient.h"
#import "AgentVMService.h"
#import "OpenRouterParsing.h"
#import <Virtualization/Virtualization.h>

static NSString * const TLAgentClientErrorDomain = @"Talaria.AgentClient";
static uint32_t const TLAgentWorkerPort = 7047;
static NSTimeInterval const TLAgentWorkerConnectionTimeout = 30.0;

static NSError *TLAgentClientError(NSString *message) {
  return [NSError errorWithDomain:TLAgentClientErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static BOOL TLAgentClientShouldUseHostNetworkFallback(NSError *error) {
  NSString *message = error.localizedDescription.lowercaseString;
  return [message containsString:@"could not read openrouter stream:"] ||
         [message containsString:@"could not load openrouter models:"];
}

typedef void (^TLBundledAgentRequestReleaseHandler)(id request);

@interface TLBundledAgentRequest : NSObject

@property (nonatomic, strong) VZVirtioSocketConnection *connection;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSMutableData *outputBuffer;
@property (nonatomic, copy) NSString *operation;
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

@end

@interface TLBundledAgentClient ()

@property (nonatomic, strong) TLAgentVMService *vmService;
@property (nonatomic, strong) TLOpenRouterClient *hostNetworkClient;
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
    NSArray<TLOpenRouterModel *> *models = [self modelsFromEvent:event error:&error];
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
  if (requestID.length == 0 || text.length == 0 || !self.deltaHandler) {
    return;
  }

  TLAgentStreamDeltaKind kind = [kindString isEqualToString:@"thinking"]
    ? TLAgentStreamDeltaKindThinking
    : TLAgentStreamDeltaKindContent;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.deltaHandler(requestID, kind, text);
  });
}

- (NSArray<TLOpenRouterModel *> *)modelsFromEvent:(NSDictionary *)event error:(NSError **)error {
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

  return TLParseOpenRouterModelsResponse(responseData, error);
}

- (void)finishWithError:(NSError *)error models:(NSArray<TLOpenRouterModel *> *)models {
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
    _hostNetworkClient = [[TLOpenRouterClient alloc] init];
    _activeRequests = [NSMutableSet set];
  }
  return self;
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
  NSDictionary *payload = @{
    @"operation": @"hermes_session_chat",
    @"request_id": requestID ?: @"",
    @"session_id": sessionID ?: @"",
    @"token": token ?: @"",
    @"model": model ?: @"",
    @"prompt": prompt ?: @"",
    @"soul": agent.soul ?: @"",
  };
  [self startWorkerWithAgent:agent payload:payload operation:@"hermes_session_chat"
                       delta:delta streamCompletion:completion modelCompletion:nil];
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

- (void)streamChatWithAgent:(TLAgentRecord *)agent
                  requestID:(NSString *)requestID
                      token:(NSString *)token
                      model:(NSString *)model
                   messages:(NSArray<TLChatMessage *> *)messages
                      delta:(TLAgentStreamDeltaHandler)delta
                 completion:(TLAgentStreamCompletionHandler)completion {
  NSDictionary *payload = @{
    @"operation": @"stream_chat",
    @"request_id": requestID ?: @"",
    @"token": token ?: @"",
    @"model": model ?: @"",
    @"agent": [self dictionaryForAgent:agent],
    @"messages": [self dictionariesForMessages:messages],
  };

  __block BOOL receivedDelta = NO;
  TLAgentStreamDeltaHandler VMDelta = ^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
    receivedDelta = YES;
    delta(deltaRequestID, kind, text);
  };
  [self startWorkerWithAgent:agent
                     payload:payload
                   operation:@"stream_chat"
                       delta:VMDelta
            streamCompletion:^(NSError *error) {
    if (!error || receivedDelta || !TLAgentClientShouldUseHostNetworkFallback(error)) {
      completion(error);
      return;
    }

    [self.hostNetworkClient streamChatWithRequestID:requestID
                                              token:token
                                              model:model
                                           messages:messages
                                              delta:^(NSString *deltaRequestID, TLOpenRouterDeltaKind kind, NSString *text) {
      TLAgentStreamDeltaKind agentKind = kind == TLOpenRouterDeltaKindThinking
        ? TLAgentStreamDeltaKindThinking
        : TLAgentStreamDeltaKindContent;
      delta(deltaRequestID, agentKind, text);
    } completion:completion];
  }
             modelCompletion:nil];
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
             modelCompletion:^(NSArray<TLOpenRouterModel *> *models, NSError *error) {
    if (!error || !TLAgentClientShouldUseHostNetworkFallback(error)) {
      completion(models, error);
      return;
    }
    [self.hostNetworkClient fetchModelCatalogueWithToken:token completion:completion];
  }];
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

  [self.vmService connectToAgent:agent port:TLAgentWorkerPort timeout:TLAgentWorkerConnectionTimeout completion:^(VZVirtioSocketConnection *connection, NSError *error) {
    if (!connection) {
      [self completeStreamCompletion:streamCompletion
                     modelCompletion:modelCompletion
                              models:nil
                               error:error ?: TLAgentClientError(@"Could not connect to the agent VM.")];
      return;
    }

    TLBundledAgentRequest *request = [[TLBundledAgentRequest alloc] init];
    request.deltaHandler = delta;
    request.streamCompletion = streamCompletion;
    request.modelCompletion = modelCompletion;
    __weak typeof(self) weakSelf = self;
    request.releaseHandler = ^(id finishedRequest) {
      [weakSelf.activeRequests removeObject:finishedRequest];
    };

    [self.activeRequests addObject:request];
    NSError *startError = nil;
    if (![request startWithConnection:connection payload:payload operation:operation error:&startError]) {
      [self.activeRequests removeObject:request];
      [self completeStreamCompletion:streamCompletion
                     modelCompletion:modelCompletion
                              models:nil
                               error:startError ?: TLAgentClientError(@"Could not start the agent VM request.")];
    }
  }];
}

- (void)completeStreamCompletion:(TLAgentStreamCompletionHandler)streamCompletion
                 modelCompletion:(TLAgentModelCatalogueHandler)modelCompletion
                          models:(NSArray<TLOpenRouterModel *> *)models
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

- (NSArray<NSDictionary<NSString *, NSString *> *> *)dictionariesForMessages:(NSArray<TLChatMessage *> *)messages {
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *dictionaries = [NSMutableArray arrayWithCapacity:messages.count];
  for (TLChatMessage *message in messages) {
    [dictionaries addObject:[message requestDictionary]];
  }
  return dictionaries;
}

@end
