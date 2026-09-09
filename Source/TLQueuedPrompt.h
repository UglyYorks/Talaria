#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// A follow-up remains separate from conversation history until it starts.
@interface TLQueuedPrompt : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<NSURL *> *attachmentURLs;
+ (instancetype)promptWithText:(NSString *)text attachmentURLs:(NSArray<NSURL *> *)URLs;
@end
NS_ASSUME_NONNULL_END
