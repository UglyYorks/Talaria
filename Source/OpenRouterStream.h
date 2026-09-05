#import <Foundation/Foundation.h>
#import "OpenRouterClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOpenRouterStream : NSObject <NSURLSessionDataDelegate>

@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, copy) TLOpenRouterDeltaHandler delta;
@property (nonatomic, copy) TLOpenRouterCompletionHandler completion;
@property (nonatomic, copy) void (^releaseHandler)(TLOpenRouterStream *stream);

- (void)start;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
