#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "AppStateManager.h"
#import "Database.h"
#import "TLTabShortcuts.h"

NS_ASSUME_NONNULL_BEGIN

@interface TalariaWindowController : NSWindowController

- (instancetype)initWithDatabase:(TLDatabase *)database
                agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator
                  appStateManager:(TLAppStateManager *)appStateManager;
@property (nonatomic, readonly, getter=isIncognito) BOOL incognito;
@property (nonatomic, copy, nullable) dispatch_block_t incognitoDidClose;
- (void)openBrowserTabWithURL:(NSURL *)URL;
- (BOOL)canPerformTabCommand:(TLTabCommand)command;
- (void)performTabCommand:(TLTabCommand)command;
- (BOOL)canPerformFindAction:(NSTextFinderAction)action;
- (void)performFindAction:(NSTextFinderAction)action;
- (void)closeActiveTabOrWindow:(id)sender;
- (void)showOnboardingDemoWindow:(id)sender;

@end

NS_ASSUME_NONNULL_END
