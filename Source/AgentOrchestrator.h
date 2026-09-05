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

- (BOOL)hasHermesInstallationForAgent:(TLAgentRecord *)agent;
- (BOOL)isVMRunningForAgent:(TLAgentRecord *)agent;
- (NSString *)displayStatusForAgent:(TLAgentRecord *)agent;

- (nullable NSArray<TLAgentRecord *> *)listAgents:(NSError **)error;
- (nullable TLAgentRecord *)createAgentWithName:(NSString *)name error:(NSError **)error;
- (nullable TLAgentRecord *)createAgentWithName:(NSString *)name avatar:(NSString *)avatar
                                         soul:(NSString *)soul folderPaths:(NSArray<NSString *> *)folderPaths
                                        error:(NSError **)error;
- (void)installHermesForAgentWithID:(NSInteger)agentID progress:(TLHermesInstallProgressHandler)progress
                        completion:(TLAgentOperationCompletionHandler)completion;
- (nullable TLAgentRecord *)defaultAgentCreatingIfNeeded:(NSError **)error;
- (void)startAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion;
- (void)stopAgentWithID:(NSInteger)agentID completion:(TLAgentOperationCompletionHandler)completion;
- (nullable TLAgentRecord *)updateAgentWithID:(NSInteger)agentID folderPaths:(NSArray<NSString *> *)folderPaths error:(NSError **)error;
- (nullable TLAgentRecord *)updateAgentWithID:(NSInteger)agentID name:(NSString *)name
                                      avatar:(NSString *)avatar soul:(NSString *)soul error:(NSError **)error;
- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error;

- (void)cancelChatWithRequestID:(NSString *)requestID;

- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID
                                  sessionID:(NSString *)sessionID
                                      token:(NSString *)token
                                      model:(NSString *)model
                                   messages:(NSArray<TLChatMessage *> *)messages
                                      delta:(TLAgentStreamDeltaHandler)delta
                                 completion:(TLAgentStreamCompletionHandler)completion;
- (void)prepareAttachmentURLs:(NSArray<NSURL *> *)URLs sessionID:(NSString *)sessionID
                  completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *_Nullable attachments, NSError *_Nullable error))completion;
- (BOOL)removeAttachmentsForSessionID:(NSString *)sessionID error:(NSError **)error;
- (void)generateTextWithDefaultAgentRequestID:(NSString *)requestID
                                       token:(NSString *)token
                                       model:(NSString *)model
                                instructions:(NSString *)instructions
                                       input:(NSString *)input
                                       delta:(TLAgentStreamDeltaHandler)delta
                                  completion:(TLAgentStreamCompletionHandler)completion;
- (void)createFreshHermesAgentWithProgress:(TLHermesInstallProgressHandler)progress
                                completion:(TLAgentOperationCompletionHandler)completion;
- (void)runShellCommandWithDefaultAgentSessionID:(NSString *)sessionID
                                         command:(NSString *)command
                                          output:(void (^)(NSString *text))output
                                      completion:(TLAgentStreamCompletionHandler)completion;
// Last successful TUI discovery for the current agent; never starts a VM.
- (nullable NSDictionary *)cachedHermesCommands;
- (void)fetchHermesCommandsWithToken:(NSString *)token
                               model:(NSString *)model
                          completion:(void (^)(NSDictionary *_Nullable catalogue, NSError *_Nullable error))completion;
- (BOOL)isDefaultAgentRunning;
- (void)connectToDefaultAgentTerminal:(TLAgentVMConnectionCompletionHandler)completion;

- (void)fetchModelCatalogueWithToken:(NSString *)token
                           completion:(TLAgentModelCatalogueHandler)completion;

@end

NS_ASSUME_NONNULL_END
