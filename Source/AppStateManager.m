#import "AppStateManager.h"

TLAppSignalName const TLAppSignalStateChanged = @"state.changed";
TLAppSignalName const TLAppSignalWorkspaceTabActivated = @"workspace.tab.activated";
TLAppSignalName const TLAppSignalWorkspaceTabsChanged = @"workspace.tabs.changed";
TLAppSignalName const TLAppSignalWorkspaceTabAdded = @"workspace.tab.added";
TLAppSignalName const TLAppSignalWorkspaceTabRemoved = @"workspace.tab.removed";
TLAppSignalName const TLAppSignalWorkspaceTabMoved = @"workspace.tab.moved";

static NSUInteger TLIndexOfWorkspaceTabInTabs(TLWorkspaceTabKind kind,
                                              NSInteger tabID,
                                              NSArray<TLWorkspaceTab *> *tabs) {
  for (NSUInteger index = 0; index < tabs.count; index += 1) {
    TLWorkspaceTab *tab = tabs[index];
    if (tab.kind == kind && tab.tabID == tabID) {
      return index;
    }
  }

  return NSNotFound;
}

static TLWorkspaceTab *TLWorkspaceTabInTabs(TLWorkspaceTabKind kind,
                                            NSInteger tabID,
                                            NSArray<TLWorkspaceTab *> *tabs) {
  NSUInteger index = TLIndexOfWorkspaceTabInTabs(kind, tabID, tabs);
  return index == NSNotFound ? nil : tabs[index];
}

static NSArray<TLWorkspaceTab *> *TLCopyWorkspaceTabs(NSArray<TLWorkspaceTab *> *tabs) {
  NSMutableArray<TLWorkspaceTab *> *copies = [NSMutableArray arrayWithCapacity:tabs.count];
  for (TLWorkspaceTab *tab in tabs) {
    [copies addObject:[tab copy]];
  }
  return [copies copy];
}

@interface TLAppSignal ()

@property (nonatomic, copy) TLAppSignalName name;
@property (nonatomic, copy) NSDictionary<NSString *, id> *payload;
@property (nonatomic, assign) NSUInteger sequence;

@end

@implementation TLAppSignal

+ (instancetype)signalWithName:(TLAppSignalName)name
                       payload:(NSDictionary<NSString *, id> *)payload
                      sequence:(NSUInteger)sequence {
  TLAppSignal *signal = [[self alloc] init];
  signal.name = name.length > 0 ? name : TLAppSignalStateChanged;
  signal.payload = payload ?: @{};
  signal.sequence = sequence;
  return signal;
}

- (id)copyWithZone:(NSZone *)zone {
  TLAppSignal *copy = [[[self class] allocWithZone:zone] init];
  copy.name = self.name;
  copy.payload = self.payload;
  copy.sequence = self.sequence;
  return copy;
}

@end

@interface TLMutableAppState ()

- (instancetype)initWithSnapshot:(TLAppStateSnapshot *)snapshot;

@end

@implementation TLMutableAppState

- (instancetype)initWithSnapshot:(TLAppStateSnapshot *)snapshot {
  self = [super init];
  if (self) {
    _activeTabKind = snapshot.activeTabKind;
    _activeTabID = snapshot.activeTabID;
    _workspaceTabs = [TLCopyWorkspaceTabs(snapshot.workspaceTabs) mutableCopy];
  }
  return self;
}

@end

@interface TLAppStateSnapshot ()

@property (nonatomic, assign) TLWorkspaceTabKind activeTabKind;
@property (nonatomic, assign) NSInteger activeTabID;
@property (nonatomic, copy) NSArray<TLWorkspaceTab *> *workspaceTabs;
@property (nonatomic, assign) NSUInteger revision;
@property (nonatomic, strong, nullable) TLAppSignal *lastSignal;

+ (instancetype)snapshotWithDraft:(TLMutableAppState *)draft
                         revision:(NSUInteger)revision
                       lastSignal:(TLAppSignal *)lastSignal;

@end

@implementation TLAppStateSnapshot

+ (instancetype)snapshotWithDraft:(TLMutableAppState *)draft
                         revision:(NSUInteger)revision
                       lastSignal:(TLAppSignal *)lastSignal {
  TLAppStateSnapshot *snapshot = [[self alloc] init];
  snapshot.activeTabKind = draft.activeTabKind;
  snapshot.activeTabID = draft.activeTabID;
  snapshot.workspaceTabs = TLCopyWorkspaceTabs(draft.workspaceTabs);
  snapshot.revision = revision;
  snapshot.lastSignal = lastSignal;
  return snapshot;
}

- (id)copyWithZone:(NSZone *)zone {
  TLAppStateSnapshot *copy = [[[self class] allocWithZone:zone] init];
  copy.activeTabKind = self.activeTabKind;
  copy.activeTabID = self.activeTabID;
  copy.workspaceTabs = self.workspaceTabs;
  copy.revision = self.revision;
  copy.lastSignal = self.lastSignal;
  return copy;
}

@end

@interface TLAppStateSubscription ()

@property (nonatomic, weak, nullable) TLAppStateManager *store;
@property (nonatomic, assign) NSUInteger token;
@property (nonatomic, assign, getter=isCancelled) BOOL cancelled;

- (instancetype)initWithStore:(TLAppStateManager *)store token:(NSUInteger)token;

@end

@interface TLAppStateObserver : NSObject

@property (nonatomic, copy, nullable) TLAppStateSelector selector;
@property (nonatomic, copy, nullable) TLAppStateChangeHandler changeHandler;
@property (nonatomic, copy, nullable) TLAppSignalName signalName;
@property (nonatomic, copy, nullable) TLAppSignalHandler signalHandler;
@property (nonatomic, strong, nullable) id selectedValue;

@end

@implementation TLAppStateObserver
@end

@interface TLAppStateManager ()

@property (nonatomic, copy) TLAppStateSnapshot *snapshot;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TLAppStateObserver *> *observers;
@property (nonatomic, assign) NSUInteger nextObserverToken;
@property (nonatomic, assign) NSUInteger nextSignalSequence;

- (void)removeObserverWithToken:(NSUInteger)token;

@end

@implementation TLAppStateSubscription

- (instancetype)initWithStore:(TLAppStateManager *)store token:(NSUInteger)token {
  self = [super init];
  if (self) {
    _store = store;
    _token = token;
  }
  return self;
}

- (void)dealloc {
  [self cancel];
}

- (void)cancel {
  if (self.cancelled) {
    return;
  }

  self.cancelled = YES;
  [self.store removeObserverWithToken:self.token];
}

@end

@implementation TLAppStateManager

- (instancetype)init {
  self = [super init];
  if (self) {
    _observers = [NSMutableDictionary dictionary];
    _nextObserverToken = 1;
    _nextSignalSequence = 1;

    TLMutableAppState *initialState = [[TLMutableAppState alloc] init];
    initialState.activeTabKind = TLWorkspaceTabKindChat;
    initialState.activeTabID = 0;
    initialState.workspaceTabs = [NSMutableArray array];
    TLAppSignal *initialSignal = [TLAppSignal signalWithName:TLAppSignalStateChanged
                                                     payload:@{}
                                                    sequence:0];
    _snapshot = [TLAppStateSnapshot snapshotWithDraft:initialState
                                            revision:0
                                          lastSignal:initialSignal];
  }
  return self;
}

- (TLAppStateSubscription *)subscribeWithSelector:(TLAppStateSelector)selector
                               notifyImmediately:(BOOL)notifyImmediately
                                         handler:(TLAppStateChangeHandler)handler {
  NSParameterAssert(selector);
  NSParameterAssert(handler);

  TLAppStateObserver *observer = [[TLAppStateObserver alloc] init];
  observer.selector = selector;
  observer.changeHandler = handler;
  observer.selectedValue = selector(self.snapshot);

  NSUInteger token = [self addObserver:observer];
  if (notifyImmediately) {
    handler(observer.selectedValue, self.snapshot, self.snapshot.lastSignal);
  }

  return [[TLAppStateSubscription alloc] initWithStore:self token:token];
}

- (TLAppStateSubscription *)subscribeToSignal:(TLAppSignalName)signalName
                                      handler:(TLAppSignalHandler)handler {
  NSParameterAssert(signalName);
  NSParameterAssert(handler);

  TLAppStateObserver *observer = [[TLAppStateObserver alloc] init];
  observer.signalName = signalName;
  observer.signalHandler = handler;
  NSUInteger token = [self addObserver:observer];
  return [[TLAppStateSubscription alloc] initWithStore:self token:token];
}

- (TLAppStateSnapshot *)setState:(TLAppStateMutation)mutation
                          signal:(TLAppSignalName)signalName
                         payload:(NSDictionary<NSString *, id> *)payload {
  NSParameterAssert(mutation);

  TLMutableAppState *draft = [[TLMutableAppState alloc] initWithSnapshot:self.snapshot];
  mutation(draft);
  TLAppSignal *signal = [self nextSignalWithName:signalName payload:payload];
  self.snapshot = [TLAppStateSnapshot snapshotWithDraft:draft
                                              revision:self.snapshot.revision + 1
                                            lastSignal:signal];
  [self notifyObserversWithSignal:signal];
  return self.snapshot;
}

- (TLAppStateSnapshot *)sendSignal:(TLAppSignalName)signalName
                           payload:(NSDictionary<NSString *, id> *)payload {
  TLMutableAppState *draft = [[TLMutableAppState alloc] initWithSnapshot:self.snapshot];
  TLAppSignal *signal = [self nextSignalWithName:signalName payload:payload];
  self.snapshot = [TLAppStateSnapshot snapshotWithDraft:draft
                                              revision:self.snapshot.revision + 1
                                            lastSignal:signal];
  [self notifyObserversWithSignal:signal];
  return self.snapshot;
}

- (void)activateWorkspaceTabKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  if (self.snapshot.activeTabKind == kind && self.snapshot.activeTabID == tabID) {
    return;
  }

  [self setState:^(TLMutableAppState *draft) {
    draft.activeTabKind = kind;
    draft.activeTabID = tabID;
  } signal:TLAppSignalWorkspaceTabActivated payload:@{
    @"kind": @(kind),
    @"tabID": @(tabID),
  }];
}

- (TLWorkspaceTab *)workspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  return [[self workspaceTabWithKind:kind tabID:tabID inTabs:self.snapshot.workspaceTabs] copy];
}

- (BOOL)hasWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  return [self workspaceTabWithKind:kind tabID:tabID] != nil;
}

- (void)addWorkspaceTab:(TLWorkspaceTab *)tab activate:(BOOL)activate {
  if (!tab) {
    return;
  }
  TLWorkspaceTab *storedTab = [tab copy];

  [self setState:^(TLMutableAppState *draft) {
    if (TLWorkspaceTabInTabs(storedTab.kind, storedTab.tabID, draft.workspaceTabs)) {
      return;
    }
    [draft.workspaceTabs addObject:storedTab];
    if (activate) {
      draft.activeTabKind = storedTab.kind;
      draft.activeTabID = storedTab.tabID;
    }
  } signal:TLAppSignalWorkspaceTabAdded payload:[self payloadForTab:storedTab extra:nil]];
}

- (void)upsertWorkspaceTab:(TLWorkspaceTab *)tab activate:(BOOL)activate {
  if (!tab) {
    return;
  }
  TLWorkspaceTab *storedTab = [tab copy];

  [self setState:^(TLMutableAppState *draft) {
    NSUInteger index = TLIndexOfWorkspaceTabInTabs(storedTab.kind, storedTab.tabID, draft.workspaceTabs);
    if (index == NSNotFound) {
      [draft.workspaceTabs addObject:storedTab];
    } else {
      draft.workspaceTabs[index] = storedTab;
    }
    if (activate) {
      draft.activeTabKind = storedTab.kind;
      draft.activeTabID = storedTab.tabID;
    }
  } signal:TLAppSignalWorkspaceTabsChanged payload:[self payloadForTab:storedTab extra:nil]];
}

- (void)replaceWorkspaceTabWithKind:(TLWorkspaceTabKind)kind
                               tabID:(NSInteger)tabID
                             withTab:(TLWorkspaceTab *)replacementTab
                            activate:(BOOL)activate {
  if (!replacementTab) {
    return;
  }
  TLWorkspaceTab *storedReplacementTab = [replacementTab copy];

  TLWorkspaceTab *previousTab = [self workspaceTabWithKind:kind tabID:tabID];
  if (!previousTab) {
    [self upsertWorkspaceTab:storedReplacementTab activate:activate];
    return;
  }

  [self setState:^(TLMutableAppState *draft) {
    NSUInteger index = TLIndexOfWorkspaceTabInTabs(kind, tabID, draft.workspaceTabs);
    if (index == NSNotFound) {
      [draft.workspaceTabs addObject:storedReplacementTab];
    } else {
      draft.workspaceTabs[index] = storedReplacementTab;
    }

    if (draft.activeTabKind == kind && draft.activeTabID == tabID) {
      draft.activeTabKind = storedReplacementTab.kind;
      draft.activeTabID = storedReplacementTab.tabID;
    }
    if (activate) {
      draft.activeTabKind = storedReplacementTab.kind;
      draft.activeTabID = storedReplacementTab.tabID;
    }
  } signal:TLAppSignalWorkspaceTabsChanged payload:[self payloadForTab:storedReplacementTab extra:@{
    @"replacedKind": @(kind),
    @"replacedTabID": @(tabID),
  }]];
}

- (void)removeWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  TLWorkspaceTab *tab = [self workspaceTabWithKind:kind tabID:tabID];
  if (!tab) {
    return;
  }

  [self setState:^(TLMutableAppState *draft) {
    NSUInteger index = TLIndexOfWorkspaceTabInTabs(kind, tabID, draft.workspaceTabs);
    if (index != NSNotFound) {
      [draft.workspaceTabs removeObjectAtIndex:index];
    }
  } signal:TLAppSignalWorkspaceTabRemoved payload:[self payloadForTab:tab extra:nil]];
}

- (void)moveWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID toIndex:(NSUInteger)targetIndex {
  TLWorkspaceTab *tab = [self workspaceTabWithKind:kind tabID:tabID];
  if (!tab) {
    return;
  }

  NSUInteger sourceIndex = [self indexOfWorkspaceTabWithKind:kind tabID:tabID inTabs:self.snapshot.workspaceTabs];
  if (sourceIndex == NSNotFound) {
    return;
  }

  NSUInteger boundedTargetIndex = MIN(targetIndex, self.snapshot.workspaceTabs.count - 1);
  if (sourceIndex == boundedTargetIndex) {
    return;
  }

  [self setState:^(TLMutableAppState *draft) {
    NSUInteger currentIndex = TLIndexOfWorkspaceTabInTabs(kind, tabID, draft.workspaceTabs);
    if (currentIndex == NSNotFound) {
      return;
    }

    TLWorkspaceTab *movingTab = draft.workspaceTabs[currentIndex];
    [draft.workspaceTabs removeObjectAtIndex:currentIndex];
    NSUInteger insertIndex = MIN(targetIndex, draft.workspaceTabs.count);
    [draft.workspaceTabs insertObject:movingTab atIndex:insertIndex];
  } signal:TLAppSignalWorkspaceTabMoved payload:[self payloadForTab:tab extra:@{
    @"fromIndex": @(sourceIndex),
    @"toIndex": @(boundedTargetIndex),
  }]];
}

- (NSUInteger)addObserver:(TLAppStateObserver *)observer {
  NSUInteger token = self.nextObserverToken;
  self.nextObserverToken += 1;
  self.observers[@(token)] = observer;
  return token;
}

- (void)removeObserverWithToken:(NSUInteger)token {
  [self.observers removeObjectForKey:@(token)];
}

- (TLAppSignal *)nextSignalWithName:(TLAppSignalName)name payload:(NSDictionary<NSString *, id> *)payload {
  TLAppSignal *signal = [TLAppSignal signalWithName:name payload:payload sequence:self.nextSignalSequence];
  self.nextSignalSequence += 1;
  return signal;
}

- (void)notifyObserversWithSignal:(TLAppSignal *)signal {
  NSArray<TLAppStateObserver *> *observers = self.observers.allValues;
  for (TLAppStateObserver *observer in observers) {
    if (observer.signalHandler && [observer.signalName isEqualToString:signal.name]) {
      observer.signalHandler(signal, self.snapshot);
    }

    if (!observer.selector || !observer.changeHandler) {
      continue;
    }

    id nextValue = observer.selector(self.snapshot);
    BOOL changed = observer.selectedValue != nextValue && ![observer.selectedValue isEqual:nextValue];
    if (!changed) {
      continue;
    }

    observer.selectedValue = nextValue;
    observer.changeHandler(nextValue, self.snapshot, signal);
  }
}

- (TLWorkspaceTab *)workspaceTabWithKind:(TLWorkspaceTabKind)kind
                                   tabID:(NSInteger)tabID
                                  inTabs:(NSArray<TLWorkspaceTab *> *)tabs {
  return TLWorkspaceTabInTabs(kind, tabID, tabs);
}

- (NSUInteger)indexOfWorkspaceTabWithKind:(TLWorkspaceTabKind)kind
                                    tabID:(NSInteger)tabID
                                   inTabs:(NSArray<TLWorkspaceTab *> *)tabs {
  return TLIndexOfWorkspaceTabInTabs(kind, tabID, tabs);
}

- (NSDictionary<NSString *, id> *)payloadForTab:(TLWorkspaceTab *)tab
                                          extra:(NSDictionary<NSString *, id> *)extra {
  NSMutableDictionary<NSString *, id> *payload = [@{
    @"kind": @(tab.kind),
    @"tabID": @(tab.tabID),
  } mutableCopy];
  if (extra) {
    [payload addEntriesFromDictionary:extra];
  }
  return payload;
}

@end
