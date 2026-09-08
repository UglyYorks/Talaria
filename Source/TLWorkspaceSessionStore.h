#import <Foundation/Foundation.h>
#import "AppStateManager.h"

NS_ASSUME_NONNULL_BEGIN

// Stores tab identities and metadata. Chat history remains in the database.
@interface TLWorkspaceSessionStore : NSObject
- (instancetype)initWithURL:(NSURL *)URL;
- (void)restoreStateManager:(TLAppStateManager *)stateManager;
- (void)observeStateManager:(TLAppStateManager *)stateManager;
@end

NS_ASSUME_NONNULL_END
