#import <AppKit/AppKit.h>
#import "AgentOrchestrator.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLChatSettingsController : NSViewController
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSString *model, NSString *supportingModel,
  NSString *reasoningEffort, void (^completion)(NSError *_Nullable error));
@property (nonatomic, strong, readonly) NSPopover *popover;
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
- (instancetype)initWithModel:(NSString *)model supportingModel:(NSString *)supportingModel
             reasoningEffort:(NSString *)reasoningEffort agentID:(NSInteger)agentID token:(NSString *)token
                orchestrator:(TLAgentOrchestrator *)orchestrator palette:(TLThemePalette *)palette;
- (void)presentRelativeToView:(NSView *)anchor;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
