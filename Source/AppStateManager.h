#import <Foundation/Foundation.h>
#import "WorkspaceState.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSString *TLAppSignalName NS_TYPED_EXTENSIBLE_ENUM;

extern TLAppSignalName const TLAppSignalStateChanged;
extern TLAppSignalName const TLAppSignalWorkspaceTabActivated;
extern TLAppSignalName const TLAppSignalWorkspaceTabsChanged;
extern TLAppSignalName const TLAppSignalWorkspaceTabAdded;
extern TLAppSignalName const TLAppSignalWorkspaceTabRemoved;
extern TLAppSignalName const TLAppSignalWorkspaceTabMoved;

@interface TLAppSignal : NSObject <NSCopying>

@property (nonatomic, copy, readonly) TLAppSignalName name;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *payload;
@property (nonatomic, assign, readonly) NSUInteger sequence;

+ (instancetype)signalWithName:(TLAppSignalName)name
                       payload:(nullable NSDictionary<NSString *, id> *)payload
                      sequence:(NSUInteger)sequence;

@end

@interface TLAppStateSnapshot : NSObject <NSCopying>

@property (nonatomic, assign, readonly) TLWorkspaceTabKind activeTabKind;
@property (nonatomic, assign, readonly) NSInteger activeTabID;
@property (nonatomic, copy, readonly) NSArray<TLWorkspaceTab *> *workspaceTabs;
@property (nonatomic, assign, readonly) NSUInteger revision;
@property (nonatomic, strong, nullable, readonly) TLAppSignal *lastSignal;

@end

@interface TLMutableAppState : NSObject

@property (nonatomic, assign) TLWorkspaceTabKind activeTabKind;
@property (nonatomic, assign) NSInteger activeTabID;
@property (nonatomic, strong) NSMutableArray<TLWorkspaceTab *> *workspaceTabs;

@end

@interface TLAppStateSubscription : NSObject

- (void)cancel;

@end

typedef id _Nullable (^TLAppStateSelector)(TLAppStateSnapshot *snapshot);
typedef void (^TLAppStateChangeHandler)(id _Nullable selectedValue,
                                        TLAppStateSnapshot *snapshot,
                                        TLAppSignal *signal);
typedef void (^TLAppSignalHandler)(TLAppSignal *signal, TLAppStateSnapshot *snapshot);
typedef void (^TLAppStateMutation)(TLMutableAppState *draft);

@interface TLAppStateManager : NSObject

@property (nonatomic, copy, readonly) TLAppStateSnapshot *snapshot;

- (TLAppStateSubscription *)subscribeWithSelector:(TLAppStateSelector)selector
                               notifyImmediately:(BOOL)notifyImmediately
                                         handler:(TLAppStateChangeHandler)handler;

- (TLAppStateSubscription *)subscribeToSignal:(TLAppSignalName)signalName
                                      handler:(TLAppSignalHandler)handler;

- (TLAppStateSnapshot *)setState:(TLAppStateMutation)mutation
                          signal:(TLAppSignalName)signalName
                         payload:(nullable NSDictionary<NSString *, id> *)payload;

- (TLAppStateSnapshot *)sendSignal:(TLAppSignalName)signalName
                           payload:(nullable NSDictionary<NSString *, id> *)payload;

- (void)activateWorkspaceTabKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID;
- (nullable TLWorkspaceTab *)workspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID;
- (BOOL)hasWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID;
- (void)addWorkspaceTab:(TLWorkspaceTab *)tab activate:(BOOL)activate;
- (void)upsertWorkspaceTab:(TLWorkspaceTab *)tab activate:(BOOL)activate;
- (void)replaceWorkspaceTabWithKind:(TLWorkspaceTabKind)kind
                               tabID:(NSInteger)tabID
                             withTab:(TLWorkspaceTab *)replacementTab
                            activate:(BOOL)activate;
- (void)removeWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID;
- (void)moveWorkspaceTabWithKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID toIndex:(NSUInteger)targetIndex;

@end

NS_ASSUME_NONNULL_END
