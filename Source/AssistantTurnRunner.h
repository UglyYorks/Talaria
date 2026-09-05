#import <Foundation/Foundation.h>
#import "AgentOrchestrator.h"
#import "Database.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLAssistantTurnUpdateHandler)(void);

typedef NS_ENUM(NSInteger, TLAssistantTurnGenerationStatus) {
  TLAssistantTurnGenerationStatusNotStarted,
  TLAssistantTurnGenerationStatusSucceeded,
  TLAssistantTurnGenerationStatusFailed,
};

typedef NS_ENUM(NSInteger, TLAssistantTurnPersistenceStatus) {
  TLAssistantTurnPersistenceStatusSucceeded,
  TLAssistantTurnPersistenceStatusFailed,
};

// A terminal snapshot. Generation can succeed while persistence fails, or fail
// while a partial reply is saved successfully. Errors are never chat messages.
@interface TLAssistantTurnResult : NSObject
@property (nonatomic, readonly) TLAssistantTurnGenerationStatus generationStatus;
@property (nonatomic, readonly) TLAssistantTurnPersistenceStatus persistenceStatus;
@property (nonatomic, strong, readonly, nullable) NSError *generationError;
@property (nonatomic, strong, readonly, nullable) NSError *persistenceError;
@property (nonatomic, copy, readonly) TLChatMessage *userMessage;
@property (nonatomic, copy, readonly, nullable) TLChatMessage *assistantMessage;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef void (^TLAssistantTurnCompletionHandler)(TLAssistantTurnResult *result);

@protocol TLAssistantTurnMessageStore <NSObject>
- (nullable TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error;
@end

@protocol TLAssistantTurnStreaming <NSObject>
- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                sessionID:(NSString *)sessionID
                                    token:(NSString *)token
                                    model:(NSString *)model
                                 messages:(NSArray<TLChatMessage *> *)messages
                                    delta:(TLAgentStreamDeltaHandler)delta
                               completion:(TLAgentStreamCompletionHandler)completion;
@end

@interface TLAssistantTurnRunner : NSObject

@property (nonatomic, readonly) BOOL running;
// Reference context is sent to the model, never displayed or stored as the user's message.
@property (nonatomic, copy, nullable) NSString *referenceContext;
@property (nonatomic) BOOL streamsPartialContent;

- (instancetype)initWithDatabase:(TLDatabase *)database agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator;
- (instancetype)initWithMessageStore:(id<TLAssistantTurnMessageStore>)messageStore
                            streaming:(id<TLAssistantTurnStreaming>)streaming;
// NO means validation rejected the turn: no mutation and no completion. YES
// means completion is called once, possibly synchronously, with both outcomes.
// If saving the prompt fails, generation is not started and rows are rolled back.
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
