#import "TalariaWindowController.h"
#import "TLChatTabController.h"
@class TLAssistantTurnResult;
@interface TalariaWindowController (ChatControllerTests)
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext ;
- (BOOL)isChatPresentationVisibleForChat:(TLChatTabController *)chatContext ;
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext ;
- (void)hideSlashCommandListForChat:(TLChatTabController *)chatContext ;
- (void)renderSlashCommandListForChat:(TLChatTabController *)chatContext ;
- (void)flushSlashCommandUpdateForChat:(TLChatTabController *)chatContext ;
- (void)updateSlashCommandListForChat:(TLChatTabController *)chatContext ;
- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset  forChat:(TLChatTabController *)chatContext ;
- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex  forChat:(TLChatTabController *)chatContext ;
- (void)showSlashCommandListWithCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext ;
- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext ;
- (void)applySlashCommandListPaletteForChat:(TLChatTabController *)chatContext ;
- (void)drainPromptQueueForChat:(TLChatTabController *)chatContext ;
- (void)finishQueuedTurnWithResult:(TLAssistantTurnResult *)result  forChat:(TLChatTabController *)chatContext ;
- (void)pausePromptQueueRestoringInFlight:(BOOL)restore  forChat:(TLChatTabController *)chatContext ;
- (void)removeQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext ;
- (void)finishQueuedPromptEditingSaving:(BOOL)save  forChat:(TLChatTabController *)chatContext ;
- (void)editQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext ;
- (void)sendQueuedPromptNowAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext ;
- (void)updatePromptQueueForChat:(TLChatTabController *)chatContext ;
- (BOOL)hasPendingChatApprovalForChat:(TLChatTabController *)chatContext ;
- (BOOL)canStopResponseForChat:(TLChatTabController *)chatContext ;
- (BOOL)isSendingForChat:(TLChatTabController *)chatContext ;
- (BOOL)preparingAttachmentsForChat:(TLChatTabController *)chatContext ;
- (TLChatTabController *)newChatTabController;
@end
