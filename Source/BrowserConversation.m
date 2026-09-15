#import "TLQuestionRequest.h"
#import "BrowserConversation.h"
#import "BrowserPageContext.h"

@interface TLBrowserConversation ()
@property TLDatabase *database;
@property (nonatomic, strong, readwrite) TLAssistantTurnRunner *runner;
@property (nonatomic, strong, readwrite) TLChatRecord *chat;
@property (nonatomic, strong, readwrite) NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, readwrite) BOOL busy;
@property (nonatomic, readwrite) NSUInteger responseCount;
@property (nonatomic, strong, readwrite) TLAssistantTurnResult *lastTurnResult;
@property (nonatomic, copy, readwrite) NSString *errorText;
@property NSUInteger turnStart;
@property (nonatomic, copy) NSString *pendingPrompt;
@end

@implementation TLBrowserConversation
- (instancetype)initWithDatabase:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator {
  if ((self = [super init])) {
    _database = database;
    _runner = [[TLAssistantTurnRunner alloc] initWithDatabase:database agentOrchestrator:orchestrator];
    _messages = [NSMutableArray array];
    _draft = @"";
  }
  return self;
}
- (void)changed {
  BOOL needsAnswer = self.pendingApproval != nil;
  for (TLQuestionRequest *question in self.questions) needsAnswer |= question.pending;
  if (!self.busy || needsAnswer) self.collapsed = NO;
  if (self.changeHandler) self.changeHandler();
}
- (NSString *)title {
  return [NSString stringWithFormat:@"%@ %@", self.chat.icon.length ? self.chat.icon : TLDefaultChatIcon(),
    self.chat.icon.length && self.chat.title.length ? self.chat.title : @"New chat"];
}
- (void)refreshChatIdentity {
  self.chat = [self.database chatWithID:self.chat.chatID error:nil] ?: self.chat;
  if (self.changeHandler) self.changeHandler();
}
- (NSString *)activityText {
  if (!self.busy) return @"";
  if (self.pendingApproval) return @"Waiting for approval…";
  for (TLQuestionRequest *question in self.questions) if (question.pending) return @"Waiting for your answer…";
  if (self.messages.count <= self.turnStart) return @"Reading page…";
  TLChatMessage *message = self.messages.lastObject;
  return message.thinkingActive || !message.content.length ? @"Thinking…" : @"Writing response…";
}
- (NSArray<NSDictionary<NSString *, NSString *> *> *)toolActivities {
  return self.messages.count > self.turnStart ? self.messages.lastObject.toolActivities : @[];
}
- (NSArray<TLQuestionRequest *> *)questions {
  return self.messages.count > self.turnStart ? self.messages.lastObject.questions : @[];
}
- (BOOL)loading {
  for (TLQuestionRequest *question in self.questions) if (question.pending) return NO;
  return self.busy && !self.pendingApproval && !self.toolActivities.count && (self.messages.count <= self.turnStart || !self.messages.lastObject.content.length);
}
- (NSDictionary *)pendingApproval {
  for (TLChatMessage *message in self.messages.reverseObjectEnumerator) {
    if (message.approvalRequest && ![message.approvalRequest[@"submitted"] boolValue]) return message.approvalRequest;
  }
  return nil;
}
- (BOOL)respondToApproval:(NSString *)requestID choice:(NSString *)choice token:(NSString *)token model:(NSString *)model {
  NSDictionary *pending = self.pendingApproval;
  NSArray *choices = [pending[@"choices"] isKindOfClass:NSArray.class] ? pending[@"choices"] : @[@"once", @"deny"];
  BOOL clarification = [pending[@"kind"] isEqual:@"clarification"];
  NSString *title = clarification ? choice : @{@"once":@"Allow once", @"session":@"Allow this session", @"always":@"Always allow", @"deny":@"Deny"}[choice];
  if (self.busy || ![pending[@"request_id"] isEqual:requestID] || (!clarification && ![choices containsObject:choice]) || !title.length) return NO;
  TLChatMessage *origin = nil;
  for (TLChatMessage *message in self.messages) if (message.approvalRequest == pending) origin = message;
  NSMutableDictionary *submitted = [pending mutableCopy];
  submitted[@"submitted"] = @YES;
  origin.approvalRequest = submitted;
  self.runner.approvalResponse = clarification ? @{@"kind":@"clarification", @"request_id":requestID,
    @"question_id":pending[@"question_id"] ?: @"", @"answer":choice} : @{@"request_id":requestID, @"choice":choice};
  BOOL started = [self sendPrompt:title token:token model:model pageReader:^(void (^completion)(NSDictionary *, NSError *)) { completion(@{}, nil); }];
  self.runner.approvalResponse = nil;
  if (!started || (!self.busy && !self.lastTurnResult) ||
      (self.lastTurnResult && self.lastTurnResult.generationStatus == TLAssistantTurnGenerationStatusNotStarted)) {
    origin.approvalRequest = pending;
    [self changed];
    return NO;
  }
  return YES;
}
- (NSArray<NSDictionary<NSString *, id> *> *)transcript {
  NSMutableArray *entries = [NSMutableArray array];
  for (TLChatMessage *message in self.messages) {
    if ((message.content.length || message.attachments.count) && ([message.role isEqual:TLRoleUser] || [message.role isEqual:TLRoleAssistant])) {
      [entries addObject:@{@"role":message.role, @"content":[message.content copy] ?: @"", @"attachments":[message.attachments copy] ?: @[]}];
    }
  }
  // Page extraction happens before the runner appends the durable user message.
  if (self.pendingPrompt.length && self.messages.count == self.turnStart) {
    [entries addObject:@{@"role":TLRoleUser, @"content":self.pendingPrompt}];
  }
  return entries;
}
- (NSString *)markdown {
  NSMutableArray *responses = [NSMutableArray array];
  for (TLChatMessage *message in self.messages) {
    if ([message.role isEqualToString:TLRoleAssistant] && message.content.length) [responses addObject:message.content];
  }
  if (self.errorText.length) [responses addObject:self.errorText];
  return [responses componentsJoinedByString:@"\n\n---\n\n"];
}
- (BOOL)sendPrompt:(NSString *)prompt token:(NSString *)token model:(NSString *)model pageReader:(TLBrowserPageReader)reader {
  if (self.busy || !reader || ![prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return NO;
  // NSTextView.string can alias mutable text storage, which the address bar resets
  // to the page URL before asynchronous extraction completes.
  NSString *submittedPrompt = [prompt copy];
  self.pendingPrompt = submittedPrompt;
  self.busy = YES;
  self.minimized = NO;
  self.collapsed = YES;
  self.errorText = nil;
  self.lastTurnResult = nil;
  self.turnStart = self.messages.count;
  [self changed];
  NSError *error = nil;
  if (!self.chat) self.chat = [self.database createChatWithModel:model error:&error];
  if (!self.chat) {
    self.busy = NO;
    self.errorText = error.localizedDescription ?: @"Could not create the conversation.";
    [self changed];
    return NO;
  }
  [self changed];
  if (!self.runner.approvalResponse && self.promptSubmittedHandler) self.promptSubmittedHandler(self, submittedPrompt);
  // Retain the conversation through the request so closing the browser still saves its reply.
  reader(^(NSDictionary *page, NSError *readError) {
    if (readError) {
      self.busy = NO;
      self.errorText = readError.localizedDescription;
      [self changed];
      return;
    }
    self.runner.referenceContext = TLBrowserPageContext(page ?: @{});
    NSError *startError = nil;
    BOOL started = [self.runner startTurnWithChat:self.chat token:token model:model messages:self.messages nextPrompt:submittedPrompt
      updateHandler:^{ [self changed]; }
      completionHandler:^(TLAssistantTurnResult *result) {
        self.busy = NO;
        self.lastTurnResult = result;
        if (result.assistantMessage.content.length && result.generationStatus == TLAssistantTurnGenerationStatusSucceeded) {
          self.responseCount += 1;
        }
        NSMutableArray<NSString *> *errors = [NSMutableArray array];
        if (result.generationError) [errors addObject:[NSString stringWithFormat:@"Request failed: %@", result.generationError.localizedDescription]];
        if (result.persistenceError) [errors addObject:[NSString stringWithFormat:@"Could not save conversation: %@", result.persistenceError.localizedDescription]];
        self.errorText = [errors componentsJoinedByString:@"\n\n"];
        [self changed];
      } error:&startError];
    if (started) {
      // Keep persisted chat metadata in sync without displaying the raw prompt as its name.
      self.chat = [self.database chatWithID:self.chat.chatID error:nil] ?: self.chat;
      [self changed];
    }
    if (!started) {
      self.busy = NO;
      self.errorText = startError.localizedDescription;
      [self changed];
    }
  });
  return YES;
}
@end
