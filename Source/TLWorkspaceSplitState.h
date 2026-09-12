#import "WorkspaceState.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *TLWorkspaceTabIdentity(TLWorkspaceTab *tab);
typedef NS_ENUM(NSInteger, TLSplitPlacement) {
  TLSplitPlacementLeft, TLSplitPlacementRight, TLSplitPlacementAbove, TLSplitPlacementBelow
};
@interface TLWorkspaceSplitGroup : NSObject
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *columns;
@property (nonatomic, copy, readonly) NSArray<NSString *> *identities;
@property (nonatomic, copy, readonly) NSString *leftIdentity;
@property (nonatomic, copy, readonly) NSString *rightIdentity;
@property (nonatomic) double fraction;
@property (nonatomic, copy, nullable) NSDictionary *layoutWeights;
@end

// Presentation identities survive draft promotion. A group has at most three
// columns, with at most three live views in each column.
@interface TLWorkspaceSplitState : NSObject
@property (nonatomic, copy, readonly) NSArray<TLWorkspaceSplitGroup *> *groups;
- (nullable TLWorkspaceSplitGroup *)groupForTab:(nullable TLWorkspaceTab *)tab;
- (BOOL)canSplitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement;
- (BOOL)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)onLeft;
- (nullable NSString *)availableNeighborForTab:(nullable TLWorkspaceTab *)tab placement:(TLSplitPlacement * _Nullable)placement;
- (void)detachTab:(TLWorkspaceTab *)tab;
- (void)removeGroupForTab:(TLWorkspaceTab *)tab;
- (void)reconcileTabs:(NSArray<TLWorkspaceTab *> *)tabs;
@end
NS_ASSUME_NONNULL_END
