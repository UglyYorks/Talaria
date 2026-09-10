#import "Database.h"

NS_ASSUME_NONNULL_BEGIN
@protocol TLHistoryReading <NSObject>
- (void)historyMatching:(NSString *)query before:(nullable TLBrowserHistoryEntry *)cursor completion:(void (^)(NSArray<TLBrowserHistoryEntry *> * _Nullable, NSError * _Nullable))completion;
- (void)faviconForVisit:(TLBrowserHistoryEntry *)visit completion:(void (^)(NSData * _Nullable))completion;
@end

@interface TLHistoryRepository : NSObject <TLHistoryReading>
- (instancetype)initWithDatabase:(TLDatabase *)database;
- (void)cacheSessions:(NSArray<NSDictionary *> *)sessions completion:(void (^)(NSArray<TLChatSummary *> * _Nullable, NSArray<TLChatSummary *> * _Nullable, NSError * _Nullable))completion;
- (void)cacheSessions:(NSArray<NSDictionary *> *)sessions agentID:(NSInteger)agentID completion:(void (^)(NSArray<TLChatSummary *> * _Nullable, NSArray<TLChatSummary *> * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
