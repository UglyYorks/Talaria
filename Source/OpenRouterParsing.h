#import <Foundation/Foundation.h>
#import "OpenRouterClient.h"

NS_ASSUME_NONNULL_BEGIN

NSArray<TLOpenRouterModel *> *_Nullable TLParseOpenRouterModelsResponse(NSData *data, NSError **error);
NSDictionary<NSString *, NSString *> *_Nullable TLParseOpenRouterStreamDelta(NSString *data, NSError **error);

NS_ASSUME_NONNULL_END
