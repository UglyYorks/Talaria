#import "DatabaseMigrator.h"

static NSInteger TLDatabaseSchemaVersion(TLSQLiteConnection *connection, NSError **error) {
  TLSQLiteStatement *statement = [connection prepareSQL:"PRAGMA user_version" error:error];
  if (!statement) {
    return -1;
  }

  int result = [statement step];
  if (result == SQLITE_ROW) {
    return sqlite3_column_int(statement.handle, 0);
  }

  [connection setCurrentError:error];
  return -1;
}

static BOOL TLDatabaseSetSchemaVersion(TLSQLiteConnection *connection, NSInteger version, NSError **error) {
  NSString *sql = [NSString stringWithFormat:@"PRAGMA user_version = %ld", (long)version];
  return [connection executeSQL:sql.UTF8String error:error];
}

// Version 5 was introduced by two independent worktrees. Both retain the
// version-4 columns and only add defaulted TEXT fields that older writes preserve.
static BOOL TLDatabaseHasCompatibleVersion5Schema(TLSQLiteConnection *connection) {
  NSDictionary<NSString *, NSArray<NSString *> *> *requiredColumns = @{
    @"chats": @[@"id", @"title", @"model", @"created_at", @"updated_at", @"icon", @"hermes_session_id"],
    @"messages": @[@"id", @"chat_id", @"role", @"content", @"thinking", @"created_at"],
    @"agents": @[@"id", @"name", @"guest_kind", @"runtime", @"status", @"vm_directory", @"last_error", @"created_at", @"updated_at"],
    @"settings": @[@"key", @"value"],
  };
  NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *knownAdditions = @{
    @"chats": @{@"supporting_model": @"'openrouter/auto'"},
    @"messages": @{@"attachments": @"'[]'"},
    @"agents": @{@"avatar": @"'🤖'", @"soul": @"''", @"folder_paths": @"'[]'"},
  };
  BOOL hasKnownAddition = NO;
  for (NSString *table in requiredColumns) {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
    TLSQLiteStatement *columns = [connection prepareSQL:sql.UTF8String error:nil];
    if (!columns) return NO;
    NSMutableSet *missing = [NSMutableSet setWithArray:requiredColumns[table]];
    int result;
    while ((result = [columns step]) == SQLITE_ROW) {
      NSString *name = [columns stringAtColumn:1];
      if ([missing containsObject:name]) {
        [missing removeObject:name];
        continue;
      }
      NSString *expectedDefault = knownAdditions[table][name];
      if (!expectedDefault || ![[[columns stringAtColumn:2] uppercaseString] isEqualToString:@"TEXT"] ||
          ![[columns stringAtColumn:4] isEqualToString:expectedDefault]) return NO;
      hasKnownAddition = YES;
    }
    if (result != SQLITE_DONE || missing.count > 0) return NO;
  }
  return hasKnownAddition;
}

// Worktrees may share a schema version while introducing independent features.
// Check this feature's actual schema inside the migration write transaction.
static BOOL TLEnsureMessageAttachments(TLSQLiteConnection *connection, NSError **error) {
  BOOL hasAttachments = NO;
  {
    TLSQLiteStatement *columns = [connection prepareSQL:"PRAGMA table_info(messages)" error:error];
    if (!columns) return NO;
    int result;
    while ((result = [columns step]) == SQLITE_ROW) {
      if ([[columns stringAtColumn:1] isEqualToString:@"attachments"]) hasAttachments = YES;
    }
    if (result != SQLITE_DONE) { [connection setCurrentError:error]; return NO; }
  }
  return hasAttachments || [connection executeSQL:
    "ALTER TABLE messages ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'" error:error];
}

static BOOL TLEnsureAgentProfiles(TLSQLiteConnection *connection, NSError **error) {
  TLSQLiteStatement *columns = [connection prepareSQL:"PRAGMA table_info(agents)" error:error];
  if (!columns) return NO;
  NSMutableSet *names = [NSMutableSet set];
  int result;
  while ((result = [columns step]) == SQLITE_ROW) [names addObject:[columns stringAtColumn:1]];
  if (result != SQLITE_DONE) { [connection setCurrentError:error]; return NO; }
  NSDictionary *defaults = @{@"avatar": @"'🤖'", @"soul": @"''", @"folder_paths": @"'[]'"};
  for (NSString *name in defaults) {
    if ([names containsObject:name]) continue;
    NSString *sql = [NSString stringWithFormat:@"ALTER TABLE agents ADD COLUMN %@ TEXT NOT NULL DEFAULT %@", name, defaults[name]];
    if (![connection executeSQL:sql.UTF8String error:error]) return NO;
  }
  return [connection executeSQL:"CREATE UNIQUE INDEX IF NOT EXISTS agents_vm_directory ON agents(vm_directory)" error:error];
}

BOOL TLDatabaseMigrate(TLSQLiteConnection *connection, NSInteger targetVersion, NSError **error) {
  NSInteger version = TLDatabaseSchemaVersion(connection, error);
  if (version < 0) {
    return NO;
  }

  if (version == 5 && targetVersion == 4 && TLDatabaseHasCompatibleVersion5Schema(connection)) {
    // Do not downgrade the version or alter data owned by the newer features.
    return YES;
  }

  if (version > targetVersion) {
    [connection setError:error message:@"Database was created by a newer version of Talaria."];
    return NO;
  }

  if (version == targetVersion) {
    return YES;
  }

  if (version < 1) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "CREATE TABLE IF NOT EXISTS chats ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  title TEXT NOT NULL,"
        "  model TEXT NOT NULL,"
        "  created_at TEXT NOT NULL DEFAULT (datetime('now')),"
        "  updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ");"
        "CREATE TABLE IF NOT EXISTS messages ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,"
        "  role TEXT NOT NULL CHECK (role IN ('system', 'user', 'assistant')),"
        "  content TEXT NOT NULL,"
        "  thinking TEXT,"
        "  created_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ");"
        "CREATE TABLE IF NOT EXISTS settings ("
        "  key TEXT PRIMARY KEY,"
        "  value TEXT NOT NULL"
        ");";

      return [connection executeSQL:sql error:transactionError] &&
        TLDatabaseSetSchemaVersion(connection, 1, transactionError);
    } error:error];
    if (!migrated) {
      return NO;
    }
    version = 1;
  }

  if (version < 2) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      const char *sql = "ALTER TABLE chats ADD COLUMN icon TEXT NOT NULL DEFAULT ''";
      return [connection executeSQL:sql error:transactionError] &&
        TLDatabaseSetSchemaVersion(connection, 2, transactionError);
    } error:error];
    if (!migrated) {
      return NO;
    }
    version = 2;
  }

  if (version < 3) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "CREATE TABLE IF NOT EXISTS agents ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  name TEXT NOT NULL,"
        "  guest_kind TEXT NOT NULL CHECK (guest_kind IN ('linux')),"
        "  runtime TEXT NOT NULL CHECK (runtime IN ('python')),"
        "  status TEXT NOT NULL CHECK (status IN ('stopped', 'starting', 'running', 'stopping', 'error')),"
        "  vm_directory TEXT NOT NULL,"
        "  last_error TEXT,"
        "  created_at TEXT NOT NULL DEFAULT (datetime('now')),"
        "  updated_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ");";
      return [connection executeSQL:sql error:transactionError] &&
        TLDatabaseSetSchemaVersion(connection, 3, transactionError);
    } error:error];
    if (!migrated) {
      return NO;
    }
    version = 3;
  }

  if (version < 4) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      const char *sql =
        "ALTER TABLE chats ADD COLUMN hermes_session_id TEXT NOT NULL DEFAULT '';"
        "UPDATE chats SET hermes_session_id = 'talaria_' || lower(hex(randomblob(16))) WHERE hermes_session_id = '';"
        "CREATE UNIQUE INDEX IF NOT EXISTS chats_hermes_session_id ON chats(hermes_session_id);";
      return [connection executeSQL:sql error:transactionError] &&
        TLDatabaseSetSchemaVersion(connection, 4, transactionError);
    } error:error];
    if (!migrated) {
      return NO;
    }
    version = 4;
  }

  if (version < 5 && targetVersion >= 5) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      return TLEnsureAgentProfiles(connection, transactionError) &&
        TLDatabaseSetSchemaVersion(connection, 5, transactionError);
    } error:error];
    if (!migrated) return NO;
    version = 5;
  }

  if (version < 6 && targetVersion >= 6) {
    // Earlier builds used version 5 for either attachments or profiles. Complete
    // the profile schema without replacing either variant's existing data.
    if (!TLDatabaseHasCompatibleVersion5Schema(connection)) {
      [connection setError:error message:@"Unrecognized version-5 database schema."];
      return NO;
    }
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      return TLEnsureAgentProfiles(connection, transactionError) &&
        TLDatabaseSetSchemaVersion(connection, 6, transactionError);
    } error:error];
    if (!migrated) return NO;
    version = 6;
  }

  if (version < 7 && targetVersion >= 7) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      if (!TLDatabaseHasCompatibleVersion5Schema(connection)) {
        [connection setError:transactionError message:@"Unrecognized database schema before attachment migration."];
        return NO;
      }
      return TLEnsureMessageAttachments(connection, transactionError) &&
        TLDatabaseSetSchemaVersion(connection, 7, transactionError);
    } error:error];
    if (!migrated) return NO;
    version = 7;
  }
  if (version < 8 && targetVersion >= 8) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      TLSQLiteStatement *columns = [connection prepareSQL:"PRAGMA table_info(chats)" error:transactionError];
      if (!columns) return NO;
      BOOL exists = NO;
      int result;
      while ((result = [columns step]) == SQLITE_ROW) {
        if ([[columns stringAtColumn:1] isEqualToString:@"supporting_model"]) exists = YES;
      }
      if (result != SQLITE_DONE) { [connection setCurrentError:transactionError]; return NO; }
      columns = nil;
      if (exists) return TLDatabaseSetSchemaVersion(connection, 8, transactionError);
      return [connection executeSQL:
        "ALTER TABLE chats ADD COLUMN supporting_model TEXT NOT NULL DEFAULT 'openrouter/auto';"
        "UPDATE chats SET supporting_model = COALESCE((SELECT NULLIF(value, '') FROM settings WHERE key = 'supportingModel'), 'openrouter/auto');"
        error:transactionError] && TLDatabaseSetSchemaVersion(connection, 8, transactionError);
    } error:error];
    if (!migrated) return NO;
    version = 8;
  }
  return version == targetVersion;
}
