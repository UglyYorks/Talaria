#import "Database.h"
#import "DatabaseMigrator.h"
#import "SQLiteConnection.h"

static NSInteger const TLDatabaseSchemaVersion = 8;

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

@interface TLDatabase ()

@property (nonatomic, strong) TLSQLiteConnection *sqliteConnection;
@property (nonatomic, strong) id<TLCredentialStore> credentialStore;

- (BOOL)executeSQL:(const char *)sql error:(NSError **)error;
- (BOOL)performTransaction:(TLDatabaseTransactionBlock)block error:(NSError **)error;

@end

@implementation TLDatabase

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
    NSString *token = remember ? [self.credentialStore credentialForAccount:TLOpenRouterTokenCredentialAccount
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
    settings.theme = TLThemePreferenceFromString(values[@"theme"] ?: @"system");
    settings.onboardingCompleted = [values[@"onboardingCompleted"] isEqualToString:@"true"];
    return settings;
  }
}

- (TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error {
  @synchronized (self) {
    NSString *selectedModel = TLNonBlank(settings.selectedModel, TLDefaultModelID);
    NSString *supportingModel = TLNonBlank(settings.supportingModel, TLDefaultSupportingModelID);
    NSString *theme = TLStringFromThemePreference(settings.theme);
    NSString *token = settings.rememberOpenRouterToken ? TLTrimmedString(settings.openRouterToken) : nil;
    NSError *credentialError = nil;
    NSString *previousToken = [self.credentialStore credentialForAccount:TLOpenRouterTokenCredentialAccount error:&credentialError];
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

- (NSArray<TLChatSummary *> *)listChats:(NSError **)error {
  @synchronized (self) {
    const char *sql =
      "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model "
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
        "INSERT INTO chats (title, model, hermes_session_id, supporting_model, created_at, updated_at) "
        "VALUES ('New chat', ?1, ?2, ?3, datetime('now'), datetime('now'))";

      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindText:TLNonBlank(model, TLDefaultModelID) atIndex:1];
      [statement bindText:[@"talaria_" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString] atIndex:2];
      [statement bindText:TLNonBlank(supportingModel, TLDefaultSupportingModelID) atIndex:3];
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
        [self setSetting:@"supportingModel" value:supportingModel error:transactionError];
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
        "INSERT INTO messages (chat_id, role, content, thinking, attachments, created_at) "
        "VALUES (?1, ?2, ?3, ?4, ?5, datetime('now'))";

      TLSQLiteStatement *statement = [self.sqliteConnection prepareSQL:sql error:transactionError];
      if (!statement) {
        return NO;
      }

      [statement bindInt64:chatID atIndex:1];
      [statement bindText:message.role atIndex:2];
      [statement bindText:message.content atIndex:3];
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

- (BOOL)setCurrentAgentID:(NSInteger)agentID error:(NSError **)error {
  @synchronized (self) {
    if (![self loadAgentWithID:agentID error:error]) return NO;
    return [self setSetting:@"currentAgentID" value:[@(agentID) stringValue] error:error];
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
  const char *chatSQL = "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model FROM chats WHERE id = ?1";

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

  const char *messagesSQL =
    "SELECT id, role, content, thinking, created_at, attachments "
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
  const char *sql = "SELECT id, title, model, icon, created_at, updated_at, hermes_session_id, supporting_model FROM chats WHERE id = ?1";

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
  const char *sql = "SELECT id, role, content, thinking, created_at, attachments FROM messages WHERE id = ?1";

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
  if (token) {
    return [self.credentialStore setCredential:token forAccount:TLOpenRouterTokenCredentialAccount error:error];
  }
  return [self.credentialStore removeCredentialForAccount:TLOpenRouterTokenCredentialAccount error:error];
}

- (BOOL)removeLegacyCredential:(NSError **)error {
  return [self executeSQL:"DELETE FROM settings WHERE key = 'openRouterToken'" error:error];
}

- (BOOL)migrateLegacyCredentialWithRemember:(BOOL)remember error:(NSError **)error {
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
