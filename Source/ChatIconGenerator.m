#import "ChatIconGenerator.h"
#import "OpenRouterSupport.h"
#import "PromptBuilder.h"

static NSString * const TLChatIconGeneratorErrorDomain = @"Talaria.ChatIconGenerator";

static NSError *TLChatIconGeneratorError(NSString *message) {
  return [NSError errorWithDomain:TLChatIconGeneratorErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static BOOL TLCodePointIsEmoji(uint32_t codePoint) {
  return (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
    (codePoint >= 0x2600 && codePoint <= 0x27BF) ||
    (codePoint >= 0x2300 && codePoint <= 0x23FF) ||
    (codePoint >= 0x2B00 && codePoint <= 0x2BFF);
}

static BOOL TLStringContainsEmojiCodePoint(NSString *value) {
  for (NSUInteger index = 0; index < value.length; index += 1) {
    unichar character = [value characterAtIndex:index];
    uint32_t codePoint = character;
    if (CFStringIsSurrogateHighCharacter(character) && index + 1 < value.length) {
      unichar low = [value characterAtIndex:index + 1];
      if (CFStringIsSurrogateLowCharacter(low)) {
        codePoint = CFStringGetLongCharacterForSurrogatePair(character, low);
        index += 1;
      }
    }

    if (TLCodePointIsEmoji(codePoint)) {
      return YES;
    }
  }

  return NO;
}

NSString *TLExtractChatIcon(NSString *value) {
  NSString *trimmed = TLOpenRouterTrim(value);
  if (trimmed.length == 0) {
    return nil;
  }

  NSCharacterSet *ignoredCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\"'`*_:;,.!?()[]{}<>"];
  __block NSString *icon = nil;
  [trimmed enumerateSubstringsInRange:NSMakeRange(0, trimmed.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
    if (substring.length == 0) {
      return;
    }

    if ([substring rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
      return;
    }

    if ([substring rangeOfCharacterFromSet:ignoredCharacters].location != NSNotFound) {
      return;
    }

    if (TLStringContainsEmojiCodePoint(substring)) {
      icon = substring;
      *stop = YES;
    }
  }];

  return icon;
}

@interface TLChatIconGenerator ()
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@end

@implementation TLChatIconGenerator

- (instancetype)initWithAgentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator {
  self = [super init];
  if (self) {
    _agentOrchestrator = agentOrchestrator;
  }
  return self;
}

- (void)generateIconForTitle:(NSString *)title
            firstUserMessage:(NSString *)firstUserMessage
                       token:(NSString *)token
                       model:(NSString *)model
                  completion:(TLChatIconGenerationCompletion)completion {
  NSString *trimmedToken = TLOpenRouterTrim(token);
  NSString *trimmedModel = TLOpenRouterTrim(model);
  NSString *trimmedMessage = TLOpenRouterTrim(firstUserMessage);

  if (trimmedToken.length == 0) {
    completion(nil, TLChatIconGeneratorError(@"OpenRouter token is required."));
    return;
  }
  if (trimmedModel.length == 0) {
    completion(nil, TLChatIconGeneratorError(@"Supporting model is required."));
    return;
  }
  if (trimmedMessage.length == 0) {
    completion(nil, TLChatIconGeneratorError(@"A user message is required."));
    return;
  }

  TLPromptBuilder *systemPromptBuilder = [[TLPromptBuilder alloc] initWithLimit:@320 separator:@"\n"];
  [[systemPromptBuilder addPartWithContent:@"You choose compact chat icons."
                                importance:TLPromptImportanceRequired
                                  strategy:TLPromptCompactionStrategyWhole
                                      name:@"role"]
    addPartWithContent:@"Return exactly one emoji and no words, punctuation, or explanation."
            importance:TLPromptImportanceRequired
              strategy:TLPromptCompactionStrategyWhole
                  name:@"format"];
  NSString *systemPrompt = systemPromptBuilder.compact.prompt;

  TLPromptBuilder *userPromptBuilder = [[TLPromptBuilder alloc] initWithLimit:@1400 separator:@"\n\n"];
  [[userPromptBuilder addPartWithContent:@"Pick the single emoji that best represents this conversation."
                              importance:TLPromptImportanceRequired
                                strategy:TLPromptCompactionStrategyWhole
                                    name:@"task"]
    addPartWithContent:[NSString stringWithFormat:@"Title: %@", TLOpenRouterTrim(title).length > 0 ? TLOpenRouterTrim(title) : @"New chat"]
            importance:TLPromptImportanceUseful
              strategy:TLPromptCompactionStrategyKeepStart
                  name:@"title"];
  [userPromptBuilder addPartWithContent:[NSString stringWithFormat:@"First user message:\n%@", trimmedMessage]
                             importance:TLPromptImportanceRequired
                               strategy:TLPromptCompactionStrategyKeepStart
                                   name:@"message"];

  NSArray<TLChatMessage *> *messages = @[
    [TLChatMessage messageWithRole:TLRoleSystem content:systemPrompt thinking:nil],
    [TLChatMessage messageWithRole:TLRoleUser content:userPromptBuilder.compact.prompt thinking:nil],
  ];
  NSString *requestID = NSUUID.UUID.UUIDString;
  NSMutableString *response = [NSMutableString string];

  [self.agentOrchestrator streamChatWithDefaultAgentRequestID:requestID
                                                       token:trimmedToken
                                                       model:trimmedModel
                                                    messages:messages
                                                       delta:^(NSString *deltaRequestID, TLAgentStreamDeltaKind kind, NSString *text) {
    if (![deltaRequestID isEqualToString:requestID] || kind != TLAgentStreamDeltaKindContent || text.length == 0) {
      return;
    }
    [response appendString:text];
  } completion:^(NSError *error) {
    if (error) {
      completion(nil, error);
      return;
    }

    NSString *icon = TLExtractChatIcon(response);
    if (icon.length == 0) {
      completion(nil, TLChatIconGeneratorError(@"The supporting model did not return an emoji."));
      return;
    }

    completion(icon, nil);
  }];
}

@end
