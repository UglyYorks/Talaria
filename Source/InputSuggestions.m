#import "InputSuggestions.h"
#import <math.h>

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

// Keep path/query case and fragments: they can identify different documents.
+ (NSString *)destinationKeyForURL:(NSURL *)URL {
  NSURLComponents *parts = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
  parts.scheme = parts.scheme.lowercaseString;
  parts.host = parts.host.lowercaseString;
  if (([parts.scheme isEqual:@"https"] && parts.port.integerValue == 443) ||
      ([parts.scheme isEqual:@"http"] && parts.port.integerValue == 80)) parts.port = nil;
  if (!parts.path.length) parts.path = @"/";
  return parts.string ?: URL.absoluteString;
}

+ (NSArray<NSDictionary *> *)prepareLocalCandidates:(NSArray<NSDictionary *> *)candidates {
  NSMutableArray *prepared = [NSMutableArray arrayWithCapacity:candidates.count];
  NSISO8601DateFormatter *dates = [NSISO8601DateFormatter new];
  for (NSDictionary *candidate in candidates) {
    if (candidate[@"destinationKey"]) { [prepared addObject:candidate]; continue; }
    NSURL *URL = [self browserURLForInput:candidate[@"URL"] ?: @""];
    if (!URL) continue;
    NSString *fullAddress = URL.absoluteString.lowercaseString;
    NSString *address = [fullAddress substringFromIndex:NSMaxRange([fullAddress rangeOfString:@"://"])];
    if ([address hasPrefix:@"www."]) address = [address substringFromIndex:4];
    NSString *host = URL.host.lowercaseString ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    NSString *timestamp = [candidate[@"visitedAt"] ?: @"" stringByReplacingOccurrencesOfString:@" " withString:@"T"];
    if (timestamp.length == 19) timestamp = [timestamp stringByAppendingString:@"Z"];
    NSDate *date = [dates dateFromString:timestamp];
    NSMutableDictionary *entry = [candidate mutableCopy];
    entry[@"URL"] = URL.absoluteString;
    NSString *title = [candidate[@"title"] ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *titleURL = [self browserURLForInput:title];
    BOOL fallbackTitle = !title.length || (titleURL && [[self destinationKeyForURL:titleURL] isEqual:[self destinationKeyForURL:URL]]);
    entry[@"fallbackTitle"] = @(fallbackTitle);
    entry[@"title"] = fallbackTitle ? host : title;
    entry[@"domain"] = host;
    entry[@"destinationKey"] = [self destinationKeyForURL:URL];
    entry[@"fields"] = @[[entry[@"title"] lowercaseString], address, fullAddress, host];
    entry[@"visitedTimestamp"] = @(date ? date.timeIntervalSince1970 : 0);
    [prepared addObject:entry];
  }
  return prepared;
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)suggestionsForInput:(NSString *)input
  commands:(NSArray<NSDictionary *> *)commands localCandidates:(NSArray<NSDictionary *> *)candidates
  searchURL:(NSURL *)searchURL hasAttachments:(BOOL)attachments {
  NSString *query = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!query.length) return @[];
  NSDictionary *prompt = @{@"kind":@"prompt", @"value":input, @"command":@"Ask agent",
    @"title":input, @"icon":@"text.bubble"};
  NSDictionary *search = @{@"kind":@"search", @"value":input, @"URL":searchURL.absoluteString ?: @"",
    @"command":[@"Search for " stringByAppendingString:input], @"title":input, @"icon":@"magnifyingglass"};
  NSArray *slash = [self slashCommandsForInput:input commands:commands];
  if ([query hasPrefix:@"/"]) {
    if (!slash.count) return @[prompt, search];
    NSMutableArray *rows = [slash mutableCopy];
    [rows insertObject:prompt atIndex:0];
    [rows insertObject:search atIndex:MIN(2, rows.count)];
    return rows;
  }
  NSString *needle = query.lowercaseString;
  NSURL *URL = [self browserURLForInput:query];
  NSString *navigationKey = URL ? [self destinationKeyForURL:URL] : nil;
  NSArray *prepared = [self prepareLocalCandidates:candidates];
  NSMutableDictionary<NSString *, NSNumber *> *ranks = [NSMutableDictionary dictionary];
  // First collect matching identities. Unmatched visits still contribute frequency
  // when an open tab or bookmark matches under a different title for the same URL.
  for (NSDictionary *candidate in prepared) {
    NSInteger rank = 0;
    for (NSString *field in candidate[@"fields"]) {
      if ([field isEqual:needle]) rank = MAX(rank, 3);
      else if ([field hasPrefix:needle]) rank = MAX(rank, 2);
      else if ([field containsString:needle]) rank = MAX(rank, 1);
    }
    NSString *key = candidate[@"destinationKey"];
    if (rank || [key isEqual:navigationKey]) ranks[key] = @(MAX(rank, ranks[key].integerValue));
  }
  NSMutableDictionary<NSString *, NSMutableDictionary *> *destinations = [NSMutableDictionary dictionary];
  for (NSDictionary *candidate in prepared) {
    NSString *key = candidate[@"destinationKey"];
    if (!ranks[key]) continue;
    NSMutableDictionary *entry = destinations[key];
    if (!entry) {
      entry = [@{@"URL":candidate[@"URL"], @"title":@"", @"visits":@0, @"visitedAt":@"", @"rank":ranks[key]} mutableCopy];
      destinations[key] = entry;
    }
    NSString *domain = candidate[@"domain"] ?: @"";
    entry[@"domainRank"] = @([domain isEqual:needle] ? 3 : ([domain hasPrefix:needle] ? 2 : ([domain containsString:needle] ? 1 : 0)));
    NSString *title = candidate[@"title"] ?: @"";
    NSString *date = candidate[@"visitedAt"] ?: @"";
    BOOL hasTitle = [entry[@"title"] length] > 0;
    BOOL fallbackTitle = [candidate[@"fallbackTitle"] boolValue];
    if (!hasTitle || (!fallbackTitle && ([entry[@"fallbackTitle"] boolValue] || candidate[@"tabID"] || candidate[@"bookmark"] ||
        [date compare:entry[@"visitedAt"]] == NSOrderedDescending))) {
      entry[@"title"] = title;
      entry[@"fallbackTitle"] = @(fallbackTitle);
    }
    entry[@"visits"] = @([entry[@"visits"] integerValue] + [candidate[@"visits"] integerValue]);
    if ([date compare:entry[@"visitedAt"]] == NSOrderedDescending) entry[@"visitedAt"] = date;
    entry[@"visitedTimestamp"] = @(MAX([entry[@"visitedTimestamp"] doubleValue], [candidate[@"visitedTimestamp"] doubleValue]));
    if (candidate[@"tabID"]) entry[@"tabID"] = candidate[@"tabID"];
    if (candidate[@"bookmark"]) entry[@"bookmark"] = @YES;
    if (candidate[@"faviconData"]) entry[@"faviconData"] = candidate[@"faviconData"];
    if (candidate[@"faviconImage"]) entry[@"faviconImage"] = candidate[@"faviconImage"];
  }
  NSComparator compare = ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    NSComparisonResult order = [b[@"domainRank"] compare:a[@"domainRank"]];
    if (order != NSOrderedSame) return order;
    order = [b[@"rank"] compare:a[@"rank"]];
    if (order != NSOrderedSame) return order;
    // Frequency and recency each contribute within a match class, never across it.
    order = [b[@"boost"] compare:a[@"boost"]];
    return order == NSOrderedSame ? [a[@"URL"] compare:b[@"URL"]] : order;
  };
  NSMutableArray *matches = [NSMutableArray array];
  NSTimeInterval now = NSDate.date.timeIntervalSince1970;
  for (NSMutableDictionary *entry in destinations.allValues) {
    if (![entry[@"rank"] integerValue]) continue;
    double days = MAX(0, (now - [entry[@"visitedTimestamp"] doubleValue]) / 86400.0);
    entry[@"boost"] = @(log1p([entry[@"visits"] doubleValue]) + 3.0 / (1.0 + days / 7.0));
    // Keep only visible results; broad prefixes need no full-history sort.
    NSUInteger index = [matches indexOfObject:entry inSortedRange:NSMakeRange(0, matches.count)
      options:NSBinarySearchingInsertionIndex usingComparator:compare];
    if (index < 6) [matches insertObject:entry atIndex:index];
    if (matches.count > 6) [matches removeLastObject];
  }
  NSMutableArray *local = [NSMutableArray array];
  for (NSDictionary *entry in matches) {
    if (local.count == 6) break;
    NSString *title = [entry[@"title"] length] ? entry[@"title"] : entry[@"URL"];
    NSMutableDictionary *row = [@{@"kind":entry[@"tabID"] ? @"tab" : @"web", @"value":input,
      @"URL":entry[@"URL"], @"command":entry[@"tabID"] ? [@"Switch to tab · " stringByAppendingString:title] : title,
      @"title":title, @"description":entry[@"URL"], @"match":query,
      @"domainMatch":[entry[@"domainRank"] integerValue] > 0 ? @"yes" : @"no",
      @"icon":entry[@"tabID"] ? @"square.on.square" : (entry[@"bookmark"] ? @"bookmark" : @"clock"),
      @"strong":([entry[@"rank"] integerValue] == 3 || ([entry[@"rank"] integerValue] == 2 && needle.length >= 3)) ? @"yes" : @"no"} mutableCopy];
    if (entry[@"tabID"]) row[@"tabID"] = [entry[@"tabID"] description];
    if (entry[@"faviconData"]) row[@"faviconData"] = entry[@"faviconData"];
    if (entry[@"faviconImage"]) row[@"faviconImage"] = entry[@"faviconImage"];
    [local addObject:row];
  }
  NSMutableDictionary *go = nil;
  if (URL) {
    NSString *key = [self destinationKeyForURL:URL];
    NSDictionary *open = destinations[key];
    NSString *domain = URL.host.lowercaseString ?: URL.absoluteString;
    if ([domain hasPrefix:@"www."]) domain = [domain substringFromIndex:4];
    go = [@{@"kind":open[@"tabID"] ? @"tab" : @"web", @"value":input, @"URL":URL.absoluteString,
      @"command":[@"Go to " stringByAppendingString:domain], @"title":URL.absoluteString, @"icon":@"safari"} mutableCopy];
    if (open[@"faviconData"]) go[@"faviconData"] = open[@"faviconData"];
    if (open[@"faviconImage"]) go[@"faviconImage"] = open[@"faviconImage"];
    if (open[@"tabID"]) {
      go[@"tabID"] = [open[@"tabID"] description];
      go[@"command"] = [@"Switch to tab · Go to " stringByAppendingString:domain];
    }
    NSIndexSet *duplicates = [local indexesOfObjectsPassingTest:^BOOL(NSDictionary *row, NSUInteger idx, BOOL *stop) {
      return [[self destinationKeyForURL:[NSURL URLWithString:row[@"URL"]]] isEqual:key];
    }];
    [local removeObjectsAtIndexes:duplicates];
  }
  BOOL domainMatch = [local.firstObject[@"domainMatch"] isEqual:@"yes"];
  NSDictionary *primary = go ?: ((domainMatch || [local.firstObject[@"strong"] isEqual:@"yes"]) ? local.firstObject : search);
  BOOL websiteFirst = !attachments && (go || domainMatch);
  NSMutableArray *rows = [NSMutableArray arrayWithArray:websiteFirst ? @[primary, prompt] : @[prompt, primary]];
  if (primary != search) [rows addObject:search];
  for (NSDictionary *row in local) if (row != primary) [rows addObject:row];
  return rows;
}

@end
