#import "PromptMessages.h"
#import "PromptBuilder.h"

const NSUInteger TLMessagePromptLimit = 12000;

NSString *TLBuildPromptContent(TLChatMessage *message, BOOL isLatestUserMessage) {
  TLPromptBuilder *builder = [[TLPromptBuilder alloc] initWithLimit:@(TLMessagePromptLimit) separator:@"\n"];
  return [[builder addPartWithContent:message.content
                           importance:isLatestUserMessage ? TLPromptImportanceRequired : TLPromptImportanceUseful
                             strategy:isLatestUserMessage ? TLPromptCompactionStrategyKeepStart : TLPromptCompactionStrategyKeepEnd
                                 name:[NSString stringWithFormat:@"%@-message", message.role]] build];
}

NSArray<TLChatMessage *> *TLBuildRequestMessages(NSArray<TLChatMessage *> *messages, NSString *nextUserPrompt) {
  NSMutableArray<TLChatMessage *> *requestMessages = [NSMutableArray arrayWithArray:messages];
  [requestMessages addObject:[TLChatMessage messageWithRole:TLRoleUser content:nextUserPrompt thinking:nil]];

  NSUInteger latestUserMessageIndex = requestMessages.count - 1;
  NSMutableArray<TLChatMessage *> *builtMessages = [NSMutableArray arrayWithCapacity:requestMessages.count];

  [requestMessages enumerateObjectsUsingBlock:^(TLChatMessage *message, NSUInteger index, BOOL *stop) {
    NSString *content = TLBuildPromptContent(message, index == latestUserMessageIndex);
    [builtMessages addObject:[TLChatMessage messageWithRole:message.role content:content thinking:nil]];
  }];

  return builtMessages;
}
