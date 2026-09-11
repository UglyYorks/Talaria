#import "TLHistoryRepository.h"

@implementation TLHistoryRepository {
  TLDatabase *_database;
}
- (instancetype)initWithDatabase:(TLDatabase *)database {
  if ((self = [super init])) _database = database;
  return self;
}
- (void)historyMatching:(NSString *)query before:(TLBrowserHistoryEntry *)cursor completion:(void (^)(NSArray<TLBrowserHistoryEntry *> * _Nullable, NSError * _Nullable))completion {
  NSString *snapshot = [query copy];
  [_database performAsync:^(TLDatabase *database) {
    NSError *error = nil;
    NSArray *page = [database browserHistoryMatching:snapshot before:cursor limit:100 error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(page, error); });
  }];
}
- (void)faviconForVisit:(TLBrowserHistoryEntry *)visit completion:(void (^)(NSData *))completion {
  [_database performAsync:^(TLDatabase *database) {
    NSData *data = [database faviconForBrowserVisit:visit error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ completion(data); });
  }];
}
- (void)cacheSessions:(NSArray<NSDictionary *> *)sessions completion:(void (^)(NSArray<TLChatSummary *> * _Nullable, NSArray<TLChatSummary *> * _Nullable, NSError * _Nullable))completion {
  [self cacheSessions:sessions agentID:0 completion:completion];
}
- (void)cacheSessions:(NSArray<NSDictionary *> *)sessions agentID:(NSInteger)agentID completion:(void (^)(NSArray<TLChatSummary *> * _Nullable, NSArray<TLChatSummary *> * _Nullable, NSError * _Nullable))completion {
  NSArray *snapshot = [sessions copy];
  [_database performAsync:^(TLDatabase *database) {
    NSError *error = nil;
    NSArray *summaries = [database cacheHermesSessionSummaries:snapshot agentID:agentID error:&error];
    NSArray *all = summaries ? [database listChats:&error] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(summaries, all, error); });
  }];
}
@end
