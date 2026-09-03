#import "InputSuggestions.h"

@implementation TLInputSuggestions

+ (nullable NSURLComponents *)componentsForInput:(NSString *)input {
  if (input.length == 0 || [input rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
    return nil;
  }
  NSString *lowercase = input.lowercaseString;
  BOOL explicitScheme = [lowercase hasPrefix:@"http://"] || [lowercase hasPrefix:@"https://"];
  if ([input containsString:@"://"] && !explicitScheme) {
    return nil;
  }
  NSURLComponents *components = [NSURLComponents componentsWithString:explicitScheme ? input : [@"https://" stringByAppendingString:input]];
  if (components.user.length > 0 || components.password.length > 0) {
    return nil;
  }
  return components;
}

+ (nullable NSURL *)browserURLForInput:(NSString *)input {
  NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSURLComponents *components = [self componentsForInput:text];
  NSString *host = components.host.lowercaseString;
  if (host.length == 0 || [host hasSuffix:@"."] || [host hasPrefix:@"."] || [host containsString:@".."] ||
      [host rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
    return nil;
  }
  NSString *lowercase = text.lowercaseString;
  BOOL explicitScheme = [lowercase hasPrefix:@"http://"] || [lowercase hasPrefix:@"https://"];
  if (!explicitScheme && ![host containsString:@"."] && ![host isEqualToString:@"localhost"]) {
    return nil;
  }
  return components.URL;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)webSuggestionsForInput:(NSString *)input {
  NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0 || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound || [text hasPrefix:@"/"]) {
    return @[];
  }
  NSString *lowercase = text.lowercaseString;
  BOOL protocolPrefix = lowercase.length >= 4 && ([@"https://" hasPrefix:lowercase] || [@"http://" hasPrefix:lowercase]);
  NSURL *URL = [self browserURLForInput:text];
  NSString *host = [self componentsForInput:text].host;
  BOOL domainPrefix = [host containsString:@"."] && ![host hasPrefix:@"."] && ![host containsString:@".."];
  if (!URL && !protocolPrefix && ![lowercase isEqualToString:@"www"] && !domainPrefix) {
    return @[];
  }
  return @[
    @{@"kind": @"web", @"value": text, @"URL": URL.absoluteString ?: @"",
      @"command": [@"Open " stringByAppendingString:text], @"title": @"Open web page", @"icon": @"safari"},
    @{@"kind": @"prompt", @"value": text,
      @"command": @"Send message", @"title": @"Send message", @"icon": @"text.bubble"},
  ];
}

@end
