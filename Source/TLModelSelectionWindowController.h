#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLModelSelectionWindowController : NSWindowController
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSString *model, void (^completion)(NSError *_Nullable error));
- (instancetype)initWithSmallModel:(BOOL)small selectedModel:(NSString *)model
                            token:(NSString *)token orchestrator:(TLAgentOrchestrator *)orchestrator
                          palette:(TLThemePalette *)palette;
- (void)presentForWindow:(NSWindow *)window;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
