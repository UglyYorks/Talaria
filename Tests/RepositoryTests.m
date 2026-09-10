#import "Database.h"
#import "SQLiteConnection.h"
#import "DatabaseMigrator.h"
#import "TLHistoryRepository.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSInteger ReadCount(TLSQLiteConnection *connection, const char *sql) {
  TLSQLiteStatement *statement = [connection prepareSQL:sql error:nil];
  Check(statement && [statement step] == SQLITE_ROW, @"read query succeeds");
  return sqlite3_column_int64(statement.handle, 0);
}
static int CountMessageReads(void *context, int operation, const char *table, const char *column, const char *db, const char *trigger) {
  if (operation == SQLITE_READ && table && !strcmp(table, "messages")) (*(NSUInteger *)context)++;
  return SQLITE_OK;
}

static void TestSharedSchemaVersion(NSURL *directory) {
  NSURL *url = [directory URLByAppendingPathComponent:@"shared-version.sqlite"];
  NSError *error = nil;
  TLSQLiteConnection *connection = [TLSQLiteConnection openURL:url error:&error];
  Check(connection && TLDatabaseMigrate(connection, 11, &error), @"creates pre-refactor schema");
  Check([connection executeSQL:
    "ALTER TABLE messages ADD COLUMN notification TEXT NOT NULL DEFAULT '{}';"
    "ALTER TABLE messages ADD COLUMN source_message_id TEXT NOT NULL DEFAULT '';"
    "ALTER TABLE messages ADD COLUMN source_tool_call_ids TEXT NOT NULL DEFAULT '[]';"
    "CREATE TABLE notifications (id INTEGER PRIMARY KEY, payload TEXT);"
    "INSERT INTO notifications VALUES (1, 'retained');"
    "INSERT INTO chats (id, title, model) VALUES (1, 'Retained chat', 'test');"
    "INSERT INTO messages (id, chat_id, role, content, attachments, notification, source_message_id) "
    "VALUES (7, 1, 'user', 'first', '[{\"name\":\"retained\",\"guestPath\":\"/workspace/retained\",\"directory\":false}]', '{\"read\":true}', 'remote-7'),"
    "(9, 1, 'assistant', 'second', '[]', '{}', 'remote-9');"
    "INSERT INTO browser_history (id, url, title, favicon) VALUES (1, 'https://example.com/old', 'Retained visit', X'010203');"
    "PRAGMA user_version = 12;" error:&error], @"creates another feature's version-12 database");
  TLDatabase *database = [[TLDatabase alloc] initWithURL:url error:&error];
  Check(database != nil && !error, @"startup reconciles columns despite a shared schema version");
  TLChatRecord *chat = [database chatWithID:1 error:&error];
  Check(chat.messages.count == 2 && chat.messages[0].messageID == 7 && chat.messages[1].messageID == 9,
    @"shared-version migration preserves messages and their original order");
  Check(chat.messages[0].attachments.count == 1 && chat.messages[0].position == 7,
    @"migration preserves attachments and backfills message positions");
  Check(ReadCount(connection, "SELECT COUNT(*) FROM messages WHERE source_message_id='remote-7' AND notification='{\"read\":true}'") == 1 &&
    ReadCount(connection, "SELECT COUNT(*) FROM notifications WHERE payload='retained'") == 1,
    @"migration preserves unrelated feature data");
  Check(ReadCount(connection, "SELECT COUNT(*) FROM browser_history WHERE origin='https://example.com:443' AND hex(favicon)='010203'") == 1,
    @"shared-version migration backfills origins without replacing favicons");
  Check([connection executeSQL:"UPDATE messages SET position=20 WHERE id=7; UPDATE messages SET position=10 WHERE id=9" error:&error],
    @"creates a subsequently reordered transcript");
  database = nil;
  database = [[TLDatabase alloc] initWithURL:url error:&error];
  chat = [database chatWithID:1 error:&error];
  Check(chat.messages.count == 2 && chat.messages[0].messageID == 9 && chat.messages[1].messageID == 7 &&
    ReadCount(connection, "PRAGMA user_version") == 12, @"reopening is idempotent and preserves newer transcript ordering");
}

int main(void) {
  @autoreleasepool {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    TLDatabase *database = [[TLDatabase alloc] initWithURL:[directory URLByAppendingPathComponent:@"repository.sqlite"] error:nil];
    Check(database != nil, @"opens schema 12");
    TestSharedSchemaVersion(directory);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [database performAsync:^(TLDatabase *store) {
      Check(!NSThread.isMainThread, @"repository work is off main");
      TLSQLiteConnection *connection = [store valueForKey:@"sqliteConnection"];
      NSDictionary *session = @{@"hermes_session_id":@"repeated", @"title":@"Test", @"model":@"test", @"created_at":@"2026-09-01", @"updated_at":@"2026-09-02"};
      TLChatRecord *chat = [store cacheHermesSession:session messages:nil error:nil];
      TLChatMessage *first = [TLChatMessage messageWithRole:TLRoleUser content:@"again" thinking:nil];
      first.attachments = @[@{@"name":@"first", @"guestPath":@"/workspace/first", @"directory":@NO}];
      TLStoredChatMessage *a = [store saveMessage:first chatID:chat.chatID error:nil];
      first.attachments = @[@{@"name":@"second", @"guestPath":@"/workspace/second", @"directory":@NO}];
      TLStoredChatMessage *b = [store saveMessage:first chatID:chat.chatID error:nil];
      NSArray *transcript = @[@{@"role":@"user", @"content":@"again"}, @{@"role":@"user", @"content":@"again"}];
      Check([connection executeSQL:"CREATE TABLE message_writes(value); CREATE TRIGGER writes_insert AFTER INSERT ON messages BEGIN INSERT INTO message_writes VALUES (1); END; CREATE TRIGGER writes_update AFTER UPDATE ON messages BEGIN INSERT INTO message_writes VALUES (1); END; CREATE TRIGGER writes_delete AFTER DELETE ON messages BEGIN INSERT INTO message_writes VALUES (1); END;" error:nil], @"installs write counters");
      chat = [store cacheHermesSession:session messages:transcript error:nil];
      Check(chat.messages[0].messageID == a.messageID && chat.messages[1].messageID == b.messageID, @"repeated occurrences retain distinct IDs");
      Check([chat.messages[1].attachments isEqual:b.attachments], @"repeated occurrences retain their own attachments");
      Check(ReadCount(connection, "SELECT COUNT(*) FROM message_writes") == 0, @"unchanged transcript performs zero message writes");
      NSArray *inserted = [@[@{@"role":@"assistant", @"content":@"inserted before duplicates"}] arrayByAddingObjectsFromArray:transcript];
      chat = [store cacheHermesSession:session messages:inserted error:nil];
      Check(chat.messages.count == 3 && chat.messages[1].messageID == a.messageID && chat.messages[2].messageID == b.messageID, @"inserting before existing messages preserves IDs and remote order");
      NSError *error = nil;
      Check(![store cacheHermesSession:session messages:@[@{@"role":@"bad", @"content":@"bad"}] error:&error] && error, @"malformed refresh fails");
      Check([store chatWithID:chat.chatID error:nil].messages.count == 3, @"failed refresh leaves the transcript intact");
      NSUInteger reads = 0;
      sqlite3_set_authorizer(connection.handle, CountMessageReads, &reads);
      NSArray *summaries = [store cacheHermesSessionSummaries:@[session] error:nil];
      sqlite3_set_authorizer(connection.handle, NULL, NULL);
      Check(summaries.count == 1 && reads == 0 && ![summaries[0] isKindOfClass:TLChatRecord.class], @"summary batches never hydrate transcripts");
      NSInteger special = [store recordBrowserVisitToURL:[NSURL URLWithString:@"https://example.com/caf%C3%A9"] title:@"Old visit" error:nil];
      NSData *icon = [@"fixture icon" dataUsingEncoding:NSUTF8StringEncoding];
      Check([store updateBrowserVisitWithID:special faviconData:icon error:nil], @"saves favicon");
      for (NSUInteger i = 0; i < 350; i++) Check([store recordBrowserVisitToURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://example.com/%lu", i]] title:@"Recent" error:nil] > 0, @"records visit");
      NSArray *matches = [store browserHistoryMatching:@"CAFE" before:nil limit:17 error:nil];
      Check(matches.count == 1 && [matches[0] visitID] == special, @"search includes old visits, decoded URLs and diacritics");
      NSMutableSet *ids = [NSMutableSet set];
      TLBrowserHistoryEntry *cursor = nil;
      NSUInteger pages = 0;
      while (YES) {
        NSArray *page = [store browserHistoryMatching:@"" before:cursor limit:17 error:nil];
        Check(page && page.count <= 17, @"history reads are bounded");
        if (!page.count) break;
        for (TLBrowserHistoryEntry *visit in page) {
          Check(!visit.faviconData && ![ids containsObject:@(visit.visitID)], @"pages omit icon blobs and do not overlap");
          [ids addObject:@(visit.visitID)];
        }
        cursor = page.lastObject; pages++;
        Check(pages < 30, @"pagination advances");
      }
      Check(ids.count == 351, @"pagination includes every tied timestamp");
      TLBrowserHistoryEntry *recent = [store browserHistoryMatching:@"" before:nil limit:1 error:nil].firstObject;
      Check([[store faviconForBrowserVisit:recent error:nil] isEqual:icon], @"lazy icons preserve same-origin fallback");
      dispatch_semaphore_signal(done);
    }];
    Check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) == 0, @"database queue completes without nested-dispatch deadlock");
    TLHistoryRepository *repository = [[TLHistoryRepository alloc] initWithDatabase:database];
    __block BOOL delivered = NO;
    [repository historyMatching:@"CAFE" before:nil completion:^(NSArray *page, NSError *error) {
      Check(NSThread.isMainThread && page.count == 1 && !error, @"repository delivers snapshots on main"); delivered = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!delivered && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(delivered, @"repository callback completes");
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    NSLog(@"RepositoryTests passed");
  }
}
