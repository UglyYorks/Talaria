#import <Foundation/Foundation.h>
#import "Database.h"
#import "DatabaseMigrator.h"
#import "SQLiteConnection.h"
#import "AgentOrchestrator.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TLNotificationTestCredentials : NSObject <TLCredentialStore>
@end
@implementation TLNotificationTestCredentials
- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error { return nil; }
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error { return YES; }
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error { return YES; }
@end

@interface TLNotificationTestVM : TLAgentVMService
@property (nonatomic) BOOL running;
@property (nonatomic) NSInteger startCount;
@property (nonatomic) NSInteger startedAgentID;
@end
@implementation TLNotificationTestVM
- (BOOL)isAgentRunning:(TLAgentRecord *)agent { return self.running; }
- (void)startAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion {
  self.startCount += 1; self.startedAgentID = agent.agentID; self.running = YES; completion(nil);
}
@end

@interface TLNotificationTestClient : NSObject
@property (nonatomic) NSInteger capturedAgentID;
@property (nonatomic, copy) NSString *capturedSessionID;
@property (nonatomic, copy) NSDictionary *capturedParameters;
@end
@implementation TLNotificationTestClient
- (void)hermesNotificationsWithAgent:(TLAgentRecord *)agent parameters:(NSDictionary *)parameters token:(NSString *)token model:(NSString *)model completion:(void (^)(NSDictionary *, NSError *))completion {
  self.capturedAgentID = agent.agentID; self.capturedParameters = parameters; completion(@{}, nil);
}
- (void)selectHermesModelWithAgent:(TLAgentRecord *)agent sessionID:(NSString *)sessionID token:(NSString *)token model:(NSString *)model completion:(TLAgentStreamCompletionHandler)completion {
  self.capturedAgentID = agent.agentID; self.capturedSessionID = sessionID; completion(nil);
}
- (void)streamHermesSessionWithAgent:(TLAgentRecord *)agent requestID:(NSString *)requestID sessionID:(NSString *)sessionID token:(NSString *)token model:(NSString *)model prompt:(NSString *)prompt delta:(TLAgentStreamDeltaHandler)delta completion:(TLAgentStreamCompletionHandler)completion {
  self.capturedAgentID = agent.agentID; self.capturedSessionID = sessionID; completion(nil);
}
@end

static void TestOwnerRouting(TLDatabase *db, NSURL *folder) {
  NSError *error = nil;
  TLAgentRecord *a = [db createAgentWithName:@"A" avatar:@"A" soul:@"" folderPaths:@[] vmDirectory:[folder.path stringByAppendingPathComponent:@"a"] error:&error];
  TLAgentRecord *b = [db createAgentWithName:@"B" avatar:@"B" soul:@"" folderPaths:@[] vmDirectory:[folder.path stringByAppendingPathComponent:@"b"] error:&error];
  Check(a && b && [db setCurrentAgentID:b.agentID error:&error], [NSString stringWithFormat:@"creates two owners and selects a different current agent: %@", error]);
  TLNotificationTestClient *client = [TLNotificationTestClient new];
  TLNotificationTestVM *vm = [[TLNotificationTestVM alloc] initWithAgentsDirectoryURL:folder runtimeBundleURL:folder];
  vm.running = YES;
  TLAgentOrchestrator *orchestrator = [[TLAgentOrchestrator alloc] initWithDatabase:db agentClient:(id<TLAgentStreaming>)client vmService:vm];
  __block BOOL completed = NO;
  [orchestrator streamChatWithAgentID:a.agentID requestID:@"owned-request" sessionID:@"continuation"
    token:@"test" model:@"test" messages:@[[TLChatMessage messageWithRole:TLRoleUser content:@"Reply" thinking:nil]]
    delta:^(NSString *requestID, TLAgentStreamDeltaKind kind, NSString *text) {} completion:^(NSError *error) { completed = error == nil; }];
  Check(completed && client.capturedAgentID == a.agentID && [client.capturedSessionID isEqual:@"continuation"], @"notification replies use source owner after the selected agent changes");
  [orchestrator selectModel:@"model" sessionID:@"continuation" agentID:a.agentID token:@"test" completion:^(NSError *error) {}];
  Check(client.capturedAgentID == a.agentID, @"notification model changes keep their source owner");
  vm.running = NO; completed = NO;
  [orchestrator hermesNotificationsWithParameters:@{@"action": @"sync"} agentID:a.agentID token:@"test" model:@"test"
    completion:^(NSDictionary *result, NSError *error) { completed = error != nil; }];
  Check(completed && vm.startCount == 0, @"background notification synchronization never starts a stopped VM");
  [orchestrator hermesNotificationsWithParameters:@{@"action": @"open_source", @"id": @"n-1", @"version": @1}
    agentID:a.agentID token:@"test" model:@"test" completion:^(NSDictionary *result, NSError *error) { completed = error == nil; }];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:0.1];
  while (limit.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:limit];
  Check(completed && vm.startCount == 1 && vm.startedAgentID == a.agentID && client.capturedAgentID == a.agentID,
    @"opening a source starts only the requested owner");
  Check([client.capturedParameters[@"notification_tool_description"] length] > 0, @"native prompt builder supplies notification tool guidance");
}

static NSDictionary *Notification(NSString *identifier, NSInteger version, NSInteger sequence, BOOL read) {
  return @{@"id": identifier, @"title": @"Payment pending", @"summary": @"Review the overdue invoice.",
    @"task_id": @"email", @"task_name": @"Daily Email Summary", @"source_kind": @"cron", @"run_id": @"run-1",
    @"session_id": @"original", @"message_id": @42, @"tool_call_id": @"call-1", @"urgency": @"high",
    @"finding_key": @"invoice-1", @"change_key": @"overdue", @"version": @(version), @"change_seq": @(sequence),
    @"is_read": @(read), @"created_at": @"2026-09-09", @"updated_at": @"2026-09-09"};
}
static NSDictionary *Page(NSString *generation, NSInteger cursor, BOOL reset, NSArray *rows) {
  return @{@"generation": generation, @"cursor": @(cursor), @"reset": @(reset), @"has_more": @NO, @"notifications": rows};
}
static TLDatabase *Open(NSURL *url) {
  NSError *error = nil;
  TLDatabase *db = [[TLDatabase alloc] initWithURL:url credentialStore:[TLNotificationTestCredentials new] error:&error];
  Check(db != nil, [NSString stringWithFormat:@"database opens: %@", error]);
  return db;
}

static void TestSharedSchemaVersions(NSURL *folder) {
  for (NSNumber *version in @[@9, @10, @11]) {
    NSError *error = nil;
    NSURL *url = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"browser-%@.sqlite", version]];
    TLSQLiteConnection *connection = [TLSQLiteConnection openURL:url error:&error];
    Check(TLDatabaseMigrate(connection, version.integerValue, &error), @"creates browser schema fixture");
    Check([connection executeSQL:"INSERT INTO chats(title,model,hermes_session_id) VALUES('Keep chat','model','s');"
      "INSERT INTO messages(chat_id,role,content,attachments) VALUES(1,'user','Keep message','[]');"
      "INSERT INTO browser_history(url,title) VALUES('https://example.com','Keep visit');" error:&error], @"seeds historical tables");
    if (version.integerValue >= 10) Check([connection executeSQL:"UPDATE browser_history SET favicon=x'010203'" error:&error], @"seeds binary favicon");
    if (version.integerValue == 11) Check([connection executeSQL:"INSERT INTO bookmarks(name,chat_id,emoji,favicon) VALUES('Keep bookmark',1,'star','saved-icon')" error:&error], @"seeds chat bookmark");
    Check(TLDatabaseMigrate(connection, 12, &error), [NSString stringWithFormat:@"migrates browser schema %@: %@", version, error]);
    Check(TLDatabaseMigrate(connection, 12, &error), @"repeat migration is safe");
    TLSQLiteStatement *check = [connection prepareSQL:"SELECT content,source_message_id FROM messages WHERE id=1" error:&error];
    Check([check step] == SQLITE_ROW && [[check stringAtColumn:0] isEqual:@"Keep message"] && [[check stringAtColumn:1] isEqual:@""], @"preserves chat rows while adding canonical identities");
    check = [connection prepareSQL:"SELECT title,hex(favicon) FROM browser_history WHERE id=1" error:&error];
    Check([check step] == SQLITE_ROW && [[check stringAtColumn:0] isEqual:@"Keep visit"] &&
      (version.integerValue < 10 || [[check stringAtColumn:1] isEqual:@"010203"]), @"preserves browser history and binary favicon");
    if (version.integerValue == 11) {
      check = [connection prepareSQL:"SELECT name,chat_id,favicon FROM bookmarks WHERE id=1" error:&error];
      Check([check step] == SQLITE_ROW && [[check stringAtColumn:0] isEqual:@"Keep bookmark"] && sqlite3_column_int(check.handle,1)==1 && [[check stringAtColumn:2] isEqual:@"saved-icon"], @"preserves bookmark and its chat reference");
    }
  }
  NSError *error = nil;
  TLSQLiteConnection *connection = [TLSQLiteConnection openURL:[folder URLByAppendingPathComponent:@"early-notifications.sqlite"] error:&error];
  Check(TLDatabaseMigrate(connection, 12, &error), @"creates notification schema fixture");
  Check([connection executeSQL:"DROP TABLE bookmarks; DROP TABLE browser_history; PRAGMA user_version=9;"
    "INSERT INTO notifications VALUES(1,'keep',1,1,'{}');" error:&error], @"reproduces the earlier notification-only version 9");
  Check(TLDatabaseMigrate(connection, 12, &error), @"merges notification-only version 9 with browser additions");
  TLSQLiteStatement *check = [connection prepareSQL:"SELECT notification_id FROM notifications" error:&error];
  Check([check step] == SQLITE_ROW && [[check stringAtColumn:0] isEqual:@"keep"], @"preserves existing notification data");
  check = nil;
  Check([connection executeSQL:"PRAGMA user_version=13" error:&error], @"creates unknown future version fixture");
  Check(!TLDatabaseMigrate(connection, 12, &error) && error != nil, @"still rejects unknown newer databases");
}

int main(void) { @autoreleasepool {
  NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
  TestSharedSchemaVersions(folder);
  NSURL *url = [folder URLByAppendingPathComponent:@"notifications.sqlite"];
  NSError *error = nil;
  TLSQLiteConnection *legacy = [TLSQLiteConnection openURL:url error:&error];
  Check(TLDatabaseMigrate(legacy, 8, &error), @"builds an actual version-8 migration fixture");
  Check([legacy executeSQL:"INSERT INTO chats(title,model,hermes_session_id) VALUES('Old chat','model','original');"
    "INSERT INTO messages(chat_id,role,content) VALUES(1,'user','Preserved');" error:&error], @"creates legacy conversation");
  legacy = nil;
  TLDatabase *db = Open(url);
  TLChatRecord *old = [db chatWithID:1 error:&error];
  Check(old.sourceAgentID == 0 && [old.messages.firstObject.content isEqual:@"Preserved"], @"migration preserves unassigned legacy history");

  NSDictionary *session = @{@"id": @"original", @"title": @"Daily summary", @"model": @"model", @"source_session_id": @"original",
    @"continuation_session_id": @"continuation", @"created_at": @"2026-09-09", @"updated_at": @"2026-09-09"};
  NSDictionary *source = @{@"role": @"assistant", @"content": @"", @"source_message_id": @42,
    @"source_tool_call_ids": @[@"call-1"], @"notification": Notification(@"n-1", 1, 1, NO)};
  TLChatRecord *first = [db cacheHermesSession:session messages:@[source] agentID:1 error:&error];
  Check(first.chatID == old.chatID && first.sourceAgentID == 1, @"authoritative import claims only the matching unassigned chat");
  TLChatRecord *second = [db cacheHermesSession:session messages:@[source] agentID:2 error:&error];
  Check(second.chatID != first.chatID && second.sourceAgentID == 2, @"identical session IDs from distinct agents stay separate");
  Check([db chatWithHermesSessionID:@"original" agentID:1 error:&error].chatID == first.chatID, @"session lookup respects owner");
  TLChatMessage *copy = [first.messages.firstObject copy];
  Check([copy.sourceMessageID isEqual:@"42"] && [copy.sourceToolCallIDs isEqual:@[@"call-1"]] &&
    [copy.notification[@"id"] isEqual:@"n-1"], @"source metadata survives import and copy even when the message is empty");
  NSInteger previousLocalID = first.messages.firstObject.messageID;
  first = [db cacheHermesSession:session messages:@[source, source] agentID:1 error:&error];
  Check(first.messages.firstObject.messageID != previousLocalID && [first.messages.firstObject.sourceMessageID isEqual:@"42"],
    @"recaching changes local IDs without changing source anchors");
  NSMutableDictionary *continued = [session mutableCopy];
  continued[@"source_session_id"] = @"unexpected-new-source"; continued[@"continuation_session_id"] = @"latest";
  first = [db cacheHermesSession:continued messages:nil agentID:1 error:&error];
  Check([first.sourceSessionID isEqual:@"original"] && [first.continuationSessionID isEqual:@"latest"],
    @"continuation updates never move the original source");
  TLStoredChatMessage *saved = [db saveMessage:copy chatID:first.chatID error:&error];
  Check([saved.sourceMessageID isEqual:@"42"] && [saved.notification[@"id"] isEqual:@"n-1"], @"ordinary persistence retains durable metadata");

  // The original notification session may compress to a continuation. A fresh
  // source response must include subsequent authored rows from that lineage.
  TLChatMessage *followup = [TLChatMessage messageWithRole:TLRoleUser content:@"What should I do next?" thinking:nil];
  TLChatMessage *reply = [TLChatMessage messageWithRole:TLRoleAssistant content:@"Contact the sender." thinking:nil];
  Check([db saveMessage:followup chatID:first.chatID error:&error] != nil &&
    [db saveMessage:reply chatID:first.chatID error:&error] != nil, @"completed continuation replies are initially cached in the source tab");
  NSArray *lineage = @[source,
    @{@"role": @"user", @"content": followup.content, @"source_message_id": @70},
    @{@"role": @"assistant", @"content": reply.content, @"source_message_id": @71}];
  NSMutableDictionary *lineageSession = [session mutableCopy];
  lineageSession[@"continuation_session_id"] = @"latest";
  TLChatRecord *reopened = [db cacheHermesSession:lineageSession messages:lineage agentID:1 error:&error];
  Check(reopened.chatID == first.chatID && reopened.sourceAgentID == 1 && [reopened.sourceSessionID isEqual:@"original"] &&
    [reopened.continuationSessionID isEqual:@"latest"], @"lineage refresh preserves source tab, original session, and owner while routing replies to its continuation");
  Check(reopened.messages.count == 3 && [reopened.messages.firstObject.sourceMessageID isEqual:@"42"] &&
    [reopened.messages.firstObject.notification[@"id"] isEqual:@"n-1"] &&
    [reopened.messages[1].content isEqual:followup.content] && [reopened.messages.lastObject.content isEqual:reply.content] &&
    [reopened.messages.lastObject.sourceMessageID isEqual:@"71"], @"reopening the source preserves both its exact anchor and completed continuation replies");
  NSMutableDictionary *aliased = [session mutableCopy];
  aliased[@"id"] = @"other-source"; aliased[@"source_session_id"] = @"other-source"; aliased[@"hermes_session_id"] = @"talaria-alias";
  TLChatRecord *aliasChat = [db cacheHermesSession:aliased messages:@[] agentID:1 error:&error];
  [aliased removeObjectForKey:@"hermes_session_id"];
  TLChatRecord *notificationChat = [db cacheHermesSession:aliased messages:@[source] agentID:1 error:&error];
  Check(aliasChat.chatID == notificationChat.chatID && [notificationChat.hermesSessionID isEqual:@"talaria-alias"],
    @"notification source imports reuse an existing History alias and its tab");
  Check([db chatWithHermesSessionID:@"other-source" agentID:1 error:&error].chatID == aliasChat.chatID,
    @"original source lookup resolves existing owned aliases");
  Check([db applyNotificationSyncResult:Page(@"generation-a", 1, YES, @[Notification(@"n-1", 1, 1, NO)]) agentID:1 error:&error], @"first page is cached");
  Check([db applyNotificationSyncResult:Page(@"generation-b", 1, YES, @[Notification(@"n-1", 1, 1, NO)]) agentID:2 error:&error], @"another agent has its own cache");
  Check([db cacheNotification:Notification(@"n-1", 1, 2, YES) agentID:1 error:&error], @"read response persists");
  Check([db applyNotificationSyncResult:Page(@"generation-a", 1, NO, @[Notification(@"n-1", 1, 1, NO)]) agentID:1 error:&error], @"replayed page is harmless");
  Check([[db notificationsForAgentID:1 error:&error].firstObject[@"is_read"] boolValue], @"older sync cannot overwrite a read acknowledgement");
  Check([db cacheNotification:Notification(@"n-1", 2, 3, NO) agentID:1 error:&error], @"changed finding persists unread revision");
  Check([db cacheNotification:Notification(@"n-1", 1, 2, YES) agentID:1 error:&error], @"old read response is harmless");
  Check(![[db notificationsForAgentID:1 error:&error].firstObject[@"is_read"] boolValue], @"old read acknowledgement cannot consume a new revision");
  error = nil;
  Check(![db applyNotificationSyncResult:Page(@"generation-a", 4, NO, @[Notification(@"n-2", 1, 4, NO), @{@"id": @"invalid"}]) agentID:1 error:&error] && error != nil,
    @"invalid page fails atomically");
  Check([db notificationsForAgentID:1 error:nil].count == 1 && [[db notificationSyncStateForAgentID:1 error:nil][@"cursor"] isEqual:@1],
    @"partial records and cursor both roll back");
  error = nil;
  Check(![db applyNotificationSyncResult:Page(@"unknown-generation", 4, NO, @[]) agentID:1 error:&error], @"changed generation requires explicit reset");
  Check([db applyNotificationSyncResult:Page(@"generation-c", 0, YES, @[]) agentID:1 error:&error], @"generation reset clears only its own cache");
  Check([db notificationsForAgentID:1 error:nil].count == 0 && [db notificationsForAgentID:2 error:nil].count == 1, @"reset cannot erase another agent's notifications");
  db = nil;
  db = Open(url);
  Check([[db notificationSyncStateForAgentID:1 error:nil][@"generation"] isEqual:@"generation-c"] &&
    [db notificationsForAgentID:2 error:nil].count == 1, @"cache and cursor survive reopening");
  Check([[db chatWithID:first.chatID error:nil].sourceSessionID isEqual:@"original"], @"original session identity survives reopening");
  TestOwnerRouting(db, folder);
  db = nil;
  [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
  NSLog(@"Notification data tests passed.");
  return 0;
} }
