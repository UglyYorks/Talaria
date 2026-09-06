#import "TLWorkspaceSplitState.h"

NSString *TLWorkspaceTabIdentity(TLWorkspaceTab *tab) {
  return tab.presentationIdentity ?: [NSString stringWithFormat:@"%ld:%ld", (long)tab.kind, (long)tab.tabID];
}
@implementation TLWorkspaceSplitGroup
@end

@interface TLWorkspaceSplitState ()
@property (nonatomic, copy, readwrite) NSArray<TLWorkspaceSplitGroup *> *groups;
@end
@implementation TLWorkspaceSplitState
- (instancetype)init {
  if ((self = [super init])) _groups = @[];
  return self;
}
- (TLWorkspaceSplitGroup *)groupForTab:(TLWorkspaceTab *)tab {
  if (!tab) return nil;
  NSString *identity = TLWorkspaceTabIdentity(tab);
  for (TLWorkspaceSplitGroup *group in self.groups) {
    if ([group.leftIdentity isEqual:identity] || [group.rightIdentity isEqual:identity]) return group;
  }
  return nil;
}
- (void)removeGroupForTab:(TLWorkspaceTab *)tab {
  TLWorkspaceSplitGroup *group = [self groupForTab:tab];
  if (!group) return;
  NSMutableArray *groups = self.groups.mutableCopy;
  [groups removeObject:group];
  self.groups = groups;
}
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)onLeft {
  NSString *identity = TLWorkspaceTabIdentity(tab), *otherIdentity = TLWorkspaceTabIdentity(other);
  if ([identity isEqual:otherIdentity]) return;
  TLWorkspaceSplitGroup *previous = [self groupForTab:tab];
  double fraction = previous && previous == [self groupForTab:other] ? previous.fraction : 0.5;
  [self removeGroupForTab:tab];
  [self removeGroupForTab:other];
  TLWorkspaceSplitGroup *group = [TLWorkspaceSplitGroup new];
  group.leftIdentity = onLeft ? identity : otherIdentity;
  group.rightIdentity = onLeft ? otherIdentity : identity;
  group.fraction = fraction;
  self.groups = [self.groups arrayByAddingObject:group];
}
- (void)reconcileTabs:(NSArray<TLWorkspaceTab *> *)tabs {
  NSMutableSet *identities = [NSMutableSet set];
  for (TLWorkspaceTab *tab in tabs) [identities addObject:TLWorkspaceTabIdentity(tab)];
  self.groups = [self.groups filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TLWorkspaceSplitGroup *group, NSDictionary *bindings) {
    return [identities containsObject:group.leftIdentity] && [identities containsObject:group.rightIdentity];
  }]];
}
@end
