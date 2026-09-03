#import "OpenRouterParsing.h"
#import "OpenRouterSupport.h"

static BOOL TLStringArrayContains(NSArray *array, NSString *value) {
  for (id item in array) {
    if ([item isKindOfClass:NSString.class] && [(NSString *)item isEqualToString:value]) {
      return YES;
    }
  }

  return NO;
}

static NSString *TLGroupedInteger(NSInteger value) {
  NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
  formatter.numberStyle = NSNumberFormatterDecimalStyle;
  return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%ld", (long)value];
}

static NSString *TLPricePerMillionTokens(NSString *rawPrice) {
  NSString *trimmed = TLOpenRouterTrim(rawPrice);
  if (trimmed.length == 0) {
    return nil;
  }

  double price = trimmed.doubleValue * 1000000.0;
  if (price <= 0.0) {
    return @"$0/M";
  }
  if (price < 0.01) {
    return @"<$0.01/M";
  }
  if (price < 1.0) {
    return [NSString stringWithFormat:@"$%.2f/M", price];
  }
  if (price < 10.0) {
    return [NSString stringWithFormat:@"$%.1f/M", price];
  }
  return [NSString stringWithFormat:@"$%.0f/M", price];
}

@implementation TLOpenRouterModel

- (instancetype)init {
  self = [super init];
  if (self) {
    _modelID = @"";
    _name = @"";
    _modelDescription = @"";
    _promptPrice = @"";
    _completionPrice = @"";
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLOpenRouterModel *copy = [[[self class] allocWithZone:zone] init];
  copy.modelID = self.modelID;
  copy.name = self.name;
  copy.modelDescription = self.modelDescription;
  copy.contextLength = self.contextLength;
  copy.promptPrice = self.promptPrice;
  copy.completionPrice = self.completionPrice;
  return copy;
}

- (NSString *)displayTitle {
  return TLOpenRouterNonEmpty(self.name) ?: self.modelID;
}

- (NSString *)detailText {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  if (self.modelID.length > 0) {
    [parts addObject:self.modelID];
  }
  if (self.contextLength > 0) {
    [parts addObject:[NSString stringWithFormat:@"%@ context", TLGroupedInteger(self.contextLength)]];
  }

  NSString *promptPrice = TLPricePerMillionTokens(self.promptPrice);
  NSString *completionPrice = TLPricePerMillionTokens(self.completionPrice);
  if (promptPrice.length > 0) {
    [parts addObject:[NSString stringWithFormat:@"%@ input", promptPrice]];
  }
  if (completionPrice.length > 0) {
    [parts addObject:[NSString stringWithFormat:@"%@ output", completionPrice]];
  }

  return [parts componentsJoinedByString:@" | "];
}

@end

static TLOpenRouterModel *TLOpenRouterModelFromDictionary(NSDictionary *dictionary) {
  NSString *modelID = TLOpenRouterTrim(TLOpenRouterStringValue(dictionary[@"id"]));
  if (modelID.length == 0) {
    return nil;
  }

  NSDictionary *architecture = [dictionary[@"architecture"] isKindOfClass:NSDictionary.class] ? dictionary[@"architecture"] : nil;
  NSArray *outputModalities = [architecture[@"output_modalities"] isKindOfClass:NSArray.class] ? architecture[@"output_modalities"] : nil;
  if (outputModalities.count > 0 && !TLStringArrayContains(outputModalities, @"text")) {
    return nil;
  }

  NSDictionary *pricing = [dictionary[@"pricing"] isKindOfClass:NSDictionary.class] ? dictionary[@"pricing"] : nil;
  TLOpenRouterModel *model = [[TLOpenRouterModel alloc] init];
  model.modelID = modelID;
  model.name = TLOpenRouterNonEmpty(TLOpenRouterStringValue(dictionary[@"name"])) ?: modelID;
  model.modelDescription = TLOpenRouterStringValue(dictionary[@"description"]) ?: @"";
  model.contextLength = TLOpenRouterIntegerValue(dictionary[@"context_length"]);
  model.promptPrice = TLOpenRouterStringValue(pricing[@"prompt"]) ?: @"";
  model.completionPrice = TLOpenRouterStringValue(pricing[@"completion"]) ?: @"";
  return model;
}

NSArray<TLOpenRouterModel *> *TLParseOpenRouterModelsResponse(NSData *data, NSError **error) {
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (!json) {
    if (error && *error) {
      *error = TLOpenRouterError([NSString stringWithFormat:@"OpenRouter returned an unexpected models response: %@", (*error).localizedDescription]);
    }
    return nil;
  }

  if (![json isKindOfClass:NSDictionary.class]) {
    if (error) {
      *error = TLOpenRouterError(@"OpenRouter returned an unexpected models response.");
    }
    return nil;
  }

  NSArray *dataArray = ((NSDictionary *)json)[@"data"];
  if (![dataArray isKindOfClass:NSArray.class]) {
    if (error) {
      *error = TLOpenRouterError(@"OpenRouter returned a models response without a data array.");
    }
    return nil;
  }

  NSMutableArray<TLOpenRouterModel *> *models = [NSMutableArray arrayWithCapacity:dataArray.count];
  for (id item in dataArray) {
    if (![item isKindOfClass:NSDictionary.class]) {
      continue;
    }

    TLOpenRouterModel *model = TLOpenRouterModelFromDictionary(item);
    if (model) {
      [models addObject:model];
    }
  }

  return models;
}

static NSString *TLContentToText(id content) {
  if (!content || content == NSNull.null) {
    return nil;
  }

  if ([content isKindOfClass:NSString.class]) {
    return content;
  }

  if ([content isKindOfClass:NSArray.class]) {
    NSMutableString *text = [NSMutableString string];

    for (id part in (NSArray *)content) {
      if (![part isKindOfClass:NSDictionary.class]) {
        continue;
      }

      id partText = part[@"text"] ?: part[@"content"];
      if ([partText isKindOfClass:NSString.class]) {
        [text appendString:partText];
      }
    }

    return TLOpenRouterNonEmpty(text);
  }

  return nil;
}

static NSString *TLReasoningDetailsToText(id details) {
  if (![details isKindOfClass:NSArray.class]) {
    return nil;
  }

  NSMutableString *text = [NSMutableString string];

  for (id detail in (NSArray *)details) {
    if (![detail isKindOfClass:NSDictionary.class]) {
      continue;
    }

    id detailText = detail[@"text"] ?: detail[@"summary"];
    if ([detailText isKindOfClass:NSString.class]) {
      [text appendString:detailText];
    }
  }

  return TLOpenRouterNonEmpty(text);
}

static NSString *TLThinkingTextFromDelta(NSDictionary *delta) {
  NSString *reasoningDetailsText = TLReasoningDetailsToText(delta[@"reasoning_details"]);
  if (reasoningDetailsText.length > 0) {
    return reasoningDetailsText;
  }

  NSString *reasoningText = TLContentToText(delta[@"reasoning"]);
  if (reasoningText.length > 0) {
    return reasoningText;
  }

  NSString *reasoningContentText = TLContentToText(delta[@"reasoning_content"]);
  if (reasoningContentText.length > 0) {
    return reasoningContentText;
  }

  return nil;
}

NSDictionary<NSString *, NSString *> *TLParseOpenRouterStreamDelta(NSString *data, NSError **error) {
  NSData *jsonData = [data dataUsingEncoding:NSUTF8StringEncoding];
  id json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
  if (!json) {
    if (error && *error) {
      *error = TLOpenRouterError([NSString stringWithFormat:@"OpenRouter returned an unexpected stream chunk: %@", (*error).localizedDescription]);
    }
    return nil;
  }

  if (![json isKindOfClass:NSDictionary.class]) {
    if (error) {
      *error = TLOpenRouterError(@"OpenRouter returned an unexpected stream chunk.");
    }
    return nil;
  }

  NSMutableString *content = [NSMutableString string];
  NSMutableString *thinking = [NSMutableString string];
  NSArray *choices = json[@"choices"];

  if (![choices isKindOfClass:NSArray.class]) {
    return @{@"content": @"", @"thinking": @""};
  }

  for (id choice in choices) {
    if (![choice isKindOfClass:NSDictionary.class]) {
      continue;
    }

    id delta = choice[@"delta"];
    if (![delta isKindOfClass:NSDictionary.class]) {
      continue;
    }

    NSString *contentText = TLContentToText(delta[@"content"]);
    if (contentText.length > 0) {
      [content appendString:contentText];
    }

    NSString *thinkingText = TLThinkingTextFromDelta(delta);
    if (thinkingText.length > 0) {
      [thinking appendString:thinkingText];
    }
  }

  return @{
    @"content": content,
    @"thinking": thinking,
  };
}
