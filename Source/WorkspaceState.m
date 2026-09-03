#import "WorkspaceState.h"

@implementation TLWorkspaceTab

+ (instancetype)tabWithKind:(TLWorkspaceTabKind)kind
                      tabID:(NSInteger)tabID
                      title:(NSString *)title
                    toolTip:(NSString *)toolTip
                         URL:(NSURL *)URL
                   closeable:(BOOL)closeable {
  TLWorkspaceTab *tab = [[self alloc] init];
  tab.kind = kind;
  tab.tabID = tabID;
  tab.title = title ?: @"";
  tab.toolTip = toolTip ?: tab.title;
  tab.URL = URL;
  tab.closeable = closeable;
  return tab;
}

- (id)copyWithZone:(NSZone *)zone {
  TLWorkspaceTab *copy = [[[self class] allocWithZone:zone] init];
  copy.kind = self.kind;
  copy.tabID = self.tabID;
  copy.URL = self.URL;
  copy.title = self.title;
  copy.toolTip = self.toolTip;
  copy.closeable = self.closeable;
  return copy;
}

@end
