#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLProviderSetupWindowController : NSWindowController
@property (nonatomic, copy, nullable) void (^completionHandler)(NSString *selection);
- (instancetype)initWithAgent:(TLAgentRecord *)agent orchestrator:(TLAgentOrchestrator *)orchestrator palette:(TLThemePalette *)palette;
- (void)presentForWindow:(NSWindow *)window;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
