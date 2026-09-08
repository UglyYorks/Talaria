#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Stores independent snapshots in the directory mounted at /workspace in the VM.
@interface TLChatAttachmentStore : NSObject
- (instancetype)initWithWorkspaceURL:(NSURL *)workspaceURL;
// Resolves only retained, regular files/folders belonging to this conversation.
- (nullable NSURL *)fileURLForAttachment:(NSDictionary *)attachment sessionID:(NSString *)sessionID;
- (nullable NSArray<NSDictionary<NSString *, id> *> *)copyURLs:(NSArray<NSURL *> *)URLs
                                                   sessionID:(NSString *)sessionID
                                                       error:(NSError **)error;
- (BOOL)removeAttachmentsForSessionID:(NSString *)sessionID error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
