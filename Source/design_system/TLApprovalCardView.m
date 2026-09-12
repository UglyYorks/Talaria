#import "TLApprovalCardView.h"

NSArray<NSString *> *TLApprovalChoices(NSDictionary *request) {
  NSArray *choices = [request[@"choices"] isKindOfClass:NSArray.class] ? request[@"choices"] : @[@"once", @"deny"];
  NSMutableOrderedSet *allowed = [NSMutableOrderedSet orderedSet];
  for (id choice in choices) {
    if ([@[@"once", @"session", @"always", @"deny"] containsObject:choice]) [allowed addObject:choice];
  }
  return allowed.array;
}

NSString *TLApprovalChoiceTitle(NSString *choice) {
  return @{@"once":@"Allow once", @"session":@"Allow this session", @"always":@"Always allow", @"deny":@"Deny"}[choice] ?: @"";
}

@implementation TLApprovalCardView
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette {
  if ([request[@"kind"] isEqual:@"clarification"]) return [super initWithRequest:request palette:palette];
  NSMutableDictionary *question = [request mutableCopy];
  question[@"title"] = [request[@"submitted"] boolValue] ? @"Approval response sent" : @"Approval required";
  if (![request[@"description"] length]) question[@"description"] = @"Hermes needs your permission to run this command.";
  NSMutableArray *options = [NSMutableArray array];
  for (NSString *choice in TLApprovalChoices(request))
    [options addObject:@{@"id":choice, @"title":TLApprovalChoiceTitle(choice), @"primary":@([choice isEqual:@"once"])}];
  question[@"options"] = options;
  return [super initWithRequest:question palette:palette];
}
@end
