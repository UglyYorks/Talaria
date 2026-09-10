#import "Database.h"
#import "DatabaseMigrator.h"
#import "SQLiteConnection.h"

static NSInteger const TLDatabaseSchemaVersion = 12;

typedef BOOL (^TLDatabaseTransactionBlock)(NSError **error);

static void TLSetDatabaseError(NSError **error, NSString *message) {
  TLSetSQLiteError(error, message);
}

static NSString *TLStringFromColumn(sqlite3_stmt *statement, int column) {
  const unsigned char *text = sqlite3_column_text(statement, column);
  if (!text) {
    return @"";
  }

  return [NSString stringWithUTF8String:(const char *)text] ?: @"";
}

static NSString *TLNullableStringFromColumn(sqlite3_stmt *statement, int column) {
  if (sqlite3_column_type(statement, column) == SQLITE_NULL) {
    return nil;
  }

  return TLStringFromColumn(statement, column);
}

static NSString *TLTrimmedString(NSString *value) {
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *TLNonBlank(NSString *value, NSString *fallback) {
  NSString *trimmed = TLTrimmedString(value);
  return trimmed.length > 0 ? trimmed : fallback;
}

static NSString *TLTitleFromMessage(NSString *content) {
  NSArray<NSString *> *parts = [content componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSMutableArray<NSString *> *words = [NSMutableArray array];

  for (NSString *part in parts) {
    if (part.length > 0) {
      [words addObject:part];
    }
  }

  NSString *title = [[words componentsJoinedByString:@" "] substringToIndex:MIN((NSUInteger)48, [words componentsJoinedByString:@" "].length)];
  return title.length > 0 ? title : @"New chat";
}


static NSString *TLSourceIdentity(id value) {
  return [value isKindOfClass:NSString.class] ? value : ([value isKindOfClass:NSNumber.class] ? [value stringValue] : @"");
}

static BOOL TLValidSourceMetadata(id calls, id notification) {
  if (![calls isKindOfClass:NSArray.class] || ![notification isKindOfClass:NSDictionary.class] ||
      ![NSJSONSerialization isValidJSONObject:notification]) return NO;
  for (id call in calls) if (![call isKindOfClass:NSString.class]) return NO;
  return YES;
}

static NSString *TLJSONText(id value, NSError **error) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:error];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static id TLJSONValue(NSString *text) {
  return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

@interface TLDatabase ()

@property (nonatomic, strong) TLSQLiteConnection *sqliteConnection;
@property (nonatomic, readwrite, getter=isIncognito) BOOL incognito;
@property (nonatomic, copy) NSString *incognitoToken;
@property (nonatomic, strong) id<TLCredentialStore> credentialStore;

- (BOOL)executeSQL:(const char *)sql error:(NSError **)error;
- (BOOL)performTransaction:(TLDatabaseTransactionBlock)block error:(NSError **)error;

@end

@implementation TLDatabase

- (TLDatabase *)incognitoDatabase:(NSError **)error {
  @synchronized (self) {
    TLDatabase *copy = [TLDatabase new];
    copy.incognito = YES;
    copy.incognitoToken = [self appSettings:error].openRouterToken;
    copy.sqliteConnection = [TLSQLiteConnection openInMemory:error];
    if (!copy.sqliteConnection) return nil;
    sqlite3_backup *backup = sqlite3_backup_init(copy.sqliteConnection.handle, "main", self.sqliteConnection.handle, "main");
    if (!backup) { [copy.sqliteConnection setCurrentError:error]; return nil; }
    int result = sqlite3_backup_step(backup, -1);
    sqlite3_backup_finish(backup);
    if (result != SQLITE_DONE) { [copy.sqliteConnection setCurrentError:error]; return nil; }
    if (![copy executeSQL:"PRAGMA foreign_keys=ON; PRAGMA temp_store=MEMORY; DELETE FROM messages; DELETE FROM bookmarks; DELETE FROM chats; DELETE FROM browser_history; DELETE FROM notifications; DELETE FROM notification_sync;" error:error]) return nil;
    return copy;
  }
}

+ (NSURL *)defaultDatabaseURL {
  NSURL *supportURL = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
  return [[supportURL URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES]
    URLByAppendingPathComponent:@"talaria.sqlite3"];
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
  return [self initWithURL:url credentialStore:[[TLKeychainCredentialStore alloc] init] error:error];
}

- (instancetype)initWithURL:(NSURL *)url credentialStore:(id<TLCredentialStore>)credentialStore error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }
  _credentialStore = credentialStore;

  NSURL *directoryURL = [url URLByDeletingLastPathComponent];
  if (![NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:error]) {
    return nil;
  }

  _sqliteConnection = [TLSQLiteConnection openURL:url error:error];
  if (!_sqliteConnection) {
    return nil;
  }

  if (![self initializeSchema:error]) {
    return nil;
  }

  return self;
}

- (NSArray<TLBookmark *> *)listBookmarks:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "SELECT id, name, url, chat_id, emoji, favicon FROM bookmarks ORDER BY id" error:error];
    if (!statement) return nil;
    NSMutableArray *bookmarks = [NSMutableArray array];
    int result;
    while ((result = [statement step]) == SQLITE_ROW) {
      TLBookmark *bookmark = [TLBookmark new];
      bookmark.bookmarkID = sqlite3_column_int64(statement.handle, 0);
      bookmark.name = [statement stringAtColumn:1];
      NSString *address = [statement nullableStringAtColumn:2];
      bookmark.URL = address.length ? [NSURL URLWithString:address] : nil;
      bookmark.chatID = sqlite3_column_int64(statement.handle, 3);
      bookmark.emoji = [statement stringAtColumn:4];
      bookmark.faviconData = [[NSData alloc] initWithBase64EncodedString:[statement stringAtColumn:5] options:0];
      [bookmarks addObject:bookmark];
    }
    if (result != SQLITE_DONE) { [self.sqliteConnection setCurrentError:error]; return nil; }
    return bookmarks;
  }
}

- (BOOL)saveBookmark:(TLBookmark *)bookmark error:(NSError **)error {
  @synchronized (self) {
    NSString *name = TLTrimmedString(bookmark.name);
    NSURL *URL = bookmark.URL ? [TLBookmark normalizedURL:bookmark.URL.absoluteString] : nil;
    if (!name.length || (bookmark.chatID <= 0 && !URL) || (bookmark.chatID > 0 && bookmark.URL)) {
      TLSetDatabaseError(error, @"Enter a name and a valid website address or conversation.");
      return NO;
    }
    // Saving the same destination again updates its label/icon without duplicating it.
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "INSERT INTO bookmarks (name, url, chat_id, emoji, favicon) VALUES (?1, ?2, ?3, ?4, ?5) "
      "ON CONFLICT DO UPDATE SET name=excluded.name, emoji=excluded.emoji, favicon=excluded.favicon" error:error];
    if (!statement) return NO;
    [statement bindText:name atIndex:1];
    if (URL) [statement bindText:URL.absoluteString atIndex:2]; else [statement bindNullAtIndex:2];
    if (bookmark.chatID > 0) [statement bindInt64:bookmark.chatID atIndex:3]; else [statement bindNullAtIndex:3];
    [statement bindText:bookmark.emoji ?: TLDefaultChatIcon() atIndex:4];
    [statement bindText:[bookmark.faviconData base64EncodedStringWithOptions:0] ?: @"" atIndex:5];
    return [statement stepDone:error];
  }
}

- (BOOL)deleteBookmarkWithID:(NSInteger)bookmarkID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:"DELETE FROM bookmarks WHERE id=?1" error:error];
    if (!statement) return NO;
    [statement bindInt64:bookmarkID atIndex:1];
    return [statement stepDone:error];
  }
}

- (TLAppSettings *)appSettings:(NSError **)error {
  @synchronized (self) {
    NSDictionary<NSString *, NSString *> *values = [self storedSettings:error];
    if (!values) {
      return nil;
    }
    BOOL remember = [values[@"rememberOpenRouterToken"] isEqualToString:@"true"];
    if (![self migrateLegacyCredentialWithRemember:remember error:error]) {
      return nil;
    }

    NSError *credentialError = nil;
    NSString *token = self.incognito ? self.incognitoToken : remember ? [self.credentialStore credentialForAccount:TLOpenRouterTokenCredentialAccount
                                                                    error:&credentialError] : nil;
    if (credentialError) {
      if (error) { *error = credentialError; }
      return nil;
    }

    TLAppSettings *settings = [[TLAppSettings alloc] init];
    settings.rememberOpenRouterToken = remember;
    settings.openRouterToken = token ?: @"";
    settings.selectedModel = values[@"selectedModel"] ?: TLDefaultModelID;
    settings.supportingModel = values[@"supportingModel"] ?: TLDefaultSupportingModelID;
    // Older versions stored a manual override. Talaria now always follows macOS.
    settings.theme = TLThemePreferenceSystem;
    settings.onboardingCompleted = [values[@"onboardingCompleted"] isEqualToString:@"true"];
    return settings;
  }
}

- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error {
  @synchronized (self) {
    NSString *selectedModel = TLNonBlank(settings.selectedModel, TLDefaultModelID);
    NSString *supportingModel = TLNonBlank(settings.supportingModel, TLDefaultSupportingModelID);
    NSString *theme = @"system";
    NSString *token = settings.rememberOpenRouterToken ? TLTrimmedString(settings.openRouterToken) : nil;
    NSError *credentialError = nil;
    NSString *previousToken = self.incognito ? self.incognitoToken : [self.credentialStore credentialForAccount:TLOpenRouterTokenCredentialAccount error:&credentialError];
    if (credentialError) {
      if (error) { *error = credentialError; }
      return nil;
    }
    __block BOOL credentialChanged = NO;

    NSError *saveError = nil;
    BOOL saved = [self performTransaction:^BOOL(NSError **transactionError) {
      if (![self setSetting:@"rememberOpenRouterToken" value:settings.rememberOpenRouterToken ? @"true" : @"false" error:transactionError]) {
        return NO;
      }
      if (![self setSetting:@"selectedModel" value:selectedModel error:transactionError]) {
        return NO;
      }
      if (![self setSetting:@"supportingModel" value:supportingModel error:transactionError]) {
        return NO;
      }
      if (![self recordDefaultModelsForAgentID:self.currentAgentID model:selectedModel supportingModel:supportingModel error:transactionError]) return NO;
      if (![self setSetting:@"theme" value:theme error:transactionError]) {
        return NO;
      }
      if (![self setSetting:@"onboardingCompleted" value:settings.onboardingCompleted ? @"true" : @"false" error:transactionError]) {
        return NO;
      }
      if (![self removeLegacyCredential:transactionError]) {
        return NO;
      }
      if ([previousToken isEqualToString:token] || (!previousToken && !token)) {
        return YES;
      }
      credentialChanged = [self storeToken:token error:transactionError];
      return credentialChanged;
    } error:&saveError];
    if (!saved) {
      // SQLite and Keychain cannot share a transaction. If COMMIT failed after
      // changing Keychain, restore its prior value before reporting the failure.
      NSError *restoreError = nil;
      if (credentialChanged && ![self storeToken:previousToken error:&restoreError]) {
        saveError = [NSError errorWithDomain:TLSQLiteErrorDomain code:2 userInfo:@{
          NSLocalizedDescriptionKey: @"Settings could not be saved, and the previous Keychain credential could not be restored. Please save the token again.",
          NSUnderlyingErrorKey: saveError ?: restoreError,
          @"credentialRestoreError": restoreError
        }];
      }
      if (error) { *error = saveError; }
      return nil;
    }

    TLAppSettings *savedSettings = [settings copy];
    savedSettings.selectedModel = selectedModel;
    savedSettings.supportingModel = supportingModel;
    savedSettings.theme = TLThemePreferenceFromString(theme);
    return savedSettings;
  }
}

// Hermes owns history. These records only adapt it to Talaria's existing tab/message cache.
- (nullable TLChatRecord *)cacheHermesSession:(NSDictionary *)session
                                   messages:(nullable NSArray<NSDictionary *> *)messages
                                      error:(NSError **)error {
  return [self cacheHermesSession:session messages:messages agentID:0 error:error];
}

- (TLChatRecord *)cacheHermesSession:(NSDictionary *)session messages:(NSArray<NSDictionary *> *)messages
                           agentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    NSString *(^string)(id) = ^NSString *(id value) { return [value isKindOfClass:NSString.class] ? value : @""; };
    NSString *sessionID = string(session[@"hermes_session_id"]);
    if (!sessionID.length) sessionID = string(session[@"id"]);
    NSString *sourceID = string(session[@"source_session_id"]);
    if (!sourceID.length) sourceID = string(session[@"id"]);
    NSString *continuationID = string(session[@"continuation_session_id"]);
    if (!sessionID.length) { TLSetDatabaseError(error, @"Hermes session identity is missing."); return nil; }
    // History can use a Talaria alias while notification links use the stored
    // Hermes ID. Both refer to the same owned chat, never its continuation.
    if (agentID > 0 && sourceID.length) {
      TLChatRecord *existing = [self chatWithHermesSessionID:sourceID agentID:agentID error:error];
      if (existing) sessionID = existing.hermesSessionID;
    }
    __block NSInteger chatID = 0;
    BOOL saved = [self performTransaction:^BOOL(NSError **transactionError) {
      // An authoritative import may claim an unowned legacy chat, but never another agent's chat.
      if (agentID > 0) {
        TLSQLiteStatement *claim = [self.sqliteConnection prepareSQL:
          "UPDATE chats SET source_agent_id = ?1 WHERE source_agent_id = 0 AND hermes_session_id = ?2 "
          "AND NOT EXISTS (SELECT 1 FROM chats WHERE source_agent_id = ?1 AND hermes_session_id = ?2)" error:transactionError];
        if (!claim) return NO;
        [claim bindInt64:agentID atIndex:1]; [claim bindText:sessionID atIndex:2];
        if (![claim stepDone:transactionError]) return NO;
      }
      TLSQLiteStatement *upsert = [self.sqliteConnection prepareSQL:
        "INSERT INTO chats (title, model, icon, hermes_session_id, created_at, updated_at, source_agent_id, source_session_id, continuation_session_id) "
        "VALUES (?1, ?2, '', ?3, ?4, ?5, ?6, ?7, ?8) ON CONFLICT(source_agent_id, hermes_session_id) DO UPDATE SET "
        "title = excluded.title, model = CASE WHEN excluded.model = '' THEN chats.model ELSE excluded.model END, "
        "created_at = excluded.created_at, updated_at = excluded.updated_at, "
        "source_session_id = CASE WHEN chats.source_session_id = '' THEN excluded.source_session_id ELSE chats.source_session_id END, "
        "continuation_session_id = CASE WHEN excluded.continuation_session_id = '' THEN chats.continuation_session_id ELSE excluded.continuation_session_id END" error:transactionError];
      if (!upsert) return NO;
      [upsert bindText:string(session[@"title"]) atIndex:1];
      [upsert bindText:string(session[@"model"]) atIndex:2];
      [upsert bindText:sessionID atIndex:3];
      [upsert bindText:string(session[@"created_at"]) atIndex:4];
      [upsert bindText:string(session[@"updated_at"]) atIndex:5];
      [upsert bindInt64:agentID atIndex:6];
      [upsert bindText:sourceID atIndex:7];
      [upsert bindText:continuationID atIndex:8];
      if (![upsert stepDone:transactionError]) return NO;
      TLSQLiteStatement *lookup = [self.sqliteConnection prepareSQL:"SELECT id FROM chats WHERE hermes_session_id = ?1 AND source_agent_id = ?2" error:transactionError];
      if (!lookup) return NO;
      [lookup bindText:sessionID atIndex:1];
      [lookup bindInt64:agentID atIndex:2];
      if ([lookup step] != SQLITE_ROW) { [self.sqliteConnection setCurrentError:transactionError]; return NO; }
      chatID = sqlite3_column_int64(lookup.handle, 0);
      sqlite3_reset(lookup.handle);
      if (!messages) return YES;
      TLChatRecord *previous = [self loadChatWithID:chatID error:transactionError];
      if (!previous) return NO;
      TLSQLiteStatement *remove = [self.sqliteConnection prepareSQL:"DELETE FROM messages WHERE chat_id = ?1" error:transactionError];
      if (!remove) return NO;
      [remove bindInt64:chatID atIndex:1];
      if (![remove stepDone:transactionError]) return NO;
      NSMutableArray<TLStoredChatMessage *> *oldMessages = [previous.messages mutableCopy];
      for (id item in messages) {
        if (![item isKindOfClass:NSDictionary.class] || ![self isValidRole:string(item[@"role"])] ||
            ![item[@"content"] isKindOfClass:NSString.class]) {
          TLSetDatabaseError(transactionError, @"Hermes returned an invalid transcript.");
          return NO; // Rolls back both the transcript and metadata.
        }
        NSArray *attachments = @[];
        NSString *thinking = string(item[@"thinking"]);
        // Attachment files belong to Talaria; retain their descriptors on matching turns.
        for (TLStoredChatMessage *old in [oldMessages copy]) {
          if ([old.role isEqual:item[@"role"]] && [old.content isEqual:item[@"content"]]) {
            attachments = old.attachments ?: @[];
            if (!thinking.length) thinking = old.thinking ?: @"";
            [oldMessages removeObjectIdenticalTo:old];
            break;
          }
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:attachments options:0 error:transactionError];
        if (!data) return NO;
        TLSQLiteStatement *insert = [self.sqliteConnection prepareSQL:
          "INSERT INTO messages (chat_id, role, content, thinking, attachments, created_at, source_message_id, source_tool_call_ids, notification) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
          error:transactionError];
        if (!insert) return NO;
        [insert bindInt64:chatID atIndex:1];
        [insert bindText:item[@"role"] atIndex:2];
        [insert bindText:item[@"content"] atIndex:3];
        [insert bindText:thinking atIndex:4];
        [insert bindText:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] atIndex:5];
        [insert bindText:string(item[@"created_at"]) atIndex:6];
        [insert bindText:TLSourceIdentity(item[@"source_message_id"]) atIndex:7];
        NSArray *calls = item[@"source_tool_call_ids"] ?: @[];
        NSDictionary *notification = item[@"notification"] ?: @{};
        if (!TLValidSourceMetadata(calls, notification)) { TLSetDatabaseError(transactionError, @"Hermes returned invalid source metadata."); return NO; }
        [insert bindText:TLJSONText(calls, transactionError) atIndex:8];
        [insert bindText:TLJSONText(notification, transactionError) atIndex:9];
        if (![insert stepDone:transactionError]) return NO;
      }
      return YES;
    } error:error];
    return saved ? [self loadChatWithID:chatID error:error] : nil;
  }
}

- (NSInteger)recordBrowserVisitToURL:(NSURL *)URL title:(NSString *)title error:(NSError **)error {
  if (self.incognito) return 0;
  NSString *scheme = URL.scheme.lowercaseString;
  if ((![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) || !URL.host.length) return 0;
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "INSERT INTO browser_history (url, title, favicon) VALUES (?1, ?2, "
      "(SELECT favicon FROM browser_history WHERE url = ?1 AND favicon IS NOT NULL ORDER BY id DESC LIMIT 1))" error:error];
    if (!statement) return 0;
    [statement bindText:URL.absoluteString atIndex:1];
    [statement bindText:title.length ? title : URL.absoluteString atIndex:2];
    return [statement stepDone:error] ? self.sqliteConnection.lastInsertRowID : 0;
  }
}

- (BOOL)updateBrowserVisitWithID:(NSInteger)visitID title:(NSString *)title error:(NSError **)error {
  if (visitID <= 0 || !title.length) return YES;
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "UPDATE browser_history SET title = ?1 WHERE id = ?2" error:error];
    if (!statement) return NO;
    [statement bindText:title atIndex:1];
    [statement bindInt64:visitID atIndex:2];
    return [statement stepDone:error];
  }
}

- (BOOL)updateBrowserVisitWithID:(NSInteger)visitID faviconData:(NSData *)data error:(NSError **)error {
  if (visitID <= 0 || !data.length) return YES;
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "UPDATE browser_history SET favicon = ?1 WHERE id = ?2" error:error];
    if (!statement) return NO;
    sqlite3_bind_blob64(statement.handle, 1, data.bytes, data.length, SQLITE_TRANSIENT);
    [statement bindInt64:visitID atIndex:2];
    return [statement stepDone:error];
  }
}

- (NSArray<TLBrowserHistoryEntry *> *)listBrowserHistory:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "SELECT id, url, title, visited_at, favicon FROM browser_history ORDER BY visited_at DESC, id DESC" error:error];
    if (!statement) return nil;
    NSMutableArray<TLBrowserHistoryEntry *> *entries = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSData *> *siteIcons = [NSMutableDictionary dictionary];
    int result;
    while ((result = [statement step]) == SQLITE_ROW) {
      TLBrowserHistoryEntry *entry = [TLBrowserHistoryEntry new];
      entry.visitID = sqlite3_column_int64(statement.handle, 0);
      entry.URLString = [statement stringAtColumn:1];
      entry.title = [statement stringAtColumn:2];
      entry.visitedAt = [statement stringAtColumn:3];
      int length = sqlite3_column_bytes(statement.handle, 4);
      if (length > 0) {
        entry.faviconData = [NSData dataWithBytes:sqlite3_column_blob(statement.handle, 4) length:(NSUInteger)length];
        NSString *origin = TLBrowserHistoryOrigin([NSURL URLWithString:entry.URLString]);
        if (origin && !siteIcons[origin]) siteIcons[origin] = entry.faviconData;
      }
      [entries addObject:entry];
    }
    if (result != SQLITE_DONE) { [self.sqliteConnection setCurrentError:error]; return nil; }
    // Older visits can use the newest saved icon from the same website. Preserve
    // page-specific icons when present, and never fetch icons while reading history.
    for (TLBrowserHistoryEntry *entry in entries) {
      NSString *origin = TLBrowserHistoryOrigin([NSURL URLWithString:entry.URLString]);
      if (!entry.faviconData && origin) entry.faviconData = siteIcons[origin];
    }
    return entries;
  }
}

- (BOOL)deleteBrowserVisitWithID:(NSInteger)visitID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:"DELETE FROM browser_history WHERE id = ?1" error:error];
    if (!statement) return NO;
    [statement bindInt64:visitID atIndex:1];
    return [statement stepDone:error];
  }
}

- (TLChatRecord *)chatWithHermesSessionID:(NSString *)sessionID agentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "SELECT id FROM chats WHERE source_agent_id = ?1 AND (hermes_session_id = ?2 OR source_session_id = ?2) "
      "ORDER BY CASE WHEN hermes_session_id = ?2 THEN 0 ELSE 1 END, id LIMIT 1" error:error];
    if (!statement) return nil;
    [statement bindInt64:agentID atIndex:1]; [statement bindText:sessionID atIndex:2];
    int result = [statement step];
    if (result == SQLITE_ROW) {
      NSInteger chatID = sqlite3_column_int64(statement.handle, 0);
      sqlite3_reset(statement.handle);
      return [self loadChatWithID:chatID error:error];
    }
    if (result != SQLITE_DONE) [self.sqliteConnection setCurrentError:error];
    return nil;
  }
}

- (NSArray<NSDictionary *> *)notificationsForAgentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "SELECT payload FROM notifications WHERE agent_id = ?1 ORDER BY change_seq DESC, notification_id" error:error];
    if (!statement) return nil;
    [statement bindInt64:agentID atIndex:1];
    NSMutableArray *rows = [NSMutableArray array];
    int result;
    while ((result = [statement step]) == SQLITE_ROW) {
      id notification = TLJSONValue([statement stringAtColumn:0]);
      if (![notification isKindOfClass:NSDictionary.class]) { TLSetDatabaseError(error, @"Invalid cached notification."); return nil; }
      [rows addObject:notification];
    }
    if (result != SQLITE_DONE) { [self.sqliteConnection setCurrentError:error]; return nil; }
    return rows;
  }
}

- (NSDictionary *)notificationSyncStateForAgentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "SELECT generation, cursor FROM notification_sync WHERE agent_id = ?1" error:error];
    if (!statement) return nil;
    [statement bindInt64:agentID atIndex:1];
    int result = [statement step];
    if (result == SQLITE_ROW) {
      NSDictionary *state = @{@"generation": [statement stringAtColumn:0], @"cursor": @(sqlite3_column_int64(statement.handle, 1))};
      sqlite3_reset(statement.handle);
      return state;
    }
    if (result != SQLITE_DONE) { [self.sqliteConnection setCurrentError:error]; return nil; }
    return @{@"generation": @"", @"cursor": @0};
  }
}

- (BOOL)storeNotification:(NSDictionary *)notification agentID:(NSInteger)agentID error:(NSError **)error {
  if (agentID <= 0 || ![notification isKindOfClass:NSDictionary.class] || ![NSJSONSerialization isValidJSONObject:notification]) {
    TLSetDatabaseError(error, @"Invalid notification data."); return NO;
  }
  for (NSString *key in @[@"id", @"title", @"task_id", @"session_id"]) {
    if (![notification[key] isKindOfClass:NSString.class] || ![notification[key] length]) {
      TLSetDatabaseError(error, @"A notification is missing its source or title."); return NO;
    }
  }
  for (NSString *key in @[@"change_seq", @"version", @"is_read"]) {
    if (![notification[key] isKindOfClass:NSNumber.class] || [notification[key] longLongValue] < 0) {
      TLSetDatabaseError(error, @"A notification has invalid revision data."); return NO;
    }
  }
  NSString *json = TLJSONText(notification, error);
  if (!json) return NO;
  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
    "INSERT INTO notifications(agent_id, notification_id, change_seq, version, payload) VALUES (?1, ?2, ?3, ?4, ?5) "
    "ON CONFLICT(agent_id, notification_id) DO UPDATE SET change_seq = excluded.change_seq, version = excluded.version, payload = excluded.payload "
    "WHERE excluded.change_seq >= notifications.change_seq AND excluded.version >= notifications.version" error:error];
  if (!statement) return NO;
  [statement bindInt64:agentID atIndex:1]; [statement bindText:notification[@"id"] atIndex:2];
  [statement bindInt64:[notification[@"change_seq"] longLongValue] atIndex:3];
  [statement bindInt64:[notification[@"version"] longLongValue] atIndex:4]; [statement bindText:json atIndex:5];
  return [statement stepDone:error];
}

- (BOOL)cacheNotification:(NSDictionary *)notification agentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    return [self performTransaction:^BOOL(NSError **transactionError) {
      return [self storeNotification:notification agentID:agentID error:transactionError];
    } error:error];
  }
}

- (BOOL)applyNotificationSyncResult:(NSDictionary *)result agentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    if (agentID <= 0 || ![result isKindOfClass:NSDictionary.class] ||
        ![result[@"generation"] isKindOfClass:NSString.class] || ![result[@"generation"] length] ||
        ![result[@"cursor"] isKindOfClass:NSNumber.class] || [result[@"cursor"] longLongValue] < 0 ||
        ![result[@"notifications"] isKindOfClass:NSArray.class] ||
        ![result[@"reset"] isKindOfClass:NSNumber.class] || ![result[@"has_more"] isKindOfClass:NSNumber.class]) {
      TLSetDatabaseError(error, @"Hermes returned invalid notification sync data."); return NO;
    }
    return [self performTransaction:^BOOL(NSError **transactionError) {
      NSDictionary *state = [self notificationSyncStateForAgentID:agentID error:transactionError];
      if (!state) return NO;
      BOOL reset = [result[@"reset"] boolValue];
      if ([state[@"generation"] length] && ![state[@"generation"] isEqual:result[@"generation"]] && !reset) {
        TLSetDatabaseError(transactionError, @"Notification generation changed. Restart synchronization."); return NO;
      }
      if (!reset && [state[@"cursor"] longLongValue] > [result[@"cursor"] longLongValue]) {
        TLSetDatabaseError(transactionError, @"Notification sync response is stale."); return NO;
      }
      if (reset) {
        TLSQLiteStatement *remove = [self.sqliteConnection prepareSQL:"DELETE FROM notifications WHERE agent_id = ?1" error:transactionError];
        if (!remove) return NO;
        [remove bindInt64:agentID atIndex:1]; if (![remove stepDone:transactionError]) return NO;
      }
      for (id notification in result[@"notifications"]) {
        if (![self storeNotification:notification agentID:agentID error:transactionError]) return NO;
      }
      TLSQLiteStatement *save = [self.sqliteConnection prepareSQL:
        "INSERT INTO notification_sync(agent_id, generation, cursor) VALUES (?1, ?2, ?3) "
        "ON CONFLICT(agent_id) DO UPDATE SET generation = excluded.generation, cursor = excluded.cursor" error:transactionError];
      if (!save) return NO;
      [save bindInt64:agentID atIndex:1]; [save bindText:result[@"generation"] atIndex:2];
      [save bindInt64:[result[@"cursor"] longLongValue] atIndex:3];
      return [save stepDone:transactionError];
    } error:error];
  }
}

- (NSArray<TLChatSummary *> *)listChats:(NSError **)error {
  @synchronized (self) {
    const char *sql =
      "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model, source_agent_id, source_session_id, continuation_session_id "
      "FROM chats "
      "ORDER BY datetime(updated_at) DESC, id DESC";

    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
    if (!statement) {
      return nil;
    }

    NSMutableArray<TLChatSummary *> *chats = [NSMutableArray array];
    int result = SQLITE_ROW;

    while ((result = [statement step]) == SQLITE_ROW) {
      [chats addObject:[self chatSummaryFromStatement:statement.handle]];
    }

    if (result != SQLITE_DONE) {
      [self.sqliteConnection setCurrentError:error];
      return nil;
    }

    return chats;
  }
}

- (TLChatRecord *)createChatWithModel:(NSString *)model error:(NSError **)error {
  @synchronized (self) {
    NSString *small = [self settingForKey:@"supportingModel" error:error] ?: TLDefaultSupportingModelID;
    return [self createChatWithModel:model supportingModel:small error:error];
  }
}

- (TLChatRecord *)createChatWithModel:(NSString *)model supportingModel:(NSString *)supportingModel error:(NSError **)error {
  @synchronized (self) {
    __block sqlite3_int64 chatID = 0;
    BOOL created = [self performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "INSERT INTO chats (title, model, hermes_session_id, supporting_model, created_at, updated_at, source_agent_id) "
        "VALUES ('New chat', ?1, ?2, ?3, datetime('now'), datetime('now'), ?4)";

      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindText:TLNonBlank(model, TLDefaultModelID) atIndex:1];
      [statement bindText:[@"talaria_" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString] atIndex:2];
      [statement bindText:TLNonBlank(supportingModel, TLDefaultSupportingModelID) atIndex:3];
      [statement bindInt64:self.currentAgentID atIndex:4];
      if (![statement stepDone:transactionError]) {
        return NO;
      }

      chatID = [self.sqliteConnection lastInsertRowID];
      return YES;
    } error:error];
    if (!created) {
      return nil;
    }

    return [self loadChatWithID:chatID error:error];
  }
}

- (BOOL)saveModelsForChatID:(NSInteger)chatID model:(NSString *)model supportingModel:(NSString *)supportingModel error:(NSError **)error {
  @synchronized (self) {
    if (!TLTrimmedString(model).length || !TLTrimmedString(supportingModel).length) {
      TLSetDatabaseError(error, @"Choose both a large and small model.");
      return NO;
    }
    return [self performTransaction:^BOOL(NSError **transactionError) {
      if (chatID > 0) {
        if (![self loadChatSummaryWithID:chatID error:transactionError]) return NO;
        TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
          "UPDATE chats SET model = ?1, supporting_model = ?2 WHERE id = ?3" error:transactionError];
        if (!statement) return NO;
        [statement bindText:model atIndex:1];
        [statement bindText:supportingModel atIndex:2];
        [statement bindInt64:chatID atIndex:3];
        if (![statement stepDone:transactionError]) return NO;
      }
      return [self setSetting:@"selectedModel" value:model error:transactionError] &&
        [self setSetting:@"supportingModel" value:supportingModel error:transactionError] &&
        [self recordDefaultModelsForAgentID:self.currentAgentID model:model supportingModel:supportingModel error:transactionError];
    } error:error];
  }
}

- (TLChatRecord *)chatWithID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    return [self loadChatWithID:chatID error:error];
  }
}

- (TLChatSummary *)saveChatTitle:(NSString *)title chatID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    NSString *trimmedTitle = TLTrimmedString(title);
    if (trimmedTitle.length == 0) {
      TLSetDatabaseError(error, @"Chat title cannot be empty.");
      return nil;
    }

    BOOL saved = [self performTransaction:^BOOL(NSError **transactionError) {
      const char *sql = "UPDATE chats SET title = ?1, updated_at = datetime('now') WHERE id = ?2";
      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindText:trimmedTitle atIndex:1];
      [statement bindInt64:chatID atIndex:2];
      return [statement stepDone:transactionError];
    } error:error];
    if (!saved) {
      return nil;
    }

    return [self loadChatSummaryWithID:chatID error:error];
  }
}

- (TLChatSummary *)saveChatIcon:(NSString *)icon chatID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    NSString *trimmedIcon = TLTrimmedString(icon);
    if (trimmedIcon.length == 0) {
      TLSetDatabaseError(error, @"Chat icon cannot be empty.");
      return nil;
    }

    BOOL saved = [self performTransaction:^BOOL(NSError **transactionError) {
      const char *sql = "UPDATE chats SET icon = ?1 WHERE id = ?2";
      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindText:trimmedIcon atIndex:1];
      [statement bindInt64:chatID atIndex:2];
      return [statement stepDone:transactionError];
    } error:error];
    if (!saved) {
      return nil;
    }

    return [self loadChatSummaryWithID:chatID error:error];
  }
}

- (TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    if (![self isValidRole:message.role]) {
      TLSetDatabaseError(error, @"Messages must use system, user, or assistant roles.");
      return nil;
    }

    __block TLStoredChatMessage *savedMessage = nil;
    BOOL saved = [self performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "INSERT INTO messages (chat_id, role, content, thinking, attachments, created_at, source_message_id, source_tool_call_ids, notification) "
        "VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'), ?6, ?7, ?8)";

      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindInt64:chatID atIndex:1];
      [statement bindText:message.role atIndex:2];
      [statement bindText:message.content atIndex:3];
      if (!TLValidSourceMetadata(message.sourceToolCallIDs, message.notification ?: @{})) { TLSetDatabaseError(transactionError, @"Invalid message source metadata."); return NO; }
      [statement bindText:message.sourceMessageID ?: @"" atIndex:6];
      [statement bindText:TLJSONText(message.sourceToolCallIDs, transactionError) atIndex:7];
      [statement bindText:TLJSONText(message.notification ?: @{}, transactionError) atIndex:8];
      NSData *attachmentData = [NSJSONSerialization dataWithJSONObject:message.attachments ?: @[] options:0 error:transactionError];
      if (!attachmentData) return NO;
      [statement bindText:[[NSString alloc] initWithData:attachmentData encoding:NSUTF8StringEncoding] atIndex:5];

      if (message.thinking.length > 0) {
        [statement bindText:message.thinking atIndex:4];
      } else {
        [statement bindNullAtIndex:4];
      }

      if (![statement stepDone:transactionError]) {
        return NO;
      }

      sqlite3_int64 messageID = [self.sqliteConnection lastInsertRowID];
      if ([message.role isEqualToString:TLRoleUser]) {
        if (![self updateTitleForUserMessage:message.content chatID:chatID error:transactionError]) {
          return NO;
        }
      } else if (![self touchChatWithID:chatID error:transactionError]) {
        return NO;
      }

      savedMessage = [self loadMessageWithID:messageID error:transactionError];
      return savedMessage != nil;
    } error:error];
    if (!saved) {
      return nil;
    }

    return savedMessage;
  }
}

- (TLStoredChatMessage *)replaceMessage:(TLChatMessage *)message messageID:(NSInteger)messageID chatID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    __block TLStoredChatMessage *saved = nil;
    BOOL replaced = [self performTransaction:^BOOL(NSError **transactionError) {
      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
        "UPDATE messages SET content = ?1, thinking = ?2 WHERE id = ?3 AND chat_id = ?4 AND role = 'assistant'"
        error:transactionError];
      if (!statement) return NO;
      [statement bindText:message.content atIndex:1];
      if (message.thinking.length) [statement bindText:message.thinking atIndex:2];
      else [statement bindNullAtIndex:2];
      [statement bindInt64:messageID atIndex:3];
      [statement bindInt64:chatID atIndex:4];
      if (![statement stepDone:transactionError]) return NO;
      if (sqlite3_changes(self.sqliteConnection.handle) != 1) {
        TLSetDatabaseError(transactionError, @"Answer was not found in this chat.");
        return NO;
      }
      if (![self touchChatWithID:chatID error:transactionError]) return NO;
      saved = [self loadMessageWithID:messageID error:transactionError];
      return saved != nil;
    } error:error];
    return replaced ? saved : nil;
  }
}

- (BOOL)deleteMessageWithID:(NSInteger)messageID chatID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    return [self performTransaction:^BOOL(NSError **transactionError) {
      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
        "DELETE FROM messages WHERE id = ?1 AND chat_id = ?2 AND role IN ('user', 'assistant')"
        error:transactionError];
      if (!statement) { return NO; }
      [statement bindInt64:messageID atIndex:1];
      [statement bindInt64:chatID atIndex:2];
      if (![statement stepDone:transactionError]) { return NO; }
      if (sqlite3_changes(self.sqliteConnection.handle) != 1) {
        TLSetDatabaseError(transactionError, @"Message was not found in this chat.");
        return NO;
      }
      return [self touchChatWithID:chatID error:transactionError];
    } error:error];
  }
}

- (TLChatRecord *)clearChatWithID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    BOOL cleared = [self performTransaction:^BOOL(NSError **transactionError) {
      TLSQLiteStatement *deleteStatement = [self.sqliteConnection prepareSQL:"DELETE FROM messages WHERE chat_id = ?1" error:transactionError];
      if (!deleteStatement) {
        return NO;
      }
      [deleteStatement bindInt64:chatID atIndex:1];
      BOOL deleted = [deleteStatement stepDone:transactionError];

      if (!deleted) {
        return NO;
      }

      const char *sql = "UPDATE chats SET title = 'New chat', icon = '', updated_at = datetime('now') WHERE id = ?1";
      TLSQLiteStatement *updateStatement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!updateStatement) {
        return NO;
      }
      [updateStatement bindInt64:chatID atIndex:1];
      return [updateStatement stepDone:transactionError];
    } error:error];
    if (!cleared) {
      return nil;
    }

    return [self loadChatWithID:chatID error:error];
  }
}

- (BOOL)deleteChatWithID:(NSInteger)chatID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:"DELETE FROM chats WHERE id = ?1" error:error];
    if (!statement) {
      return NO;
    }
    [statement bindInt64:chatID atIndex:1];
    return [statement stepDone:error];
  }
}

- (NSArray<TLAgentRecord *> *)listAgents:(NSError **)error {
  @synchronized (self) {
    const char *sql =
      "SELECT id, name, guest_kind, runtime, status, vm_directory, last_error, created_at, updated_at, avatar, soul, folder_paths "
      "FROM agents "
      "ORDER BY id ASC";

    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
    if (!statement) {
      return nil;
    }

    NSMutableArray<TLAgentRecord *> *agents = [NSMutableArray array];
    int result = SQLITE_ROW;

    while ((result = [statement step]) == SQLITE_ROW) {
      [agents addObject:[self agentFromStatement:statement.handle]];
    }

    if (result != SQLITE_DONE) {
      [self.sqliteConnection setCurrentError:error];
      return nil;
    }

    return agents;
  }
}

- (TLAgentRecord *)createAgentWithName:(NSString *)name
                             guestKind:(NSString *)guestKind
                               runtime:(NSString *)runtime
                           vmDirectory:(NSString *)vmDirectory
                                 error:(NSError **)error {
  if (![self isValidAgentGuestKind:guestKind] || ![self isValidAgentRuntime:runtime]) {
    TLSetDatabaseError(error, @"Only local Linux agents are supported.");
    return nil;
  }
  return [self createAgentWithName:name avatar:@"🤖" soul:@"" folderPaths:@[] vmDirectory:vmDirectory error:error];
}

- (TLAgentRecord *)createAgentWithName:(NSString *)name avatar:(NSString *)avatar
                                 soul:(NSString *)soul folderPaths:(NSArray<NSString *> *)folderPaths
                          vmDirectory:(NSString *)vmDirectory error:(NSError **)error {
  @synchronized (self) {
    NSString *agentName = TLNonBlank(name, @"Agent");
    NSString *agentGuestKind = TLAgentGuestKindLinux;
    NSString *agentRuntime = TLAgentRuntimePython;
    NSString *agentVMDirectory = vmDirectory.stringByStandardizingPath;
    NSData *folderData = [NSJSONSerialization dataWithJSONObject:folderPaths options:0 error:error];
    if (!folderData || !agentVMDirectory.isAbsolutePath) {
      TLSetDatabaseError(error, @"An agent requires its own local VM directory.");
      return nil;
    }

    if (![self isValidAgentGuestKind:agentGuestKind]) {
      TLSetDatabaseError(error, @"Agent guest kind is not supported.");
      return nil;
    }
    if (![self isValidAgentRuntime:agentRuntime]) {
      TLSetDatabaseError(error, @"Agent runtime is not supported.");
      return nil;
    }

    __block sqlite3_int64 agentID = 0;
    BOOL created = [self performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "INSERT INTO agents (name, guest_kind, runtime, status, vm_directory, last_error, created_at, updated_at, avatar, soul, folder_paths) "
        "VALUES (?1, ?2, ?3, ?4, ?5, NULL, datetime('now'), datetime('now'), ?6, ?7, ?8)";

      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindText:agentName atIndex:1];
      [statement bindText:agentGuestKind atIndex:2];
      [statement bindText:agentRuntime atIndex:3];
      [statement bindText:TLAgentStatusStopped atIndex:4];
      [statement bindText:agentVMDirectory atIndex:5];
      [statement bindText:TLNonBlank(avatar, @"🤖") atIndex:6];
      [statement bindText:soul ?: @"" atIndex:7];
      [statement bindText:[[NSString alloc] initWithData:folderData encoding:NSUTF8StringEncoding] atIndex:8];
      if (![statement stepDone:transactionError]) {
        return NO;
      }

      agentID = [self.sqliteConnection lastInsertRowID];
      return YES;
    } error:error];
    if (!created) {
      return nil;
    }

    return [self loadAgentWithID:agentID error:error];
  }
}

- (NSInteger)currentAgentID {
  @synchronized (self) {
    NSInteger savedID = [[self settingForKey:@"currentAgentID" error:nil] integerValue];
    NSArray<TLAgentRecord *> *agents = [self listAgents:nil];
    for (TLAgentRecord *agent in agents) {
      if (agent.agentID == savedID) return savedID;
    }
    return agents.lastObject.agentID;
  }
}

- (BOOL)recordDefaultModelsForAgentID:(NSInteger)agentID model:(NSString *)model supportingModel:(NSString *)supportingModel error:(NSError **)error {
  if (agentID <= 0) return YES;
  return [self setSetting:[NSString stringWithFormat:@"agent.%ld.model", (long)agentID] value:model error:error] &&
    [self setSetting:[NSString stringWithFormat:@"agent.%ld.supportingModel", (long)agentID] value:supportingModel error:error];
}

- (BOOL)saveDefaultModel:(NSString *)model forAgentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    if (![self agentWithID:agentID error:error] || !TLTrimmedString(model).length) return NO;
    return [self performTransaction:^BOOL(NSError **transactionError) {
      if (![self recordDefaultModelsForAgentID:agentID model:model supportingModel:model error:transactionError]) return NO;
      if (self.currentAgentID == agentID) {
        return [self setSetting:@"selectedModel" value:model error:transactionError] &&
          [self setSetting:@"supportingModel" value:model error:transactionError];
      }
      return YES;
    } error:error];
  }
}

- (BOOL)setCurrentAgentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    if (![self loadAgentWithID:agentID error:error]) return NO;
    return [self performTransaction:^BOOL(NSError **transactionError) {
      if (![self setSetting:@"currentAgentID" value:[@(agentID) stringValue] error:transactionError]) return NO;
      NSString *model = [self settingForKey:[NSString stringWithFormat:@"agent.%ld.model", (long)agentID] error:transactionError];
      if (!model.length) return YES;
      NSString *supporting = [self settingForKey:[NSString stringWithFormat:@"agent.%ld.supportingModel", (long)agentID] error:transactionError] ?: model;
      return [self setSetting:@"selectedModel" value:model error:transactionError] &&
        [self setSetting:@"supportingModel" value:supporting error:transactionError];
    } error:error];
  }
}

- (TLAgentRecord *)agentWithID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    return [self loadAgentWithID:agentID error:error];
  }
}

- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID
                              status:(NSString *)status
                           lastError:(NSString *)lastError
                               error:(NSError **)error {
  @synchronized (self) {
    NSString *agentStatus = TLNonBlank(status, TLAgentStatusStopped);
    if (![self isValidAgentStatus:agentStatus]) {
      TLSetDatabaseError(error, @"Agent status is not supported.");
      return nil;
    }

    const char *sql =
      "UPDATE agents "
      "SET status = ?1, last_error = ?2, updated_at = datetime('now') "
      "WHERE id = ?3";

    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
    if (!statement) {
      return nil;
    }

    [statement bindText:agentStatus atIndex:1];
    if (lastError.length > 0) {
      [statement bindText:lastError atIndex:2];
    } else {
      [statement bindNullAtIndex:2];
    }
    [statement bindInt64:agentID atIndex:3];

    if (![statement stepDone:error]) {
      return nil;
    }

    return [self loadAgentWithID:agentID error:error];
  }
}

- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID folderPaths:(NSArray<NSString *> *)folderPaths error:(NSError **)error {
  @synchronized (self) {
    if (![self loadAgentWithID:agentID error:error]) return nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:folderPaths options:0 error:error];
    if (!data) return nil;
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "UPDATE agents SET folder_paths = ?1, updated_at = datetime('now') WHERE id = ?2" error:error];
    if (!statement) return nil;
    [statement bindText:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] atIndex:1];
    [statement bindInt64:agentID atIndex:2];
    if (![statement stepDone:error]) return nil;
    return [self loadAgentWithID:agentID error:error];
  }
}

- (TLAgentRecord *)updateAgentWithID:(NSInteger)agentID name:(NSString *)name
                             avatar:(NSString *)avatar soul:(NSString *)soul error:(NSError **)error {
  @synchronized (self) {
    if (![self loadAgentWithID:agentID error:error]) return nil;
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
      "UPDATE agents SET name = ?1, avatar = ?2, soul = ?3, updated_at = datetime('now') WHERE id = ?4" error:error];
    if (!statement) return nil;
    [statement bindText:name atIndex:1];
    [statement bindText:avatar atIndex:2];
    [statement bindText:soul atIndex:3];
    [statement bindInt64:agentID atIndex:4];
    if (![statement stepDone:error]) return nil;
    return [self loadAgentWithID:agentID error:error];
  }
}

- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:"DELETE FROM agents WHERE id = ?1" error:error];
    if (!statement) {
      return NO;
    }
    [statement bindInt64:agentID atIndex:1];
    return [statement stepDone:error];
  }
}

- (BOOL)initializeSchema:(NSError **)error {
  // Erase removed legacy secrets from SQLite pages as well as the settings row.
  if (![self executeSQL:"PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON" error:error]) {
    return NO;
  }

  return TLDatabaseMigrate(self.sqliteConnection, TLDatabaseSchemaVersion, error);
}

- (TLChatRecord *)loadChatWithID:(NSInteger)chatID error:(NSError **)error {
  const char *chatSQL = "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model, source_agent_id, source_session_id, continuation_session_id FROM chats WHERE id = ?1";

  TLSQLiteStatement *chatStatement = [self.sqliteConnection prepareSQL:chatSQL error:error];
  if (!chatStatement) {
    return nil;
  }

  [chatStatement bindInt64:chatID atIndex:1];
  int result = [chatStatement step];

  if (result != SQLITE_ROW) {
    TLSetDatabaseError(error, @"Chat was not found.");
    return nil;
  }

  TLChatRecord *chat = [[TLChatRecord alloc] init];
  TLChatSummary *summary = [self chatSummaryFromStatement:chatStatement.handle];
  chat.chatID = summary.chatID;
  chat.title = summary.title;
  chat.icon = summary.icon;
  chat.model = summary.model;
  chat.supportingModel = summary.supportingModel;
  chat.createdAt = summary.createdAt;
  chat.updatedAt = summary.updatedAt;
  chat.hermesSessionID = summary.hermesSessionID;
  chat.sourceAgentID = summary.sourceAgentID;
  chat.sourceSessionID = summary.sourceSessionID;
  chat.continuationSessionID = summary.continuationSessionID;

  const char *messagesSQL =
    "SELECT id, role, content, thinking, created_at, attachments, source_message_id, source_tool_call_ids, notification "
    "FROM messages "
    "WHERE chat_id = ?1 "
    "ORDER BY id ASC";

  TLSQLiteStatement *messagesStatement = [self.sqliteConnection prepareSQL:messagesSQL error:error];
  if (!messagesStatement) {
    return nil;
  }

  [messagesStatement bindInt64:chatID atIndex:1];
  NSMutableArray<TLStoredChatMessage *> *messages = [NSMutableArray array];

  while ((result = [messagesStatement step]) == SQLITE_ROW) {
    [messages addObject:[self storedMessageFromStatement:messagesStatement.handle]];
  }

  if (result != SQLITE_DONE) {
    [self.sqliteConnection setCurrentError:error];
    return nil;
  }

  chat.messages = messages;
  return chat;
}

- (TLChatSummary *)loadChatSummaryWithID:(NSInteger)chatID error:(NSError **)error {
  const char *sql = "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model, source_agent_id, source_session_id, continuation_session_id FROM chats WHERE id = ?1";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return nil;
  }

  [statement bindInt64:chatID atIndex:1];
  int result = [statement step];
  if (result != SQLITE_ROW) {
    TLSetDatabaseError(error, @"Chat was not found.");
    return nil;
  }

  return [self chatSummaryFromStatement:statement.handle];
}

- (TLStoredChatMessage *)loadMessageWithID:(NSInteger)messageID error:(NSError **)error {
  const char *sql = "SELECT id, role, content, thinking, created_at, attachments, source_message_id, source_tool_call_ids, notification FROM messages WHERE id = ?1";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return nil;
  }

  [statement bindInt64:messageID atIndex:1];
  int result = [statement step];

  if (result != SQLITE_ROW) {
    TLSetDatabaseError(error, @"Message was not found.");
    return nil;
  }

  TLStoredChatMessage *message = [self storedMessageFromStatement:statement.handle];
  return message;
}

- (TLAgentRecord *)loadAgentWithID:(NSInteger)agentID error:(NSError **)error {
  const char *sql =
    "SELECT id, name, guest_kind, runtime, status, vm_directory, last_error, created_at, updated_at, avatar, soul, folder_paths "
    "FROM agents "
    "WHERE id = ?1";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return nil;
  }

  [statement bindInt64:agentID atIndex:1];
  int result = [statement step];

  if (result != SQLITE_ROW) {
    TLSetDatabaseError(error, @"Agent was not found.");
    return nil;
  }

  return [self agentFromStatement:statement.handle];
}

- (TLAgentRecord *)agentFromStatement:(sqlite3_stmt *)statement {
  TLAgentRecord *agent = [[TLAgentRecord alloc] init];
  agent.agentID = sqlite3_column_int64(statement, 0);
  agent.name = TLStringFromColumn(statement, 1);
  agent.guestKind = TLStringFromColumn(statement, 2);
  agent.runtime = TLStringFromColumn(statement, 3);
  agent.status = TLStringFromColumn(statement, 4);
  agent.vmDirectory = TLStringFromColumn(statement, 5);
  agent.lastError = TLNullableStringFromColumn(statement, 6);
  agent.createdAt = TLStringFromColumn(statement, 7);
  agent.updatedAt = TLStringFromColumn(statement, 8);
  agent.avatar = TLStringFromColumn(statement, 9);
  agent.soul = TLStringFromColumn(statement, 10);
  NSData *folderData = [TLStringFromColumn(statement, 11) dataUsingEncoding:NSUTF8StringEncoding];
  id paths = [NSJSONSerialization JSONObjectWithData:folderData options:0 error:nil];
  agent.folderPaths = [paths isKindOfClass:NSArray.class] ? paths : @[];
  return agent;
}

- (TLChatSummary *)chatSummaryFromStatement:(sqlite3_stmt *)statement {
  TLChatSummary *summary = [[TLChatSummary alloc] init];
  summary.chatID = sqlite3_column_int64(statement, 0);
  summary.title = TLStringFromColumn(statement, 1);
  summary.model = TLStringFromColumn(statement, 2);
  summary.icon = TLStringFromColumn(statement, 3);
  summary.createdAt = TLStringFromColumn(statement, 4);
  summary.updatedAt = TLStringFromColumn(statement, 5);
  summary.hermesSessionID = TLStringFromColumn(statement, 6);
  summary.supportingModel = TLStringFromColumn(statement, 7);
  summary.sourceAgentID = sqlite3_column_int64(statement, 8);
  summary.sourceSessionID = TLStringFromColumn(statement, 9);
  summary.continuationSessionID = TLStringFromColumn(statement, 10);
  return summary;
}

- (TLStoredChatMessage *)storedMessageFromStatement:(sqlite3_stmt *)statement {
  TLStoredChatMessage *message = [[TLStoredChatMessage alloc] init];
  message.messageID = sqlite3_column_int64(statement, 0);
  message.role = TLStringFromColumn(statement, 1);
  message.content = TLStringFromColumn(statement, 2);
  message.thinking = TLNullableStringFromColumn(statement, 3);
  message.createdAt = TLStringFromColumn(statement, 4);
  NSData *data = [TLStringFromColumn(statement, 5) dataUsingEncoding:NSUTF8StringEncoding];
  id attachments = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSMutableArray *valid = [NSMutableArray array];
  if ([attachments isKindOfClass:NSArray.class]) {
    for (id item in attachments) {
      if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class] &&
          [item[@"guestPath"] isKindOfClass:NSString.class] && [item[@"directory"] isKindOfClass:NSNumber.class]) [valid addObject:item];
    }
  }
  message.attachments = valid;
  message.sourceMessageID = TLStringFromColumn(statement, 6);
  id calls = TLJSONValue(TLStringFromColumn(statement, 7));
  id notification = TLJSONValue(TLStringFromColumn(statement, 8));
  if (TLValidSourceMetadata(calls, notification)) {
    message.sourceToolCallIDs = calls;
    message.notification = [notification count] ? notification : nil;
  }
  return message;
}

- (NSDictionary<NSString *, NSString *> *)storedSettings:(NSError **)error {
  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:
    "SELECT key, value FROM settings WHERE key != 'openRouterToken'" error:error];
  if (!statement) {
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
  int result;
  while ((result = [statement step]) == SQLITE_ROW) {
    values[[statement stringAtColumn:0]] = [statement stringAtColumn:1];
  }
  if (result != SQLITE_DONE) {
    [self.sqliteConnection setCurrentError:error];
    return nil;
  }
  return values;
}

- (BOOL)storeToken:(NSString *)token error:(NSError **)error {
  if (self.incognito) { self.incognitoToken = token; return YES; }
  if (token) {
    return [self.credentialStore setCredential:token forAccount:TLOpenRouterTokenCredentialAccount error:error];
  }
  return [self.credentialStore removeCredentialForAccount:TLOpenRouterTokenCredentialAccount error:error];
}

- (BOOL)removeLegacyCredential:(NSError **)error {
  return [self executeSQL:"DELETE FROM settings WHERE key = 'openRouterToken'" error:error];
}

- (BOOL)migrateLegacyCredentialWithRemember:(BOOL)remember error:(NSError **)error {
  if (self.incognito) return YES;
  NSError *readError = nil;
  NSString *legacyToken = [self settingForKey:@"openRouterToken" error:&readError];
  if (readError) {
    if (error) { *error = readError; }
    return NO;
  }
  if (!legacyToken) {
    return YES;
  }
  if (remember && legacyToken.length > 0) {
    NSString *currentToken = [self.credentialStore credentialForAccount:TLOpenRouterTokenCredentialAccount error:&readError];
    if (readError) {
      if (error) { *error = readError; }
      return NO;
    }
    // A previous interrupted migration may already have saved a credential.
    // Keep that value, which may have been updated since the SQLite copy.
    if (![self storeToken:currentToken ?: TLTrimmedString(legacyToken) error:error]) {
      return NO;
    }
  }
  // If deletion fails, keep the secure copy and retry deletion on the next read.
  return [self removeLegacyCredential:error];
}

- (NSString *)settingForKey:(NSString *)key error:(NSError **)error {
  const char *sql = "SELECT value FROM settings WHERE key = ?1";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return nil;
  }

  [statement bindText:key atIndex:1];
  int result = [statement step];
  NSString *value = nil;

  if (result == SQLITE_ROW) {
    value = [statement stringAtColumn:0];
  } else if (result != SQLITE_DONE) {
    [self.sqliteConnection setCurrentError:error];
  }

  return value;
}

- (BOOL)setSetting:(NSString *)key value:(NSString *)value error:(NSError **)error {
  const char *sql =
    "INSERT INTO settings (key, value) VALUES (?1, ?2) "
    "ON CONFLICT(key) DO UPDATE SET value = excluded.value";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return NO;
  }

  [statement bindText:key atIndex:1];
  [statement bindText:value atIndex:2];
  return [statement stepDone:error];
}

- (BOOL)updateTitleForUserMessage:(NSString *)content chatID:(NSInteger)chatID error:(NSError **)error {
  const char *sql =
    "UPDATE chats "
    "SET title = CASE WHEN title = 'New chat' THEN ?1 ELSE title END, "
    "    updated_at = datetime('now') "
    "WHERE id = ?2";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return NO;
  }

  [statement bindText:TLTitleFromMessage(content) atIndex:1];
  [statement bindInt64:chatID atIndex:2];
  return [statement stepDone:error];
}

- (BOOL)touchChatWithID:(NSInteger)chatID error:(NSError **)error {
  const char *sql = "UPDATE chats SET updated_at = datetime('now') WHERE id = ?1";

  TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:error];
  if (!statement) {
    return NO;
  }

  [statement bindInt64:chatID atIndex:1];
  return [statement stepDone:error];
}

- (BOOL)executeSQL:(const char *)sql error:(NSError **)error {
  return [self.sqliteConnection executeSQL:sql error:error];
}

- (BOOL)performTransaction:(TLDatabaseTransactionBlock)block error:(NSError **)error {
  return [self.sqliteConnection performTransaction:block error:error];
}

- (BOOL)isValidRole:(NSString *)role {
  return [role isEqualToString:TLRoleSystem] || [role isEqualToString:TLRoleUser] || [role isEqualToString:TLRoleAssistant];
}

- (BOOL)isValidAgentGuestKind:(NSString *)guestKind {
  return [guestKind isEqualToString:TLAgentGuestKindLinux];
}

- (BOOL)isValidAgentRuntime:(NSString *)runtime {
  return [runtime isEqualToString:TLAgentRuntimePython];
}

- (BOOL)isValidAgentStatus:(NSString *)status {
  return [status isEqualToString:TLAgentStatusStopped] ||
    [status isEqualToString:TLAgentStatusStarting] ||
    [status isEqualToString:TLAgentStatusRunning] ||
    [status isEqualToString:TLAgentStatusStopping] ||
    [status isEqualToString:TLAgentStatusError];
}

@end
