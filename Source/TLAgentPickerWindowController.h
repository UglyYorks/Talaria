#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLAgentPickerWindowController : NSWindowController
@property (nonatomic, copy, nullable) BOOL (^selectionHandler)(NSInteger agentID);
@property (nonatomic, copy, nullable) void (^manageHandler)(void);
- (instancetype)initWithAgents:(NSArray<TLAgentRecord *> *)agents
               currentAgentID:(NSInteger)currentAgentID
             selectionEnabled:(BOOL)selectionEnabled
                      palette:(TLThemePalette *)palette;
- (void)showErrorMessage:(NSString *)message;
- (void)showFromWindow:(NSWindow *)parent;
- (void)applyPalette:(TLThemePalette *)palette;
@end

NS_ASSUME_NONNULL_END
