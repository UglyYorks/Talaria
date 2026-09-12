#import "design_system/TLIncognitoPill.h"
#import "TLProviderSetupWindowController.h"
#import "TLBookmarkEditorController.h"
#import "TLEmptyStateTips.h"
#import "TLBrowserImageActions.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLActionMenuItem.h"
#import "TLAutomationsTabController.h"
#import "TLNotificationsController.h"
#import "design_system/TLNotificationMessageCardView.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLApprovalCardView.h"
#import "design_system/TLInputSuggestionListView.h"
#import "TalariaWindowController.h"
#import "TLBrowserPreferences.h"
#import "TLDownloadsTabController.h"
#import "TLApplicationPreferences.h"
#import "PromptBuilder.h"
#import "AgentOrchestrator.h"
#import "AppStateManager.h"
#import "AssistantTurnRunner.h"
#import "ChatIconGenerator.h"
#import "MarkdownRenderer.h"
#import "design_system/TLMarkdownContentWebView.h"
#import "NotchOverlayController.h"
#import "TLQuickInputWindowController.h"
#import "InputSuggestions.h"
#import "Theme.h"
#import "TLHistoryPanelController.h"
#import "TLBrowserTabController.h"
#import "TLSettingsTabController.h"
#import "TLModelSelectionWindowController.h"
#import "TLMainWindow.h"
#import "TLOnboardingDemoWindowController.h"
#import "TLHermesOnboardingWindowController.h"
#import "TLAgentCreationWindowController.h"
#import "TLAgentFolderAccessWindowController.h"
#import "TLVMTerminalSession.h"
#import "TLWorkspaceTabsController.h"
#import "UIComponents.h"
#import "design_system/TLWorkspaceOutlineView.h"
#import "design_system/TLAgentTableCells.h"
#import "design_system/TLTransitionCoordinator.h"
#import "design_system/TLChromeTabView.h"
#import "WorkspaceState.h"
#import "TLChatTabController.h"
#import "design_system/TLToolActivityView.h"
#import "TLAttachmentViewerWindowController.h"
#import "design_system/TLAttachmentChipView.h"
#import "TLWorkspaceSplitState.h"
#import "design_system/TLSplitWorkspaceView.h"
#import "WorkspaceTabRuntime.h"
#import "Widgetbook.h"
#import "design_system/TLButton.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLASCIIPlanetScreensaverView.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLMessageInput.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static void *TLEffectiveAppearanceObservationContext = &TLEffectiveAppearanceObservationContext;

static NSString *const TLAWSOutageChatTitle = @"AWS Oregon Outage";
static NSString *const TLAWSOutageAgentMessage = @"\u26A0\uFE0F AWS is reporting an outage in the Oregon region. Talaria traffic routed through US West is seeing elevated errors and intermittent request failures. Failover capacity is available in US Central.";
static NSString *const TLAWSOutageIntent = @"Route Talaria traffic to the US-central region";
static const CGFloat TLMainWindowOnboardingRevealDuration = 0.3;
static const CGFloat TLMainWindowOnboardingRevealInitialScale = 0.001;

@interface TLClosedWorkspaceTab : NSObject
@property (nonatomic, copy) TLWorkspaceTab *tab;
@property (nonatomic) NSUInteger index;
@property (nonatomic, strong) TLChatRecord *draftChat;
@property (nonatomic, copy) NSString *prompt;
@end
@implementation TLClosedWorkspaceTab
@end

@interface TalariaWindowController () <NSWindowDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, TLHistoryPanelControllerDelegate, TLWorkspaceTabsControllerDelegate>

@property (nonatomic, strong) TLChatTabController *chatPresentation;
@property (nonatomic, strong) TLAttachmentViewerWindowController *attachmentViewer;
@property (nonatomic, strong) TLDownloadsTabController *downloadsController;
@property (nonatomic, strong) TLWorkspaceTab *downloadsTab;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TLChatTabController *> *chatPresentations;
@property (nonatomic, strong) TLWorkspaceSplitState *splitState;
@property (nonatomic, strong) TLSplitWorkspaceView *splitWorkspace;
@property (nonatomic, strong) TLWorkspaceTab *displayedWorkspaceTab;
@property (nonatomic, strong) TLWorkspaceTab *tabBeforePointerSelection;
@property (nonatomic, strong) TLWorkspaceTab *splitDropTarget;
@property (nonatomic) BOOL bookmarkDropTarget;
@property (nonatomic) TLSplitDropSide splitDropSide;
@property (nonatomic, strong) id paneFocusMonitor;
@property (nonatomic) BOOL updatingSplitLayout;
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TLAssistantTurnRunner *> *turnRunners;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<TLChatMessage *> *> *turnMessagesByChat;
@property (nonatomic, strong) TLChatIconGenerator *chatIconGenerator;
@property (nonatomic, strong) TLAppStateManager *appStateManager;
@property (nonatomic, strong) NSMutableArray<TLAppStateSubscription *> *appStateSubscriptions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLWorkspaceTabRuntime *> *workspaceTabRuntimes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *chatIconRequests;
@property (nonatomic, strong) NSMutableArray<TLClosedWorkspaceTab *> *closedWorkspaceTabs;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLAppSettings *settings;
@property (nonatomic, strong) NSMutableArray<TLChatSummary *> *chats;
@property (nonatomic, strong) NSMutableArray<TLAgentRecord *> *agents;
@property (nonatomic, strong, nullable) TLWorkspaceTab *historyTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *settingsTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *agentsTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *debugTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *automationsTab;
@property (nonatomic, strong, nullable) TLAutomationsTabController *automationsController;
@property (nonatomic, strong) TLNotificationsController *notificationsController;
@property (nonatomic, strong) NSTimer *notificationsTimer;
@property (nonatomic) NSInteger notificationsAgentID;
@property (nonatomic) NSUInteger notificationsSyncGeneration;
@property (nonatomic) NSUInteger notificationsNavigationGeneration;
@property (nonatomic) BOOL notificationsSyncInFlight;
@property (nonatomic) BOOL openingNotificationSource;
@property (nonatomic) NSUInteger notificationsFailureCount;
@property (nonatomic, strong) NSDate *notificationsNextSync;
@property (nonatomic, strong) TLChatRecord *activeChat;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSURL *> *> *attachmentDrafts;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *attachmentPromptDrafts;
@property (nonatomic, readonly) BOOL preparingAttachments;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *preparingAttachmentChats;
@property (nonatomic) NSInteger nextBrowserTabID;
@property (nonatomic) NSInteger nextDraftChatID;
@property (nonatomic, strong) NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageRowViews;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSString *> *messageRowSignatures;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageMarkdownViews;
@property (nonatomic, copy) NSArray<TLChatMessage *> *renderedMessages;
@property (nonatomic, readonly) BOOL isSending;
@property (nonatomic, readonly) BOOL hasSendingTurns;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL widgetbookMode;
@property (nonatomic, copy) NSString *errorMessage;

@property (nonatomic, strong) TLTokenView *rootView;
@property (nonatomic, strong) NSVisualEffectView *frostedBackgroundView;
@property (nonatomic, strong) TLTokenView *frostedOverlayView;
@property (nonatomic, strong) TLTokenView *topbar;
@property (nonatomic, strong) TLTokenView *sidebarView;
@property (nonatomic, strong) TLTokenView *messagesBackground;
@property (nonatomic, strong) TLMessageInput *messageInput;
@property (nonatomic, strong) TLTokenView *contentShadowView;
@property (nonatomic, strong) TLTokenView *contentHost;
@property (nonatomic, strong) TLWorkspaceOutlineView *workspaceOutline;
@property (nonatomic, strong) TLTransitionCoordinator *sidebarTransitions;
@property (nonatomic, strong) NSView *chatWorkspace;
@property (nonatomic, strong) NSLayoutConstraint *messageInputWidthConstraint;
@property (nonatomic, strong) NSStackView *tabStack;
@property (nonatomic, strong) TLWorkspaceTabsController *workspaceTabsController;
@property (nonatomic) BOOL workspaceRenderScheduled;
@property (nonatomic, strong) NSLayoutConstraint *tabStackLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentLeadingConstraint;
@property (nonatomic, strong) NSStackView *sidebarTileGrid;
@property (nonatomic, strong) TLHoverStackView *sidebarAgentPane;
@property (nonatomic, strong) NSView *sidebarAgentPaneSurface;
@property (nonatomic, strong) NSStackView *sidebarInboxStack;
@property (nonatomic, strong) TLSidebarShortcutsView *sidebarShortcutsView;
@property (nonatomic, copy) NSArray<TLBookmark *> *bookmarks;
@property (nonatomic, strong) NSPopover *bookmarkPopover;
@property (nonatomic, strong) TLBookmarkEditorController *bookmarkEditor;
@property (nonatomic, strong) TLSidebarInboxPaneView *sidebarInboxPaneView;
@property (nonatomic, strong) TLSidebarInboxStackView *gmailInboxStackView;
@property (nonatomic, strong) TLSidebarInboxStackView *slackInboxStackView;
@property (nonatomic, strong) NSLayoutConstraint *sidebarTileGridLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarTileGridTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarInboxLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarInboxTrailingConstraint;
@property (nonatomic, strong) NSStackView *sidebarActionStack;
@property (nonatomic, strong) NSLayoutConstraint *sidebarActionStackLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarActionStackTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sidebarActionStackHeightConstraint;
@property (nonatomic, strong) TLSidebarNavigationButton *sidebarAutomationsButton;
@property (nonatomic, strong) TLSidebarUserButton *sidebarUserButton;
@property (nonatomic, strong) TLSidebarResizeHandle *sidebarResizeHandle;
@property (nonatomic) CGFloat sidebarPreferredWidth;
@property (nonatomic) CGFloat sidebarResizeStartWidth;
@property (nonatomic) BOOL sidebarVisible;
@property (nonatomic) BOOL effectiveAppearanceObserverInstalled;
@property (nonatomic) BOOL streamingRenderScheduled;
@property (nonatomic) NSUInteger streamingRenderGeneration;

@property (nonatomic, strong) TLHistoryPanelController *historyPanelController;
@property (nonatomic, strong) TLHistoryRepository *historyRepository;
@property (nonatomic, copy) NSArray<TLChatSummary *> *hermesHistoryChats;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSDictionary *> *hermesHistorySessions;
@property (nonatomic) NSInteger historyAgentID;
@property (nonatomic) NSUInteger historyRequestGeneration;
@property (nonatomic) BOOL historyWasVisible;
@property (nonatomic, strong) TLTokenView *agentsView;
@property (nonatomic, strong) TLSettingsTabController *settingsTabController;
@property (nonatomic, strong) NSTableView *agentsTableView;
@property (nonatomic, strong) NSTextField *agentsStatusLabel;
@property (nonatomic, strong) NSButton *createAgentButton;
@property (nonatomic, strong) NSButton *startAgentButton;
@property (nonatomic, strong) NSButton *stopAgentButton;
@property (nonatomic, strong) NSButton *agentSettingsButton;
@property (nonatomic, strong) TLAgentCreationWindowController *agentSettingsWindowController;
@property (nonatomic, strong) NSButton *folderAccessButton;
@property (nonatomic, strong) TLAgentFolderAccessWindowController *agentFolderAccessWindowController;
@property (nonatomic, strong) NSButton *deleteAgentButton;
@property (nonatomic, strong) NSButton *closeAgentsButton;
@property (nonatomic, strong) NSScrollView *messageScrollView;
@property (nonatomic, strong) TLFlippedView *messageDocumentView;
@property (nonatomic, strong) NSStackView *messageStack;
@property (nonatomic, strong) NSLayoutConstraint *messageStackBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *messageStackMinimumBottomConstraint;
@property (nonatomic, strong) NSTextView *promptTextView;
@property (nonatomic, strong) TLNotchOverlayController *notchOverlayController;
@property (nonatomic, strong) TLQuickInputWindowController *quickInputController;
@property (nonatomic, strong) id messageScrollWheelMonitor;
@property (nonatomic, strong) id messageContextMenuMonitor;

@property (nonatomic, strong) TLButton *createChatButton;
@property (nonatomic, strong) TLButton *sidebarToggleButton;
@property (nonatomic, strong) TLIncognitoPill *incognitoPill;
@property (nonatomic, strong) TLInputSuggestionPanelView *slashCommandListView;
@property (nonatomic, strong) TLInputSuggestionListView *slashCommandScrollView;
@property (nonatomic, strong) NSTimer *slashCommandUpdateTimer;
@property (nonatomic) BOOL renderingSlashCommands;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *hermesCommands;
@property (nonatomic, strong) NSDate *hermesCommandsFetchedAt;
@property (nonatomic) NSInteger hermesCommandsAgentID;
@property (nonatomic) BOOL loadingHermesCommands;
@property (nonatomic, copy) NSString *hermesCommandsRequestID;
@property (nonatomic, copy) NSString *hermesCommandsError;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *visibleSlashCommands;
@property (nonatomic) NSInteger selectedSlashCommandIndex;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListBottomConstraint;
@property (nonatomic, strong) TLOnboardingDemoWindowController *onboardingDemoWindowController;
@property (nonatomic, strong) TLProviderSetupWindowController *providerSetupWindowController;
@property (nonatomic, strong) TLHermesOnboardingWindowController *hermesOnboardingWindowController;
@property (nonatomic, strong) TLAgentCreationWindowController *agentCreationWindowController;
@property (nonatomic) BOOL openingDebugTerminal;
@property (nonatomic, weak) TLThemedButton *debugTerminalButton;
@property (nonatomic, strong) NSTimer *debugTerminalStateTimer;
@property (nonatomic, strong, nullable) TLASCIIPlanetScreensaverView *screensaverView;
@property (nonatomic) NSRect mainWindowFrameBeforeOnboarding;
@property (nonatomic) BOOL hasMainWindowFrameBeforeOnboarding;
@property (nonatomic, strong) NSImage *mainWindowSnapshotBeforeOnboarding;
@property (nonatomic, strong) NSWindow *mainWindowRevealOverlayWindow;
@property (nonatomic, strong) TLGlassButton *sendButton;
@property (nonatomic, strong) TLModelSelectionWindowController *modelSelectionController;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TLChatRecord *> *modelDraftChats;

- (void)handleFileURLsDroppedOnNotch:(NSArray<NSURL *> *)fileURLs;
- (void)handleLinkURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)modifierFlags;
- (void)handleBrowserTabRequestURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)modifierFlags;
- (void)openSidebarBookmark:(TLSidebarShortcutButton *)sender;
- (nullable NSURL *)browserURLFromPromptString:(NSString *)promptString;
- (void)applyBrowserAddressInputWidth:(CGFloat)width;
- (void)applyContentTopLeftCornerRadius:(CGFloat)cornerRadius;
- (void)invalidateThemeAppearanceForViewTree:(NSView *)view;
- (void)installEffectiveAppearanceObserver;
- (void)handleEffectiveAppearanceChanged;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsMatchingPrompt:(NSString *)prompt;
- (NSView *)buildSlashCommandListView;
- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands;
- (void)applySlashCommandListPalette;
- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex;
- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset;
- (BOOL)performSelectedSlashCommand;
- (void)updateSlashCommandList;
- (void)openAppFromOnboarding;
- (void)revealMainWindowFromOnboarding;
- (NSImage *)snapshotOfMainWindow;
- (void)finishMainWindowRevealWithFinalFrame:(NSRect)finalFrame;
- (void)hideSlashCommandList;
- (void)showOnboardingDemoWindow:(id)sender;
- (void)showScreensaver;
- (void)hideScreensaver;
- (void)addUrgentNotification;
- (void)addDelayedCalendarConflictNotification;
- (void)openAWSOutageChat:(id)sender;
- (void)sendAWSOutageIntent:(id)sender;
- (void)prepareResponsiveLayoutForWindowWidth:(CGFloat)windowWidth;
- (CGFloat)tabStackLeadingConstantForSidebarWidth:(CGFloat)sidebarWidth;
- (CGFloat)availableTabStripWidthForLeadingConstant:(CGFloat)leadingConstant topbarWidth:(CGFloat)topbarWidth;
- (CGFloat)clampedSidebarWidthForPreferredWidth:(CGFloat)preferredWidth windowWidth:(CGFloat)windowWidth;
- (BOOL)closeWindowIfOnlyWorkspaceTab:(TLWorkspaceTab *)tab;

- (void)updateControlStatesForChat:(TLChatTabController *)chatContext;
- (BOOL)isChatPresentationVisibleForChat:(TLChatTabController *)chatContext;
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext;
- (void)hideSlashCommandListForChat:(TLChatTabController *)chatContext;
- (void)renderSlashCommandListForChat:(TLChatTabController *)chatContext;
- (void)flushSlashCommandUpdateForChat:(TLChatTabController *)chatContext;
- (void)updateSlashCommandListForChat:(TLChatTabController *)chatContext;
- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset  forChat:(TLChatTabController *)chatContext;
- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex  forChat:(TLChatTabController *)chatContext;
- (void)showSlashCommandListWithCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext;
- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext;
- (void)applySlashCommandListPaletteForChat:(TLChatTabController *)chatContext;
- (void)drainPromptQueueForChat:(TLChatTabController *)chatContext;
- (void)finishQueuedTurnWithResult:(TLAssistantTurnResult *)result  forChat:(TLChatTabController *)chatContext;
- (void)pausePromptQueueRestoringInFlight:(BOOL)restore  forChat:(TLChatTabController *)chatContext;
- (void)removeQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext;
- (void)finishQueuedPromptEditingSaving:(BOOL)save  forChat:(TLChatTabController *)chatContext;
- (void)editQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext;
- (void)sendQueuedPromptNowAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext;
- (void)updatePromptQueueForChat:(TLChatTabController *)chatContext;
- (BOOL)hasPendingChatApprovalForChat:(TLChatTabController *)chatContext;
- (BOOL)canStopResponseForChat:(TLChatTabController *)chatContext;
- (BOOL)isSendingForChat:(TLChatTabController *)chatContext;
- (BOOL)preparingAttachmentsForChat:(TLChatTabController *)chatContext;
@end

@implementation TalariaWindowController

- (TLChatTabController *)newChatTabController {
  TLChatTabController *chat = [[TLChatTabController alloc] initWithPalette:self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem]];
  __weak typeof(self) weakSelf = self;
  __weak TLChatTabController *origin = chat;
  chat.notificationRevealHandler = ^BOOL { return [weakSelf revealNotificationInPresentation:origin]; };
  chat.previewItemProvider = ^TLAttachmentPreviewItem *(NSDictionary *attachment) {
    return [weakSelf previewItemForAttachment:attachment sessionID:origin.chat.hermesSessionID];
  };
  chat.attachmentPreviewHandler = ^(TLChatMessage *message, NSUInteger index) { [weakSelf previewAttachmentsForPresentation:origin message:message index:index]; };
  chat.approvalHandler = ^BOOL(NSString *requestID, NSString *choice) { return [weakSelf respondToApproval:requestID choice:choice chatID:origin.chat.chatID]; };
  chat.linkHandler = ^(NSURL *URL, NSEventModifierFlags flags) { [weakSelf handleLinkURL:URL modifierFlags:flags]; };
  chat.linkContextMenuHandler = ^dispatch_block_t(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point) {
    TalariaWindowController *owner = weakSelf;
    TLWorkspaceTab *source = [owner.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:origin.chat.chatID];
    if (!source) return nil;
    NSString *identity = TLWorkspaceTabIdentity(source);
    return [TLBrowserLinkActions configureNativeMenu:menu forURL:URL inView:view atPoint:point open:^(NSURL *link, TLBrowserLinkDestination destination) {
      [weakSelf handleContextLinkURL:link destination:destination sourceIdentity:identity];
    }];
  };
  chat.streamingProvider = ^BOOL{ return weakSelf.turnRunners[@(origin.chat.chatID)] != nil; };
  chat.intentHandler = ^{ [weakSelf activateCachedChatWithID:origin.chat.chatID]; [weakSelf sendAWSOutageIntent:nil]; };
  chat.composerTarget = self;
  chat.composerDelegate = self;
  chat.sendAction = @selector(activateComposerButton:);
  chat.settingsAction = @selector(showChatModelMenu:);
  chat.attachmentsChangedHandler = ^{
    [origin updateMessageScrollInsets];
    [weakSelf updateSlashCommandListForChat:origin];
    [weakSelf updateControlStatesForChat:origin];
  };
  chat.suggestionActivationHandler = ^(NSUInteger index) {
    [weakSelf focusChatContainingView:origin.slashCommandScrollView];
    [weakSelf performInputSuggestionAtIndex:index];
  };
  chat.queueSendNowHandler = ^(NSUInteger index) { [weakSelf sendQueuedPromptNowAtIndex:index forChat:origin]; };
  chat.queueEditHandler = ^(NSUInteger index) { [weakSelf editQueuedPromptAtIndex:index forChat:origin]; };
  chat.queueRemoveHandler = ^(NSUInteger index) { [weakSelf removeQueuedPromptAtIndex:index forChat:origin]; };
  chat.queueResumeHandler = ^{ origin.queuePaused = NO; [weakSelf drainPromptQueueForChat:origin]; [weakSelf updateControlStatesForChat:origin]; };
  chat.queueCancelEditHandler = ^{ [weakSelf finishQueuedPromptEditingSaving:NO forChat:origin]; };
  return chat;
}

- (TLChatTabController *)currentChatPresentation {
  if (!self.chatPresentation) self.chatPresentation = [self newChatTabController];
  return self.chatPresentation;
}

- (NSMutableArray<TLChatMessage *> *)messages { return [self currentChatPresentation].messages; }
- (void)setMessages:(NSMutableArray<TLChatMessage *> *)value { [self currentChatPresentation].messages = value; }
- (NSMapTable<TLChatMessage *, NSView *> *)messageRowViews { return [self currentChatPresentation].messageRowViews; }
- (void)setMessageRowViews:(NSMapTable<TLChatMessage *, NSView *> *)value { [self currentChatPresentation].messageRowViews = value; }
- (NSMapTable<TLChatMessage *, NSString *> *)messageRowSignatures { return [self currentChatPresentation].messageRowSignatures; }
- (void)setMessageRowSignatures:(NSMapTable<TLChatMessage *, NSString *> *)value { [self currentChatPresentation].messageRowSignatures = value; }
- (NSMapTable<TLChatMessage *, NSView *> *)messageMarkdownViews { return [self currentChatPresentation].messageMarkdownViews; }
- (void)setMessageMarkdownViews:(NSMapTable<TLChatMessage *, NSView *> *)value { [self currentChatPresentation].messageMarkdownViews = value; }
- (NSArray<TLChatMessage *> *)renderedMessages { return [self currentChatPresentation].renderedMessages; }
- (void)setRenderedMessages:(NSArray<TLChatMessage *> *)value { [self currentChatPresentation].renderedMessages = value; }
- (BOOL)isLoading { return [self currentChatPresentation].isLoading; }
- (void)setIsLoading:(BOOL)value { [self currentChatPresentation].isLoading = value; }
- (NSString *)errorMessage { return [self currentChatPresentation].errorMessage; }
- (void)setErrorMessage:(NSString *)value { [self currentChatPresentation].errorMessage = value; }
- (TLTokenView *)messagesBackground { return [self currentChatPresentation].messagesBackground; }
- (void)setMessagesBackground:(TLTokenView *)value { [self currentChatPresentation].messagesBackground = value; }
- (TLMessageInput *)messageInput { return [self currentChatPresentation].messageInput; }
- (void)setMessageInput:(TLMessageInput *)value { [self currentChatPresentation].messageInput = value; }
- (NSView *)chatWorkspace { return [self currentChatPresentation].chatWorkspace; }
- (void)setChatWorkspace:(NSView *)value { [self currentChatPresentation].chatWorkspace = value; }
- (NSLayoutConstraint *)messageInputWidthConstraint { return [self currentChatPresentation].messageInputWidthConstraint; }
- (void)setMessageInputWidthConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].messageInputWidthConstraint = value; }
- (NSScrollView *)messageScrollView { return [self currentChatPresentation].messageScrollView; }
- (void)setMessageScrollView:(NSScrollView *)value { [self currentChatPresentation].messageScrollView = value; }
- (TLFlippedView *)messageDocumentView { return [self currentChatPresentation].messageDocumentView; }
- (void)setMessageDocumentView:(TLFlippedView *)value { [self currentChatPresentation].messageDocumentView = value; }
- (NSStackView *)messageStack { return [self currentChatPresentation].messageStack; }
- (void)setMessageStack:(NSStackView *)value { [self currentChatPresentation].messageStack = value; }
- (NSLayoutConstraint *)messageStackBottomConstraint { return [self currentChatPresentation].messageStackBottomConstraint; }
- (void)setMessageStackBottomConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].messageStackBottomConstraint = value; }
- (NSLayoutConstraint *)messageStackMinimumBottomConstraint { return [self currentChatPresentation].messageStackMinimumBottomConstraint; }
- (void)setMessageStackMinimumBottomConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].messageStackMinimumBottomConstraint = value; }
- (NSTextView *)promptTextView { return [self currentChatPresentation].promptTextView; }
- (void)setPromptTextView:(NSTextView *)value { [self currentChatPresentation].promptTextView = value; }
- (TLInputSuggestionPanelView *)slashCommandListView { return [self currentChatPresentation].slashCommandListView; }
- (void)setSlashCommandListView:(TLInputSuggestionPanelView *)value { [self currentChatPresentation].slashCommandListView = value; }
- (TLInputSuggestionListView *)slashCommandScrollView { return [self currentChatPresentation].slashCommandScrollView; }
- (void)setSlashCommandScrollView:(TLInputSuggestionListView *)value { [self currentChatPresentation].slashCommandScrollView = value; }
- (NSTimer *)slashCommandUpdateTimer { return [self currentChatPresentation].slashCommandUpdateTimer; }
- (void)setSlashCommandUpdateTimer:(NSTimer *)value { [self currentChatPresentation].slashCommandUpdateTimer = value; }
- (BOOL)renderingSlashCommands { return [self currentChatPresentation].renderingSlashCommands; }
- (void)setRenderingSlashCommands:(BOOL)value { [self currentChatPresentation].renderingSlashCommands = value; }
- (NSArray<NSDictionary<NSString *, NSString *> *> *)visibleSlashCommands { return [self currentChatPresentation].visibleSlashCommands; }
- (void)setVisibleSlashCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)value { [self currentChatPresentation].visibleSlashCommands = value; }
- (NSInteger)selectedSlashCommandIndex { return [self currentChatPresentation].selectedSlashCommandIndex; }
- (void)setSelectedSlashCommandIndex:(NSInteger)value { [self currentChatPresentation].selectedSlashCommandIndex = value; }
- (NSLayoutConstraint *)slashCommandListWidthConstraint { return [self currentChatPresentation].slashCommandListWidthConstraint; }
- (void)setSlashCommandListWidthConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].slashCommandListWidthConstraint = value; }
- (NSLayoutConstraint *)slashCommandListHeightConstraint { return [self currentChatPresentation].slashCommandListHeightConstraint; }
- (void)setSlashCommandListHeightConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].slashCommandListHeightConstraint = value; }
- (NSLayoutConstraint *)slashCommandListBottomConstraint { return [self currentChatPresentation].slashCommandListBottomConstraint; }
- (void)setSlashCommandListBottomConstraint:(NSLayoutConstraint *)value { [self currentChatPresentation].slashCommandListBottomConstraint = value; }
- (BOOL)streamingRenderScheduled { return [self currentChatPresentation].streamingRenderScheduled; }
- (void)setStreamingRenderScheduled:(BOOL)value { [self currentChatPresentation].streamingRenderScheduled = value; }
- (NSUInteger)streamingRenderGeneration { return [self currentChatPresentation].streamingRenderGeneration; }
- (void)setStreamingRenderGeneration:(NSUInteger)value { [self currentChatPresentation].streamingRenderGeneration = value; }
- (TLGlassButton *)sendButton { return [self currentChatPresentation].sendButton; }
- (void)setSendButton:(TLGlassButton *)value { [self currentChatPresentation].sendButton = value; }
- (TLASCIIPlanetScreensaverView *)screensaverView { return [self currentChatPresentation].screensaverView; }
- (void)setScreensaverView:(TLASCIIPlanetScreensaverView *)value { [self currentChatPresentation].screensaverView = value; }

- (TLChatRecord *)activeChat { return [self currentChatPresentation].chat; }
- (void)setActiveChat:(TLChatRecord *)chat {
  TLChatRecord *previous = self.activeChat;
  if (!self.attachmentDrafts) self.attachmentDrafts = [NSMutableDictionary dictionary];
  if (!self.attachmentPromptDrafts) self.attachmentPromptDrafts = [NSMutableDictionary dictionary];
  if (!self.chatPresentations) self.chatPresentations = [NSMutableDictionary dictionary];
  if (previous && chat && previous.chatID == chat.chatID) {
    self.chatPresentation.chat = chat;
    return;
  }
  [self hideSlashCommandList];
  if (previous) {
    self.attachmentDrafts[@(previous.chatID)] = self.messageInput.attachmentURLs ?: @[];
    self.attachmentPromptDrafts[@(previous.chatID)] = self.promptTextView.string ?: @"";
    if (previous.chatID <= 0) {
      if (!self.modelDraftChats) self.modelDraftChats = [NSMutableDictionary dictionary];
      self.modelDraftChats[@(previous.chatID)] = previous;
    }
  }
  if (chat) {
    TLChatTabController *next = self.chatPresentations[@(chat.chatID)];
    if (!next) next = previous ? [self newChatTabController] : [self currentChatPresentation];
    self.chatPresentation = next;
    if (!next.chatWorkspace && self.contentHost) {
      self.chatWorkspace = [self buildChatWorkspace];
      self.messagesBackground.fillColor = self.palette.tabBackground;
      [self addWorkspaceContentView:self.chatWorkspace];
    }
    self.chatPresentations[@(chat.chatID)] = next;
  }
  self.chatPresentation.chat = chat;
  self.promptTextView.string = chat ? self.attachmentPromptDrafts[@(chat.chatID)] ?: @"" : @"";
  [self.messageInput setAttachmentURLs:chat ? self.attachmentDrafts[@(chat.chatID)] ?: @[] : @[] animated:NO];
}

- (BOOL)activateCachedChatWithID:(NSInteger)chatID {
  TLChatTabController *presentation = self.chatPresentations[@(chatID)];
  if (!presentation.chat) return NO;
  self.activeChat = presentation.chat;
  if (![self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID])
    [self addChatToSessionIfNeeded:chatID activate:YES];
  [self activateTabKind:TLWorkspaceTabKindChat tabID:chatID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  if (presentation.chatWorkspace) [self renderMessagesScrollingToBottom:NO];
  [self updateControlStates];
  return YES;
}

// Background updates never change keyboard focus or the selected workspace tab.
- (void)restoreAttachmentDraft:(NSArray<NSURL *> *)URLs prompt:(NSString *)prompt chatID:(NSInteger)chatID {
  self.attachmentDrafts[@(chatID)] = URLs;
  self.attachmentPromptDrafts[@(chatID)] = [prompt copy];
  TLChatTabController *presentation = self.chatPresentations[@(chatID)];
  {
    TLChatTabController *originChat = presentation;
    if (originChat) {
      originChat.messageInput.attachmentURLs = URLs;
      originChat.promptTextView.string = prompt;
      [originChat.messageInput recalculateHeight];
      [self updateControlStatesForChat:originChat];
    }
  }
}


- (void)allowHorizontalWindowExpansionForView:(NSView *)view {
  [view setContentHuggingPriority:NSLayoutPriorityDefaultLow
                   forOrientation:NSLayoutConstraintOrientationHorizontal];
  [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
}

- (BOOL)isIncognito { return [self.database respondsToSelector:@selector(isIncognito)] && self.database.incognito; }

- (instancetype)initWithDatabase:(TLDatabase *)database
                agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator
                  appStateManager:(TLAppStateManager *)appStateManager {
  TLThemePalette *initialPalette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSRect frame = NSMakeRect(0, 0, initialPalette.windowInitialWidth, initialPalette.windowInitialHeight);
  NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:frame
                                                     styleMask:styleMask
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
  window.title = @"Talaria";
  window.titleVisibility = NSWindowTitleHidden;
  window.titlebarAppearsTransparent = YES;
  window.opaque = NO;
  window.backgroundColor = initialPalette.appBackground;
  window.hasShadow = YES;
  window.minSize = NSMakeSize(initialPalette.windowMinimumWidth, initialPalette.windowMinimumHeight);
  window.contentMinSize = NSMakeSize(initialPalette.windowMinimumWidth, initialPalette.windowMinimumHeight);
  window.maxSize = NSMakeSize(100000.0, 100000.0);
  window.contentMaxSize = NSMakeSize(100000.0, 100000.0);
  window.releasedWhenClosed = NO;
  [window center];

  self = [super initWithWindow:window];
  if (self) {
    _database = database;
    _agentOrchestrator = agentOrchestrator;
    _turnRunners = [NSMutableDictionary dictionary];
    _turnMessagesByChat = [NSMutableDictionary dictionary];
    _chatIconGenerator = [[TLChatIconGenerator alloc] initWithAgentOrchestrator:agentOrchestrator];
    _appStateManager = appStateManager ?: [[TLAppStateManager alloc] init];
    _appStateSubscriptions = [NSMutableArray array];
    _workspaceTabRuntimes = [NSMutableDictionary dictionary];
    _chatIconRequests = [NSMutableSet set];
    _settings = [TLAppSettings defaultSettings];
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _sidebarPreferredWidth = _palette.sidebarWidth;
    _chats = [NSMutableArray array];
    _agents = [NSMutableArray array];
    _nextBrowserTabID = 1;
    _nextDraftChatID = -1;
    self.messages = [NSMutableArray array];
    self.messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
    self.messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
    self.messageMarkdownViews = [NSMapTable strongToStrongObjectsMapTable];
    self.chatPresentation.messageActivityViews = [NSMapTable strongToStrongObjectsMapTable];
    self.errorMessage = @"";
    _sidebarVisible = !database.incognito;
    if (database.incognito) {
      window.title = @"Talaria — Incognito";
      [TLWebKitBrowserController.sharedController markWindowIncognito:window];
    }
    _widgetbookMode = TLWidgetbookModeEnabled();
    if (_widgetbookMode) {
      window.title = @"Talaria Widgetbook";
    }
    window.delegate = self;
    [self buildInterface];
    [self installAppStateBindings];
    [self loadInitialState];
    [self installEffectiveAppearanceObserver];
    if (!database.incognito) {
    _notchOverlayController = [[TLNotchOverlayController alloc] initWithPalette:_palette
                                                                         target:self
                                                                         action:@selector(openFromNotchOverlay:)];
    __weak typeof(self) weakSelf = self;
    _notchOverlayController.fileDropHandler = ^(NSArray<NSURL *> *fileURLs) {
      [weakSelf handleFileURLsDroppedOnNotch:fileURLs];
    };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationPreferencesChanged:)
      name:TLApplicationPreferencesDidChangeNotification object:TLApplicationPreferences.sharedPreferences];
    TLApplicationPreferences.sharedPreferences.quickInputHandler = ^{ [weakSelf openFromNotchOverlay:nil]; };
    [self applicationPreferencesChanged:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(notificationsDidActivate:)
      name:NSApplicationDidBecomeActiveNotification object:nil];
    [self startNotifications];
    }
  }
  return self;
}

- (void)dealloc {
  [self.notificationsTimer invalidate];
  [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidBecomeActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter removeObserver:self name:TLApplicationPreferencesDidChangeNotification object:nil];
  [self.debugTerminalStateTimer invalidate];
  if (self.effectiveAppearanceObserverInstalled) {
    [NSApp removeObserver:self
               forKeyPath:@"effectiveAppearance"
                  context:TLEffectiveAppearanceObservationContext];
  }
  for (TLAppStateSubscription *subscription in self.appStateSubscriptions) {
    [subscription cancel];
  }
  [self.notchOverlayController stopTracking];
  for (TLWorkspaceTab *browserTab in [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser]) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:browserTab];
    [runtime.featureController close];
  }
  if (self.paneFocusMonitor) [NSEvent removeMonitor:self.paneFocusMonitor];
  if (self.messageScrollWheelMonitor) {
    [NSEvent removeMonitor:self.messageScrollWheelMonitor];
  }
  if (self.messageContextMenuMonitor) {
    [NSEvent removeMonitor:self.messageContextMenuMonitor];
  }
}

- (void)installEffectiveAppearanceObserver {
  if (self.effectiveAppearanceObserverInstalled) {
    return;
  }

  [NSApp addObserver:self
          forKeyPath:@"effectiveAppearance"
             options:NSKeyValueObservingOptionNew
             context:TLEffectiveAppearanceObservationContext];
  self.effectiveAppearanceObserverInstalled = YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if (context == TLEffectiveAppearanceObservationContext) {
    [self handleEffectiveAppearanceChanged];
    return;
  }

  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)handleEffectiveAppearanceChanged {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self applyTheme];
  });
}

- (void)installAppStateBindings {
  __weak typeof(self) weakSelf = self;
  void (^handleTabsChanged)(TLAppSignal *, TLAppStateSnapshot *) = ^(TLAppSignal *signal, TLAppStateSnapshot *snapshot) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if ([signal.name isEqual:TLAppSignalWorkspaceTabRemoved]) {
      TLWorkspaceSplitGroup *closingGroup = [strongSelf.splitState groupForTab:strongSelf.displayedWorkspaceTab];
      if (closingGroup && ![strongSelf tabWithPresentationIdentity:TLWorkspaceTabIdentity(strongSelf.displayedWorkspaceTab)]) {
        for (NSString *identity in closingGroup.identities) {
          TLWorkspaceTab *survivor = [strongSelf tabWithPresentationIdentity:identity];
          if (survivor) { [strongSelf activateTabKind:survivor.kind tabID:survivor.tabID]; break; }
        }
      }
      [strongSelf.splitState reconcileTabs:snapshot.workspaceTabs];
    }
    [strongSelf reloadWorkspaceTabs];
  };

  for (TLAppSignalName signalName in @[
    TLAppSignalWorkspaceTabActivated,
    TLAppSignalWorkspaceTabsChanged,
    TLAppSignalWorkspaceTabAdded,
    TLAppSignalWorkspaceTabRemoved,
    TLAppSignalWorkspaceTabMoved,
  ]) {
    TLAppStateSubscription *subscription = [self.appStateManager subscribeToSignal:signalName handler:handleTabsChanged];
    [self.appStateSubscriptions addObject:subscription];
  }
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  if (self.incognito) {
    for (TLAssistantTurnRunner *runner in self.turnRunners.allValues) [runner cancel];
    [self.agentOrchestrator closeIncognito];
    for (TLWorkspaceTabRuntime *runtime in self.workspaceTabRuntimes.allValues) [runtime.featureController close];
    [TLWebKitBrowserController.sharedController forgetIncognitoWindow:sender];
    [self.closedWorkspaceTabs removeAllObjects];
    [self.messages removeAllObjects];
    if (self.incognitoDidClose) self.incognitoDidClose();
    return YES;
  }
  [sender orderOut:self];
  return NO;
}

- (NSUInteger)activeWorkspaceTabIndex {
  return [[self workspaceTabsForTabsController:self.workspaceTabsController] indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *tab, NSUInteger index, BOOL *stop) {
    return [self workspaceTabsController:self.workspaceTabsController isTabActive:tab];
  }];
}

- (BOOL)canPerformTabCommand:(TLTabCommand)command {
  if (self.widgetbookMode) return NO;
  NSUInteger count = [self workspaceTabsForTabsController:self.workspaceTabsController].count;
  NSUInteger index = [self activeWorkspaceTabIndex];
  if (command >= TLTabCommandSelectFirst && command <= TLTabCommandSelectLast) {
    return command == TLTabCommandSelectLast ? count > 0 : (NSUInteger)(command - TLTabCommandSelectFirst) < count;
  }
  switch (command) {
    case TLTabCommandNew:
    case TLTabCommandCloseWindow: return YES;
    case TLTabCommandClose: return count <= 1 || (index != NSNotFound && [self activeWorkspaceTab].closeable);
    case TLTabCommandReopen: return self.closedWorkspaceTabs.count > 0;
    case TLTabCommandNext:
    case TLTabCommandPrevious: return count > 1;
    case TLTabCommandMoveLeft: return index != NSNotFound && index > 0;
    case TLTabCommandMoveRight: return index != NSNotFound && index + 1 < count;
    default: return NO;
  }
}

- (void)selectWorkspaceTabAtIndex:(NSUInteger)index {
  NSArray<TLWorkspaceTab *> *tabs = [self workspaceTabsForTabsController:self.workspaceTabsController];
  if (index >= tabs.count || index == [self activeWorkspaceTabIndex]) return;
  TLWorkspaceTab *tab = tabs[index];
  SEL action = [self runtimeForTab:tab].openAction;
  if (!action) return;
  NSButton *sender = [[NSButton alloc] init];
  sender.tag = tab.tabID;
  [NSApp sendAction:action to:self from:sender];
}

- (void)performTabCommand:(TLTabCommand)command {
  if (![self canPerformTabCommand:command]) return;
  NSUInteger count = [self workspaceTabsForTabsController:self.workspaceTabsController].count;
  NSUInteger index = [self activeWorkspaceTabIndex];
  if (command >= TLTabCommandSelectFirst && command <= TLTabCommandSelectLast) {
    [self selectWorkspaceTabAtIndex:command == TLTabCommandSelectLast ? count - 1 : command - TLTabCommandSelectFirst];
    return;
  }
  switch (command) {
    case TLTabCommandNew: [self startNewChatFromButton:self]; break;
    case TLTabCommandClose: [self closeActiveTabOrWindow:self]; break;
    case TLTabCommandCloseWindow: [self.window performClose:self]; break;
    case TLTabCommandReopen: [self reopenLastClosedWorkspaceTab]; break;
    case TLTabCommandNext:
      [self selectWorkspaceTabAtIndex:index == NSNotFound ? 0 : (index + 1) % count]; break;
    case TLTabCommandPrevious:
      [self selectWorkspaceTabAtIndex:index == NSNotFound ? count - 1 : (index + count - 1) % count]; break;
    case TLTabCommandMoveLeft:
    case TLTabCommandMoveRight:
      [self workspaceTabsController:self.workspaceTabsController moveTab:[self activeWorkspaceTab]
                            toIndex:command == TLTabCommandMoveLeft ? index - 1 : index + 1];
      break;
    default: break;
  }
}

- (void)rememberClosedWorkspaceTab:(TLWorkspaceTab *)tab {
  TLClosedWorkspaceTab *closed = [[TLClosedWorkspaceTab alloc] init];
  closed.tab = tab;
  closed.index = [[self workspaceTabs] indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *candidate, NSUInteger index, BOOL *stop) {
    return candidate.kind == tab.kind && candidate.tabID == tab.tabID;
  }];
  if (closed.index == NSNotFound) return;
  if (tab.kind == TLWorkspaceTabKindChat && self.activeChat.chatID == tab.tabID) {
    closed.prompt = self.promptTextView.string;
    if (tab.tabID <= 0) closed.draftChat = self.activeChat;
  }
  if (!self.closedWorkspaceTabs) self.closedWorkspaceTabs = [NSMutableArray array];
  [self.closedWorkspaceTabs addObject:closed];
  // Keep only lightweight metadata; closed browsers release their live session.
  if (self.closedWorkspaceTabs.count > 50) [self.closedWorkspaceTabs removeObjectAtIndex:0];
}

- (void)reopenLastClosedWorkspaceTab {
  TLClosedWorkspaceTab *closed = self.closedWorkspaceTabs.lastObject;
  if (!closed) return;
  [self.closedWorkspaceTabs removeLastObject];
  TLWorkspaceTab *tab = closed.tab;
  switch (tab.kind) {
    case TLWorkspaceTabKindChat:
      if (tab.tabID <= 0) {
        [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:self.chatWorkspace
          openAction:@selector(openChatTab:) closeAction:@selector(closeChatTab:)] forTab:tab];
        [self.appStateManager addWorkspaceTab:tab activate:NO];
      }
      [self loadChatWithID:tab.tabID];
      if (self.activeChat.chatID == tab.tabID) {
        if (closed.draftChat) self.activeChat = closed.draftChat;
        if (closed.prompt) self.promptTextView.string = closed.prompt;
        [self updateControlStates];
      }
      break;
    case TLWorkspaceTabKindBrowser:
      [self openBrowserTabWithURL:tab.URL];
      tab = [self activeWorkspaceTab];
      break;
    case TLWorkspaceTabKindHistory: [self showHistoryScreen:self]; break;
    case TLWorkspaceTabKindSettings: [self showSettings:self]; break;
    case TLWorkspaceTabKindAgents: [self showAgents:self]; break;
    case TLWorkspaceTabKindDebug: [self showDebug:self]; break;
    case TLWorkspaceTabKindDownloads: [self showDownloads:self]; break;
    case TLWorkspaceTabKindAutomations: [self showAutomations:self]; break;
  }
  if (tab && [self.appStateManager hasWorkspaceTabWithKind:tab.kind tabID:tab.tabID]) {
    [self.appStateManager moveWorkspaceTabWithKind:tab.kind tabID:tab.tabID
                          toIndex:MIN(closed.index, [self workspaceTabs].count - 1)];
    [self renderWorkspaceTabs];
  }
}

- (TLBrowserTabController *)activeBrowserController {
  TLWorkspaceTab *tab = [self activeWorkspaceTab];
  if (self.widgetbookMode || tab.kind != TLWorkspaceTabKindBrowser) return nil;
  id controller = [self runtimeForTab:tab].featureController;
  return [controller isKindOfClass:TLBrowserTabController.class] && ![controller isClosed] ? controller : nil;
}
- (id<TLFindActionTarget>)activeFindTarget {
  TLWorkspaceTab *tab = [self activeWorkspaceTab];
  if (self.widgetbookMode) return nil;
  if (tab.kind == TLWorkspaceTabKindChat) return self.chatPresentations[@(tab.tabID)];
  return [self activeBrowserController];
}
- (BOOL)canPerformFindAction:(NSTextFinderAction)action {
  id<TLFindActionTarget> controller = [self activeFindTarget];
  if (!controller) return NO;
  if (action == NSTextFinderActionHideFindInterface) return controller.findBarVisible;
  return action == NSTextFinderActionShowFindInterface || action == NSTextFinderActionNextMatch || action == NSTextFinderActionPreviousMatch;
}
- (void)performFindAction:(NSTextFinderAction)action {
  if (![self canPerformFindAction:action]) return;
  id<TLFindActionTarget> controller = [self activeFindTarget];
  switch (action) {
    case NSTextFinderActionShowFindInterface: [controller showFindBar]; break;
    case NSTextFinderActionNextMatch: [controller findNext:YES]; break;
    case NSTextFinderActionPreviousMatch: [controller findNext:NO]; break;
    case NSTextFinderActionHideFindInterface: [controller hideFindBar]; break;
    default: break;
  }
}

- (void)closeActiveTabOrWindow:(id)sender {
  NSArray<TLWorkspaceTab *> *tabs = [self workspaceTabsForTabsController:self.workspaceTabsController];
  if (tabs.count <= 1) {
    [self.window performClose:sender];
    return;
  }

  TLWorkspaceTab *activeTab = [self activeWorkspaceTab];
  if ([self.splitState groupForTab:activeTab]) {
    NSMenuItem *groupSender = [NSMenuItem new]; groupSender.representedObject = activeTab;
    [self closeSplitTab:groupSender]; return;
  }
  TLWorkspaceTabRuntime *runtime = [self runtimeForTab:activeTab];
  if (!activeTab || !runtime.closeAction) {
    return;
  }

  NSButton *closeSender = [[NSButton alloc] init];
  closeSender.tag = activeTab.tabID;
  [NSApp sendAction:runtime.closeAction to:self from:closeSender];
}

- (void)showWindow:(id)sender {
  [self.quickInputController dismiss];
  [NSApp unhide:nil];
  [super showWindow:sender];
  [self.window deminiaturize:sender];
  [self.window makeKeyAndOrderFront:sender];
  [self.window orderFrontRegardless];
  [self layoutTrafficLightButtons];
  if (!self.isSending && self.promptTextView && [self isChatWorkspaceActive]) {
    [self.window makeFirstResponder:self.promptTextView];
  }
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
  [self updateMessageInputWidthForWindowWidth:NSWidth(self.window.frame)];
}

- (void)windowDidResize:(NSNotification *)notification {
  [self layoutTrafficLightButtons];
  [self updateSidebarLayoutAnimated:NO];
  [self updateMessageInputWidthForWindowWidth:NSWidth(self.window.frame)];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
  [self prepareResponsiveLayoutForWindowWidth:frameSize.width];
  return frameSize;
}

- (void)buildInterface {
  self.rootView = [[TLTokenView alloc] init];
  self.rootView.translatesAutoresizingMaskIntoConstraints = YES;
  self.rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self allowHorizontalWindowExpansionForView:self.rootView];
  self.window.contentView = self.rootView;

  self.frostedBackgroundView = [[NSVisualEffectView alloc] init];
  self.frostedBackgroundView.frame = self.rootView.bounds;
  self.frostedBackgroundView.translatesAutoresizingMaskIntoConstraints = YES;
  self.frostedBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self allowHorizontalWindowExpansionForView:self.frostedBackgroundView];
  self.frostedBackgroundView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
  self.frostedBackgroundView.material = NSVisualEffectMaterialUnderWindowBackground;
  self.frostedBackgroundView.state = NSVisualEffectStateActive;
  [self.rootView addSubview:self.frostedBackgroundView];

  self.frostedOverlayView = [[TLTokenView alloc] init];
  self.frostedOverlayView.frame = self.rootView.bounds;
  self.frostedOverlayView.translatesAutoresizingMaskIntoConstraints = YES;
  self.frostedOverlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self allowHorizontalWindowExpansionForView:self.frostedOverlayView];
  [self.rootView addSubview:self.frostedOverlayView];

  NSView *workspace = [self buildWorkspace];
  workspace.frame = self.rootView.bounds;
  workspace.translatesAutoresizingMaskIntoConstraints = YES;
  workspace.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self.rootView addSubview:workspace];

  [self applyTheme];
}

- (NSView *)buildHistoryPanel {
  self.historyPanelController = [[TLHistoryPanelController alloc] initWithPalette:self.palette];
  self.historyPanelController.delegate = self;
  return self.historyPanelController.panelView;
}

- (NSView *)buildWorkspace {
  NSView *workspace = [[NSView alloc] init];
  workspace.translatesAutoresizingMaskIntoConstraints = NO;
  [self allowHorizontalWindowExpansionForView:workspace];

  self.sidebarView = [[TLTokenView alloc] init];
  self.sidebarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.sidebarView.wantsLayer = YES;
  self.sidebarView.layer.masksToBounds = YES;
  self.sidebarView.canDragWindow = YES;
  self.sidebarView.hidden = self.incognito;
  [self allowHorizontalWindowExpansionForView:self.sidebarView];
  self.sidebarWidthConstraint = [self.sidebarView.widthAnchor constraintEqualToConstant:[self currentSidebarContentWidth]];
  self.sidebarTileGrid = [self buildSidebarTileGrid];
  self.sidebarInboxStack = [self buildSidebarInboxStack];
  self.sidebarActionStack = [self buildSidebarActionStack];
  self.sidebarResizeHandle = [[TLSidebarResizeHandle alloc] init];
  self.sidebarResizeHandle.target = self;
  self.sidebarResizeHandle.action = @selector(resizeSidebar:);
  self.sidebarResizeHandle.hidden = !self.sidebarVisible;
  [self.sidebarView addSubview:self.sidebarTileGrid];
  [self.sidebarView addSubview:self.sidebarInboxStack];
  [self.sidebarView addSubview:self.sidebarActionStack];

  NSView *topbar = [self buildTopbar];
  self.contentShadowView = [[TLTokenView alloc] init];
  self.contentShadowView.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentShadowView.wantsLayer = YES;
  self.contentShadowView.layer.masksToBounds = NO;
  [self allowHorizontalWindowExpansionForView:self.contentShadowView];

  self.contentHost = [[TLTokenView alloc] init];
  self.contentHost.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentHost.wantsLayer = YES;
  self.contentHost.layer.masksToBounds = YES;
  [self allowHorizontalWindowExpansionForView:self.contentHost];
  [workspace addSubview:self.sidebarView];
  [workspace addSubview:self.contentShadowView];
  [workspace addSubview:topbar];
  [workspace addSubview:self.sidebarResizeHandle];
  [self.contentShadowView addSubview:self.contentHost];
  self.workspaceOutline = [[TLWorkspaceOutlineView alloc] init];
  self.workspaceOutline.incognito = self.incognito;
  self.workspaceOutline.translatesAutoresizingMaskIntoConstraints = NO;
  self.workspaceOutline.layer.zPosition = 11.0;
  self.workspaceOutline.contentView = self.contentHost;
  self.workspaceOutline.selectionView = self.workspaceTabsController.selectionView;
  [workspace addSubview:self.workspaceOutline];
  [NSLayoutConstraint activateConstraints:@[
    [self.workspaceOutline.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor],
    [self.workspaceOutline.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor],
    [self.workspaceOutline.topAnchor constraintEqualToAnchor:workspace.topAnchor],
    [self.workspaceOutline.bottomAnchor constraintEqualToAnchor:workspace.bottomAnchor],
  ]];
  __weak TLWorkspaceOutlineView *outline = self.workspaceOutline;
  __weak typeof(self) colorOwner = self;
  self.workspaceTabsController.selectionView.geometryChanged = ^{
    [outline updateOutline];
    [colorOwner updateBrowserTabColorSample];
  };
  self.contentLeadingConstraint = [self.contentShadowView.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor
                                                                                       constant:[self contentLeadingOffsetForSidebarWidth:[self currentSidebarWidth]]];
  self.sidebarActionStackLeadingConstraint =
    [self.sidebarActionStack.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor
                                                           constant:self.palette.sidebarActionStackLeadingInset];
  self.sidebarActionStackTrailingConstraint =
    [self.sidebarActionStack.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor
                                                            constant:-self.palette.sidebarActionStackTrailingInset];
  self.sidebarActionStackHeightConstraint =
    [self.sidebarActionStack.heightAnchor constraintEqualToConstant:[self sidebarActionStackHeight]];
  self.sidebarTileGridLeadingConstraint =
    [self.sidebarTileGrid.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor
                                                       constant:self.palette.sidebarContentLeadingInset];
  self.sidebarTileGridTrailingConstraint =
    [self.sidebarTileGrid.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor
                                                        constant:-self.palette.sidebarContentTrailingInset];
  self.sidebarInboxLeadingConstraint =
    [self.sidebarInboxStack.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor
                                                         constant:self.palette.sidebarInboxOuterHorizontalInset];
  self.sidebarInboxTrailingConstraint =
    [self.sidebarInboxStack.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor
                                                          constant:-self.palette.sidebarInboxOuterHorizontalInset];
  NSArray<NSLayoutConstraint *> *sidebarContentHorizontalConstraints = @[
    self.sidebarTileGridLeadingConstraint,
    self.sidebarTileGridTrailingConstraint,
    self.sidebarInboxLeadingConstraint,
    self.sidebarInboxTrailingConstraint,
    self.sidebarActionStackLeadingConstraint,
    self.sidebarActionStackTrailingConstraint,
  ];
  for (NSLayoutConstraint *constraint in sidebarContentHorizontalConstraints) {
    constraint.priority = NSLayoutPriorityDefaultHigh;
  }

  [NSLayoutConstraint activateConstraints:@[
    [self.sidebarView.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor],
    [self.sidebarView.topAnchor constraintEqualToAnchor:workspace.topAnchor],
    [self.sidebarView.bottomAnchor constraintEqualToAnchor:workspace.bottomAnchor],
    self.sidebarWidthConstraint,
    self.sidebarTileGridLeadingConstraint,
    self.sidebarTileGridTrailingConstraint,
    [self.sidebarTileGrid.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor constant:self.palette.topbarHeight + self.palette.space8],
    [self.sidebarTileGrid.heightAnchor constraintEqualToConstant:self.palette.space12 + self.palette.space10],
    self.sidebarInboxLeadingConstraint,
    self.sidebarInboxTrailingConstraint,
    [self.sidebarInboxStack.topAnchor constraintEqualToAnchor:self.sidebarTileGrid.bottomAnchor constant:self.palette.space10],
    [self.sidebarInboxStack.bottomAnchor constraintEqualToAnchor:self.sidebarActionStack.topAnchor constant:-self.palette.space8],
    self.sidebarActionStackLeadingConstraint,
    self.sidebarActionStackTrailingConstraint,
    self.sidebarActionStackHeightConstraint,
    [self.sidebarActionStack.bottomAnchor constraintEqualToAnchor:self.sidebarView.bottomAnchor constant:-self.palette.space8],
    [topbar.leadingAnchor constraintEqualToAnchor:workspace.leadingAnchor],
    [topbar.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor],
    [topbar.topAnchor constraintEqualToAnchor:workspace.topAnchor],
    self.contentLeadingConstraint,
    [self.contentShadowView.trailingAnchor constraintEqualToAnchor:workspace.trailingAnchor constant:-self.palette.space4],
    [self.contentShadowView.topAnchor constraintEqualToAnchor:topbar.bottomAnchor],
    [self.contentShadowView.bottomAnchor constraintEqualToAnchor:workspace.bottomAnchor constant:-self.palette.space4],
    [self.sidebarResizeHandle.centerXAnchor constraintEqualToAnchor:self.contentShadowView.leadingAnchor],
    [self.sidebarResizeHandle.topAnchor constraintEqualToAnchor:self.contentShadowView.topAnchor],
    [self.sidebarResizeHandle.bottomAnchor constraintEqualToAnchor:self.contentShadowView.bottomAnchor],
    [self.sidebarResizeHandle.widthAnchor constraintEqualToConstant:self.palette.space3],
    [self.contentHost.leadingAnchor constraintEqualToAnchor:self.contentShadowView.leadingAnchor],
    [self.contentHost.trailingAnchor constraintEqualToAnchor:self.contentShadowView.trailingAnchor],
    [self.contentHost.topAnchor constraintEqualToAnchor:self.contentShadowView.topAnchor],
    [self.contentHost.bottomAnchor constraintEqualToAnchor:self.contentShadowView.bottomAnchor],
  ]];

  [self installSplitWorkspace];
  self.chatWorkspace = [self buildChatWorkspace];
  NSView *historyScreen = [self buildHistoryPanel];
  [self addWorkspaceContentView:self.chatWorkspace];
  [self addWorkspaceContentView:historyScreen];

  [self updateSidebarLayoutAnimated:NO];
  [self updateWorkspaceMode];
  return workspace;
}

- (NSStackView *)buildSidebarTileGrid {
  TLHoverStackView *tileGrid = [[TLHoverStackView alloc] init];
  tileGrid.translatesAutoresizingMaskIntoConstraints = NO;
  tileGrid.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  tileGrid.alignment = NSLayoutAttributeCenterY;
  tileGrid.distribution = NSStackViewDistributionFill;
  tileGrid.spacing = self.palette.space5;

  __weak typeof(self) weakSelf = self;
  tileGrid.hoverChanged = ^(BOOL hovered) {
    if (hovered) {
      [weakSelf showSidebarAgentPane];
    } else {
      [weakSelf scheduleSidebarAgentPaneDismissal];
    }
  };
  return tileGrid;
}

- (NSImage *)avatarImageForAgent:(TLAgentRecord *)agent {
  CGFloat size = self.palette.agentMenuAvatarSize;
  NSAttributedString *emoji = [[NSAttributedString alloc] initWithString:agent.avatar.length ? agent.avatar : @"🤖"
    attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:self.palette.space16]}];
  return [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
    NSSize textSize = emoji.size;
    [emoji drawAtPoint:NSMakePoint((NSWidth(bounds) - textSize.width) / 2,
                                   (NSHeight(bounds) - textSize.height) / 2)];
    return YES;
  }];
}

- (void)rebuildSidebarAgents {
  if (!self.sidebarTileGrid) return;
  [self.sidebarAgentPaneSurface removeFromSuperview];
  self.sidebarAgentPaneSurface = nil;
  self.sidebarAgentPane = nil;
  for (NSView *view in self.sidebarTileGrid.arrangedSubviews.copy) {
    [self.sidebarTileGrid removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.drawsBackground = NO;
  scroll.hasHorizontalScroller = YES;
  scroll.autohidesScrollers = YES;
  NSStackView *tiles = [[NSStackView alloc] init];
  tiles.translatesAutoresizingMaskIntoConstraints = NO;
  tiles.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  tiles.alignment = NSLayoutAttributeCenterY;
  tiles.spacing = self.palette.space5;
  NSInteger currentID = self.database.currentAgentID;
  TLIconTileView *currentTile = nil;
  for (TLAgentRecord *agent in self.agents) {
    TLIconTileView *tile = [[TLIconTileView alloc] init];
    tile.palette = self.palette;
    tile.image = [self avatarImageForAgent:agent];
    tile.imageSize = self.palette.space12 + self.palette.space2;
    tile.selected = agent.agentID == currentID;
    tile.toolTip = [NSString stringWithFormat:@"%@%@ — Local Hermes", agent.name, tile.selected ? @" (Current)" : @""];
    tile.accessibilityLabel = tile.toolTip;
    tile.accessibilitySelected = tile.selected;
    tile.tag = agent.agentID;
    tile.target = self;
    tile.action = @selector(activateSidebarAgent:);
    [tiles addArrangedSubview:tile];
    [tile.widthAnchor constraintEqualToConstant:self.palette.sidebarAgentTileMaximumWidth].active = YES;
    [tile.heightAnchor constraintEqualToAnchor:tiles.heightAnchor].active = YES;
    if (tile.selected) currentTile = tile;
  }
  scroll.documentView = tiles;
  [self.sidebarTileGrid addArrangedSubview:scroll];
  [scroll.widthAnchor constraintEqualToAnchor:self.sidebarTileGrid.widthAnchor].active = YES;
  [scroll.heightAnchor constraintEqualToAnchor:self.sidebarTileGrid.heightAnchor].active = YES;
  [tiles.heightAnchor constraintEqualToAnchor:scroll.contentView.heightAnchor].active = YES;
  [self.sidebarTileGrid layoutSubtreeIfNeeded];
  if (currentTile) [tiles scrollRectToVisible:currentTile.frame];
}

- (void)activateSidebarAgent:(NSControl *)sender {
  if (self.hasSendingTurns) return;
  NSError *error = nil;
  if (![self.database setCurrentAgentID:sender.tag error:&error]) {
    [self presentErrorMessage:error.localizedDescription];
    return;
  }
  self.settings = [self.database appSettings:nil] ?: self.settings;
  [self refreshAgents];
}

- (void)showSidebarAgentPane {
  if (self.sidebarAgentPane || !self.window.isKeyWindow || self.sidebarTileGrid.hidden) {
    return;
  }
  TLHoverStackView *pane = [[TLHoverStackView alloc] init];
  pane.translatesAutoresizingMaskIntoConstraints = NO;
  pane.orientation = NSUserInterfaceLayoutOrientationVertical;
  pane.alignment = NSLayoutAttributeLeading;
  pane.distribution = NSStackViewDistributionFill;
  pane.spacing = self.palette.space2;
  pane.edgeInsets = NSEdgeInsetsMake(self.palette.space3, self.palette.space3,
                                     self.palette.space5, self.palette.space3);
  NSInteger currentID = self.database.currentAgentID;
  for (TLAgentRecord *agent in self.agents) {
    NSString *title = [NSString stringWithFormat:@"%@  %@%@", agent.avatar, agent.name,
      agent.agentID == currentID ? @"  ✓" : @""];
    NSButton *row = [NSButton buttonWithTitle:title target:self action:@selector(activateSidebarAgent:)];
    row.tag = agent.agentID;
    row.bordered = NO;
    row.alignment = NSTextAlignmentLeft;
    row.font = self.palette.labelFont;
    row.contentTintColor = self.palette.appText;
    row.enabled = !self.hasSendingTurns;
    row.toolTip = [NSString stringWithFormat:@"%@ — Local Hermes%@", agent.name,
      agent.agentID == currentID ? @" (Current)" : @""];
    [pane addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:self.palette.settingsActionHeight].active = YES;
  }
  NSButton *addButton = [[NSButton alloc] init];
  TLSpacedButtonCell *addCell = [[TLSpacedButtonCell alloc] initTextCell:@"Manage Agents"];
  addCell.imageTitleSpacing = self.palette.menuActionIconTextSpacing;
  addCell.imageUpwardOffset = self.palette.menuActionIconUpwardOffset;
  addButton.cell = addCell;
  addButton.target = self;
  addButton.action = @selector(openAgentsFromSidebarPane:);
  addButton.image = [NSImage imageWithSystemSymbolName:@"person.2" accessibilityDescription:@"Manage Agents"];
  addButton.imagePosition = NSImageLeft;
  addButton.imageHugsTitle = YES;
  addButton.bordered = NO;
  addButton.alignment = NSTextAlignmentCenter;
  addButton.contentTintColor = self.palette.labelText;
  TLSelectionStackView *addRow = [[TLSelectionStackView alloc] init];
  addRow.palette = self.palette;
  addRow.wantsLayer = YES;
  addRow.orientation = NSUserInterfaceLayoutOrientationVertical;
  addRow.alignment = NSLayoutAttributeWidth;
  addRow.distribution = NSStackViewDistributionFill;
  addRow.edgeInsets = NSEdgeInsetsMake(self.palette.space2, self.palette.space6,
                                      self.palette.space2, self.palette.space6);
  addButton.translatesAutoresizingMaskIntoConstraints = NO;
  [addRow addArrangedSubview:addButton];
  [addButton.widthAnchor constraintEqualToAnchor:addRow.widthAnchor constant:-(self.palette.space6 * 2.0)].active = YES;
  [addButton.heightAnchor constraintGreaterThanOrEqualToConstant:self.palette.sidebarBookmarkButtonSize].active = YES;
  [pane addArrangedSubview:addRow];
  for (NSView *row in pane.arrangedSubviews) {
    [row.widthAnchor constraintEqualToAnchor:pane.widthAnchor constant:-(self.palette.space3 * 2.0)].active = YES;
  }
  // Let the widest row determine the panel width without compressing its contents.
  NSLayoutConstraint *fittingWidth = [pane.widthAnchor constraintEqualToConstant:self.palette.space0];
  fittingWidth.priority = NSLayoutPriorityFittingSizeCompression;
  fittingWidth.active = YES;
  self.sidebarAgentPane = pane;
  __weak typeof(self) weakSelf = self;
  pane.hoverChanged = ^(BOOL hovered) {
    if (!hovered) { [weakSelf scheduleSidebarAgentPaneDismissal]; }
  };
  TLGlassPaneView *surface = [[TLGlassPaneView alloc] init];
  surface.palette = self.palette;
  [surface addSubview:pane];
  self.sidebarAgentPaneSurface = surface;
  [self.rootView addSubview:surface positioned:NSWindowAbove relativeTo:nil];
  [NSLayoutConstraint activateConstraints:@[
    [surface.leadingAnchor constraintEqualToAnchor:self.sidebarTileGrid.leadingAnchor],
    [surface.topAnchor constraintEqualToAnchor:self.sidebarTileGrid.topAnchor],
    [pane.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
    [pane.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
    [pane.topAnchor constraintEqualToAnchor:surface.topAnchor],
    [pane.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
  ]];
}

- (void)openAgentsFromSidebarPane:(id)sender {
  [self.sidebarAgentPaneSurface removeFromSuperview];
  self.sidebarAgentPaneSurface = nil;
  self.sidebarAgentPane = nil;
  [self showAgents:sender];
}

- (void)scheduleSidebarAgentPaneDismissal {
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    TalariaWindowController *controller = weakSelf;
    if (!controller.sidebarAgentPane) { return; }
    NSPoint point = controller.window.mouseLocationOutsideOfEventStream;
    BOOL inPane = NSPointInRect([controller.sidebarAgentPane convertPoint:point fromView:nil], controller.sidebarAgentPane.bounds);
    BOOL inTiles = NSPointInRect([controller.sidebarTileGrid convertPoint:point fromView:nil], controller.sidebarTileGrid.bounds);
    if (!controller.window.isKeyWindow || (!inPane && !inTiles)) {
      [controller.sidebarAgentPaneSurface removeFromSuperview];
      controller.sidebarAgentPaneSurface = nil;
      controller.sidebarAgentPane = nil;
    }
  });
}

- (NSStackView *)buildSidebarInboxStack {
  NSStackView *inboxStack = [[NSStackView alloc] init];
  inboxStack.translatesAutoresizingMaskIntoConstraints = NO;
  inboxStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  inboxStack.alignment = NSLayoutAttributeWidth;
  inboxStack.distribution = NSStackViewDistributionFill;
  inboxStack.spacing = self.palette.space0;
  [inboxStack setContentHuggingPriority:NSLayoutPriorityDefaultLow
                         forOrientation:NSLayoutConstraintOrientationVertical];
  [inboxStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                      forOrientation:NSLayoutConstraintOrientationVertical];

  self.sidebarShortcutsView = [[TLSidebarShortcutsView alloc] init];
  self.sidebarShortcutsView.palette = self.palette;

  self.sidebarShortcutsView.addButton.target = self;
  self.sidebarShortcutsView.addButton.action = @selector(showAddBookmark:);
  [self reloadBookmarks];

  self.notificationsController = [[TLNotificationsController alloc] initWithPalette:self.palette];
  __weak typeof(self) weakSelf = self;
  self.notificationsController.openHandler = ^(NSDictionary *notification) { [weakSelf openNotification:notification]; };
  self.notificationsController.readHandler = ^(NSDictionary *notification, BOOL read) {
    [weakSelf setNotification:notification read:read agentID:weakSelf.notificationsAgentID];
  };
  NSView *notifications = self.notificationsController.view;
  notifications.translatesAutoresizingMaskIntoConstraints = NO;
  [inboxStack addArrangedSubview:self.sidebarShortcutsView];
  [inboxStack setCustomSpacing:self.palette.space5 afterView:self.sidebarShortcutsView];
  [inboxStack addArrangedSubview:notifications];
  [self.sidebarShortcutsView.widthAnchor constraintEqualToAnchor:inboxStack.widthAnchor].active = YES;
  [notifications.widthAnchor constraintEqualToAnchor:inboxStack.widthAnchor].active = YES;
  return inboxStack;
}

- (TLSidebarInboxStackView *)sidebarInboxStackViewWithTitle:(NSString *)title
                                                   subtitle:(NSString *)subtitle
                                              iconAssetName:(NSString *)iconAssetName
                                          notificationCount:(NSInteger)notificationCount {
  TLSidebarInboxStackView *stackView = [[TLSidebarInboxStackView alloc] init];
  stackView.palette = self.palette;
  stackView.image = [self inboxIconNamed:iconAssetName];
  stackView.title = title;
  stackView.subtitle = subtitle;
  stackView.notificationCount = notificationCount;
  return stackView;
}

- (TLSidebarInboxStackView *)sidebarInboxStackViewWithTitle:(NSString *)title
                                                   subtitle:(NSString *)subtitle
                                             systemIconName:(NSString *)systemIconName
                                          notificationCount:(NSInteger)notificationCount {
  TLSidebarInboxStackView *stackView = [[TLSidebarInboxStackView alloc] init];
  stackView.palette = self.palette;
  stackView.imageUsesTemplateRendering = YES;
  stackView.image = [self symbolImageNamed:systemIconName accessibilityDescription:title];
  stackView.title = title;
  stackView.subtitle = subtitle;
  stackView.notificationCount = notificationCount;
  return stackView;
}

- (NSStackView *)buildSidebarActionStack {
  NSStackView *actionStack = [[NSStackView alloc] init];
  actionStack.translatesAutoresizingMaskIntoConstraints = NO;
  actionStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  actionStack.alignment = NSLayoutAttributeLeading;
  actionStack.distribution = NSStackViewDistributionFill;
  actionStack.spacing = self.palette.space0;
  [actionStack setContentHuggingPriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationVertical];
  [actionStack setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                       forOrientation:NSLayoutConstraintOrientationVertical];

  self.sidebarAutomationsButton = [[TLSidebarNavigationButton alloc] init];
  self.sidebarAutomationsButton.palette = self.palette;
  self.sidebarAutomationsButton.title = @"Automations";
  self.sidebarAutomationsButton.systemIconName = @"clock.arrow.circlepath";
  self.sidebarAutomationsButton.accessorySystemIconName = @"arrow.up.right.square";
  self.sidebarAutomationsButton.target = self;
  self.sidebarAutomationsButton.action = @selector(showAutomations:);
  self.sidebarAutomationsButton.toolTip = @"Open Automations";
  [self.sidebarAutomationsButton setAccessibilityLabel:@"Automations"];
  [self.sidebarAutomationsButton setAccessibilityRole:NSAccessibilityButtonRole];
  self.sidebarUserButton = [self sidebarUserButtonWithDisplayName:@"Yaroslav"];

  [actionStack addArrangedSubview:self.sidebarAutomationsButton];
  [self.sidebarAutomationsButton.trailingAnchor constraintEqualToAnchor:actionStack.trailingAnchor].active = YES;
  [actionStack addArrangedSubview:self.sidebarUserButton];
  [self.sidebarUserButton.trailingAnchor constraintLessThanOrEqualToAnchor:actionStack.trailingAnchor].active = YES;
  return actionStack;
}

- (TLSidebarUserButton *)sidebarUserButtonWithDisplayName:(NSString *)displayName {
  TLSidebarUserButton *button = [[TLSidebarUserButton alloc] init];
  button.palette = self.palette;
  button.displayName = displayName;
  button.target = self;
  button.action = @selector(showSidebarUserMenu:);
  button.toolTip = displayName;
  return button;
}

- (nullable NSImage *)inboxIconNamed:(NSString *)name {
  NSURL *iconURL = [NSBundle.mainBundle URLForResource:name
                                         withExtension:@"svg"
                                          subdirectory:@"inbox-icons"];
  if (!iconURL) {
    return nil;
  }

  NSImage *image = [[NSImage alloc] initWithContentsOfURL:iconURL];
  image.template = NO;
  return image;
}

- (nullable NSImage *)sidebarPlanetImage {
  NSURL *planetURL = [NSBundle.mainBundle URLForResource:@"sidebar-planet" withExtension:@"png"];
  if (!planetURL) {
    return nil;
  }
  return [[NSImage alloc] initWithContentsOfURL:planetURL];
}

- (NSView *)buildChatWorkspace { NSView *view = [[self currentChatPresentation] buildChatWorkspace]; [self installMessageScrollWheelMonitor]; return view; }

- (void)updateMessageInputWidthForWindowWidth:(CGFloat)windowWidth {
  if (!self.messageInputWidthConstraint) {
    return;
  }

  if (self.splitWorkspace.split) { [self updateSplitContentSizes]; return; }
  CGFloat previousWidth = self.messageInputWidthConstraint.constant;
  CGFloat nextWidth = [self messageInputWidthForWindowWidth:windowWidth
                                               sidebarWidth:[self currentSidebarWidth]
                                      contentLeadingPadding:[self contentLeadingPadding]];
  self.messageInputWidthConstraint.constant = nextWidth;
  [self applyBrowserAddressInputWidth:nextWidth];
  [self updateSplitContentSizes];
  if (!self.slashCommandListView.hidden) {
    [self updateSlashCommandList];
  }
  if (fabs(previousWidth - nextWidth) > 0.5 && self.messages.count > 0) {
    [self resetMessageRowCache];
    [self renderMessages];
  }
}

- (void)applyBrowserAddressInputWidth:(CGFloat)width {
  for (TLWorkspaceTab *browserTab in [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser]) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:browserTab];
    [(TLBrowserTabController *)runtime.featureController setAddressInputWidth:width];
  }
}

- (CGFloat)messageInputWidthForWindowWidth:(CGFloat)windowWidth
                              sidebarWidth:(CGFloat)sidebarWidth
                     contentLeadingPadding:(CGFloat)contentLeadingPadding {
  CGFloat availableWidth = windowWidth - sidebarWidth - contentLeadingPadding - self.palette.space4 - (self.palette.space11 * 2.0);
  return MIN(self.palette.messageInputMaxWidth,
             MAX(self.palette.messageInputMinWidth, availableWidth));
}

- (NSView *)buildTopbar {
  self.topbar = [[TLTokenView alloc] init];
  self.topbar.translatesAutoresizingMaskIntoConstraints = NO;
  self.topbar.wantsLayer = YES;
  self.topbar.layer.zPosition = 10.0;
  [self allowHorizontalWindowExpansionForView:self.topbar];
  self.topbar.canDragWindow = YES;
  [self.topbar.heightAnchor constraintEqualToConstant:self.palette.topbarHeight].active = YES;

  TLWindowDragStackView *tabStack = [[TLWindowDragStackView alloc] init];
  tabStack.canDragWindow = YES;
  self.tabStack = tabStack;
  self.tabStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabStack.wantsLayer = YES;
  self.tabStack.layer.zPosition = 1.0;
  self.tabStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  self.tabStack.alignment = NSLayoutAttributeCenterY;
  self.tabStack.spacing = self.palette.space0;
  [self.tabStack setContentHuggingPriority:NSLayoutPriorityRequired
                            forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.tabStack setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.workspaceTabsController = [[TLWorkspaceTabsController alloc] initWithTabStack:self.tabStack
                                                                              target:self
                                                                            delegate:self
                                                                             palette:self.palette];
  self.sidebarToggleButton = [self makeSidebarToggleButton];
  if (self.incognito) {
    self.sidebarToggleButton.hidden = YES;
    self.incognitoPill = [TLIncognitoPill new];
    self.incognitoPill.palette = self.palette;
    [self.topbar addSubview:self.incognitoPill];
    [NSLayoutConstraint activateConstraints:@[
      [self.incognitoPill.leadingAnchor constraintEqualToAnchor:self.topbar.leadingAnchor constant:self.palette.trafficLightLeftInset + self.palette.trafficLightReservedWidth - self.palette.space5],
      [self.incognitoPill.centerYAnchor constraintEqualToAnchor:self.topbar.centerYAnchor],
      [self.incognitoPill.widthAnchor constraintEqualToConstant:self.incognitoPill.intrinsicContentSize.width],
      [self.incognitoPill.heightAnchor constraintEqualToConstant:self.incognitoPill.intrinsicContentSize.height],
    ]];
  }
  self.createChatButton = [self makeCreateChatButton];
  __weak TLButton *animatedCreateButton = self.createChatButton;
  self.workspaceTabsController.animationActivityChanged = ^(BOOL animating) {
    animatedCreateButton.hoverSuppressed = animating;
  };

  [self.topbar addSubview:self.tabStack];
  [self.topbar addSubview:self.createChatButton];
  [self.topbar addSubview:self.sidebarToggleButton];

  NSSize headerButtonSize = self.createChatButton.intrinsicContentSize;
  self.tabStackLeadingConstraint = [self.tabStack.leadingAnchor constraintEqualToAnchor:self.topbar.leadingAnchor
                                                                                constant:[self tabStackLeadingConstant]];
  NSLayoutConstraint *tabStackTrailingConstraint =
    [self.tabStack.trailingAnchor constraintEqualToAnchor:self.createChatButton.leadingAnchor
                                                 constant:[self createChatButtonTabOverlap]];
  tabStackTrailingConstraint.priority = NSLayoutPriorityDefaultHigh;
  self.workspaceTabsController.createTabButtonSpacingConstraint = tabStackTrailingConstraint;
  NSLayoutConstraint *createButtonTrailingConstraint =
    [self.createChatButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.topbar.trailingAnchor
                                                                    constant:-self.palette.space4];
  createButtonTrailingConstraint.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    [self.sidebarToggleButton.leadingAnchor constraintEqualToAnchor:self.topbar.leadingAnchor
                                                           constant:self.palette.trafficLightLeftInset + self.palette.trafficLightReservedWidth - self.palette.space5],
    [self.sidebarToggleButton.centerYAnchor constraintEqualToAnchor:self.topbar.centerYAnchor],
    [self.sidebarToggleButton.widthAnchor constraintEqualToConstant:headerButtonSize.width],
    [self.sidebarToggleButton.heightAnchor constraintEqualToConstant:headerButtonSize.height],
    self.tabStackLeadingConstraint,
    tabStackTrailingConstraint,
    [self.tabStack.bottomAnchor constraintEqualToAnchor:self.topbar.bottomAnchor],
    createButtonTrailingConstraint,
    [self.createChatButton.centerYAnchor constraintEqualToAnchor:self.topbar.centerYAnchor constant:[self createChatButtonVerticalOffset]],
    [self.createChatButton.widthAnchor constraintEqualToConstant:headerButtonSize.width],
    [self.createChatButton.heightAnchor constraintEqualToConstant:headerButtonSize.height],
  ]];

  return self.topbar;
}

- (void)layoutTrafficLightButtons {
  NSButton *closeButton = [self.window standardWindowButton:NSWindowCloseButton];
  NSButton *miniaturizeButton = [self.window standardWindowButton:NSWindowMiniaturizeButton];
  NSButton *zoomButton = [self.window standardWindowButton:NSWindowZoomButton];
  if (!closeButton || !miniaturizeButton || !zoomButton || !closeButton.superview || NSIsEmptyRect(self.rootView.bounds)) {
    return;
  }

  CGFloat closeToMiniaturizeGap = NSMinX(miniaturizeButton.frame) - NSMinX(closeButton.frame);
  CGFloat miniaturizeToZoomGap = NSMinX(zoomButton.frame) - NSMinX(miniaturizeButton.frame);
  CGFloat y = NSHeight(self.rootView.bounds) - ((self.palette.topbarHeight + NSHeight(closeButton.frame)) * 0.5);
  NSPoint origin = [closeButton.superview convertPoint:NSMakePoint(self.palette.trafficLightLeftInset, y)
                                              fromView:self.rootView];

  [closeButton setFrameOrigin:origin];
  [miniaturizeButton setFrameOrigin:NSMakePoint(origin.x + closeToMiniaturizeGap, origin.y)];
  [zoomButton setFrameOrigin:NSMakePoint(origin.x + closeToMiniaturizeGap + miniaturizeToZoomGap, origin.y)];

  NSRect zoomFrameInRootView = [zoomButton.superview convertRect:zoomButton.frame toView:self.rootView];
  CGFloat minimumTabLeading = NSMaxX(zoomFrameInRootView) + self.palette.space5;
  CGFloat reservedTabLeading = [self tabStackLeadingConstant];
  self.tabStackLeadingConstraint.constant = MAX(reservedTabLeading, minimumTabLeading);
  [self updateWorkspaceTabWidths];
}

- (NSView *)buildMessagesView { return [[self currentChatPresentation] buildMessagesView]; }

- (void)installMessageScrollWheelMonitor {
  [self installMessageContextMenuMonitor];
  if (self.messageScrollWheelMonitor) {
    return;
  }

  __weak typeof(self) weakSelf = self;
  self.messageScrollWheelMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel
                                                                         handler:^NSEvent *(NSEvent *event) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf || event.window != strongSelf.window) {
      return event;
    }
    if (![strongSelf isChatWorkspaceActive] || strongSelf.chatWorkspace.hidden) {
      return event;
    }
    NSView *contentView = strongSelf.window.contentView;
    NSPoint hitPoint = [contentView.superview convertPoint:event.locationInWindow fromView:nil];
    for (NSView *hit = [contentView hitTest:hitPoint]; hit; hit = hit.superview) {
      if ([hit isKindOfClass:TLGlassPaneView.class]) {
        return event;
      }
    }
    if (fabs(event.scrollingDeltaY) < fabs(event.scrollingDeltaX)) {
      return event;
    }

    NSPoint pointInInput = [strongSelf.messageInput convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(pointInInput, strongSelf.messageInput.bounds)) {
      return event;
    }

    NSPoint pointInMessages = [strongSelf.messageScrollView convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(pointInMessages, strongSelf.messageScrollView.bounds)) {
      return event;
    }

    strongSelf.chatPresentation.notificationTargetMessageID = nil;
    strongSelf.chatPresentation.notificationTargetToolCallID = nil;
    strongSelf.chatPresentation.notificationDidReveal = nil;
    [strongSelf.messageScrollView scrollWheel:event];
    return nil;
  }];
}

- (void)installMessageContextMenuMonitor {
  if (self.messageContextMenuMonitor) { return; }
  __weak typeof(self) weakSelf = self;
  self.messageContextMenuMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
    NSEventMaskRightMouseDown | NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
    TalariaWindowController *controller = weakSelf;
    BOOL contextualClick = event.type == NSEventTypeRightMouseDown ||
      (event.type == NSEventTypeLeftMouseDown && (event.modifierFlags & NSEventModifierFlagControl));
    if (!contextualClick || event.window != controller.window ||
        ![controller isChatWorkspaceActive] || controller.chatWorkspace.hidden) {
      return event;
    }
    NSView *contentView = controller.window.contentView;
    NSPoint point = [contentView.superview convertPoint:event.locationInWindow fromView:nil];
    NSView *hitView = [contentView hitTest:point];
    for (TLChatMessage *message in controller.messages) {
      NSView *row = [controller.messageRowViews objectForKey:message];
      if (!row || ![hitView isDescendantOf:row] ||
          (![message.role isEqualToString:TLRoleUser] && ![message.role isEqualToString:TLRoleAssistant])) {
        continue;
      }
      NSDictionary *context = @{@"message": message, @"chatID": @(controller.activeChat.chatID)};
      NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Message"];
      menu.autoenablesItems = NO;
      NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy message"
        action:@selector(copyChatMessage:) keyEquivalent:@""];
      copyItem.target = controller;
      copyItem.representedObject = context;
      [menu addItem:copyItem];
      NSString *regenerateTitle = [message.role isEqualToString:TLRoleUser] ? @"Regenerate response" : @"Regenerate";
      NSMenuItem *regenerateItem = [[NSMenuItem alloc] initWithTitle:regenerateTitle
        action:@selector(regenerateChatMessage:) keyEquivalent:@""];
      regenerateItem.target = controller;
      regenerateItem.representedObject = context;
      regenerateItem.enabled = [controller canRegenerateChatMessage:message];
      regenerateItem.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil];
      [menu addItem:regenerateItem];
      [menu addItem:NSMenuItem.separatorItem];
      NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete message"
        action:@selector(deleteChatMessage:) keyEquivalent:@""];
      deleteItem.target = controller;
      deleteItem.representedObject = context;
      deleteItem.enabled = !controller.isSending;
      deleteItem.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:nil];
      [menu addItem:deleteItem];
      // WebKit must receive the click to identify the link and build its native
      // menu (including Inspect Element). The row menu is only a fallback.
      for (NSView *view = hitView; view && view != row; view = view.superview) {
        if ([view isKindOfClass:TLMarkdownContentWebView.class]) {
          ((TLMarkdownContentWebView *)view).fallbackContextMenu = menu;
          return event;
        }
      }
      [NSMenu popUpContextMenu:menu withEvent:event forView:row];
      return nil;
    }
    return event;
  }];
}

- (void)copyChatMessage:(NSMenuItem *)sender {
  TLChatMessage *message = sender.representedObject[@"message"];
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:message.content ?: @"" forType:NSPasteboardTypeString];
}

- (TLChatMessage *)promptForRegeneratingMessage:(TLChatMessage *)message {
  NSUInteger index = [self.messages indexOfObjectIdenticalTo:message];
  if (index == NSNotFound) return nil;
  if (![message.role isEqual:TLRoleUser] && ![message.role isEqual:TLRoleAssistant]) return nil;
  for (NSInteger i = (NSInteger)index; i >= 0; i--) {
    TLChatMessage *candidate = self.messages[i];
    if ([candidate.role isEqual:TLRoleUser]) return candidate;
  }
  return nil;
}

- (BOOL)canRegenerateChatMessage:(TLChatMessage *)message {
  if (self.isSending || self.preparingAttachments || self.chatPresentation.queuedPrompts.count ||
      self.chatPresentation.editingQueuedPrompt) return NO;
  for (TLChatMessage *candidate in self.messages) if (candidate.approvalRequest) return NO;
  TLChatMessage *prompt = [self promptForRegeneratingMessage:message];
  return prompt && (prompt.content.length || prompt.attachments.count);
}

- (void)regenerateChatMessage:(NSMenuItem *)sender {
  TLChatMessage *message = sender.representedObject[@"message"];
  NSInteger chatID = [sender.representedObject[@"chatID"] integerValue];
  if (self.activeChat.chatID != chatID || ![self canRegenerateChatMessage:message]) return;
  NSString *token = self.settings.openRouterToken;
  NSString *model = self.activeChat.model ?: self.settings.selectedModel;
  if (!token.length || !model.length) {
    [self presentErrorMessage:@"Configure your token and model before regenerating an answer."];
    return;
  }
  TLChatMessage *prompt = [self promptForRegeneratingMessage:message];
  TLChatMessage *answer = [message.role isEqual:TLRoleAssistant] ? message : nil;
  if (!answer) {
    NSUInteger index = [self.messages indexOfObjectIdenticalTo:prompt];
    for (NSUInteger i = index + 1; i < self.messages.count; i++) {
      TLChatMessage *candidate = self.messages[i];
      if ([candidate.role isEqual:TLRoleUser]) break;
      if ([candidate.role isEqual:TLRoleAssistant]) { answer = candidate; break; }
    }
  }
  TLPromptBuilder *builder = [[TLPromptBuilder alloc] init];
  [builder addPartWithContent:@"Regenerate your answer to the following earlier user request. Give a fresh, complete answer to that request."
    importance:TLPromptImportanceRequired strategy:TLPromptCompactionStrategyWhole name:@"regeneration"];
  [builder addPartWithContent:prompt.content importance:TLPromptImportanceRequired
    strategy:TLPromptCompactionStrategyWhole name:@"original-request"];
  [self beginPreparedTurnWithChat:self.activeChat messages:self.messages token:token model:model prompt:[builder build]
    attachments:prompt.attachments sourceURLs:@[] approvalResponse:nil regenerationPrompt:prompt regenerationMessage:answer];
}

- (void)deleteChatMessage:(NSMenuItem *)sender {
  TLChatMessage *message = sender.representedObject[@"message"];
  NSInteger chatID = [sender.representedObject[@"chatID"] integerValue];
  NSUInteger index = [self.messages indexOfObjectIdenticalTo:message];
  if (self.isSending || self.activeChat.chatID != chatID || index == NSNotFound) { return; }
  if ([message isKindOfClass:TLStoredChatMessage.class]) {
    NSError *error = nil;
    if (![self.database deleteMessageWithID:((TLStoredChatMessage *)message).messageID chatID:chatID error:&error]) {
      [self presentErrorMessage:error.localizedDescription ?: @"Could not delete message."];
      return;
    }
    NSMutableArray *storedMessages = [self.activeChat.messages mutableCopy];
    NSIndexSet *deletedIndexes = [storedMessages indexesOfObjectsPassingTest:^BOOL(TLStoredChatMessage *stored, NSUInteger idx, BOOL *stop) {
      return stored.messageID == ((TLStoredChatMessage *)message).messageID;
    }];
    [storedMessages removeObjectsAtIndexes:deletedIndexes];
    self.activeChat.messages = storedMessages;
  }
  NSView *row = [self.messageRowViews objectForKey:message];
  if (row) { [self detachMessageRowFromStack:row]; }
  [self.messageRowViews removeObjectForKey:message];
  [self.messageRowSignatures removeObjectForKey:message];
  [self.messageMarkdownViews removeObjectForKey:message];
  [self.chatPresentation.messageActivityViews removeObjectForKey:message];
  [self.messages removeObjectAtIndex:index];
  [self refreshChatsKeepingActiveSelection];
  [self renderMessagesScrollingToBottom:NO];
  [self updateControlStates];
}

- (NSView *)buildMessageInput { return [[self currentChatPresentation] buildMessageInput]; }

- (void)loadInitialState {
  if (self.widgetbookMode) {
    [self loadWidgetbookState];
    return;
  }

  self.isLoading = YES;
  [self renderMessages];

  NSError *error = nil;
  TLAppSettings *storedSettings = [self.database appSettings:&error];
  NSArray<TLChatSummary *> *loadedChats = [self.database listChats:&error];
  NSArray<TLAgentRecord *> *loadedAgents = [self.agentOrchestrator listAgents:&error];

  if (!storedSettings || !loadedChats || !loadedAgents) {
    self.errorMessage = error.localizedDescription ?: @"Could not load Talaria data.";
    self.isLoading = NO;
    [self renderMessages];
    return;
  }

  self.settings = storedSettings;
  self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.chats = [loadedChats mutableCopy];
  self.agents = [loadedAgents mutableCopy];
  [self refreshNotifications];
  [self.settingsTabController refreshPluginsForSelectedAgent];
  [self rebuildSidebarAgents];

  // A chat can have been deleted since this session was last saved.
  NSMutableSet<NSNumber *> *chatIDs = [NSMutableSet set];
  for (TLChatSummary *chat in self.chats) [chatIDs addObject:@(chat.chatID)];
  for (TLWorkspaceTab *tab in self.appStateManager.snapshot.workspaceTabs) {
    if (tab.kind == TLWorkspaceTabKindChat && tab.tabID > 0 && ![chatIDs containsObject:@(tab.tabID)]) {
      [self.appStateManager removeWorkspaceTabWithKind:tab.kind tabID:tab.tabID];
    }
  }

  TLBrowserPreferences *browserPreferences = TLBrowserPreferences.sharedPreferences;
  if (![[browserPreferences localValue:@"startup"] isEqual:@"restore"]) {
    for (TLWorkspaceTab *tab in self.appStateManager.snapshot.workspaceTabs.copy) {
      if (tab.kind == TLWorkspaceTabKindBrowser && !tab.pinned) [self.appStateManager removeWorkspaceTabWithKind:tab.kind tabID:tab.tabID];
    }
  }
  if (self.appStateManager.snapshot.workspaceTabs.count > 0) {
    [self hydrateWorkspaceTabsFromAppState];
    [self restoreWorkspaceFromAppState];
  } else if (self.chats.count > 0) {
    [self loadChatWithID:self.chats[0].chatID];
  } else {
    [self startNewChatWithModel:self.settings.selectedModel focus:NO];
  }

  if (!self.incognito) for (NSURL *URL in browserPreferences.startupURLs) [self openBrowserTabWithURL:URL];
  self.isLoading = NO;
  self.errorMessage = @"";
  [self applyTheme];
  [self renderMessages];
  if (!self.incognito && !self.settings.onboardingCompleted) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self showOnboardingDemoWindow:self]; });
  } else {
    // Restore suggestions immediately, then warm the VM/gateway before the first /.
    [self prepareHermesCommands];
  }
}

- (void)hydrateWorkspaceTabsFromAppState {
  for (TLWorkspaceTab *tab in self.appStateManager.snapshot.workspaceTabs) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:tab];
    switch (tab.kind) {
      case TLWorkspaceTabKindChat:
        self.nextDraftChatID = MIN(self.nextDraftChatID, tab.tabID - 1);
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:self.chatWorkspace
                                                       openAction:@selector(openChatTab:)
                                                      closeAction:@selector(closeChatTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        break;
      case TLWorkspaceTabKindHistory:
        self.historyTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:self.historyPanelController.panelView
                                                       openAction:@selector(openHistoryTab:)
                                                      closeAction:@selector(closeHistoryTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        break;
      case TLWorkspaceTabKindSettings:
        self.settingsTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[self buildSettingsTabContent]
                                                       openAction:@selector(openSettingsTab:)
                                                      closeAction:@selector(closeSettingsTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        if (runtime.contentView) {
          [self addWorkspaceContentView:runtime.contentView];
        }
        break;
      case TLWorkspaceTabKindAgents:
        self.agentsTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[self buildAgentsTabContent]
                                                       openAction:@selector(openAgentsTab:)
                                                      closeAction:@selector(closeAgentsTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        if (runtime.contentView) {
          [self addWorkspaceContentView:runtime.contentView];
        }
        break;
      case TLWorkspaceTabKindDownloads:
        self.downloadsTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[self buildDownloadsContent]
            openAction:@selector(showDownloads:) closeAction:@selector(closeDownloadsTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        if (runtime.contentView) [self addWorkspaceContentView:runtime.contentView];
        break;
      case TLWorkspaceTabKindAutomations:
        self.automationsTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[self buildAutomationsContent]
            openAction:@selector(showAutomations:) closeAction:@selector(closeAutomationsTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        if (runtime.contentView) [self addWorkspaceContentView:runtime.contentView];
        break;
      case TLWorkspaceTabKindDebug:
        self.debugTab = tab;
        if (!runtime) {
          runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[self buildDebugTabContent]
                                                       openAction:@selector(openDebugTab:)
                                                      closeAction:@selector(closeDebugTab:)];
          [self setRuntime:runtime forTab:tab];
        }
        if (runtime.contentView) {
          [self addWorkspaceContentView:runtime.contentView];
        }
        break;
      case TLWorkspaceTabKindBrowser:
        self.nextBrowserTabID = MAX(self.nextBrowserTabID, tab.tabID + 1);
        [self ensureBrowserRuntimeForTab:tab];
        break;
    }
  }
}

- (void)restoreWorkspaceFromAppState {
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;

  if (snapshot.activeTabKind == TLWorkspaceTabKindChat && snapshot.activeTabID > 0) {
    [self loadChatWithID:snapshot.activeTabID];
    return;
  }
  if (snapshot.activeTabKind == TLWorkspaceTabKindChat && snapshot.activeTabID <= 0) {
    [self activateDraftChatWithID:snapshot.activeTabID];
    return;
  }

  if (snapshot.activeTabKind == TLWorkspaceTabKindHistory) {
    [self ensureHistoryTab];
  } else if (snapshot.activeTabKind == TLWorkspaceTabKindSettings) {
    [self showSettings:self];
  } else if (snapshot.activeTabKind == TLWorkspaceTabKindAgents) {
    [self showAgents:self];
  } else if (snapshot.activeTabKind == TLWorkspaceTabKindDownloads) {
    [self showDownloads:self];
  } else if (snapshot.activeTabKind == TLWorkspaceTabKindAutomations) {
    [self showAutomations:self];
  } else if (snapshot.activeTabKind == TLWorkspaceTabKindDebug) {
    [self showDebug:self];
  }

  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)loadWidgetbookState {
  self.isLoading = NO;
  self.errorMessage = @"";
  self.settings = [TLAppSettings defaultSettings];
  self.settings.selectedModel = @"widgetbook";
  self.chats = [TLWidgetbookChats() mutableCopy];
  self.activeChat = TLWidgetbookChat();
  [self addChatToSessionIfNeeded:self.activeChat.chatID activate:YES];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  for (TLChatMessage *message in self.activeChat.messages) {
    [self.messages addObject:[message copy]];
  }
  self.promptTextView.string = @"Widgetbook mode";
  [self applyTheme];
  [self reloadHistoryPanel];
  [self selectActiveChatInHistory];
  [self updateWorkspaceMode];
  [self renderMessages];
  [self updateControlStates];
  NSURL *browserURL = TLWidgetbookBrowserURL();
  if (browserURL) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self openBrowserTabWithURL:browserURL];
    });
  }
}

- (void)refreshChatsKeepingActiveSelection {
  NSError *error = nil;
  NSArray<TLChatSummary *> *nextChats = [self.database listChats:&error];
  if (!nextChats) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not refresh chats."];
    return;
  }

  self.chats = [nextChats mutableCopy];
  [self reloadHistoryPanel];
  if ([self isHistoryScreenActive]) [self refreshHermesHistory];
  [self selectActiveChatInHistory];

  for (TLChatSummary *summary in self.chats) {
    if (summary.chatID == self.activeChat.chatID) {
      self.activeChat.title = summary.title;
      self.activeChat.icon = summary.icon;
      self.activeChat.updatedAt = summary.updatedAt;
      break;
    }
  }

  [self synchronizeChatTabTitles];
  [self reloadWorkspaceTabs];
}

- (void)loadChatWithID:(NSInteger)chatID {
  if ([self activateCachedChatWithID:chatID]) return;
  if (chatID <= 0) {
    [self activateDraftChatWithID:chatID];
    return;
  }

  NSError *error = nil;
  TLChatRecord *chat = [self.database chatWithID:chatID error:&error];
  if (!chat) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not load chat."];
    return;
  }

  self.activeChat = chat;
  [self applySavedChatSummary:chat];
  [self addChatToSessionIfNeeded:chat.chatID activate:YES];
  [self showChatWorkspace];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  for (TLStoredChatMessage *storedMessage in chat.messages) {
    [self.messages addObject:[storedMessage copy]];
  }
  NSMutableArray<TLChatMessage *> *streamingMessages = self.turnMessagesByChat[@(chatID)];
  if (streamingMessages) self.messages = streamingMessages;

  self.promptTextView.string = self.attachmentPromptDrafts[@(chatID)] ?: @"";
  self.errorMessage = @"";
  [self selectActiveChatInHistory];
  [self renderMessages];
  [self updateControlStates];
  if (!self.openingNotificationSource) [self generateChatIconIfNeededForChatID:chat.chatID messages:self.messages];
}

- (void)activateDraftChatWithID:(NSInteger)chatID {
  if ([self activateCachedChatWithID:chatID]) return;
  TLWorkspaceTab *tab = [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
  if (!tab) {
    return;
  }

  TLChatRecord *chat = self.activeChat.chatID == chatID ? self.activeChat : self.modelDraftChats[@(chatID)];
  if (!chat) {
    chat = [[TLChatRecord alloc] init];
    chat.chatID = chatID;
    chat.title = tab.title.length > 0 ? tab.title : @"New chat";
    chat.model = self.settings.selectedModel.length > 0 ? self.settings.selectedModel : TLDefaultModelID;
    chat.supportingModel = self.settings.supportingModel;
    chat.messages = @[];
  }

  self.activeChat = chat;
  [self activateTabKind:TLWorkspaceTabKindChat tabID:chatID];
  [self showChatWorkspace];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  self.promptTextView.string = self.attachmentPromptDrafts[@(chatID)] ?: @"";
  self.errorMessage = @"";
  [self selectActiveChatInHistory];
  [self renderMessages];
  [self updateControlStates];
}

- (void)startNewChatFromButton:(id)sender {
  [self startNewChatWithModel:self.settings.selectedModel focus:YES];
}

- (NSMenu *)newTabContextMenu {
  NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
  NSMenuItem *tab = [[NSMenuItem alloc] initWithTitle:@"Open new tab" action:@selector(startNewChatFromButton:) keyEquivalent:@""];
  tab.target = self; tab.enabled = self.createChatButton.enabled && !self.widgetbookMode;
  [menu addItem:tab];
  NSMenuItem *sideview = [[NSMenuItem alloc] initWithTitle:@"Open new tab in a sideview" action:@selector(startNewChatInSideview:) keyEquivalent:@""];
  sideview.target = self;
  sideview.enabled = tab.enabled && [self.splitState availableNeighborForTab:[self activeWorkspaceTab] placement:NULL] != nil;
  [menu addItem:sideview];
  return menu;
}

- (void)startNewChatInSideview:(id)sender {
  if (self.widgetbookMode || !self.createChatButton.enabled) return;
  TLSplitPlacement placement;
  NSString *identity = [self.splitState availableNeighborForTab:[self activeWorkspaceTab] placement:&placement];
  TLWorkspaceTab *neighbor = [self tabWithPresentationIdentity:identity];
  // Recheck capacity when invoked so a stale menu cannot create a tenth tab.
  if (!neighbor) return;
  [self startNewChatFromButton:sender];
  [self splitTab:[self activeWorkspaceTab] besideTab:neighbor placement:placement];
  [self.window makeFirstResponder:self.promptTextView];
}

- (void)showHistoryScreen:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  [self ensureHistoryTab];
  [self activateTabKind:TLWorkspaceTabKindHistory tabID:self.historyTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)showSidebarUserMenu:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Yaroslav"];
  menu.autoenablesItems = NO;

  NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:@"History"
                                                       action:@selector(showHistoryScreen:)
                                                keyEquivalent:@""];
  historyItem.target = self;
  historyItem.image = [self symbolImageNamed:@"clock" accessibilityDescription:@"History"];
  [menu addItem:historyItem];

  NSMenuItem *downloadsItem = [[NSMenuItem alloc] initWithTitle:@"Downloads" action:@selector(showDownloads:) keyEquivalent:@""];
  downloadsItem.target = self;
  downloadsItem.image = [self symbolImageNamed:@"arrow.down.circle" accessibilityDescription:@"Downloads"];
  [menu addItem:downloadsItem];

  NSMenuItem *debugItem = [[NSMenuItem alloc] initWithTitle:@"Debug"
                                                     action:@selector(showDebug:)
                                              keyEquivalent:@""];
  debugItem.target = self;
  debugItem.image = [self symbolImageNamed:@"terminal" accessibilityDescription:@"Debug"];
  [menu addItem:debugItem];

  NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings"
                                                        action:@selector(showSettings:)
                                                 keyEquivalent:@""];
  settingsItem.target = self;
  settingsItem.image = [self symbolImageNamed:@"gearshape" accessibilityDescription:@"Settings"];
  [menu addItem:settingsItem];

  if (@available(macOS 27.0, *)) {
    for (NSMenuItem *item in menu.itemArray) {
      item.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
    }
  }

  NSView *sourceView = [sender isKindOfClass:NSView.class] ? (NSView *)sender : self.sidebarUserButton;
  [menu popUpMenuPositioningItem:nil
                       atLocation:NSMakePoint(self.palette.space0, -self.palette.space2)
                           inView:sourceView];
}

- (NSView *)buildDownloadsContent {
  self.downloadsController = [[TLDownloadsTabController alloc]
    initWithManager:TLBrowserDownloadManager.sharedManager palette:self.palette];
  return self.downloadsController.view;
}

- (void)showDownloads:(id)sender {
  if (self.widgetbookMode) return;
  if (!self.downloadsTab) {
    NSView *content = [self buildDownloadsContent];
    self.downloadsTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindDownloads tabID:0
      title:@"Downloads" toolTip:@"Browser downloads" URL:nil closeable:YES];
    [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:content
      openAction:@selector(showDownloads:) closeAction:@selector(closeDownloadsTab:)] forTab:self.downloadsTab];
    [self addWorkspaceContentView:content];
    [self.appStateManager addWorkspaceTab:self.downloadsTab activate:NO];
  }
  [self activateTabKind:TLWorkspaceTabKindDownloads tabID:self.downloadsTab.tabID];
  [self.downloadsController refresh];
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
}

- (void)closeDownloadsTab:(id)sender {
  if (!self.downloadsTab || [self closeWindowIfOnlyWorkspaceTab:self.downloadsTab]) return;
  [self rememberClosedWorkspaceTab:self.downloadsTab];
  [self.downloadsController close];
  [self.appStateManager removeWorkspaceTabWithKind:self.downloadsTab.kind tabID:self.downloadsTab.tabID];
  [[self contentViewForTab:self.downloadsTab] removeFromSuperview];
  [self removeRuntimeForKind:self.downloadsTab.kind tabID:self.downloadsTab.tabID];
  self.downloadsTab = nil; self.downloadsController = nil;
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
}

- (void)showChatWorkspace {
  if (self.activeChat) {
    [self activateTabKind:TLWorkspaceTabKindChat tabID:self.activeChat.chatID];
  }
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
}

- (void)openHistoryTab:(id)sender {
  if (self.widgetbookMode || !self.historyTab) {
    return;
  }

  [self activateTabKind:TLWorkspaceTabKindHistory tabID:self.historyTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)closeHistoryTab:(id)sender {
  if (!self.historyTab || self.widgetbookMode) {
    return;
  }
  if ([self closeWindowIfOnlyWorkspaceTab:self.historyTab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:self.historyTab];

  [self.appStateManager removeWorkspaceTabWithKind:self.historyTab.kind tabID:self.historyTab.tabID];
  [self removeRuntimeForKind:self.historyTab.kind tabID:self.historyTab.tabID];
  self.historyTab = nil;

  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openChatTab:(NSButton *)sender {
  [self openChatTabWithID:sender.tag];
}

- (void)openChatTabWithID:(NSInteger)chatID {
  if (self.widgetbookMode) {
    return;
  }

  [self loadChatWithID:chatID];
}

- (void)closeChatTab:(NSButton *)sender {
  [self closeChatTabWithID:sender.tag];
}

- (void)closeChatTabWithID:(NSInteger)chatID {
  if (self.widgetbookMode) {
    return;
  }

  NSUInteger closedIndex = [self indexOfSessionChatID:chatID];
  if (closedIndex == NSNotFound) {
    return;
  }

  TLWorkspaceTab *tab = [self workspaceTabsOfKind:TLWorkspaceTabKindChat][closedIndex];
  if ([self closeWindowIfOnlyWorkspaceTab:tab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:tab];

  BOOL closingActiveChat = self.activeChat && self.activeChat.chatID == chatID;
  [self.appStateManager removeWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
  [self removeRuntimeForKind:TLWorkspaceTabKindChat tabID:chatID];

  if (closingActiveChat) {
    self.activeChat = nil;
    self.messages = [NSMutableArray array];
    [self resetMessageRowCache];
    self.promptTextView.string = @"";
    self.errorMessage = @"";
    [self updateWorkspaceMode];
    [self renderMessages];
  }

  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)handleLinkURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)modifierFlags {
  if (![self isBrowserURL:URL]) {
    return;
  }

  if ((modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand) {
    [NSWorkspace.sharedWorkspace openURL:URL];
    return;
  }

  [self openBrowserTabWithURL:URL];
}

- (void)handleBrowserTabRequestURL:(NSURL *)URL modifierFlags:(NSEventModifierFlags)modifierFlags {
  if (![self isBrowserURL:URL]) {
    return;
  }

  [self openBrowserTabWithURL:URL];
}

- (void)openBrowserTabWithURL:(NSURL *)URL {
  [self openBrowserTabWithURL:URL replacingChatTab:nil];
}

- (void)openBrowserURLFromChatInput:(NSURL *)URL {
  TLWorkspaceTab *source = [self activeWorkspaceTab];
  BOOL emptyChat = source && source.kind == TLWorkspaceTabKindChat && self.activeChat &&
    source.tabID == self.activeChat.chatID && !self.messages.count && !self.activeChat.messages.count &&
    !self.isSending && !self.isLoading && !self.messageInput.attachmentURLs.count &&
    !self.chatPresentation.queuedPrompts.count && !self.chatPresentation.queuedPromptInFlight;
  [self openBrowserTabWithURL:URL replacingChatTab:emptyChat ? source : nil];
}

- (void)openBrowserTabWithURL:(NSURL *)URL replacingChatTab:(TLWorkspaceTab *)source {
  [self openBrowserTabWithURL:URL replacingChatTab:source configuration:nil];
}

- (WKWebView *)openBrowserTabWithURL:(NSURL *)URL replacingChatTab:(TLWorkspaceTab *)source configuration:(WKWebViewConfiguration *)configuration {
  if (!configuration && ![self isBrowserURL:URL]) return nil;
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser
    tabID:self.nextBrowserTabID++ title:[self browserTabTitleForURL:URL]
    toolTip:URL.absoluteString URL:URL closeable:YES];
  // Install the supplied WebKit configuration before activation can create a runtime.
  if (configuration) [self ensureBrowserRuntimeForTab:tab configuration:configuration];
  if (source) {
    // Replacement retains the tab's position and presentation identity, which
    // also keeps an existing split attached to the same pane.
    [self.appStateManager replaceWorkspaceTabWithKind:source.kind tabID:source.tabID withTab:tab activate:YES];
    [self.chatPresentation.slashCommandUpdateTimer invalidate];
    [self removeRuntimeForKind:source.kind tabID:source.tabID];
    [self.modelDraftChats removeObjectForKey:@(source.tabID)];
    [self.attachmentDrafts removeObjectForKey:@(source.tabID)];
    [self.attachmentPromptDrafts removeObjectForKey:@(source.tabID)];
    self.chatPresentation = nil;
  } else {
    [self.appStateManager addWorkspaceTab:tab afterTab:[self activeWorkspaceTab] activate:YES];
  }
  if (configuration) [self ensureBrowserRuntimeForTab:tab configuration:configuration];
  else [self ensureBrowserRuntimeForTab:tab];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
  if (!configuration) return nil;
  TLBrowserTabController *controller = (id)[self runtimeForTab:tab].featureController;
  return [controller startInWindow:self.window configuration:configuration];
}

- (void)handleContextLinkURL:(NSURL *)URL destination:(TLBrowserLinkDestination)destination sourceIdentity:(NSString *)identity {
  TLWorkspaceTab *source = [self tabWithPresentationIdentity:identity];
  if (!source || ![self isBrowserURL:URL]) return;
  if (destination == TLBrowserLinkNewWindow) {
    [TLWebKitBrowserController.sharedController openURL:URL fromWindow:self.window modifierFlags:0];
    return;
  }
  [self openBrowserTabWithURL:URL];
  if (destination == TLBrowserLinkSplitView) [self splitTab:[self activeWorkspaceTab] besideTab:source onLeft:NO];
}
- (void)openLinkURL:(NSURL *)URL inSplitBesideBrowserTabID:(NSInteger)tabID {
  TLWorkspaceTab *source = [self browserTabWithID:tabID];
  if (source) [self handleContextLinkURL:URL destination:TLBrowserLinkSplitView sourceIdentity:TLWorkspaceTabIdentity(source)];
}

- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab { [self ensureBrowserRuntimeForTab:tab configuration:nil]; }
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab configuration:(WKWebViewConfiguration *)configuration {
  TLWorkspaceTabRuntime *existing = [self runtimeForTab:tab];
  if (existing) {
    if (existing.contentView) [self addWorkspaceContentView:existing.contentView];
    return;
  }
  NSURL *URL = tab.URL;
  if (!configuration && ![self isBrowserURL:URL]) return;
  CGFloat inputWidth = [self messageInputWidthForWindowWidth:NSWidth(self.window.frame)
    sidebarWidth:[self currentSidebarWidth] contentLeadingPadding:[self contentLeadingPadding]];
  TLBrowserTabController *controller = [[TLBrowserTabController alloc] initWithURL:URL palette:self.palette
    database:self.database orchestrator:self.agentOrchestrator inputWidth:inputWidth];
  TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime runtimeWithContentView:controller.view
    openAction:@selector(openBrowserTab:) closeAction:@selector(closeBrowserTab:)];
  runtime.featureController = controller;
  [self setRuntime:runtime forTab:tab];
  NSInteger tabID = tab.tabID;
  __weak typeof(self) weakSelf = self;
  controller.metadataChangedHandler = ^(NSString *title, NSURL *updatedURL) {
    TalariaWindowController *windowController = weakSelf;
    TLWorkspaceTab *updatedTab = [windowController browserTabWithID:tabID];
    if (!updatedTab) return;
    updatedTab.title = title;
    updatedTab.URL = updatedURL;
    updatedTab.toolTip = updatedURL.absoluteString ?: title;
    [windowController.appStateManager upsertWorkspaceTab:updatedTab activate:[windowController isWorkspaceTabActive:updatedTab]];
  };
  controller.historyChangedHandler = ^{ [weakSelf reloadHistoryPanel]; };
  controller.faviconChangedHandler = ^{ [weakSelf reloadWorkspaceTabs]; };
  __weak TLBrowserTabController *weakBrowser = controller;
  __block BOOL hasInitialHeaderColor = NO;
  controller.headerColorChangedHandler = ^{
    [weakSelf.workspaceTabsController refreshContentColorsAnimated:hasInitialHeaderColor && weakBrowser.headerColorChangesAnimated];
    hasInitialHeaderColor = weakBrowser.headerContentColor != nil;
  };
  controller.linkHandler = ^(NSURL *linkedURL, NSEventModifierFlags flags) {
    [weakSelf handleBrowserTabRequestURL:linkedURL modifierFlags:flags];
  };
  NSString *sourceIdentity = TLWorkspaceTabIdentity(tab);
  controller.contextLinkHandler = ^(NSURL *linkedURL, TLBrowserLinkDestination destination) {
    [weakSelf handleContextLinkURL:linkedURL destination:destination sourceIdentity:sourceIdentity];
  };
  controller.createTabHandler = ^WKWebView *(NSURL *URL, WKWebViewConfiguration *configuration) {
    return [weakSelf openBrowserTabWithURL:URL replacingChatTab:nil configuration:configuration];
  };
  controller.closeTabHandler = ^{ [weakSelf closeBrowserTabWithID:tabID]; };
  controller.settingsProvider = ^{ return weakSelf.settings; };
  controller.settingsRequiredHandler = ^{ [weakSelf showSettings:weakSelf]; };
  [self addWorkspaceContentView:controller.view];
  if (configuration) [controller startInWindow:self.window configuration:configuration];
  else [controller startInWindow:self.window];
}

- (void)reloadBookmarks {
  if (!self.sidebarShortcutsView) return;
  NSError *error = nil;
  NSArray *bookmarks = [self.database listBookmarks:&error];
  if (!bookmarks && error) { [self presentErrorMessage:error.localizedDescription]; return; }
  self.bookmarks = bookmarks ?: @[];
  [self.sidebarShortcutsView removeAllShortcutButtons];
  for (TLBookmark *bookmark in self.bookmarks) {
    TLSidebarShortcutButton *button = [TLSidebarShortcutButton new];
    button.palette = self.palette;
    button.title = bookmark.name;
    button.tag = bookmark.bookmarkID;
    button.URL = bookmark.URL;
    if (bookmark.chatID > 0) {
      NSString *emoji = bookmark.emoji.length ? bookmark.emoji : TLDefaultChatIcon();
      NSFont *font = self.palette.titleFont;
      CGFloat size = self.palette.sidebarBookmarkIconSize;
      button.image = [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        NSAttributedString *text = [[NSAttributedString alloc] initWithString:emoji attributes:@{NSFontAttributeName:font}];
        [text drawAtPoint:NSMakePoint((NSWidth(bounds) - text.size.width) / 2, (NSHeight(bounds) - text.size.height) / 2)];
        return YES;
      }];
    } else {
      button.image = bookmark.faviconData ? [[NSImage alloc] initWithData:bookmark.faviconData] : nil;
      if (!button.image) button.systemIconName = @"globe";
    }
    button.target = self;
    button.action = @selector(openSidebarBookmark:);
    button.menu = [self menuForSidebarBookmark:bookmark button:button];
    [self.sidebarShortcutsView addShortcutButton:button];
  }
}

- (NSMenu *)menuForSidebarBookmark:(TLBookmark *)bookmark button:(TLSidebarShortcutButton *)button {
  __weak typeof(self) weakSelf = self;
  NSMenu *menu;
  if (bookmark.URL) {
    menu = [TLBrowserLinkActions menuForURL:bookmark.URL canSplit:YES view:button
      point:NSMakePoint(NSMidX(button.bounds), NSMidY(button.bounds))
      open:^(NSURL *URL, TLBrowserLinkDestination destination) {
        [weakSelf openBookmark:bookmark destination:destination];
      } inspect:nil imageMenu:nil];
    // Sidebar shortcuts have no page element to inspect. Keep the separator
    // after Share for the bookmark-specific action below.
    [menu removeItem:[menu itemWithTitle:@"Inspect Element"]];
  } else {
    menu = [NSMenu new]; menu.autoenablesItems = NO;
    [menu addItem:[TLActionMenuItem itemWithTitle:@"Open Conversation in New Tab" action:^{
      [weakSelf openBookmark:bookmark destination:TLBrowserLinkNewTab];
    }]];
    [menu addItem:[TLActionMenuItem itemWithTitle:@"Open Conversation in Split View" action:^{
      [weakSelf openBookmark:bookmark destination:TLBrowserLinkSplitView];
    }]];
    [menu addItem:NSMenuItem.separatorItem];
  }
  NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"Delete bookmark" action:@selector(removeBookmark:) keyEquivalent:@""];
  remove.target = self; remove.tag = bookmark.bookmarkID; [menu addItem:remove];
  return menu;
}

- (void)openBookmarkURLInNewWindow:(NSURL *)URL {
  [TLWebKitBrowserController.sharedController openURL:URL fromWindow:self.window modifierFlags:0];
}

- (void)openBookmark:(TLBookmark *)bookmark destination:(TLBrowserLinkDestination)destination {
  TLWorkspaceTab *source = [self activeWorkspaceTab];
  if (bookmark.chatID > 0) [self openChatTabWithID:bookmark.chatID];
  else if (bookmark.URL) {
    if (destination == TLBrowserLinkNewWindow) { [self openBookmarkURLInNewWindow:bookmark.URL]; return; }
    [self openBrowserTabWithURL:bookmark.URL];
  } else return;
  if (destination == TLBrowserLinkSplitView && source)
    [self splitTab:[self activeWorkspaceTab] besideTab:source onLeft:NO];
}

- (TLBookmark *)bookmarkForCurrentPage {
  return [self bookmarkForTab:[self activeWorkspaceTab]];
}

- (TLBookmark *)bookmarkForTab:(TLWorkspaceTab *)tab {
  if (!tab || (tab.kind != TLWorkspaceTabKindBrowser && tab.kind != TLWorkspaceTabKindChat)) return nil;
  TLBookmark *bookmark = [TLBookmark new];
  bookmark.name = tab.title ?: @"";
  if (tab.kind == TLWorkspaceTabKindBrowser) {
    bookmark.URL = tab.URL;
    if (![TLBookmark normalizedURL:tab.URL.absoluteString]) return nil;
    TLBrowserTabController *browser = (TLBrowserTabController *)[self runtimeForTab:tab].featureController;
    NSImage *favicon = browser.favicon;
    if (favicon) {
      CGFloat size = self.palette.sidebarBookmarkButtonSize;
      NSImage *thumbnail = [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [favicon drawInRect:bounds]; return YES;
      }];
      NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:thumbnail.TIFFRepresentation];
      bookmark.faviconData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }
  } else {
    TLChatRecord *chat = self.activeChat.chatID == tab.tabID ? self.activeChat : self.chatPresentations[@(tab.tabID)].chat;
    if (!chat) chat = self.modelDraftChats[@(tab.tabID)];
    if (!chat && tab.tabID > 0) chat = [self.database chatWithID:tab.tabID error:nil];
    bookmark.chatID = tab.tabID;
    bookmark.name = chat.title.length ? chat.title : (tab.title.length ? tab.title : @"New chat");
    bookmark.emoji = chat.icon.length ? chat.icon : TLDefaultChatIcon();
  }
  return bookmark;
}

- (void)showAddBookmark:(id)sender {
  if (self.bookmarkPopover.shown) { [self.bookmarkPopover close]; return; }
  [self showBookmarkEditorForTab:[self activeWorkspaceTab]];
}

- (void)addTabToBookmarks:(NSMenuItem *)sender {
  TLWorkspaceTab *tab = [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(sender.representedObject)];
  [self showBookmarkEditorForTab:tab];
}

- (void)showBookmarkEditorForTab:(TLWorkspaceTab *)tab {
  TLBookmark *bookmark = [self bookmarkForTab:tab];
  if (!bookmark) return;
  [self.bookmarkPopover close];
  if (!self.sidebarVisible) {
    self.sidebarVisible = YES;
    [self updateSidebarLayoutAnimated:NO];
    [self.window.contentView layoutSubtreeIfNeeded];
  }
  NSString *sourceIdentity = TLWorkspaceTabIdentity(tab);
  self.bookmarkEditor = [[TLBookmarkEditorController alloc] initWithBookmark:bookmark palette:self.palette];
  self.bookmarkPopover = [NSPopover new];
  // Keep the editor open while the system emoji panel accepts input.
  self.bookmarkPopover.behavior = NSPopoverBehaviorSemitransient;
  __weak typeof(self) weakSelf = self;
  self.bookmarkEditor.contentSizeChangedHandler = ^(NSSize size) { weakSelf.bookmarkPopover.contentSize = size; };
  self.bookmarkPopover.contentViewController = self.bookmarkEditor;
  self.bookmarkPopover.appearance = self.bookmarkEditor.view.appearance;
  self.bookmarkEditor.saveHandler = ^BOOL(TLBookmark *entry, NSError **error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner) return NO;
    if (entry.chatID < 0) {
      TLWorkspaceTab *source = [owner tabWithPresentationIdentity:sourceIdentity];
      // A context-menu bookmark may refer to an inactive draft. Activate that
      // presentation before materializing it so its attachments stay with it.
      if (source && source.tabID < 0) [owner focusWorkspaceTab:source];
      if (source.tabID > 0) entry.chatID = source.tabID;
      else if (source && [owner isWorkspaceTabActive:source] &&
               [owner persistActiveDraftChatWithModel:owner.activeChat.model]) entry.chatID = owner.activeChat.chatID;
      else {
        if (error) *error = [NSError errorWithDomain:@"TLBookmarks" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Return to this conversation to bookmark it."}];
        return NO;
      }
    }
    if (![owner.database saveBookmark:entry error:error]) return NO;
    [owner reloadBookmarks];
    return YES;
  };
  self.bookmarkEditor.closeHandler = ^{
    NSPopover *popover = weakSelf.bookmarkPopover;
    // AppKit can ignore a close while the opening animation is still active.
    // Cancel and save must dismiss immediately, including keyboard activation.
    popover.animates = NO;
    [popover close];
  };
  NSView *anchor = self.sidebarShortcutsView.addButton;
  [self.bookmarkPopover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMinY];
}

- (void)openSidebarBookmark:(TLSidebarShortcutButton *)sender {
  for (TLBookmark *bookmark in self.bookmarks) {
    if (bookmark.bookmarkID != sender.tag) continue;
    if (bookmark.chatID > 0) [self openChatTabWithID:bookmark.chatID];
    else if (bookmark.URL) [self openBrowserTabWithURL:bookmark.URL];
    return;
  }
}

- (void)removeBookmark:(NSMenuItem *)sender {
  NSError *error = nil;
  if (![self.database deleteBookmarkWithID:sender.tag error:&error]) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not remove bookmark."];
    return;
  }
  [self reloadBookmarks];
}

- (nullable NSURL *)browserURLFromPromptString:(NSString *)promptString {
  return [TLInputSuggestions browserURLForInput:promptString];
}


- (void)openBrowserTab:(NSButton *)sender {
  [self openBrowserTabWithID:sender.tag];
}

- (void)openBrowserTabWithID:(NSInteger)tabID {
  if (self.widgetbookMode) {
    return;
  }

  TLWorkspaceTab *tab = [self browserTabWithID:tabID];
  if (!tab) {
    return;
  }

  [self activateTabKind:TLWorkspaceTabKindBrowser tabID:tab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)closeBrowserTab:(NSButton *)sender {
  [self closeBrowserTabWithID:sender.tag];
}

- (void)closeBrowserTabWithID:(NSInteger)tabID {
  if (self.widgetbookMode) {
    return;
  }

  NSUInteger closedIndex = [self indexOfBrowserTabID:tabID];
  if (closedIndex == NSNotFound) {
    return;
  }

  TLWorkspaceTab *tab = [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser][closedIndex];
  if ([self closeWindowIfOnlyWorkspaceTab:tab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:tab];
  TLWorkspaceTabRuntime *runtime = [self runtimeForTab:tab];
  [runtime.featureController close];
  [runtime.contentView removeFromSuperview];
  [self.appStateManager removeWorkspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:tab.tabID];
  [self removeRuntimeForKind:TLWorkspaceTabKindBrowser tabID:tab.tabID];

  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus {

  TLChatRecord *chat = [[TLChatRecord alloc] init];
  chat.chatID = self.nextDraftChatID;
  self.nextDraftChatID -= 1;
  chat.title = @"New chat";
  chat.model = model.length > 0 ? model : TLDefaultModelID;
  chat.supportingModel = self.settings.supportingModel;
  chat.messages = @[];
  self.activeChat = chat;
  [self addChatToSessionIfNeeded:chat.chatID activate:YES];
  [self showChatWorkspace];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  self.promptTextView.string = @"";
  [self selectActiveChatInHistory];
  [self renderMessages];
  [self updateControlStates];

  if (focus) {
    [self.window makeFirstResponder:self.promptTextView];
  }
}

- (void)clearActiveChat:(id)sender {
  if (!self.activeChat || self.isSending) {
    return;
  }

  if (self.activeChat.chatID <= 0) {
    self.messages = [NSMutableArray array];
    [self resetMessageRowCache];
    self.promptTextView.string = @"";
    [self renderMessages];
    [self updateControlStates];
    [self.window makeFirstResponder:self.promptTextView];
    return;
  }

  NSError *error = nil;
  TLChatRecord *chat = [self.database clearChatWithID:self.activeChat.chatID error:&error];
  if (!chat) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not clear chat."];
    return;
  }

  [self.turnMessagesByChat removeObjectForKey:@(chat.chatID)];
  self.activeChat = chat;
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  [self refreshChatsKeepingActiveSelection];
  [self renderMessages];
  [self updateControlStates];
  [self.window makeFirstResponder:self.promptTextView];
}

- (BOOL)persistActiveDraftChatWithModel:(NSString *)model {
  if (!self.activeChat || self.activeChat.chatID > 0) {
    return YES;
  }

  NSInteger draftChatID = self.activeChat.chatID;
  NSError *error = nil;
  TLChatRecord *persistedChat = [self.database createChatWithModel:model supportingModel:self.activeChat.supportingModel error:&error];
  if (!persistedChat) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not create chat."];
    return NO;
  }

  persistedChat.messages = @[];
  NSArray *draftURLs = self.messageInput.attachmentURLs;
  // Keep the same presentation when the draft gains its database identity.
  TLChatTabController *presentation = [self currentChatPresentation];
  self.chatPresentations[@(persistedChat.chatID)] = presentation;
  [self.chatPresentations removeObjectForKey:@(draftChatID)];
  presentation.chat = persistedChat;
  self.activeChat = persistedChat;
  [self.modelDraftChats removeObjectForKey:@(draftChatID)];
  self.messageInput.attachmentURLs = draftURLs;
  [self.attachmentDrafts removeObjectForKey:@(draftChatID)];
  [self.attachmentPromptDrafts removeObjectForKey:@(draftChatID)];
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                             tabID:persistedChat.chatID
                                             title:persistedChat.title.length > 0 ? persistedChat.title : @"New chat"
                                           toolTip:persistedChat.title.length > 0 ? persistedChat.title : @"New chat"
                                               URL:nil
                                         closeable:YES];
  // Promotion changes identity, not ownership. Replacing this runtime would
  // close the retained chat controller when the draft runtime is released.
  TLWorkspaceTabRuntime *runtime = [self runtimeForKind:TLWorkspaceTabKindChat tabID:draftChatID];
  if (!runtime) runtime = [TLWorkspaceTabRuntime runtimeWithContentView:self.chatWorkspace
                                                           openAction:@selector(openChatTab:)
                                                          closeAction:@selector(closeChatTab:)];
  [self setRuntime:runtime forTab:tab];
  [self.appStateManager replaceWorkspaceTabWithKind:TLWorkspaceTabKindChat
                                              tabID:draftChatID
                                            withTab:tab
                                           activate:YES];
  [self removeRuntimeForKind:TLWorkspaceTabKindChat tabID:draftChatID];
  [self showChatWorkspace];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
  return YES;
}

- (BOOL)preparingAttachments { return [self preparingAttachmentsForChat:[self currentChatPresentation]]; }
- (BOOL)preparingAttachmentsForChat:(TLChatTabController *)chatContext {
  return chatContext.chat && [self.preparingAttachmentChats containsObject:@(chatContext.chat.chatID)];
}

- (BOOL)isSending { return [self isSendingForChat:[self currentChatPresentation]]; }
- (BOOL)isSendingForChat:(TLChatTabController *)chatContext {
  return chatContext.chat && (self.turnRunners[@(chatContext.chat.chatID)] != nil || [self preparingAttachmentsForChat:chatContext]);
}

- (BOOL)hasSendingTurns {
  return self.turnRunners.count > 0 || self.preparingAttachmentChats.count > 0;
}

- (TLAssistantTurnRunner *)newAssistantTurnRunner {
  return [[TLAssistantTurnRunner alloc] initWithDatabase:self.database agentOrchestrator:self.agentOrchestrator];
}

- (BOOL)canStopResponse { return [self canStopResponseForChat:[self currentChatPresentation]]; }
- (BOOL)canStopResponseForChat:(TLChatTabController *)chatContext {
  return self.turnRunners[@(chatContext.chat.chatID)].running && [self isChatPresentationVisibleForChat:chatContext] &&
    chatContext.promptTextView.string.length == 0 && chatContext.messageInput.attachmentURLs.count == 0;
}

- (void)showChatModelMenu:(id)sender {
  [self focusChatContainingView:sender];
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Chat models"];
  NSString *large = self.activeChat.model ?: self.settings.selectedModel;
  NSString *small = self.activeChat.supportingModel ?: self.settings.supportingModel;
  for (NSNumber *smallChoice in @[@NO, @YES]) {
    BOOL isSmall = smallChoice.boolValue;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@: %@",
      isSmall ? @"Small model" : @"Large model", isSmall ? small : large]
      action:@selector(chooseChatModel:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = smallChoice;
    [menu addItem:item];
  }
  NSView *button = self.messageInput.settingsButton;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(button.bounds)) inView:button];
}

- (void)chooseChatModel:(NSMenuItem *)sender {
  if (self.window.attachedSheet) return;
  BOOL small = [sender.representedObject boolValue];
  TLChatRecord *chat = self.activeChat;
  NSString *largeModel = chat.model ?: self.settings.selectedModel;
  NSString *smallModel = chat.supportingModel ?: self.settings.supportingModel;
  TLModelSelectionWindowController *controller = [[TLModelSelectionWindowController alloc]
    initWithSmallModel:small selectedModel:small ? smallModel : largeModel token:self.settings.openRouterToken
    orchestrator:self.agentOrchestrator palette:self.palette];
  self.modelSelectionController = controller;
  __weak typeof(self) weakSelf = self;
  controller.selectionHandler = ^(NSString *model, void (^completion)(NSError *)) {
    typeof(self) owner = weakSelf;
    if (!owner) return;
    NSString *largeChoice = small ? largeModel : model;
    NSString *smallChoice = small ? model : smallModel;
    void (^saveSelection)(NSError *) = ^(NSError *switchError) {
      if (switchError) { completion(switchError); return; }
      NSError *error = nil;
      if (![owner.database saveModelsForChatID:chat.chatID model:largeChoice supportingModel:smallChoice error:&error]) {
        completion(error); return;
      }
      chat.model = largeChoice;
      chat.supportingModel = smallChoice;
      owner.settings.selectedModel = largeChoice;
      owner.settings.supportingModel = smallChoice;
      for (TLChatSummary *summary in owner.chats) {
        if (summary.chatID == chat.chatID) { summary.model = largeChoice; summary.supportingModel = smallChoice; }
      }
      [owner updateControlStates];
      completion(nil);
    };
    // Small models use isolated supporting sessions. Draft chats have no Hermes
    // conversation yet; their selection is verified when the first turn starts.
    if (small || !chat.hermesSessionID.length) { saveSelection(nil); return; }
    [owner.agentOrchestrator selectModel:model sessionID:chat.continuationSessionID.length ? chat.continuationSessionID : chat.hermesSessionID
      agentID:chat.sourceAgentID token:owner.settings.openRouterToken
      completion:saveSelection];
  };
  [controller presentForWindow:self.window];
}

- (BOOL)hasPendingChatApproval { return [self hasPendingChatApprovalForChat:[self currentChatPresentation]]; }
- (BOOL)hasPendingChatApprovalForChat:(TLChatTabController *)chatContext {
  for (TLChatMessage *message in chatContext.messages) {
    if (message.approvalRequest && ![message.approvalRequest[@"submitted"] boolValue]) return YES;
  }
  return NO;
}

- (void)updatePromptQueue { [self updatePromptQueueForChat:[self currentChatPresentation]]; }
- (void)updatePromptQueueForChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (!presentation.promptQueueView) return;
  [presentation.promptQueueView updatePrompts:presentation.queuedPrompts editing:presentation.editingQueuedPrompt
    paused:presentation.queuePaused canResume:![self isSendingForChat:chatContext] && ![self hasPendingChatApprovalForChat:chatContext]
    canSendNow:![self preparingAttachmentsForChat:chatContext] && !presentation.queueInterruptPending && ![self hasPendingChatApprovalForChat:chatContext] palette:self.palette];
}

- (void)sendQueuedPromptNowAtIndex:(NSUInteger)index { [self sendQueuedPromptNowAtIndex:index forChat:[self currentChatPresentation]]; }
- (void)sendQueuedPromptNowAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (index >= presentation.queuedPrompts.count || presentation.editingQueuedPrompt ||
      presentation.queueInterruptPending || [self preparingAttachmentsForChat:chatContext] || [self hasPendingChatApprovalForChat:chatContext]) return;
  TLQueuedPrompt *prompt = presentation.queuedPrompts[index];
  [presentation.queuedPrompts removeObjectAtIndex:index];
  [presentation.queuedPrompts insertObject:prompt atIndex:0];
  presentation.queuePaused = NO;
  TLAssistantTurnRunner *runner = self.turnRunners[@(presentation.chat.chatID)];
  if (runner) {
    // Cancellation finalizes the partial reply synchronously. Its completion
    // schedules dispatch after cancel has also reached the transport.
    presentation.queueInterruptPending = YES;
    [self updateControlStatesForChat:chatContext];
    [runner cancel];
  } else {
    [self drainPromptQueueForChat:chatContext];
  }
}

- (void)editQueuedPromptAtIndex:(NSUInteger)index { [self editQueuedPromptAtIndex:index forChat:[self currentChatPresentation]]; }
- (void)editQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (presentation.editingQueuedPrompt || presentation.queueInterruptPending || index >= presentation.queuedPrompts.count || [self preparingAttachmentsForChat:chatContext]) return;
  presentation.queueDraft = [TLQueuedPrompt promptWithText:chatContext.promptTextView.string attachmentURLs:chatContext.messageInput.attachmentURLs];
  presentation.editingQueuedPrompt = presentation.queuedPrompts[index];
  chatContext.promptTextView.string = presentation.editingQueuedPrompt.text;
  chatContext.messageInput.attachmentURLs = presentation.editingQueuedPrompt.attachmentURLs;
  [self updateControlStatesForChat:chatContext];
  [self.window makeFirstResponder:chatContext.promptTextView];
}

- (void)finishQueuedPromptEditingSaving:(BOOL)save { [self finishQueuedPromptEditingSaving:save forChat:[self currentChatPresentation]]; }
- (void)finishQueuedPromptEditingSaving:(BOOL)save  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (!presentation.editingQueuedPrompt) return;
  if (save) {
    NSString *text = [chatContext.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length && !chatContext.messageInput.attachmentURLs.count) return;
    presentation.editingQueuedPrompt.text = text;
    presentation.editingQueuedPrompt.attachmentURLs = chatContext.messageInput.attachmentURLs;
  }
  chatContext.promptTextView.string = presentation.queueDraft.text ?: @"";
  chatContext.messageInput.attachmentURLs = presentation.queueDraft.attachmentURLs ?: @[];
  presentation.queueDraft = nil;
  presentation.editingQueuedPrompt = nil;
  [self updateControlStatesForChat:chatContext];
  [self drainPromptQueueForChat:chatContext];
}

- (void)removeQueuedPromptAtIndex:(NSUInteger)index { [self removeQueuedPromptAtIndex:index forChat:[self currentChatPresentation]]; }
- (void)removeQueuedPromptAtIndex:(NSUInteger)index  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (presentation.queueInterruptPending || index >= presentation.queuedPrompts.count) return;
  BOOL editing = presentation.editingQueuedPrompt == presentation.queuedPrompts[index];
  [presentation.queuedPrompts removeObjectAtIndex:index];
  if (editing) [self finishQueuedPromptEditingSaving:NO forChat:chatContext];
  [self updateControlStatesForChat:chatContext];
}

- (void)pausePromptQueueRestoringInFlight:(BOOL)restore { [self pausePromptQueueRestoringInFlight:restore forChat:[self currentChatPresentation]]; }
- (void)pausePromptQueueRestoringInFlight:(BOOL)restore  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if (restore && presentation.queuedPromptInFlight) [presentation.queuedPrompts insertObject:presentation.queuedPromptInFlight atIndex:0];
  presentation.queuedPromptInFlight = nil;
  presentation.queueInterruptPending = NO;
  presentation.queuePaused = YES;
  [self updateControlStatesForChat:chatContext];
}

- (void)finishQueuedTurnWithResult:(TLAssistantTurnResult *)result { [self finishQueuedTurnWithResult:result forChat:[self currentChatPresentation]]; }
- (void)finishQueuedTurnWithResult:(TLAssistantTurnResult *)result  forChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  BOOL interruptedForQueuedPrompt = presentation.queueInterruptPending &&
    result.generationStatus == TLAssistantTurnGenerationStatusCancelled;
  if ((!interruptedForQueuedPrompt && result.generationStatus != TLAssistantTurnGenerationStatusSucceeded) ||
      result.persistenceStatus != TLAssistantTurnPersistenceStatusSucceeded || result.assistantMessage.approvalRequest) {
    [self pausePromptQueueRestoringInFlight:result.generationStatus == TLAssistantTurnGenerationStatusNotStarted forChat:chatContext];
    return;
  }
  presentation.queuedPromptInFlight = nil;
  // Leave the completion stack before starting the next turn, including synchronous failures.
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (presentation) [weakSelf drainPromptQueueForChat:presentation];
  });
}

- (void)drainPromptQueue { [self drainPromptQueueForChat:[self currentChatPresentation]]; }
- (void)drainPromptQueueForChat:(TLChatTabController *)chatContext {
  TLChatTabController *presentation = chatContext;
  if ([self isSendingForChat:chatContext] || presentation.queuePaused || presentation.editingQueuedPrompt ||
      presentation.queuedPromptInFlight || !presentation.queuedPrompts.count || [self hasPendingChatApprovalForChat:chatContext]) return;
  NSString *token = self.settings.openRouterToken ?: @"";
  NSString *model = presentation.chat.model ?: self.settings.selectedModel ?: @"";
  if (!token.length || !model.length) { presentation.queueInterruptPending = NO; presentation.queuePaused = YES; [self updateControlStatesForChat:chatContext]; return; }
  presentation.queueInterruptPending = NO;
  TLQueuedPrompt *prompt = presentation.queuedPrompts.firstObject;
  [presentation.queuedPrompts removeObjectAtIndex:0];
  presentation.queuedPromptInFlight = prompt;
  NSString *text = prompt.text;
  if (!text.length) {
    TLPromptBuilder *builder = [TLPromptBuilder new];
    text = [[builder addPartWithContent:@"Please inspect the attached files and folders." importance:TLPromptImportanceRequired
      strategy:TLPromptCompactionStrategyWhole name:@"file-only-request"] build];
  }
  void (^start)(NSArray *) = ^(NSArray *attachments) {
    {
      TLChatTabController *originChat = presentation;
      if (originChat) {
        if (presentation.queuePaused) { [self pausePromptQueueRestoringInFlight:YES forChat:originChat]; return; }
        originChat.errorMessage = @"";
        [self beginPreparedTurnWithChat:presentation.chat messages:presentation.messages token:token model:model prompt:text
          attachments:attachments sourceURLs:prompt.attachmentURLs];
        [self updateControlStatesForChat:originChat];
      }
    }
  };
  if (prompt.attachmentURLs.count) {
    if (!self.preparingAttachmentChats) self.preparingAttachmentChats = [NSMutableSet set];
    [self.preparingAttachmentChats addObject:@(presentation.chat.chatID)];
    [self updateControlStatesForChat:chatContext];
    [self.agentOrchestrator prepareAttachmentURLs:prompt.attachmentURLs
      sessionID:presentation.chat.continuationSessionID.length ? presentation.chat.continuationSessionID : presentation.chat.hermesSessionID
      agentID:presentation.chat.sourceAgentID
      completion:^(NSArray *attachments, NSError *error) {
        [self.preparingAttachmentChats removeObject:@(presentation.chat.chatID)];
        if (!attachments) {
          {
            TLChatTabController *originChat = presentation;
            if (originChat) {
              [self pausePromptQueueRestoringInFlight:YES forChat:originChat];
              originChat.errorMessage = error.localizedDescription ?: @"Could not copy queued attachments.";
              [originChat renderMessagesScrollingToBottom:YES];
            }
          }
          return;
        }
        start(attachments);
      }];
  } else start(@[]);
}

- (void)activateComposerButton:(id)sender {
  [self focusChatContainingView:sender];
  if (!self.chatPresentation.editingQueuedPrompt && [self canStopResponse]) {
    self.chatPresentation.queuePaused = YES;
    self.chatPresentation.queueInterruptPending = NO;
    [self updatePromptQueue];
    [self.turnRunners[@(self.activeChat.chatID)] cancel];
  } else {
    [self sendMessage:sender];
  }
}

- (void)sendMessage:(id)sender {
  [self flushSlashCommandUpdate];
  if (!self.messageInput.attachmentURLs.count && [self performSelectedSlashCommand]) {
    return;
  }
  [self sendMessage:sender allowAutomaticRouting:YES];
}

- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting {
  NSString *token = [self.settings.openRouterToken stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *model = [(self.activeChat.model ?: self.settings.selectedModel) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *nextPrompt = [self.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

  NSArray<NSURL *> *sourceURLs = self.messageInput.attachmentURLs;
  if (sourceURLs.count) allowAutomaticRouting = NO;
  if (self.preparingAttachments || (!nextPrompt.length && !sourceURLs.count)) return;
  if (self.chatPresentation.editingQueuedPrompt) {
    [self finishQueuedPromptEditingSaving:YES];
    return;
  }
  NSURL *browserURL = allowAutomaticRouting ? [self browserURLFromPromptString:nextPrompt] : nil;
  if (browserURL) {
    self.promptTextView.string = @"";
    [self.messageInput recalculateHeight];
    [self updateMessageScrollInsets];
    [self updateSlashCommandList];
    [self openBrowserURLFromChatInput:browserURL];
    return;
  }

  if (self.isSending || self.chatPresentation.queuedPrompts.count) {
    [self.chatPresentation.queuedPrompts addObject:[TLQueuedPrompt promptWithText:nextPrompt attachmentURLs:sourceURLs]];
    self.promptTextView.string = @"";
    self.messageInput.attachmentURLs = @[];
    [self updateControlStates];
    [self drainPromptQueue];
    return;
  }

  if (!nextPrompt.length) {
    TLPromptBuilder *builder = [[TLPromptBuilder alloc] init];
    nextPrompt = [[builder addPartWithContent:@"Please inspect the attached files and folders." importance:TLPromptImportanceRequired
                                    strategy:TLPromptCompactionStrategyWhole name:@"file-only-request"] build];
  }

  if (model.length == 0) {
    return;
  }


  if (!self.activeChat) {
    [self startNewChatWithModel:model focus:NO];
  }

  if (![self persistActiveDraftChatWithModel:model]) {
    return;
  }

  self.chatPresentation.queuePaused = NO;
  TLChatRecord *chat = self.activeChat;
  NSMutableArray<TLChatMessage *> *turnMessages = self.messages;
  if (sourceURLs.count) {
    if (!self.preparingAttachmentChats) self.preparingAttachmentChats = [NSMutableSet set];
    [self.preparingAttachmentChats addObject:@(chat.chatID)];
    [self updateControlStates];
    [self.agentOrchestrator prepareAttachmentURLs:sourceURLs sessionID:chat.continuationSessionID.length ? chat.continuationSessionID : chat.hermesSessionID agentID:chat.sourceAgentID
      completion:^(NSArray *attachments, NSError *error) {
        [self.preparingAttachmentChats removeObject:@(chat.chatID)];
        if (!attachments) {
          [self restoreAttachmentDraft:sourceURLs prompt:nextPrompt chatID:chat.chatID];
          [self presentErrorMessage:error.localizedDescription ?: @"Could not copy attachments."];
          [self updateControlStates];
          return;
        }
        [self beginPreparedTurnWithChat:chat messages:turnMessages token:token model:model prompt:nextPrompt
                           attachments:attachments sourceURLs:sourceURLs];
      }];
  } else {
    [self beginPreparedTurnWithChat:chat messages:turnMessages token:token model:model prompt:nextPrompt
                       attachments:@[] sourceURLs:@[]];
  }
}

- (void)beginPreparedTurnWithChat:(TLChatRecord *)chat messages:(NSMutableArray<TLChatMessage *> *)turnMessages
                          token:(NSString *)token model:(NSString *)model prompt:(NSString *)nextPrompt
                    attachments:(NSArray<NSDictionary<NSString *, id> *> *)attachments sourceURLs:(NSArray<NSURL *> *)sourceURLs {
  [self beginPreparedTurnWithChat:chat messages:turnMessages token:token model:model prompt:nextPrompt
                     attachments:attachments sourceURLs:sourceURLs approvalResponse:nil];
}

- (void)beginPreparedTurnWithChat:(TLChatRecord *)chat messages:(NSMutableArray<TLChatMessage *> *)turnMessages
                          token:(NSString *)token model:(NSString *)model prompt:(NSString *)nextPrompt
                    attachments:(NSArray<NSDictionary<NSString *, id> *> *)attachments sourceURLs:(NSArray<NSURL *> *)sourceURLs
               approvalResponse:(NSDictionary *)approvalResponse {
  [self beginPreparedTurnWithChat:chat messages:turnMessages token:token model:model prompt:nextPrompt
    attachments:attachments sourceURLs:sourceURLs approvalResponse:approvalResponse regenerationPrompt:nil regenerationMessage:nil];
}

- (void)beginPreparedTurnWithChat:(TLChatRecord *)chat messages:(NSMutableArray<TLChatMessage *> *)turnMessages
                          token:(NSString *)token model:(NSString *)model prompt:(NSString *)nextPrompt
                    attachments:(NSArray<NSDictionary<NSString *, id> *> *)attachments sourceURLs:(NSArray<NSURL *> *)sourceURLs
               approvalResponse:(NSDictionary *)approvalResponse regenerationPrompt:(TLChatMessage *)regenerationPrompt
            regenerationMessage:(TLChatMessage *)regenerationMessage {
  TLChatTabController *origin = self.chatPresentations[@(chat.chatID)];
  origin.notificationTargetMessageID = nil;
  origin.notificationTargetToolCallID = nil;
  origin.notificationDidReveal = nil;
  origin.suppressAutomaticScroll = NO;
  if (!regenerationPrompt && !approvalResponse && !self.chatPresentations[@(chat.chatID)].queuedPromptInFlight) {
    self.attachmentDrafts[@(chat.chatID)] = @[];
    self.attachmentPromptDrafts[@(chat.chatID)] = @"";
    {
      TLChatTabController *originChat = self.chatPresentations[@(chat.chatID)];
      if (originChat) {
        originChat.promptTextView.string = @"";
        originChat.messageInput.attachmentURLs = @[];
        originChat.errorMessage = @"";
        [originChat.messageInput recalculateHeight];
        [self updateControlStatesForChat:originChat];
      }
    }
  }
  TLAssistantTurnRunner *runner = [self newAssistantTurnRunner];
  if (!self.turnRunners) self.turnRunners = [NSMutableDictionary dictionary];
  if (!self.turnMessagesByChat) self.turnMessagesByChat = [NSMutableDictionary dictionary];
  self.turnRunners[@(chat.chatID)] = runner;
  self.turnMessagesByChat[@(chat.chatID)] = turnMessages;
  runner.attachments = attachments;
  runner.approvalResponse = approvalResponse;
  runner.regenerationPrompt = regenerationPrompt;
  runner.regenerationMessage = regenerationMessage;
  __weak typeof(self) weakSelf = self;

  NSError *startError = nil;
  BOOL started = [runner startTurnWithChat:chat
                                                       token:token
                                                       model:model
                                                    messages:turnMessages
                                                  nextPrompt:nextPrompt
                                               updateHandler:^{
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    TLChatTabController *presentation = strongSelf.chatPresentations[@(chat.chatID)];
    if (![presentation.chatWorkspace isHiddenOrHasHiddenAncestor]) {
      [presentation markMessageDirty:strongSelf.turnRunners[@(chat.chatID)].streamingMessage];
      [presentation scheduleStreamingMessageRender];
      [strongSelf updateControlStatesForChat:presentation];
    }
  } completionHandler:^(TLAssistantTurnResult *result) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    [strongSelf.turnRunners removeObjectForKey:@(chat.chatID)];
    if (approvalResponse && result.generationStatus == TLAssistantTurnGenerationStatusNotStarted) {
      [strongSelf restorePendingApproval:approvalResponse inMessages:turnMessages];
    }
    BOOL hasApproval = NO;
    for (TLChatMessage *message in turnMessages) if (message.approvalRequest) hasApproval = YES;
    if (!hasApproval) [strongSelf.turnMessagesByChat removeObjectForKey:@(chat.chatID)];
    BOOL showingOrigin = strongSelf.activeChat.chatID == chat.chatID && [strongSelf isChatWorkspaceActive];
    if (!regenerationPrompt && !approvalResponse && !strongSelf.chatPresentations[@(chat.chatID)].queuedPromptInFlight && result.generationStatus == TLAssistantTurnGenerationStatusNotStarted) {
      [strongSelf restoreAttachmentDraft:sourceURLs prompt:nextPrompt chatID:chat.chatID];
    }
    if (!regenerationPrompt && !approvalResponse && !strongSelf.chatPresentations[@(chat.chatID)].queuedPromptInFlight && showingOrigin && result.generationStatus == TLAssistantTurnGenerationStatusNotStarted) {
      strongSelf.promptTextView.string = result.userMessage.content;
      [strongSelf.messageInput recalculateHeight];
      [strongSelf updateMessageScrollInsets];
    }

    {
      TLChatTabController *originChat = strongSelf.chatPresentations[@(chat.chatID)];
      if (originChat) {
        [strongSelf finishQueuedTurnWithResult:result forChat:originChat];
      }
    }

    if ([nextPrompt hasPrefix:@"/"]) strongSelf.hermesCommandsFetchedAt = nil;
    [strongSelf refreshChatsKeepingActiveSelection];
    if (!result.assistantMessage.approvalRequest && result.generationStatus == TLAssistantTurnGenerationStatusSucceeded &&
        result.persistenceStatus == TLAssistantTurnPersistenceStatusSucceeded) {
      [strongSelf generateChatIconIfNeededForChatID:chat.chatID messages:turnMessages];
    }
    if (showingOrigin) [strongSelf renderMessages];
    else {
      TLChatTabController *originChat = strongSelf.chatPresentations[@(chat.chatID)];
      if (originChat) {
        [originChat renderMessagesScrollingToBottom:YES];
        [strongSelf updateControlStatesForChat:originChat];
      }
    }
    [strongSelf updateControlStates];
    if (showingOrigin) [strongSelf.window makeFirstResponder:strongSelf.promptTextView];

    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    if (result.generationError) {
      [errors addObject:[NSString stringWithFormat:@"Request failed: %@", result.generationError.localizedDescription]];
    }
    if (result.persistenceError) {
      [errors addObject:[NSString stringWithFormat:@"Could not save conversation: %@", result.persistenceError.localizedDescription]];
    }
    if (errors.count && showingOrigin) {
      [strongSelf presentErrorMessage:[errors componentsJoinedByString:@"\n\n"]];
    } else if (errors.count) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = [NSString stringWithFormat:@"Conversation: %@", chat.title ?: @"Chat"];
      alert.informativeText = [errors componentsJoinedByString:@"\n\n"];
      [alert beginSheetModalForWindow:strongSelf.window completionHandler:nil];
    }
  } error:&startError];

  // The first prompt saves the durable title synchronously, before any deltas.
  // Publish it now so background streaming tabs never fall back to "New chat".
  if (started && self.turnRunners[@(chat.chatID)]) {
    [self refreshChatsKeepingActiveSelection];
  }
  if (!started) {
    [self.turnRunners removeObjectForKey:@(chat.chatID)];
    if (approvalResponse) [self restorePendingApproval:approvalResponse inMessages:turnMessages];
    if (!approvalResponse) {
      [self.turnMessagesByChat removeObjectForKey:@(chat.chatID)];
      if (!regenerationPrompt && !self.chatPresentations[@(chat.chatID)].queuedPromptInFlight)
        [self restoreAttachmentDraft:sourceURLs prompt:nextPrompt chatID:chat.chatID];
    }
    TLChatTabController *originChat = self.chatPresentations[@(chat.chatID)];
    if (originChat) [self pausePromptQueueRestoringInFlight:YES forChat:originChat];
    [self presentErrorMessage:startError.localizedDescription ?: @"Could not start assistant turn."];
    [self updateControlStates];
  }
}

- (void)restorePendingApproval:(NSDictionary *)response inMessages:(NSArray<TLChatMessage *> *)messages {
  for (TLChatMessage *message in messages) {
    if ([message.approvalRequest[@"request_id"] isEqual:response[@"request_id"]]) {
      NSMutableDictionary *request = [message.approvalRequest mutableCopy];
      [request removeObjectForKey:@"submitted"];
      message.approvalRequest = request;
    }
  }
}

- (BOOL)respondToApproval:(NSString *)requestID choice:(NSString *)choice chatID:(NSInteger)chatID {
  if (self.activeChat.chatID != chatID || self.isSending) return NO;
  TLChatMessage *pending = nil;
  for (TLChatMessage *message in self.messages) {
    if ([message.approvalRequest[@"request_id"] isEqual:requestID] && ![message.approvalRequest[@"submitted"] boolValue]) pending = message;
  }
  if (!pending || ![TLApprovalChoices(pending.approvalRequest) containsObject:choice]) return NO;
  if (!self.settings.selectedModel.length) {
    [self presentErrorMessage:@"Choose a model before responding to Hermes."];
    return NO;
  }
  NSMutableDictionary *request = [pending.approvalRequest mutableCopy];
  request[@"submitted"] = @YES;
  pending.approvalRequest = request;
  NSDictionary *response = @{@"request_id":requestID, @"choice":choice};
  [self beginPreparedTurnWithChat:self.activeChat messages:self.messages token:self.settings.openRouterToken
    model:self.settings.selectedModel prompt:TLApprovalChoiceTitle(choice) attachments:@[] sourceURLs:@[] approvalResponse:response];
  return [pending.approvalRequest[@"submitted"] boolValue];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsMatchingPrompt:(NSString *)prompt {
  NSString *trimmed = [prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (![trimmed hasPrefix:@"/"]) return [TLInputSuggestions webSuggestionsForInput:trimmed];
  return [TLInputSuggestions slashCommandsForInput:prompt commands:[self availableSlashCommands]];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSlashCommands {
  return self.hermesCommands ?: @[];
}

- (void)prepareHermesCommands {
  self.hermesCommandsAgentID = self.database.currentAgentID;
  self.hermesCommandsRequestID = nil;
  self.loadingHermesCommands = NO;
  self.hermesCommandsFetchedAt = nil;
  self.hermesCommandsError = nil;
  NSDictionary *cached = [self.agentOrchestrator cachedHermesCommands];
  self.hermesCommands = cached ? [TLInputSuggestions hermesCommandsFromCatalogue:cached] : @[];
  // Let AppKit finish presenting the window before beginning VM startup.
  dispatch_async(dispatch_get_main_queue(), ^{ [self refreshHermesCommandsIfNeeded]; });
}

- (void)refreshHermesCommandsIfNeeded {
  if (self.loadingHermesCommands || (self.hermesCommandsFetchedAt && -self.hermesCommandsFetchedAt.timeIntervalSinceNow < 60)) return;
  self.loadingHermesCommands = YES;
  self.hermesCommandsError = nil;
  NSString *requestID = NSUUID.UUID.UUIDString;
  self.hermesCommandsRequestID = requestID;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator fetchHermesCommandsWithToken:self.settings.openRouterToken ?: @""
                                               model:self.settings.selectedModel ?: @""
                                          completion:^(NSDictionary *catalogue, NSError *error) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) return;
    if (![strongSelf.hermesCommandsRequestID isEqualToString:requestID]) return;
    strongSelf.loadingHermesCommands = NO;
    strongSelf.hermesCommandsFetchedAt = NSDate.date;
    strongSelf.hermesCommandsError = error.localizedDescription;
    if (catalogue) strongSelf.hermesCommands = [TLInputSuggestions hermesCommandsFromCatalogue:catalogue];
    strongSelf.quickInputController.commands = strongSelf.hermesCommands ?: @[];
    [strongSelf updateSlashCommandList];
  }];
}

- (NSView *)buildSlashCommandListView { return [[self currentChatPresentation] buildSlashCommandListView]; }

- (void)applySlashCommandListPalette { [self applySlashCommandListPaletteForChat:[self currentChatPresentation]]; }
- (void)applySlashCommandListPaletteForChat:(TLChatTabController *)chatContext {
  if (!chatContext.slashCommandListView) {
    return;
  }
  chatContext.slashCommandListView.palette = self.palette;
  chatContext.slashCommandScrollView.palette = self.palette;
  chatContext.slashCommandListBottomConstraint.constant = -self.palette.space5;
}

- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands { return [self slashCommandListWidthForCommands:commands forChat:[self currentChatPresentation]]; }
- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext {
  CGFloat availableInputWidth = NSWidth(chatContext.messageInput.bounds);
  if (availableInputWidth <= self.palette.space0) {
    availableInputWidth = chatContext.messageInputWidthConstraint.constant;
  }
  if (availableInputWidth <= self.palette.space0) {
    availableInputWidth = self.palette.messageInputMaxWidth;
  }

  CGFloat maximum = availableInputWidth * 0.9;
  CGFloat padding = self.palette.space3 * 2;
  return MIN(maximum, padding + [chatContext.slashCommandScrollView preferredWidthWithMaximum:MAX(0, maximum - padding)]);
}

- (void)showSlashCommandListWithCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands { [self showSlashCommandListWithCommands:commands forChat:[self currentChatPresentation]]; }
- (void)showSlashCommandListWithCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands  forChat:(TLChatTabController *)chatContext {
  CGFloat rowHeight = self.palette.slashCommandRowHeight;
  CGFloat padding = self.palette.space2;

  BOOL changed = ![chatContext.visibleSlashCommands isEqualToArray:commands];
  chatContext.visibleSlashCommands = [commands copy];
  chatContext.slashCommandScrollView.suggestions = commands;
  if (changed) chatContext.selectedSlashCommandIndex = -1;
  [self applySlashCommandListPaletteForChat:chatContext];
  CGFloat availableHeight = MAX(rowHeight + padding * 2, NSHeight(self.rootView.bounds) * 0.4);
  CGFloat contentHeight = chatContext.slashCommandScrollView.contentHeight;
  CGFloat heightLimit = MIN(availableHeight, (rowHeight + self.palette.space2) * 8 + padding * 2);
  chatContext.slashCommandListHeightConstraint.constant = MIN(contentHeight + padding * 2, heightLimit);
  chatContext.slashCommandScrollView.scrollingEnabled = contentHeight + padding * 2 > heightLimit;
  chatContext.slashCommandListWidthConstraint.constant = [self slashCommandListWidthForCommands:commands forChat:chatContext];
  chatContext.slashCommandListView.hidden = NO;
  [chatContext updateMessageScrollInsets];
}

- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex { [self setSelectedSlashCommandIndexAndUpdateRows:selectedIndex forChat:[self currentChatPresentation]]; }
- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex  forChat:(TLChatTabController *)chatContext {
  chatContext.slashCommandScrollView.selectedIndex = selectedIndex;
  chatContext.selectedSlashCommandIndex = chatContext.slashCommandScrollView.selectedIndex;
}

- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset { return [self moveSlashCommandSelectionByOffset:offset forChat:[self currentChatPresentation]]; }
- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset  forChat:(TLChatTabController *)chatContext {
  if (chatContext.slashCommandListView.hidden) return NO;
  BOOL moved = [chatContext.slashCommandScrollView moveSelectionByOffset:offset];
  chatContext.selectedSlashCommandIndex = chatContext.slashCommandScrollView.selectedIndex;
  return moved;
}

- (BOOL)performSelectedSlashCommand {
  NSInteger selectedIndex = self.selectedSlashCommandIndex;
  if (self.slashCommandListView.hidden || selectedIndex < 0 || selectedIndex >= (NSInteger)self.visibleSlashCommands.count) {
    return NO;
  }
  return [self performInputSuggestionAtIndex:(NSUInteger)selectedIndex];
}

- (BOOL)performInputSuggestionAtIndex:(NSUInteger)index {
  if (self.preparingAttachments || self.chatPresentation.editingQueuedPrompt || self.messageInput.attachmentURLs.count ||
      index >= self.visibleSlashCommands.count || ![self.slashCommandScrollView isSuggestionEnabledAtIndex:index]) {
    return NO;
  }
  NSDictionary<NSString *, NSString *> *suggestion = self.visibleSlashCommands[index];
  if (![[self slashCommandsMatchingPrompt:self.promptTextView.string ?: @""] containsObject:suggestion]) {
    return NO;
  }
  if ([suggestion[@"kind"] isEqualToString:@"web"]) {
    NSURL *URL = [TLInputSuggestions browserURLForInput:suggestion[@"value"]];
    if (!URL) { return NO; }
    self.promptTextView.string = @"";
    [self.messageInput recalculateHeight];
    [self hideSlashCommandList];
    [self openBrowserURLFromChatInput:URL];
    return YES;
  }
  if ([suggestion[@"kind"] isEqualToString:@"prompt"]) {
    self.promptTextView.string = suggestion[@"value"];
    [self hideSlashCommandList];
    [self sendMessage:self allowAutomaticRouting:NO];
    return YES;
  }
  NSString *command = suggestion[@"command"];
  NSString *current = [self.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if ([current caseInsensitiveCompare:command] == NSOrderedSame) {
    [self hideSlashCommandList];
    [self sendMessage:self allowAutomaticRouting:NO];
  } else {
    self.promptTextView.string = [command stringByAppendingString:@" "];
    [self.messageInput recalculateHeight];
    [self hideSlashCommandList];
    [self.window makeFirstResponder:self.promptTextView];
    [self.promptTextView setSelectedRange:NSMakeRange(self.promptTextView.string.length, 0)];
    [self updateControlStates];
  }
  return YES;
}

- (void)addUrgentNotification {
  TLSidebarInboxStackView *urgentNotification =
    [self sidebarInboxStackViewWithTitle:@"AWS Oregon Outage"
                                subtitle:@"service monitoring"
                          systemIconName:@"eye"
                       notificationCount:1];
  urgentNotification.urgent = YES;
  urgentNotification.showsSeparator = NO;
  urgentNotification.target = self;
  urgentNotification.action = @selector(openAWSOutageChat:);
  [self.sidebarInboxPaneView insertInboxItemView:urgentNotification atIndex:0];

  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf addDelayedCalendarConflictNotification];
  });
}

- (void)openAWSOutageChat:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  NSError *error = nil;
  NSArray<TLChatSummary *> *chats = [self.database listChats:&error];
  if (!chats) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not load chats."];
    return;
  }

  for (TLChatSummary *chat in chats) {
    if ([chat.title isEqualToString:TLAWSOutageChatTitle]) {
      self.chats = [chats mutableCopy];
      [self reloadHistoryPanel];
      [self loadChatWithID:chat.chatID];
      return;
    }
  }

  TLChatRecord *chat = [self.database createChatWithModel:self.settings.selectedModel error:&error];
  if (!chat || ![self.database saveChatTitle:TLAWSOutageChatTitle chatID:chat.chatID error:&error] ||
      ![self.database saveMessage:[TLChatMessage messageWithRole:TLRoleAssistant
                                                        content:TLAWSOutageAgentMessage
                                                       thinking:nil]
                           chatID:chat.chatID
                            error:&error]) {
    if (chat) {
      [self.database deleteChatWithID:chat.chatID error:nil];
    }
    [self presentErrorMessage:error.localizedDescription ?: @"Could not create the outage chat."];
    return;
  }

  chats = [self.database listChats:&error];
  if (chats) {
    self.chats = [chats mutableCopy];
    [self reloadHistoryPanel];
  }
  [self loadChatWithID:chat.chatID];
}

- (void)sendAWSOutageIntent:(id)sender {
  self.promptTextView.string = TLAWSOutageIntent;
  [self.messageInput recalculateHeight];
  [self updateMessageScrollInsets];
  [self updateControlStates];
  [self sendMessage:sender];
}

- (void)addDelayedCalendarConflictNotification {
  TLSidebarInboxStackView *calendarNotification =
    [self sidebarInboxStackViewWithTitle:@"Calendar Conflicts"
                                subtitle:@"Calendar Conflicts"
                           iconAssetName:@"google-calendar"
                       notificationCount:3];
  calendarNotification.showsSeparator = NO;
  [self.sidebarInboxPaneView insertInboxItemView:calendarNotification atIndex:2];
}

- (void)showScreensaver {
  [self hideScreensaver];

  TLASCIIPlanetScreensaverView *screensaverView =
    [[TLASCIIPlanetScreensaverView alloc] initWithFrame:self.rootView.bounds
                                        backgroundColor:self.palette.messagesSurface
                                               artColor:self.palette.textMuted];
  screensaverView.translatesAutoresizingMaskIntoConstraints = YES;
  screensaverView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  __weak typeof(self) weakSelf = self;
  screensaverView.dismissHandler = ^{
    [weakSelf hideScreensaver];
  };
  self.screensaverView = screensaverView;
  [self.rootView addSubview:screensaverView positioned:NSWindowAbove relativeTo:nil];
  [screensaverView startAnimating];
}

- (void)hideScreensaver {
  if (!self.screensaverView) {
    return;
  }

  [self.screensaverView stopAnimating];
  [self.screensaverView removeFromSuperview];
  self.screensaverView = nil;
  if (!self.isSending && self.promptTextView && [self isChatWorkspaceActive]) {
    [self.window makeFirstResponder:self.promptTextView];
  }
}

- (void)updateSlashCommandList { [self updateSlashCommandListForChat:[self currentChatPresentation]]; }
- (void)updateSlashCommandListForChat:(TLChatTabController *)chatContext {
  if (chatContext.renderingSlashCommands) return;
  [chatContext.slashCommandUpdateTimer invalidate];
  __weak typeof(self) weakSelf = self;
  __weak TLChatTabController *origin = chatContext;
  // Return the keystroke to AppKit before filtering, fetching, or rendering suggestions.
  chatContext.slashCommandUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 repeats:NO block:^(NSTimer *timer) {
    TLChatTabController *originChat = origin;
    if (originChat) [weakSelf flushSlashCommandUpdateForChat:originChat];
  }];
}

- (void)flushSlashCommandUpdate { [self flushSlashCommandUpdateForChat:[self currentChatPresentation]]; }
- (void)flushSlashCommandUpdateForChat:(TLChatTabController *)chatContext {
  if (!chatContext.slashCommandUpdateTimer) return;
  [chatContext.slashCommandUpdateTimer invalidate];
  chatContext.slashCommandUpdateTimer = nil;
  chatContext.renderingSlashCommands = YES;
  [self renderSlashCommandListForChat:chatContext];
  [self updateControlStatesForChat:chatContext];
  chatContext.renderingSlashCommands = NO;
}

- (void)renderSlashCommandList { [self renderSlashCommandListForChat:[self currentChatPresentation]]; }
- (void)renderSlashCommandListForChat:(TLChatTabController *)chatContext {
  if ([self preparingAttachmentsForChat:chatContext] || chatContext.editingQueuedPrompt || chatContext.messageInput.attachmentURLs.count || ![self isChatWorkspaceActiveForChat:chatContext] || !chatContext.messageInput.window || NSIsEmptyRect(chatContext.messageInput.bounds)) {
    [self hideSlashCommandListForChat:chatContext];
    return;
  }

  NSString *input = chatContext.promptTextView.string ?: @"";
  BOOL slashInput = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] hasPrefix:@"/"];
  if (slashInput) [self refreshHermesCommandsIfNeeded];
  NSArray<NSDictionary<NSString *, NSString *> *> *commands = [self slashCommandsMatchingPrompt:input];
  if (slashInput && self.loadingHermesCommands && self.hermesCommands.count == 0) {
    commands = @[@{@"kind": @"status", @"command": @"Loading Hermes commands…",
                  @"title": @"Starting Hermes for first discovery", @"description": @"", @"icon": @"terminal"}];
  } else if (slashInput && self.hermesCommandsError.length) {
    commands = [commands arrayByAddingObject:@{@"kind": @"status", @"command": self.hermesCommandsError,
                  @"title": self.hermesCommandsError}];
  }
  if (commands.count == 0) {
    [self hideSlashCommandListForChat:chatContext];
    return;
  }

  [self showSlashCommandListWithCommands:commands forChat:chatContext];
  NSString *trimmedPrompt = [chatContext.promptTextView.string
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmedPrompt.length > 1 && chatContext.selectedSlashCommandIndex < 0) {
    [self moveSlashCommandSelectionByOffset:1 forChat:chatContext];
  }
}

- (void)hideSlashCommandList { [self hideSlashCommandListForChat:[self currentChatPresentation]]; }
- (void)hideSlashCommandListForChat:(TLChatTabController *)chatContext {
  [chatContext.slashCommandUpdateTimer invalidate];
  chatContext.slashCommandUpdateTimer = nil;
  if (!chatContext.slashCommandListView.hidden || chatContext.slashCommandListHeightConstraint.constant > self.palette.space0) {
    chatContext.slashCommandListView.hidden = YES;
    chatContext.visibleSlashCommands = @[];
    chatContext.slashCommandScrollView.suggestions = @[];
    chatContext.selectedSlashCommandIndex = -1;
    chatContext.slashCommandListWidthConstraint.constant = self.palette.space0;
    chatContext.slashCommandListHeightConstraint.constant = self.palette.space0;
    [chatContext updateMessageScrollInsets];
  }
}

- (void)showOnboardingDemoWindow:(id)sender {
  [self createAgent:sender];
}

- (void)openAppFromOnboarding {
  [self.onboardingDemoWindowController.window close];
  [self revealMainWindowFromOnboarding];
}

- (void)revealMainWindowFromOnboarding {
  NSWindow *window = self.window;
  if (!window) {
    return;
  }

  NSRect finalFrame = self.hasMainWindowFrameBeforeOnboarding
      ? self.mainWindowFrameBeforeOnboarding
      : window.frame;
  self.hasMainWindowFrameBeforeOnboarding = NO;

  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp unhide:self];
  window.alphaValue = 0.0;
  [window deminiaturize:self];
  [window setFrame:finalFrame display:YES];
  [self layoutTrafficLightButtons];
  [self updateMessageInputWidthForWindowWidth:NSWidth(finalFrame)];
  [window orderOut:self];

  NSImage *snapshot = self.mainWindowSnapshotBeforeOnboarding;
  self.mainWindowSnapshotBeforeOnboarding = nil;
  if (!snapshot) {
    window.alphaValue = 1.0;
    [window makeKeyAndOrderFront:self];
    [window orderFrontRegardless];
    [self finishMainWindowRevealWithFinalFrame:finalFrame];
    return;
  }

  NSWindow *overlayWindow = [[NSWindow alloc] initWithContentRect:finalFrame
                                                        styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
  overlayWindow.opaque = NO;
  overlayWindow.backgroundColor = self.palette.transparentSurface;
  overlayWindow.hasShadow = NO;
  overlayWindow.releasedWhenClosed = NO;
  overlayWindow.level = NSNormalWindowLevel;

  NSImageView *snapshotView = [[NSImageView alloc] initWithFrame:overlayWindow.contentView.bounds];
  snapshotView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  snapshotView.image = snapshot;
  snapshotView.imageScaling = NSImageScaleAxesIndependently;
  snapshotView.wantsLayer = YES;
  [overlayWindow.contentView addSubview:snapshotView];
  [overlayWindow.contentView layoutSubtreeIfNeeded];
  snapshotView.frame = overlayWindow.contentView.bounds;

  NSRect finalSnapshotBounds = overlayWindow.contentView.bounds;
  snapshotView.layer.anchorPoint = CGPointMake(0.5, 0.5);
  snapshotView.layer.position = CGPointMake(NSMidX(finalSnapshotBounds), NSMidY(finalSnapshotBounds));
  snapshotView.layer.opacity = 1.0;
  snapshotView.layer.transform = CATransform3DMakeScale(TLMainWindowOnboardingRevealInitialScale,
                                                        TLMainWindowOnboardingRevealInitialScale,
                                                        1.0);
  self.mainWindowRevealOverlayWindow = overlayWindow;

  [overlayWindow orderFrontRegardless];
  [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];

  __weak typeof(self) weakSelf = self;
  CAMediaTimingFunction *timingFunction =
      [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  CABasicAnimation *scaleAnimation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
  scaleAnimation.fromValue = @(TLMainWindowOnboardingRevealInitialScale);
  scaleAnimation.toValue = @1.0;
  scaleAnimation.duration = TLMainWindowOnboardingRevealDuration;
  scaleAnimation.timingFunction = timingFunction;

  [CATransaction begin];
  [CATransaction setAnimationDuration:TLMainWindowOnboardingRevealDuration];
  [CATransaction setCompletionBlock:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TalariaWindowController *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      [strongSelf.mainWindowRevealOverlayWindow close];
      strongSelf.mainWindowRevealOverlayWindow = nil;
      [strongSelf finishMainWindowRevealWithFinalFrame:finalFrame];
    });
  }];
  [CATransaction setDisableActions:YES];
  snapshotView.layer.transform = CATransform3DIdentity;
  [snapshotView.layer addAnimation:scaleAnimation forKey:@"main-window-reveal-scale"];
  [CATransaction commit];
}

- (NSImage *)snapshotOfMainWindow {
  NSWindow *window = self.window;
  if (!window || window.windowNumber <= 0) {
    return nil;
  }

  CGImageRef image = CGWindowListCreateImage(CGRectNull,
                                              kCGWindowListOptionIncludingWindow,
                                              (CGWindowID)window.windowNumber,
                                              kCGWindowImageBoundsIgnoreFraming |
                                                  kCGWindowImageBestResolution);
  if (!image) {
    return nil;
  }
  NSImage *snapshot = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
  CGImageRelease(image);
  return snapshot;
}

- (void)finishMainWindowRevealWithFinalFrame:(NSRect)finalFrame {
  NSWindow *window = self.window;
  window.alphaValue = 1.0;
  [window setFrame:finalFrame display:YES];
  [window makeKeyAndOrderFront:self];
  [window orderFrontRegardless];
  [self layoutTrafficLightButtons];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
  [self updateMessageInputWidthForWindowWidth:NSWidth(finalFrame)];
  if (!self.isSending && self.promptTextView && [self isChatWorkspaceActive]) {
    [window makeFirstResponder:self.promptTextView];
  }
  [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps |
                                                           NSApplicationActivateAllWindows];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)showSettings:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  if (!self.settingsTab) {
    NSView *contentView = [self buildSettingsTabContent];
    self.settingsTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindSettings
                                             tabID:0
                                             title:@"Settings"
                                           toolTip:@"Settings"
                                               URL:nil
                                         closeable:YES];
    [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:contentView
                                                        openAction:@selector(openSettingsTab:)
                                                       closeAction:@selector(closeSettingsTab:)]
              forTab:self.settingsTab];
    [self addWorkspaceContentView:contentView];
    [self.appStateManager addWorkspaceTab:self.settingsTab activate:NO];
  }

  [self activateTabKind:TLWorkspaceTabKindSettings tabID:self.settingsTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openSettingsTab:(id)sender {
  if (self.widgetbookMode || !self.settingsTab) {
    return;
  }

  [self activateTabKind:TLWorkspaceTabKindSettings tabID:self.settingsTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)showAgents:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  if (!self.agentsTab) {
    NSView *contentView = [self buildAgentsTabContent];
    self.agentsTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindAgents
                                           tabID:0
                                           title:@"Agents"
                                         toolTip:@"Agents"
                                             URL:nil
                                       closeable:YES];
    [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:contentView
                                                        openAction:@selector(openAgentsTab:)
                                                       closeAction:@selector(closeAgentsTab:)]
              forTab:self.agentsTab];
    [self addWorkspaceContentView:contentView];
    [self.appStateManager addWorkspaceTab:self.agentsTab activate:NO];
  }

  [self refreshAgents];
  [self activateTabKind:TLWorkspaceTabKindAgents tabID:self.agentsTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openAgentsTab:(id)sender {
  if (self.widgetbookMode || !self.agentsTab) {
    return;
  }

  [self refreshAgents];
  [self activateTabKind:TLWorkspaceTabKindAgents tabID:self.agentsTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)closeAgentsTab:(id)sender {
  if (!self.agentsTab) {
    return;
  }
  if ([self closeWindowIfOnlyWorkspaceTab:self.agentsTab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:self.agentsTab];

  [self.appStateManager removeWorkspaceTabWithKind:self.agentsTab.kind tabID:self.agentsTab.tabID];
  [[self contentViewForTab:self.agentsTab] removeFromSuperview];
  [self removeRuntimeForKind:self.agentsTab.kind tabID:self.agentsTab.tabID];
  self.agentsTab = nil;


  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (NSView *)buildAutomationsContent {
  __weak typeof(self) weakSelf = self;
  NSArray *agents = [self.agentOrchestrator listAgents:nil] ?: @[];
  NSInteger agentID = self.database.currentAgentID;
  if (!agentID) agentID = [(TLAgentRecord *)agents.lastObject agentID];
  self.automationsController = [[TLAutomationsTabController alloc] initWithPalette:self.palette
    agents:agents agentID:agentID request:^(NSInteger selectedAgentID, NSDictionary *parameters, TLAutomationReply reply) {
      typeof(self) controller = weakSelf;
      if (!controller) return;
      [controller.agentOrchestrator hermesAutomationsWithParameters:parameters agentID:selectedAgentID
        token:controller.settings.openRouterToken model:controller.settings.selectedModel completion:reply];
    }];
  return self.automationsController.view;
}

- (void)showAutomations:(id)sender {
  if (self.widgetbookMode) return;
  if (!self.automationsTab) {
    NSView *content = [self buildAutomationsContent];
    self.automationsTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindAutomations tabID:0
      title:@"Automations" toolTip:@"Hermes scheduled jobs" URL:nil closeable:YES];
    [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:content
      openAction:@selector(showAutomations:) closeAction:@selector(closeAutomationsTab:)] forTab:self.automationsTab];
    [self addWorkspaceContentView:content];
    [self.appStateManager addWorkspaceTab:self.automationsTab activate:NO];
  }
  [self activateTabKind:TLWorkspaceTabKindAutomations tabID:self.automationsTab.tabID];
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
  [self.automationsController refresh:nil];
}

- (void)closeAutomationsTab:(id)sender {
  if (!self.automationsTab || [self closeWindowIfOnlyWorkspaceTab:self.automationsTab]) return;
  [self rememberClosedWorkspaceTab:self.automationsTab];
  [self.automationsController close];
  [self.appStateManager removeWorkspaceTabWithKind:self.automationsTab.kind tabID:self.automationsTab.tabID];
  [[self contentViewForTab:self.automationsTab] removeFromSuperview];
  [self removeRuntimeForKind:self.automationsTab.kind tabID:self.automationsTab.tabID];
  self.automationsTab = nil; self.automationsController = nil;
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
}

- (void)showDebug:(id)sender {
  if (self.widgetbookMode) {
    return;
  }

  if (!self.debugTerminalStateTimer) {
    __weak typeof(self) weakSelf = self;
    self.debugTerminalStateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
      TalariaWindowController *controller = weakSelf;
      if ([controller isWorkspaceTabActive:controller.debugTab]) [controller refreshDebugTerminalAvailability];
    }];
  }

  if (!self.debugTab) {
    NSView *contentView = [self buildDebugTabContent];
    self.debugTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindDebug
                                          tabID:0
                                          title:@"Debug"
                                        toolTip:@"Debug"
                                            URL:nil
                                      closeable:YES];
    [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:contentView
                                                        openAction:@selector(openDebugTab:)
                                                       closeAction:@selector(closeDebugTab:)]
              forTab:self.debugTab];
    [self addWorkspaceContentView:contentView];
    [self.appStateManager addWorkspaceTab:self.debugTab activate:NO];
  }

  [self refreshDebugTerminalAvailability];
  [self activateTabKind:TLWorkspaceTabKindDebug tabID:self.debugTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openDebugTab:(id)sender {
  if (self.widgetbookMode || !self.debugTab) {
    return;
  }
  [self refreshDebugTerminalAvailability];
  [self activateTabKind:TLWorkspaceTabKindDebug tabID:self.debugTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)closeDebugTab:(id)sender {
  if (!self.debugTab) {
    return;
  }
  if ([self closeWindowIfOnlyWorkspaceTab:self.debugTab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:self.debugTab];

  [self.appStateManager removeWorkspaceTabWithKind:self.debugTab.kind tabID:self.debugTab.tabID];
  [[self contentViewForTab:self.debugTab] removeFromSuperview];
  [self removeRuntimeForKind:self.debugTab.kind tabID:self.debugTab.tabID];
  self.debugTab = nil;
  [self.debugTerminalStateTimer invalidate];
  self.debugTerminalStateTimer = nil;
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)refreshDebugTerminalAvailability {
  BOOL running = [self.agentOrchestrator isDefaultAgentRunning];
  self.debugTerminalButton.enabled = running && !self.openingDebugTerminal;
  self.debugTerminalButton.toolTip = running ? nil : @"The agent VM must be running to open a terminal.";
}

- (void)openDebugTerminal:(id)sender {
  [self refreshDebugTerminalAvailability];
  if (self.openingDebugTerminal || ![self.agentOrchestrator isDefaultAgentRunning]) return;
  self.openingDebugTerminal = YES;
  [self rebuildDebugTabContentForCurrentPalette];
  [self.agentOrchestrator connectToDefaultAgentTerminal:^(VZVirtioSocketConnection *connection, NSError *error) {
    self.openingDebugTerminal = NO;
    [self rebuildDebugTabContentForCurrentPalette];
    if (!connection) { if (error) [NSApp presentError:error]; return; }
    NSError *sessionError = nil;
    TLVMTerminalSession *session = [[TLVMTerminalSession alloc] initWithConnection:connection
      executableURL:NSBundle.mainBundle.executableURL error:&sessionError];
    if (!session) { [NSApp presentError:sessionError]; return; }
    [session openInTerminalWithCompletion:^(NSError *launchError) {
      if (launchError) [NSApp presentError:launchError];
    }];
  }];
}

- (void)rebuildDebugTabContentForCurrentPalette {
  if (!self.debugTab) {
    return;
  }
  TLWorkspaceTabRuntime *runtime = [self runtimeForTab:self.debugTab];
  if (!runtime) {
    return;
  }
  NSView *previousContentView = runtime.contentView;
  NSView *nextContentView = [self buildDebugTabContent];
  runtime.contentView = nextContentView;
  [previousContentView removeFromSuperview];
  [self addWorkspaceContentView:nextContentView];
  [self updateWorkspaceMode];
}

- (NSView *)buildDebugTabContent {
  TLThemePalette *palette = self.palette;
  NSScrollView *scrollView = [[NSScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.drawsBackground = YES;
  scrollView.backgroundColor = palette.tabBackground;
  TLFlippedView *content = [[TLFlippedView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = content;

  NSTextField *titleLabel = [self labelWithString:@"Debug" font:palette.titleFont color:palette.appText];
  NSTextField *subtitleLabel = [self labelWithString:@"Inspect the agent VM or reset Talaria for a fresh start."
                                                font:palette.bodyFont
                                               color:palette.textMuted];
  subtitleLabel.usesSingleLineMode = NO;
  subtitleLabel.maximumNumberOfLines = 0;
  subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
  NSTextField *terminalLabel = [self labelWithString:@"VM terminal" font:palette.labelFont color:palette.labelText];
  NSTextField *terminalDescription = [self labelWithString:@"Open macOS Terminal connected to the VM. Use an interactive shell with tab completion, command history, keyboard shortcuts, and terminal apps."
                                                     font:palette.bodyFont
                                                    color:palette.textMuted];
  terminalDescription.usesSingleLineMode = NO;
  terminalDescription.maximumNumberOfLines = 0;
  terminalDescription.lineBreakMode = NSLineBreakByWordWrapping;

  TLThemedButton *openButton = [TLThemedButton buttonWithTitle:self.openingDebugTerminal ? @"Connecting…" : @"Open in Terminal" target:self action:@selector(openDebugTerminal:)];
  self.debugTerminalButton = openButton;
  [self refreshDebugTerminalAvailability];
  openButton.translatesAutoresizingMaskIntoConstraints = NO;
  openButton.bezelStyle = NSBezelStyleRounded;
  openButton.controlSize = NSControlSizeLarge;
  openButton.palette = palette;
  openButton.primary = YES;

  TLTokenView *card = [[TLTokenView alloc] init];
  card.translatesAutoresizingMaskIntoConstraints = NO;
  card.fillColor = palette.controlSurface;
  card.cornerRadius = palette.radiusMedium;
  for (NSView *view in @[terminalLabel, terminalDescription, openButton]) {
    [card addSubview:view];
  }
  NSTextField *resetLabel = [self labelWithString:@"Reset app" font:palette.labelFont color:palette.labelText];
  NSTextField *resetDescription = [self labelWithString:@"Permanently erase all chats, settings, saved API token, browser data, and Talaria VMs and their files. Restart at onboarding. This affects every copy of Talaria on this Mac."
                                                  font:palette.bodyFont color:palette.textMuted];
  resetDescription.usesSingleLineMode = NO;
  resetDescription.maximumNumberOfLines = 0;
  resetDescription.lineBreakMode = NSLineBreakByWordWrapping;
  TLThemedButton *resetButton = [TLThemedButton buttonWithTitle:@"Reset everything…" target:NSApp.delegate action:@selector(resetApp:)];
  resetButton.translatesAutoresizingMaskIntoConstraints = NO;
  resetButton.bezelStyle = NSBezelStyleRounded;
  resetButton.controlSize = NSControlSizeLarge;
  resetButton.palette = palette;
  resetButton.primary = NO;
  TLTokenView *resetCard = [[TLTokenView alloc] init];
  resetCard.translatesAutoresizingMaskIntoConstraints = NO;
  resetCard.fillColor = palette.controlSurface;
  resetCard.cornerRadius = palette.radiusMedium;
  for (NSView *view in @[resetLabel, resetDescription, resetButton]) [resetCard addSubview:view];
  for (NSView *view in @[titleLabel, subtitleLabel, card, resetCard]) {
    [content addSubview:view];
  }

  for (NSView *view in @[subtitleLabel, terminalDescription, resetDescription, openButton, resetButton]) {
    [self allowHorizontalWindowExpansionForView:view];
  }
  [NSLayoutConstraint activateConstraints:@[
    [content.leadingAnchor constraintEqualToAnchor:scrollView.contentView.leadingAnchor],
    [content.topAnchor constraintEqualToAnchor:scrollView.contentView.topAnchor],
    [content.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
    [content.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.contentView.heightAnchor],
    [content.bottomAnchor constraintGreaterThanOrEqualToAnchor:resetCard.bottomAnchor constant:palette.space11],
    [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:palette.space12],
    [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:palette.space11],
    [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [subtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:palette.space2],
    [card.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [card.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [card.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:palette.space10],
    [terminalLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:palette.space8],
    [terminalLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:palette.space8],
    [terminalDescription.leadingAnchor constraintEqualToAnchor:terminalLabel.leadingAnchor],
    [terminalDescription.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-palette.space8],
    [terminalDescription.topAnchor constraintEqualToAnchor:terminalLabel.bottomAnchor constant:palette.space3],
    [openButton.leadingAnchor constraintEqualToAnchor:terminalLabel.leadingAnchor],
    [openButton.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-palette.space8],
    [openButton.topAnchor constraintEqualToAnchor:terminalDescription.bottomAnchor constant:palette.space6],
    [openButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-palette.space8],
    [openButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
    [resetCard.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
    [resetCard.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    [resetCard.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:palette.space8],
    [resetLabel.leadingAnchor constraintEqualToAnchor:resetCard.leadingAnchor constant:palette.space8],
    [resetLabel.topAnchor constraintEqualToAnchor:resetCard.topAnchor constant:palette.space8],
    [resetDescription.leadingAnchor constraintEqualToAnchor:resetLabel.leadingAnchor],
    [resetDescription.trailingAnchor constraintEqualToAnchor:resetCard.trailingAnchor constant:-palette.space8],
    [resetDescription.topAnchor constraintEqualToAnchor:resetLabel.bottomAnchor constant:palette.space3],
    [resetButton.leadingAnchor constraintEqualToAnchor:resetLabel.leadingAnchor],
    [resetButton.trailingAnchor constraintLessThanOrEqualToAnchor:resetDescription.trailingAnchor],
    [resetButton.topAnchor constraintEqualToAnchor:resetDescription.bottomAnchor constant:palette.space6],
    [resetButton.bottomAnchor constraintEqualToAnchor:resetCard.bottomAnchor constant:-palette.space8],
    [resetButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
  ]];
  return scrollView;
}

- (NSView *)buildAgentsTabContent {
  TLThemePalette *palette = self.palette;
  TLTokenView *content = [[TLTokenView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  content.fillColor = palette.tabBackground;
  self.agentsView = content;

  NSTextField *titleLabel = [self labelWithString:@"Agents" font:palette.titleFont color:palette.appText];
  self.agentsStatusLabel = [self labelWithString:@"" font:palette.smallFont color:palette.textMuted];
  self.createAgentButton = [self buttonWithTitle:@"New" action:@selector(createAgent:)];
  self.startAgentButton = [self buttonWithTitle:@"Start" action:@selector(startSelectedAgent:)];
  self.stopAgentButton = [self buttonWithTitle:@"Stop" action:@selector(stopSelectedAgent:)];
  self.agentSettingsButton = [self buttonWithTitle:@"Settings…" action:@selector(editSelectedAgentSettings:)];
  self.folderAccessButton = [self buttonWithTitle:@"Folder Access…" action:@selector(manageSelectedAgentFolders:)];
  self.deleteAgentButton = [self buttonWithTitle:@"Delete" action:@selector(deleteSelectedAgent:)];
  self.closeAgentsButton = [self buttonWithTitle:@"Close" action:@selector(closeAgentsTab:)];

  NSStackView *agentActionStack = [[NSStackView alloc] init];
  agentActionStack.translatesAutoresizingMaskIntoConstraints = NO;
  agentActionStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  agentActionStack.alignment = NSLayoutAttributeCenterY;
  agentActionStack.distribution = NSStackViewDistributionFillEqually;
  agentActionStack.spacing = palette.space4;
  for (NSButton *button in @[
    self.createAgentButton,
    self.agentSettingsButton,
    self.folderAccessButton,
    self.startAgentButton,
    self.stopAgentButton,
    self.deleteAgentButton,
    self.closeAgentsButton,
  ]) {
    [agentActionStack addArrangedSubview:button];
    [button.heightAnchor constraintEqualToConstant:palette.settingsActionHeight].active = YES;
  }

  self.agentsTableView = [[NSTableView alloc] init];
  self.agentsTableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.agentsTableView.delegate = self;
  self.agentsTableView.dataSource = self;
  self.agentsTableView.usesAlternatingRowBackgroundColors = NO;
  self.agentsTableView.gridStyleMask = NSTableViewGridNone;
  self.agentsTableView.rowHeight = palette.historyRowHeight;
  self.agentsTableView.backgroundColor = palette.tabBackground;
  self.agentsTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

  NSArray<NSArray<NSString *> *> *columns = @[
    @[@"name", @"Name"],
    @[@"vm", @"VM directory"],
    @[@"status", @"Status"],
  ];
  for (NSArray<NSString *> *columnSpec in columns) {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columnSpec[0]];
    column.title = columnSpec[1];
    column.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    column.width = [column.identifier isEqualToString:@"vm"] ? palette.controlMinWidth * 4.0 : palette.controlMinWidth * 1.4;
    if ([column.identifier isEqualToString:@"name"]) {
      column.minWidth = palette.controlMinWidth * 1.8;
      column.width = palette.controlMinWidth * 2.5;
    } else if ([column.identifier isEqualToString:@"status"]) {
      column.minWidth = ceil([@"VM running · Hermes installed" sizeWithAttributes:@{NSFontAttributeName: palette.bodyFont}].width) + palette.space8 + palette.space4 * 3;
      column.width = column.minWidth;
      column.resizingMask = NSTableColumnUserResizingMask;
    }
    [self.agentsTableView addTableColumn:column];
  }

  NSScrollView *tableScrollView = [[NSScrollView alloc] init];
  tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  tableScrollView.documentView = self.agentsTableView;
  tableScrollView.hasVerticalScroller = YES;
  tableScrollView.drawsBackground = NO;

  for (NSView *view in @[
    titleLabel,
    self.agentsStatusLabel,
    agentActionStack,
    tableScrollView,
  ]) {
    [content addSubview:view];
  }

  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:palette.space12],
    [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:palette.space11],

    [self.agentsStatusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [self.agentsStatusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [self.agentsStatusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:palette.space2],

    [agentActionStack.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [agentActionStack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [agentActionStack.topAnchor constraintEqualToAnchor:self.agentsStatusLabel.bottomAnchor constant:palette.space6],

    [tableScrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:palette.space12],
    [tableScrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [tableScrollView.topAnchor constraintEqualToAnchor:agentActionStack.bottomAnchor constant:palette.space8],
    [tableScrollView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-palette.space12],
  ]];

  [self styleButton:self.createAgentButton background:palette.primaryActionSurface foreground:palette.primaryActionText];
  [self styleButton:self.startAgentButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self styleButton:self.stopAgentButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self styleButton:self.agentSettingsButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self styleButton:self.folderAccessButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self styleButton:self.deleteAgentButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self styleButton:self.closeAgentsButton background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  [self refreshAgents];
  return content;
}

- (void)refreshAgents {
  if (!self.agentOrchestrator) {
    return;
  }

  NSInteger selectedAgentID = [self selectedAgent].agentID;
  NSError *error = nil;
  NSArray<TLAgentRecord *> *loadedAgents = [self.agentOrchestrator listAgents:&error];
  if (!loadedAgents) {
    if (self.agentsStatusLabel) {
      self.agentsStatusLabel.stringValue = error.localizedDescription ?: @"Could not load agents.";
    }
    return;
  }

  self.agents = [loadedAgents mutableCopy];
  [self refreshNotifications];
  if (self.historyAgentID != self.database.currentAgentID) {
    self.historyRequestGeneration += 1;
    self.historyPanelController.loading = NO;
    self.hermesHistoryChats = @[];
    self.hermesHistorySessions = @{};
    [self reloadHistoryPanel];
    if ([self isHistoryScreenActive]) [self refreshHermesHistory];
  }

  if (self.hermesCommandsAgentID != self.database.currentAgentID) {
    [self prepareHermesCommands];
    [self updateSlashCommandList];
  }
  [self rebuildSidebarAgents];
  [self.agentsTableView reloadData];
  if (selectedAgentID > 0) {
    for (NSUInteger index = 0; index < self.agents.count; index += 1) {
      if (self.agents[index].agentID == selectedAgentID) {
        [self.agentsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        break;
      }
    }
  }

  [self updateAgentsStatusLabel];
  [self updateAgentControlStates];
}

- (void)updateAgentsStatusLabel {
  if (!self.agentsStatusLabel) {
    return;
  }

  NSString *runtimePath = self.agentOrchestrator.runtimeBundleURL.path ?: @"";
  if (!self.agentOrchestrator.virtualizationSupported) {
    self.agentsStatusLabel.stringValue = [NSString stringWithFormat:@"%lu agents. Virtualization unavailable on this Mac.",
                                                                            (unsigned long)self.agents.count];
    return;
  }

  self.agentsStatusLabel.stringValue = [NSString stringWithFormat:@"%lu agents. Linux/Python runtime: %@",
                                                                          (unsigned long)self.agents.count,
                                                                          runtimePath];
}

- (void)createAgent:(id)sender {
  if (self.widgetbookMode || self.hasSendingTurns || self.window.attachedSheet) return;
  [self.sidebarAgentPaneSurface removeFromSuperview];
  self.sidebarAgentPaneSurface = nil;
  self.sidebarAgentPane = nil;
  self.agentCreationWindowController = [[TLAgentCreationWindowController alloc]
    initWithPalette:self.palette orchestrator:self.agentOrchestrator];
  __weak typeof(self) weakSelf = self;
  self.agentCreationWindowController.agentCreatedHandler = ^(TLAgentRecord *agent) {
    TalariaWindowController *strongSelf = weakSelf;
    [strongSelf showAgents:nil];
    [strongSelf selectAgentWithID:agent.agentID];
    [strongSelf configureProviderForAgent:agent];
  };
  [self.agentCreationWindowController showFromWindow:self.window];
}

- (void)configureProviderForAgent:(TLAgentRecord *)agent {
  self.providerSetupWindowController = [[TLProviderSetupWindowController alloc] initWithAgent:agent orchestrator:self.agentOrchestrator palette:self.palette];
  __weak typeof(self) weakSelf = self;
  self.providerSetupWindowController.completionHandler = ^(NSString *selection) {
    typeof(self) owner = weakSelf;
    if (!owner) return;
    owner.settings = [owner.database appSettings:nil] ?: owner.settings;
    TLAppSettings *completed = [owner.settings copy]; completed.onboardingCompleted = YES;
    owner.settings = [owner.database saveAppSettings:completed error:nil] ?: owner.settings;
    [owner refreshAgents]; [owner prepareHermesCommands]; [owner updateControlStates];
  };
  [self.providerSetupWindowController presentForWindow:self.window];
}

- (void)editSelectedAgentSettings:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent || self.window.attachedSheet) return;
  self.agentSettingsWindowController = [[TLAgentCreationWindowController alloc]
    initWithAgent:agent palette:self.palette orchestrator:self.agentOrchestrator];
  __weak typeof(self) weakSelf = self;
  self.agentSettingsWindowController.providerSetupHandler = ^{ [weakSelf configureProviderForAgent:agent]; };
  self.agentSettingsWindowController.agentUpdatedHandler = ^(TLAgentRecord *updatedAgent) {
    [weakSelf refreshAgents];
    if (updatedAgent.agentID == weakSelf.database.currentAgentID) [weakSelf prepareHermesCommands];
  };
  [self.agentSettingsWindowController showFromWindow:self.window];
}

- (void)manageSelectedAgentFolders:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent || self.window.attachedSheet) return;
  self.agentFolderAccessWindowController = [[TLAgentFolderAccessWindowController alloc]
    initWithAgent:agent palette:self.palette orchestrator:self.agentOrchestrator];
  __weak typeof(self) weakSelf = self;
  self.agentFolderAccessWindowController.savedHandler = ^{ [weakSelf refreshAgents]; };
  [self.agentFolderAccessWindowController showFromWindow:self.window];
}

- (void)initializeAgentWithID:(NSInteger)agentID {
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator installHermesForAgentWithID:agentID progress:^(NSString *text) {
    NSString *line = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (line.length) weakSelf.agentsStatusLabel.stringValue = [@"Installing Hermes: " stringByAppendingString:line];
  } completion:^(TLAgentRecord *agent, NSError *error) {
    [weakSelf refreshAgents];
    if (error) [weakSelf presentErrorMessage:error.localizedDescription];
    else {
      [weakSelf prepareHermesCommands];
      [weakSelf updateSlashCommandList];
    }
  }];
  [self refreshAgents];
}

- (void)startSelectedAgent:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent) {
    return;
  }

  if ([agent.status isEqualToString:TLAgentStatusError] || ![self.agentOrchestrator hasHermesInstallationForAgent:agent]) {
    [self initializeAgentWithID:agent.agentID];
    return;
  }

  self.agentsStatusLabel.stringValue = [NSString stringWithFormat:@"Starting %@", agent.name];
  [self updateAgentControlStates];
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator startAgentWithID:agent.agentID completion:^(TLAgentRecord *updatedAgent, NSError *error) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if (error) {
      [strongSelf presentErrorMessage:error.localizedDescription ?: @"Could not start agent."];
    }
    [strongSelf refreshAgents];
    if (updatedAgent) {
      [strongSelf selectAgentWithID:updatedAgent.agentID];
    }
    if (!error && updatedAgent.agentID == strongSelf.database.currentAgentID) {
      [strongSelf prepareHermesCommands];
    }
  }];
}

- (void)stopSelectedAgent:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent) {
    return;
  }

  self.agentsStatusLabel.stringValue = [NSString stringWithFormat:@"Stopping %@", agent.name];
  [self updateAgentControlStates];
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator stopAgentWithID:agent.agentID completion:^(TLAgentRecord *updatedAgent, NSError *error) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    if (error) {
      [strongSelf presentErrorMessage:error.localizedDescription ?: @"Could not stop agent."];
    }
    [strongSelf refreshAgents];
    if (updatedAgent) {
      [strongSelf selectAgentWithID:updatedAgent.agentID];
    }
  }];
}

- (void)deleteSelectedAgent:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent) {
    return;
  }

  NSError *error = nil;
  if (![self.agentOrchestrator deleteAgentWithID:agent.agentID error:&error]) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not delete agent."];
    [self refreshAgents];
    return;
  }

  [self refreshAgents];
  NSInteger nextRow = MIN(self.agentsTableView.selectedRow, (NSInteger)self.agents.count - 1);
  if (nextRow >= 0) {
    [self.agentsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)nextRow] byExtendingSelection:NO];
  }
}

- (TLAgentRecord *)selectedAgent {
  NSInteger row = self.agentsTableView.selectedRow;
  if (row < 0 || row >= (NSInteger)self.agents.count) {
    return nil;
  }

  return self.agents[(NSUInteger)row];
}

- (void)selectAgentWithID:(NSInteger)agentID {
  if (!self.agentsTableView || agentID <= 0) {
    return;
  }

  for (NSUInteger index = 0; index < self.agents.count; index += 1) {
    if (self.agents[index].agentID == agentID) {
      [self.agentsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
      return;
    }
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  if (tableView != self.agentsTableView) {
    return 0;
  }

  return (NSInteger)self.agents.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  if (tableView != self.agentsTableView || row < 0 || row >= (NSInteger)self.agents.count) {
    return nil;
  }

  NSString *identifier = tableColumn.identifier;
  TLAgentRecord *agent = self.agents[(NSUInteger)row];
  if ([identifier isEqualToString:@"name"]) {
    TLAgentNameCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) cell = [[TLAgentNameCellView alloc] initWithPalette:self.palette];
    cell.identifier = identifier;
    [cell configureWithName:agent.name avatar:agent.avatar current:agent.agentID == self.database.currentAgentID palette:self.palette];
    return cell;
  }
  if ([identifier isEqualToString:@"status"]) {
    TLAgentStatusCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) cell = [[TLAgentStatusCellView alloc] initWithPalette:self.palette];
    cell.identifier = identifier;
    [cell configureWithStatus:[self.agentOrchestrator displayStatusForAgent:agent] running:([self.agentOrchestrator isVMRunningForAgent:agent] && [self.agentOrchestrator hasHermesInstallationForAgent:agent] && ![agent.status isEqualToString:TLAgentStatusError]) initializing:[agent.status isEqualToString:TLAgentStatusInitializing] setupRequired:![self.agentOrchestrator hasHermesInstallationForAgent:agent] palette:self.palette];
    cell.textField.toolTip = agent.lastError.length > 0 ? agent.lastError : cell.textField.stringValue;
    return cell;
  }
  NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] init];
    cell.identifier = identifier;
    NSTextField *textField = [self labelWithString:@"" font:self.palette.bodyFont color:self.palette.appText];
    textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.textField = textField;
    [cell addSubview:textField];
    [NSLayoutConstraint activateConstraints:@[
      [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space4],
      [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space4],
      [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
  }

  cell.textField.stringValue = agent.vmDirectory;
  cell.textField.font = self.palette.bodyFont;
  cell.textField.textColor = self.palette.appText;
  cell.textField.toolTip = agent.vmDirectory;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (notification.object == self.agentsTableView) {
    [self updateAgentControlStates];
  }
}

- (void)updateAgentControlStates {
  BOOL controlsAllowed = !self.hasSendingTurns && !self.widgetbookMode && self.agentsTab != nil;
  TLAgentRecord *agent = [self selectedAgent];
  BOOL hasAgent = agent != nil;
  BOOL starting = [agent.status isEqualToString:TLAgentStatusStarting];
  BOOL running = [self.agentOrchestrator isVMRunningForAgent:agent];
  BOOL needsSetup = hasAgent && ![self.agentOrchestrator hasHermesInstallationForAgent:agent];
  BOOL failed = [agent.status isEqualToString:TLAgentStatusError];
  BOOL stopping = [agent.status isEqualToString:TLAgentStatusStopping];
  BOOL busy = starting || stopping || [agent.status isEqualToString:TLAgentStatusInitializing];
  self.startAgentButton.title = failed ? @"Retry setup" : (needsSetup ? @"Install Hermes" : @"Start VM");

  self.createAgentButton.enabled = controlsAllowed;
  self.startAgentButton.enabled = controlsAllowed && hasAgent && (!running || needsSetup || failed) && !busy;
  self.stopAgentButton.enabled = controlsAllowed && hasAgent && running && !busy;
  self.deleteAgentButton.enabled = controlsAllowed && hasAgent && !running && !busy;
  self.agentSettingsButton.enabled = controlsAllowed && hasAgent && !busy;
  self.folderAccessButton.enabled = controlsAllowed && hasAgent;
  self.closeAgentsButton.enabled = controlsAllowed;

  [self updateButtonAlpha:self.createAgentButton];
  [self updateButtonAlpha:self.startAgentButton];
  [self updateButtonAlpha:self.stopAgentButton];
  [self updateButtonAlpha:self.agentSettingsButton];
  [self updateButtonAlpha:self.folderAccessButton];
  [self updateButtonAlpha:self.deleteAgentButton];
  [self updateButtonAlpha:self.closeAgentsButton];
}

- (void)updateButtonAlpha:(NSButton *)button {
  if (!button) {
    return;
  }

  button.alphaValue = button.enabled ? 1.0 : self.palette.disabledOpacity;
}

- (NSView *)buildSettingsTabContent {
  TLSettingsTabController *controller = [[TLSettingsTabController alloc] initWithSettings:self.settings
    database:self.database orchestrator:self.agentOrchestrator palette:self.palette];
  self.settingsTabController = controller;
  __weak typeof(self) weakSelf = self;
  controller.onboardingHandler = ^{ [weakSelf showOnboardingDemoWindow:weakSelf]; };
  controller.errorHandler = ^(NSString *message) { [weakSelf presentErrorMessage:message]; };
  controller.skillsSavedHandler = ^(NSInteger agentID) {
    if (agentID == weakSelf.database.currentAgentID) [weakSelf prepareHermesCommands];
  };
  controller.settingsSavedHandler = ^(TLAppSettings *settings) {
    TalariaWindowController *windowController = weakSelf;
    BOOL inferenceChanged = ![windowController.settings.openRouterToken isEqualToString:settings.openRouterToken] ||
      ![windowController.settings.selectedModel isEqualToString:settings.selectedModel];
    windowController.settings = settings;
    [windowController applyTheme];
    if (inferenceChanged) [windowController prepareHermesCommands];
  };
  return controller.view;
}

- (void)closeSettingsTab:(id)sender {
  if (!self.settingsTab) {
    return;
  }
  if ([self closeWindowIfOnlyWorkspaceTab:self.settingsTab]) {
    return;
  }
  [self rememberClosedWorkspaceTab:self.settingsTab];

  [self.appStateManager removeWorkspaceTabWithKind:self.settingsTab.kind tabID:self.settingsTab.tabID];
  [[self contentViewForTab:self.settingsTab] removeFromSuperview];
  [self removeRuntimeForKind:self.settingsTab.kind tabID:self.settingsTab.tabID];
  self.settingsTab = nil;
  self.settingsTabController = nil;


  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  [self focusChatContainingView:textView];
  if (commandSelector == @selector(cancelOperation:)) {
    if (self.chatPresentation.editingQueuedPrompt) { [self finishQueuedPromptEditingSaving:NO]; return YES; }
    if (self.slashCommandUpdateTimer || !self.slashCommandListView.hidden) { [self hideSlashCommandList]; return YES; }
  }
  if (commandSelector == @selector(insertTab:) || commandSelector == @selector(moveUp:) ||
      commandSelector == @selector(moveDown:) || commandSelector == @selector(insertNewline:)) {
    [self flushSlashCommandUpdate];
  }
  if (commandSelector == @selector(insertTab:) && !self.slashCommandListView.hidden) {
    if (self.selectedSlashCommandIndex < 0) [self moveSlashCommandSelectionByOffset:1];
    NSInteger index = self.selectedSlashCommandIndex;
    if (index >= 0 && [self.visibleSlashCommands[(NSUInteger)index][@"kind"] isEqualToString:@"hermes"]) {
      self.promptTextView.string = [self.visibleSlashCommands[(NSUInteger)index][@"command"] stringByAppendingString:@" "];
      [self.messageInput recalculateHeight];
      [self.promptTextView setSelectedRange:NSMakeRange(self.promptTextView.string.length, 0)];
      [self hideSlashCommandList];
      [self updateControlStates];
      return YES;
    }
  }
  if (commandSelector == @selector(moveUp:)) {
    return [self moveSlashCommandSelectionByOffset:-1];
  }
  if (commandSelector == @selector(moveDown:)) {
    return [self moveSlashCommandSelectionByOffset:1];
  }
  if (commandSelector == @selector(insertNewline:)) {
    BOOL shiftPressed = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
    if (!shiftPressed) {
      if (!self.messageInput.attachmentURLs.count && [self performSelectedSlashCommand]) return YES;
      [self sendMessage:textView];
      return YES;
    }
  }

  return NO;
}

- (void)textDidChange:(NSNotification *)notification {
  [self focusChatContainingView:notification.object];
  // TextKit has already applied the edit. Do not force the workspace to lay out
  // before AppKit can paint it; suggestions and composer chrome follow next frame.
  [self updateSlashCommandList];
}

- (void)renderMessages { [self renderMessagesScrollingToBottom:YES]; }
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom {
  TLChatTabController *chat = [self currentChatPresentation];
  for (TLAgentRecord *agent in self.agents) if (agent.agentID == self.database.currentAgentID) { chat.agentAvatar = agent.avatar; break; }
  [chat renderMessagesScrollingToBottom:scrollToBottom];
}
- (void)scheduleStreamingMessageRender { [[self currentChatPresentation] scheduleStreamingMessageRender]; }
- (void)updateMessageScrollInsets { [[self currentChatPresentation] updateMessageScrollInsets]; }
- (void)resetMessageRowCache { [[self currentChatPresentation] resetMessageRowCache]; }
- (void)detachMessageRowFromStack:(NSView *)row { [[self currentChatPresentation] detachMessageRowFromStack:row]; }

- (TLAttachmentPreviewItem *)previewItemForAttachment:(NSDictionary *)attachment sessionID:(NSString *)sessionID {
  TLAttachmentPreviewItem *item = [[TLAttachmentPreviewItem alloc] init];
  NSString *name = attachment[@"name"];
  item.name = [name isKindOfClass:NSString.class] && name.length ? name : @"Attachment";
  item.directory = [attachment[@"directory"] boolValue];
  TLAgentOrchestrator *orchestrator = self.agentOrchestrator;
  item.URLResolver = ^NSURL *{ return [orchestrator fileURLForAttachment:attachment sessionID:sessionID]; };
  return item;
}

- (void)previewAttachmentsForPresentation:(TLChatTabController *)presentation message:(TLChatMessage *)selectedMessage index:(NSUInteger)index {
  NSMutableArray *items = [NSMutableArray array];
  NSUInteger selectedIndex = NSNotFound;
  for (TLChatMessage *message in presentation.messages) {
    if (message == selectedMessage && index < message.attachments.count) selectedIndex = items.count + index;
    for (NSDictionary *attachment in message.attachments) {
      [items addObject:[self previewItemForAttachment:attachment sessionID:presentation.chat.hermesSessionID]];
    }
  }
  if (selectedIndex == NSNotFound || !items.count) return;
  [self.attachmentViewer close];
  self.attachmentViewer = [[TLAttachmentViewerWindowController alloc] initWithItems:items
    conversationTitle:presentation.chat.title selectedIndex:selectedIndex palette:self.palette];
  [self.attachmentViewer showOnScreen:self.window.screen ?: NSScreen.mainScreen];
}

- (NSView *)plainTextViewWithString:(NSString *)string textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont {
  TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:self.palette];
  __weak typeof(self) weakSelf = self;
  renderer.linkHandler = ^(NSURL *URL, NSEventModifierFlags modifierFlags) {
    [weakSelf handleLinkURL:URL modifierFlags:modifierFlags];
  };
  return [renderer viewForPlainText:string ?: @"" textColor:textColor baseFont:baseFont];
}

- (NSView *)chipWithText:(NSString *)text {
  TLTokenView *chip = [[TLTokenView alloc] init];
  chip.translatesAutoresizingMaskIntoConstraints = NO;
  chip.fillColor = self.palette.chipSurface;
  chip.borderColor = self.palette.chipBorder;
  chip.borderEdges = TLBorderEdgeAll;
  chip.borderWidth = self.palette.borderWidth;
  chip.cornerRadius = self.palette.chipRadius;

  NSTextField *label = [self labelWithString:text font:self.palette.smallFont color:self.palette.chipText];
  [chip addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:self.palette.space6],
    [label.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-self.palette.space6],
    [label.topAnchor constraintEqualToAnchor:chip.topAnchor constant:self.palette.chipVerticalPadding],
    [label.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor constant:-self.palette.chipVerticalPadding],
  ]];
  return chip;
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:string];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font;
  label.textColor = color;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (NSTextField *)wrappingLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [self labelWithString:string font:font color:color];
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.maximumNumberOfLines = 0;
  label.usesSingleLineMode = NO;
  return label;
}

- (TLButton *)makeCreateChatButton {
  TLButton *button = [[TLButton alloc] init];
  button.palette = self.palette;
  button.style = TLButtonStyleCompactMinimal;
  button.size = TLButtonSizeMedium;
  button.target = self;
  button.action = @selector(startNewChatFromButton:);
  button.image = [self symbolImageNamed:@"plus" accessibilityDescription:@"New chat"];
  button.toolTip = @"New chat";
  __weak typeof(self) weakSelf = self;
  button.hoverChanged = ^(BOOL hovered) {
    [weakSelf.workspaceTabsController setNewTabButtonHovered:hovered];
  };
  button.contextMenuProvider = ^NSMenu *{ return [weakSelf newTabContextMenu]; };
  return button;
}

- (TLButton *)makeSidebarToggleButton {
  TLButton *button = [[TLButton alloc] init];
  button.palette = self.palette;
  button.style = TLButtonStyleMinimal;
  button.size = TLButtonSizeMedium;
  button.target = self;
  button.action = @selector(toggleSidebar:);
  button.image = [self symbolImageNamed:@"rectangle.leftthird.inset.filled" accessibilityDescription:@"Toggle sidebar"];
  button.toolTip = @"Toggle sidebar";
  return button;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
  NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bordered = NO;
  button.wantsLayer = YES;
  button.font = self.palette.labelFont;
  button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
  return button;
}

- (nullable NSImage *)symbolImageNamed:(NSString *)name accessibilityDescription:(NSString *)description {
  if (@available(macOS 11.0, *)) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
  }
  return nil;
}

- (CGFloat)tabStackLeadingConstant {
  return [self tabStackLeadingConstantForSidebarWidth:[self currentSidebarWidth]];
}

- (CGFloat)tabStackLeadingConstantForSidebarWidth:(CGFloat)sidebarWidth {
  if (self.sidebarVisible) {
    return sidebarWidth + self.palette.space3;
  }

  return self.palette.trafficLightLeftInset + self.palette.trafficLightReservedWidth - self.palette.space5 + (self.incognito ? self.incognitoPill.intrinsicContentSize.width + self.palette.space3 : self.sidebarToggleButton.intrinsicContentSize.width) + self.palette.space0;
}

- (CGFloat)availableTabStripWidthForLeadingConstant:(CGFloat)leadingConstant {
  CGFloat topbarWidth = NSWidth(self.topbar.bounds) > self.palette.space0
    ? NSWidth(self.topbar.bounds)
    : NSWidth(self.window.contentView.bounds);
  return [self availableTabStripWidthForLeadingConstant:leadingConstant topbarWidth:topbarWidth];
}

- (CGFloat)availableTabStripWidthForLeadingConstant:(CGFloat)leadingConstant topbarWidth:(CGFloat)topbarWidth {
  if (topbarWidth <= self.palette.space0) {
    return self.palette.space0;
  }

  CGFloat createButtonWidth = NSWidth(self.createChatButton.bounds) > self.palette.space0
    ? NSWidth(self.createChatButton.bounds)
    : self.createChatButton.intrinsicContentSize.width;
  CGFloat maximumTabTrailing = topbarWidth -
    self.palette.space4 -
    createButtonWidth +
    [self createChatButtonTabOverlap];
  return MAX(self.palette.space0, maximumTabTrailing - leadingConstant);
}

- (CGFloat)createChatButtonTabOverlap {
  return self.palette.space4 - self.palette.space2;
}

- (CGFloat)createChatButtonVerticalOffset {
  return self.palette.space2 * 0.5;
}

- (void)updateWorkspaceTabWidths {
  if (!self.workspaceTabsController || !self.tabStackLeadingConstraint) {
    return;
  }

  [self.workspaceTabsController updateTabWidthsForAvailableWidth:[self availableTabStripWidthForLeadingConstant:self.tabStackLeadingConstraint.constant]
    contentWidth:NSWidth(self.contentHost.bounds)];
}

- (CGFloat)contentLeadingPadding {
  return self.sidebarVisible ? self.palette.space3 : self.palette.space4;
}

- (CGFloat)contentLeadingOffsetForSidebarWidth:(CGFloat)sidebarWidth {
  return sidebarWidth + [self contentLeadingPadding];
}

- (CGFloat)sidebarActionStackHeight {
  return self.sidebarAutomationsButton.intrinsicContentSize.height +
    self.sidebarActionStack.spacing + self.sidebarUserButton.intrinsicContentSize.height;
}

- (CGFloat)currentSidebarContentWidth {
  return [self sidebarContentWidthForWindowWidth:NSWidth(self.window.contentView.bounds)];
}

- (CGFloat)sidebarContentWidthForWindowWidth:(CGFloat)windowWidth {
  CGFloat resolvedWindowWidth = windowWidth > self.palette.space0 ? windowWidth : self.palette.windowInitialWidth;
  return [self clampedSidebarWidthForPreferredWidth:self.sidebarPreferredWidth
                                       windowWidth:resolvedWindowWidth];
}

- (CGFloat)currentSidebarWidth {
  if (!self.sidebarVisible) {
    return self.palette.space0;
  }

  return [self currentSidebarContentWidth];
}

- (CGFloat)clampedSidebarWidthForPreferredWidth:(CGFloat)preferredWidth {
  return [self clampedSidebarWidthForPreferredWidth:preferredWidth
                                       windowWidth:NSWidth(self.window.contentView.bounds)];
}

- (CGFloat)clampedSidebarWidthForPreferredWidth:(CGFloat)preferredWidth windowWidth:(CGFloat)windowWidth {
  CGFloat desiredWidth = preferredWidth > self.palette.space0 ? preferredWidth : self.palette.sidebarWidth;
  CGFloat availableWidth = MAX(self.palette.space0, windowWidth - self.palette.messageInputMinWidth);
  CGFloat maximumWidth = MIN(self.palette.sidebarMaximumWidth, availableWidth);
  if (maximumWidth <= self.palette.space0) {
    return self.palette.space0;
  }

  CGFloat minimumWidth = MIN(self.palette.sidebarMinimumWidth, maximumWidth);
  return MIN(MAX(desiredWidth, minimumWidth), maximumWidth);
}

- (void)prepareResponsiveLayoutForWindowWidth:(CGFloat)windowWidth {
  if (!self.sidebarWidthConstraint || !self.contentLeadingConstraint || !self.tabStackLeadingConstraint) {
    return;
  }

  CGFloat targetSidebarContentWidth = [self sidebarContentWidthForWindowWidth:windowWidth];
  CGFloat targetSidebarWidth = self.sidebarVisible ? targetSidebarContentWidth : self.palette.space0;
  CGFloat targetContentLeading = self.sidebarVisible ? self.palette.space3 : self.palette.space4;
  CGFloat targetContentLeadingOffset = targetSidebarWidth + targetContentLeading;
  CGFloat targetTabLeading = [self tabStackLeadingConstantForSidebarWidth:targetSidebarWidth];
  CGFloat targetTabAvailableWidth = [self availableTabStripWidthForLeadingConstant:targetTabLeading
                                                                       topbarWidth:windowWidth];

  self.sidebarWidthConstraint.constant = targetSidebarContentWidth;
  self.contentLeadingConstraint.constant = targetContentLeadingOffset;
  self.tabStackLeadingConstraint.constant = targetTabLeading;
  if (self.splitWorkspace.split) {
    [self prepareSplitContentWidths:windowWidth - targetContentLeadingOffset - self.palette.space4];
  } else if (self.messageInputWidthConstraint) {
    CGFloat targetInputWidth = [self messageInputWidthForWindowWidth:windowWidth
                                                         sidebarWidth:targetSidebarWidth
                                                contentLeadingPadding:targetContentLeading];
    self.messageInputWidthConstraint.constant = targetInputWidth;
    [self applyBrowserAddressInputWidth:targetInputWidth];
  }
  [self.workspaceTabsController updateTabWidthsForAvailableWidth:targetTabAvailableWidth
    contentWidth:MAX(0,windowWidth-targetContentLeadingOffset-self.palette.space4)];
}

- (void)toggleSidebar:(id)sender {
  if (self.incognito) return;
  self.sidebarVisible = !self.sidebarVisible;
  [self updateSidebarLayoutAnimated:YES];
}

- (void)resizeSidebar:(TLSidebarResizeHandle *)sender {
  if (!self.sidebarVisible) {
    return;
  }

  if (sender.dragPhase == TLSidebarResizeHandlePhaseBegan) {
    self.sidebarResizeStartWidth = [self currentSidebarWidth];
    return;
  }

  if (sender.dragPhase == TLSidebarResizeHandlePhaseChanged ||
      sender.dragPhase == TLSidebarResizeHandlePhaseEnded) {
    self.sidebarPreferredWidth = [self clampedSidebarWidthForPreferredWidth:self.sidebarResizeStartWidth + sender.dragDeltaX];
    [self updateSidebarLayoutAnimated:NO];
  }
}

- (void)invalidateSidebarResizeCursorRects {
  if (self.sidebarResizeHandle.window) {
    [self.sidebarResizeHandle.window invalidateCursorRectsForView:self.sidebarResizeHandle];
  }
}

- (void)updateSidebarLayoutAnimated:(BOOL)animated {
  if (!self.sidebarWidthConstraint) {
    return;
  }

  NSView *layoutView = self.window.contentView;
  BOOL hideAfterLayout = !self.sidebarVisible;
  CGFloat windowWidth = NSWidth(self.window.contentView.bounds);
  CGFloat targetSidebarWidth = [self currentSidebarWidth];
  CGFloat targetSidebarContentWidth = [self currentSidebarContentWidth];
  CGFloat targetTabLeading = [self tabStackLeadingConstant];
  CGFloat targetContentLeading = [self contentLeadingPadding];
  CGFloat targetContentLeadingOffset = [self contentLeadingOffsetForSidebarWidth:targetSidebarWidth];
  CGFloat targetInputWidth = [self messageInputWidthForWindowWidth:windowWidth
                                                      sidebarWidth:targetSidebarWidth
                                             contentLeadingPadding:targetContentLeading];
  if (!self.sidebarTransitions) self.sidebarTransitions = [[TLTransitionCoordinator alloc] init];
  [self.sidebarTransitions cancelTransitionForKey:@"sidebar"];
  [layoutView layoutSubtreeIfNeeded];
  CGFloat startWidth = self.sidebarWidthConstraint.constant;
  CGFloat startTabLeading = self.tabStackLeadingConstraint.constant;
  CGFloat startContentLeading = self.contentLeadingConstraint.constant;
  CGFloat startInputWidth = self.messageInputWidthConstraint.constant;
  CGFloat startAlpha = self.sidebarView.hidden ? 0 : self.sidebarView.alphaValue;
  self.sidebarView.hidden = NO;
  self.sidebarResizeHandle.hidden = NO;
  __weak typeof(self) weakSelf = self;
  NSTimeInterval duration = animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0.18 : 0;
  [self.sidebarTransitions startTransitionForKey:@"sidebar" duration:duration update:^(CGFloat progress) {
    TalariaWindowController *owner = weakSelf;
    if (!owner) return;
    // Layout, selection geometry and the union outline share one model-frame tick.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    owner.sidebarWidthConstraint.constant = startWidth + (targetSidebarContentWidth - startWidth) * progress;
    owner.tabStackLeadingConstraint.constant = startTabLeading + (targetTabLeading - startTabLeading) * progress;
    owner.contentLeadingConstraint.constant = startContentLeading + (targetContentLeadingOffset - startContentLeading) * progress;
    if (!owner.splitWorkspace.split) owner.messageInputWidthConstraint.constant = startInputWidth + (targetInputWidth - startInputWidth) * progress;
    else [owner prepareSplitContentWidths:NSWidth(owner.window.contentView.bounds) - owner.contentLeadingConstraint.constant - owner.palette.space4];
    owner.sidebarView.alphaValue = startAlpha + ((hideAfterLayout ? 0 : 1) - startAlpha) * progress;
    if (!owner.splitWorkspace.split) [owner applyBrowserAddressInputWidth:owner.messageInputWidthConstraint.constant];
    [layoutView layoutSubtreeIfNeeded];
    [owner updateWorkspaceTabWidths];
    [layoutView layoutSubtreeIfNeeded];
    [owner.workspaceTabsController updateEdgeAttachmentState];
    [owner.workspaceOutline updateOutline];
    [CATransaction commit];
  } completion:^(BOOL finished) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || !finished) return;
    owner.sidebarView.hidden = hideAfterLayout;
    owner.sidebarResizeHandle.hidden = hideAfterLayout;
    owner.sidebarView.alphaValue = 1;
    [owner invalidateSidebarResizeCursorRects];
    [owner.workspaceOutline updateOutline];
  }];
}

- (NSUInteger)indexOfSessionChatID:(NSInteger)chatID {
  NSArray<TLWorkspaceTab *> *chatTabs = [self workspaceTabsOfKind:TLWorkspaceTabKindChat];
  for (NSUInteger index = 0; index < chatTabs.count; index += 1) {
    if (chatTabs[index].tabID == chatID) {
      return index;
    }
  }

  return NSNotFound;
}

- (void)addChatToSessionIfNeeded:(NSInteger)chatID activate:(BOOL)activate {
  TLChatSummary *chat = [self summaryForChatID:chatID];
  TLWorkspaceTab *existing = [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
  NSString *title = chat.title.length > 0 ? chat.title : (existing.title.length > 0 ? existing.title : @"New chat");
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                             tabID:chatID
                                             title:title
                                           toolTip:title
                                               URL:nil
                                         closeable:YES];
  [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:self.chatWorkspace
                                                      openAction:@selector(openChatTab:)
                                                     closeAction:@selector(closeChatTab:)]
            forTab:tab];
  [self.appStateManager upsertWorkspaceTab:tab activate:activate];
}

- (NSArray<TLWorkspaceTab *> *)workspaceTabsOfKind:(TLWorkspaceTabKind)kind {
  NSMutableArray<TLWorkspaceTab *> *tabs = [NSMutableArray array];
  for (TLWorkspaceTab *tab in self.appStateManager.snapshot.workspaceTabs) {
    if (tab.kind == kind) {
      [tabs addObject:tab];
    }
  }
  return tabs;
}

- (TLChatSummary *)summaryForChatID:(NSInteger)chatID {
  for (TLChatSummary *summary in self.chats) {
    if (summary.chatID == chatID) {
      return summary;
    }
  }

  if (self.activeChat && self.activeChat.chatID == chatID) {
    return self.activeChat;
  }

  return nil;
}

- (NSUInteger)indexOfBrowserTabID:(NSInteger)tabID {
  NSArray<TLWorkspaceTab *> *browserTabs = [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser];
  for (NSUInteger index = 0; index < browserTabs.count; index += 1) {
    if (browserTabs[index].tabID == tabID) {
      return index;
    }
  }

  return NSNotFound;
}

- (TLWorkspaceTab *)browserTabWithID:(NSInteger)tabID {
  return [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:tabID];
}

- (TLWorkspaceTabRuntime *)runtimeForKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  return self.workspaceTabRuntimes[TLWorkspaceTabRuntimeKey(kind, tabID)];
}

- (TLWorkspaceTabRuntime *)runtimeForTab:(TLWorkspaceTab *)tab {
  if (!tab) {
    return nil;
  }
  return [self runtimeForKind:tab.kind tabID:tab.tabID];
}

- (void)setRuntime:(TLWorkspaceTabRuntime *)runtime forTab:(TLWorkspaceTab *)tab {
  if (!runtime || !tab) {
    return;
  }
  if (tab.kind == TLWorkspaceTabKindChat) runtime.featureController = self.chatPresentations[@(tab.tabID)] ?: self.chatPresentation;
  if (tab.kind == TLWorkspaceTabKindSettings) runtime.featureController = self.settingsTabController;
  if (tab.kind == TLWorkspaceTabKindDownloads) runtime.featureController = self.downloadsController;
  if (tab.kind == TLWorkspaceTabKindAutomations) runtime.featureController = self.automationsController;
  TLWorkspaceTabRuntime *previous = self.workspaceTabRuntimes[TLWorkspaceTabRuntimeKey(tab.kind, tab.tabID)];
  if (previous != runtime && previous.featureController == runtime.featureController) previous.featureController = nil;
  self.workspaceTabRuntimes[TLWorkspaceTabRuntimeKey(tab.kind, tab.tabID)] = runtime;
}

- (void)removeRuntimeForKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  if (kind == TLWorkspaceTabKindChat) {
    TLChatTabController *presentation = self.chatPresentations[@(tabID)];
    [presentation close];
    if (presentation.closed) [self.chatPresentations removeObjectForKey:@(tabID)];
    else [self updatePromptQueueForChat:presentation];
  }
  [self.workspaceTabRuntimes removeObjectForKey:TLWorkspaceTabRuntimeKey(kind, tabID)];
}

- (NSView *)contentViewForTab:(TLWorkspaceTab *)tab {
  if (tab && tab.kind == TLWorkspaceTabKindChat) return self.chatPresentations[@(tab.tabID)].chatWorkspace;
  return [self runtimeForTab:tab].contentView;
}

- (void)ensureHistoryTab {
  if (self.historyTab) {
    return;
  }

  self.historyTab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindHistory
                                          tabID:0
                                          title:@"History"
                                        toolTip:@"History"
                                            URL:nil
                                      closeable:YES];
  [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:self.historyPanelController.panelView
                                                      openAction:@selector(openHistoryTab:)
                                                     closeAction:@selector(closeHistoryTab:)]
            forTab:self.historyTab];
  [self.appStateManager addWorkspaceTab:self.historyTab activate:NO];
}

- (void)activateTabKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  [self.appStateManager activateWorkspaceTabKind:kind tabID:tabID];
}

- (TLWorkspaceTab *)activeWorkspaceTab {
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;
  return [self workspaceTabForKind:snapshot.activeTabKind tabID:snapshot.activeTabID];
}

- (TLWorkspaceTab *)workspaceTabForKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  return [self.appStateManager workspaceTabWithKind:kind tabID:tabID];
}

- (void)activateDefaultTab {
  if (self.activeChat && [self.appStateManager hasWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:self.activeChat.chatID]) {
    [self activateTabKind:TLWorkspaceTabKindChat tabID:self.activeChat.chatID];
    return;
  }

  TLWorkspaceTab *fallbackTab = [self workspaceTabs].firstObject;
  if (fallbackTab) {
    [self activateTabKind:fallbackTab.kind tabID:fallbackTab.tabID];
    return;
  }
}

- (BOOL)isBrowserURL:(NSURL *)URL {
  return TLBrowserImageURLIsSupported(URL);
}

- (NSString *)browserTabTitleForURL:(NSURL *)URL {
  if (URL.host.length > 0) {
    return URL.host;
  }
  if (URL.absoluteString.length > 0) {
    return URL.absoluteString;
  }
  return @"Browser";
}

- (BOOL)isHistoryScreenActive {
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;
  return snapshot.activeTabKind == TLWorkspaceTabKindHistory && self.historyTab && snapshot.activeTabID == self.historyTab.tabID;
}

- (BOOL)isChatWorkspaceActive { return [self isChatWorkspaceActiveForChat:[self currentChatPresentation]]; }
- (BOOL)isChatWorkspaceActiveForChat:(TLChatTabController *)chatContext {
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;
  return snapshot.activeTabKind == TLWorkspaceTabKindChat && chatContext.chat && snapshot.activeTabID == chatContext.chat.chatID;
}

- (void)mountWorkspaceView:(NSView *)view inHost:(NSView *)host {
  if (!view || !host || view.superview == host) return;
  [view removeFromSuperview];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [host addSubview:view];
  [NSLayoutConstraint activateConstraints:@[
    [view.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
    [view.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
    [view.topAnchor constraintEqualToAnchor:host.topAnchor],
    [view.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
  ]];
}
- (void)addWorkspaceContentView:(NSView *)contentView {
  [self mountWorkspaceView:contentView inHost:self.splitWorkspace.leftHost ?: self.contentHost];
}

- (NSArray<TLWorkspaceTab *> *)workspaceTabs {
  return self.appStateManager.snapshot.workspaceTabs;
}

- (BOOL)closeWindowIfOnlyWorkspaceTab:(TLWorkspaceTab *)tab {
  NSArray<TLWorkspaceTab *> *tabs = [self workspaceTabs];
  if (!tab || tabs.count != 1) {
    return NO;
  }

  TLWorkspaceTab *onlyTab = tabs.firstObject;
  if (onlyTab.kind != tab.kind || onlyTab.tabID != tab.tabID) {
    return NO;
  }

  [self.window performClose:nil];
  return YES;
}

- (NSString *)displayTitleForWorkspaceTab:(TLWorkspaceTab *)tab {
  if (tab.kind == TLWorkspaceTabKindChat) {
    TLChatSummary *chat = [self summaryForChatID:tab.tabID];
    return chat.title.length > 0 ? chat.title : (tab.title.length > 0 ? tab.title : @"New chat");
  }
  if (tab.kind == TLWorkspaceTabKindBrowser) {
    return tab.title.length > 0 ? tab.title : [self browserTabTitleForURL:tab.URL];
  }
  return tab.title.length > 0 ? tab.title : @"";
}

- (NSString *)displayIconForWorkspaceTab:(TLWorkspaceTab *)tab {
  if (tab.kind == TLWorkspaceTabKindChat) {
    TLChatSummary *chat = [self summaryForChatID:tab.tabID];
    return chat.icon.length > 0 ? chat.icon : TLDefaultChatIcon();
  }
  if (tab.kind == TLWorkspaceTabKindBrowser) {
    return @"\U0001F310";
  }
  return @"";
}

- (NSImage *)displayImageForWorkspaceTab:(TLWorkspaceTab *)tab {
  if (tab.kind != TLWorkspaceTabKindBrowser) {
    return nil;
  }
  return ((TLBrowserTabController *)[self runtimeForTab:tab].featureController).favicon;
}

- (NSString *)displaySystemIconNameForWorkspaceTab:(TLWorkspaceTab *)tab {
  switch (tab.kind) {
    case TLWorkspaceTabKindHistory:
      return @"clock";
    case TLWorkspaceTabKindSettings:
      return @"gearshape";
    case TLWorkspaceTabKindAgents:
      return @"cpu";
    case TLWorkspaceTabKindDownloads:
      return @"arrow.down.circle";
    case TLWorkspaceTabKindAutomations:
      return @"clock.arrow.circlepath";
    case TLWorkspaceTabKindDebug:
      return @"terminal";
    case TLWorkspaceTabKindChat:
    case TLWorkspaceTabKindBrowser:
      return @"";
  }
}

- (NSString *)displayToolTipForWorkspaceTab:(TLWorkspaceTab *)tab {
  if (tab.kind == TLWorkspaceTabKindChat) {
    return [self displayTitleForWorkspaceTab:tab];
  }
  if (tab.kind == TLWorkspaceTabKindBrowser) {
    return tab.URL.absoluteString ?: [self displayTitleForWorkspaceTab:tab];
  }
  return tab.toolTip.length > 0 ? tab.toolTip : [self displayTitleForWorkspaceTab:tab];
}

- (NSArray<TLWorkspaceTab *> *)workspaceTabsForTabsController:(TLWorkspaceTabsController *)controller {
  NSMutableArray *tabs = [NSMutableArray new];
  NSMutableSet *seen = [NSMutableSet new];
  for (TLWorkspaceTab *tab in [self workspaceTabs]) {
    TLWorkspaceSplitGroup *group = [self.splitState groupForTab:tab];
    if (group && [seen containsObject:group]) continue;
    if (group) [seen addObject:group];
    [tabs addObject:tab];
  }
  return tabs;
}
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller isTabSplitCompanion:(TLWorkspaceTab *)tab { return NO; }
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller isTabActive:(TLWorkspaceTab *)tab {
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:tab];
  return [self isWorkspaceTabActive:tab] || (group && group == [self.splitState groupForTab:[self activeWorkspaceTab]]);
}

- (NSColor *)workspaceTabsController:(TLWorkspaceTabsController *)controller backgroundColorForTab:(TLWorkspaceTab *)tab {
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:tab];
  if (group) return self.palette.tabBackground;
  id feature=[self runtimeForTab:tab].featureController;
  return [feature isKindOfClass:TLBrowserTabController.class] ? ((TLBrowserTabController *)feature).headerContentColor : nil;
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayTitleForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? @"Split view" : [self displayTitleForWorkspaceTab:tab];
}

- (NSImage *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayImageForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? nil : [self displayImageForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayIconForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? @"" : [self displayIconForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displaySystemIconNameForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? @"rectangle.3.group" : [self displaySystemIconNameForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayToolTipForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? @"Split view" : [self displayToolTipForWorkspaceTab:tab];
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller openActionForTab:(TLWorkspaceTab *)tab {
  return [self runtimeForTab:tab].openAction;
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller closeActionForTab:(TLWorkspaceTab *)tab {
  return [self.splitState groupForTab:tab] ? @selector(closeSplitTab:) : [self runtimeForTab:tab].closeAction;
}

- (NSRect)workspaceTabsControllerContentDragBoundsInWindow:(TLWorkspaceTabsController *)controller {
  if (!self.contentHost.window) {
    return NSZeroRect;
  }

  return [self.contentHost convertRect:self.contentHost.bounds toView:nil];
}

- (NSRect)workspaceTabsControllerNewTabButtonBoundsInWindow:(TLWorkspaceTabsController *)controller {
  if (!self.createChatButton.window) {
    return NSZeroRect;
  }

  return [self.createChatButton convertRect:self.createChatButton.bounds toView:nil];
}

- (BOOL)workspaceTabsControllerShouldConnectFirstActiveTabToContentEdge:(TLWorkspaceTabsController *)controller {
  return self.sidebarVisible;
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller firstTabEdgeCornerRadiusDidChange:(CGFloat)cornerRadius {
  [self applyContentTopLeftCornerRadius:cornerRadius];
}

- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index {
  NSMutableArray *visible = [[self workspaceTabsForTabsController:controller] mutableCopy];
  TLWorkspaceSplitGroup *movingGroup = [self.splitState groupForTab:tab];
  NSUInteger from = [visible indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *candidate, NSUInteger i, BOOL *stop) {
    return [TLWorkspaceTabIdentity(candidate) isEqual:TLWorkspaceTabIdentity(tab)] || (movingGroup && movingGroup == [self.splitState groupForTab:candidate]);
  }];
  if (from == NSNotFound) return;
  TLWorkspaceTab *representative = visible[from];
  [visible removeObjectAtIndex:from]; [visible insertObject:representative atIndex:MIN(index,visible.count)];
  NSMutableArray *ordered = [NSMutableArray new];
  for (TLWorkspaceTab *entry in visible) {
    TLWorkspaceSplitGroup *group = [self.splitState groupForTab:entry];
    for (TLWorkspaceTab *member in [self workspaceTabs])
      if (group ? [group.identities containsObject:TLWorkspaceTabIdentity(member)] : [TLWorkspaceTabIdentity(entry) isEqual:TLWorkspaceTabIdentity(member)]) [ordered addObject:member];
  }
  for (NSUInteger i=0;i<ordered.count;i++) {
    TLWorkspaceTab *entry=ordered[i]; [self.appStateManager moveWorkspaceTabWithKind:entry.kind tabID:entry.tabID toIndex:i];
  }
  [self renderWorkspaceTabs];
}
- (void)closePaneWithIdentity:(NSString *)identity {
  TLWorkspaceTab *tab = [self tabWithPresentationIdentity:identity];
  if (!tab || !tab.closeable) return;
  NSButton *sender = [NSButton new]; sender.tag = tab.tabID;
  SEL action = [self runtimeForTab:tab].closeAction;
  if (action) [NSApp sendAction:action to:self from:sender];
}
- (void)closeSplitTab:(id)sender {
  TLWorkspaceTab *tab = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
  if (!tab) return;
  NSArray *identities = [[self.splitState groupForTab:tab].identities copy];
  for (NSString *identity in identities) [self closePaneWithIdentity:identity];
}

- (BOOL)isWorkspaceTabActive:(TLWorkspaceTab *)tab {
  switch (tab.kind) {
    case TLWorkspaceTabKindChat:
      return [self isChatWorkspaceActive] && self.activeChat && self.activeChat.chatID == tab.tabID;
    case TLWorkspaceTabKindHistory:
      return [self isHistoryScreenActive];
    case TLWorkspaceTabKindBrowser:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindBrowser &&
        self.appStateManager.snapshot.activeTabID == tab.tabID;
    case TLWorkspaceTabKindSettings:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindSettings &&
        self.settingsTab &&
        self.appStateManager.snapshot.activeTabID == self.settingsTab.tabID;
    case TLWorkspaceTabKindAgents:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindAgents &&
        self.agentsTab &&
        self.appStateManager.snapshot.activeTabID == self.agentsTab.tabID;
    case TLWorkspaceTabKindDownloads:
      return self.downloadsTab && self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindDownloads &&
        self.appStateManager.snapshot.activeTabID == self.downloadsTab.tabID;
    case TLWorkspaceTabKindAutomations:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindAutomations &&
        self.automationsTab && self.appStateManager.snapshot.activeTabID == self.automationsTab.tabID;
    case TLWorkspaceTabKindDebug:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindDebug &&
        self.debugTab &&
        self.appStateManager.snapshot.activeTabID == self.debugTab.tabID;
  }
}

- (TLWorkspaceTab *)tabWithPresentationIdentity:(NSString *)identity {
  if (!identity) return nil;
  for (TLWorkspaceTab *tab in [self workspaceTabs]) if ([TLWorkspaceTabIdentity(tab) isEqual:identity]) return tab;
  return nil;
}

- (void)installSplitWorkspace {
  self.splitState = [TLWorkspaceSplitState new];
  self.splitWorkspace = [TLSplitWorkspaceView new];
  self.splitWorkspace.palette = self.palette;
  [self mountWorkspaceView:self.splitWorkspace inHost:self.contentHost];
  __weak typeof(self) weakSelf = self;
  self.splitWorkspace.focusIdentity = ^(NSString *identity) { [weakSelf focusWorkspaceTab:[weakSelf tabWithPresentationIdentity:identity]]; };
  self.splitWorkspace.closeIdentity = ^(NSString *identity) { [weakSelf closePaneWithIdentity:identity]; };
  self.splitWorkspace.dragPane = ^(NSString *identity, NSPoint point, BOOL ended, BOOL cancelled) {
    [weakSelf dragSplitPane:identity atWindowPoint:point ended:ended cancelled:cancelled];
  };
  self.splitWorkspace.fractionChanged = ^(CGFloat fraction) {
    TalariaWindowController *owner = weakSelf;
    [owner.splitState groupForTab:[owner activeWorkspaceTab]].fraction = fraction;
  };
  self.splitWorkspace.layoutWeightsChanged = ^(NSDictionary *weights) {
    TalariaWindowController *owner = weakSelf;
    [owner.splitState groupForTab:[owner activeWorkspaceTab]].layoutWeights = weights;
  };
  self.splitWorkspace.contentSizeChanged = ^{ [weakSelf updateSplitContentSizes]; };
  self.paneFocusMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
    NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown | NSEventMaskScrollWheel
    handler:^NSEvent *(NSEvent *event) {
    TalariaWindowController *owner = weakSelf;
    if (event.window != owner.window) return event;
    if (event.type == NSEventTypeScrollWheel || event.type == NSEventTypeLeftMouseDown) {
      for (TLChatTabController *presentation in owner.chatPresentations.allValues) {
        NSPoint scrollPoint = [presentation.messageScrollView convertPoint:event.locationInWindow fromView:nil];
        if (presentation.messageScrollView.window && !presentation.chatWorkspace.hidden &&
            NSPointInRect(scrollPoint, presentation.messageScrollView.bounds)) {
          presentation.notificationTargetMessageID = nil;
          presentation.notificationTargetToolCallID = nil;
          presentation.notificationDidReveal = nil;
        }
      }
    }
    if (!owner.splitWorkspace.split) return event;
    NSPoint point = [owner.splitWorkspace convertPoint:event.locationInWindow fromView:nil];
    // Scrolling does not steal typing focus. Native scroll views still receive it.
    if (event.type != NSEventTypeScrollWheel) {
      NSString *identity = [owner.splitWorkspace identityAtPoint:point];
      if (identity) [owner focusWorkspaceTab:[owner tabWithPresentationIdentity:identity]];
    }
    return event;
  }];
}

- (void)focusWorkspaceTab:(TLWorkspaceTab *)tab {
  if (!tab || [self isWorkspaceTabActive:tab]) return;
  if (tab.kind == TLWorkspaceTabKindChat) [self loadChatWithID:tab.tabID];
  else {
    [self hideSlashCommandList];
    [self activateTabKind:tab.kind tabID:tab.tabID];
    [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
  }
}
- (void)focusChatContainingView:(id)view {
  if (![view isKindOfClass:NSView.class]) return;
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    if ([view isDescendantOf:presentation.chatWorkspace]) {
      TLWorkspaceTab *tab = [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:presentation.chat.chatID];
      [self focusWorkspaceTab:tab];
      return;
    }
  }
}
- (void)focusSplitPane:(BOOL)right {
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:[self activeWorkspaceTab]];
  [self focusWorkspaceTab:[self tabWithPresentationIdentity:right ? group.rightIdentity : group.leftIdentity]];
}
- (BOOL)isChatPresentationVisible { return [self isChatPresentationVisibleForChat:[self currentChatPresentation]]; }
- (BOOL)isChatPresentationVisibleForChat:(TLChatTabController *)chatContext {
  TLWorkspaceTab *tab = [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatContext.chat.chatID];
  if ([self isChatWorkspaceActiveForChat:chatContext]) return YES;
  if (!tab || !chatContext.chat) return NO;
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:[self activeWorkspaceTab]];
  return group && group == [self.splitState groupForTab:tab];
}
- (void)prepareSplitContentWidths:(CGFloat)workspaceWidth {
  CGFloat scale = workspaceWidth / MAX(1,NSWidth(self.splitWorkspace.bounds));
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    if (presentation.chatWorkspace.isHiddenOrHasHiddenAncestor) continue;
    CGFloat paneWidth = NSWidth(presentation.chatWorkspace.superview.bounds) * scale;
    presentation.messageInputWidthConstraint.constant = MAX(0, MIN(self.palette.messageInputMaxWidth, paneWidth - self.palette.space11 * 2));
  }
  for (TLWorkspaceTab *tab in [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser]) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:tab];
    if (runtime.contentView.isHiddenOrHasHiddenAncestor) continue;
    CGFloat paneWidth = NSWidth(runtime.contentView.superview.bounds) * scale;
    [(TLBrowserTabController *)runtime.featureController setAddressInputWidth:MAX(0, MIN(self.palette.messageInputMaxWidth, paneWidth - self.palette.space11 * 2))];
  }
}
// Infer the solid tab color from the corresponding horizontal page edge.
- (void)updateBrowserTabColorSample {
  TLBrowserTabController *browser=[self activeBrowserController];
  if(!browser || !browser.view.window)return;
  TLChromeTabSelectionView *selection=self.workspaceTabsController.selectionView;
  NSRect page=[browser.view convertRect:browser.view.bounds toView:selection];
  CGPathRef outline=[selection newOutlinePath];
  NSRect tab=NSRectFromCGRect(CGPathGetBoundingBox(outline));CGPathRelease(outline);
  CGFloat left=MAX(NSMinX(page),NSMinX(tab)),right=MIN(NSMaxX(page),NSMaxX(tab));
  browser.tabColorSampleRect=NSWidth(page)>0 && right>left
    ? NSMakeRect((left-NSMinX(page))/NSWidth(page),0,(right-left)/NSWidth(page),1) : NSZeroRect;
}

- (void)updateSplitContentSizes {
  if (self.updatingSplitLayout || !self.splitWorkspace) return;
  self.updatingSplitLayout = YES;
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    if (presentation.chatWorkspace.isHiddenOrHasHiddenAncestor) continue;
      CGFloat available = NSWidth(presentation.chatWorkspace.superview.bounds) - self.palette.space11 * 2;
      CGFloat width = MAX(0, MIN(self.palette.messageInputMaxWidth, available));
      BOOL changed = fabs(presentation.messageInputWidthConstraint.constant - width) > 0.5;
      presentation.messageInputWidthConstraint.constant = width;
      if (changed) {
        [presentation.messageInput recalculateHeight];
        [presentation updateMessageScrollInsets];
        [presentation resetMessageRowCache];
        [presentation renderMessagesScrollingToBottom:NO];
      }

  }
  for (TLWorkspaceTab *tab in [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser]) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:tab];
    if (runtime.contentView.isHiddenOrHasHiddenAncestor) continue;
    CGFloat width = MAX(0, MIN(self.palette.messageInputMaxWidth, NSWidth(runtime.contentView.superview.bounds) - self.palette.space11 * 2));
    [(TLBrowserTabController *)runtime.featureController setAddressInputWidth:width];
  }
  self.updatingSplitLayout = NO;
  [self updateBrowserTabColorSample];
}

- (TLWorkspaceTab *)splitCompanionForTab:(TLWorkspaceTab *)tab preferred:(TLWorkspaceTab *)preferred {
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:tab];
  NSString *identity = TLWorkspaceTabIdentity(tab);
  if (group) return [self tabWithPresentationIdentity:[identity isEqual:group.leftIdentity] ? group.rightIdentity : group.leftIdentity];
  TLWorkspaceTab *currentPreferred = preferred ? [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(preferred)] : nil;
  if (currentPreferred && ![TLWorkspaceTabIdentity(currentPreferred) isEqual:identity]) return currentPreferred;
  NSArray *tabs = [self workspaceTabs];
  NSUInteger index = [tabs indexOfObjectPassingTest:^BOOL(TLWorkspaceTab *candidate, NSUInteger i, BOOL *stop) {
    return [TLWorkspaceTabIdentity(candidate) isEqual:identity];
  }];
  if (tabs.count < 2 || index == NSNotFound) return nil;
  return tabs[index > 0 ? index - 1 : 1];
}
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)left {
  [self splitTab:tab besideTab:other placement:left ? TLSplitPlacementLeft : TLSplitPlacementRight];
}
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement {
  tab = [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(tab)];
  other = [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(other)];
  if (!tab || !other || [TLWorkspaceTabIdentity(tab) isEqual:TLWorkspaceTabIdentity(other)]) return;
  // Materialize both chat presentations before exposing the pair.
  if (other.kind == TLWorkspaceTabKindChat && !self.chatPresentations[@(other.tabID)]) [self loadChatWithID:other.tabID];
  if (tab.kind == TLWorkspaceTabKindChat && !self.chatPresentations[@(tab.tabID)]) [self loadChatWithID:tab.tabID];
  TLWorkspaceSplitGroup *previousGroup = [self.splitState groupForTab:other];
  NSString *previousLeftIdentity = previousGroup.leftIdentity;
  BOOL alreadySideBySide = previousGroup.columns.count == 2 && previousGroup.identities.count == 2 &&
    [previousGroup.identities containsObject:TLWorkspaceTabIdentity(tab)];
  if (![self.splitState splitTab:tab besideTab:other placement:placement]) return;
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:tab];
  BOOL browserAndChat = (tab.kind == TLWorkspaceTabKindBrowser && other.kind == TLWorkspaceTabKindChat) ||
    (tab.kind == TLWorkspaceTabKindChat && other.kind == TLWorkspaceTabKindBrowser);
  if (alreadySideBySide && browserAndChat && group.columns.count == 2 &&
      ![previousLeftIdentity isEqual:group.leftIdentity]) {
    // Swapping the pair keeps each view's share, including a manual resize.
    group.fraction = 1 - group.fraction;
    group.layoutWeights = nil;
  } else if (!alreadySideBySide && browserAndChat && group.identities.count == 2 && group.columns.count == 2 &&
      NSWidth(self.splitWorkspace.bounds) > 1200) {
    TLWorkspaceTab *browser = tab.kind == TLWorkspaceTabKindBrowser ? tab : other;
    group.fraction = [group.leftIdentity isEqual:TLWorkspaceTabIdentity(browser)] ? 0.7 : 0.3;
    group.layoutWeights = nil;
  }
  [self focusWorkspaceTab:tab];
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs]; [self updateControlStates];
}
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller willSelectTab:(TLWorkspaceTab *)tab {
  self.tabBeforePointerSelection = [self activeWorkspaceTab];
}
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller dragTab:(TLWorkspaceTab *)tab atWindowPoint:(NSPoint)point {
  NSPoint bookmarkPoint = [self.sidebarShortcutsView convertPoint:point fromView:nil];
  self.bookmarkDropTarget = self.sidebarVisible && !self.sidebarShortcutsView.isHiddenOrHasHiddenAncestor &&
    (tab.kind == TLWorkspaceTabKindChat || (tab.kind == TLWorkspaceTabKindBrowser && [TLBookmark normalizedURL:tab.URL.absoluteString])) &&
    NSPointInRect(bookmarkPoint, self.sidebarShortcutsView.bounds);
  self.sidebarShortcutsView.dropTargeted = self.bookmarkDropTarget;
  if (self.bookmarkDropTarget) {
    [self.splitWorkspace clearDropPreview];
    self.splitDropSide = TLSplitDropSideNone;
    self.splitDropTarget = nil;
    return YES;
  }
  NSPoint topbarPoint = [self.topbar convertPoint:point fromView:nil];
  BOOL outside = !NSPointInRect(topbarPoint, NSInsetRect(self.topbar.bounds, 0, -self.palette.space3));
  TLWorkspaceTab *companion = [self splitCompanionForTab:tab preferred:self.tabBeforePointerSelection];
  BOOL grouped = [self.splitState groupForTab:tab] != nil;
  // Reveal all destinations on the first drag movement, even over the tab bar.
  if (companion && !grouped) [self focusWorkspaceTab:companion];
  NSPoint local = [self.splitWorkspace convertPoint:point fromView:nil];
  [self.splitWorkspace prepareDropTargetsWithValidator:^BOOL(NSString *identity, TLSplitDropSide side) {
    return !grouped && [self.splitState canSplitTab:tab besideTab:[self tabWithPresentationIdentity:identity] placement:[self placementForDropSide:side]];
  }];
  self.splitDropSide = outside ? [self.splitWorkspace dropSideAtPoint:local] : TLSplitDropSideNone;
  self.splitDropTarget = [self tabWithPresentationIdentity:[self.splitWorkspace dropIdentityAtPoint:local]] ?: companion;
  [self.splitWorkspace showDropSide:self.splitDropSide title:[self displayTitleForWorkspaceTab:tab] point:local];
  return outside;
}
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller endDraggingTab:(TLWorkspaceTab *)tab cancelled:(BOOL)cancelled {
  BOOL bookmarkDrop = self.bookmarkDropTarget;
  self.bookmarkDropTarget = NO;
  self.sidebarShortcutsView.dropTargeted = NO;
  TLWorkspaceTab *other = self.splitDropTarget;
  TLSplitDropSide side = self.splitDropSide;
  [self.splitWorkspace clearDropPreview];
  self.splitDropTarget = nil; self.splitDropSide = TLSplitDropSideNone;
  if (!cancelled && bookmarkDrop) [self showBookmarkEditorForTab:tab];
  else if (!cancelled && side != TLSplitDropSideNone && other) [self splitTab:tab besideTab:other placement:[self placementForDropSide:side]];
  else if (other) [self focusWorkspaceTab:self.tabBeforePointerSelection ?: tab];
  self.tabBeforePointerSelection = nil;
}
- (TLSplitPlacement)placementForDropSide:(TLSplitDropSide)side {
  switch (side) {
    case TLSplitDropSideAbove: return TLSplitPlacementAbove;
    case TLSplitDropSideBelow: return TLSplitPlacementBelow;
    case TLSplitDropSideRight: return TLSplitPlacementRight;
    default: return TLSplitPlacementLeft;
  }
}
- (void)dragSplitPane:(NSString *)identity atWindowPoint:(NSPoint)point ended:(BOOL)ended cancelled:(BOOL)cancelled {
  TLWorkspaceTab *tab = [self tabWithPresentationIdentity:identity];
  if (!tab) return;
  BOOL inStrip = NSPointInRect([self.topbar convertPoint:point fromView:nil],self.topbar.bounds);
  NSPoint local = [self.splitWorkspace convertPoint:point fromView:nil];
  [self.splitWorkspace prepareDropTargetsWithValidator:^BOOL(NSString *candidate, TLSplitDropSide side) {
    return [self.splitState canSplitTab:tab besideTab:[self tabWithPresentationIdentity:candidate] placement:[self placementForDropSide:side]];
  }];
  TLWorkspaceTab *other = [self tabWithPresentationIdentity:[self.splitWorkspace dropIdentityAtPoint:local]];
  TLSplitDropSide side = [self.splitWorkspace dropSideAtPoint:local];
  if (!ended) {
    if (inStrip) [self.workspaceTabsController showPaneDropAtWindowPoint:point]; else [self.workspaceTabsController clearPaneDrop];
    [self.splitWorkspace showDropSide:inStrip ? TLSplitDropSideNone : side title:[self displayTitleForWorkspaceTab:tab] point:local];
    return;
  }
  [self.splitWorkspace clearDropPreview];
  [self.workspaceTabsController clearPaneDrop];
  if (cancelled) return;
  if (inStrip) {
    NSUInteger index = [self.workspaceTabsController insertionIndexAtWindowPoint:point];
    [self.splitState detachTab:tab];
    [self workspaceTabsController:self.workspaceTabsController moveTab:tab toIndex:index];
    [self focusWorkspaceTab:tab]; [self updateWorkspaceMode]; [self reloadWorkspaceTabs];
  } else if (side != TLSplitDropSideNone) {
    [self splitTab:tab besideTab:other placement:[self placementForDropSide:side]];
  }
}
- (NSMenu *)workspaceTabsController:(TLWorkspaceTabsController *)controller contextMenuForTab:(TLWorkspaceTab *)tab {
  NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
  if (tab.kind == TLWorkspaceTabKindBrowser) {
    NSMenuItem *reload = [[NSMenuItem alloc] initWithTitle:@"Reload" action:@selector(reloadTabFromMenu:) keyEquivalent:@""];
    reload.target = self; reload.representedObject = tab; [menu addItem:reload];
  }
  NSMenuItem *pin = [[NSMenuItem alloc] initWithTitle:tab.pinned ? @"Unpin tab" : @"Pin tab" action:@selector(toggleTabPinFromMenu:) keyEquivalent:@""];
  pin.target = self; pin.representedObject = tab; [menu addItem:pin];
  [menu addItem:NSMenuItem.separatorItem];
  TLWorkspaceTab *other = [self splitCompanionForTab:tab preferred:[self activeWorkspaceTab]];
  NSArray *titles = @[@"Open in Split View on Left", @"Open in Split View on Right", @"Open in Split View Above", @"Open in Split View Below"];
  for (NSUInteger placement=0;placement<titles.count;placement++) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[placement] action:@selector(splitTabFromMenu:) keyEquivalent:@""];
    item.target = self; item.enabled = [self.splitState canSplitTab:tab besideTab:other placement:placement];
    item.representedObject = @{ @"tab":tab, @"placement":@(placement) }; [menu addItem:item];
  }
  if (tab.kind == TLWorkspaceTabKindChat || tab.kind == TLWorkspaceTabKindBrowser) {
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Add to bookmarks" action:@selector(addTabToBookmarks:) keyEquivalent:@""];
    item.target = self; item.representedObject = tab;
    item.enabled = !self.widgetbookMode && (tab.kind == TLWorkspaceTabKindChat || [TLBookmark normalizedURL:tab.URL.absoluteString] != nil);
    [menu addItem:item];
  }
  return menu;
}
- (void)reloadTabFromMenu:(NSMenuItem *)sender {
  TLWorkspaceTab *tab = [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(sender.representedObject)];
  if (!tab || tab.kind != TLWorkspaceTabKindBrowser) return;
  [(TLBrowserTabController *)[self runtimeForTab:tab].featureController reloadBrowser:sender];
}
- (void)toggleTabPinFromMenu:(NSMenuItem *)sender {
  TLWorkspaceTab *tab = [self tabWithPresentationIdentity:TLWorkspaceTabIdentity(sender.representedObject)];
  if (!tab) return;
  [self.appStateManager setWorkspaceTabPinned:!tab.pinned kind:tab.kind tabID:tab.tabID];
  [self reloadWorkspaceTabs];
}
- (void)splitTabFromMenu:(NSMenuItem *)sender {
  TLWorkspaceTab *tab = sender.representedObject[@"tab"];
  TLWorkspaceTab *other = [self splitCompanionForTab:tab preferred:[self activeWorkspaceTab]];
  if (other) [self splitTab:tab besideTab:other placement:[sender.representedObject[@"placement"] integerValue]];
}
- (void)separateSplitFromMenu:(NSMenuItem *)sender {
  TLWorkspaceTab *tab = sender.representedObject;
  [self.splitState detachTab:tab]; [self focusWorkspaceTab:tab];
  [self updateWorkspaceMode]; [self reloadWorkspaceTabs];
}

- (void)updateWorkspaceMode {
  if (self.updatingSplitLayout) return;
  self.updatingSplitLayout = YES;
  self.displayedWorkspaceTab = [self activeWorkspaceTab];
  [self.splitState reconcileTabs:[self workspaceTabs]];
  TLWorkspaceTab *active = [self activeWorkspaceTab];
  TLWorkspaceSplitGroup *group = [self.splitState groupForTab:active];
  self.splitWorkspace.columns = group ? group.columns : (active ? @[@[TLWorkspaceTabIdentity(active)]] : @[]);
  if (group) {
    self.splitWorkspace.fraction = group.fraction;
    [self.splitWorkspace restoreLayoutWeights:group.layoutWeights];
  }
  self.splitWorkspace.focusedIdentity = active ? TLWorkspaceTabIdentity(active) : @"";
  NSMutableArray<NSView *> *visibleViews = [NSMutableArray new];
  NSArray *identities = group ? group.identities : (active ? @[TLWorkspaceTabIdentity(active)] : @[]);
  BOOL downloadsVisible = NO, historyVisible = NO;
  for (NSString *identity in identities) {
    TLWorkspaceTab *tab = [self tabWithPresentationIdentity:identity];
    NSView *view = [self contentViewForTab:tab];
    if (view) [visibleViews addObject:view];
    [self.splitWorkspace setTitle:[self displayTitleForWorkspaceTab:tab] image:[self displayImageForWorkspaceTab:tab]
      icon:[self displayIconForWorkspaceTab:tab] systemIcon:[self displaySystemIconNameForWorkspaceTab:tab] forIdentity:identity];
    [self mountWorkspaceView:view inHost:[self.splitWorkspace hostForIdentity:identity]];
    downloadsVisible |= tab.kind == TLWorkspaceTabKindDownloads;
    historyVisible |= tab.kind == TLWorkspaceTabKindHistory;
  }
  // Only visible content participates in pane layout. Hidden feature screens
  // can carry their own minimum widths; retain them in their runtimes instead
  // of letting those constraints enlarge a different tab's split.
  NSMutableSet<NSView *> *contentViews = [NSMutableSet set];
  for (TLWorkspaceTabRuntime *runtime in self.workspaceTabRuntimes.allValues)
    if (runtime.contentView) [contentViews addObject:runtime.contentView];
  for (TLChatTabController *presentation in self.chatPresentations.allValues)
    if (presentation.chatWorkspace) [contentViews addObject:presentation.chatWorkspace];
  if (self.chatWorkspace) [contentViews addObject:self.chatWorkspace];
  if (self.historyPanelController.panelView) [contentViews addObject:self.historyPanelController.panelView];
  for (NSView *view in contentViews) {
    BOOL visible = [visibleViews containsObject:view];
    view.hidden = !visible;
    if (!visible) [view removeFromSuperview];
  }
  if (downloadsVisible) [self.downloadsController refresh];
  BOOL refreshHistory = historyVisible && (!self.historyWasVisible || self.historyAgentID != self.database.currentAgentID);
  self.historyWasVisible = historyVisible;
  self.historyPanelController.visible = historyVisible;
  if (refreshHistory) [self refreshHermesHistory];
  [self.splitWorkspace layoutSubtreeIfNeeded];
  self.updatingSplitLayout = NO;
  [self updateSplitContentSizes];
}

- (void)reloadWorkspaceTabs {
  if (self.workspaceRenderScheduled) return;
  self.workspaceRenderScheduled = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    TalariaWindowController *owner = weakSelf;
    if (!owner) return;
    TLAppStateSnapshot *snapshot = owner.appStateManager.snapshot;
    if (snapshot.activeTabKind == TLWorkspaceTabKindChat &&
        [owner.appStateManager hasWorkspaceTabWithKind:snapshot.activeTabKind tabID:snapshot.activeTabID] &&
        (!owner.activeChat || owner.activeChat.chatID != snapshot.activeTabID)) {
      [owner loadChatWithID:snapshot.activeTabID];
    }
    [owner updateWorkspaceMode];
    [owner renderWorkspaceTabs];
    [owner updateControlStates];
    owner.workspaceRenderScheduled = NO;
  });
}

- (void)renderWorkspaceTabs {
  if (!self.tabStack) {
    return;
  }

  self.workspaceTabsController.palette = self.palette;
  [self.workspaceTabsController reloadTabs];
  [self updateWorkspaceTabWidths];
  [self styleHeaderButtons];
}

- (void)styleHeaderButtons {
  NSColor *foreground = self.palette.labelText;
  self.sidebarToggleButton.palette = self.palette;
  self.incognitoPill.palette = self.palette;
  self.sidebarToggleButton.contentTintColor = foreground;
  self.createChatButton.palette = self.palette;
  self.createChatButton.contentTintColor = foreground;
  [self styleSidebarActionButtons];
}

- (void)styleSidebarActionButtons {
  self.sidebarActionStack.spacing = self.palette.space0;
  [self updateSidebarContentInsets];

  self.sidebarAutomationsButton.palette = self.palette;
  // This row opens a tab; the tab strip owns the persistent selection state.
  self.sidebarAutomationsButton.selected = NO;
  self.sidebarUserButton.palette = self.palette;
  self.sidebarUserButton.displayName = @"Yaroslav";
  self.sidebarActionStackHeightConstraint.constant = [self sidebarActionStackHeight];
}

- (void)updateSidebarContentInsets {
  self.sidebarTileGridLeadingConstraint.constant = self.palette.sidebarContentLeadingInset;
  self.sidebarTileGridTrailingConstraint.constant = -self.palette.sidebarContentTrailingInset;
  self.sidebarInboxLeadingConstraint.constant = self.palette.sidebarInboxOuterHorizontalInset;
  self.sidebarInboxTrailingConstraint.constant = -self.palette.sidebarInboxOuterHorizontalInset;
  self.sidebarActionStackLeadingConstraint.constant = self.palette.sidebarActionStackLeadingInset;
  self.sidebarActionStackTrailingConstraint.constant = -self.palette.sidebarActionStackTrailingInset;
}

- (void)applyTheme {
  [self.sidebarAgentPaneSurface removeFromSuperview];
  self.sidebarAgentPaneSurface = nil;
  self.sidebarAgentPane = nil;
  self.window.appearance = nil;
  self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem effectiveAppearance:self.window.effectiveAppearance];
  [TLWebKitBrowserController.sharedController applyDarkAppearance:self.palette.dark];
  self.window.opaque = NO;
  self.window.backgroundColor = self.palette.appBackground;
  self.frostedBackgroundView.material = NSVisualEffectMaterialUnderWindowBackground;
  self.frostedBackgroundView.state = NSVisualEffectStateActive;
  self.frostedOverlayView.fillColor = self.palette.frostedOverlay;

  self.rootView.fillColor = self.palette.appBackground;
  self.contentShadowView.fillColor = self.palette.tabBackground;
  self.contentShadowView.borderEdges = TLBorderEdgeNone;
  self.contentShadowView.layer.backgroundColor = TLCGColor(self.palette.transparentSurface);
  self.contentShadowView.layer.masksToBounds = NO;
  // The unified workspace perimeter owns the content + selected-tab shadow.
  self.contentShadowView.layer.shadowOpacity = 0.0;
  self.contentHost.fillColor = self.palette.tabBackground;
  self.workspaceOutline.palette = self.palette;
  self.splitWorkspace.palette = self.palette;
  self.contentHost.layer.masksToBounds = YES;
  [self applyContentTopLeftCornerRadius:self.palette.space5];
  self.sidebarView.fillColor = self.palette.appBackground;
  [self applySidebarTilePalette];
  [self applySidebarInboxPalette];
  [self.historyPanelController applyPalette:self.palette];
  [self.attachmentViewer applyPalette:self.palette];
  self.topbar.fillColor = self.palette.appBackground;
  self.topbar.borderColor = self.palette.topbarBorder;
  self.topbar.borderEdges = TLBorderEdgeNone;
  self.messagesBackground.fillColor = self.palette.tabBackground;
  [self.screensaverView updateBackgroundColor:self.palette.messagesSurface artColor:self.palette.textMuted];
  self.messageStack.spacing = self.palette.messageVerticalSpacing;
  self.messageInput.palette = self.palette;
  [self.chatPresentation applyFindPalette:self.palette];
  [self.onboardingDemoWindowController updatePalette:self.palette];
  [self.providerSetupWindowController applyPalette:self.palette];
  [self applySlashCommandListPalette];
  if (!self.slashCommandListView.hidden) {
    [self updateSlashCommandList];
  }

  for (TLWorkspaceTabRuntime *runtime in self.workspaceTabRuntimes.allValues) {
    [runtime.featureController applyPalette:self.palette];
  }
  if (self.agentsView) {
    self.agentsView.fillColor = self.palette.tabBackground;
    [self.agentsView setNeedsDisplay:YES];
  }
  [self rebuildDebugTabContentForCurrentPalette];
  self.agentsTableView.backgroundColor = self.palette.tabBackground;
  if (self.createAgentButton) {
    [self styleButton:self.createAgentButton background:self.palette.primaryActionSurface foreground:self.palette.primaryActionText];
  }
  if (self.startAgentButton) {
    [self styleButton:self.startAgentButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  if (self.stopAgentButton) {
    [self styleButton:self.stopAgentButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  if (self.agentSettingsButton) {
    [self styleButton:self.agentSettingsButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  if (self.folderAccessButton) {
    [self styleButton:self.folderAccessButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  if (self.deleteAgentButton) {
    [self styleButton:self.deleteAgentButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  if (self.closeAgentsButton) {
    [self styleButton:self.closeAgentsButton background:self.palette.secondaryActionSurface foreground:self.palette.secondaryActionText];
  }
  [self.agentsTableView reloadData];
  [self updateAgentsStatusLabel];

  [self styleHeaderButtons];
  [self updateSidebarLayoutAnimated:NO];

  [self.rootView setNeedsDisplay:YES];
  [self.frostedOverlayView setNeedsDisplay:YES];
  [self.contentShadowView setNeedsDisplay:YES];
  [self.contentHost setNeedsDisplay:YES];
  [self.sidebarView setNeedsDisplay:YES];
  [self.topbar setNeedsDisplay:YES];
  [self.messagesBackground setNeedsDisplay:YES];
  [self.messageInput setNeedsDisplay:YES];
  [self reloadHistoryPanel];
  [self reloadWorkspaceTabs];
  [self resetMessageRowCache];
  [self renderMessages];
  [self updateControlStates];
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    if (presentation == self.chatPresentation) continue;
    [presentation applyPalette:self.palette];
    [presentation renderMessagesScrollingToBottom:NO];
  }
  [self.notchOverlayController updatePalette:self.palette];
  [self.quickInputController applyPalette:self.palette];
  [self layoutTrafficLightButtons];
  [self updateMessageInputWidthForWindowWidth:NSWidth(self.window.frame)];
  [self updateMessageScrollInsets];
  [self invalidateThemeAppearanceForViewTree:self.window.contentView];
}

- (void)invalidateThemeAppearanceForViewTree:(NSView *)view {
  if (!view) {
    return;
  }

  [view setNeedsDisplay:YES];
  [view setNeedsLayout:YES];
  [view.layer setNeedsDisplay];
  for (NSView *subview in view.subviews) {
    [self invalidateThemeAppearanceForViewTree:subview];
  }
}

- (void)applySidebarTilePalette {
  [self rebuildSidebarAgents];
  [self.agentCreationWindowController applyPalette:self.palette];
  [self.agentFolderAccessWindowController applyPalette:self.palette];
  [self.agentSettingsWindowController applyPalette:self.palette];
  [self.modelSelectionController applyPalette:self.palette];
  [self.bookmarkEditor applyPalette:self.palette];
  self.bookmarkPopover.appearance = self.bookmarkEditor.view.appearance;
  [self styleSidebarActionButtons];
}

- (void)applySidebarInboxPalette {
  self.sidebarInboxStack.spacing = self.palette.space0;
  [self.sidebarInboxStack setCustomSpacing:self.palette.space5 afterView:self.sidebarShortcutsView];
  self.sidebarShortcutsView.palette = self.palette;
  self.sidebarInboxPaneView.palette = self.palette;
  self.notificationsController.palette = self.palette;

  for (NSView *view in self.sidebarInboxPaneView.contentStackView.arrangedSubviews) {
    if ([view isKindOfClass:TLSidebarInboxStackView.class]) {
      ((TLSidebarInboxStackView *)view).palette = self.palette;
    }
  }
}

- (void)applyContentTopLeftCornerRadius:(CGFloat)cornerRadius {
  CGFloat clampedRadius = MIN(self.palette.space5, MAX(self.palette.space0, cornerRadius));
  self.contentShadowView.cornerRadius = self.palette.space5;
  self.contentShadowView.topLeftCornerRadius = clampedRadius;
  self.contentHost.cornerRadius = self.palette.space5;
  self.contentHost.topLeftCornerRadius = clampedRadius;
  [self.contentShadowView setNeedsDisplay:YES];
  [self.contentHost setNeedsDisplay:YES];
  [self.workspaceOutline updateOutline];
}

- (void)applicationPreferencesChanged:(NSNotification *)notification {
  self.notchOverlayController.enabled = TLApplicationPreferences.sharedPreferences.notchEnabled;
  if (!self.quickInputController.window.visible) [self.notchOverlayController startTracking];
}

- (void)openFromNotchOverlay:(id)sender {
  if (!self.quickInputController) {
    self.quickInputController = [[TLQuickInputWindowController alloc] initWithPalette:self.palette];
    self.quickInputController.model = self.settings.selectedModel;
    self.quickInputController.supportingModel = self.settings.supportingModel;
    __weak typeof(self) weakSelf = self;
    self.quickInputController.submissionHandler = ^(NSString *text, NSArray<NSURL *> *files, BOOL allowAutomaticRouting) {
      [weakSelf submitQuickInput:text files:files allowAutomaticRouting:allowAutomaticRouting];
    };
    self.quickInputController.settingsHandler = ^{ [weakSelf showQuickInputModelMenu]; };
    self.quickInputController.visibilityChangeHandler = ^(BOOL visible) {
      if (visible) [weakSelf.notchOverlayController stopTracking];
      else [weakSelf.notchOverlayController startTracking];
    };
  }
  self.quickInputController.commands = [self availableSlashCommands];
  NSScreen *notchScreen = self.notchOverlayController.presentationScreen;
  NSRect notchFrame = self.notchOverlayController.visibleFrame;
  if (notchScreen && !NSIsEmptyRect(notchFrame)) {
    [self.quickInputController presentInNotchOnScreen:notchScreen fromFrame:notchFrame];
    return;
  }
  NSPoint location = NSEvent.mouseLocation;
  NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
  for (NSScreen *candidate in NSScreen.screens) {
    if (NSPointInRect(location, candidate.frame)) { screen = candidate; break; }
  }
  if (self.notchOverlayController.enabled) [self.quickInputController presentInNotchOnScreen:screen];
  else [self.quickInputController presentOnScreen:screen];
}

- (void)handleFileURLsDroppedOnNotch:(NSArray<NSURL *> *)fileURLs {
  if (!fileURLs.count) return;
  [self openFromNotchOverlay:self.notchOverlayController];
  [self.quickInputController.messageInput addAttachmentURLs:fileURLs];
}

- (void)submitQuickInput:(NSString *)text files:(NSArray<NSURL *> *)files allowAutomaticRouting:(BOOL)allowAutomaticRouting {
  // Routing happens only after submission, without disturbing the current chat's draft.
  NSURL *URL = allowAutomaticRouting && !files.count ? [self browserURLFromPromptString:text] : nil;
  [self showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
  if (URL) {
    [self openBrowserTabWithURL:URL];
  } else {
    [self startNewChatWithModel:self.quickInputController.model focus:NO];
    self.activeChat.supportingModel = self.quickInputController.supportingModel;
    self.promptTextView.string = text;
    [self.messageInput setAttachmentURLs:files animated:NO];
    [self updateControlStates];
    [self.window makeFirstResponder:self.promptTextView];
    [self sendMessage:self allowAutomaticRouting:NO];
  }
}

- (void)showQuickInputModelMenu {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Chat models"];
  for (NSNumber *smallChoice in @[@NO, @YES]) {
    BOOL small = smallChoice.boolValue;
    NSString *model = small ? self.quickInputController.supportingModel : self.quickInputController.model;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@: %@", small ? @"Small model" : @"Large model", model]
      action:@selector(chooseQuickInputModel:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = smallChoice;
    [menu addItem:item];
  }
  NSView *button = self.quickInputController.messageInput.settingsButton;
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(button.bounds)) inView:button];
}

- (void)chooseQuickInputModel:(NSMenuItem *)sender {
  TLQuickInputWindowController *quickInput = self.quickInputController;
  if (quickInput.window.attachedSheet) return;
  BOOL small = [sender.representedObject boolValue];
  TLModelSelectionWindowController *controller = [[TLModelSelectionWindowController alloc]
    initWithSmallModel:small selectedModel:small ? quickInput.supportingModel : quickInput.model
    token:self.settings.openRouterToken orchestrator:self.agentOrchestrator palette:self.palette];
  self.modelSelectionController = controller;
  controller.selectionHandler = ^(NSString *model, void (^completion)(NSError *)) {
    if (small) quickInput.supportingModel = model;
    else quickInput.model = model;
    completion(nil);
  };
  [controller presentForWindow:quickInput.window];
}

- (void)styleButton:(NSButton *)button background:(NSColor *)background foreground:(NSColor *)foreground {
  button.font = self.palette.labelFont;
  button.contentTintColor = foreground;
  button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
    NSForegroundColorAttributeName: foreground,
    NSFontAttributeName: self.palette.labelFont,
  }];
  button.layer.backgroundColor = TLCGColor(background);
  button.layer.cornerRadius = self.palette.radiusMedium;
}

- (void)updateControlStates { [self updateControlStatesForChat:[self currentChatPresentation]]; }
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {
  TLWorkspaceTab *bookmarkTab = [self activeWorkspaceTab];
  self.sidebarShortcutsView.addButton.enabled = !self.widgetbookMode && bookmarkTab &&
    (bookmarkTab.kind == TLWorkspaceTabKindChat ||
      (bookmarkTab.kind == TLWorkspaceTabKindBrowser && [TLBookmark normalizedURL:bookmarkTab.URL.absoluteString]));
  [self updatePromptQueueForChat:chatContext];
  [chatContext.messageInput recalculateHeight];
  [chatContext updateMessageScrollInsets];

  if (self.widgetbookMode) {
    self.createChatButton.enabled = NO;
    self.sidebarToggleButton.enabled = NO;
    self.sidebarAutomationsButton.enabled = NO;
    self.sidebarUserButton.enabled = NO;
    chatContext.sendButton.enabled = NO;
    chatContext.messageInput.attachmentsEditable = NO;
    self.historyPanelController.enabled = NO;
    chatContext.promptTextView.editable = NO;
    chatContext.promptTextView.selectable = YES;
    self.createChatButton.alphaValue = self.palette.disabledOpacity;
    self.sidebarToggleButton.alphaValue = self.palette.disabledOpacity;
    chatContext.sendButton.alphaValue = self.palette.disabledOpacity;
    [self styleSidebarActionButtons];
    [self.workspaceTabsController setControlsEnabled:NO disabledOpacity:self.palette.disabledOpacity];
    [self updateAgentControlStates];
    return;
  }

  NSString *prompt = [chatContext.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  BOOL chatActive = [self isChatPresentationVisibleForChat:chatContext];
  if (!chatActive || prompt.length == 0 || [self preparingAttachmentsForChat:chatContext] || chatContext.editingQueuedPrompt || chatContext.messageInput.attachmentURLs.count) {
    [self hideSlashCommandListForChat:chatContext];
  }
  self.createChatButton.enabled = YES;
  self.sidebarToggleButton.enabled = YES;
  self.sidebarAutomationsButton.enabled = YES;
  self.sidebarUserButton.enabled = YES;
  chatContext.messageInput.placeholderText = chatContext.editingQueuedPrompt ? @"Edit queued prompt" :
    ([self isSendingForChat:chatContext] || chatContext.queuedPrompts.count) ? @"Queue a follow-up" : @"Give a task or enter a URL";
  chatContext.messageInput.showsStopButton = !chatContext.editingQueuedPrompt && [self canStopResponseForChat:chatContext];
  BOOL hasAttachments = chatContext.messageInput.attachmentURLs.count > 0;
  chatContext.sendButton.enabled = ![self preparingAttachmentsForChat:chatContext] && (chatContext.messageInput.showsStopButton ||
    (chatActive && (prompt.length > 0 || hasAttachments)));
  if (!chatContext.messageInput.showsStopButton) {
    BOOL editing = chatContext.editingQueuedPrompt != nil;
    BOOL queuing = [self isSendingForChat:chatContext] || chatContext.queuedPrompts.count > 0;
    NSString *label = editing ? @"Save queued prompt" : queuing ? @"Queue follow-up" : @"Send";
    [chatContext.messageInput.sendButton setImage:[NSImage imageWithSystemSymbolName:editing ? @"checkmark" : queuing ? @"text.badge.plus" : @"arrow.up" accessibilityDescription:label] animated:NO];
    chatContext.sendButton.toolTip = label;
  }
  chatContext.messageInput.attachmentsEditable = ![self preparingAttachmentsForChat:chatContext] && chatActive;
  if ([self preparingAttachmentsForChat:chatContext]) chatContext.sendButton.toolTip = @"Copying attachments…";
  self.historyPanelController.enabled = YES;
  chatContext.promptTextView.editable = chatActive && ![self preparingAttachmentsForChat:chatContext];
  chatContext.promptTextView.selectable = YES;

  self.createChatButton.alphaValue = self.createChatButton.enabled ? 1.0 : self.palette.disabledOpacity;
  self.sidebarToggleButton.alphaValue = self.sidebarToggleButton.enabled ? 1.0 : self.palette.disabledOpacity;
  chatContext.sendButton.alphaValue = chatContext.sendButton.enabled ? 1.0 : self.palette.disabledOpacity;
  [self styleSidebarActionButtons];
  [self.workspaceTabsController setControlsEnabled:YES disabledOpacity:self.palette.disabledOpacity];
  [self updateAgentControlStates];
}

- (void)startNotifications {
  if (self.incognito) return;
  if (self.widgetbookMode || self.notificationsTimer) return;
  __weak typeof(self) weakSelf = self;
  self.notificationsTimer = [NSTimer timerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
    [weakSelf refreshNotifications];
  }];
  [[NSRunLoop mainRunLoop] addTimer:self.notificationsTimer forMode:NSRunLoopCommonModes];
  [self refreshNotifications];
}

- (void)notificationsDidActivate:(NSNotification *)notification {
  [self refreshNotifications];
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    if (presentation.notificationDidReveal) [self revealNotificationInPresentation:presentation];
  }
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
  [self notificationsDidActivate:notification];
}

- (void)refreshNotifications {
  if (self.incognito) return;
  if (self.widgetbookMode || !self.notificationsController || !self.agentOrchestrator) return;
  NSInteger agentID = self.database.currentAgentID;
  if (self.notificationsAgentID != agentID) {
    self.notificationsAgentID = agentID;
    self.notificationsSyncGeneration++;
    self.notificationsNavigationGeneration++;
    self.notificationsSyncInFlight = NO;
    self.notificationsNextSync = nil;
    self.notificationsFailureCount = 0;
    for (TLChatTabController *presentation in self.chatPresentations.allValues) {
      presentation.notificationTargetMessageID = nil;
      presentation.notificationTargetToolCallID = nil;
      presentation.notificationDidReveal = nil;
    }
    self.notificationsController.notifications = agentID > 0 ? [self.database notificationsForAgentID:agentID error:nil] ?: @[] : @[];
    self.notificationsController.errorMessage = nil;
  }
  if (agentID <= 0) { self.notificationsController.loading = NO; return; }
  if (self.notificationsSyncInFlight || [self.notificationsNextSync timeIntervalSinceNow] > 0) return;
  TLAgentRecord *agent = [self.database agentWithID:agentID error:nil];
  if (!agent || ![self.agentOrchestrator isVMRunningForAgent:agent]) {
    self.notificationsController.loading = NO;
    self.notificationsController.errorMessage = @"Agent offline. Saved notifications remain available.";
    return;
  }
  NSError *cacheError = nil;
  NSDictionary *state = [self.database notificationSyncStateForAgentID:agentID error:&cacheError];
  if (!state) { self.notificationsController.errorMessage = cacheError.localizedDescription; return; }
  NSMutableDictionary *params = [state mutableCopy];
  params[@"action"] = @"sync";
  params[@"limit"] = @200;
  self.notificationsSyncInFlight = YES;
  self.notificationsController.loading = self.notificationsController.notifications.count == 0;
  NSUInteger generation = ++self.notificationsSyncGeneration;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesNotificationsWithParameters:params agentID:agentID
    token:self.settings.openRouterToken model:self.settings.selectedModel completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || generation != owner.notificationsSyncGeneration || agentID != owner.database.currentAgentID) return;
    owner.notificationsSyncInFlight = NO;
    owner.notificationsController.loading = NO;
    NSError *failure = error;
    if (!failure && ![owner.database applyNotificationSyncResult:result agentID:agentID error:&failure]) {
      if (!failure) failure = [NSError errorWithDomain:@"Talaria.Notifications" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Could not cache notifications."}];
    }
    if (failure) {
      owner.notificationsFailureCount = MIN(4, owner.notificationsFailureCount + 1);
      owner.notificationsNextSync = [NSDate dateWithTimeIntervalSinceNow:MIN(60, 5 * (1 << owner.notificationsFailureCount))];
      owner.notificationsController.errorMessage = failure.localizedDescription;
      return;
    }
    owner.notificationsFailureCount = 0;
    owner.notificationsController.errorMessage = nil;
    owner.notificationsController.notifications = [owner.database notificationsForAgentID:agentID error:nil] ?: @[];
    owner.notificationsNextSync = [NSDate dateWithTimeIntervalSinceNow:[result[@"has_more"] boolValue] ? 0 : 5];
    if ([result[@"has_more"] boolValue]) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshNotifications]; });
  }];
}

- (void)setNotification:(NSDictionary *)notification read:(BOOL)read agentID:(NSInteger)agentID {
  if (agentID <= 0 || !notification[@"id"] || !notification[@"version"]) return;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesNotificationsWithParameters:@{@"action": @"set_read", @"id": notification[@"id"],
      @"version": notification[@"version"], @"read": @(read)} agentID:agentID
    token:self.settings.openRouterToken model:self.settings.selectedModel completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner) return;
    NSError *failure = error;
    NSDictionary *updated = [result[@"notification"] isKindOfClass:NSDictionary.class] ? result[@"notification"] : nil;
    if (!failure && updated) [owner.database cacheNotification:updated agentID:agentID error:&failure];
    if (agentID != owner.database.currentAgentID) return;
    if (failure || !updated) {
      owner.notificationsController.errorMessage = failure.localizedDescription ?: @"Could not update notification read state.";
      return;
    }
    owner.notificationsController.notifications = [owner.database notificationsForAgentID:agentID error:nil] ?: @[];
  }];
}

- (BOOL)message:(TLChatMessage *)message matchesNotification:(NSDictionary *)notification {
  NSString *messageID = [notification[@"message_id"] description];
  NSString *callID = notification[@"tool_call_id"];
  if (!messageID.length || !callID.length || ![message.sourceMessageID isEqual:messageID]) return NO;
  NSString *cardCallID = message.notification[@"tool_call_id"];
  return cardCallID.length ? [cardCallID isEqual:callID] : [message.sourceToolCallIDs containsObject:callID];
}

- (BOOL)insertNotificationSource:(NSDictionary *)notification transcript:(NSArray<NSDictionary *> *)transcript
                   presentation:(TLChatTabController *)presentation {
  // Ordinary Hermes history omits tool-only calls. Restore that exact source
  // row by durable neighboring IDs while retaining the live turn's objects.
  NSUInteger sourceIndex = [transcript indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger index, BOOL *stop) {
    return [[row[@"source_message_id"] description] isEqual:[notification[@"message_id"] description]] &&
      [row[@"notification"][@"tool_call_id"] isEqual:notification[@"tool_call_id"]];
  }];
  if (sourceIndex == NSNotFound) return NO;
  TLAssistantTurnRunner *runner = self.turnRunners[@(presentation.chat.chatID)];
  NSUInteger boundary = [presentation.messages indexOfObjectIdenticalTo:runner.activeUserMessage];
  if (boundary == NSNotFound) boundary = presentation.messages.count;
  NSUInteger insertion = boundary;
  BOOL located = NO;
  for (NSUInteger index = sourceIndex + 1; index < transcript.count && !located; index++) {
    NSString *nextID = [transcript[index][@"source_message_id"] description];
    for (NSUInteger local = 0; local < boundary; local++) {
      if (nextID.length && [presentation.messages[local].sourceMessageID isEqual:nextID]) {
        insertion = local; located = YES; break;
      }
    }
  }
  for (NSInteger index = (NSInteger)sourceIndex - 1; index >= 0 && !located; index--) {
    NSString *previousID = [transcript[index][@"source_message_id"] description];
    for (NSUInteger local = 0; local < boundary; local++) {
      if (previousID.length && [presentation.messages[local].sourceMessageID isEqual:previousID]) {
        insertion = local + 1; located = YES; break;
      }
    }
  }
  NSDictionary *row = transcript[sourceIndex];
  TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleAssistant content:row[@"content"] ?: @"" thinking:row[@"thinking"]];
  message.sourceMessageID = [row[@"source_message_id"] description];
  message.sourceToolCallIDs = row[@"source_tool_call_ids"] ?: @[];
  message.notification = row[@"notification"];
  [presentation.messages insertObject:message atIndex:insertion];
  return YES;
}

- (void)openNotification:(NSDictionary *)notification {
  NSInteger agentID = self.notificationsAgentID;
  if (agentID <= 0 || agentID != self.database.currentAgentID || !notification[@"id"] || !notification[@"version"]) return;
  NSUInteger generation = ++self.notificationsNavigationGeneration;
  for (TLChatTabController *presentation in self.chatPresentations.allValues) {
    presentation.notificationTargetMessageID = nil;
    presentation.notificationTargetToolCallID = nil;
    presentation.notificationDidReveal = nil;
  }
  self.notificationsController.errorMessage = nil;
  TLChatRecord *requestedChat = [self.database chatWithHermesSessionID:notification[@"session_id"] agentID:agentID error:nil];
  NSNumber *requestedChatID = requestedChat ? @(requestedChat.chatID) : nil;
  BOOL requestedWithLiveHistory = requestedChatID && (self.turnRunners[requestedChatID] ||
    self.turnMessagesByChat[requestedChatID] || [self.preparingAttachmentChats containsObject:requestedChatID]);
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesNotificationsWithParameters:@{@"action": @"open_source", @"id": notification[@"id"],
      @"version": notification[@"version"]} agentID:agentID token:self.settings.openRouterToken
    model:self.settings.selectedModel completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || generation != owner.notificationsNavigationGeneration || agentID != owner.database.currentAgentID) return;
    NSArray *messages = [result[@"messages"] isKindOfClass:NSArray.class] ? result[@"messages"] : nil;
    NSDictionary *session = [result[@"session"] isKindOfClass:NSDictionary.class] ? result[@"session"] : nil;
    NSDictionary *source = [result[@"notification"] isKindOfClass:NSDictionary.class] ? result[@"notification"] : nil;
    if (error || !messages || !session || ![source[@"id"] isEqual:notification[@"id"]] ||
        ![source[@"version"] isEqual:notification[@"version"]] || ![source[@"session_id"] isEqual:result[@"source_session_id"]]) {
      owner.notificationsController.errorMessage = error.localizedDescription ?: @"The notification's source is unavailable.";
      return;
    }
    NSMutableDictionary *metadata = [session mutableCopy];
    metadata[@"id"] = result[@"source_session_id"];
    metadata[@"source_session_id"] = result[@"source_session_id"];
    metadata[@"continuation_session_id"] = result[@"continuation_session_id"] ?: result[@"source_session_id"];
    if ([result[@"model"] isKindOfClass:NSString.class] && [result[@"model"] length]) metadata[@"model"] = result[@"model"];
    TLChatRecord *existing = [owner.database chatWithHermesSessionID:metadata[@"id"] agentID:agentID error:nil];
    TLChatTabController *presentation = existing ? owner.chatPresentations[@(existing.chatID)] : nil;
    NSNumber *existingChatID = existing ? @(existing.chatID) : nil;
    BOOL preserveHistory = existingChatID && (owner.turnRunners[existingChatID] ||
      owner.turnMessagesByChat[existingChatID] || [owner.preparingAttachmentChats containsObject:existingChatID]);
    BOOL localHistoryChanged = existing && (!requestedChat || existing.messages.count != requestedChat.messages.count ||
      existing.messages.lastObject.messageID != requestedChat.messages.lastObject.messageID);
    if (!preserveHistory && (requestedWithLiveHistory || localHistoryChanged)) {
      // The runtime snapshot may predate a reply that finished during this
      // request. Fetch again after completion before replacing local history.
      [owner openNotification:notification];
      return;
    }
    // Keep arrays owned by streaming, paused approvals, or attachment preparation.
    TLChatRecord *chat = [owner.database cacheHermesSession:metadata messages:preserveHistory ? nil : messages agentID:agentID error:&error];
    if (!chat) { owner.notificationsController.errorMessage = error.localizedDescription; return; }
    NSArray *displayMessages = preserveHistory ? presentation.messages : chat.messages;
    BOOL found = NO;
    for (TLChatMessage *message in displayMessages) {
      if ([owner message:message matchesNotification:source]) {
        if (!message.notification) message.notification = source;
        found = YES; break;
      }
    }
    if (!found && preserveHistory) found = [owner insertNotificationSource:source transcript:messages presentation:presentation];
    if (!found) {
      owner.notificationsController.errorMessage = @"The original notification message is unavailable. Try reopening after this turn finishes.";
      return;
    }
    if (presentation && !preserveHistory) {
      presentation.chat = chat;
      presentation.messages = [[NSArray alloc] initWithArray:chat.messages copyItems:YES].mutableCopy;
    }
    [owner addChatToSessionIfNeeded:chat.chatID activate:YES];
    owner.openingNotificationSource = YES;
    @try { [owner loadChatWithID:chat.chatID]; } @finally { owner.openingNotificationSource = NO; }
    presentation = owner.chatPresentations[@(chat.chatID)];
    presentation.notificationTargetMessageID = [source[@"message_id"] description];
    presentation.notificationTargetToolCallID = source[@"tool_call_id"];
    presentation.notificationNavigationGeneration = generation;
    presentation.suppressAutomaticScroll = YES;
    presentation.notificationDidReveal = ^{
      TalariaWindowController *current = weakSelf;
      if (current && generation == current.notificationsNavigationGeneration && agentID == current.database.currentAgentID) {
        [current setNotification:source read:YES agentID:agentID];
      }
    };
    [owner renderMessagesScrollingToBottom:NO];
  }];
}

- (BOOL)revealNotificationInPresentation:(TLChatTabController *)presentation {
  if (!presentation.notificationTargetMessageID.length || !presentation.notificationTargetToolCallID.length) return NO;
  if (presentation.notificationNavigationGeneration != self.notificationsNavigationGeneration) return NO;
  NSDictionary *target = @{@"message_id": presentation.notificationTargetMessageID, @"tool_call_id": presentation.notificationTargetToolCallID};
  for (TLChatMessage *message in presentation.messages) {
    if (![self message:message matchesNotification:target]) continue;
    NSView *row = [presentation.messageRowViews objectForKey:message];
    if (!row || !row.window.isVisible || row.window.isMiniaturized || row.isHiddenOrHasHiddenAncestor ||
        presentation.chatWorkspace.isHiddenOrHasHiddenAncestor) return NO;
    [presentation.messageDocumentView layoutSubtreeIfNeeded];
    [row scrollRectToVisible:row.bounds];
    NSRect location = [row convertRect:row.bounds toView:presentation.messageDocumentView];
    if (!NSIntersectsRect(location, presentation.messageScrollView.documentVisibleRect)) return NO;
    if (presentation.notificationDidReveal) {
      void (^revealed)(void) = presentation.notificationDidReveal;
      presentation.notificationDidReveal = nil;
      row.wantsLayer = YES;
      row.layer.borderColor = self.palette.sidebarInboxPrimaryBadgeSurface.CGColor;
      row.layer.borderWidth = self.palette.borderWidth;
      row.layer.cornerRadius = self.palette.radiusMedium;
      __weak NSView *weakRow = row;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakRow.layer.borderWidth = 0;
      });
      revealed();
    }
    return YES;
  }
  return NO;
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectChatID:(NSInteger)chatID {
  if (self.widgetbookMode) {
    [self selectActiveChatInHistory];
    return;
  }
  if (![self isHistoryScreenActive]) {
    return;
  }

  if (self.historyPanelController.loading) return;
  if (self.turnRunners[@(chatID)] || [self.preparingAttachmentChats containsObject:@(chatID)]) {
    [self loadChatWithID:chatID];
    return;
  }
  NSDictionary *session = self.hermesHistorySessions[@(chatID)];
  if (!session) return;
  NSInteger agentID = self.database.currentAgentID;
  NSUInteger generation = ++self.historyRequestGeneration;
  self.historyPanelController.loading = YES;
  self.historyPanelController.statusMessage = @"Opening Hermes session…";
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesHistoryWithAction:@"open" sessionID:session[@"id"]
                                          token:self.settings.openRouterToken model:self.settings.selectedModel
                                     completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || generation != owner.historyRequestGeneration) return;
    owner.historyPanelController.loading = NO;
    owner.historyPanelController.statusMessage = @"";
    if (agentID != owner.database.currentAgentID) { [owner refreshHermesHistory]; return; }
    NSArray *messages = [result[@"messages"] isKindOfClass:NSArray.class] ? result[@"messages"] : nil;
    if (error || !messages) {
      owner.historyPanelController.statusMessage = error.localizedDescription ?: @"Hermes returned an invalid transcript.";
      return;
    }
    if (owner.turnRunners[@(chatID)] || [owner.preparingAttachmentChats containsObject:@(chatID)]) return;
    NSMutableDictionary *metadata = [session mutableCopy];
    if ([result[@"model"] isKindOfClass:NSString.class]) metadata[@"model"] = result[@"model"];
    TLChatRecord *chat = [owner.database cacheHermesSession:metadata messages:messages agentID:agentID error:&error];
    if (!chat) { owner.historyPanelController.statusMessage = error.localizedDescription; return; }
    owner.chats = [[owner.database listChats:nil] mutableCopy];
    TLChatTabController *presentation = owner.chatPresentations[@(chat.chatID)];
    if (presentation) {
      presentation.chat = chat;
      presentation.messages = [[NSArray alloc] initWithArray:chat.messages copyItems:YES].mutableCopy;
    }
    if ([owner isHistoryScreenActive]) [owner loadChatWithID:chat.chatID];
  }];
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteChatID:(NSInteger)chatID {
  if (self.turnRunners[@(chatID)] || self.widgetbookMode || chatID <= 0) {
    return;
  }

  TLChatSummary *summary = [self summaryForChatID:chatID];
  NSString *title = summary.title.length > 0 ? summary.title : @"this conversation";
  NSAlert *alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleWarning;
  alert.messageText = @"Delete Conversation?";
  alert.informativeText = [NSString stringWithFormat:@"This will permanently delete \"%@\" and its messages.", title];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];

  __weak typeof(self) weakSelf = self;
  [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response != NSAlertFirstButtonReturn) {
      return;
    }

    [weakSelf deleteHermesHistoryChatWithID:chatID];
  }];
}

- (void)deleteHermesHistoryChatWithID:(NSInteger)chatID {
  if (self.turnRunners[@(chatID)] || [self.preparingAttachmentChats containsObject:@(chatID)] || self.historyPanelController.loading) return;
  NSDictionary *session = self.hermesHistorySessions[@(chatID)];
  if (!session || self.historyAgentID != self.database.currentAgentID) return;
  NSInteger agentID = self.database.currentAgentID;
  NSUInteger generation = ++self.historyRequestGeneration;
  self.historyPanelController.loading = YES;
  self.historyPanelController.statusMessage = @"Deleting Hermes session…";
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesHistoryWithAction:@"delete" sessionID:session[@"id"]
                                          token:self.settings.openRouterToken model:self.settings.selectedModel
                                     completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || generation != owner.historyRequestGeneration) return;
    owner.historyPanelController.loading = NO;
    owner.historyPanelController.statusMessage = @"";
    if (agentID != owner.database.currentAgentID) { [owner refreshHermesHistory]; return; }
    if (error || ![result[@"deleted"] isEqual:session[@"id"]]) {
      owner.historyPanelController.statusMessage = error.localizedDescription ?: @"Hermes did not confirm deletion.";
      return;
    }
    [owner deleteChatWithID:chatID];
    [owner refreshHermesHistory];
  }];
}

- (void)deleteChatWithID:(NSInteger)chatID {
  if (self.turnRunners[@(chatID)] || self.widgetbookMode || chatID <= 0) {
    return;
  }

  BOOL deletingLoadedChat = self.activeChat && self.activeChat.chatID == chatID;
  NSUInteger closedIndex = [self indexOfSessionChatID:chatID];

  NSError *error = nil;
  TLChatRecord *deletedChat = [self.database chatWithID:chatID error:&error];
  if (!deletedChat) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not load conversation."];
    return;
  }
  if (![self.database deleteChatWithID:chatID error:&error]) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not delete conversation."];
    return;
  }

  [self.chatPresentations[@(chatID)].queuedPrompts removeAllObjects];
  [self.turnMessagesByChat removeObjectForKey:@(chatID)];
  NSError *attachmentCleanupError = nil;
  [self.agentOrchestrator removeAttachmentsForSessionID:deletedChat.hermesSessionID error:&attachmentCleanupError];
  if (attachmentCleanupError) [self presentErrorMessage:attachmentCleanupError.localizedDescription];
  [self.chatIconRequests removeObject:@(chatID)];
  [self.attachmentDrafts removeObjectForKey:@(chatID)];
  [self.attachmentPromptDrafts removeObjectForKey:@(chatID)];
  if (closedIndex != NSNotFound) {
    [self.appStateManager removeWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
    [self removeRuntimeForKind:TLWorkspaceTabKindChat tabID:chatID];
  }

  [self reloadBookmarks];
  NSArray<TLChatSummary *> *nextChats = [self.database listChats:&error];
  if (!nextChats) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not refresh conversations."];
    nextChats = @[];
  }
  self.chats = [nextChats mutableCopy];

  if (deletingLoadedChat) {
    self.activeChat = nil;
    self.messages = [NSMutableArray array];
    [self resetMessageRowCache];
    self.promptTextView.string = @"";
    self.errorMessage = @"";
  }

  if ([self workspaceTabs].count == 0) {
    [self ensureHistoryTab];
    [self activateTabKind:TLWorkspaceTabKindHistory tabID:self.historyTab.tabID];
  }

  [self reloadHistoryPanel];
  [self selectActiveChatInHistory];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  if (deletingLoadedChat) {
    [self renderMessages];
  }
  [self updateControlStates];
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectBrowserURL:(NSURL *)URL {
  [self openBrowserTabWithURL:URL];
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteBrowserVisitID:(NSInteger)visitID {
  NSError *error = nil;
  if (![self.database deleteBrowserVisitWithID:visitID error:&error]) { [NSApp presentError:error]; return; }
  [self reloadHistoryPanel];
}

- (void)historyPanelControllerDidRequestRefresh:(TLHistoryPanelController *)controller {
  [self refreshHermesHistory];
}

- (void)refreshHermesHistory {
  if (self.widgetbookMode) { [self reloadHistoryPanel]; return; }
  NSInteger agentID = self.database.currentAgentID;
  if (self.historyPanelController.loading && self.historyAgentID == agentID) return;
  NSUInteger generation = ++self.historyRequestGeneration;
  self.historyAgentID = agentID;
  self.hermesHistoryChats = @[];
  self.hermesHistorySessions = @{};
  self.historyPanelController.searchPreviews = @{};
  self.historyPanelController.statusMessage = @"";
  [self reloadHistoryPanel];
  if (agentID <= 0) {
    self.historyPanelController.loading = NO;
    self.historyPanelController.statusMessage = @"Select an agent to view its Hermes history.";
    return;
  }
  self.historyPanelController.loading = YES;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesHistoryWithAction:@"list" sessionID:@""
                                          token:self.settings.openRouterToken model:self.settings.selectedModel
                                     completion:^(NSDictionary *result, NSError *error) {
    TalariaWindowController *owner = weakSelf;
    if (!owner || generation != owner.historyRequestGeneration) return;
    owner.historyPanelController.loading = NO;
    if (agentID != owner.database.currentAgentID) { [owner refreshHermesHistory]; return; }
    NSArray *sessions = [result[@"sessions"] isKindOfClass:NSArray.class] ? result[@"sessions"] : nil;
    if (error || !sessions) {
      owner.historyPanelController.statusMessage = error.localizedDescription ?: @"Hermes returned an invalid session list.";
      return;
    }
    for (id session in sessions) {
      if (![session isKindOfClass:NSDictionary.class] || ![session[@"id"] isKindOfClass:NSString.class]) {
        owner.historyPanelController.statusMessage = @"Hermes returned an invalid session.";
        return;
      }
    }
    owner.historyPanelController.loading = YES;
    [owner.historyRepository cacheSessions:sessions agentID:agentID completion:^(NSArray *chats, NSArray *allChats, NSError *cacheError) {
      TalariaWindowController *current = weakSelf;
      if (!current || generation != current.historyRequestGeneration) return;
      current.historyPanelController.loading = NO;
      if (agentID != current.database.currentAgentID) { [current refreshHermesHistory]; return; }
      if (!chats) { current.historyPanelController.statusMessage = cacheError.localizedDescription; return; }
      NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
      NSMutableDictionary *previews = [NSMutableDictionary dictionary];
      [chats enumerateObjectsUsingBlock:^(TLChatSummary *chat, NSUInteger index, BOOL *stop) {
        NSDictionary *session = sessions[index];
        metadata[@(chat.chatID)] = session;
        previews[@(chat.chatID)] = [session[@"preview"] isKindOfClass:NSString.class] ? session[@"preview"] : @"";
      }];
      current.hermesHistoryChats = chats;
      current.hermesHistorySessions = metadata;
      current.historyPanelController.searchPreviews = previews;
      current.chats = [allChats mutableCopy];
      [current reloadHistoryPanel];
      [current reloadWorkspaceTabs];
    }];
  }];
}

- (void)reloadHistoryPanel {
  if (!self.historyPanelController) return;
  if (!self.widgetbookMode && !self.historyRepository) {
    self.historyRepository = [[TLHistoryRepository alloc] initWithDatabase:self.database];
    self.historyPanelController.repository = self.historyRepository;
  }
  self.historyPanelController.chats = self.widgetbookMode ? (self.chats ?: @[]) : (self.hermesHistoryChats ?: @[]);
  [self.historyPanelController reloadData];
}

- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray<TLChatMessage *> *)messages {
  if (self.widgetbookMode || chatID <= 0) {
    return;
  }

  TLChatSummary *summary = [self summaryForChatID:chatID];
  if (summary.icon.length > 0) {
    return;
  }

  NSNumber *requestKey = @(chatID);
  if ([self.chatIconRequests containsObject:requestKey]) {
    return;
  }

  NSString *firstUserMessage = [self firstUserMessageFromMessages:messages];
  if (firstUserMessage.length == 0) {
    return;
  }

  NSString *token = [self.settings.openRouterToken stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *model = [(summary.supportingModel ?: self.settings.supportingModel) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (model.length == 0) {
    return;
  }

  [self.chatIconRequests addObject:requestKey];
  NSString *title = summary.title.length > 0 ? summary.title : @"New chat";
  __weak typeof(self) weakSelf = self;
  [self.chatIconGenerator generateIconForTitle:title
                              firstUserMessage:firstUserMessage
                                         token:token
                                         model:model
                                    completion:^(NSString *icon, NSError *error) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    [strongSelf.chatIconRequests removeObject:requestKey];
    if (error) {
      [strongSelf presentErrorMessage:[NSString stringWithFormat:@"Could not generate the chat icon: %@", error.localizedDescription]];
      return;
    }
    if (icon.length == 0) {
      return;
    }

    NSError *saveError = nil;
    TLChatSummary *savedSummary = [strongSelf.database saveChatIcon:icon chatID:chatID error:&saveError];
    if (!savedSummary) {
      return;
    }

    [strongSelf applySavedChatSummary:savedSummary];
  }];
}

- (NSString *)firstUserMessageFromMessages:(NSArray<TLChatMessage *> *)messages {
  for (TLChatMessage *message in messages) {
    if ([message.role isEqualToString:TLRoleUser] && message.content.length > 0) {
      return message.content;
    }
  }

  return @"";
}

- (void)synchronizeChatTabTitles {
  for (TLWorkspaceTab *tab in [self workspaceTabsOfKind:TLWorkspaceTabKindChat]) {
    TLChatSummary *summary = [self summaryForChatID:tab.tabID];
    if (!summary.title.length || ([tab.title isEqual:summary.title] && [tab.toolTip isEqual:summary.title])) continue;
    TLWorkspaceTab *updatedTab = [tab copy];
    updatedTab.title = summary.title;
    updatedTab.toolTip = summary.title;
    [self.appStateManager upsertWorkspaceTab:updatedTab activate:NO];
  }
}

- (void)applySavedChatSummary:(TLChatSummary *)savedSummary {
  if (!savedSummary) {
    return;
  }

  if (!self.chats) self.chats = [NSMutableArray array];
  BOOL found = NO;
  for (NSUInteger index = 0; index < self.chats.count; index += 1) {
    if (self.chats[index].chatID == savedSummary.chatID) {
      self.chats[index] = [savedSummary copy];
      found = YES;
      break;
    }
  }

  if (!found) [self.chats addObject:[savedSummary copy]];

  if (self.activeChat.chatID == savedSummary.chatID) {
    self.activeChat.title = savedSummary.title;
    self.activeChat.icon = savedSummary.icon;
    self.activeChat.updatedAt = savedSummary.updatedAt;
  }

  [self synchronizeChatTabTitles];
  [self reloadHistoryPanel];
  [self selectActiveChatInHistory];
  [self reloadWorkspaceTabs];
}

- (void)selectActiveChatInHistory {
  if (!self.activeChat || !self.historyPanelController) {
    return;
  }

  if (![self isChatWorkspaceActive]) {
    [self.historyPanelController deselectAll];
    return;
  }

  if ([self isHistoryScreenActive]) {
    [self.historyPanelController deselectAll];
    return;
  }

  [self.historyPanelController selectChatWithID:self.activeChat.chatID];
}

- (void)presentErrorMessage:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Talaria";
  alert.informativeText = message;
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end
