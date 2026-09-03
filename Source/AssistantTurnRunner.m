#import "AssistantTurnRunner.h"
#import "PromptMessages.h"
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

@interface TLAssistantTurnRunner ()
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) BOOL lastTurnSucceeded;
@end

@implementation TLAssistantTurnRunner

- (instancetype)initWithDatabase:(TLDatabase *)database agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator {
  self = [super init];
  if (self) {
    _database = database;
    _agentOrchestrator = agentOrchestrator;
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
  NSUInteger assistantMessageIndex = messages.count + 1;
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *assistantContent = [NSMutableString string];
  NSMutableString *assistantThinking = [NSMutableString string];
  TLStreamingBlockBuffer *assistantContentDisplay = [[TLStreamingBlockBuffer alloc] init];
  TLStreamingBlockBuffer *assistantThinkingDisplay = [[TLStreamingBlockBuffer alloc] init];

  [messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:trimmedPrompt thinking:nil]];
  [messages addObject:[TLChatMessage messageWithRole:TLRoleAssistant content:@"" thinking:nil]];
  self.running = YES;
  self.lastTurnSucceeded = NO;
  if (updateHandler) {
    updateHandler();
  }

  NSError *saveError = nil;
  TLStoredChatMessage *savedUser = [self.database saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:trimmedPrompt thinking:nil]
                      chatID:chat.chatID
                       error:&saveError];
  if (saveError) {
    [self finishFailedTurnWithMessages:messages
                        assistantIndex:assistantMessageIndex
                                chatID:chat.chatID
                               message:saveError.localizedDescription ?: @"Could not save user message."
                         updateHandler:updateHandler
                     completionHandler:completionHandler];
    return YES;
  }
  if (savedUser) { messages[assistantMessageIndex - 1] = savedUser; }

  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator streamChatWithDefaultAgentRequestID:requestID
                                                        token:trimmedToken
                                                        model:trimmedModel
                                                     messages:requestMessages
                                                        delta:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
    TLAssistantTurnRunner *strongSelf = weakSelf;
    if (!strongSelf || !strongSelf.running || ![deltaRequestID isEqualToString:requestID] || text.length == 0) {
      return;
    }

    if (assistantMessageIndex >= messages.count) {
      return;
    }

    TLChatMessage *assistantMessage = messages[assistantMessageIndex];
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
    if (!strongSelf || !strongSelf.running) {
      return;
    }

    if (streamError) {
      NSString *failureContent = [NSString stringWithFormat:@"Request failed: %@", streamError.localizedDescription];
      [strongSelf finishFailedTurnWithMessages:messages
                                assistantIndex:assistantMessageIndex
                                        chatID:chat.chatID
                                       message:failureContent
                                 updateHandler:updateHandler
                             completionHandler:completionHandler];
      return;
    }

    if (assistantMessageIndex < messages.count) {
      TLChatMessage *assistantMessage = messages[assistantMessageIndex];
      assistantMessage.content = [assistantContentDisplay flush];
      NSString *displayThinking = [assistantThinkingDisplay flush];
      assistantMessage.thinking = displayThinking.length > 0 ? displayThinking : nil;
    }

    NSError *assistantSaveError = nil;
    TLStoredChatMessage *savedAssistant = [strongSelf.database saveMessage:[TLChatMessage messageWithRole:TLRoleAssistant
                                                            content:assistantContent
                                                           thinking:assistantThinking.length > 0 ? assistantThinking : nil]
                              chatID:chat.chatID
                               error:&assistantSaveError];
    if (savedAssistant && assistantMessageIndex < messages.count) {
      messages[assistantMessageIndex] = savedAssistant;
    }
    strongSelf.running = NO;
    strongSelf.lastTurnSucceeded = YES;
    if (completionHandler) {
      completionHandler(assistantSaveError);
    }
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

- (void)finishFailedTurnWithMessages:(NSMutableArray<TLChatMessage *> *)messages
                      assistantIndex:(NSUInteger)assistantIndex
                              chatID:(NSInteger)chatID
                             message:(NSString *)message
                       updateHandler:(TLAssistantTurnUpdateHandler)updateHandler
                   completionHandler:(TLAssistantTurnCompletionHandler)completionHandler {
  if (assistantIndex < messages.count) {
    messages[assistantIndex].content = message;
    messages[assistantIndex].thinking = nil;
  }

  TLStoredChatMessage *savedAssistant = [self.database saveMessage:[TLChatMessage messageWithRole:TLRoleAssistant content:message thinking:nil]
                      chatID:chatID
                       error:nil];
  if (savedAssistant && assistantIndex < messages.count) {
    messages[assistantIndex] = savedAssistant;
  }
  self.running = NO;
  if (updateHandler) {
    updateHandler();
  }
  if (completionHandler) {
    completionHandler(nil);
  }
}

@end
