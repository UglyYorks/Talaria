#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "TLFeatureTabController.h"
#import "TLAttachmentViewerWindowController.h"
#import "TLQueuedPrompt.h"
#import "design_system/TLPromptQueueView.h"
#import "design_system/TLFindBar.h"
#import "UIComponents.h"
#import "design_system/TLMessageInput.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLASCIIPlanetScreensaverView.h"
#import "design_system/TLStarryEmptyStateView.h"

// UI state belongs to a chat, including its live transcript, draft, selection,
// scroll position and pending render. The window routes actions to the focused
// controller; background work receives its originating controller explicitly.
NS_ASSUME_NONNULL_BEGIN
@interface TLChatTabController : TLFeatureTabController <TLFindActionTarget>
@property (nonatomic, weak, nullable) id composerTarget;
@property (nonatomic, weak, nullable) id<NSTextViewDelegate> composerDelegate;
@property (nonatomic) SEL sendAction;
@property (nonatomic) SEL settingsAction;
@property (nonatomic, copy, nullable) dispatch_block_t attachmentsChangedHandler;
@property (nonatomic, copy, nullable) void (^suggestionActivationHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^queueSendNowHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^queueEditHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^queueRemoveHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) dispatch_block_t queueResumeHandler;
@property (nonatomic, copy, nullable) dispatch_block_t queueCancelEditHandler;
- (NSView *)buildChatWorkspace;
- (NSView *)buildMessagesView;
- (NSView *)buildMessageInput;
- (NSView *)buildSlashCommandListView;
@property (nonatomic, copy, nullable) NSString *agentAvatar;
@property (nonatomic, copy, nullable) TLAttachmentPreviewItem *(^previewItemProvider)(NSDictionary *attachment);
@property (nonatomic, copy, nullable) void (^attachmentPreviewHandler)(TLChatMessage *message, NSUInteger index);
@property (nonatomic, copy, nullable) BOOL (^approvalHandler)(NSString *requestID, NSString *choice);
@property (nonatomic, copy, nullable) void (^linkHandler)(NSURL *URL, NSEventModifierFlags flags);
@property (nonatomic, copy, nullable) dispatch_block_t _Nullable (^linkContextMenuHandler)(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point);
@property (nonatomic, copy, nullable) BOOL (^streamingProvider)(void);
@property (nonatomic, copy, nullable) dispatch_block_t intentHandler;
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom;
- (void)scheduleStreamingMessageRender;
- (void)markMessageDirty:(nullable TLChatMessage *)message;
- (void)updateMessageScrollInsets;
- (void)resetMessageRowCache;
- (void)detachMessageRowFromStack:(NSView *)row;
@property (nonatomic, strong, readonly) TLFindBar *findBar;
- (void)installFindBarInView:(NSView *)view palette:(TLThemePalette *)palette;
- (void)applyFindPalette:(TLThemePalette *)palette;
- (void)refreshFindResults;
@property (nonatomic, strong) TLChatRecord *chat;
@property (nonatomic, strong) NSMutableArray<TLQueuedPrompt *> *queuedPrompts;
@property (nonatomic, strong) TLPromptQueueView *promptQueueView;
@property (nonatomic, strong) NSLayoutConstraint *promptQueueBottomConstraint;
@property (nonatomic) BOOL queuePaused;
@property (nonatomic) BOOL queueInterruptPending;
@property (nonatomic, strong, nullable) TLQueuedPrompt *editingQueuedPrompt;
@property (nonatomic, strong, nullable) TLQueuedPrompt *queueDraft;
@property (nonatomic, strong, nullable) TLQueuedPrompt *queuedPromptInFlight;
@property (nonatomic, strong) NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageRowViews;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSString *> *messageRowSignatures;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageMarkdownViews;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageActivityViews;
@property (nonatomic, copy) NSArray<TLChatMessage *> *renderedMessages;
@property (nonatomic) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, strong) TLStarryEmptyStateView *emptyStateView;
@property (nonatomic, strong) TLTokenView *messagesBackground;
@property (nonatomic, strong) TLMessageInput *messageInput;
@property (nonatomic, strong) NSView *chatWorkspace;
@property (nonatomic, strong) NSLayoutConstraint *messageInputWidthConstraint;
@property (nonatomic, strong) NSScrollView *messageScrollView;
@property (nonatomic, strong) TLFlippedView *messageDocumentView;
@property (nonatomic, strong) NSStackView *messageStack;
@property (nonatomic, strong) NSLayoutConstraint *messageStackBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *messageStackMinimumBottomConstraint;
@property (nonatomic, strong) NSTextView *promptTextView;
@property (nonatomic, strong) TLInputSuggestionPanelView *slashCommandListView;
@property (nonatomic, strong) TLInputSuggestionListView *slashCommandScrollView;
@property (nonatomic, strong, nullable) NSTimer *slashCommandUpdateTimer;
@property (nonatomic) BOOL renderingSlashCommands;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *visibleSlashCommands;
@property (nonatomic) NSInteger selectedSlashCommandIndex;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListBottomConstraint;
@property (nonatomic) BOOL streamingRenderScheduled;
@property (nonatomic) NSUInteger streamingRenderGeneration;
@property (nonatomic, strong) TLGlassButton *sendButton;
@property (nonatomic, strong, nullable) TLASCIIPlanetScreensaverView *screensaverView;
@end
NS_ASSUME_NONNULL_END
