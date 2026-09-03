#import "AssistantTurnRunner.h"

typedef void (^TLBrowserPageReader)(void (^completion)(NSDictionary *page, NSError *error));

@interface TLBrowserConversation : NSObject
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL loading;
@property (nonatomic, readonly) NSUInteger responseCount;
@property (nonatomic, copy, readonly) NSString *markdown;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic) BOOL minimized;
@property (nonatomic, copy) void (^changeHandler)(void);
- (instancetype)initWithDatabase:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator;
- (BOOL)sendPrompt:(NSString *)prompt token:(NSString *)token model:(NSString *)model pageReader:(TLBrowserPageReader)reader;
@end
