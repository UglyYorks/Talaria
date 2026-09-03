#import "OpenRouterSupport.h"

NSString * const TLOpenRouterErrorDomain = @"Talaria.OpenRouter";

NSError *TLOpenRouterError(NSString *message) {
  return [NSError errorWithDomain:TLOpenRouterErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

NSString *TLOpenRouterTrim(NSString *value) {
  return [(value ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *TLOpenRouterNonEmpty(NSString *value) {
  return value.length > 0 ? value : nil;
}

NSString *TLOpenRouterStringValue(id value) {
  return [value isKindOfClass:NSString.class] ? value : nil;
}

NSInteger TLOpenRouterIntegerValue(id value) {
  return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}
