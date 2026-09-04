#import <Foundation/Foundation.h>
#import "AgentClient.h"
#import "AgentVMService.h"
#import "Database.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLAgentOperationCompletionHandler)(TLAgentRecord *_Nullable agent, NSError *_Nullable error);
typedef void (^TLHermesInstallProgressHandler)(NSString *text);

@interface TLAgentOrchestrator : NSObject

@property (nonatomic, readonly) NSURL *runtimeBundleURL;
@property (nonatomic, readonly, getter=isVirtualizationSupported) BOOL virtualizationSupported;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabase:(TLDatabase *)database
                     agentClient:(id<TLAgentStreaming>)agentClient
                       vmService:(TLAgentVMService *)vmService NS_DESIGNATED_INITIALIZER;

- (nullable NSArray<TLAgentRecord *> *)listAgents:(NSError **)error;
- (nullable TLAgentRecord *)createAgentWithName:(NSString *)name error:(NSError **)error;
- (nullable TLAgentRecord *)defaultAgentCreatingIfNeeded:(NSError **)error;
- (void)startAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion;
- (void)stopAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion;
- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error;

- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                  sessionID:(NSString *)sessionID
                                      token:(NSString *)token
                                      model:(NSString *)model
                                   messages:(NSArray<TLChatMessage *> *)messages
                                      delta:(TLAgentStreamDeltaHandler)delta
                                 completion:(TLAgentStreamCompletionHandler)completion;
- (void)createFreshHermesAgentWithProgress:(TLHermesInstallProgressHandler)progress
                                completion:(TLAgentOperationCompletionHandler)completion;
- (void)runShellCommandWithDefaultAgentSessionID:(NSString *)sessionID
                                         command:(NSString *)command
                                          output:(void (^)(NSString *text))output
                                      completion:(TLAgentStreamCompletionHandler)completion;
- (void)fetchModelCatalogueWithToken:(NSString *)token
                           completion:(TLAgentModelCatalogueHandler)completion;

@end

NS_ASSUME_NONNULL_END
