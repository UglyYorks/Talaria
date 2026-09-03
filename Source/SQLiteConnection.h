#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^TLSQLiteTransactionBlock)(NSError **error);

FOUNDATION_EXPORT NSString * const TLSQLiteErrorDomain;

void TLSetSQLiteError(NSError **error, NSString *message);

@interface TLSQLiteStatement : NSObject

@property (nonatomic, readonly) sqlite3_stmt *handle;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithConnection:(sqlite3 *)connection
                                        sql:(const char *)sql
                                      error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (void)bindInt64:(sqlite3_int64)value atIndex:(int)index;
- (void)bindText:(NSString *)value atIndex:(int)index;
- (void)bindNullAtIndex:(int)index;
- (int)step;
- (BOOL)stepDone:(NSError **)error;
- (NSString *)stringAtColumn:(int)column;
- (nullable NSString *)nullableStringAtColumn:(int)column;

@end

@interface TLSQLiteConnection : NSObject

@property (nonatomic, readonly) sqlite3 *handle;

+ (nullable instancetype)openURL:(NSURL *)URL error:(NSError **)error;
- (BOOL)executeSQL:(const char *)sql error:(NSError **)error;
- (nullable TLSQLiteStatement *)prepareSQL:(const char *)sql error:(NSError **)error;
- (BOOL)performTransaction:(TLSQLiteTransactionBlock)block error:(NSError **)error;
- (sqlite3_int64)lastInsertRowID;
- (void)setError:(NSError **)error message:(NSString *)message;
- (void)setCurrentError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
