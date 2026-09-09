#import <Foundation/Foundation.h>
#import "AssistantTurnRunner.h"

static NSUInteger failures = 0;
static void TLAssert(BOOL condition, NSString *message) {
  if (!condition) {
    failures += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
  }
}

static NSError *TLTestError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.Test" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface TLTurnTestMessageStore : NSObject <TLAssistantTurnMessageStore>
@property NSMutableArray<TLStoredChatMessage *> *savedMessages;
@property NSUInteger saveCount;
@property NSUInteger failOnSave;
@property NSError *saveError;
@property NSUInteger replacementCount;
@end

@implementation TLTurnTestMessageStore
- (TLStoredChatMessage *)replaceMessage:(TLChatMessage *)message messageID:(NSInteger)messageID chatID:(NSInteger)chatID error:(NSError **)error {
  self.replacementCount++;
  TLStoredChatMessage *saved = [self saveMessage:message chatID:chatID error:error];
  saved.messageID = messageID;
  return saved;
}
- (instancetype)init {
  if ((self = [super init])) _savedMessages = [NSMutableArray array];
  return self;
}
- (TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error {
  self.saveCount += 1;
  if (self.saveCount == self.failOnSave) {
    if (error) *error = self.saveError;
    return nil;
  }
  TLStoredChatMessage *saved = [TLStoredChatMessage messageWithRole:message.role content:message.content thinking:message.thinking];
  saved.attachments = message.attachments;
  saved.messageID = (NSInteger)self.saveCount;
  saved.createdAt = @"2026-09-05";
  [self.savedMessages addObject:saved];
  return saved;
}
@end

@interface TLTurnTestRequest : NSObject
@property NSString *requestID;
@property (copy) TLAgentStreamDeltaHandler delta;
@property (copy) TLAgentStreamCompletionHandler completion;
@end
@implementation TLTurnTestRequest
@end

@interface TLTurnTestStream : NSObject <TLAssistantTurnStreaming>
@property NSMutableArray<TLTurnTestRequest *> *requests;
@property NSString *content;
@property NSString *thinking;
@property NSError *streamError;
@property BOOL deferred;
@property NSArray<TLChatMessage *> *lastMessages;
@property NSString *cancelledRequestID;
@property NSUInteger cancelCount;
@end

@implementation TLTurnTestStream
- (void)cancelChatWithRequestID:(NSString *)requestID {
  self.cancelledRequestID = requestID;
  self.cancelCount += 1;
}
- (instancetype)init {
  if ((self = [super init])) {
    _requests = [NSMutableArray array];
    _content = @"Unfinished ```markdown";
    _thinking = @"Partial reasoning";
  }
  return self;
}
- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                sessionID:(NSString *)sessionID
                                    token:(NSString *)token
                                    model:(NSString *)model
                                 messages:(NSArray<TLChatMessage *> *)messages
                                    delta:(TLAgentStreamDeltaHandler)delta
                               completion:(TLAgentStreamCompletionHandler)completion {
  self.lastMessages = messages;
  TLTurnTestRequest *request = [[TLTurnTestRequest alloc] init];
  request.requestID = requestID;
  request.delta = delta;
  request.completion = completion;
  [self.requests addObject:request];
  if (self.deferred) return;
  if (self.thinking.length) delta(requestID, TLAgentStreamDeltaKindThinking, self.thinking);
  if (self.content.length) delta(requestID, TLAgentStreamDeltaKindContent, self.content);
  completion(self.streamError);
}
@end

static TLChatRecord *TLTestChat(void) {
  TLChatRecord *chat = [[TLChatRecord alloc] init];
  chat.chatID = 17;
  chat.hermesSessionID = @"fake-session";
  return chat;
}

static TLAssistantTurnResult *TLRunTurn(TLTurnTestMessageStore *store, TLTurnTestStream *stream,
                                      NSMutableArray<TLChatMessage *> *messages) {
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
  __block TLAssistantTurnResult *result = nil;
  __block NSUInteger completionCount = 0;
  NSError *error = nil;
  BOOL started = [runner startTurnWithChat:TLTestChat() token:@"test-token" model:@"test-model"
    messages:messages nextPrompt:@"  hello  " updateHandler:nil
    completionHandler:^(TLAssistantTurnResult *terminalResult) {
      completionCount += 1;
      result = terminalResult;
    } error:&error];
  TLAssert(started && !error, @"valid turn starts even when its synchronous completion reports failure");
  TLAssert(result && completionCount == 1 && !runner.running, @"turn completes once and releases running state");
  return result;
}

static void TestSuccessfulTurn(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  NSMutableArray *messages = [NSMutableArray array];
  TLAssistantTurnResult *result = TLRunTurn(store, stream, messages);
  TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusSucceeded &&
           result.persistenceStatus == TLAssistantTurnPersistenceStatusSucceeded, @"successful generation and saves have distinct success statuses");
  TLAssert(!result.generationError && !result.persistenceError, @"successful outcome has no errors");
  TLAssert([result.assistantMessage.content isEqual:stream.content] &&
           [result.assistantMessage.thinking isEqual:stream.thinking], @"terminal snapshot flushes unfinished content and thinking");
  TLAssert(store.savedMessages.count == 2 && [messages.lastObject isKindOfClass:TLStoredChatMessage.class], @"saved messages retain database identity");
  ((TLChatMessage *)messages.lastObject).content = @"Changed after completion";
  TLAssert([result.assistantMessage.content isEqual:stream.content], @"later view mutations do not alter the result snapshot");
}

static void TestUserSaveFailure(void) {
  for (NSNumber *hasError in @[@YES, @NO]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    store.failOnSave = 1;
    store.saveError = hasError.boolValue ? TLTestError(@"Disk full") : nil;
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    TLChatMessage *priorMessage = [TLChatMessage messageWithRole:TLRoleAssistant content:@"Earlier reply" thinking:nil];
    NSMutableArray *messages = [NSMutableArray arrayWithObject:priorMessage];
    TLAssistantTurnResult *result = TLRunTurn(store, stream, messages);
    TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusNotStarted && !result.generationError,
             @"prompt persistence failure does not claim generation failed or succeeded");
    TLAssert(result.persistenceStatus == TLAssistantTurnPersistenceStatusFailed && result.persistenceError,
             @"missing saved prompt is a failure even if the store forgot an NSError");
    TLAssert(stream.requests.count == 0 && store.saveCount == 1, @"failed prompt save prevents model call and synthetic failure message save");
    TLAssert(messages.count == 1 && messages.firstObject == priorMessage, @"failed prompt save rolls back only this turn's rows");
    TLAssert([result.userMessage.content isEqual:@"hello"] && !result.assistantMessage, @"result retains the prompt for retry without an assistant placeholder");
  }
}

static void TestAssistantSaveFailure(void) {
  for (NSNumber *hasError in @[@YES, @NO]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    store.failOnSave = 2;
    store.saveError = hasError.boolValue ? TLTestError(@"Assistant save failed") : nil;
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    NSMutableArray *messages = [NSMutableArray array];
    TLAssistantTurnResult *result = TLRunTurn(store, stream, messages);
    TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusSucceeded && !result.generationError,
             @"response save failure preserves successful generation status");
    TLAssert(result.persistenceStatus == TLAssistantTurnPersistenceStatusFailed && result.persistenceError,
             @"response save failure is always surfaced separately");
    TLAssert(messages.count == 2 && [((TLChatMessage *)messages.lastObject).content isEqual:stream.content] &&
             [result.assistantMessage.content isEqual:stream.content], @"unsaved response remains visible and recoverable");
    TLAssert(store.savedMessages.count == 1 && ![messages.lastObject isKindOfClass:TLStoredChatMessage.class],
             @"unsaved response does not acquire a fake persisted identity");
  }
}

static void TestPartialStreamFailures(void) {
  for (NSNumber *saveFails in @[@NO, @YES]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    store.failOnSave = saveFails.boolValue ? 2 : 0;
    store.saveError = TLTestError(@"Partial save failed");
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    stream.streamError = TLTestError(@"Disconnected");
    NSMutableArray *messages = [NSMutableArray array];
    TLAssistantTurnResult *result = TLRunTurn(store, stream, messages);
    TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusFailed && result.generationError == stream.streamError,
             @"generation failure preserves its original error");
    TLAssert((result.persistenceStatus == TLAssistantTurnPersistenceStatusFailed) == saveFails.boolValue,
             @"partial reply save has an independent outcome");
    TLAssert(result.persistenceError == (saveFails.boolValue ? store.saveError : nil), @"both errors survive when generation and persistence fail");
    TLAssert([result.assistantMessage.content isEqual:stream.content] &&
             [result.assistantMessage.thinking isEqual:stream.thinking], @"failure does not overwrite unfinished output with error prose");
    TLAssert([((TLChatMessage *)messages.lastObject).content isEqual:stream.content], @"partial output is flushed to the visible conversation");
    if (!saveFails.boolValue) {
      TLAssert([store.savedMessages.lastObject.content isEqual:stream.content], @"partial output is persisted when possible");
    }
  }
}

static void TestFailureWithoutOutput(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  stream.content = @"";
  stream.thinking = @"";
  stream.streamError = TLTestError(@"No connection");
  NSMutableArray *messages = [NSMutableArray array];
  TLAssistantTurnResult *result = TLRunTurn(store, stream, messages);
  TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusFailed &&
           result.persistenceStatus == TLAssistantTurnPersistenceStatusSucceeded, @"failed empty request retains the successfully saved prompt");
  TLAssert(!result.assistantMessage && messages.count == 1 && store.saveCount == 1,
           @"failed empty request leaves no synthetic or empty assistant response in history");
}

static void TestThinkingDeltasAreImmediatelyVisible(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  stream.deferred = YES;
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
  NSMutableArray<TLChatMessage *> *messages = [NSMutableArray array];
  __block NSString *visibleThinking = nil;
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
    updateHandler:^{ visibleThinking = messages.lastObject.thinking; } completionHandler:nil error:nil];
  TLTurnTestRequest *request = stream.requests.lastObject;
  request.delta(request.requestID, TLAgentStreamDeltaKindThinking, @"Let me check");
  TLAssert([visibleThinking isEqual:@"Let me check"] && runner.running && store.saveCount == 1,
           @"thinking appears without waiting for a paragraph or completion");
  request.delta(request.requestID, TLAgentStreamDeltaKindThinking, @" this 🦊");
  TLAssert([visibleThinking isEqual:@"Let me check this 🦊"], @"thinking preserves every partial delta");
  [runner cancel];
  TLAssert([store.savedMessages.lastObject.thinking isEqual:visibleThinking], @"cancellation preserves partial thinking");
}

static void TestAnswerDeltasAreImmediatelyVisible(void) {
  for (NSNumber *fails in @[@NO, @YES]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    stream.deferred = YES;
    TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
    NSMutableArray<TLChatMessage *> *messages = [NSMutableArray array];
    NSMutableArray<NSString *> *visibleAnswers = [NSMutableArray array];
    __block TLAssistantTurnResult *result = nil;
    [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
      updateHandler:^{ [visibleAnswers addObject:messages.lastObject.content ?: @""]; }
      completionHandler:^(TLAssistantTurnResult *terminalResult) { result = terminalResult; } error:nil];
    TLTurnTestRequest *request = stream.requests.lastObject;
    NSMutableString *expected = [NSMutableString string];
    // No blank line or closing fence: none of these chunks completes a Markdown block.
    for (NSString *chunk in @[@"Hello", @" 🦊", @"\n```swift\n", @"print(\"hi\")"]) {
      NSUInteger previousUpdates = visibleAnswers.count;
      [expected appendString:chunk];
      request.delta(request.requestID, TLAgentStreamDeltaKindContent, chunk);
      TLAssert(runner.running && !result && store.saveCount == 1, @"answer appears before completion or assistant persistence");
      TLAssert(visibleAnswers.count == previousUpdates + 1 && [visibleAnswers.lastObject isEqual:expected],
               @"every delta immediately updates the visible answer, including unfinished Markdown");
    }
    NSUInteger previousUpdates = visibleAnswers.count;
    request.delta(@"unrelated-request", TLAgentStreamDeltaKindContent, @"wrong answer");
    request.delta(request.requestID, TLAgentStreamDeltaKindContent, @"");
    TLAssert(visibleAnswers.count == previousUpdates, @"empty and mismatched deltas do not update the answer");
    NSError *streamError = fails.boolValue ? TLTestError(@"Disconnected") : nil;
    request.completion(streamError);
    TLAssert(result.generationError == streamError && !runner.running, @"stream retains its completion outcome");
    TLAssert([result.assistantMessage.content isEqual:expected] && [store.savedMessages.lastObject.content isEqual:expected] &&
             [visibleAnswers.lastObject isEqual:expected], @"completion preserves the exact streamed answer without duplication on success or failure");
    TLAssert([visibleAnswers[1] isEqual:@"Hello"], @"later deltas do not mutate earlier display snapshots");
  }
}

static void TestThinkingStatusReplacesWithoutAccumulating(void) {
  for (NSNumber *outcome in @[@0, @1, @2]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    stream.deferred = YES;
    TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
    NSMutableArray<TLChatMessage *> *messages = [NSMutableArray array];
    __block NSUInteger updates = 0;
    [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
      updateHandler:^{ updates++; } completionHandler:nil error:nil];
    TLTurnTestRequest *request = stream.requests.lastObject;
    for (NSString *notice in @[@"computing...", @"waiting — 30s", @"waiting — 30s", @"waiting — 60s"]) {
      BOOL duplicate = [messages.lastObject.thinking isEqual:notice];
      NSUInteger before = updates;
      request.delta(request.requestID, TLAgentStreamDeltaKindStatus, notice);
      TLAssert([messages.lastObject.thinking isEqual:notice], @"only the current status appears immediately, without waiting for a paragraph");
      TLAssert(updates == before + (duplicate ? 0 : 1), @"identical status snapshots do not redraw the message");
    }
    request.delta(@"other-request", TLAgentStreamDeltaKindStatus, @"unrelated status");
    TLAssert([messages.lastObject.thinking isEqual:@"waiting — 60s"], @"unrelated status is ignored");
    request.delta(request.requestID, TLAgentStreamDeltaKindStatus, @"");
    TLAssert(messages.lastObject.thinking == nil, @"empty status clears the notice");
    request.delta(request.requestID, TLAgentStreamDeltaKindThinking, @"First");
    TLAssert([messages.lastObject.thinking isEqual:@"First"], @"reasoning tokens appear immediately");
    request.delta(request.requestID, TLAgentStreamDeltaKindStatus, @"waiting again");
    TLAssert([messages.lastObject.thinking isEqual:@"First\n\nwaiting again"], @"status is a separate paragraph from reasoning");
    request.delta(request.requestID, TLAgentStreamDeltaKindThinking, @" thought");
    TLAssert([messages.lastObject.thinking isEqual:@"First thought"], @"reasoning resumes without stale status or added token separators");
    request.delta(request.requestID, TLAgentStreamDeltaKindStatus, @"waiting again");
    request.delta(request.requestID, TLAgentStreamDeltaKindContent, @"Answer");
    TLAssert([messages.lastObject.thinking isEqual:@"First thought"], @"answer output clears the waiting notice");
    request.delta(request.requestID, TLAgentStreamDeltaKindStatus, @"last notice");
    if (outcome.integerValue == 2) [runner cancel];
    else request.completion(outcome.integerValue == 1 ? TLTestError(@"Disconnected") : nil);
    TLAssert([store.savedMessages.lastObject.thinking isEqual:@"First thought"],
      @"success, failure and cancellation preserve reasoning without storing runtime notices");
  }
}

static void TestStructuredApproval(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  stream.deferred = YES;
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
  NSMutableArray<TLChatMessage *> *messages = [NSMutableArray array];
  __block TLAssistantTurnResult *result = nil;
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"research"
    updateHandler:nil completionHandler:^(TLAssistantTurnResult *value) { result = value; } error:nil];
  TLTurnTestRequest *request = stream.requests.lastObject;
  NSDictionary *approval = @{@"request_id":@"exact-id", @"command":@"execute_code\n# literal comment\nprint('hello')", @"choices":@[@"once", @"deny"]};
  NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:approval options:0 error:nil] encoding:NSUTF8StringEncoding];
  request.delta(request.requestID, TLAgentStreamDeltaKindApproval, json);
  TLAssert([messages.lastObject.approvalRequest isEqual:approval] && !messages.lastObject.content.length,
    @"approval command is structured metadata, never assistant Markdown");
  request.completion(nil);
  TLAssert([messages.lastObject.approvalRequest isEqual:approval] && [result.assistantMessage.approvalRequest isEqual:approval],
    @"pending card survives terminal snapshot and replacement with a saved message");
  TLAssert(messages.lastObject.requestDictionary[@"approvalRequest"] == nil, @"approval payload is not model context");
  runner.approvalResponse = @{@"request_id":@"exact-id", @"choice":@"deny"};
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"Deny"
    updateHandler:nil completionHandler:nil error:nil];
  TLAssert([stream.lastMessages.lastObject.approvalResponse isEqual:runner.approvalResponse],
    @"approval response reaches transport separately from visible user text");
  [runner cancel];
}

static void TestValidationAndStaleCallbacks(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  stream.deferred = YES;
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
  NSMutableArray *messages = [NSMutableArray array];
  __block NSUInteger completionCount = 0;
  NSError *error = nil;
  TLAssistantTurnCompletionHandler completion = ^(TLAssistantTurnResult *result) { completionCount += 1; };
  BOOL accepted = [runner startTurnWithChat:nil token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
                            updateHandler:nil completionHandler:completion error:&error];
  TLAssert(!accepted && error && !messages.count && completionCount == 0 && !store.saveCount,
           @"validation failure neither mutates nor completes a turn");
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
             updateHandler:nil completionHandler:completion error:nil];
  TLTurnTestRequest *first = stream.requests.firstObject;
  first.delta(first.requestID, TLAgentStreamDeltaKindContent, @"first reply");
  first.completion(nil);
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"again"
             updateHandler:nil completionHandler:completion error:nil];
  first.delta(first.requestID, TLAgentStreamDeltaKindContent, @"stale reply");
  first.completion(TLTestError(@"stale failure"));
  TLAssert(runner.running && completionCount == 1 && store.saveCount == 3,
           @"previous request cannot complete or persist while a new request is active");
  TLTurnTestRequest *second = stream.requests.lastObject;
  second.delta(second.requestID, TLAgentStreamDeltaKindContent, @"second reply");
  second.completion(nil);
  second.completion(nil);
  TLAssert(!runner.running && completionCount == 2 && store.saveCount == 4,
           @"duplicate terminal callback is ignored");
  TLAssert([((TLChatMessage *)messages.lastObject).content isEqual:@"second reply"], @"new response remains independent of stale callbacks");
}

static void TestCancellation(void) {
  for (NSNumber *partial in @[@NO, @YES]) {
    TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
    TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
    stream.deferred = YES;
    TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
    NSMutableArray *messages = [NSMutableArray array];
    __block NSUInteger completions = 0;
    __block TLAssistantTurnResult *result;
    [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
      updateHandler:nil completionHandler:^(TLAssistantTurnResult *value) { result = value; completions++; } error:nil];
    TLTurnTestRequest *first = stream.requests.lastObject;
    if (partial.boolValue) {
      first.delta(first.requestID, TLAgentStreamDeltaKindContent, @"Partial **answer");
      first.delta(first.requestID, TLAgentStreamDeltaKindThinking, @"Thinking");
    }
    [runner cancel];
    [runner cancel];
    TLAssert(!runner.running && completions == 1 && stream.cancelCount == 1 &&
      [stream.cancelledRequestID isEqual:first.requestID], @"Stop cancels exactly the active request once");
    TLAssert(result.generationStatus == TLAssistantTurnGenerationStatusCancelled && !result.generationError,
      @"user cancellation is a normal terminal outcome without an error alert");
    TLAssert(messages.count == (partial.boolValue ? 2 : 1), @"empty cancelled placeholders are removed");
    if (partial.boolValue) TLAssert([result.assistantMessage.content isEqual:@"Partial **answer"] &&
      [store.savedMessages.lastObject.thinking isEqual:@"Thinking"], @"Stop persists unfinished content and thinking");
    [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"next"
      updateHandler:nil completionHandler:^(TLAssistantTurnResult *value) { completions++; } error:nil];
    first.delta(first.requestID, TLAgentStreamDeltaKindContent, @"late output");
    first.completion(TLTestError(@"late error"));
    TLAssert(runner.running && completions == 1 && ((TLChatMessage *)messages.lastObject).content.length == 0,
      @"late cancelled callbacks cannot affect a new response");
    TLTurnTestRequest *second = stream.requests.lastObject;
    second.delta(second.requestID, TLAgentStreamDeltaKindContent, @"New answer");
    second.completion(nil);
    TLAssert(completions == 2 && [store.savedMessages.lastObject.content isEqual:@"New answer"],
      @"a new response can finish normally after Stop");
  }
}

static void TestAttachmentPrompt(void) {
  TLTurnTestMessageStore *store = [[TLTurnTestMessageStore alloc] init];
  TLTurnTestStream *stream = [[TLTurnTestStream alloc] init];
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
  runner.attachments = @[@{@"name":@"report.pdf", @"guestPath":@"/workspace/attachments/session/batch/report.pdf", @"directory":@NO}];
  NSString *prompt = [@"Review " stringByPaddingToLength:16000 withString:@"details " startingAtIndex:0];
  NSMutableArray *messages = [NSMutableArray array];
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:prompt
             updateHandler:nil completionHandler:nil error:nil];
  TLAssert([stream.lastMessages.lastObject.content containsString:@"report.pdf"], @"file manifest survives long-prompt compaction");
  TLAssert([stream.lastMessages.lastObject.content containsString:@"reference material"], @"wire prompt distinguishes document content from instructions");
  TLAssert([store.savedMessages.firstObject.content isEqual:prompt], @"attachment context does not replace the user's saved text");
  TLAssert(store.savedMessages.firstObject.attachments.count == 1 && store.savedMessages.lastObject.attachments.count == 0,
           @"metadata belongs only to the outgoing message");
  [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:[NSMutableArray array]
    nextPrompt:@"/help with this file" updateHandler:nil completionHandler:nil error:nil];
  TLAssert(![stream.lastMessages.lastObject.content hasPrefix:@"/"] &&
    [stream.lastMessages.lastObject.content containsString:@"/help with this file"], @"attached slash text is sent as a turn, not dispatched as a TUI command");
}

static void TestLiveToolActivity(void) {
  for (NSNumber *outcome in @[@0, @1, @2, @3]) {
    TLTurnTestMessageStore *store = [TLTurnTestMessageStore new];
    TLTurnTestStream *stream = [TLTurnTestStream new];
    stream.deferred = YES;
    TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
    NSMutableArray<TLChatMessage *> *messages = [NSMutableArray array];
    __block NSUInteger updates = 0;
    __block TLAssistantTurnResult *result;
    [runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"hello"
      updateHandler:^{ updates++; } completionHandler:^(TLAssistantTurnResult *value) { result = value; } error:nil];
    TLTurnTestRequest *request = stream.requests.lastObject;
    void (^emit)(NSString *, NSString *, NSString *) = ^(NSString *rid, NSString *identifier, NSString *state) {
      NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"id":identifier, @"name":@"terminal", @"state":state, @"detail":@"pwd"} options:0 error:nil];
      request.delta(rid, TLAgentStreamDeltaKindToolActivity, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    };
    emit(@"wrong-request", @"wrong", @"running");
    request.delta(request.requestID, TLAgentStreamDeltaKindToolActivity, @"[]");
    TLAssert(!messages.lastObject.toolActivities.count, @"malformed and foreign tool updates are ignored");
    emit(request.requestID, @"preparing:terminal", @"preparing");
    emit(request.requestID, @"a", @"running");
    TLAssert(runner.running && messages.lastObject.toolActivities.count == 1, @"preparing becomes a live running row before completion");
    TLChatMessage *snapshot = [messages.lastObject copy];
    NSUInteger before = updates;
    emit(request.requestID, @"a", @"running");
    TLAssert(updates == before, @"repeated tool snapshots do not redraw");
    emit(request.requestID, @"b", @"running");
    emit(request.requestID, @"a", @"completed");
    emit(request.requestID, @"a", @"running");
    TLAssert(messages.lastObject.toolActivities.count == 2 && [messages.lastObject.toolActivities[0][@"state"] isEqual:@"completed"],
      @"overlapping same-name tools are keyed by call ID and completed calls stay completed");
    TLAssert([snapshot.toolActivities[0][@"state"] isEqual:@"running"], @"activity snapshots are immutable");
    TLAssert(!messages.lastObject.content.length && !messages.lastObject.thinking.length &&
      ![messages.lastObject.requestDictionary.description containsString:@"terminal"], @"tool activity stays out of answer, reasoning and prompt context");
    if (outcome.integerValue == 3) request.delta(request.requestID, TLAgentStreamDeltaKindApproval, @"{\"request_id\":\"p\",\"command\":\"pwd\"}");
    if (outcome.integerValue == 2) [runner cancel];
    else request.completion(outcome.integerValue == 1 ? TLTestError(@"Disconnected") : nil);
    NSString *expected = @[@"ended", @"interrupted", @"stopped", @"paused"][outcome.unsignedIntegerValue];
    TLAssert([messages.lastObject.toolActivities.lastObject[@"state"] isEqual:expected], @"all terminal paths settle active tool rows");
    TLAssert(result.assistantMessage.toolActivities.count == 2, @"tool-only turns survive persistence replacement and failure");
    emit(request.requestID, @"b", @"completed");
    TLAssert([messages.lastObject.toolActivities.lastObject[@"state"] isEqual:expected], @"late callbacks cannot reopen a finished turn");
  }
}

static void TestRegeneration(void) {
  for (NSString *outcome in @[@"success", @"failure", @"cancel", @"save-failure"]) {
    TLTurnTestMessageStore *store = [TLTurnTestMessageStore new];
    TLTurnTestStream *stream = [TLTurnTestStream new];
    stream.deferred = YES;
    TLChatMessage *prompt = [TLChatMessage messageWithRole:TLRoleUser content:@"Explain the image" thinking:nil];
    prompt.attachments = @[@{@"path":@"/workspace/image.png", @"name":@"image.png"}];
    TLStoredChatMessage *answer = [TLStoredChatMessage messageWithRole:TLRoleAssistant content:@"Original answer" thinking:nil];
    answer.messageID = 42;
    TLChatMessage *later = [TLChatMessage messageWithRole:TLRoleUser content:@"Later question" thinking:nil];
    NSMutableArray *messages = [NSMutableArray arrayWithObjects:prompt, answer, later, nil];
    TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:store streaming:stream];
    runner.regenerationPrompt = prompt;
    runner.regenerationMessage = answer;
    runner.attachments = prompt.attachments;
    __block TLAssistantTurnResult *result;
    TLAssert([runner startTurnWithChat:TLTestChat() token:@"token" model:@"model" messages:messages nextPrompt:@"Regenerate the earlier answer"
      updateHandler:nil completionHandler:^(TLAssistantTurnResult *value) { result = value; } error:nil], @"regeneration starts");
    TLAssert(messages.count == 3 && messages[0] == prompt && messages[2] == later && store.saveCount == 0,
      @"regeneration replaces only the selected row without duplicating or saving a user prompt");
    TLAssert([stream.lastMessages.lastObject.content containsString:@"image.png"] &&
      [stream.lastMessages.lastObject.content containsString:@"attachment"], @"regeneration retains original attachment context");
    TLTurnTestRequest *request = stream.requests.lastObject;
    request.delta(request.requestID, TLAgentStreamDeltaKindContent, @"Fresh answer");
    TLAssert([((TLChatMessage *)messages[1]).content isEqual:@"Fresh answer"], @"regeneration streams into the selected answer's position");
    if ([outcome isEqual:@"save-failure"]) { store.failOnSave = 1; store.saveError = TLTestError(@"Disk full"); }
    if ([outcome isEqual:@"cancel"]) [runner cancel];
    else request.completion([outcome isEqual:@"failure"] ? TLTestError(@"Offline") : nil);
    if ([outcome isEqual:@"success"]) {
      TLAssert(((TLStoredChatMessage *)messages[1]).messageID == 42 && store.replacementCount == 1 && store.saveCount == 1,
        @"successful regeneration updates the same durable answer without adding rows");
    } else TLAssert(messages[1] == answer, @"failed, cancelled or unsaved regeneration restores the original answer");
    TLAssert(result && !runner.running && messages.count == 3 && messages[2] == later, @"regeneration completes without discarding later messages");
  }
}

int main(void) {
  @autoreleasepool {
    TestAttachmentPrompt();
    TestRegeneration();
    TestLiveToolActivity();
    TestCancellation();
    TestSuccessfulTurn();
    TestUserSaveFailure();
    TestAssistantSaveFailure();
    TestPartialStreamFailures();
    TestFailureWithoutOutput();
    TestAnswerDeltasAreImmediatelyVisible();
    TestThinkingDeltasAreImmediatelyVisible();
    TestThinkingStatusReplacesWithoutAccumulating();
    TestStructuredApproval();
    TestValidationAndStaleCallbacks();
    if (failures == 0) fprintf(stdout, "AssistantTurnResultTests passed\n");
  }
  return failures == 0 ? 0 : 1;
}
