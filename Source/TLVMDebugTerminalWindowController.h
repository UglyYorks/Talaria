#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLVMDebugTerminalWindowController : NSWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette
               agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator;
- (void)showFromWindow:(nullable NSWindow *)parentWindow;
- (void)updatePalette:(TLThemePalette *)palette;

@end

NS_ASSUME_NONNULL_END
