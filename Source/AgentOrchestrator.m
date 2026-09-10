#import "AgentOrchestrator.h"
#import "ChatAttachmentStore.h"
#import "PromptBuilder.h"

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
  NSString *rawInput = messages.lastObject.content ?: @"";
  if ([rawInput hasPrefix:@"/"]) { return rawInput; }
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

static NSURL *TLHermesCommandCacheURL(TLAgentRecord *agent) {
  return [NSURL fileURLWithPath:[agent.vmDirectory stringByAppendingPathComponent:@"hermes-commands-cache.json"]];
}

static BOOL TLValidHermesCatalogue(id catalogue) {
  return [catalogue isKindOfClass:NSDictionary.class] && [catalogue[@"pairs"] isKindOfClass:NSArray.class];
}

typedef void (^TLAgentReadyCompletionHandler)(TLAgentRecord *_Nullable agent, NSError *_Nullable error);

@interface TLAgentOrchestrator ()

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURL *> *incognitoAttachmentURLs;
@property (nonatomic, strong) id<TLAgentStreaming> agentClient;
@property (nonatomic, strong) TLAgentVMService *vmService;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *initializingAgentIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLAgentStreamCompletionHandler> *chatCompletions;

- (void)withDefaultRunningAgent:(TLAgentReadyCompletionHandler)completion;
- (void)withRunningAgentID:(NSInteger)agentID completion:(TLAgentReadyCompletionHandler)completion;
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

- (TLAgentOrchestrator *)incognitoOrchestratorWithDatabase:(TLDatabase *)database {
  TLBundledAgentClient *client = [[TLBundledAgentClient alloc] initWithVMService:self.vmService];
  client.incognitoID = NSUUID.UUID.UUIDString;
  return [[TLAgentOrchestrator alloc] initWithDatabase:database agentClient:client vmService:self.vmService];
}

- (void)closeIncognito {
  if (self.database.incognito && [self.agentClient isKindOfClass:TLBundledAgentClient.class])
    [(TLBundledAgentClient *)self.agentClient closeIncognito];
  [self.incognitoAttachmentURLs removeAllObjects];
}

- (NSURL *)runtimeBundleURL {
  return self.vmService.runtimeBundleURL;
}

- (BOOL)isVirtualizationSupported {
  return self.vmService.virtualizationSupported;
}

// Hermes is installed in the persistent workspace shared with the VM. Inspect
// directory entries rather than following Linux symlinks on the macOS host.
- (BOOL)hasHermesInstallationForAgent:(TLAgentRecord *)agent {
  NSString *workspace = [agent.vmDirectory stringByAppendingPathComponent:@"workspace"];
  for (NSString *relative in @[@".hermes/hermes-agent/venv/bin/hermes", @".local/bin/hermes"]) {
    NSString *path = [workspace stringByAppendingPathComponent:relative];
    NSString *type = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType];
    if ([type isEqualToString:NSFileTypeRegular] || [type isEqualToString:NSFileTypeSymbolicLink]) return YES;
  }
  return NO;
}

- (BOOL)isVMRunningForAgent:(TLAgentRecord *)agent {
  return agent && [self.vmService isAgentRunning:agent];
}

- (NSString *)displayStatusForAgent:(TLAgentRecord *)agent {
  if ([self isInitializingAgentWithID:agent.agentID]) return @"Installing Hermes…";
  if ([agent.status isEqualToString:TLAgentStatusStarting]) return @"Starting VM…";
  if ([agent.status isEqualToString:TLAgentStatusStopping]) return @"Stopping VM…";
  NSString *vm = [self isVMRunningForAgent:agent] ? @"VM running" : @"VM stopped";
  if ([agent.status isEqualToString:TLAgentStatusError]) return [vm stringByAppendingString:@" · Error"];
  if (![self hasHermesInstallationForAgent:agent]) {
    return [self isVMRunningForAgent:agent] ? @"VM is running, but setup is required" : @"VM is stopped; setup is required";
  }
  return [self isVMRunningForAgent:agent] ? @"Running" : @"Stopped";
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

  if (self.database.incognito) {
    if (error) *error = TLAgentOrchestratorError(@"Set up an agent in a normal Talaria window before starting private chats.");
    return nil;
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

- (void)selectModel:(NSString *)model sessionID:(NSString *)sessionID token:(NSString *)token
        completion:(TLAgentStreamCompletionHandler)completion {
  [self selectModel:model sessionID:sessionID agentID:0 token:token completion:completion];
}

- (void)selectModel:(NSString *)model sessionID:(NSString *)sessionID agentID:(NSInteger)agentID token:(NSString *)token
        completion:(TLAgentStreamCompletionHandler)completion {
  [self withRunningAgentID:agentID completion:^(TLAgentRecord *agent, NSError *error) {
    if (!agent) { completion(error ?: TLAgentOrchestratorError(@"Could not open the agent VM.")); return; }
    if (![self.agentClient respondsToSelector:@selector(selectHermesModelWithAgent:sessionID:token:model:completion:)]) {
      completion(TLAgentOrchestratorError(@"Update the agent runtime to switch models.")); return;
    }
    [self.agentClient selectHermesModelWithAgent:agent sessionID:sessionID token:token model:model completion:completion];
  }];
}

- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                  sessionID:(NSString *)sessionID
                                      token:(NSString *)token
                                      model:(NSString *)model
                                   messages:(NSArray<TLChatMessage *> *)messages
                                      delta:(TLAgentStreamDeltaHandler)delta
                                 completion:(TLAgentStreamCompletionHandler)completion {
  [self streamChatWithAgentID:0 requestID:requestID sessionID:sessionID token:token model:model messages:messages delta:delta completion:completion];
}

- (void)streamChatWithAgentID:(NSInteger)agentID requestID:(NSString *)requestID sessionID:(NSString *)sessionID
                       token:(NSString *)token model:(NSString *)model messages:(NSArray<TLChatMessage *> *)messages
                       delta:(TLAgentStreamDeltaHandler)delta completion:(TLAgentStreamCompletionHandler)completion {
  self.chatCompletions[requestID] = completion;
  TLAgentStreamCompletionHandler finish = ^(NSError *error) {
    TLAgentStreamCompletionHandler callback = self.chatCompletions[requestID];
    [self.chatCompletions removeObjectForKey:requestID];
    if (callback) callback(error);
  };
  [self withRunningAgentID:agentID completion:^(TLAgentRecord *agent, NSError *agentError) {
    if (!self.chatCompletions[requestID]) return;
    if (!agent) {
      [self completeStreamWithError:(agentError ?: TLAgentOrchestratorError(@"Could not open an agent VM.")) completion:finish];
      return;
    }

    if (sessionID.length == 0) {
      [self completeStreamWithError:TLAgentOrchestratorError(@"A Hermes session is required for conversation turns.") completion:finish];
      return;
    }
    if (![self.agentClient respondsToSelector:@selector(streamHermesSessionWithAgent:requestID:sessionID:token:model:prompt:delta:completion:)]) {
      [self completeStreamWithError:TLAgentOrchestratorError(@"The Hermes TUI gateway is required. Update the agent runtime.") completion:finish];
      return;
    }
    NSDictionary *approvalResponse = messages.lastObject.approvalResponse;
    if (approvalResponse) {
      if (![self.agentClient respondsToSelector:@selector(streamHermesSessionWithAgent:requestID:sessionID:token:model:prompt:approvalResponse:delta:completion:)]) {
        finish(TLAgentOrchestratorError(@"Update the agent runtime to respond to this approval."));
        return;
      }
      [self.agentClient streamHermesSessionWithAgent:agent requestID:requestID sessionID:sessionID token:token model:model
        prompt:TLHermesInputFromMessages(messages) approvalResponse:approvalResponse delta:delta completion:finish];
      return;
    }
    [self.agentClient streamHermesSessionWithAgent:agent requestID:requestID sessionID:sessionID
                                             token:token model:model prompt:TLHermesInputFromMessages(messages)
                                             delta:delta completion:finish];
  }];
}

- (void)generateTextWithDefaultAgentRequestID:(NSString *)requestID
                                       token:(NSString *)token
                                       model:(NSString *)model
                                instructions:(NSString *)instructions
                                       input:(NSString *)input
                                       delta:(TLAgentStreamDeltaHandler)delta
                                  completion:(TLAgentStreamCompletionHandler)completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) {
      [self completeStreamWithError:error ?: TLAgentOrchestratorError(@"Could not open an agent VM.") completion:completion];
      return;
    }
    if (![self.agentClient respondsToSelector:@selector(generateHermesTextWithAgent:requestID:token:model:instructions:input:delta:completion:)]) {
      [self completeStreamWithError:TLAgentOrchestratorError(@"The Hermes TUI gateway is required for supporting-model tasks.") completion:completion];
      return;
    }
    [self.agentClient generateHermesTextWithAgent:agent requestID:requestID token:token model:model
                                   instructions:instructions input:input delta:delta completion:completion];
  }];
}

- (void)prepareAttachmentURLs:(NSArray<NSURL *> *)URLs sessionID:(NSString *)sessionID
                  completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *, NSError *))completion {
  [self prepareAttachmentURLs:URLs sessionID:sessionID agentID:0 completion:completion];
}

- (void)prepareAttachmentURLs:(NSArray<NSURL *> *)URLs sessionID:(NSString *)sessionID agentID:(NSInteger)agentID
                  completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *, NSError *))completion {
  if (self.database.incognito) {
    [self withRunningAgentID:agentID > 0 ? agentID : self.database.currentAgentID completion:^(TLAgentRecord *agent, NSError *error) {
      if (!agent || error) { completion(nil, error); return; }
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *files = [NSMutableArray array];
        NSError *readError = nil;
        for (NSURL *URL in URLs) {
          NSData *data = [NSData dataWithContentsOfURL:URL options:0 error:&readError];
          if (!data || data.length > 20 * 1024 * 1024) {
            readError = readError ?: TLAgentOrchestratorError(@"Incognito attachments must be individual files smaller than 20 MB.");
            break;
          }
          [files addObject:@{@"name": URL.lastPathComponent, @"data": [data base64EncodedStringWithOptions:0]}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          if (readError) { completion(nil, readError); return; }
          [(TLBundledAgentClient *)self.agentClient uploadIncognitoAttachments:files agent:agent completion:^(NSArray *rows, NSError *uploadError) {
            if (!self.incognitoAttachmentURLs) self.incognitoAttachmentURLs = [NSMutableDictionary dictionary];
            if (rows.count == URLs.count) for (NSUInteger i = 0; i < rows.count; i++)
              self.incognitoAttachmentURLs[rows[i][@"guestPath"]] = URLs[i];
            completion(rows, uploadError);
          }];
        });
      });
    }];
    return;
  }
  NSError *error = nil;
  TLAgentRecord *agent = (agentID > 0 ? [self.database agentWithID:agentID error:&error] : [self defaultAgentCreatingIfNeeded:&error]);
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
  if (self.database.incognito) return YES;
  NSArray *agents = [self.database listAgents:error];
  if (!agents) return NO;
  for (TLAgentRecord *agent in agents) {
    NSURL *workspace = [[NSURL fileURLWithPath:agent.vmDirectory] URLByAppendingPathComponent:@"workspace"];
    TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
    if (![store removeAttachmentsForSessionID:sessionID error:error]) return NO;
  }
  return YES;
}

- (NSURL *)fileURLForAttachment:(NSDictionary *)attachment sessionID:(NSString *)sessionID {
  if (self.database.incognito) return self.incognitoAttachmentURLs[attachment[@"guestPath"]];
  // Reading a saved attachment must never start a VM or create an agent.
  for (TLAgentRecord *agent in [self.database listAgents:nil]) {
    NSURL *workspace = [[NSURL fileURLWithPath:agent.vmDirectory] URLByAppendingPathComponent:@"workspace"];
    TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
    NSURL *URL = [store fileURLForAttachment:attachment sessionID:sessionID];
    if (URL) return URL;
  }
  return nil;
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
                                    progress:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, id value) {
    NSString *text = [value isKindOfClass:NSString.class] ? value : @"";
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
                                        output:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, id value) {
    NSString *text = [value isKindOfClass:NSString.class] ? value : @"";
      if (kind == TLAgentStreamDeltaKindContent && output) output(text);
    } completion:completion];
  }];
}

- (void)hermesSkillsForAgentWithID:(NSInteger)agentID changes:(NSDictionary<NSString *, NSNumber *> *)changes
                      completion:(void (^)(NSDictionary *, NSError *))completion {
  NSError *error = nil;
  TLAgentRecord *selected = [self.database agentWithID:agentID error:&error];
  if (!selected || ![self hasHermesInstallationForAgent:selected]) {
    completion(nil, error ?: TLAgentOrchestratorError(@"Install Hermes for this agent to manage its skills."));
    return;
  }
  if (![self.agentClient respondsToSelector:@selector(hermesSkillsWithAgent:changes:completion:)]) {
    completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to manage Hermes skills."));
    return;
  }
  void (^ready)(TLAgentRecord *, NSError *) = ^(TLAgentRecord *agent, NSError *startError) {
    if (!agent || startError) { completion(nil, startError); return; }
    [self.agentClient hermesSkillsWithAgent:agent changes:changes completion:^(NSDictionary *result, NSError *skillError) {
      if (!skillError && changes.count) {
        [NSFileManager.defaultManager removeItemAtURL:TLHermesCommandCacheURL(agent) error:nil];
      }
      completion(result, skillError);
    }];
  };
  if ([self isVMRunningForAgent:selected]) ready(selected, nil);
  else [self startAgentWithID:agentID completion:ready];
}

- (NSDictionary *)cachedHermesCommands {
  // The file belongs to one agent, so reinstalling/deleting it cannot leak another
  // installation's skills or custom commands into the picker. Cache only metadata.
  NSArray<TLAgentRecord *> *agents = [self.database listAgents:nil];
  TLAgentRecord *agent = [self.database agentWithID:self.database.currentAgentID error:nil] ?: agents.lastObject;
  if (!agent) return nil;
  NSData *data = [NSData dataWithContentsOfURL:TLHermesCommandCacheURL(agent)];
  if (!data) return nil;
  id saved = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![saved isKindOfClass:NSDictionary.class] || ![saved[@"version"] isEqual:@1] ||
      !TLValidHermesCatalogue(saved[@"catalogue"])) return nil;
  return saved[@"catalogue"];
}

- (void)fetchHermesCommandsWithToken:(NSString *)token
                               model:(NSString *)model
                          completion:(void (^)(NSDictionary *, NSError *))completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(fetchHermesCommandsWithAgent:token:model:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to discover Hermes commands."));
      return;
    }
    [self.agentClient fetchHermesCommandsWithAgent:agent token:token model:model completion:^(NSDictionary *catalogue, NSError *fetchError) {
      if (!fetchError && !TLValidHermesCatalogue(catalogue)) {
        fetchError = TLAgentOrchestratorError(@"Hermes returned an invalid command catalogue.");
      }
      if (!fetchError) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"catalogue": catalogue} options:0 error:nil];
        // A cache write failure must not discard a successful live discovery.
        if (!self.database.incognito) [data writeToURL:TLHermesCommandCacheURL(agent) options:NSDataWritingAtomic error:nil];
      }
      completion(fetchError ? nil : catalogue, fetchError);
    }];
  }];
}

- (TLAgentRecord *)existingAgentForTerminal:(NSError **)error {
  NSArray<TLAgentRecord *> *agents = [self.database listAgents:error];
  NSInteger currentID = self.database.currentAgentID;
  for (TLAgentRecord *agent in agents) {
    if (agent.agentID == currentID) return agent;
  }
  return agents.lastObject;
}

- (BOOL)isDefaultAgentRunning {
  TLAgentRecord *agent = [self existingAgentForTerminal:nil];
  return agent && [self.vmService isAgentRunning:agent];
}

- (void)connectToDefaultAgentTerminal:(TLAgentVMConnectionCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSError *error = nil;
    TLAgentRecord *agent = [self existingAgentForTerminal:&error];
    if (!agent || ![self.vmService isAgentRunning:agent]) {
      completion(nil, error ?: TLAgentOrchestratorError(@"The agent VM is not running."));
      return;
    }
    [self.vmService connectToAgent:agent port:7048 timeout:30 completion:completion];
  });
}

- (void)hermesProvidersForAgentID:(NSInteger)agentID parameters:(NSDictionary *)parameters
                       completion:(void (^)(NSDictionary *, NSError *))completion {
  [self startAgentWithID:agentID completion:^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesProvidersWithAgent:parameters:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the runtime to configure providers.")); return;
    }
    [self.agentClient hermesProvidersWithAgent:agent parameters:parameters completion:^(NSDictionary *result, NSError *providerError) {
      if ([result[@"ok"] boolValue] && [parameters[@"action"] isEqual:@"select"]) {
        NSError *saveError = nil;
        if (![self.database saveDefaultModel:result[@"selection"] forAgentID:agentID error:&saveError]) {
          completion(nil, saveError); return;
        }
      }
      completion(result, providerError);
    }];
  }];
}

- (void)hermesNotificationsWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID
                                    token:(NSString *)token model:(NSString *)model
                               completion:(void (^)(NSDictionary *, NSError *))completion {
  if (agentID <= 0) { completion(nil, TLAgentOrchestratorError(@"Select an agent to view its notifications.")); return; }
  NSMutableDictionary *request = [parameters mutableCopy];
  request[@"notification_tool_description"] = [TLPromptBuilder notificationToolDescription];
  TLAgentReadyCompletionHandler ready = ^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesNotificationsWithAgent:parameters:token:model:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to use Hermes notifications.")); return;
    }
    [self.agentClient hermesNotificationsWithAgent:agent parameters:request token:token model:model completion:completion];
  };
  if ([parameters[@"action"] isEqual:@"open_source"]) {
    [self withRunningAgentID:agentID completion:ready];
    return;
  }
  // Background inbox sync must never start a stopped VM.
  NSError *error = nil;
  TLAgentRecord *agent = [self.database agentWithID:agentID error:&error];
  if (agent && ![self.vmService isAgentRunning:agent]) {
    error = TLAgentOrchestratorError(@"The agent is stopped. Start it to refresh notifications.");
    agent = nil;
  }
  [self completeDefaultAgent:agent error:error completion:ready];
}

- (void)hermesPluginsWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID
                                  token:(NSString *)token model:(NSString *)model
                             completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  if (agentID <= 0) { completion(nil, TLAgentOrchestratorError(@"Select an agent to view its plugins.")); return; }
  // Pin every operation to the agent displayed by the tab, even if the current
  // agent changes while its VM is starting or a request is in flight.
  [self startAgentWithID:agentID completion:^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesPluginsWithAgent:parameters:token:model:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to manage Hermes plugins."));
      return;
    }
    [self.agentClient hermesPluginsWithAgent:agent parameters:parameters token:token model:model completion:completion];
  }];
}

- (void)hermesAutomationsWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID
                                  token:(NSString *)token model:(NSString *)model
                             completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  // Pin every operation to the agent displayed by the tab, even if the current
  // agent changes while its VM is starting or a request is in flight.
  [self startAgentWithID:agentID completion:^(TLAgentRecord *agent, NSError *error) {
    if (!agent || error) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesAutomationsWithAgent:parameters:token:model:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to manage Hermes automations."));
      return;
    }
    [self.agentClient hermesAutomationsWithAgent:agent parameters:parameters token:token model:model completion:completion];
  }];
}

- (void)hermesCredentialsWithAction:(NSString *)action key:(NSString *)key value:(NSString *)value
                              token:(NSString *)token
                         completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  // Resolve the selected agent before starting async VM work, so switching
  // agents cannot redirect a credential write to another profile.
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *error) {
    if (!agent) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesCredentialsWithAgent:action:key:value:token:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"Update the agent runtime to manage Hermes tool credentials."));
      return;
    }
    [self.agentClient hermesCredentialsWithAgent:agent action:action key:key value:value token:token completion:completion];
  }];
}

- (void)hermesHistoryWithAction:(NSString *)action sessionID:(NSString *)sessionID
                         token:(NSString *)token model:(NSString *)model
                    completion:(void (^)(NSDictionary *_Nullable result, NSError *_Nullable error))completion {
  [self withDefaultRunningAgent:^(TLAgentRecord *agent, NSError *error) {
    if (!agent) { completion(nil, error); return; }
    if (![self.agentClient respondsToSelector:@selector(hermesHistoryWithAgent:action:sessionID:token:model:completion:)]) {
      completion(nil, TLAgentOrchestratorError(@"This runtime does not support Hermes history. Update the agent runtime."));
      return;
    }
    [self.agentClient hermesHistoryWithAgent:agent action:action sessionID:sessionID token:token model:model completion:completion];
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

- (void)withRunningAgentID:(NSInteger)agentID completion:(TLAgentReadyCompletionHandler)completion {
  if (agentID <= 0) { [self withDefaultRunningAgent:completion]; return; }
  NSError *error = nil;
  TLAgentRecord *agent = [self.database agentWithID:agentID error:&error];
  if (!agent) { [self completeDefaultAgent:nil error:error completion:completion]; return; }
  if ([self isInitializingAgentWithID:agentID]) {
    [self completeDefaultAgent:nil error:TLAgentOrchestratorError(@"This agent is still initializing.") completion:completion]; return;
  }
  if ([self.vmService isAgentRunning:agent]) { [self completeDefaultAgent:agent error:nil completion:completion]; return; }
  [self startAgentWithID:agentID completion:completion];
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
