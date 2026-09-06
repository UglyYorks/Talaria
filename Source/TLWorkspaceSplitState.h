#import "WorkspaceState.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *TLWorkspaceTabIdentity(TLWorkspaceTab *tab);

@interface TLWorkspaceSplitGroup : NSObject
@property (nonatomic, copy) NSString *leftIdentity;
@property (nonatomic, copy) NSString *rightIdentity;
@property (nonatomic) double fraction;
@end

// A tab belongs to at most one pair. Groups use presentation identities so
// promoting a draft to a saved chat does not break its split.
@interface TLWorkspaceSplitState : NSObject
@property (nonatomic, copy, readonly) NSArray<TLWorkspaceSplitGroup *> *groups;
- (nullable TLWorkspaceSplitGroup *)groupForTab:(nullable TLWorkspaceTab *)tab;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)onLeft;
- (void)removeGroupForTab:(TLWorkspaceTab *)tab;
- (void)reconcileTabs:(NSArray<TLWorkspaceTab *> *)tabs;
@end
NS_ASSUME_NONNULL_END
