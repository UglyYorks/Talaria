#import <AppKit/AppKit.h>
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLChatPresentation.h"
#import "TLNotificationsController.h"
#import "AppStateManager.h"
#import "AgentOrchestrator.h"
#import "PromptBuilder.h"

static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]]; }

@interface TalariaWindowController (NotificationTests)
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)openNotification:(NSDictionary *)notification;
- (void)renderMessagesScrollingToBottom:(BOOL)scroll;
- (BOOL)revealNotificationInPresentation:(TLChatPresentation *)presentation;
- (void)refreshAgents;
@end

@interface TLNotificationTestCredentials : NSObject <TLCredentialStore> @end
@implementation TLNotificationTestCredentials
- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error { return nil; }
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error { return YES; }
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error { return YES; }
@end

@interface TLNotificationTestVM : NSObject @end
@implementation TLNotificationTestVM
- (BOOL)isAgentRunning:(TLAgentRecord *)agent { return NO; }
- (BOOL)virtualizationSupported { return NO; }
- (NSURL *)runtimeBundleURL { return nil; }
@end
@interface TLNotificationRunningTurn : NSObject
@property (nonatomic, strong) TLChatMessage *activeUserMessage;
@end
@implementation TLNotificationRunningTurn
- (BOOL)running { return YES; }
@end

@interface TLNotificationTestGateway : TLAgentOrchestrator
@property (nonatomic, strong) NSMutableArray *opens;
@property (nonatomic, strong) NSMutableArray *reads;
@property (nonatomic, strong) NSDictionary *finding;
@end
@implementation TLNotificationTestGateway
- (void)hermesNotificationsWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID
  token:(NSString *)token model:(NSString *)model completion:(void (^)(NSDictionary *, NSError *))completion {
  if ([parameters[@"action"] isEqual:@"open_source"]) {
    [self.opens addObject:[completion copy]];
  } else if ([parameters[@"action"] isEqual:@"set_read"]) {
    [self.reads addObject:@{@"agent": @(agentID), @"params": parameters}];
    NSMutableDictionary *updated = self.finding.mutableCopy;
    updated[@"is_read"] = parameters[@"read"]; updated[@"change_seq"] = @2;
    completion(@{@"notification": updated}, nil);
  }
}
@end

@interface TLNotificationTestWindow : TalariaWindowController @end
@implementation TLNotificationTestWindow
- (void)refreshHermesHistory {}
- (void)prepareHermesCommands {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (NSView *)markdownViewWithString:(NSString *)text textColor:(NSColor *)color baseFont:(NSFont *)font {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.textColor = color; label.font = font;
  return label;
}
@end

static NSDictionary *Finding(void) {
  return @{@"id": @"finding-1", @"task_id": @"job-1", @"task_name": @"Review email", @"source_kind": @"cron",
    @"run_id": @"run-1", @"session_id": @"source-session", @"message_id": @"42", @"tool_call_id": @"call-1",
    @"title": @"Payment pending", @"summary": @"Invoice 12 needs attention tomorrow.", @"urgency": @"high",
    @"finding_key": @"mail:account:12:payment", @"change_key": @"pending:tomorrow", @"version": @1,
    @"is_read": @NO, @"created_at": @"2026-09-09T01:00:00Z", @"updated_at": @"2026-09-09T01:00:00Z", @"change_seq": @1};
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
  NSError *error = nil;
  TLDatabase *database = [[TLDatabase alloc] initWithURL:[directory URLByAppendingPathComponent:@"test.sqlite"]
    credentialStore:[TLNotificationTestCredentials new] error:&error];
  Check(database != nil, error.localizedDescription);
  TLAgentRecord *agent = [database createAgentWithName:@"A" guestKind:@"linux" runtime:@"python" vmDirectory:[directory.path stringByAppendingPathComponent:@"a"] error:&error];
  TLAgentRecord *other = [database createAgentWithName:@"B" guestKind:@"linux" runtime:@"python" vmDirectory:[directory.path stringByAppendingPathComponent:@"b"] error:&error];
  Check([database setCurrentAgentID:agent.agentID error:&error], @"set selected agent");
  NSDictionary *finding = Finding();
  Check([database cacheNotification:finding agentID:agent.agentID error:&error], @"cache initial unread finding");
  TLNotificationTestGateway *gateway = [[TLNotificationTestGateway alloc] initWithDatabase:database agentClient:(id)[NSObject new] vmService:(id)[TLNotificationTestVM new]];
  gateway.opens = [NSMutableArray array]; gateway.reads = [NSMutableArray array]; gateway.finding = finding;
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,700)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLNotificationTestWindow *owner = [[TLNotificationTestWindow alloc] initWithWindow:window];
  TLAppStateManager *state = [TLAppStateManager new];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"turnRunners"];
  [owner setValue:database forKey:@"database"]; [owner setValue:gateway forKey:@"agentOrchestrator"];
  [owner setValue:[TLAppSettings defaultSettings] forKey:@"settings"];
  [owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  [owner setValue:[NSMutableArray arrayWithObjects:agent,other,nil] forKey:@"agents"];
  [owner setValue:[NSMutableArray array] forKey:@"chats"];
  [owner buildInterface]; [owner installAppStateBindings];
  [window orderFront:nil];
  [owner setValue:@(agent.agentID) forKey:@"notificationsAgentID"];
  NSMutableArray *messages = [NSMutableArray array];
  for (NSUInteger i = 0; i < 70; i++) {
    [messages addObject:i == 5 ? @{@"role": @"assistant", @"content": @"", @"source_message_id": @"42",
      @"source_tool_call_ids": @[@"call-1"], @"notification": finding} :
      @{@"role": @"user", @"content": @"Repeated text must never be used as an anchor.", @"source_message_id": @(100+i)}];
  }
  NSDictionary *reply = @{@"notification": finding, @"session": @{@"id": @"source-session", @"title": @"Review email", @"model": @"test"},
    @"source_session_id": @"source-session", @"continuation_session_id": @"continued-session", @"model": @"test", @"messages": messages};
  [owner openNotification:finding];
  Check(gateway.reads.count == 0, @"click alone does not acknowledge unread content");
  void (^complete)(NSDictionary *, NSError *) = gateway.opens.lastObject;
  complete(reply, nil); Drain();
  TLChatPresentation *presentation = [owner valueForKey:@"chatPresentation"];
  Check([presentation.chat.sourceSessionID isEqual:@"source-session"] && [presentation.chat.continuationSessionID isEqual:@"continued-session"], @"original source stays separate from reply session");
  Check(presentation.chat.sourceAgentID == agent.agentID && presentation.messages.count == 70, @"source is imported into owning agent");
  Check(gateway.reads.count == 1 && [gateway.reads[0][@"params"][@"version"] isEqual:@1], @"only displayed revision acknowledged after reveal");
  TLChatMessage *target = presentation.messages[5];
  NSView *row = [presentation.messageRowViews objectForKey:target];
  NSRect rowRect = [row convertRect:row.bounds toView:presentation.messageDocumentView];
  Check(NSIntersectsRect(rowRect, presentation.messageScrollView.documentVisibleRect), @"exact tool-only invocation visible");
  Check(presentation.suppressAutomaticScroll, @"explicit navigation suppresses automatic bottom scrolling");
  [owner renderMessagesScrollingToBottom:YES]; Drain();
  Check(NSIntersectsRect([row convertRect:row.bounds toView:presentation.messageDocumentView], presentation.messageScrollView.documentVisibleRect), @"later rendering preserves the source position");
  Check(gateway.reads.count == 1, @"layout updates do not acknowledge again");
  presentation.messages[5].content = @"Stale cached content";
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply,nil); Drain();
  presentation = [owner valueForKey:@"chatPresentation"];
  Check([presentation.messages[5].content isEqual:@""], @"idle cached presentation is refreshed");
  NSMutableDictionary *runners = [owner valueForKey:@"turnRunners"];
  TLNotificationRunningTurn *running = [TLNotificationRunningTurn new];
  runners[@(presentation.chat.chatID)] = running;
  [presentation.messages addObject:[TLChatMessage messageWithRole:TLRoleAssistant content:@"In flight" thinking:nil]];
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply,nil); Drain();
  Check(presentation.messages.count == 71, @"opening during streaming preserves in-flight messages");
  [presentation.messages removeObjectAtIndex:5];
  TLChatMessage *liveUser = [TLChatMessage messageWithRole:TLRoleUser content:@"Follow up" thinking:nil];
  running.activeUserMessage = liveUser;
  [presentation.messages addObject:liveUser];
  NSMutableArray *liveArray = presentation.messages;
  NSUInteger missingCount = liveArray.count;
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply,nil); Drain();
  Check(presentation.messages == liveArray && presentation.messages.count == missingCount + 1 &&
    [presentation.messages[5].sourceMessageID isEqual:@"42"] && presentation.messages.lastObject == liveUser,
    @"flattened History restores missing tool-only source without replacing active turn objects");
  NSUInteger openCount = gateway.opens.count;
  [owner openNotification:finding]; complete = gateway.opens.lastObject;
  [runners removeAllObjects];
  TLStoredChatMessage *finished = [database saveMessage:[TLChatMessage messageWithRole:TLRoleAssistant
    content:@"Completed continuation reply" thinking:nil] chatID:presentation.chat.chatID error:&error];
  [presentation.messages addObject:finished];
  complete(reply, nil); Drain();
  Check(gateway.opens.count == openCount + 2 && presentation.messages.lastObject == finished,
    @"a turn finishing during source loading triggers a fresh snapshot without discarding its reply");
  [messages addObject:@{@"role": @"assistant", @"content": finished.content, @"source_message_id": @300}];
  complete = gateway.opens.lastObject; complete(reply, nil); Drain();
  presentation = [owner valueForKey:@"chatPresentation"];
  Check([presentation.messages.lastObject.sourceMessageID isEqual:@"300"] &&
    [presentation.messages[5].sourceMessageID isEqual:@"42"], @"fresh continuation history retains the original anchor and completed reply");
  openCount = gateway.opens.count;
  [owner openNotification:finding]; complete = gateway.opens.lastObject;
  finished = [database saveMessage:[TLChatMessage messageWithRole:TLRoleAssistant
    content:@"Another turn started and finished" thinking:nil] chatID:presentation.chat.chatID error:&error];
  [presentation.messages addObject:finished];
  complete(reply, nil); Drain();
  Check(gateway.opens.count == openCount + 2 && presentation.messages.lastObject == finished,
    @"a turn starting and finishing during source loading also invalidates the older snapshot");
  [messages addObject:@{@"role": @"assistant", @"content": finished.content, @"source_message_id": @301}];
  complete = gateway.opens.lastObject; complete(reply, nil); Drain();
  presentation = [owner valueForKey:@"chatPresentation"];
  TLChatMessage *approval = [TLChatMessage messageWithRole:TLRoleAssistant content:@"Awaiting approval" thinking:nil];
  approval.approvalRequest = @{@"id": @"approval-test"};
  [presentation.messages addObject:approval];
  liveArray = presentation.messages;
  NSMutableDictionary *retainedTurns = [NSMutableDictionary dictionaryWithObject:liveArray forKey:@(presentation.chat.chatID)];
  [owner setValue:retainedTurns forKey:@"turnMessagesByChat"];
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply, nil); Drain();
  Check(presentation.messages == liveArray && presentation.messages.lastObject == approval && approval.approvalRequest != nil,
    @"source navigation preserves an actionable paused approval after its runner exits");
  [retainedTurns removeAllObjects];
  NSMutableSet *preparing = [NSMutableSet setWithObject:@(presentation.chat.chatID)];
  [owner setValue:preparing forKey:@"preparingAttachmentChats"];
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply, nil); Drain();
  Check(presentation.messages == liveArray && presentation.messages.lastObject == approval,
    @"source navigation preserves arrays captured by attachment preparation");
  [preparing removeAllObjects];
  NSUInteger readCount = gateway.reads.count;
  [owner openNotification:finding]; complete = gateway.opens.lastObject; complete(reply,nil);
  [window orderOut:nil]; Drain();
  Check(gateway.reads.count == readCount, @"hidden window never acknowledges unseen content");
  [window orderFront:nil]; [owner renderMessagesScrollingToBottom:NO]; Drain();
  Check(gateway.reads.count == readCount + 1, @"pending source acknowledges after it becomes visible");
  readCount = gateway.reads.count;
  [owner openNotification:finding]; complete = gateway.opens.lastObject;
  [database setCurrentAgentID:other.agentID error:nil]; [owner refreshAgents];
  Check([[owner valueForKey:@"notificationsAgentID"] integerValue] == other.agentID &&
    ((TLNotificationsController *)[owner valueForKey:@"notificationsController"]).notifications.count == 0,
    @"agent switch immediately replaces the inbox");
  [database setCurrentAgentID:agent.agentID error:nil]; [owner refreshAgents]; complete(reply,nil); Drain();
  Check(gateway.reads.count == readCount, @"agent switch invalidates pending open and read acknowledgement");
  [database setCurrentAgentID:agent.agentID error:nil];
  [owner openNotification:finding]; void (^oldComplete)(NSDictionary *, NSError *) = gateway.opens.lastObject;
  [owner openNotification:finding]; oldComplete(reply,nil); Drain();
  Check(gateway.reads.count == readCount, @"newer navigation invalidates older completion");
  complete = gateway.opens.lastObject; complete(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Source deleted"}]);
  Check(gateway.reads.count == readCount && [[owner valueForKey:@"notificationsController"] errorMessage].length > 0, @"missing source stays unread and reports an error");
  Check([[TLPromptBuilder notificationToolDescription] containsString:@"finding_key"], @"tool instructions built natively");
  [window close]; owner = nil; gateway = nil; database = nil;
  [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
  NSLog(@"Notification navigation tests passed");
  return 0;
} }
