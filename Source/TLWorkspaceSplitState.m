#import "TLWorkspaceSplitState.h"

NSString *TLWorkspaceTabIdentity(TLWorkspaceTab *tab) {
  return tab.presentationIdentity ?: [NSString stringWithFormat:@"%ld:%ld", (long)tab.kind, (long)tab.tabID];
}
@implementation TLWorkspaceSplitGroup
- (instancetype)init { if ((self = [super init])) { _columns = @[]; _fraction = 0.5; } return self; }
- (NSArray<NSString *> *)identities {
  NSMutableArray *result = [NSMutableArray new];
  for (NSArray *column in self.columns) [result addObjectsFromArray:column];
  return result;
}
- (NSString *)leftIdentity { return self.identities.firstObject; }
- (NSString *)rightIdentity { return self.identities.count > 1 ? self.identities[1] : nil; }
@end

@interface TLWorkspaceSplitState ()
@property (nonatomic, copy, readwrite) NSArray<TLWorkspaceSplitGroup *> *groups;
@end
@implementation TLWorkspaceSplitState
- (instancetype)init { if ((self = [super init])) _groups = @[]; return self; }
- (TLWorkspaceSplitGroup *)groupForTab:(TLWorkspaceTab *)tab {
  if (!tab) return nil;
  for (TLWorkspaceSplitGroup *group in self.groups)
    if ([group.identities containsObject:TLWorkspaceTabIdentity(tab)]) return group;
  return nil;
}
- (void)removeGroupForTab:(TLWorkspaceTab *)tab {
  TLWorkspaceSplitGroup *group = [self groupForTab:tab];
  if (!group) return;
  NSMutableArray *groups = self.groups.mutableCopy; [groups removeObject:group]; self.groups = groups;
}
- (NSArray *)columnsOfGroup:(TLWorkspaceSplitGroup *)group excluding:(NSString *)identity {
  NSMutableArray *columns = [NSMutableArray new];
  for (NSArray *column in group.columns) {
    NSMutableArray *remaining = column.mutableCopy; [remaining removeObject:identity];
    if (remaining.count) [columns addObject:remaining];
  }
  return columns;
}
- (void)detachTab:(TLWorkspaceTab *)tab {
  TLWorkspaceSplitGroup *group = [self groupForTab:tab];
  if (!group) return;
  NSArray *columns = [self columnsOfGroup:group excluding:TLWorkspaceTabIdentity(tab)];
  if (group.identities.count <= 2) [self removeGroupForTab:tab];
  else group.columns = columns;
}
- (NSString *)availableNeighborForTab:(TLWorkspaceTab *)tab placement:(TLSplitPlacement *)placement {
  if (!tab) return nil;
  TLWorkspaceSplitGroup *group = [self groupForTab:tab];
  NSArray<NSArray<NSString *> *> *columns = group ? group.columns : @[@[TLWorkspaceTabIdentity(tab)]];
  // Fill holes in existing columns before starting another column.
  for (NSArray<NSString *> *column in columns) {
    if (column.count < 3) {
      if (placement) *placement = TLSplitPlacementBelow;
      return column.lastObject;
    }
  }
  if (columns.count < 3) {
    if (placement) *placement = TLSplitPlacementRight;
    return columns.lastObject.lastObject;
  }
  return nil;
}
- (NSArray<NSArray<NSString *> *> *)columnsBySplittingTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement {
  if (!tab || !other || [TLWorkspaceTabIdentity(tab) isEqual:TLWorkspaceTabIdentity(other)]) return nil;
  TLWorkspaceSplitGroup *group = [self groupForTab:other];
  NSArray *remaining = [self columnsOfGroup:group excluding:TLWorkspaceTabIdentity(tab)];
  NSMutableArray *columns = (remaining.count ? remaining : @[@[TLWorkspaceTabIdentity(other)]]).mutableCopy;
  NSUInteger columnIndex = [columns indexOfObjectPassingTest:^BOOL(NSArray *column, NSUInteger i, BOOL *stop) {
    return [column containsObject:TLWorkspaceTabIdentity(other)];
  }];
  if (columnIndex == NSNotFound) return nil;
  NSString *identity = TLWorkspaceTabIdentity(tab);
  if (placement == TLSplitPlacementLeft || placement == TLSplitPlacementRight) {
    if (columns.count >= 3) return nil;
    [columns insertObject:@[identity] atIndex:columnIndex + (placement == TLSplitPlacementRight)];
  } else {
    NSMutableArray *column = [columns[columnIndex] mutableCopy];
    if (column.count >= 3) return nil;
    [column insertObject:identity atIndex:[column indexOfObject:TLWorkspaceTabIdentity(other)] + (placement == TLSplitPlacementBelow)];
    columns[columnIndex] = column;
  }
  // A destination must change the layout, not reinsert the pane where it was.
  return [columns isEqual:group.columns] ? nil : columns;
}
- (BOOL)canSplitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement {
  return [self columnsBySplittingTab:tab besideTab:other placement:placement] != nil;
}
- (BOOL)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement {
  NSArray *columns = [self columnsBySplittingTab:tab besideTab:other placement:placement];
  if (!columns) return NO;
  TLWorkspaceSplitGroup *group = [self groupForTab:other];
  [self detachTab:tab];
  if (!group) group = [TLWorkspaceSplitGroup new];
  group.columns = columns;
  if (![self.groups containsObject:group]) self.groups = [self.groups arrayByAddingObject:group];
  return YES;
}
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)onLeft {
  [self splitTab:tab besideTab:other placement:onLeft ? TLSplitPlacementLeft : TLSplitPlacementRight];
}
- (void)reconcileTabs:(NSArray<TLWorkspaceTab *> *)tabs {
  NSMutableSet *identities = [NSMutableSet set];
  for (TLWorkspaceTab *tab in tabs) [identities addObject:TLWorkspaceTabIdentity(tab)];
  NSMutableArray *groups = [NSMutableArray new];
  for (TLWorkspaceSplitGroup *group in self.groups) {
    NSMutableArray *columns = [NSMutableArray new];
    for (NSArray *column in group.columns) {
      NSArray *live = [column filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *identity, NSDictionary *bindings) {
        return [identities containsObject:identity];
      }]];
      if (live.count) [columns addObject:live];
    }
    group.columns = columns;
    if (group.identities.count > 1) [groups addObject:group];
  }
  self.groups = groups;
}
@end
