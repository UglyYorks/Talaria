#import "AgentOrchestrator.h"
#import "ChatAttachmentStore.h"
#import "PromptBuilder.h"

static NSString * const TLAgentOrchestratorErrorDomain = @"Talaria.AgentOrchestrator";

static NSError *TLAgentOrchestratorError(NSString *message) {
  return [NSError errorWithDomain:TLAgentOrchestratorErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static NSString *TLAgentOrchestratorTrim(NSString *value) {
  return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *TLHermesInputFromMessages(NSArray<TLChatMessage *> *messages) {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (TLChatMessage *message in messages) {
    if ([message.role isEqualToString:TLRoleSystem] && message.content.length > 0) {
      [parts addObject:message.content];
    }
  }
  NSString *prompt = messages.lastObject.content ?: @"";
  if (prompt.length > 0) {
    [parts addObject:prompt];
  }
  TLPromptBuilder *builder = [[TLPromptBuilder alloc] init];
  for (NSString *part in parts) [builder addPartWithContent:part importance:TLPromptImportanceRequired
                                                strategy:TLPromptCompactionStrategyWhole name:nil];
  return [builder build];
}

typedef void (^TLAgentReadyCompletionHandler)(TLAgentRecord *_Nullable agent, NSError *_Nullable error);

@interface TLAgentOrchestrator ()

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) id<TLAgentStreaming> agentClient;
@property (nonatomic, strong) TLAgentVMService *vmService;

- (void)withDefaultRunningAgent:(TLAgentReadyCompletionHandler)completion;
- (void)completeDefaultAgent:(TLAgentRecord *)agent
                       error:(NSError *)error
                  completion:(TLAgentReadyCompletionHandler)completion;

@end

@implementation TLAgentOrchestrator

- (instancetype)initWithDatabase:(TLDatabase *)database
                     agentClient:(id<TLAgentStreaming>)agentClient
                       vmService:(TLAgentVMService *)vmService {
  self = [super init];
  if (self) {
    _database = database;
    _agentClient = agentClient;
    _vmService = vmService;
  }
  return self;
}

- (NSURL *)runtimeBundleURL {
  return self.vmService.runtimeBundleURL;
}

- (BOOL)isVirtualizationSupported {
  return self.vmService.virtualizationSupported;
}

- (NSArray<TLAgentRecord *> *)listAgents:(NSError **)error {
  return [self.database listAgents:error];
}

- (TLAgentRecord *)createAgentWithName:(NSString *)name error:(NSError **)error {
  NSString *trimmedName = TLAgentOrchestratorTrim(name ?: @"");
  NSString *agentName = trimmedName.length > 0 ? trimmedName : @"Agent";
  NSString *vmDirectory = [self.vmService newVMDirectoryPathForAgentName:agentName];
  TLAgentRecord *agent = [self.database createAgentWithName:agentName
                                                  guestKind:TLAgentGuestKindLinux
                                                    runtime:TLAgentRuntimePython
                                                vmDirectory:vmDirectory
                                                      error:error];
  if (!agent) {
    return nil;
  }

  NSError *storageError = nil;
  if (![self.vmService prepareStorageForAgent:agent error:&storageError]) {
    [self.database updateAgentWithID:agent.agentID
                              status:TLAgentStatusError
                           lastError:storageError.localizedDescription
                               error:nil];
    if (error) {
      *error = storageError;
    }
    return nil;
  }

  return agent;
}

- (TLAgentRecord *)defaultAgentCreatingIfNeeded:(NSError **)error {
  NSArray<TLAgentRecord *> *agents = [self.database listAgents:error];
  if (!agents) {
    return nil;
  }

  if (agents.count > 0) {
    return agents.lastObject;
  }

  return [self createAgentWithName:@"Default Agent" error:error];
}

- (void)startAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion {
  NSError *loadError = nil;
  TLAgentRecord *agent = [self.database agentWithID:agentID error:&loadError];
  if (!agent) {
    [self completeAgentOperationWithAgent:nil error:loadError completion:completion];
    return;
  }

  NSError *statusError = nil;
  TLAgentRecord *startingAgent = [self.database updateAgentWithID:agent.agentID
                                                           status:TLAgentStatusStarting
                                                        lastError:nil
                                                            error:&statusError];
  if (!startingAgent) {
    [self completeAgentOperationWithAgent:nil error:statusError completion:completion];
    return;
  }

  [self.vmService startAgent:startingAgent completion:^(NSError *vmError) {
    NSError *updateError = nil;
    TLAgentRecord *updatedAgent = nil;
    if (vmError) {
      updatedAgent = [self.database updateAgentWithID:startingAgent.agentID
                                               status:TLAgentStatusError
                                            lastError:vmError.localizedDescription
                                                error:&updateError];
    } else {
      updatedAgent = [self.database updateAgentWithID:startingAgent.agentID
                                               status:TLAgentStatusRunning
                                            lastError:nil
                                                error:&updateError];
    }

    [self completeAgentOperationWithAgent:updatedAgent error:(vmError ?: updateError) completion:completion];
  }];
}

- (void)stopAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion {
  NSError *loadError = nil;
  TLAgentRecord *agent = [self.database agentWithID:agentID error:&loadError];
  if (!agent) {
    [self completeAgentOperationWithAgent:nil error:loadError completion:completion];
    return;
  }

  NSError *statusError = nil;
  TLAgentRecord *stoppingAgent = [self.database updateAgentWithID:agent.agentID
                                                           status:TLAgentStatusStopping
                                                        lastError:nil
                                                            error:&statusError];
  if (!stoppingAgent) {
    [self completeAgentOperationWithAgent:nil error:statusError completion:completion];
    return;
  }

  [self.vmService stopAgent:stoppingAgent completion:^(NSError *vmError) {
    NSError *updateError = nil;
    TLAgentRecord *updatedAgent = nil;
    if (vmError) {
      updatedAgent = [self.database updateAgentWithID:stoppingAgent.agentID
                                               status:TLAgentStatusError
                                            lastError:vmError.localizedDescription
                                                error:&updateError];
    } else {
      updatedAgent = [self.database updateAgentWithID:stoppingAgent.agentID
                                               status:TLAgentStatusStopped
                                            lastError:nil
                                                error:&updateError];
    }

    [self completeAgentOperationWithAgent:updatedAgent error:(vmError ?: updateError) completion:completion];
  }];
}

- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error {
  TLAgentRecord *agent = [self.database agentWithID:agentID error:error];
  if (!agent) {
    return NO;
  }

  if (![self.vmService deleteVMForAgent:agent error:error]) {
    return NO;
  }

  return [self.database deleteAgentWithID:agentID error:error];
}

- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                  sessionID:(NSString *)sessionID
                                      token:(NSString *)token
                                      model:(NSString *)model
                                   messages:(NSArray<TLChatMessage *> *)messages
                                      delta:(TLAgentStreamDeltaHandler)delta
                                 completion:(TLAgentStreamCompletionHandler)completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *agentError) {
    if (!agent) {
      [self completeStreamWithError:(agentError ?: TLAgentOrchestratorError(@"Could not open an agent VM.")) completion:completion];
      return;
    }

    if (sessionID.length > 0 &&
        [self.agentClient respondsToSelector:@selector(streamHermesSessionWithAgent:requestID:sessionID:token:model:prompt:delta:completion:)]) {
      [self.agentClient streamHermesSessionWithAgent:agent requestID:requestID sessionID:sessionID
                                               token:token model:model prompt:TLHermesInputFromMessages(messages)
                                               delta:delta completion:completion];
      return;
    }
    [self.agentClient streamChatWithAgent:agent requestID:requestID token:token model:model
                                 messages:messages delta:delta completion:completion];
  }];
}

- (void)prepareAttachmentURLs:(NSArray<NSURL *> *)URLs sessionID:(NSString *)sessionID
                  completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *, NSError *))completion {
  NSError *error = nil;
  TLAgentRecord *agent = [self defaultAgentCreatingIfNeeded:&error];
  if (!agent || ![self.vmService prepareStorageForAgent:agent error:&error]) {
    completion(nil, error ?: TLAgentOrchestratorError(@"Could not prepare the attachment workspace."));
    return;
  }
  NSArray *sources = [URLs copy];
  NSURL *workspace = [[NSURL fileURLWithPath:agent.vmDirectory] URLByAppendingPathComponent:@"workspace"];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *copyError = nil;
    TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
    NSArray *attachments = [store copyURLs:sources sessionID:sessionID error:&copyError];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(attachments, copyError); });
  });
}

- (BOOL)removeAttachmentsForSessionID:(NSString *)sessionID error:(NSError **)error {
  NSArray *agents = [self.database listAgents:error];
  if (!agents) return NO;
  for (TLAgentRecord *agent in agents) {
    NSURL *workspace = [[NSURL fileURLWithPath:agent.vmDirectory] URLByAppendingPathComponent:@"workspace"];
    TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
    if (![store removeAttachmentsForSessionID:sessionID error:error]) return NO;
  }
  return YES;
}

- (void)createFreshHermesAgentWithProgress:(TLHermesInstallProgressHandler)progress
                                completion:(TLAgentOperationCompletionHandler)completion {
  NSError *createError = nil;
  TLAgentRecord *agent = [self createAgentWithName:@"Hermes Agent" error:&createError];
  if (!agent) {
    [self completeAgentOperationWithAgent:nil error:createError completion:completion];
    return;
  }
  [self startAgentWithID:agent.agentID completion:^(TLAgentRecord *runningAgent, NSError *startError) {
    if (!runningAgent || startError) {
      if (completion) completion(runningAgent, startError);
      return;
    }
    if (![self.agentClient respondsToSelector:@selector(installHermesWithAgent:requestID:progress:completion:)]) {
      if (completion) completion(runningAgent, TLAgentOrchestratorError(@"This VM runtime cannot install Hermes Agent."));
      return;
    }
    NSString *requestID = NSUUID.UUID.UUIDString;
    [self.agentClient installHermesWithAgent:runningAgent requestID:requestID
                                    progress:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
      if (progress && [deltaRequestID isEqualToString:requestID]) progress(text);
    } completion:^(NSError *installError) {
      if (completion) completion(runningAgent, installError);
    }];
  }];
}

- (void)runShellCommandWithDefaultAgentSessionID:(NSString *)sessionID
                                         command:(NSString *)command
                                          output:(void (^)(NSString *text))output
                                      completion:(TLAgentStreamCompletionHandler)completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *agentError) {
    if (!agent) {
      if (completion) completion(agentError ?: TLAgentOrchestratorError(@"Could not open an agent VM."));
      return;
    }
    if (![self.agentClient respondsToSelector:@selector(runShellCommandWithAgent:requestID:sessionID:command:output:completion:)]) {
      if (completion) completion(TLAgentOrchestratorError(@"This VM runtime does not support debug terminal commands."));
      return;
    }
    NSString *requestID = NSUUID.UUID.UUIDString;
    [self.agentClient runShellCommandWithAgent:agent
                                     requestID:requestID
                                     sessionID:sessionID
                                       command:command
                                        output:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
      if (kind == TLAgentStreamDeltaKindContent && output) output(text);
    } completion:completion];
  }];
}

- (void)fetchModelCatalogueWithToken:(NSString *)token completion:(TLAgentModelCatalogueHandler)completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *agentError) {
    if (!agent) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
          completion(nil, agentError ?: TLAgentOrchestratorError(@"Could not open an agent VM."));
        }
      });
      return;
    }

    [self.agentClient fetchModelCatalogueWithAgent:agent token:token completion:completion];
  }];
}

- (void)withDefaultRunningAgent:(TLAgentReadyCompletionHandler)completion {
  NSError *agentError = nil;
  TLAgentRecord *agent = [self defaultAgentCreatingIfNeeded:&agentError];
  if (!agent) {
    [self completeDefaultAgent:nil
                         error:agentError ?: TLAgentOrchestratorError(@"Could not create a default agent.")
                    completion:completion];
    return;
  }

  if ([self.vmService isAgentRunning:agent]) {
    if ([agent.status isEqualToString:TLAgentStatusRunning]) {
      [self completeDefaultAgent:agent error:nil completion:completion];
      return;
    }

    NSError *statusError = nil;
    TLAgentRecord *runningAgent = [self.database updateAgentWithID:agent.agentID
                                                           status:TLAgentStatusRunning
                                                        lastError:nil
                                                            error:&statusError];
    [self completeDefaultAgent:runningAgent error:statusError completion:completion];
    return;
  }

  NSError *statusError = nil;
  TLAgentRecord *startingAgent = [self.database updateAgentWithID:agent.agentID
                                                          status:TLAgentStatusStarting
                                                       lastError:nil
                                                           error:&statusError];
  if (!startingAgent) {
    [self completeDefaultAgent:nil error:statusError completion:completion];
    return;
  }

  [self.vmService startAgent:startingAgent completion:^(NSError *vmError) {
    NSError *updateError = nil;
    TLAgentRecord *updatedAgent = nil;
    if (vmError) {
      updatedAgent = [self.database updateAgentWithID:startingAgent.agentID
                                               status:TLAgentStatusError
                                            lastError:vmError.localizedDescription
                                                error:&updateError];
    } else {
      updatedAgent = [self.database updateAgentWithID:startingAgent.agentID
                                               status:TLAgentStatusRunning
                                            lastError:nil
                                                error:&updateError];
    }

    [self completeDefaultAgent:updatedAgent error:(vmError ?: updateError) completion:completion];
  }];
}

- (void)completeDefaultAgent:(TLAgentRecord *)agent
                       error:(NSError *)error
                  completion:(TLAgentReadyCompletionHandler)completion {
  if (!completion) {
    return;
  }

  if (NSThread.isMainThread) {
    completion(agent, error);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(agent, error);
    });
  }
}

- (void)completeAgentOperationWithAgent:(TLAgentRecord *)agent
                                  error:(NSError *)error
                             completion:(TLAgentOperationCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (completion) {
      completion(agent, error);
    }
  });
}

- (void)completeStreamWithError:(NSError *)error completion:(TLAgentStreamCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (completion) {
      completion(error);
    }
  });
}

@end
