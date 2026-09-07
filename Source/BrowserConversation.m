#import "BrowserConversation.h"
#import "BrowserPageContext.h"

@interface TLBrowserConversation ()
@property TLDatabase *database;
@property TLAssistantTurnRunner *runner;
@property TLChatRecord *chat;
@property NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, readwrite) BOOL busy;
@property (nonatomic, readwrite) NSUInteger responseCount;
@property (nonatomic, strong, readwrite) TLAssistantTurnResult *lastTurnResult;
@property NSString *errorText;
@property NSUInteger turnStart;
@end

@implementation TLBrowserConversation
- (instancetype)initWithDatabase:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator {
  if ((self = [super init])) {
    _database = database;
    _runner = [[TLAssistantTurnRunner alloc] initWithDatabase:database agentOrchestrator:orchestrator];
    _messages = [NSMutableArray array];
  }
  return self;
}
- (void)changed { if (self.changeHandler) self.changeHandler(); }
- (NSString *)title { return self.chat.title ?: @"New chat"; }
- (BOOL)loading {
  return self.busy && !self.pendingApproval && (self.messages.count <= self.turnStart || !self.messages.lastObject.content.length);
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
  NSString *title = @{@"once":@"Allow once", @"session":@"Allow this session", @"always":@"Always allow", @"deny":@"Deny"}[choice];
  if (self.busy || ![pending[@"request_id"] isEqual:requestID] || ![choices containsObject:choice] || !title) return NO;
  TLChatMessage *origin = nil;
  for (TLChatMessage *message in self.messages) if (message.approvalRequest == pending) origin = message;
  NSMutableDictionary *submitted = [pending mutableCopy];
  submitted[@"submitted"] = @YES;
  origin.approvalRequest = submitted;
  self.runner.approvalResponse = @{@"request_id":requestID, @"choice":choice};
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
- (NSString *)markdown {
  NSMutableArray *responses = [NSMutableArray array];
  for (TLChatMessage *message in self.messages) {
    if ([message.role isEqualToString:TLRoleAssistant] && message.content.length) [responses addObject:message.content];
  }
  if (self.errorText.length) [responses addObject:self.errorText];
  return [responses componentsJoinedByString:@"\n\n---\n\n"];
}
- (BOOL)sendPrompt:(NSString *)prompt token:(NSString *)token model:(NSString *)model pageReader:(TLBrowserPageReader)reader {
  if (self.busy || !reader) return NO;
  self.busy = YES;
  self.minimized = NO;
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
    BOOL started = [self.runner startTurnWithChat:self.chat token:token model:model messages:self.messages nextPrompt:prompt
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
      // Saving the first user message generates the title through the normal chat path.
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
