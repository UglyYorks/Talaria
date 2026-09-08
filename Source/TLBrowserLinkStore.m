#import "TLBrowserLinkStore.h"
#import "TLBrowserPreferences.h"
BOOL TLBrowserLinkURLIsNavigable(NSURL *URL) {
  return URL.host.length && [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString];
}
@interface TLBrowserLinkStore ()
@property NSURL *URL;
@property NSDictionary *contents;
@end
@implementation TLBrowserLinkStore
+ (instancetype)sharedStore {
  static TLBrowserLinkStore *store; static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [[self alloc] initWithURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"TalariaLinks.json"]]; }); return store;
}
- (instancetype)initWithURL:(NSURL *)URL {
  if ((self = [super init])) {
    _URL = URL;
    NSData *data = [NSData dataWithContentsOfURL:URL];
    NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) saved = @{};
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    NSMutableArray *groups = [NSMutableArray array];
    if ([saved[@"groups"] isKindOfClass:NSArray.class]) for (NSDictionary *group in saved[@"groups"]) {
      if (![group isKindOfClass:NSDictionary.class] || ![group[@"id"] isKindOfClass:NSString.class] ||
          ![group[@"title"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:group[@"id"]]) continue;
      if (![[groups valueForKey:@"id"] containsObject:group[@"id"]]) [groups addObject:@{@"id":group[@"id"], @"title":group[@"title"]}];
    }
    clean[@"groups"] = groups;
    for (NSString *key in [groups valueForKey:@"id"]) {
      NSMutableArray *links = [NSMutableArray array];
      if ([saved[key] isKindOfClass:NSArray.class]) for (NSDictionary *link in saved[key]) {
        if (![link isKindOfClass:NSDictionary.class] || ![link[@"url"] isKindOfClass:NSString.class] || ![link[@"title"] isKindOfClass:NSString.class]) continue;
        if (TLBrowserLinkURLIsNavigable([NSURL URLWithString:link[@"url"]])) [links addObject:@{@"url":link[@"url"], @"title":link[@"title"]}];
      }
      clean[key] = links;
    }
    _contents = clean;
  } return self;
}
- (NSArray *)groups { return self.contents[@"groups"]; }
- (NSArray *)linksInCollection:(NSString *)collection { return self.contents[collection] ?: @[]; }
- (BOOL)save:(NSDictionary *)contents error:(NSError **)error {
  NSData *data = [NSJSONSerialization dataWithJSONObject:contents options:NSJSONWritingPrettyPrinted error:error];
  if (!data || ![NSFileManager.defaultManager createDirectoryAtURL:self.URL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
      ![data writeToURL:self.URL options:NSDataWritingAtomic error:error]) return NO;
  self.contents = contents; return YES;
}
- (BOOL)addURL:(NSURL *)URL title:(NSString *)title collection:(NSString *)collection error:(NSError **)error {
  if (!TLBrowserLinkURLIsNavigable(URL) || !self.contents[collection] || [collection isEqual:@"groups"]) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.Links" code:1 userInfo:@{NSLocalizedDescriptionKey:@"This link cannot be saved in this collection."}]; return NO;
  }
  NSMutableDictionary *contents = self.contents.mutableCopy;
  NSMutableArray *links = [self linksInCollection:collection].mutableCopy;
  NSIndexSet *duplicates = [links indexesOfObjectsPassingTest:^BOOL(NSDictionary *link, NSUInteger index, BOOL *stop) { return [link[@"url"] isEqual:URL.absoluteString]; }];
  [links removeObjectsAtIndexes:duplicates];
  NSString *name = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  [links addObject:@{@"url":URL.absoluteString, @"title":name.length ? name : URL.absoluteString}];
  contents[collection] = links; return [self save:contents error:error];
}
- (NSString *)createGroupNamed:(NSString *)name error:(NSError **)error {
  NSString *title = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!title.length) title = @"Untitled Group";
  NSString *identifier = NSUUID.UUID.UUIDString;
  NSMutableDictionary *contents = self.contents.mutableCopy;
  contents[@"groups"] = [self.groups arrayByAddingObject:@{@"id":identifier, @"title":title}]; contents[identifier] = @[];
  return [self save:contents error:error] ? identifier : nil;
}
- (BOOL)removeURL:(NSString *)URLString collection:(NSString *)collection error:(NSError **)error {
  if ([collection isEqual:@"groups"] || !self.contents[collection]) return NO;
  NSMutableDictionary *contents = self.contents.mutableCopy;
  NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *link, NSDictionary *bindings) { return ![link[@"url"] isEqual:URLString]; }];
  contents[collection] = [[self linksInCollection:collection] filteredArrayUsingPredicate:keep]; return [self save:contents error:error];
}
- (BOOL)removeGroup:(NSString *)identifier error:(NSError **)error {
  NSMutableDictionary *contents = self.contents.mutableCopy;
  contents[@"groups"] = [self.groups filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *group, NSDictionary *bindings) { return ![group[@"id"] isEqual:identifier]; }]];
  if (![[self.groups valueForKey:@"id"] containsObject:identifier]) return NO;
  [contents removeObjectForKey:identifier]; return [self save:contents error:error];
}
@end
