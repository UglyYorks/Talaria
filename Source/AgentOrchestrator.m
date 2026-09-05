#import "AgentOrchestrator.h"

static NSString * const TLAgentOrchestratorErrorDomain = @"Talaria.AgentOrchestrator";

static NSError *TLAgentOrchestratorError(NSString *message) {
  return [NSError errorWithDomain:TLAgentOrchestratorErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static NSArray<NSString *> *TLValidatedAgentFolders(NSArray<NSString *> *folderPaths, NSError **error) {
  NSMutableOrderedSet<NSString *> *folders = [NSMutableOrderedSet orderedSet];
  for (NSString *path in folderPaths) {
    NSString *normalized = path.stringByStandardizingPath;
    BOOL directory = NO;
    if (!normalized.isAbsolutePath || ![NSFileManager.defaultManager fileExistsAtPath:normalized isDirectory:&directory] || !directory) {
      if (error) *error = TLAgentOrchestratorError(@"Choose existing local folders for this agent.");
      return nil;
    }
    [folders addObject:normalized];
  }
  return folders.array;
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
  return [parts componentsJoinedByString:@"\n\n"];
}

typedef void (^TLAgentReadyCompletionHandler)(TLAgentRecord *_Nullable agent, NSError *_Nullable error);

@interface TLAgentOrchestrator ()

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) id<TLAgentStreaming> agentClient;
@property (nonatomic, strong) TLAgentVMService *vmService;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *initializingAgentIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLAgentStreamCompletionHandler> *chatCompletions;

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
    _initializingAgentIDs = [NSMutableSet set];
    _chatCompletions = [NSMutableDictionary dictionary];
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
  NSArray<TLAgentRecord *> *agents = [self.database listAgents:error];
  for (TLAgentRecord *agent in agents) {
    if ([self isInitializingAgentWithID:agent.agentID]) agent.status = TLAgentStatusInitializing;
  }
  return agents;
}

- (BOOL)isInitializingAgentWithID:(NSInteger)agentID {
  @synchronized (self.initializingAgentIDs) {
    return [self.initializingAgentIDs containsObject:@(agentID)];
  }
}

- (TLAgentRecord *)createAgentWithName:(NSString *)name error:(NSError **)error {
  return [self createAgentWithName:name avatar:@"🤖" soul:@"" folderPaths:@[] error:error];
}

- (TLAgentRecord *)createAgentWithName:(NSString *)name avatar:(NSString *)avatar
                                 soul:(NSString *)soul folderPaths:(NSArray<NSString *> *)folderPaths
                                error:(NSError **)error {
  NSString *agentName = TLAgentOrchestratorTrim(name ?: @"");
  if (!agentName.length) {
    if (error) *error = TLAgentOrchestratorError(@"Give your agent a name.");
    return nil;
  }
  NSArray<NSString *> *folders = TLValidatedAgentFolders(folderPaths, error);
  if (!folders) return nil;
  // Preserve the previous selection while the new VM is being provisioned.
  NSInteger currentID = self.database.currentAgentID;
  if (currentID > 0 && ![self.database setCurrentAgentID:currentID error:error]) return nil;
  NSString *vmDirectory = [self.vmService newVMDirectoryPathForAgentName:agentName];
  TLAgentRecord *agent = [self.database createAgentWithName:agentName avatar:avatar soul:soul
                                               folderPaths:folders vmDirectory:vmDirectory error:error];
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
    NSInteger currentID = self.database.currentAgentID;
    for (TLAgentRecord *agent in agents) {
      if (agent.agentID == currentID) return agent;
    }
    return agents.lastObject;
  }

  return [self createAgentWithName:@"Default Agent" error:error];
}

- (void)startAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion {
  if ([self isInitializingAgentWithID:agentID]) {
    [self completeAgentOperationWithAgent:nil error:TLAgentOrchestratorError(@"This agent is still initializing.") completion:completion];
    return;
  }
  [self startVMForAgentWithID:agentID completion:completion];
}

- (void)startVMForAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion {
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
  if ([self isInitializingAgentWithID:agentID]) {
    [self completeAgentOperationWithAgent:nil error:TLAgentOrchestratorError(@"This agent is still initializing.") completion:completion];
    return;
  }
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

- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID folderPaths:(NSArray<NSString *> *)folderPaths error:(NSError **)error {
  NSArray<NSString *> *folders = TLValidatedAgentFolders(folderPaths, error);
  if (!folders) return nil;
  return [self.database updateAgentWithID:agentID folderPaths:folders error:error];
}

- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID name:(NSString *)name
                             avatar:(NSString *)avatar soul:(NSString *)soul error:(NSError **)error {
  NSString *agentName = TLAgentOrchestratorTrim(name ?: @"");
  if (!agentName.length) {
    if (error) *error = TLAgentOrchestratorError(@"Give your agent a name.");
    return nil;
  }
  return [self.database updateAgentWithID:agentID name:agentName avatar:avatar soul:soul error:error];
}

- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error {
  if ([self isInitializingAgentWithID:agentID]) {
    if (error) *error = TLAgentOrchestratorError(@"This agent is still initializing.");
    return NO;
  }
  TLAgentRecord *agent = [self.database agentWithID:agentID error:error];
  if (!agent) {
    return NO;
  }

  if (![self.vmService deleteVMForAgent:agent error:error]) {
    return NO;
  }

  return [self.database deleteAgentWithID:agentID error:error];
}

- (void)cancelChatWithRequestID:(NSString *)requestID {
  TLAgentStreamCompletionHandler completion = self.chatCompletions[requestID];
  if (!completion) return;
  [self.chatCompletions removeObjectForKey:requestID];
  if ([self.agentClient respondsToSelector:@selector(cancelChatWithRequestID:)]) {
    [self.agentClient cancelChatWithRequestID:requestID];
  }
  completion([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
}

- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                  sessionID:(NSString *)sessionID
                                      token:(NSString *)token
                                      model:(NSString *)model
                                   messages:(NSArray<TLChatMessage *> *)messages
                                      delta:(TLAgentStreamDeltaHandler)delta
                                 completion:(TLAgentStreamCompletionHandler)completion {
  self.chatCompletions[requestID] = completion;
  TLAgentStreamCompletionHandler finish = ^(NSError *error) {
    TLAgentStreamCompletionHandler callback = self.chatCompletions[requestID];
    [self.chatCompletions removeObjectForKey:requestID];
    if (callback) callback(error);
  };
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *agentError) {
    if (!self.chatCompletions[requestID]) return;
    if (!agent) {
      [self completeStreamWithError:(agentError ?: TLAgentOrchestratorError(@"Could not open an agent VM.")) completion:finish];
      return;
    }

    if (sessionID.length > 0 &&
        [self.agentClient respondsToSelector:@selector(streamHermesSessionWithAgent:requestID:sessionID:token:model:prompt:delta:completion:)]) {
      [self.agentClient streamHermesSessionWithAgent:agent requestID:requestID sessionID:sessionID
                                               token:token model:model prompt:TLHermesInputFromMessages(messages)
                                               delta:delta completion:finish];
      return;
    }
    [self.agentClient streamChatWithAgent:agent requestID:requestID token:token model:model
                                 messages:messages delta:delta completion:finish];
  }];
}

- (void)createFreshHermesAgentWithProgress:(TLHermesInstallProgressHandler)progress
                                completion:(TLAgentOperationCompletionHandler)completion {
  NSError *createError = nil;
  TLAgentRecord *agent = [self createAgentWithName:@"Hermes Agent" error:&createError];
  if (!agent) {
    [self completeAgentOperationWithAgent:nil error:createError completion:completion];
    return;
  }
  [self installHermesForAgentWithID:agent.agentID progress:progress completion:completion];
}

- (void)installHermesForAgentWithID:(NSInteger)agentID progress:(TLHermesInstallProgressHandler)progress
                        completion:(TLAgentOperationCompletionHandler)completion {
  @synchronized (self.initializingAgentIDs) {
    if ([self.initializingAgentIDs containsObject:@(agentID)]) {
      [self completeAgentOperationWithAgent:nil error:TLAgentOrchestratorError(@"This agent is already initializing.") completion:completion];
      return;
    }
    [self.initializingAgentIDs addObject:@(agentID)];
  }
  // Keep provisioning alive independently of the creation sheet, and clear it on every terminal path.
  TLAgentOperationCompletionHandler finish = ^(TLAgentRecord *agent, NSError *installError) {
    NSError *saveError = nil;
    TLAgentRecord *updatedAgent = agent;
    if (agent) {
      updatedAgent = [self.database updateAgentWithID:agentID
        status:installError ? TLAgentStatusError : TLAgentStatusRunning
        lastError:installError.localizedDescription error:&saveError] ?: agent;
      if (!installError && !saveError) [self.database setCurrentAgentID:agentID error:&saveError];
    }
    @synchronized (self.initializingAgentIDs) { [self.initializingAgentIDs removeObject:@(agentID)]; }
    [self completeAgentOperationWithAgent:updatedAgent error:installError ?: saveError completion:completion];
  };
  [self startVMForAgentWithID:agentID completion:^(TLAgentRecord *runningAgent, NSError *startError) {
    if (!runningAgent || startError) { finish(runningAgent, startError); return; }
    if (![self.agentClient respondsToSelector:@selector(installHermesWithAgent:requestID:progress:completion:)]) {
      finish(runningAgent, TLAgentOrchestratorError(@"This VM runtime cannot install Hermes Agent."));
      return;
    }
    NSString *requestID = NSUUID.UUID.UUIDString;
    [self.agentClient installHermesWithAgent:runningAgent requestID:requestID
                                    progress:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
      if (progress && [deltaRequestID isEqualToString:requestID]) progress(text);
    } completion:^(NSError *installError) { finish(runningAgent, installError); }];
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

  if ([self isInitializingAgentWithID:agent.agentID]) {
    [self completeDefaultAgent:nil error:TLAgentOrchestratorError(@"This agent is still initializing. Try again when setup finishes.") completion:completion];
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
