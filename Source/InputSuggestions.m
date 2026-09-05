#import "InputSuggestions.h"

@implementation TLInputSuggestions

// Hermes owns names, aliases, descriptions, argument modes, and skill discovery.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)hermesCommandsFromCatalogue:(NSDictionary *)catalogue {
  NSMutableArray *rows = [NSMutableArray array];
  NSMutableDictionary *byName = [NSMutableDictionary dictionary];
  NSDictionary *metadata = [catalogue[@"commands"] isKindOfClass:NSDictionary.class] ? catalogue[@"commands"] : @{};
  NSArray *pairs = [catalogue[@"pairs"] isKindOfClass:NSArray.class] ? catalogue[@"pairs"] : @[];
  for (id pair in pairs) {
    if (![pair isKindOfClass:NSArray.class] || [pair count] < 2 ||
        ![pair[0] isKindOfClass:NSString.class] || ![pair[1] isKindOfClass:NSString.class]) continue;
    NSString *name = pair[0];
    if (![name hasPrefix:@"/"] || name.length < 2 || byName[name] ||
        [name rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) continue;
    NSDictionary *meta = [metadata[name] isKindOfClass:NSDictionary.class] ? metadata[name] : @{};
    NSString *argumentMode = [meta[@"argument_mode"] isKindOfClass:NSString.class] ? meta[@"argument_mode"] : @"";
    NSDictionary *row = @{@"kind": @"hermes", @"command": name, @"description": pair[1],
                          @"title": pair[1], @"icon": @"terminal", @"argument_mode": argumentMode};
    [rows addObject:row];
    byName[name] = row;
  }
  NSDictionary *aliases = [catalogue[@"canon"] isKindOfClass:NSDictionary.class] ? catalogue[@"canon"] : @{};
  for (id alias in [[aliases allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    id canonical = aliases[alias];
    if (![alias isKindOfClass:NSString.class] || ![canonical isKindOfClass:NSString.class] ||
        ![alias hasPrefix:@"/"] || byName[alias] || !byName[canonical]) continue;
    NSMutableDictionary *row = [byName[canonical] mutableCopy];
    row[@"command"] = alias;
    [rows addObject:row];
    byName[alias] = row;
  }
  return rows;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsForInput:(NSString *)input commands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands {
  NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (![text hasPrefix:@"/"] ||
      [input hasSuffix:@" "] || [input hasSuffix:@"\t"] ||
      [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return @[];
  NSMutableArray *matches = [NSMutableArray array];
  for (NSDictionary *command in commands) {
    NSString *name = [command[@"command"] lowercaseString];
    if ([name isEqualToString:text.lowercaseString]) [matches insertObject:command atIndex:0];
    else if ([name hasPrefix:text.lowercaseString]) [matches addObject:command];
  }
  return matches;
}

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
