#import <Foundation/Foundation.h>
#import "AgentOrchestrator.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLChatIconGenerationCompletion)(NSString *_Nullable icon, NSError *_Nullable error);

NSString *_Nullable TLExtractChatIcon(NSString *_Nullable value);

@interface TLChatIconGenerator : NSObject

- (instancetype)initWithAgentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator;
- (void)generateIconForTitle:(NSString *)title
            firstUserMessage:(NSString *)firstUserMessage
                       token:(NSString *)token
                       model:(NSString *)model
                  completion:(TLChatIconGenerationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
