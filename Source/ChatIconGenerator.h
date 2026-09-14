#import <Foundation/Foundation.h>
#import "AgentOrchestrator.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLChatNameGenerationCompletion)(NSString *_Nullable title, NSString *_Nullable icon, NSError *_Nullable error);

NSString *_Nullable TLExtractChatIcon(NSString *_Nullable value);

@interface TLChatIconGenerator : NSObject

- (instancetype)initWithAgentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator;
// Called before appending the newly submitted user message. Only the first three
// user turns are named; a newer request supersedes any older result for this chat.
- (void)generateNameForChatID:(NSInteger)chatID
                   messages:(NSArray<TLChatMessage *> *)messages
                 nextPrompt:(NSString *)nextPrompt
                      token:(NSString *)token
                      model:(NSString *)model
                 completion:(TLChatNameGenerationCompletion)completion;
- (void)cancelNamingForChatID:(NSInteger)chatID;

@end

NS_ASSUME_NONNULL_END
