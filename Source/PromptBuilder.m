#import "PromptBuilder.h"
#import <math.h>

@interface TLPromptPart : NSObject

@property (nonatomic) NSInteger partID;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *originalContent;
@property (nonatomic) TLPromptImportance importance;
@property (nonatomic) TLPromptCompactionStrategy strategy;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSUInteger removedCharacters;
@property (nonatomic) BOOL removed;

@end

@implementation TLPromptPart
@end

@implementation TLCompactedPromptPart
@end

@implementation TLCompactedPrompt
@end

@interface TLPromptBuilder ()

@property (nonatomic, strong) NSNumber *limit;
@property (nonatomic, copy) NSString *separator;
@property (nonatomic, strong) NSMutableArray<TLPromptPart *> *parts;
@property (nonatomic) NSInteger nextID;

@end

@implementation TLPromptBuilder

- (instancetype)init {
  return [self initWithLimit:nil separator:@"\n"];
}

- (instancetype)initWithLimit:(NSNumber *)limit separator:(NSString *)separator {
  self = [super init];
  if (self) {
    if (limit) {
      [self assertValidLimit:limit];
    }

    _limit = limit;
    _separator = [separator copy];
    _parts = [NSMutableArray array];
    _nextID = 0;
  }
  return self;
}

- (instancetype)addPartWithContent:(NSString *)content
                        importance:(TLPromptImportance)importance
                          strategy:(TLPromptCompactionStrategy)strategy
                              name:(NSString *)name {
  [self validateImportance:importance strategy:strategy];

  TLPromptPart *part = [[TLPromptPart alloc] init];
  part.partID = self.nextID++;
  part.content = content;
  part.originalContent = content;
  part.importance = importance;
  part.strategy = strategy;
  part.name = name;
  part.removedCharacters = 0;
  part.removed = NO;
  [self.parts addObject:part];
  return self;
}

- (instancetype)withLimit:(NSNumber *)limit {
  if (limit) {
    [self assertValidLimit:limit];
  }

  self.limit = limit;
  return self;
}

- (NSString *)build {
  return [self compact].prompt;
}

- (TLCompactedPrompt *)compact {
  NSMutableArray<TLPromptPart *> *compactedParts = [NSMutableArray arrayWithCapacity:self.parts.count];

  for (TLPromptPart *part in self.parts) {
    TLPromptPart *copy = [[TLPromptPart alloc] init];
    copy.partID = part.partID;
    copy.content = part.content;
    copy.originalContent = part.content;
    copy.importance = part.importance;
    copy.strategy = part.strategy;
    copy.name = part.name;
    copy.removedCharacters = 0;
    copy.removed = NO;
    [compactedParts addObject:copy];
  }

  NSUInteger originalLength = [self joinParts:compactedParts].length;

  if (!self.limit || originalLength <= self.limit.unsignedIntegerValue) {
    NSString *prompt = [self joinParts:compactedParts];
    return [self promptWithText:prompt
                          limit:self.limit
                         length:prompt.length
                 originalLength:originalLength
                   wasCompacted:NO
                          parts:compactedParts];
  }

  NSArray<NSNumber *> *importanceOrder = @[@(TLPromptImportanceOptional), @(TLPromptImportanceUseful), @(TLPromptImportanceRequired)];
  for (NSNumber *importanceValue in importanceOrder) {
    TLPromptImportance importance = importanceValue.integerValue;

    for (TLPromptPart *part in [compactedParts copy]) {
      if ([self joinParts:compactedParts].length <= self.limit.unsignedIntegerValue) {
        break;
      }

      if (part.importance != importance) {
        continue;
      }

      if (part.strategy == TLPromptCompactionStrategyWhole) {
        part.content = @"";
      } else {
        part.content = [self largestFittingContentForPart:part allParts:compactedParts];
      }

      part.removedCharacters = part.originalContent.length - part.content.length;
      part.removed = part.content.length == 0;
    }
  }

  NSString *prompt = [self joinParts:compactedParts];
  return [self promptWithText:prompt
                        limit:self.limit
                       length:prompt.length
               originalLength:originalLength
                 wasCompacted:prompt.length != originalLength
                        parts:compactedParts];
}

- (instancetype)clear {
  [self.parts removeAllObjects];
  return self;
}

- (NSString *)largestFittingContentForPart:(TLPromptPart *)part allParts:(NSArray<TLPromptPart *> *)allParts {
  NSInteger low = 0;
  NSInteger high = (NSInteger)part.content.length;
  NSString *best = @"";

  while (low <= high) {
    NSInteger length = (low + high) / 2;
    part.content = [self sliceContent:part.originalContent strategy:part.strategy length:(NSUInteger)length];

    if ([self joinParts:allParts].length <= self.limit.unsignedIntegerValue) {
      best = part.content;
      low = length + 1;
    } else {
      high = length - 1;
    }
  }

  return best;
}

- (NSString *)sliceContent:(NSString *)content strategy:(TLPromptCompactionStrategy)strategy length:(NSUInteger)length {
  if (length >= content.length) {
    return content;
  }

  if (strategy == TLPromptCompactionStrategyKeepEnd) {
    return [content substringFromIndex:content.length - length];
  }

  return [content substringToIndex:length];
}

- (NSString *)joinParts:(NSArray<TLPromptPart *> *)parts {
  NSMutableArray<NSString *> *contentParts = [NSMutableArray array];

  for (TLPromptPart *part in parts) {
    if (part.content.length > 0) {
      [contentParts addObject:part.content];
    }
  }

  return [contentParts componentsJoinedByString:self.separator];
}

- (TLCompactedPrompt *)promptWithText:(NSString *)text
                                limit:(NSNumber *)limit
                               length:(NSUInteger)length
                       originalLength:(NSUInteger)originalLength
                         wasCompacted:(BOOL)wasCompacted
                                parts:(NSArray<TLPromptPart *> *)parts {
  TLCompactedPrompt *prompt = [[TLCompactedPrompt alloc] init];
  prompt.prompt = text;
  prompt.limit = limit;
  prompt.length = length;
  prompt.originalLength = originalLength;
  prompt.wasCompacted = wasCompacted;
  prompt.parts = [self publicPartsFromParts:parts];
  return prompt;
}

- (NSArray<TLCompactedPromptPart *> *)publicPartsFromParts:(NSArray<TLPromptPart *> *)parts {
  NSMutableArray<TLCompactedPromptPart *> *publicParts = [NSMutableArray arrayWithCapacity:parts.count];

  for (TLPromptPart *part in parts) {
    TLCompactedPromptPart *publicPart = [[TLCompactedPromptPart alloc] init];
    publicPart.content = part.content;
    publicPart.originalContent = part.originalContent;
    publicPart.importance = part.importance;
    publicPart.strategy = part.strategy;
    publicPart.name = part.name;
    publicPart.removedCharacters = part.removedCharacters;
    publicPart.removed = part.removed;
    [publicParts addObject:publicPart];
  }

  return publicParts;
}

- (void)validateImportance:(TLPromptImportance)importance strategy:(TLPromptCompactionStrategy)strategy {
  if (importance < TLPromptImportanceRequired || importance > TLPromptImportanceOptional) {
    [NSException raise:NSInvalidArgumentException format:@"Prompt part importance must be 1, 2, or 3."];
  }

  if (strategy < TLPromptCompactionStrategyWhole || strategy > TLPromptCompactionStrategyKeepEnd) {
    [NSException raise:NSInvalidArgumentException
                format:@"Prompt part compaction strategy must be whole, keep-start, or keep-end."];
  }
}

- (void)assertValidLimit:(NSNumber *)limit {
  if (limit.integerValue < 0 || limit.doubleValue != floor(limit.doubleValue)) {
    [NSException raise:NSInvalidArgumentException format:@"Prompt limit must be a non-negative integer."];
  }
}

@end
