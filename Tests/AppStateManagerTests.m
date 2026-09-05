#import <Foundation/Foundation.h>
#import "AppStateManager.h"

static void TLAssert(BOOL condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

static TLAppStateManager *TLMixedWorkspace(NSUInteger activeIndex) {
  TLAppStateManager *manager = [[TLAppStateManager alloc] init];
  NSArray<NSNumber *> *kinds = @[@(TLWorkspaceTabKindChat), @(TLWorkspaceTabKindBrowser), @(TLWorkspaceTabKindSettings)];
  for (NSUInteger index = 0; index < kinds.count; index++) {
    // Matching IDs exercise identity by both kind and ID.
    TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:kinds[index].integerValue tabID:7
      title:@"Test tab" toolTip:nil URL:nil closeable:YES];
    [manager addWorkspaceTab:tab activate:index == activeIndex];
  }
  return manager;
}

static BOOL TLHasValidSelection(TLAppStateSnapshot *snapshot) {
  if (snapshot.workspaceTabs.count == 0) {
    return snapshot.activeTabKind == TLWorkspaceTabKindChat && snapshot.activeTabID == 0;
  }
  for (TLWorkspaceTab *tab in snapshot.workspaceTabs) {
    if (snapshot.activeTabKind == tab.kind && snapshot.activeTabID == tab.tabID) {
      return YES;
    }
  }
  return NO;
}

static void TLAssertClose(TLAppStateManager *manager, TLWorkspaceTabKind closingKind,
                          TLWorkspaceTabKind fallbackKind, NSInteger fallbackID) {
  NSUInteger revision = manager.snapshot.revision;
  NSUInteger initialCount = manager.snapshot.workspaceTabs.count;
  __block NSUInteger stateNotifications = 0;
  __block NSUInteger removalNotifications = 0;
  __block NSUInteger activationNotifications = 0;
  TLAppStateSubscription *state = [manager subscribeWithSelector:^id(TLAppStateSnapshot *snapshot) {
    return @(snapshot.revision);
  } notifyImmediately:NO handler:^(id selected, TLAppStateSnapshot *snapshot, TLAppSignal *signal) {
    stateNotifications++;
    TLAssert([selected unsignedIntegerValue] == snapshot.revision, @"selector and handler observe the same revision");
    TLAssert(snapshot.revision == revision + 1, @"close publishes exactly one new revision");
    TLAssert(snapshot.workspaceTabs.count == initialCount - 1, @"close notification includes updated tab collection");
    TLAssert(TLHasValidSelection(snapshot), @"no observer sees the removed tab selected");
    TLAssert(snapshot.activeTabKind == fallbackKind && snapshot.activeTabID == fallbackID,
      @"fallback selection is part of the removal notification");
    TLAssert([signal.name isEqualToString:TLAppSignalWorkspaceTabRemoved], @"atomic close uses the removal signal");
    TLAssert([signal.payload[@"kind"] integerValue] == closingKind && [signal.payload[@"tabID"] integerValue] == 7,
      @"removal signal identifies the exact closed tab");
    TLAssert(snapshot.lastSignal.sequence == signal.sequence, @"signal matches its snapshot");
  }];
  TLAppStateSubscription *removal = [manager subscribeToSignal:TLAppSignalWorkspaceTabRemoved
    handler:^(TLAppSignal *signal, TLAppStateSnapshot *snapshot) {
      removalNotifications++;
      TLAssert(TLHasValidSelection(snapshot), @"signal subscribers receive a valid selection");
    }];
  TLAppStateSubscription *activation = [manager subscribeToSignal:TLAppSignalWorkspaceTabActivated
    handler:^(TLAppSignal *signal, TLAppStateSnapshot *snapshot) { activationNotifications++; }];

  [manager removeWorkspaceTabWithKind:closingKind tabID:7];
  TLAssert(stateNotifications == 1 && removalNotifications == 1 && activationNotifications == 0,
    @"close emits one state/removal notification without a separate activation");
  TLAssert(manager.snapshot.revision == revision + 1, @"close commits one state revision");
  TLAssert(![manager hasWorkspaceTabWithKind:closingKind tabID:7], @"closed tab is absent");
  [state cancel];
  [removal cancel];
  [activation cancel];
}

static void TestActiveTabFallback(void) {
  TLAppStateManager *first = TLMixedWorkspace(0);
  TLAssertClose(first, TLWorkspaceTabKindChat, TLWorkspaceTabKindBrowser, 7);
  TLAssert(first.snapshot.workspaceTabs.firstObject.kind == TLWorkspaceTabKindBrowser,
    @"closing first tab selects the immediate right neighbor across tab kinds");

  TLAppStateManager *middle = TLMixedWorkspace(1);
  TLAssertClose(middle, TLWorkspaceTabKindBrowser, TLWorkspaceTabKindSettings, 7);
  TLAssert(middle.snapshot.workspaceTabs.firstObject.kind == TLWorkspaceTabKindChat,
    @"middle closure preserves tabs to its left");

  TLAppStateManager *last = TLMixedWorkspace(2);
  TLAssertClose(last, TLWorkspaceTabKindSettings, TLWorkspaceTabKindBrowser, 7);
  TLAssert(last.snapshot.workspaceTabs.lastObject.kind == TLWorkspaceTabKindBrowser,
    @"closing last tab selects its immediate left neighbor");
}

static void TestInactiveAndFinalTabClosure(void) {
  TLAppStateManager *manager = TLMixedWorkspace(1);
  TLAssertClose(manager, TLWorkspaceTabKindChat, TLWorkspaceTabKindBrowser, 7);
  TLAssertClose(manager, TLWorkspaceTabKindSettings, TLWorkspaceTabKindBrowser, 7);
  TLAssertClose(manager, TLWorkspaceTabKindBrowser, TLWorkspaceTabKindChat, 0);
  TLAssert(manager.snapshot.workspaceTabs.count == 0, @"closing the sole tab empties the workspace");

  NSUInteger revision = manager.snapshot.revision;
  __block NSUInteger notifications = 0;
  TLAppStateSubscription *subscription = [manager subscribeWithSelector:^id(TLAppStateSnapshot *snapshot) {
    return @(snapshot.revision);
  } notifyImmediately:NO handler:^(id value, TLAppStateSnapshot *snapshot, TLAppSignal *signal) { notifications++; }];
  [manager removeWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:7];
  TLAssert(manager.snapshot.revision == revision && notifications == 0,
    @"closing an already removed tab makes no state change");
  [subscription cancel];
}

static void TestReentrantNotificationOrdering(void) {
  TLAppStateManager *manager = TLMixedWorkspace(0);
  NSUInteger initialRevision = manager.snapshot.revision;
  NSMutableArray<TLAppStateSubscription *> *subscriptions = [NSMutableArray array];
  NSMutableArray<NSNumber *> *deliveryOrder = [NSMutableArray array];
  NSMutableArray<NSMutableArray<NSNumber *> *> *revisionsByObserver = [NSMutableArray array];
  __block BOOL queuedSecondClose = NO;
  __block TLAppStateSnapshot *firstDeliveredSnapshot = nil;

  void (^observe)(NSUInteger, TLAppSignal *, TLAppStateSnapshot *) =
    ^(NSUInteger observerIndex, TLAppSignal *signal, TLAppStateSnapshot *snapshot) {
      [revisionsByObserver[observerIndex] addObject:@(snapshot.revision)];
      [deliveryOrder addObject:@(snapshot.revision)];
      TLAssert(snapshot.revision == initialRevision + 1 || snapshot.revision == initialRevision + 2,
        @"reentrant close delivers the expected revisions");
      TLAssert(snapshot.lastSignal.sequence == signal.sequence &&
        [snapshot.lastSignal.payload isEqualToDictionary:signal.payload], @"reentrant delivery keeps signal and snapshot paired");
      TLAssert(TLHasValidSelection(snapshot), @"reentrant delivery never exposes an invalid active tab");
      if (snapshot.revision == initialRevision + 1) {
        TLAssert(snapshot.workspaceTabs.count == 2 && snapshot.activeTabKind == TLWorkspaceTabKindBrowser,
          @"all observers of first close see browser fallback even after another mutation");
        TLAssert([signal.payload[@"kind"] integerValue] == TLWorkspaceTabKindChat,
          @"first revision carries the first closed tab identity");
        if (!firstDeliveredSnapshot) { firstDeliveredSnapshot = snapshot; }
      } else {
        TLAssert(snapshot.workspaceTabs.count == 1 && snapshot.activeTabKind == TLWorkspaceTabKindSettings,
          @"all observers of second close see settings fallback");
        TLAssert([signal.payload[@"kind"] integerValue] == TLWorkspaceTabKindBrowser,
          @"second revision carries the second closed tab identity");
      }
      if (!queuedSecondClose) {
        queuedSecondClose = YES;
        [manager removeWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:7];
      }
    };

  // Either kind of observer may be delivered first; both may trigger reentrancy.
  for (NSUInteger index = 0; index < 4; index++) {
    [revisionsByObserver addObject:[NSMutableArray array]];
    TLAppStateSubscription *subscription;
    if (index % 2 == 0) {
      subscription = [manager subscribeToSignal:TLAppSignalWorkspaceTabRemoved
        handler:^(TLAppSignal *signal, TLAppStateSnapshot *snapshot) { observe(index, signal, snapshot); }];
    } else {
      subscription = [manager subscribeWithSelector:^id(TLAppStateSnapshot *snapshot) {
        return @[@(snapshot.revision), @(snapshot.activeTabKind), @(snapshot.workspaceTabs.count)];
      } notifyImmediately:NO handler:^(id selected, TLAppStateSnapshot *snapshot, TLAppSignal *signal) {
        NSArray *expected = @[@(snapshot.revision), @(snapshot.activeTabKind), @(snapshot.workspaceTabs.count)];
        TLAssert([selected isEqual:expected], @"reentrant selector result matches its delivered snapshot");
        observe(index, signal, snapshot);
      }];
    }
    [subscriptions addObject:subscription];
  }

  [manager removeWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:7];
  NSArray<NSNumber *> *expectedRevisions = @[@(initialRevision + 1), @(initialRevision + 2)];
  for (NSArray *revisions in revisionsByObserver) {
    TLAssert([revisions isEqual:expectedRevisions], @"every subscriber receives both revisions exactly once and in order");
  }
  TLAssert(deliveryOrder.count == 8, @"each close notifies all four observers once");
  for (NSUInteger index = 0; index < deliveryOrder.count; index++) {
    TLAssert(deliveryOrder[index].unsignedIntegerValue == initialRevision + (index < 4 ? 1 : 2),
      @"first revision reaches every subscriber before the queued revision begins");
  }
  TLAssert(firstDeliveredSnapshot.workspaceTabs.count == 2 && firstDeliveredSnapshot.activeTabKind == TLWorkspaceTabKindBrowser,
    @"later mutations do not modify a retained earlier snapshot");
  TLAssert(manager.snapshot.revision == initialRevision + 2 && manager.snapshot.activeTabKind == TLWorkspaceTabKindSettings,
    @"reentrant closes finish in the expected final state");
  for (TLAppStateSubscription *subscription in subscriptions) { [subscription cancel]; }
}

int main(void) {
  @autoreleasepool {
    TestActiveTabFallback();
    TestInactiveAndFinalTabClosure();
    TestReentrantNotificationOrdering();
    NSLog(@"AppStateManagerTests passed");
  }
  return 0;
}
