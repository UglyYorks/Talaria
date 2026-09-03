#import <Foundation/Foundation.h>
#import "SQLiteConnection.h"

NS_ASSUME_NONNULL_BEGIN

BOOL TLDatabaseMigrate(TLSQLiteConnection *connection, NSInteger targetVersion, NSError **error);

NS_ASSUME_NONNULL_END
