#import "TLQueuedPrompt.h"
@implementation TLQueuedPrompt
+ (instancetype)promptWithText:(NSString *)text attachmentURLs:(NSArray<NSURL *> *)URLs {
  TLQueuedPrompt *prompt = [self new];
  prompt.text = text;
  prompt.attachmentURLs = URLs;
  return prompt;
}
@end
