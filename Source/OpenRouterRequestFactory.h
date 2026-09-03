#import <Foundation/Foundation.h>
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

NSURLRequest *TLOpenRouterMakeModelCatalogueRequest(NSString *_Nullable token);
NSURLRequest *_Nullable TLOpenRouterMakeChatRequest(NSString *token,
                                                    NSString *model,
                                                    NSArray<TLChatMessage *> *messages,
                                                    NSError **error);
NSError *_Nullable TLOpenRouterValidateChatInput(NSString *token,
                                                 NSString *model,
                                                 NSString *requestID,
                                                 NSArray<TLChatMessage *> *messages);

NS_ASSUME_NONNULL_END
