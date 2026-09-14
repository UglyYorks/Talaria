#import "AssistantTurnRunner.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLBrowserPageReader)(void (^completion)(NSDictionary *_Nullable page, NSError *_Nullable error));

@interface TLBrowserConversation : NSObject
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL loading;
@property (nonatomic, readonly) NSUInteger responseCount;
@property (nonatomic, copy, readonly) NSString *markdown;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *transcript;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *activityText;
@property (nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *toolActivities;
@property (nonatomic, copy, readonly, nullable) NSDictionary *pendingApproval;
@property (nonatomic, copy, readonly) NSArray<TLQuestionRequest *> *questions;
- (BOOL)respondToApproval:(NSString *)requestID choice:(NSString *)choice token:(NSString *)token model:(NSString *)model;
@property (nonatomic, strong, readonly, nullable) TLAssistantTurnResult *lastTurnResult;
@property (nonatomic) BOOL minimized;
@property (nonatomic) BOOL collapsed;
@property (nonatomic, copy) NSString *draft;
// The split workspace takes ownership of these same live objects on promotion.
@property (nonatomic, strong, readonly, nullable) TLChatRecord *chat;
@property (nonatomic, strong, readonly) NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, strong, readonly) TLAssistantTurnRunner *runner;
@property (nonatomic, copy, readonly, nullable) NSString *errorText;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);
@property (nonatomic, copy, nullable) void (^promptSubmittedHandler)(TLBrowserConversation *conversation, NSString *prompt);
- (void)refreshChatIdentity;
- (instancetype)initWithDatabase:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator;
- (BOOL)sendPrompt:(NSString *)prompt token:(NSString *)token model:(NSString *)model pageReader:(nullable TLBrowserPageReader)reader;
@end

NS_ASSUME_NONNULL_END
