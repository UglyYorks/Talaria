#import "AssistantTurnRunner.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLBrowserPageReader)(void (^completion)(NSDictionary *_Nullable page, NSError *_Nullable error));

@interface TLBrowserConversation : NSObject
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL loading;
@property (nonatomic, readonly) NSUInteger responseCount;
@property (nonatomic, copy, readonly) NSString *markdown;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, strong, readonly, nullable) TLAssistantTurnResult *lastTurnResult;
@property (nonatomic) BOOL minimized;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);
- (instancetype)initWithDatabase:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator;
- (BOOL)sendPrompt:(NSString *)prompt token:(NSString *)token model:(NSString *)model pageReader:(nullable TLBrowserPageReader)reader;
@end

NS_ASSUME_NONNULL_END
