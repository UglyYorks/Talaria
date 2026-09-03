#import <Foundation/Foundation.h>
#import "AgentOrchestrator.h"
#import "Database.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLAssistantTurnUpdateHandler)(void);
typedef void (^TLAssistantTurnCompletionHandler)(NSError *_Nullable error);

@interface TLAssistantTurnRunner : NSObject

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) BOOL lastTurnSucceeded;
// Reference context is sent to the model, never displayed or stored as the user's message.
@property (nonatomic, copy, nullable) NSString *referenceContext;
@property (nonatomic) BOOL streamsPartialContent;

- (instancetype)initWithDatabase:(TLDatabase *)database agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator;
- (BOOL)startTurnWithChat:(nullable TLChatRecord *)chat
                    token:(NSString *)token
                    model:(NSString *)model
                 messages:(nullable NSMutableArray<TLChatMessage *> *)messages
               nextPrompt:(NSString *)nextPrompt
            updateHandler:(nullable TLAssistantTurnUpdateHandler)updateHandler
        completionHandler:(nullable TLAssistantTurnCompletionHandler)completionHandler
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
