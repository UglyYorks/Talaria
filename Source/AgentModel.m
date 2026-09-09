#import "AgentModel.h"

static NSString *TLModelString(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

@implementation TLAgentModel
- (instancetype)init {
  self = [super init];
  if (self) {
    _modelID = @"";
    _providerID = @"";
    _name = @"";
    _modelDescription = @"";
    _inputPrice = @"";
    _outputPrice = @"";
  }
  return self;
}
- (id)copyWithZone:(NSZone *)zone {
  TLAgentModel *copy = [[[self class] allocWithZone:zone] init];
  copy.modelID = self.modelID;
  copy.providerID = self.providerID;
  copy.name = self.name;
  copy.modelDescription = self.modelDescription;
  copy.inputPrice = self.inputPrice;
  copy.outputPrice = self.outputPrice;
  return copy;
}
- (NSString *)displayTitle { return self.name.length ? self.name : self.modelID; }
- (NSString *)detailText {
  NSMutableArray *parts = [NSMutableArray arrayWithObject:self.modelID];
  if (self.inputPrice.length) [parts addObject:[self.inputPrice stringByAppendingString:@"/M input"]];
  if (self.outputPrice.length) [parts addObject:[self.outputPrice stringByAppendingString:@"/M output"]];
  return [parts componentsJoinedByString:@" | "];
}
@end

NSArray<TLAgentModel *> *TLParseHermesModelOptions(NSData *data, NSError **error) {
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (!json) return nil;
  if (![json isKindOfClass:NSDictionary.class] || ![json[@"providers"] isKindOfClass:NSArray.class]) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.Hermes" code:1
      userInfo:@{NSLocalizedDescriptionKey: @"Hermes returned an invalid model catalogue."}];
    return nil;
  }
  NSMutableArray *models = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (id provider in json[@"providers"]) {
    if (![provider isKindOfClass:NSDictionary.class] || !TLModelString(provider[@"slug"]).length ||
        ![provider[@"models"] isKindOfClass:NSArray.class]) continue;
    NSDictionary *pricing = [provider[@"pricing"] isKindOfClass:NSDictionary.class] ? provider[@"pricing"] : @{};
    for (id value in provider[@"models"]) {
      NSString *modelID = [TLModelString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      NSString *selection = [NSString stringWithFormat:@"%@::%@", provider[@"slug"], modelID];
      if (!modelID.length || [seen containsObject:selection]) continue;
      [seen addObject:selection];
      TLAgentModel *model = [[TLAgentModel alloc] init];
      model.modelID = selection;
      model.providerID = provider[@"slug"];
      model.name = modelID;
      model.modelDescription = TLModelString(provider[@"name"]);
      NSDictionary *prices = [pricing[modelID] isKindOfClass:NSDictionary.class] ? pricing[modelID] : @{};
      model.inputPrice = TLModelString(prices[@"input"]);
      model.outputPrice = TLModelString(prices[@"output"]);
      [models addObject:model];
    }
  }
  return models;
}
