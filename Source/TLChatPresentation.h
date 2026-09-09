#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "TLQueuedPrompt.h"
#import "design_system/TLPromptQueueView.h"
#import "UIComponents.h"
#import "design_system/TLMessageInput.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLASCIIPlanetScreensaverView.h"

// UI state belongs to a chat, including its live transcript, draft, selection,
// scroll position and pending render. The window routes actions to the focused
// presentation; background rendering explicitly scopes itself to its origin.
NS_ASSUME_NONNULL_BEGIN
@interface TLChatPresentation : NSObject
@property (nonatomic, strong) TLChatRecord *chat;
@property (nonatomic, strong) NSMutableArray<TLQueuedPrompt *> *queuedPrompts;
@property (nonatomic, strong) TLPromptQueueView *promptQueueView;
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
@property (nonatomic, strong) NSTimer *slashCommandUpdateTimer;
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
