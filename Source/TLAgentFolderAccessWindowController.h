#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLAgentFolderAccessWindowController : NSWindowController
@property (nonatomic, copy, nullable) void (^savedHandler)(void);
- (instancetype)initWithAgent:(TLAgentRecord *)agent palette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator;
- (void)showFromWindow:(NSWindow *)parent;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
