#import <Foundation/Foundation.h>
#import "AgentModel.h"
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

@class TLAgentVMService;

typedef NS_ENUM(NSInteger, TLAgentStreamDeltaKind) {
  TLAgentStreamDeltaKindContent = 0,
  TLAgentStreamDeltaKindThinking,
};

typedef void (^TLAgentStreamDeltaHandler)(NSString *requestID, TLAgentStreamDeltaKind kind, NSString *text);
typedef void (^TLAgentStreamCompletionHandler)(NSError *_Nullable error);
typedef void (^TLAgentModelCatalogueHandler)(NSArray<TLAgentModel *> *_Nullable models, NSError *_Nullable error);

@protocol TLAgentStreaming <NSObject>

- (void)generateHermesTextWithAgent:(TLAgentRecord *)agent
                          requestID:(NSString *)requestID
                              token:(NSString *)token
                              model:(NSString *)model
                       instructions:(NSString *)instructions
                              input:(NSString *)input
                              delta:(TLAgentStreamDeltaHandler)delta
                         completion:(TLAgentStreamCompletionHandler)completion;

- (void)fetchModelCatalogueWithAgent:(TLAgentRecord *)agent
                                token:(NSString *)token
                           completion:(TLAgentModelCatalogueHandler)completion;

- (void)fetchHermesCommandsWithAgent:(TLAgentRecord *)agent
                              token:(NSString *)token
                              model:(NSString *)model
                         completion:(void (^)(NSDictionary *_Nullable catalogue, NSError *_Nullable error))completion;
- (void)streamHermesSessionWithAgent:(TLAgentRecord *)agent
                           requestID:(NSString *)requestID
                           sessionID:(NSString *)sessionID
                               token:(NSString *)token
                               model:(NSString *)model
                              prompt:(NSString *)prompt
                               delta:(TLAgentStreamDeltaHandler)delta
                          completion:(TLAgentStreamCompletionHandler)completion;
@optional
- (void)installHermesWithAgent:(TLAgentRecord *)agent
                     requestID:(NSString *)requestID
                      progress:(TLAgentStreamDeltaHandler)progress
                    completion:(TLAgentStreamCompletionHandler)completion;
- (void)runShellCommandWithAgent:(TLAgentRecord *)agent
                       requestID:(NSString *)requestID
                       sessionID:(NSString *)sessionID
                         command:(NSString *)command
                          output:(TLAgentStreamDeltaHandler)output
                      completion:(TLAgentStreamCompletionHandler)completion;

@end

@interface TLBundledAgentClient : NSObject <TLAgentStreaming>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithVMService:(TLAgentVMService *)vmService NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
