#import "TLTranscriptReconciler.h"

@implementation TLTranscriptChanges
@end

@implementation TLTranscriptReconciler
+ (TLTranscriptChanges *)reconcileMessages:(NSArray<NSDictionary *> *)incoming
                                 previous:(NSArray<TLStoredChatMessage *> *)previous error:(NSError **)error {
  NSMutableDictionary<NSArray *, NSMutableArray *> *buckets = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSArray *, NSNumber *> *offsets = [NSMutableDictionary dictionary];
  NSMutableSet *retained = [NSMutableSet set];
  NSMutableArray *writes = [NSMutableArray array];
  for (TLStoredChatMessage *message in previous) {
    NSArray *key = @[message.role, message.content];
    if (!buckets[key]) buckets[key] = [NSMutableArray array];
    [buckets[key] addObject:message];
  }
  NSInteger position = 0;
  for (id item in incoming) {
    if (![item isKindOfClass:NSDictionary.class] ||
        ![@[TLRoleSystem, TLRoleUser, TLRoleAssistant] containsObject:item[@"role"] ?: NSNull.null] ||
        ![item[@"content"] isKindOfClass:NSString.class]) {
      if (error) *error = [NSError errorWithDomain:@"Talaria.Transcript" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Hermes returned an invalid transcript."}];
      return nil;
    }
    NSArray *key = @[item[@"role"], item[@"content"]];
    NSUInteger offset = [offsets[key] unsignedIntegerValue];
    NSArray *bucket = buckets[key];
    TLStoredChatMessage *old = offset < bucket.count ? bucket[offset] : nil;
    offsets[key] = @(offset + 1);
    TLStoredChatMessage *message = old ? [old copy] : [TLStoredChatMessage new];
    message.role = key[0]; message.content = key[1]; message.position = position++;
    if ([item[@"thinking"] isKindOfClass:NSString.class] && [item[@"thinking"] length]) message.thinking = item[@"thinking"];
    if ([item[@"created_at"] isKindOfClass:NSString.class] && [item[@"created_at"] length]) message.createdAt = item[@"created_at"];
    if (old) [retained addObject:@(old.messageID)];
    if (!old || old.position != message.position || ![old.createdAt isEqual:message.createdAt] || ![(old.thinking ?: @"") isEqual:message.thinking ?: @""]) [writes addObject:message];
  }
  NSMutableArray *deleted = [NSMutableArray array];
  for (TLStoredChatMessage *message in previous) if (![retained containsObject:@(message.messageID)]) [deleted addObject:@(message.messageID)];
  TLTranscriptChanges *changes = [TLTranscriptChanges new];
  changes.writes = writes; changes.deletedIDs = deleted;
  return changes;
}
@end
