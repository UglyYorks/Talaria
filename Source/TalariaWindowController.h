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
- (BOOL)canPerformTabCommand:(TLTabCommand)command;
- (void)performTabCommand:(TLTabCommand)command;
- (void)closeActiveTabOrWindow:(id)sender;
- (void)showOnboardingDemoWindow:(id)sender;

@end

NS_ASSUME_NONNULL_END
