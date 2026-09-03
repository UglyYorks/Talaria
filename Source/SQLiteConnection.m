#import "SQLiteConnection.h"

NSString * const TLSQLiteErrorDomain = @"Talaria.Database";

void TLSetSQLiteError(NSError **error, NSString *message) {
  if (error) {
    *error = [NSError errorWithDomain:TLSQLiteErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
  }
}

@interface TLSQLiteStatement ()

@property (nonatomic) sqlite3 *connection;
@property (nonatomic) sqlite3_stmt *handle;

@end

@implementation TLSQLiteStatement

- (instancetype)initWithConnection:(sqlite3 *)connection
                               sql:(const char *)sql
                             error:(NSError **)error {
  self = [super init];
  if (self) {
    _connection = connection;
    if (sqlite3_prepare_v2(connection, sql, -1, &_handle, NULL) != SQLITE_OK) {
      TLSetSQLiteError(error, [NSString stringWithFormat:@"Database error: %s", sqlite3_errmsg(connection)]);
      return nil;
    }
  }
  return self;
}

- (void)dealloc {
  if (_handle) {
    sqlite3_finalize(_handle);
  }
}

- (void)bindInt64:(sqlite3_int64)value atIndex:(int)index {
  sqlite3_bind_int64(self.handle, index, value);
}

- (void)bindText:(NSString *)value atIndex:(int)index {
  sqlite3_bind_text(self.handle, index, (value ?: @"").UTF8String, -1, SQLITE_TRANSIENT);
}

- (void)bindNullAtIndex:(int)index {
  sqlite3_bind_null(self.handle, index);
}

- (int)step {
  return sqlite3_step(self.handle);
}

- (BOOL)stepDone:(NSError **)error {
  if ([self step] != SQLITE_DONE) {
    TLSetSQLiteError(error, [NSString stringWithFormat:@"Database error: %s", sqlite3_errmsg(self.connection)]);
    return NO;
  }

  return YES;
}

- (NSString *)stringAtColumn:(int)column {
  const unsigned char *text = sqlite3_column_text(self.handle, column);
  if (!text) {
    return @"";
  }

  return [NSString stringWithUTF8String:(const char *)text] ?: @"";
}

- (NSString *)nullableStringAtColumn:(int)column {
  if (sqlite3_column_type(self.handle, column) == SQLITE_NULL) {
    return nil;
  }

  return [self stringAtColumn:column];
}

@end

@interface TLSQLiteConnection ()

@property (nonatomic) sqlite3 *handle;

@end

@implementation TLSQLiteConnection

+ (instancetype)openURL:(NSURL *)URL error:(NSError **)error {
  TLSQLiteConnection *connection = [[self alloc] init];
  if (sqlite3_open(URL.path.fileSystemRepresentation, &connection->_handle) != SQLITE_OK) {
    TLSetSQLiteError(error, [NSString stringWithFormat:@"Could not open database: %s", sqlite3_errmsg(connection->_handle)]);
    return nil;
  }
  return connection;
}

- (void)dealloc {
  if (_handle) {
    sqlite3_close(_handle);
  }
}

- (BOOL)executeSQL:(const char *)sql error:(NSError **)error {
  char *errorMessage = NULL;
  if (sqlite3_exec(self.handle, sql, NULL, NULL, &errorMessage) != SQLITE_OK) {
    NSString *message = [NSString stringWithFormat:@"Database error: %s", errorMessage ?: sqlite3_errmsg(self.handle)];
    sqlite3_free(errorMessage);
    TLSetSQLiteError(error, message);
    return NO;
  }

  return YES;
}

- (TLSQLiteStatement *)prepareSQL:(const char *)sql error:(NSError **)error {
  return [[TLSQLiteStatement alloc] initWithConnection:self.handle sql:sql error:error];
}

- (BOOL)performTransaction:(TLSQLiteTransactionBlock)block error:(NSError **)error {
  if (![self executeSQL:"BEGIN IMMEDIATE TRANSACTION" error:error]) {
    return NO;
  }

  NSError *blockError = nil;
  BOOL ok = block ? block(&blockError) : YES;
  if (!ok) {
    [self executeSQL:"ROLLBACK" error:nil];
    if (error && blockError) {
      *error = blockError;
    }
    return NO;
  }

  NSError *commitError = nil;
  if (![self executeSQL:"COMMIT" error:&commitError]) {
    [self executeSQL:"ROLLBACK" error:nil];
    if (error && commitError) {
      *error = commitError;
    }
    return NO;
  }

  return YES;
}

- (sqlite3_int64)lastInsertRowID {
  return sqlite3_last_insert_rowid(self.handle);
}

- (void)setError:(NSError **)error message:(NSString *)message {
  TLSetSQLiteError(error, message);
}

- (void)setCurrentError:(NSError **)error {
  [self setError:error message:[NSString stringWithFormat:@"Database error: %s", sqlite3_errmsg(self.handle)]];
}

@end
