#import <Foundation/Foundation.h>
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

@class VZVirtioSocketConnection;

typedef void (^TLAgentVMCompletionHandler)(NSError *_Nullable error);
typedef void (^TLAgentVMConnectionCompletionHandler)(VZVirtioSocketConnection *_Nullable connection, NSError *_Nullable error);

@interface TLAgentVMService : NSObject

@property (nonatomic, readonly) NSURL *agentsDirectoryURL;
@property (nonatomic, readonly) NSURL *runtimeBundleURL;
@property (nonatomic, readonly, getter=isVirtualizationSupported) BOOL virtualizationSupported;

+ (NSURL *)defaultAgentsDirectoryURL;
+ (NSURL *)defaultRuntimeBundleURL;
- (instancetype)init;
- (instancetype)initWithAgentsDirectoryURL:(NSURL *)agentsDirectoryURL
                          runtimeBundleURL:(NSURL *)runtimeBundleURL NS_DESIGNATED_INITIALIZER;

- (NSString *)newVMDirectoryPathForAgentName:(NSString *)name;
- (BOOL)prepareStorageForAgent:(TLAgentRecord *)agent error:(NSError **)error;
- (void)startAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion;
- (void)stopAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion;
- (void)connectToAgent:(TLAgentRecord *)agent
                  port:(uint32_t)port
               timeout:(NSTimeInterval)timeout
            completion:(TLAgentVMConnectionCompletionHandler)completion;
- (BOOL)deleteVMForAgent:(TLAgentRecord *)agent error:(NSError **)error;
- (BOOL)isAgentRunning:(TLAgentRecord *)agent;

@end

NS_ASSUME_NONNULL_END
