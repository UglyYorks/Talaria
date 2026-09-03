#import <Foundation/Foundation.h>
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger TLMessagePromptLimit;

NSString *TLBuildPromptContent(TLChatMessage *message, BOOL isLatestUserMessage);
NSArray<TLChatMessage *> *TLBuildRequestMessages(NSArray<TLChatMessage *> *messages, NSString *nextUserPrompt);

NS_ASSUME_NONNULL_END
