#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLAgentCreationWindowController : NSWindowController
@property (nonatomic, copy, nullable) void (^agentCreatedHandler)(TLAgentRecord *agent);
- (instancetype)initWithPalette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator;
@property (nonatomic, copy, nullable) void (^agentUpdatedHandler)(TLAgentRecord *agent);
- (instancetype)initWithAgent:(nullable TLAgentRecord *)agent palette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator;
- (void)showFromWindow:(NSWindow *)parent;
- (void)applyPalette:(TLThemePalette *)palette;
@end

NS_ASSUME_NONNULL_END
