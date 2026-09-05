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

// Worktrees may share a schema version while introducing independent features.
// Check this feature's actual schema inside the write transaction, including on reopen.
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

BOOL TLDatabaseMigrate(TLSQLiteConnection *connection, NSInteger targetVersion, NSError **error) {
  NSInteger version = TLDatabaseSchemaVersion(connection, error);
  if (version < 0) {
    return NO;
  }

  if (version > targetVersion) {
    [connection setError:error message:@"Database was created by a newer version of Talaria."];
    return NO;
  }

  if (version == targetVersion) {
    if (targetVersion < 5) return YES;
    return [connection performTransaction:^BOOL(NSError **transactionError) {
      return TLEnsureMessageAttachments(connection, transactionError);
    } error:error];
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

  if (version < 5) {
    BOOL migrated = [connection performTransaction:^BOOL(NSError **transactionError) {
      return TLEnsureMessageAttachments(connection, transactionError) &&
        TLDatabaseSetSchemaVersion(connection, 5, transactionError);
    } error:error];
    if (!migrated) return NO;
    version = 5;
  }
  return version == targetVersion;
}
