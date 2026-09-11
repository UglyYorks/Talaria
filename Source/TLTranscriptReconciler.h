#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLTranscriptChanges : NSObject
@property (nonatomic, copy) NSArray<TLStoredChatMessage *> *writes;
@property (nonatomic, copy) NSArray<NSNumber *> *deletedIDs;
@end

// Matches repeated role/content pairs in occurrence order. The remote transcript
// determines ordering; local IDs, attachments and missing reasoning survive refresh.
@interface TLTranscriptReconciler : NSObject
+ (nullable TLTranscriptChanges *)reconcileMessages:(NSArray<NSDictionary *> *)incoming
                                          previous:(NSArray<TLStoredChatMessage *> *)previous
                                             error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
