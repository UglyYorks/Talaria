#import "AssistantTurnRunner.h"
#import "PromptMessages.h"
#import "PromptBuilder.h"
#import "StreamingBlockBuffer.h"

static NSString * const TLAssistantTurnRunnerErrorDomain = @"Talaria.AssistantTurnRunner";

static NSError *TLAssistantTurnError(NSString *message) {
  return [NSError errorWithDomain:TLAssistantTurnRunnerErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *TLAssistantTurnTrim(NSString *value) {
  return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@interface TLAssistantTurnResult ()
- (instancetype)initWithGenerationStatus:(TLAssistantTurnGenerationStatus)generationStatus
                         generationError:(nullable NSError *)generationError
                        persistenceError:(nullable NSError *)persistenceError
                             userMessage:(TLChatMessage *)userMessage
                        assistantMessage:(nullable TLChatMessage *)assistantMessage;
@end

@implementation TLAssistantTurnResult
- (instancetype)initWithGenerationStatus:(TLAssistantTurnGenerationStatus)generationStatus
                         generationError:(NSError *)generationError
                        persistenceError:(NSError *)persistenceError
                             userMessage:(TLChatMessage *)userMessage
                        assistantMessage:(TLChatMessage *)assistantMessage {
  if ((self = [super init])) {
    _generationStatus = generationStatus;
    _generationError = generationError;
    _persistenceStatus = persistenceError ? TLAssistantTurnPersistenceStatusFailed : TLAssistantTurnPersistenceStatusSucceeded;
    _persistenceError = persistenceError;
    _userMessage = [userMessage copy];
    _assistantMessage = [assistantMessage copy];
  }
  return self;
}
@end

@interface TLAssistantTurnRunner ()
@property (nonatomic, strong) id<TLAssistantTurnMessageStore> messageStore;
@property (nonatomic, strong) id<TLAssistantTurnStreaming> streaming;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, copy) NSString *activeRequestID;
@end

@implementation TLAssistantTurnRunner

- (instancetype)initWithDatabase:(TLDatabase *)database agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator {
  return [self initWithMessageStore:(id<TLAssistantTurnMessageStore>)database
                         streaming:(id<TLAssistantTurnStreaming>)agentOrchestrator];
}

- (instancetype)initWithMessageStore:(id<TLAssistantTurnMessageStore>)messageStore
                            streaming:(id<TLAssistantTurnStreaming>)streaming {
  self = [super init];
  if (self) {
    _messageStore = messageStore;
    _streaming = streaming;
  }
  return self;
}

- (BOOL)startTurnWithChat:(nullable TLChatRecord *)chat
                    token:(NSString *)token
                    model:(NSString *)model
                 messages:(nullable NSMutableArray<TLChatMessage *> *)messages
               nextPrompt:(NSString *)nextPrompt
            updateHandler:(nullable TLAssistantTurnUpdateHandler)updateHandler
        completionHandler:(nullable TLAssistantTurnCompletionHandler)completionHandler
                    error:(NSError **)error {
  NSString *trimmedToken = TLAssistantTurnTrim(token ?: @"");
  NSString *trimmedModel = TLAssistantTurnTrim(model ?: @"");
  NSString *trimmedPrompt = TLAssistantTurnTrim(nextPrompt ?: @"");

  NSError *validationError = [self validationErrorForChat:chat
                                                    token:trimmedToken
                                                    model:trimmedModel
                                                 messages:messages
                                               nextPrompt:trimmedPrompt];
  if (validationError) {
    if (error) {
      *error = validationError;
    }
    return NO;
  }

  NSMutableArray<TLChatMessage *> *requestMessages = [TLBuildRequestMessages(messages, trimmedPrompt) mutableCopy];
  if (self.referenceContext.length) {
    [requestMessages insertObject:[TLChatMessage messageWithRole:TLRoleSystem content:self.referenceContext thinking:nil] atIndex:0];
  }
  NSArray *attachments = [self.attachments copy] ?: @[];
  if (attachments.count) {
    TLPromptBuilder *builder = [[TLPromptBuilder alloc] init];
    [builder addPartWithContent:requestMessages.lastObject.content importance:TLPromptImportanceRequired
                      strategy:TLPromptCompactionStrategyWhole name:@"user-request"];
    [builder addPartWithContent:TLBuildAttachmentContext(attachments) importance:TLPromptImportanceRequired
                      strategy:TLPromptCompactionStrategyWhole name:@"attachments"];
    requestMessages.lastObject.content = [builder build];
  }
  NSUInteger assistantMessageIndex = messages.count + 1;
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *assistantContent = [NSMutableString string];
  NSMutableString *assistantThinking = [NSMutableString string];
  TLStreamingBlockBuffer *assistantContentDisplay = [[TLStreamingBlockBuffer alloc] init];
  TLStreamingBlockBuffer *assistantThinkingDisplay = [[TLStreamingBlockBuffer alloc] init];

  TLChatMessage *userMessage = [TLChatMessage messageWithRole:TLRoleUser content:trimmedPrompt thinking:nil];
  userMessage.attachments = attachments;
  TLChatMessage *assistantMessage = [TLChatMessage messageWithRole:TLRoleAssistant content:@"" thinking:nil];
  [messages addObject:userMessage];
  [messages addObject:assistantMessage];
  self.running = YES;
  self.activeRequestID = requestID;
  if (updateHandler) {
    updateHandler();
  }

  NSError *saveError = nil;
  TLStoredChatMessage *savedUser = [self.messageStore saveMessage:userMessage
                      chatID:chat.chatID
                       error:&saveError];
  if (!savedUser || saveError) {
    [messages removeObjectIdenticalTo:assistantMessage];
    [messages removeObjectIdenticalTo:userMessage];
    TLAssistantTurnResult *result = [[TLAssistantTurnResult alloc]
      initWithGenerationStatus:TLAssistantTurnGenerationStatusNotStarted
      generationError:nil
      persistenceError:saveError ?: TLAssistantTurnError(@"Could not save user message.")
      userMessage:userMessage assistantMessage:nil];
    [self finishWithResult:result updateHandler:updateHandler completionHandler:completionHandler];
    return YES;
  }
  messages[assistantMessageIndex - 1] = savedUser;

  __weak typeof(self) weakSelf = self;
  [self.streaming streamChatWithDefaultAgentRequestID:requestID
                                                    sessionID:chat.hermesSessionID
                                                        token:trimmedToken
                                                        model:trimmedModel
                                                     messages:requestMessages
                                                        delta:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
    TLAssistantTurnRunner *strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.running || ![strongSelf.activeRequestID isEqualToString:requestID] ||
        ![deltaRequestID isEqualToString:requestID] || text.length == 0) {
      return;
    }

    BOOL displayChanged = NO;
    if (kind == TLAgentStreamDeltaKindThinking) {
      [assistantThinking appendString:text];
      NSString *displayThinking = [assistantThinkingDisplay appendText:text];
      if (![assistantMessage.thinking isEqualToString:displayThinking]) {
        assistantMessage.thinking = displayThinking.length > 0 ? displayThinking : nil;
        displayChanged = YES;
      }
    } else {
      [assistantContent appendString:text];
      NSString *displayContent = [assistantContentDisplay appendText:text];
      if (strongSelf.streamsPartialContent) { displayContent = [assistantContent copy]; }
      if (![assistantMessage.content isEqualToString:displayContent]) {
        assistantMessage.content = displayContent;
        displayChanged = YES;
      }
    }

    if (displayChanged && updateHandler) {
      updateHandler();
    }
  } completion:^(NSError *streamError) {
    TLAssistantTurnRunner *strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.running || ![strongSelf.activeRequestID isEqualToString:requestID]) {
      return;
    }

    // Flush even on stream failure: unfinished markdown and thinking are still
    // the user's generated content and must remain available for recovery.
    assistantMessage.content = [assistantContentDisplay flush];
    NSString *displayThinking = [assistantThinkingDisplay flush];
    assistantMessage.thinking = displayThinking.length > 0 ? displayThinking : nil;

    NSError *assistantSaveError = nil;
    TLChatMessage *resultAssistant = assistantMessage;
    if (streamError && assistantContent.length == 0 && assistantThinking.length == 0) {
      [messages removeObjectIdenticalTo:assistantMessage];
      resultAssistant = nil;
    } else {
      TLStoredChatMessage *savedAssistant = [strongSelf.messageStore saveMessage:assistantMessage
                                                                        chatID:chat.chatID
                                                                         error:&assistantSaveError];
      if (!savedAssistant && !assistantSaveError) {
        assistantSaveError = TLAssistantTurnError(@"Could not save assistant message.");
      }
      if (savedAssistant && !assistantSaveError) {
        resultAssistant = savedAssistant;
        NSUInteger currentIndex = [messages indexOfObjectIdenticalTo:assistantMessage];
        if (currentIndex != NSNotFound) messages[currentIndex] = savedAssistant;
      }
    }
    TLAssistantTurnResult *result = [[TLAssistantTurnResult alloc]
      initWithGenerationStatus:streamError ? TLAssistantTurnGenerationStatusFailed : TLAssistantTurnGenerationStatusSucceeded
      generationError:streamError persistenceError:assistantSaveError
      userMessage:savedUser assistantMessage:resultAssistant];
    [strongSelf finishWithResult:result updateHandler:updateHandler completionHandler:completionHandler];
  }];

  return YES;
}

- (NSError *)validationErrorForChat:(TLChatRecord *)chat
                              token:(NSString *)token
                              model:(NSString *)model
                           messages:(NSArray<TLChatMessage *> *)messages
                         nextPrompt:(NSString *)nextPrompt {
  if (self.running) {
    return TLAssistantTurnError(@"An assistant turn is already running.");
  }
  if (!chat) {
    return TLAssistantTurnError(@"A chat is required before sending.");
  }
  if (token.length == 0) {
    return TLAssistantTurnError(@"OpenRouter token is required.");
  }
  if (model.length == 0) {
    return TLAssistantTurnError(@"OpenRouter model is required.");
  }
  if (nextPrompt.length == 0) {
    return TLAssistantTurnError(@"Messages cannot be empty.");
  }
  if (!messages) {
    return TLAssistantTurnError(@"Message storage is required.");
  }

  return nil;
}

- (void)finishWithResult:(TLAssistantTurnResult *)result
          updateHandler:(TLAssistantTurnUpdateHandler)updateHandler
      completionHandler:(TLAssistantTurnCompletionHandler)completionHandler {
  self.running = NO;
  self.activeRequestID = nil;
  if (updateHandler) {
    updateHandler();
  }
  if (completionHandler) {
    completionHandler(result);
  }
}

@end
