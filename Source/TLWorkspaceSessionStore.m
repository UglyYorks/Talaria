#import "TLWorkspaceSessionStore.h"

static BOOL TLSessionInteger(id value) {
  return [value isKindOfClass:NSNumber.class] &&
    [value doubleValue] > (double)NSIntegerMin && [value doubleValue] < (double)NSIntegerMax &&
    [value doubleValue] == (double)[value integerValue];
}

static BOOL TLSessionTabKind(id value) {
  if (!TLSessionInteger(value)) return NO;
  switch ([value integerValue]) {
    case TLWorkspaceTabKindChat:
    case TLWorkspaceTabKindHistory:
    case TLWorkspaceTabKindBrowser:
    case TLWorkspaceTabKindSettings:
    case TLWorkspaceTabKindAgents:
    case TLWorkspaceTabKindDebug:
    case TLWorkspaceTabKindDownloads:
    case TLWorkspaceTabKindAutomations:
      return YES;
    default:
      return NO;
  }
}

@interface TLWorkspaceSessionStore ()
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) TLAppStateSubscription *subscription;
@end

@implementation TLWorkspaceSessionStore

- (instancetype)initWithURL:(NSURL *)URL {
  if ((self = [super init])) _URL = URL;
  return self;
}

- (void)restoreStateManager:(TLAppStateManager *)stateManager {
  NSData *data = [NSData dataWithContentsOfURL:self.URL];
  id session = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![session isKindOfClass:NSDictionary.class] || ![session[@"version"] isEqual:@1] ||
      ![session[@"tabs"] isKindOfClass:NSArray.class]) return;

  NSMutableArray<TLWorkspaceTab *> *tabs = [NSMutableArray array];
  NSMutableSet<NSString *> *identities = [NSMutableSet set];
  for (id entry in session[@"tabs"]) {
    if (![entry isKindOfClass:NSDictionary.class] || !TLSessionTabKind(entry[@"kind"]) ||
        !TLSessionInteger(entry[@"tabID"])) continue;
    TLWorkspaceTabKind kind = [entry[@"kind"] integerValue];
    NSInteger tabID = [entry[@"tabID"] integerValue];
    if (kind == TLWorkspaceTabKindBrowser && tabID <= 0) continue;
    if (kind != TLWorkspaceTabKindChat && kind != TLWorkspaceTabKindBrowser && tabID != 0) continue;
    NSString *identity = [NSString stringWithFormat:@"%ld:%ld", (long)kind, (long)tabID];
    if ([identities containsObject:identity]) continue;
    NSURL *URL = [entry[@"url"] isKindOfClass:NSString.class] ? [NSURL URLWithString:entry[@"url"]] : nil;
    if (kind == TLWorkspaceTabKindBrowser &&
        (!URL.host.length || ![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString])) continue;
    NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
    NSString *toolTip = [entry[@"toolTip"] isKindOfClass:NSString.class] ? entry[@"toolTip"] : title;
    TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:kind tabID:tabID title:title toolTip:toolTip
      URL:kind == TLWorkspaceTabKindBrowser ? URL : nil closeable:YES];
    tab.pinned = [entry[@"pinned"] isKindOfClass:NSNumber.class] && [entry[@"pinned"] boolValue];
    [tabs addObject:tab];
    [identities addObject:identity];
  }

  TLWorkspaceTab *active = tabs.firstObject;
  if (TLSessionTabKind(session[@"activeKind"]) && TLSessionInteger(session[@"activeID"])) {
    for (TLWorkspaceTab *tab in tabs) {
      if (tab.kind == [session[@"activeKind"] integerValue] && tab.tabID == [session[@"activeID"] integerValue]) {
        active = tab;
        break;
      }
    }
  }
  [stateManager setState:^(TLMutableAppState *draft) {
    draft.workspaceTabs = tabs;
    draft.activeTabKind = active ? active.kind : TLWorkspaceTabKindChat;
    draft.activeTabID = active ? active.tabID : 0;
  } signal:TLAppSignalWorkspaceTabsChanged payload:nil];
}

- (void)observeStateManager:(TLAppStateManager *)stateManager {
  [self.subscription cancel];
  __weak typeof(self) weakSelf = self;
  self.subscription = [stateManager subscribeWithSelector:^id(TLAppStateSnapshot *snapshot) {
    NSMutableArray *tabs = [NSMutableArray array];
    for (TLWorkspaceTab *tab in snapshot.workspaceTabs) {
      NSMutableDictionary *entry = [@{@"kind":@(tab.kind), @"tabID":@(tab.tabID),
        @"title":tab.title ?: @"", @"toolTip":tab.toolTip ?: @"", @"pinned":@(tab.pinned)} mutableCopy];
      if (tab.URL) entry[@"url"] = tab.URL.absoluteString;
      [tabs addObject:entry];
    }
    return @{@"version":@1, @"tabs":tabs, @"activeKind":@(snapshot.activeTabKind), @"activeID":@(snapshot.activeTabID)};
  } notifyImmediately:YES handler:^(id session, TLAppStateSnapshot *snapshot, TLAppSignal *signal) {
    TLWorkspaceSessionStore *store = weakSelf;
    if (!store) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:session options:0 error:&error];
    // Save each completed state change atomically, including selection-only changes.
    // Closing the window or quitting therefore cannot leave an older tab selection.
    if (!data || ![NSFileManager.defaultManager createDirectoryAtURL:store.URL.URLByDeletingLastPathComponent
      withIntermediateDirectories:YES attributes:nil error:&error] ||
      ![data writeToURL:store.URL options:NSDataWritingAtomic error:&error]) {
      NSLog(@"Could not save workspace session: %@", error.localizedDescription);
    }
  }];
}

@end
