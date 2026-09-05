#import "TalariaWindowController.h"
#import "AgentOrchestrator.h"
#import "AppStateManager.h"
#import "AssistantTurnRunner.h"
#import "ChatIconGenerator.h"
#import "MarkdownRenderer.h"
#import "NotchOverlayController.h"
#import "InputSuggestions.h"
#import "Theme.h"
#import "TLHistoryPanelController.h"
#import "TLBrowserTabController.h"
#import "TLSettingsTabController.h"
#import "TLMainWindow.h"
#import "TLOnboardingDemoWindowController.h"
#import "TLHermesOnboardingWindowController.h"
#import "TLVMDebugTerminalWindowController.h"
#import "TLWorkspaceTabsController.h"
#import "UIComponents.h"
#import "design_system/TLWorkspaceOutlineView.h"
#import "design_system/TLTransitionCoordinator.h"
#import "design_system/TLChromeTabView.h"
#import "WorkspaceState.h"
#import "WorkspaceTabRuntime.h"
#import "Widgetbook.h"
#import "design_system/TLButton.h"
#import "design_system/TLASCIIPlanetScreensaverView.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLMessageInput.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static void *TLEffectiveAppearanceObservationContext = &TLEffectiveAppearanceObservationContext;

static const CGFloat TLUserMessageBaseHorizontalInsetScale = 1.3;
static const CGFloat TLUserMessageMultilineHorizontalInsetScale = 1.6;
static const CGFloat TLUserMessageMultilineVerticalInsetScale = 1.3;
static const NSUInteger TLUserMessageShortTailCharacterLimit = 5;
static NSString *const TLAWSOutageChatTitle = @"AWS Oregon Outage";
static NSString *const TLAWSOutageAgentMessage = @"\u26A0\uFE0F AWS is reporting an outage in the Oregon region. Talaria traffic routed through US West is seeing elevated errors and intermittent request failures. Failover capacity is available in US Central.";
static NSString *const TLAWSOutageIntent = @"Route Talaria traffic to the US-central region";
static const CGFloat TLMainWindowOnboardingRevealDuration = 0.3;
static const CGFloat TLMainWindowOnboardingRevealInitialScale = 0.001;

static NSRect TLUserMessageTextBounds(NSString *text, NSFont *font, CGFloat maxWidth) {
  NSString *measuredText = text.length > 0 ? text : @" ";
  CGFloat availableWidth = MAX(1.0, maxWidth);
  NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName: font};
  return [measuredText boundingRectWithSize:NSMakeSize(availableWidth, CGFLOAT_MAX)
                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                 attributes:attributes];
}

static NSInteger TLUserMessageLineCount(NSString *text, NSFont *font, CGFloat maxWidth) {
  NSRect boundingRect = TLUserMessageTextBounds(text, font, maxWidth);
  CGFloat lineHeight = MAX(1.0, ceil(font.ascender - font.descender + font.leading));
  return MAX(1, (NSInteger)ceil(NSHeight(boundingRect) / lineHeight));
}

typedef struct {
  CGFloat leadingInset;
  CGFloat trailingInset;
  CGFloat topInset;
  CGFloat bottomInset;
  CGFloat textMaxWidth;
  BOOL rendersAsPill;
  CGFloat tailHorizontalOffset;
} TLUserMessageBubbleLayout;

static TLUserMessageBubbleLayout TLUserMessageBubbleLayoutForContent(NSString *content,
                                                                     TLThemePalette *palette,
                                                                     CGFloat availableWidth,
                                                                     CGFloat widthMultiplier,
                                                                     BOOL showsOutgoingTail) {
  CGFloat baseHorizontalInset = palette.space4 * TLUserMessageBaseHorizontalInsetScale;
  CGFloat leadingInset = baseHorizontalInset;
  CGFloat trailingInset = baseHorizontalInset;
  CGFloat topInset = palette.space4;
  CGFloat bottomInset = palette.space4;
  CGFloat textMaxWidth = MAX(1.0, (availableWidth * widthMultiplier) - leadingInset - trailingInset);
  NSInteger lineCount = TLUserMessageLineCount(content, palette.messageBodyFont, textMaxWidth);

  if (lineCount > 1) {
    leadingInset = baseHorizontalInset * TLUserMessageMultilineHorizontalInsetScale;
    trailingInset = baseHorizontalInset * TLUserMessageMultilineHorizontalInsetScale;
    topInset = palette.space4 * TLUserMessageMultilineVerticalInsetScale;
    bottomInset = palette.space3 * TLUserMessageMultilineVerticalInsetScale;
    textMaxWidth = MAX(1.0, (availableWidth * widthMultiplier) - leadingInset - trailingInset);
    lineCount = TLUserMessageLineCount(content, palette.messageBodyFont, textMaxWidth);
  }

  NSString *trimmedContent = [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  TLUserMessageBubbleLayout layout = {
    .leadingInset = leadingInset,
    .trailingInset = trailingInset,
    .topInset = topInset,
    .bottomInset = bottomInset + (showsOutgoingTail ? palette.space4 : palette.space0),
    .textMaxWidth = textMaxWidth,
    .rendersAsPill = lineCount == 1,
    .tailHorizontalOffset = showsOutgoingTail && trimmedContent.length < TLUserMessageShortTailCharacterLimit ? palette.space2 : palette.space0,
  };
  return layout;
}

@interface TalariaWindowController () <NSWindowDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, TLHistoryPanelControllerDelegate, TLWorkspaceTabsControllerDelegate>

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAssistantTurnRunner *assistantTurnRunner;
@property (nonatomic, strong) TLChatIconGenerator *chatIconGenerator;
@property (nonatomic, strong) TLAppStateManager *appStateManager;
@property (nonatomic, strong) NSMutableArray<TLAppStateSubscription *> *appStateSubscriptions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLWorkspaceTabRuntime *> *workspaceTabRuntimes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *chatIconRequests;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLAppSettings *settings;
@property (nonatomic, strong) NSMutableArray<TLChatSummary *> *chats;
@property (nonatomic, strong) NSMutableArray<TLAgentRecord *> *agents;
@property (nonatomic, strong, nullable) TLWorkspaceTab *historyTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *settingsTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *agentsTab;
@property (nonatomic, strong, nullable) TLWorkspaceTab *debugTab;
@property (nonatomic, strong) TLChatRecord *activeChat;
@property (nonatomic) NSInteger nextBrowserTabID;
@property (nonatomic) NSInteger nextDraftChatID;
@property (nonatomic, strong) NSMutableArray<TLChatMessage *> *messages;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSView *> *messageRowViews;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSString *> *messageRowSignatures;
@property (nonatomic) BOOL isSending;
@property (nonatomic) NSInteger sendingChatID;
@property (nonatomic, strong) NSMutableArray<TLChatMessage *> *sendingMessages;
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
@property (nonatomic, strong) TLSidebarUserButton *sidebarUserButton;
@property (nonatomic, strong) TLSidebarResizeHandle *sidebarResizeHandle;
@property (nonatomic) CGFloat sidebarPreferredWidth;
@property (nonatomic) CGFloat sidebarResizeStartWidth;
@property (nonatomic) BOOL sidebarVisible;
@property (nonatomic) BOOL effectiveAppearanceObserverInstalled;

@property (nonatomic, strong) TLHistoryPanelController *historyPanelController;
@property (nonatomic, strong) TLTokenView *agentsView;
@property (nonatomic, strong) TLSettingsTabController *settingsTabController;
@property (nonatomic, strong) NSTableView *agentsTableView;
@property (nonatomic, strong) NSTextField *agentsStatusLabel;
@property (nonatomic, strong) NSButton *createAgentButton;
@property (nonatomic, strong) NSButton *startAgentButton;
@property (nonatomic, strong) NSButton *stopAgentButton;
@property (nonatomic, strong) NSButton *deleteAgentButton;
@property (nonatomic, strong) NSButton *closeAgentsButton;
@property (nonatomic, strong) NSScrollView *messageScrollView;
@property (nonatomic, strong) TLFlippedView *messageDocumentView;
@property (nonatomic, strong) NSStackView *messageStack;
@property (nonatomic, strong) NSLayoutConstraint *messageStackBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *messageStackMinimumBottomConstraint;
@property (nonatomic, strong) NSTextView *promptTextView;
@property (nonatomic, strong) TLNotchOverlayController *notchOverlayController;
@property (nonatomic, strong) id messageScrollWheelMonitor;
@property (nonatomic, strong) id messageContextMenuMonitor;

@property (nonatomic, strong) TLButton *createChatButton;
@property (nonatomic, strong) TLButton *sidebarToggleButton;
@property (nonatomic, strong) TLGlassPaneView *slashCommandListView;
@property (nonatomic, strong) NSStackView *slashCommandListStack;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *visibleSlashCommands;
@property (nonatomic, copy) NSArray<TLSlashCommandItemView *> *slashCommandRows;
@property (nonatomic) NSInteger selectedSlashCommandIndex;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *slashCommandListBottomConstraint;
@property (nonatomic, strong) TLOnboardingDemoWindowController *onboardingDemoWindowController;
@property (nonatomic, strong) TLHermesOnboardingWindowController *hermesOnboardingWindowController;
@property (nonatomic, strong) TLVMDebugTerminalWindowController *debugTerminalWindowController;
@property (nonatomic, strong, nullable) TLASCIIPlanetScreensaverView *screensaverView;
@property (nonatomic) NSRect mainWindowFrameBeforeOnboarding;
@property (nonatomic) BOOL hasMainWindowFrameBeforeOnboarding;
@property (nonatomic, strong) NSImage *mainWindowSnapshotBeforeOnboarding;
@property (nonatomic, strong) NSWindow *mainWindowRevealOverlayWindow;
@property (nonatomic, strong) TLGlassButton *sendButton;

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
- (NSView *)slashCommandRowWithCommand:(NSDictionary<NSString *, NSString *> *)command;
- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands;
- (void)applySlashCommandListPalette;
- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex;
- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset;
- (BOOL)performSelectedSlashCommand;
- (BOOL)performSlashCommandIfNeededForPrompt:(NSString *)prompt;
- (void)updateSlashCommandList;
- (void)openAppFromOnboarding;
- (void)revealMainWindowFromOnboarding;
- (NSImage *)snapshotOfMainWindow;
- (void)finishMainWindowRevealWithFinalFrame:(NSRect)finalFrame;
- (void)hideSlashCommandList;
- (void)runSlashCommandFromItem:(id)sender;
- (void)showOnboardingDemoWindow:(id)sender;
- (void)showScreensaver;
- (void)hideScreensaver;
- (void)addUrgentNotification;
- (void)addDelayedCalendarConflictNotification;
- (void)openAWSOutageChat:(id)sender;
- (void)sendAWSOutageIntent:(id)sender;
- (NSView *)AWSOutageIntentWidget;
- (BOOL)messageShowsAWSOutageIntent:(TLChatMessage *)message;
- (void)prepareResponsiveLayoutForWindowWidth:(CGFloat)windowWidth;
- (CGFloat)tabStackLeadingConstantForSidebarWidth:(CGFloat)sidebarWidth;
- (CGFloat)availableTabStripWidthForLeadingConstant:(CGFloat)leadingConstant topbarWidth:(CGFloat)topbarWidth;
- (CGFloat)clampedSidebarWidthForPreferredWidth:(CGFloat)preferredWidth windowWidth:(CGFloat)windowWidth;
- (BOOL)closeWindowIfOnlyWorkspaceTab:(TLWorkspaceTab *)tab;

@end

@implementation TalariaWindowController

- (void)allowHorizontalWindowExpansionForView:(NSView *)view {
  [view setContentHuggingPriority:NSLayoutPriorityDefaultLow
                   forOrientation:NSLayoutConstraintOrientationHorizontal];
  [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];
}

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
    _assistantTurnRunner = [[TLAssistantTurnRunner alloc] initWithDatabase:database
                                                         agentOrchestrator:agentOrchestrator];
    _chatIconGenerator = [[TLChatIconGenerator alloc] initWithAgentOrchestrator:agentOrchestrator];
    _appStateManager = appStateManager ?: [[TLAppStateManager alloc] init];
    _appStateSubscriptions = [NSMutableArray array];
    _workspaceTabRuntimes = [NSMutableDictionary dictionary];
    _chatIconRequests = [NSMutableSet set];
    _settings = [TLAppSettings defaultSettings];
    _palette = [TLThemePalette paletteForPreference:_settings.theme];
    _sidebarPreferredWidth = _palette.sidebarWidth;
    _chats = [NSMutableArray array];
    _agents = [NSMutableArray array];
    _nextBrowserTabID = 1;
    _nextDraftChatID = -1;
    _messages = [NSMutableArray array];
    _messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
    _messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
    _errorMessage = @"";
    _sidebarVisible = YES;
    _widgetbookMode = TLWidgetbookModeEnabled();
    if (_widgetbookMode) {
      window.title = @"Talaria Widgetbook";
    }
    window.delegate = self;
    [self buildInterface];
    [self installAppStateBindings];
    [self loadInitialState];
    [self installEffectiveAppearanceObserver];
    _notchOverlayController = [[TLNotchOverlayController alloc] initWithPalette:_palette
                                                                         target:self
                                                                         action:@selector(openFromNotchOverlay:)];
    __weak typeof(self) weakSelf = self;
    _notchOverlayController.fileDropHandler = ^(NSArray<NSURL *> *fileURLs) {
      [weakSelf handleFileURLsDroppedOnNotch:fileURLs];
    };
    [_notchOverlayController startTracking];
  }
  return self;
}

- (void)dealloc {
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
  if (self.settings.theme != TLThemePreferenceSystem) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.settings.theme != TLThemePreferenceSystem) {
      return;
    }

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
  [sender orderOut:self];
  return NO;
}

- (void)closeActiveTabOrWindow:(id)sender {
  NSArray<TLWorkspaceTab *> *tabs = [self workspaceTabs];
  if (tabs.count <= 1) {
    [self.window performClose:sender];
    return;
  }

  TLWorkspaceTab *activeTab = [self activeWorkspaceTab];
  TLWorkspaceTabRuntime *runtime = [self runtimeForTab:activeTab];
  if (!activeTab || !runtime.closeAction) {
    return;
  }

  NSButton *closeSender = [[NSButton alloc] init];
  closeSender.tag = activeTab.tabID;
  [NSApp sendAction:runtime.closeAction to:self from:closeSender];
}

- (void)showWindow:(id)sender {
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
  self.workspaceTabsController.selectionView.geometryChanged = ^{ [outline updateOutline]; };
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

  self.chatWorkspace = [self buildChatWorkspace];
  NSView *historyScreen = [self buildHistoryPanel];
  [self.contentHost addSubview:self.chatWorkspace];
  [self.contentHost addSubview:historyScreen];

  [NSLayoutConstraint activateConstraints:@[
    [self.chatWorkspace.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
    [self.chatWorkspace.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
    [self.chatWorkspace.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
    [self.chatWorkspace.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor],
    [historyScreen.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
    [historyScreen.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
    [historyScreen.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
    [historyScreen.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor],
  ]];

  [self updateSidebarLayoutAnimated:NO];
  [self updateWorkspaceMode];
  return workspace;
}

- (NSStackView *)buildSidebarTileGrid {
  TLHoverStackView *tileGrid = [[TLHoverStackView alloc] init];
  tileGrid.translatesAutoresizingMaskIntoConstraints = NO;
  tileGrid.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  tileGrid.alignment = NSLayoutAttributeHeight;
  tileGrid.distribution = NSStackViewDistributionFill;
  tileGrid.spacing = self.palette.space5;

  TLIconTileView *planetTile = [[TLIconTileView alloc] init];
  planetTile.palette = self.palette;
  planetTile.image = [self sidebarPlanetImage];
  if (!planetTile.image) {
    planetTile.systemIconName = @"globe.europe.africa.fill";
  }
  planetTile.selected = YES;
  planetTile.imageSize = self.palette.space12 + self.palette.space2;
  planetTile.toolTip = @"Jupiter";

  TLIconTileView *saturnTile = [[TLIconTileView alloc] init];
  saturnTile.palette = self.palette;
  saturnTile.image = [self sidebarSaturnImage];
  saturnTile.imageSize = planetTile.imageSize;
  saturnTile.toolTip = @"Saturn - shared";
  saturnTile.badgeSystemIconName = @"person.2.fill";

  [tileGrid addArrangedSubview:planetTile];
  [tileGrid addArrangedSubview:saturnTile];
  NSView *remainingSpace = [[NSView alloc] init];
  [tileGrid addArrangedSubview:remainingSpace];
  NSLayoutConstraint *preferredWidth = [planetTile.widthAnchor constraintEqualToConstant:self.palette.sidebarAgentTileMaximumWidth];
  preferredWidth.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    preferredWidth,
    [planetTile.widthAnchor constraintLessThanOrEqualToConstant:self.palette.sidebarAgentTileMaximumWidth],
    [saturnTile.widthAnchor constraintEqualToAnchor:planetTile.widthAnchor],
    [remainingSpace.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.space0],
  ]];
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

- (NSImage *)sidebarSaturnImage {
  CGFloat size = self.palette.space16 + self.palette.space6;
  NSAttributedString *planet = [[NSAttributedString alloc] initWithString:@"\U0001FA90"
    attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:self.palette.space16]}];
  return [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
    NSSize textSize = planet.size;
    [planet drawAtPoint:NSMakePoint((NSWidth(bounds) - textSize.width) / 2.0,
                                   (NSHeight(bounds) - textSize.height) / 2.0)];
    return YES;
  }];
}

- (NSView *)sidebarAgentRowWithName:(NSString *)name
                            shared:(BOOL)shared
                            avatar:(NSImage *)avatar
                          selected:(BOOL)selected
                          services:(NSArray<NSImage *> *)services
                      serviceNames:(NSArray<NSString *> *)serviceNames {
  TLSelectionStackView *row = [[TLSelectionStackView alloc] init];
  row.palette = self.palette;
  row.selected = selected;
  row.wantsLayer = YES;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeCenterY;
  row.distribution = NSStackViewDistributionFill;
  row.spacing = self.palette.space8;
  row.edgeInsets = NSEdgeInsetsMake(self.palette.space8, self.palette.space6,
                                    self.palette.space8, self.palette.space6);

  NSImageView *avatarView = [[NSImageView alloc] init];
  avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  avatarView.image = avatar;
  avatarView.imageScaling = NSImageScaleProportionallyUpOrDown;
  NSView *avatarSlot = [[NSView alloc] init];
  avatarSlot.translatesAutoresizingMaskIntoConstraints = NO;
  [avatarSlot addSubview:avatarView];
  [NSLayoutConstraint activateConstraints:@[
    [avatarSlot.widthAnchor constraintEqualToConstant:self.palette.agentMenuAvatarSize],
    [avatarSlot.heightAnchor constraintEqualToConstant:self.palette.space16],
    [avatarView.widthAnchor constraintEqualToConstant:self.palette.agentMenuAvatarSize],
    [avatarView.heightAnchor constraintEqualToConstant:self.palette.agentMenuAvatarSize],
    [avatarView.centerXAnchor constraintEqualToAnchor:avatarSlot.centerXAnchor],
    [avatarView.centerYAnchor constraintEqualToAnchor:avatarSlot.centerYAnchor],
  ]];
  [row addArrangedSubview:avatarSlot];
  [row setCustomSpacing:self.palette.space5 afterView:avatarSlot];

  NSStackView *details = [[NSStackView alloc] init];
  details.orientation = NSUserInterfaceLayoutOrientationVertical;
  details.alignment = NSLayoutAttributeLeading;
  details.distribution = NSStackViewDistributionFill;
  details.spacing = self.palette.space5;
  NSStackView *heading = [[NSStackView alloc] init];
  heading.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  heading.alignment = NSLayoutAttributeCenterY;
  heading.distribution = NSStackViewDistributionFill;
  heading.spacing = self.palette.space5;
  [heading addArrangedSubview:[self labelWithString:name font:self.palette.labelFont color:self.palette.appText]];
  if (shared) {
    NSStackView *sharedLabel = [[NSStackView alloc] init];
    sharedLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sharedLabel.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    sharedLabel.alignment = NSLayoutAttributeCenterY;
    sharedLabel.distribution = NSStackViewDistributionFill;
    sharedLabel.spacing = self.palette.space2;
    NSImageView *sharedIcon = [[NSImageView alloc] init];
    sharedIcon.translatesAutoresizingMaskIntoConstraints = NO;
    sharedIcon.image = [NSImage imageWithSystemSymbolName:@"person.2" accessibilityDescription:nil];
    sharedIcon.contentTintColor = self.palette.textMuted;
    sharedIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [sharedIcon.widthAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
    [sharedIcon.heightAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
    NSView *iconSlot = [[NSView alloc] init];
    iconSlot.translatesAutoresizingMaskIntoConstraints = NO;
    [iconSlot addSubview:sharedIcon];
    [NSLayoutConstraint activateConstraints:@[
      [iconSlot.widthAnchor constraintEqualToAnchor:sharedIcon.widthAnchor],
      [iconSlot.heightAnchor constraintEqualToAnchor:sharedIcon.heightAnchor],
      [sharedIcon.leadingAnchor constraintEqualToAnchor:iconSlot.leadingAnchor],
      [sharedIcon.centerYAnchor constraintEqualToAnchor:iconSlot.centerYAnchor constant:self.palette.agentSharedIconDownwardOffset],
    ]];
    [sharedLabel addArrangedSubview:iconSlot];
    [sharedLabel addArrangedSubview:[self labelWithString:@"shared" font:self.palette.smallFont color:self.palette.textMuted]];
    NSView *sharedSlot = [[NSView alloc] init];
    sharedSlot.translatesAutoresizingMaskIntoConstraints = NO;
    [sharedSlot addSubview:sharedLabel];
    [NSLayoutConstraint activateConstraints:@[
      [sharedSlot.widthAnchor constraintEqualToAnchor:sharedLabel.widthAnchor],
      [sharedSlot.heightAnchor constraintEqualToAnchor:sharedLabel.heightAnchor],
      [sharedLabel.leadingAnchor constraintEqualToAnchor:sharedSlot.leadingAnchor],
      [sharedLabel.centerYAnchor constraintEqualToAnchor:sharedSlot.centerYAnchor constant:self.palette.agentSharedLabelDownwardOffset],
    ]];
    [heading addArrangedSubview:sharedSlot];
  }
  [details addArrangedSubview:heading];

  NSStackView *serviceRow = [[NSStackView alloc] init];
  serviceRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  serviceRow.distribution = NSStackViewDistributionFill;
  serviceRow.spacing = self.palette.space5;
  for (NSUInteger index = 0; index < services.count; index++) {
    NSImageView *icon = [[NSImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = services[index];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.toolTip = serviceNames[index];
    [icon setAccessibilityLabel:serviceNames[index]];
    [icon.widthAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
    [icon.heightAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
    [serviceRow addArrangedSubview:icon];
  }
  [details addArrangedSubview:serviceRow];
  [row addArrangedSubview:details];
  NSView *spacer = [[NSView alloc] init];
  [spacer.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.space0].active = YES;
  [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [details setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
  [row addArrangedSubview:spacer];
  NSImageView *selectionIcon = [[NSImageView alloc] init];
  selectionIcon.translatesAutoresizingMaskIntoConstraints = NO;
  selectionIcon.image = selected
    ? [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:@"Selected agent"]
    : nil;
  selectionIcon.contentTintColor = self.palette.appText;
  selectionIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
  [selectionIcon.widthAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
  [selectionIcon.heightAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize].active = YES;
  [row addArrangedSubview:selectionIcon];
  return row;
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
  [pane addArrangedSubview:[self sidebarAgentRowWithName:@"Jupiter" shared:NO
    avatar:[self sidebarPlanetImage]
    selected:((TLIconTileView *)self.sidebarTileGrid.arrangedSubviews[0]).selected
    services:@[[self inboxIconNamed:@"gmail"], [self inboxIconNamed:@"google-calendar"]]
    serviceNames:@[@"Gmail", @"Google Calendar"]]];
  [pane addArrangedSubview:[self sidebarAgentRowWithName:@"Saturn" shared:YES
    avatar:[self sidebarSaturnImage]
    selected:((TLIconTileView *)self.sidebarTileGrid.arrangedSubviews[1]).selected
    services:@[[self inboxIconNamed:@"slack"], [self browserBookmarkIconNamed:@"github"]]
    serviceNames:@[@"Slack", @"GitHub"]]];
  NSButton *addButton = [[NSButton alloc] init];
  TLSpacedButtonCell *addCell = [[TLSpacedButtonCell alloc] initTextCell:@"Create agent"];
  addCell.imageTitleSpacing = self.palette.menuActionIconTextSpacing;
  addCell.imageUpwardOffset = self.palette.menuActionIconUpwardOffset;
  addButton.cell = addCell;
  addButton.target = self;
  addButton.action = @selector(openAgentsFromSidebarPane:);
  addButton.image = [NSImage imageWithSystemSymbolName:@"person.badge.plus" accessibilityDescription:@"Create agent"];
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

  NSArray<NSDictionary<NSString *, NSString *> *> *bookmarks = @[
    @{@"title": @"Google", @"icon": @"google", @"URL": @"https://www.google.com/"},
    @{@"title": @"GitHub", @"icon": @"github", @"URL": @"https://github.com/"},
    @{@"title": @"Wikipedia", @"icon": @"wikipedia", @"URL": @"https://www.wikipedia.org/"},
    @{@"title": @"Hacker News", @"icon": @"hacker-news", @"URL": @"https://news.ycombinator.com/"},
  ];
  for (NSDictionary<NSString *, NSString *> *bookmark in bookmarks) {
    TLSidebarShortcutButton *button = [[TLSidebarShortcutButton alloc] init];
    button.palette = self.palette;
    button.title = bookmark[@"title"];
    button.image = [self browserBookmarkIconNamed:bookmark[@"icon"]];
    button.roundsImageCorners = [bookmark[@"icon"] isEqualToString:@"wikipedia"];
    button.URL = [NSURL URLWithString:bookmark[@"URL"]];
    button.shortcutKind = TLSidebarShortcutKindWebsite;
    button.target = self;
    button.action = @selector(openSidebarBookmark:);
    [self.sidebarShortcutsView addShortcutButton:button];
  }

  self.gmailInboxStackView = [self sidebarInboxStackViewWithTitle:@"Payment pending"
                                                         subtitle:@"Daily Email Summary"
                                                    iconAssetName:@"gmail"
                                                notificationCount:3];
  self.slackInboxStackView = [self sidebarInboxStackViewWithTitle:@"Project deadline question"
                                                         subtitle:@"Review Slack Mentions"
                                                    iconAssetName:@"slack"
                                                notificationCount:0];
  TLSidebarInboxStackView *driveCleanupInboxStackView = [self sidebarInboxStackViewWithTitle:@"2.4 GB can be cleaned up"
                                                                                    subtitle:@"Clean Hard Drive"
                                                                              systemIconName:@"externaldrive.fill"
                                                                           notificationCount:0];
  TLSidebarInboxStackView *downloadReviewInboxStackView = [self sidebarInboxStackViewWithTitle:@"14 downloads need review"
                                                                                      subtitle:@"Review Downloads"
                                                                                systemIconName:@"tray.and.arrow.down.fill"
                                                                             notificationCount:0];
  TLSidebarInboxStackView *securityReviewInboxStackView = [self sidebarInboxStackViewWithTitle:@"Password security issues"
                                                                                      subtitle:@"Security Checkup"
                                                                                systemIconName:@"lock.shield.fill"
                                                                             notificationCount:0];
  self.gmailInboxStackView.usesPrimaryBadge = YES;
  NSArray<TLSidebarInboxStackView *> *inboxItemViews = @[
    self.gmailInboxStackView,
    self.slackInboxStackView,
    driveCleanupInboxStackView,
    downloadReviewInboxStackView,
    securityReviewInboxStackView,
  ];
  for (TLSidebarInboxStackView *inboxItemView in inboxItemViews) {
    inboxItemView.showsSeparator = NO;
  }

  self.sidebarInboxPaneView = [[TLSidebarInboxPaneView alloc] init];
  self.sidebarInboxPaneView.palette = self.palette;
  [self.sidebarInboxPaneView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationVertical];
  [self.sidebarInboxPaneView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationVertical];
  for (TLSidebarInboxStackView *inboxItemView in inboxItemViews) {
    [self.sidebarInboxPaneView addInboxItemView:inboxItemView];
  }

  [inboxStack addArrangedSubview:self.sidebarShortcutsView];
  [inboxStack setCustomSpacing:self.palette.space5 afterView:self.sidebarShortcutsView];
  [inboxStack addArrangedSubview:self.sidebarInboxPaneView];
  [self.sidebarShortcutsView.widthAnchor constraintEqualToAnchor:inboxStack.widthAnchor].active = YES;
  [self.sidebarInboxPaneView.widthAnchor constraintEqualToAnchor:inboxStack.widthAnchor].active = YES;
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

  self.sidebarUserButton = [self sidebarUserButtonWithDisplayName:@"Yaroslav"];

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

- (nullable NSImage *)browserBookmarkIconNamed:(NSString *)name {
  NSURL *iconURL = [NSBundle.mainBundle URLForResource:name
                                         withExtension:@"png"
                                          subdirectory:@"browser-bookmarks"];
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

- (NSView *)buildChatWorkspace {
  NSView *chatWorkspace = [[NSView alloc] init];
  chatWorkspace.translatesAutoresizingMaskIntoConstraints = NO;
  [self allowHorizontalWindowExpansionForView:chatWorkspace];

  NSView *messagesView = [self buildMessagesView];
  [chatWorkspace addSubview:messagesView];
  [chatWorkspace addSubview:[self buildSlashCommandListView]];
  [chatWorkspace addSubview:[self buildMessageInput]];

  NSLayoutConstraint *messageInputLeadingConstraint = [self.messageInput.leadingAnchor constraintGreaterThanOrEqualToAnchor:chatWorkspace.leadingAnchor
                                                                                                                   constant:self.palette.space11];
  NSLayoutConstraint *messageInputTrailingConstraint = [self.messageInput.trailingAnchor constraintLessThanOrEqualToAnchor:chatWorkspace.trailingAnchor
                                                                                                                    constant:-self.palette.space11];
  messageInputLeadingConstraint.priority = NSLayoutPriorityDefaultLow;
  messageInputTrailingConstraint.priority = NSLayoutPriorityDefaultLow;
  CGFloat initialAvailableInputWidth = self.palette.windowInitialWidth - (self.palette.space11 * 2.0);
  CGFloat initialInputWidth = MIN(self.palette.messageInputMaxWidth,
                                  MAX(self.palette.messageInputMinWidth, initialAvailableInputWidth));
  self.messageInputWidthConstraint = [self.messageInput.widthAnchor constraintEqualToConstant:initialInputWidth];
  self.messageInputWidthConstraint.priority = NSLayoutPriorityWindowSizeStayPut - 1.0;
  self.slashCommandListBottomConstraint = [self.slashCommandListView.bottomAnchor constraintEqualToAnchor:self.messageInput.topAnchor
                                                                                                  constant:-self.palette.space5];

  [NSLayoutConstraint activateConstraints:@[
    [messagesView.leadingAnchor constraintEqualToAnchor:chatWorkspace.leadingAnchor],
    [messagesView.trailingAnchor constraintEqualToAnchor:chatWorkspace.trailingAnchor],
    [messagesView.topAnchor constraintEqualToAnchor:chatWorkspace.topAnchor],
    [messagesView.bottomAnchor constraintEqualToAnchor:chatWorkspace.bottomAnchor],
    [self.messageInput.centerXAnchor constraintEqualToAnchor:chatWorkspace.centerXAnchor],
    [self.slashCommandListView.leadingAnchor constraintEqualToAnchor:self.messageInput.leadingAnchor],
    self.slashCommandListWidthConstraint,
    self.slashCommandListBottomConstraint,
    self.slashCommandListHeightConstraint,
    [self.messageStack.widthAnchor constraintEqualToAnchor:self.messageInput.widthAnchor],
    [self.messageInput.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.messageInputMinWidth],
    [self.messageInput.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth],
    messageInputLeadingConstraint,
    messageInputTrailingConstraint,
    self.messageInputWidthConstraint,
    [self.messageInput.bottomAnchor constraintEqualToAnchor:chatWorkspace.bottomAnchor constant:-self.palette.space10],
  ]];

  return chatWorkspace;
}

- (void)updateMessageInputWidthForWindowWidth:(CGFloat)windowWidth {
  if (!self.messageInputWidthConstraint) {
    return;
  }

  CGFloat previousWidth = self.messageInputWidthConstraint.constant;
  CGFloat nextWidth = [self messageInputWidthForWindowWidth:windowWidth
                                               sidebarWidth:[self currentSidebarWidth]
                                      contentLeadingPadding:[self contentLeadingPadding]];
  self.messageInputWidthConstraint.constant = nextWidth;
  [self applyBrowserAddressInputWidth:nextWidth];
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

- (NSView *)buildMessagesView {
  self.messagesBackground = [[TLTokenView alloc] init];
  self.messagesBackground.translatesAutoresizingMaskIntoConstraints = NO;
  [self allowHorizontalWindowExpansionForView:self.messagesBackground];

  self.messageDocumentView = [[TLFlippedView alloc] init];
  self.messageDocumentView.translatesAutoresizingMaskIntoConstraints = NO;

  self.messageStack = [[NSStackView alloc] init];
  self.messageStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.messageStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.messageStack.alignment = NSLayoutAttributeWidth;
  self.messageStack.distribution = NSStackViewDistributionGravityAreas;
  self.messageStack.spacing = self.palette.messageVerticalSpacing;
  [self.messageStack setHuggingPriority:NSLayoutPriorityRequired
                         forOrientation:NSLayoutConstraintOrientationVertical];
  [self.messageStack setContentHuggingPriority:NSLayoutPriorityRequired
                                forOrientation:NSLayoutConstraintOrientationVertical];
  [self.messageStack setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                              forOrientation:NSLayoutConstraintOrientationVertical];
  [self.messageDocumentView addSubview:self.messageStack];

  self.messageScrollView = [[NSScrollView alloc] init];
  self.messageScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.messageScrollView.documentView = self.messageDocumentView;
  self.messageScrollView.hasVerticalScroller = YES;
  self.messageScrollView.autohidesScrollers = YES;
  self.messageScrollView.drawsBackground = NO;
  [self.messagesBackground addSubview:self.messageScrollView];
  [self installMessageScrollWheelMonitor];

  NSLayoutConstraint *documentWidthConstraint = [self.messageDocumentView.widthAnchor constraintEqualToAnchor:self.messageScrollView.contentView.widthAnchor];
  documentWidthConstraint.priority = NSLayoutPriorityDefaultLow;
  self.messageStackMinimumBottomConstraint = [self.messageStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.messageDocumentView.bottomAnchor
                                                                                                      constant:-self.palette.space12];
  self.messageStackBottomConstraint = [self.messageStack.bottomAnchor constraintEqualToAnchor:self.messageDocumentView.bottomAnchor
                                                                                     constant:-self.palette.space12];
  self.messageStackBottomConstraint.priority = NSLayoutPriorityDefaultLow;

  [NSLayoutConstraint activateConstraints:@[
    [self.messageScrollView.leadingAnchor constraintEqualToAnchor:self.messagesBackground.leadingAnchor],
    [self.messageScrollView.trailingAnchor constraintEqualToAnchor:self.messagesBackground.trailingAnchor],
    [self.messageScrollView.topAnchor constraintEqualToAnchor:self.messagesBackground.topAnchor],
    [self.messageScrollView.bottomAnchor constraintEqualToAnchor:self.messagesBackground.bottomAnchor],
    documentWidthConstraint,
    [self.messageStack.centerXAnchor constraintEqualToAnchor:self.messageDocumentView.centerXAnchor],
    [self.messageStack.topAnchor constraintEqualToAnchor:self.messageDocumentView.topAnchor constant:self.palette.space12],
    self.messageStackMinimumBottomConstraint,
    self.messageStackBottomConstraint,
  ]];

  return self.messagesBackground;
}

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
      [menu addItem:NSMenuItem.separatorItem];
      NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete message"
        action:@selector(deleteChatMessage:) keyEquivalent:@""];
      deleteItem.target = controller;
      deleteItem.representedObject = context;
      deleteItem.enabled = !controller.isSending;
      deleteItem.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:nil];
      [menu addItem:deleteItem];
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
  [self.messages removeObjectAtIndex:index];
  [self refreshChatsKeepingActiveSelection];
  [self renderMessagesScrollingToBottom:NO];
  [self updateControlStates];
}

- (NSView *)buildMessageInput {
  self.messageInput = [[TLGlassMessageInput alloc] init];
  self.messageInput.palette = self.palette;
  self.promptTextView = self.messageInput.textView;
  self.promptTextView.delegate = self;
  self.sendButton = self.messageInput.sendButton;
  self.sendButton.target = self;
  self.sendButton.action = @selector(sendMessage:);
  return self.messageInput;
}

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
  self.palette = [TLThemePalette paletteForPreference:self.settings.theme];
  self.chats = [loadedChats mutableCopy];
  self.agents = [loadedAgents mutableCopy];

  if (self.appStateManager.snapshot.workspaceTabs.count > 0) {
    [self hydrateWorkspaceTabsFromAppState];
    [self restoreWorkspaceFromAppState];
  } else if (self.chats.count > 0) {
    [self loadChatWithID:self.chats[0].chatID];
  } else {
    [self startNewChatWithModel:self.settings.selectedModel focus:NO];
  }

  self.isLoading = NO;
  self.errorMessage = @"";
  [self applyTheme];
  [self renderMessages];
  if (!self.settings.onboardingCompleted) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self showOnboardingDemoWindow:self]; });
  }
}

- (void)hydrateWorkspaceTabsFromAppState {
  for (TLWorkspaceTab *tab in self.appStateManager.snapshot.workspaceTabs) {
    TLWorkspaceTabRuntime *runtime = [self runtimeForTab:tab];
    switch (tab.kind) {
      case TLWorkspaceTabKindChat:
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
        if (runtime.contentView) {
          [self addWorkspaceContentView:runtime.contentView];
        }
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
  [self selectActiveChatInHistory];
  [self reloadWorkspaceTabs];

  for (TLChatSummary *summary in self.chats) {
    if (summary.chatID == self.activeChat.chatID) {
      self.activeChat.title = summary.title;
      self.activeChat.icon = summary.icon;
      self.activeChat.updatedAt = summary.updatedAt;
      break;
    }
  }

}

- (void)loadChatWithID:(NSInteger)chatID {
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
  [self addChatToSessionIfNeeded:chat.chatID activate:YES];
  [self showChatWorkspace];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  for (TLStoredChatMessage *storedMessage in chat.messages) {
    [self.messages addObject:[storedMessage copy]];
  }
  if (self.isSending && self.sendingChatID == chatID) self.messages = self.sendingMessages;

  self.promptTextView.string = @"";
  self.errorMessage = @"";
  [self selectActiveChatInHistory];
  [self renderMessages];
  [self updateControlStates];
  [self generateChatIconIfNeededForChatID:chat.chatID messages:self.messages];
}

- (void)activateDraftChatWithID:(NSInteger)chatID {
  TLWorkspaceTab *tab = [self.appStateManager workspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
  if (!tab) {
    return;
  }

  TLChatRecord *chat = [[TLChatRecord alloc] init];
  chat.chatID = chatID;
  chat.title = tab.title.length > 0 ? tab.title : @"New chat";
  chat.model = self.settings.selectedModel.length > 0 ? self.settings.selectedModel : TLDefaultModelID;
  chat.messages = @[];

  self.activeChat = chat;
  [self activateTabKind:TLWorkspaceTabKindChat tabID:chatID];
  [self showChatWorkspace];
  self.messages = [NSMutableArray array];
  [self resetMessageRowCache];
  self.promptTextView.string = @"";
  self.errorMessage = @"";
  [self selectActiveChatInHistory];
  [self renderMessages];
  [self updateControlStates];
}

- (void)startNewChatFromButton:(id)sender {
  [self startNewChatWithModel:self.settings.selectedModel focus:YES];
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
  if (![self isBrowserURL:URL]) return;
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser
    tabID:self.nextBrowserTabID++ title:[self browserTabTitleForURL:URL]
    toolTip:URL.absoluteString URL:URL closeable:YES];
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
  controller.faviconChangedHandler = ^{ [weakSelf reloadWorkspaceTabs]; };
  controller.linkHandler = ^(NSURL *linkedURL, NSEventModifierFlags flags) {
    [weakSelf handleBrowserTabRequestURL:linkedURL modifierFlags:flags];
  };
  controller.settingsProvider = ^{ return weakSelf.settings; };
  controller.settingsRequiredHandler = ^{ [weakSelf showSettings:weakSelf]; };
  [self.appStateManager addWorkspaceTab:tab activate:YES];
  [self addWorkspaceContentView:controller.view];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
  [controller startInWindow:self.window];
}

- (void)openSidebarBookmark:(TLSidebarShortcutButton *)sender {
  if (!sender.URL) {
    NSBeep();
    return;
  }
  [self openBrowserTabWithURL:sender.URL];
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
  TLChatRecord *persistedChat = [self.database createChatWithModel:model error:&error];
  if (!persistedChat) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not create chat."];
    return NO;
  }

  persistedChat.messages = @[];
  self.activeChat = persistedChat;
  TLWorkspaceTab *tab = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat
                                             tabID:persistedChat.chatID
                                             title:persistedChat.title.length > 0 ? persistedChat.title : @"New chat"
                                           toolTip:persistedChat.title.length > 0 ? persistedChat.title : @"New chat"
                                               URL:nil
                                         closeable:YES];
  [self setRuntime:[TLWorkspaceTabRuntime runtimeWithContentView:self.chatWorkspace
                                                      openAction:@selector(openChatTab:)
                                                     closeAction:@selector(closeChatTab:)]
            forTab:tab];
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

- (void)sendMessage:(id)sender {
  if ([self performSelectedSlashCommand]) {
    return;
  }
  [self sendMessage:sender allowAutomaticRouting:YES];
}

- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting {
  NSString *token = [self.settings.openRouterToken stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *model = [self.settings.selectedModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *nextPrompt = [self.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

  if (self.isSending || nextPrompt.length == 0) {
    return;
  }

  NSURL *browserURL = allowAutomaticRouting ? [self browserURLFromPromptString:nextPrompt] : nil;
  if (browserURL) {
    self.promptTextView.string = @"";
    [self.messageInput recalculateHeight];
    [self updateMessageScrollInsets];
    [self updateSlashCommandList];
    [self openBrowserTabWithURL:browserURL];
    return;
  }

  if (allowAutomaticRouting && [self performSlashCommandIfNeededForPrompt:nextPrompt]) {
    return;
  }

  if (model.length == 0) {
    return;
  }

  if (token.length == 0) {
    self.errorMessage = @"Add an OpenRouter token in Settings before sending.";
    [self renderMessages];
    [self showSettings:self];
    return;
  }

  if (!self.activeChat) {
    [self startNewChatWithModel:model focus:NO];
  }

  if (![self persistActiveDraftChatWithModel:model]) {
    return;
  }

  TLChatRecord *chat = self.activeChat;
  NSMutableArray<TLChatMessage *> *turnMessages = self.messages;
  self.sendingChatID = chat.chatID;
  self.sendingMessages = turnMessages;
  self.promptTextView.string = @"";
  self.isSending = YES;
  self.errorMessage = @"";
  __weak typeof(self) weakSelf = self;

  NSError *startError = nil;
  BOOL started = [self.assistantTurnRunner startTurnWithChat:chat
                                                       token:token
                                                       model:model
                                                    messages:turnMessages
                                                  nextPrompt:nextPrompt
                                               updateHandler:^{
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    if (strongSelf.activeChat.chatID == chat.chatID && [strongSelf isChatWorkspaceActive]) {
      [strongSelf renderMessages];
    }
    [strongSelf updateControlStates];
  } completionHandler:^(TLAssistantTurnResult *result) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    strongSelf.isSending = NO;
    BOOL showingOrigin = strongSelf.activeChat.chatID == chat.chatID && [strongSelf isChatWorkspaceActive];
    if (showingOrigin && result.generationStatus == TLAssistantTurnGenerationStatusNotStarted) {
      strongSelf.promptTextView.string = result.userMessage.content;
      [strongSelf.messageInput recalculateHeight];
      [strongSelf updateMessageScrollInsets];
    }

    [strongSelf refreshChatsKeepingActiveSelection];
    if (result.generationStatus == TLAssistantTurnGenerationStatusSucceeded &&
        result.persistenceStatus == TLAssistantTurnPersistenceStatusSucceeded) {
      [strongSelf generateChatIconIfNeededForChatID:chat.chatID messages:turnMessages];
    }
    if (showingOrigin) [strongSelf renderMessages];
    strongSelf.sendingMessages = nil;
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

  if (!started) {
    self.isSending = NO;
    self.sendingMessages = nil;
    self.promptTextView.string = nextPrompt;
    [self presentErrorMessage:startError.localizedDescription ?: @"Could not start assistant turn."];
    [self updateControlStates];
  }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsMatchingPrompt:(NSString *)prompt {
  NSString *trimmedPrompt = [prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (![trimmedPrompt hasPrefix:@"/"]) {
    return [TLInputSuggestions webSuggestionsForInput:trimmedPrompt];
  }
  if ([trimmedPrompt rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) {
    return @[];
  }

  NSArray<NSDictionary<NSString *, NSString *> *> *commands = [self availableSlashCommands];
  NSString *query = trimmedPrompt.length > 1 ? [[trimmedPrompt substringFromIndex:1] lowercaseString] : @"";
  if (query.length == 0) {
    return commands;
  }

  NSMutableArray<NSDictionary<NSString *, NSString *> *> *matches = [NSMutableArray array];
  for (NSDictionary<NSString *, NSString *> *command in commands) {
    NSString *name = [[command[@"command"] substringFromIndex:1] lowercaseString];
    if ([name hasPrefix:query]) {
      [matches addObject:command];
    }
  }
  return matches;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSlashCommands {
  return @[];
}

- (NSView *)buildSlashCommandListView {
  self.slashCommandListView = [[TLGlassPaneView alloc] init];
  self.slashCommandListView.translatesAutoresizingMaskIntoConstraints = NO;
  self.slashCommandListView.hidden = YES;
  self.slashCommandListView.wantsLayer = YES;
  self.slashCommandListView.layer.zPosition = 20.0;
  self.slashCommandListWidthConstraint = [self.slashCommandListView.widthAnchor constraintEqualToConstant:self.palette.space0];
  self.slashCommandListHeightConstraint = [self.slashCommandListView.heightAnchor constraintEqualToConstant:self.palette.space0];

  self.slashCommandListStack = [[NSStackView alloc] init];
  self.slashCommandListStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.slashCommandListStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.slashCommandListStack.alignment = NSLayoutAttributeLeading;
  self.slashCommandListStack.distribution = NSStackViewDistributionFill;
  self.slashCommandListStack.spacing = self.palette.space3;
  [self.slashCommandListView addSubview:self.slashCommandListStack];

  NSLayoutConstraint *stackTopConstraint = [self.slashCommandListStack.topAnchor constraintEqualToAnchor:self.slashCommandListView.topAnchor
                                                                                                constant:self.palette.space2];
  NSLayoutConstraint *stackBottomConstraint = [self.slashCommandListStack.bottomAnchor constraintEqualToAnchor:self.slashCommandListView.bottomAnchor
                                                                                                      constant:-self.palette.space2];
  stackTopConstraint.priority = NSLayoutPriorityDefaultLow;
  stackBottomConstraint.priority = NSLayoutPriorityDefaultLow;
  [NSLayoutConstraint activateConstraints:@[
    [self.slashCommandListStack.leadingAnchor constraintEqualToAnchor:self.slashCommandListView.leadingAnchor constant:self.palette.space3],
    [self.slashCommandListStack.trailingAnchor constraintEqualToAnchor:self.slashCommandListView.trailingAnchor constant:-self.palette.space3],
    stackTopConstraint,
    stackBottomConstraint,
    self.slashCommandListHeightConstraint,
  ]];

  [self applySlashCommandListPalette];
  return self.slashCommandListView;
}

- (NSView *)slashCommandRowWithCommand:(NSDictionary<NSString *, NSString *> *)command {
  TLSlashCommandItemView *row = [[TLSlashCommandItemView alloc] init];
  row.palette = self.palette;
  row.command = command[@"command"] ?: @"";
  row.commandDescription = command[@"description"] ?: @"";
  row.systemIconName = command[@"icon"] ?: @"text.bubble";
  row.enabled = ![command[@"kind"] isEqualToString:@"web"] || command[@"URL"].length > 0;
  row.target = self;
  row.action = @selector(runSlashCommandFromItem:);
  row.toolTip = command[@"title"];
  return row;
}

- (void)applySlashCommandListPalette {
  if (!self.slashCommandListView) {
    return;
  }
  self.slashCommandListView.palette = self.palette;
  self.slashCommandListStack.spacing = self.palette.space2;
  self.slashCommandListBottomConstraint.constant = -self.palette.space5;
  for (TLSlashCommandItemView *row in self.slashCommandRows) {
    row.palette = self.palette;
  }
}

- (CGFloat)slashCommandListWidthForCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands {
  CGFloat maximumCommandWidth = self.palette.space0;
  NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName: self.palette.bodyFont};
  for (NSDictionary<NSString *, NSString *> *command in commands) {
    NSString *commandText = command[@"command"] ?: @"";
    NSRect labelBounds = [commandText boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                   options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                attributes:attributes];
    CGFloat rowWidth = (self.palette.space3 * 2.0) +
      (self.palette.space8 * 2.0) +
      self.palette.sidebarActionIconSize + self.palette.space4 +
      ceil(NSWidth(labelBounds));
    NSString *description = command[@"description"] ?: @"";
    if (description.length > 0) {
      rowWidth += self.palette.space6 + ceil([description sizeWithAttributes:attributes].width);
    }
    maximumCommandWidth = MAX(maximumCommandWidth, rowWidth);
  }

  CGFloat availableInputWidth = NSWidth(self.messageInput.bounds);
  if (availableInputWidth <= self.palette.space0) {
    availableInputWidth = self.messageInputWidthConstraint.constant;
  }
  if (availableInputWidth <= self.palette.space0) {
    availableInputWidth = self.palette.messageInputMaxWidth;
  }

  return MIN(availableInputWidth, ceil(maximumCommandWidth));
}

- (void)showSlashCommandListWithCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands {
  CGFloat rowHeight = self.palette.slashCommandRowHeight;
  CGFloat padding = self.palette.space2;
  CGFloat spacing = commands.count > 1 ? self.palette.space2 * (commands.count - 1) : self.palette.space0;
  CGFloat height = (rowHeight * commands.count) + (padding * 2.0) + spacing;

  for (NSView *view in self.slashCommandListStack.arrangedSubviews.copy) {
    [self.slashCommandListStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  NSMutableArray<TLSlashCommandItemView *> *rows = [NSMutableArray arrayWithCapacity:commands.count];
  for (NSDictionary<NSString *, NSString *> *command in commands) {
    TLSlashCommandItemView *row = (TLSlashCommandItemView *)[self slashCommandRowWithCommand:command];
    row.tag = rows.count;
    [self.slashCommandListStack addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:rowHeight].active = YES;
    [row.widthAnchor constraintEqualToAnchor:self.slashCommandListStack.widthAnchor].active = YES;
    [rows addObject:row];
  }
  self.visibleSlashCommands = [commands copy];
  self.slashCommandRows = [rows copy];
  self.selectedSlashCommandIndex = -1;
  [self applySlashCommandListPalette];
  self.slashCommandListWidthConstraint.constant = [self slashCommandListWidthForCommands:commands];
  self.slashCommandListHeightConstraint.constant = height;
  self.slashCommandListView.hidden = NO;
  [self updateMessageScrollInsets];
}

- (void)setSelectedSlashCommandIndexAndUpdateRows:(NSInteger)selectedIndex {
  NSInteger boundedIndex = selectedIndex;
  if (boundedIndex < 0 || boundedIndex >= (NSInteger)self.slashCommandRows.count) {
    boundedIndex = -1;
  }
  self.selectedSlashCommandIndex = boundedIndex;
  [self.slashCommandRows enumerateObjectsUsingBlock:^(TLSlashCommandItemView *row,
                                                       NSUInteger index,
                                                       BOOL *stop) {
    row.selected = (NSInteger)index == boundedIndex;
  }];
}

- (BOOL)moveSlashCommandSelectionByOffset:(NSInteger)offset {
  NSInteger commandCount = (NSInteger)self.visibleSlashCommands.count;
  if (self.slashCommandListView.hidden || commandCount == 0) {
    return NO;
  }

  NSInteger nextIndex = self.selectedSlashCommandIndex;
  for (NSInteger attempt = 0; attempt < commandCount; attempt++) {
    nextIndex = nextIndex < 0 ? (offset < 0 ? commandCount - 1 : 0)
      : (nextIndex + offset + commandCount) % commandCount;
    if (self.slashCommandRows[(NSUInteger)nextIndex].enabled) {
      break;
    }
  }
  [self setSelectedSlashCommandIndexAndUpdateRows:nextIndex];
  return YES;
}

- (BOOL)performSelectedSlashCommand {
  NSInteger selectedIndex = self.selectedSlashCommandIndex;
  if (self.slashCommandListView.hidden || selectedIndex < 0 || selectedIndex >= (NSInteger)self.visibleSlashCommands.count) {
    return NO;
  }
  return [self performInputSuggestionAtIndex:(NSUInteger)selectedIndex];
}

- (BOOL)performInputSuggestionAtIndex:(NSUInteger)index {
  if (self.isSending || index >= self.visibleSlashCommands.count || !self.slashCommandRows[index].enabled) {
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
    [self openBrowserTabWithURL:URL];
    return YES;
  }
  if ([suggestion[@"kind"] isEqualToString:@"prompt"]) {
    self.promptTextView.string = suggestion[@"value"];
    [self hideSlashCommandList];
    [self sendMessage:self allowAutomaticRouting:NO];
    return YES;
  }
  return [self performSlashCommandIfNeededForPrompt:suggestion[@"command"]];
}

- (BOOL)performSlashCommandIfNeededForPrompt:(NSString *)prompt {
  return NO;
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

- (void)updateSlashCommandList {
  if (self.isSending || ![self isChatWorkspaceActive] || !self.messageInput.window || NSIsEmptyRect(self.messageInput.bounds)) {
    [self hideSlashCommandList];
    return;
  }

  NSArray<NSDictionary<NSString *, NSString *> *> *commands = [self slashCommandsMatchingPrompt:self.promptTextView.string ?: @""];
  if (commands.count == 0) {
    [self hideSlashCommandList];
    return;
  }

  [self showSlashCommandListWithCommands:commands];
  NSString *trimmedPrompt = [self.promptTextView.string
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmedPrompt.length > 1) {
    [self moveSlashCommandSelectionByOffset:1];
  }
}

- (void)hideSlashCommandList {
  if (!self.slashCommandListView.hidden || self.slashCommandListHeightConstraint.constant > self.palette.space0) {
    for (NSView *view in self.slashCommandListStack.arrangedSubviews.copy) {
      [self.slashCommandListStack removeArrangedSubview:view];
      [view removeFromSuperview];
    }
    self.slashCommandListView.hidden = YES;
    self.visibleSlashCommands = @[];
    self.slashCommandRows = @[];
    self.selectedSlashCommandIndex = -1;
    self.slashCommandListWidthConstraint.constant = self.palette.space0;
    self.slashCommandListHeightConstraint.constant = self.palette.space0;
    [self updateMessageScrollInsets];
  }
}

- (void)runSlashCommandFromItem:(id)sender {
  if (![sender isKindOfClass:TLSlashCommandItemView.class]) {
    return;
  }
  TLSlashCommandItemView *item = (TLSlashCommandItemView *)sender;
  [self performInputSuggestionAtIndex:(NSUInteger)item.tag];
}

- (void)showOnboardingDemoWindow:(id)sender {
  [self.hermesOnboardingWindowController.window close];
  self.hermesOnboardingWindowController = [[TLHermesOnboardingWindowController alloc]
    initWithPalette:self.palette token:self.settings.openRouterToken model:self.settings.selectedModel];
  __weak typeof(self) weakSelf = self;
  self.hermesOnboardingWindowController.startHandler = ^(NSString *token, NSString *model) {
    TalariaWindowController *strongSelf = weakSelf;
    if (!strongSelf) return;
    TLAppSettings *updated = [strongSelf.settings copy];
    updated.openRouterToken = token;
    updated.rememberOpenRouterToken = YES;
    updated.selectedModel = model;
    NSError *saveError = nil;
    TLAppSettings *saved = [strongSelf.database saveAppSettings:updated error:&saveError];
    if (!saved) {
      [strongSelf.hermesOnboardingWindowController finishWithError:saveError];
      return;
    }
    strongSelf.settings = saved;
    [strongSelf.agentOrchestrator createFreshHermesAgentWithProgress:^(NSString *text) {
      [strongSelf.hermesOnboardingWindowController appendProgress:text];
    } completion:^(TLAgentRecord *agent, NSError *installError) {
      if (!installError) {
        TLAppSettings *completed = [strongSelf.settings copy];
        completed.onboardingCompleted = YES;
        TLAppSettings *completedSettings = [strongSelf.database saveAppSettings:completed error:nil];
        if (completedSettings) strongSelf.settings = completedSettings;
        NSArray<TLAgentRecord *> *agents = [strongSelf.agentOrchestrator listAgents:nil];
        if (agents) strongSelf.agents = [agents mutableCopy];
        [strongSelf.agentsTableView reloadData];
      }
      [strongSelf.hermesOnboardingWindowController finishWithError:installError];
    }];
  };
  self.hermesOnboardingWindowController.closeHandler = ^{
    [weakSelf.window makeKeyAndOrderFront:nil];
  };
  [self.hermesOnboardingWindowController showFromWindow:self.window];
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

  [self.appStateManager removeWorkspaceTabWithKind:self.agentsTab.kind tabID:self.agentsTab.tabID];
  [[self contentViewForTab:self.agentsTab] removeFromSuperview];
  [self removeRuntimeForKind:self.agentsTab.kind tabID:self.agentsTab.tabID];
  self.agentsTab = nil;


  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)showDebug:(id)sender {
  if (self.widgetbookMode) {
    return;
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

  [self activateTabKind:TLWorkspaceTabKindDebug tabID:self.debugTab.tabID];
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openDebugTab:(id)sender {
  if (self.widgetbookMode || !self.debugTab) {
    return;
  }
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

  [self.appStateManager removeWorkspaceTabWithKind:self.debugTab.kind tabID:self.debugTab.tabID];
  [[self contentViewForTab:self.debugTab] removeFromSuperview];
  [self removeRuntimeForKind:self.debugTab.kind tabID:self.debugTab.tabID];
  self.debugTab = nil;
  [self updateWorkspaceMode];
  [self reloadWorkspaceTabs];
  [self updateControlStates];
}

- (void)openDebugTerminal:(id)sender {
  if (!self.debugTerminalWindowController) {
    self.debugTerminalWindowController = [[TLVMDebugTerminalWindowController alloc]
      initWithPalette:self.palette agentOrchestrator:self.agentOrchestrator];
  }
  [self.debugTerminalWindowController showFromWindow:self.window];
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
  nextContentView.hidden = ![self isWorkspaceTabActive:self.debugTab];
}

- (NSView *)buildDebugTabContent {
  TLThemePalette *palette = self.palette;
  TLTokenView *content = [[TLTokenView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  content.fillColor = palette.tabBackground;

  NSTextField *titleLabel = [self labelWithString:@"Debug" font:palette.titleFont color:palette.appText];
  NSTextField *subtitleLabel = [self labelWithString:@"Inspect the active agent VM from a private shell session."
                                                font:palette.bodyFont
                                               color:palette.textMuted];
  NSTextField *terminalLabel = [self labelWithString:@"VM terminal" font:palette.labelFont color:palette.labelText];
  NSTextField *terminalDescription = [self labelWithString:@"Open a terminal window for commands such as pwd, ls, cd, and cat. Commands run inside the VM, not on your Mac."
                                                     font:palette.bodyFont
                                                    color:palette.textMuted];
  terminalDescription.maximumNumberOfLines = 0;
  terminalDescription.lineBreakMode = NSLineBreakByWordWrapping;

  NSButton *openButton = [NSButton buttonWithTitle:@"Open VM terminal" target:self action:@selector(openDebugTerminal:)];
  openButton.translatesAutoresizingMaskIntoConstraints = NO;
  openButton.bezelStyle = NSBezelStyleRounded;
  openButton.controlSize = NSControlSizeLarge;
  openButton.font = palette.labelFont;
  openButton.bezelColor = palette.primaryActionSurface;
  openButton.contentTintColor = palette.primaryActionText;

  NSButton *closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDebugTab:)];
  closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  closeButton.bezelStyle = NSBezelStyleRounded;
  closeButton.controlSize = NSControlSizeLarge;
  closeButton.font = palette.labelFont;
  closeButton.bezelColor = palette.secondaryActionSurface;
  closeButton.contentTintColor = palette.secondaryActionText;

  TLTokenView *card = [[TLTokenView alloc] init];
  card.translatesAutoresizingMaskIntoConstraints = NO;
  card.fillColor = palette.controlSurface;
  card.cornerRadius = palette.radiusMedium;
  for (NSView *view in @[terminalLabel, terminalDescription, openButton]) {
    [card addSubview:view];
  }
  for (NSView *view in @[titleLabel, subtitleLabel, closeButton, card]) {
    [content addSubview:view];
  }

  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:palette.space12],
    [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:palette.space11],
    [closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [closeButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
    [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth],
    [closeButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
    [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeButton.leadingAnchor constant:-palette.space8],
    [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:palette.space2],
    [card.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [card.trailingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
    [card.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:palette.space10],
    [terminalLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:palette.space8],
    [terminalLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:palette.space8],
    [terminalDescription.leadingAnchor constraintEqualToAnchor:terminalLabel.leadingAnchor],
    [terminalDescription.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-palette.space8],
    [terminalDescription.topAnchor constraintEqualToAnchor:terminalLabel.bottomAnchor constant:palette.space3],
    [openButton.leadingAnchor constraintEqualToAnchor:terminalLabel.leadingAnchor],
    [openButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-palette.space8],
    [openButton.topAnchor constraintEqualToAnchor:terminalDescription.bottomAnchor constant:palette.space6],
    [openButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-palette.space8],
    [openButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth],
    [openButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
  ]];
  return content;
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
    @[@"guest", @"Guest"],
    @[@"runtime", @"Runtime"],
    @[@"status", @"Status"],
    @[@"vm", @"VM directory"],
  ];
  for (NSArray<NSString *> *columnSpec in columns) {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columnSpec[0]];
    column.title = columnSpec[1];
    column.resizingMask = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    column.width = [column.identifier isEqualToString:@"vm"] ? palette.controlMinWidth * 4.0 : palette.controlMinWidth * 1.4;
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
  NSString *name = [NSString stringWithFormat:@"Agent %lu", (unsigned long)self.agents.count + 1];
  NSError *error = nil;
  TLAgentRecord *agent = [self.agentOrchestrator createAgentWithName:name error:&error];
  if (!agent) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not create agent."];
  }

  [self refreshAgents];
  if (agent) {
    [self selectAgentWithID:agent.agentID];
  }
}

- (void)startSelectedAgent:(id)sender {
  TLAgentRecord *agent = [self selectedAgent];
  if (!agent) {
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

  TLAgentRecord *agent = self.agents[(NSUInteger)row];
  NSString *value = [self tableValueForAgent:agent columnIdentifier:identifier];
  cell.textField.stringValue = value;
  cell.textField.font = self.palette.bodyFont;
  cell.textField.textColor = [agent.status isEqualToString:TLAgentStatusError] && [identifier isEqualToString:@"status"]
    ? self.palette.thinkingText
    : self.palette.appText;
  cell.textField.toolTip = agent.lastError.length > 0 ? agent.lastError : value;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (notification.object == self.agentsTableView) {
    [self updateAgentControlStates];
  }
}

- (NSString *)tableValueForAgent:(TLAgentRecord *)agent columnIdentifier:(NSString *)identifier {
  if ([identifier isEqualToString:@"name"]) {
    return agent.name;
  }
  if ([identifier isEqualToString:@"guest"]) {
    return TLAgentDisplayGuestKind(agent.guestKind);
  }
  if ([identifier isEqualToString:@"runtime"]) {
    return TLAgentDisplayRuntime(agent.runtime);
  }
  if ([identifier isEqualToString:@"status"]) {
    return TLAgentDisplayStatus(agent.status);
  }
  if ([identifier isEqualToString:@"vm"]) {
    return agent.vmDirectory;
  }

  return @"";
}

- (void)updateAgentControlStates {
  BOOL controlsAllowed = !self.isSending && !self.widgetbookMode && self.agentsTab != nil;
  TLAgentRecord *agent = [self selectedAgent];
  BOOL hasAgent = agent != nil;
  BOOL starting = [agent.status isEqualToString:TLAgentStatusStarting];
  BOOL running = [agent.status isEqualToString:TLAgentStatusRunning];
  BOOL stopping = [agent.status isEqualToString:TLAgentStatusStopping];
  BOOL busy = starting || stopping;

  self.createAgentButton.enabled = controlsAllowed;
  self.startAgentButton.enabled = controlsAllowed && hasAgent && !running && !busy;
  self.stopAgentButton.enabled = controlsAllowed && hasAgent && running;
  self.deleteAgentButton.enabled = controlsAllowed && hasAgent && !running && !busy;
  self.closeAgentsButton.enabled = controlsAllowed;

  [self updateButtonAlpha:self.createAgentButton];
  [self updateButtonAlpha:self.startAgentButton];
  [self updateButtonAlpha:self.stopAgentButton];
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
  controller.closeHandler = ^{ [weakSelf closeSettingsTab:weakSelf]; };
  controller.onboardingHandler = ^{ [weakSelf showOnboardingDemoWindow:weakSelf]; };
  controller.errorHandler = ^(NSString *message) { [weakSelf presentErrorMessage:message]; };
  controller.settingsSavedHandler = ^(TLAppSettings *settings) {
    TalariaWindowController *windowController = weakSelf;
    windowController.settings = settings;
    windowController.palette = [TLThemePalette paletteForPreference:settings.theme];
    [windowController closeSettingsTab:windowController];
    [windowController applyTheme];
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
  if (commandSelector == @selector(moveUp:)) {
    return [self moveSlashCommandSelectionByOffset:-1];
  }
  if (commandSelector == @selector(moveDown:)) {
    return [self moveSlashCommandSelectionByOffset:1];
  }
  if (commandSelector == @selector(insertNewline:)) {
    BOOL shiftPressed = (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
    if (!shiftPressed) {
      if ([self performSelectedSlashCommand]) return YES;
      [self sendMessage:textView];
      return YES;
    }
  }

  return NO;
}

- (void)textDidChange:(NSNotification *)notification {

  [self.messageInput recalculateHeight];
  [self updateMessageScrollInsets];
  [self updateSlashCommandList];
  [self updateControlStates];
}

- (void)pinMessageRowToStackWidth:(NSView *)row {
  static NSString *const TLMessageRowWidthConstraintIdentifier = @"TLMessageRowWidthConstraint";

  for (NSLayoutConstraint *constraint in row.constraints) {
    if ([constraint.identifier isEqualToString:TLMessageRowWidthConstraintIdentifier]) {
      return;
    }
  }

  NSLayoutConstraint *constraint = [row.widthAnchor constraintEqualToAnchor:self.messageStack.widthAnchor];
  constraint.identifier = TLMessageRowWidthConstraintIdentifier;
  constraint.active = YES;
}

- (void)addMessageRowToStack:(NSView *)row {
  [self.messageStack addView:row inGravity:NSStackViewGravityTop];
}

- (BOOL)isUserMessageAtIndex:(NSUInteger)index {
  if (index >= self.messages.count) {
    return NO;
  }

  TLChatMessage *message = self.messages[index];
  return [message.role isEqualToString:TLRoleUser];
}

- (BOOL)showsOutgoingTailForMessageAtIndex:(NSUInteger)index {
  return [self isUserMessageAtIndex:index] && ![self isUserMessageAtIndex:index + 1];
}

- (CGFloat)messageStackSpacingAfterMessageAtIndex:(NSUInteger)index {
  if ([self isUserMessageAtIndex:index] && [self isUserMessageAtIndex:index + 1]) {
    return self.palette.space3;
  }

  return self.palette.messageVerticalSpacing;
}

- (void)removeArrangedMessageRowIfNeeded:(NSView *)row {
  if ([self.messageStack.arrangedSubviews containsObject:row]) {
    [self.messageStack removeView:row];
  }
}

- (void)detachMessageRowFromStack:(NSView *)row {
  [self removeArrangedMessageRowIfNeeded:row];
  if (row.superview) {
    [row removeFromSuperview];
  }
}

- (void)renderMessages {
  [self renderMessagesScrollingToBottom:YES];
}

- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom {
  NSPoint previousScrollOrigin = self.messageScrollView.contentView.bounds.origin;
  for (TLChatMessage *cachedMessage in self.messageRowViews.keyEnumerator.allObjects) {
    if ([self.messages indexOfObjectIdenticalTo:cachedMessage] == NSNotFound) {
      NSView *staleRow = [self.messageRowViews objectForKey:cachedMessage];
      [self detachMessageRowFromStack:staleRow];
      [self.messageRowViews removeObjectForKey:cachedMessage];
      [self.messageRowSignatures removeObjectForKey:cachedMessage];
    }
  }
  NSArray<NSView *> *previousRows = self.messageStack.arrangedSubviews.copy;
  for (NSView *view in previousRows) {
    [self removeArrangedMessageRowIfNeeded:view];
  }

  if (self.isLoading || self.errorMessage.length > 0 || self.messages.count == 0) {
    [self resetMessageRowCache];
    for (NSView *view in previousRows) {
      [self detachMessageRowFromStack:view];
    }
    NSView *emptyState = [self emptyStateView];
    [self addMessageRowToStack:emptyState];
    [self pinMessageRowToStackWidth:emptyState];
    return;
  }

  NSMutableSet<NSView *> *renderedRows = [NSMutableSet setWithCapacity:self.messages.count];
  for (NSUInteger index = 0; index < self.messages.count; index++) {
    TLChatMessage *message = self.messages[index];
    BOOL showsOutgoingTail = [self showsOutgoingTailForMessageAtIndex:index];
    NSView *row = [self cachedRowForMessage:message showsOutgoingTail:showsOutgoingTail];
    [renderedRows addObject:row];
    [self addMessageRowToStack:row];
    [self pinMessageRowToStackWidth:row];
    if ([self messageShowsAWSOutageIntent:message]) {
      [self.messageStack setCustomSpacing:self.palette.space8 afterView:row];
      NSView *intentWidget = [self AWSOutageIntentWidget];
      [renderedRows addObject:intentWidget];
      [self addMessageRowToStack:intentWidget];
      [self pinMessageRowToStackWidth:intentWidget];
      [self.messageStack setCustomSpacing:[self messageStackSpacingAfterMessageAtIndex:index] afterView:intentWidget];
    } else {
      [self.messageStack setCustomSpacing:[self messageStackSpacingAfterMessageAtIndex:index] afterView:row];
    }
  }

  for (NSView *view in self.messageStack.subviews.copy) {
    if (![renderedRows containsObject:view]) {
      [view removeFromSuperview];
    }
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateMessageScrollInsets];
    [self.messageDocumentView layoutSubtreeIfNeeded];
    if (scrollToBottom) {
      NSRect bottom = NSMakeRect(0.0, MAX(0.0, self.messageDocumentView.bounds.size.height - 1.0), 1.0, 1.0);
      [self.messageDocumentView scrollRectToVisible:bottom];
    } else {
      CGFloat maximumY = MAX(0.0, NSHeight(self.messageDocumentView.bounds) - NSHeight(self.messageScrollView.contentView.bounds));
      [self.messageScrollView.contentView scrollToPoint:NSMakePoint(previousScrollOrigin.x, MIN(previousScrollOrigin.y, maximumY))];
      [self.messageScrollView reflectScrolledClipView:self.messageScrollView.contentView];
    }
  });
}

- (BOOL)messageShowsAWSOutageIntent:(TLChatMessage *)message {
  return [self.activeChat.title isEqualToString:TLAWSOutageChatTitle] &&
    [message.role isEqualToString:TLRoleAssistant] &&
    [message.content containsString:@"AWS is reporting an outage in the Oregon region."];
}

- (NSView *)AWSOutageIntentWidget {
  NSView *row = [[NSView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;

  TLTokenView *widget = [[TLTokenView alloc] init];
  widget.translatesAutoresizingMaskIntoConstraints = NO;
  widget.fillColor = self.palette.assistantMessageSurface;
  widget.borderColor = self.palette.transparentSurface;
  widget.borderEdges = TLBorderEdgeNone;
  widget.cornerRadius = self.palette.space9;
  [row addSubview:widget];

  NSStackView *content = [[NSStackView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  content.orientation = NSUserInterfaceLayoutOrientationVertical;
  content.alignment = NSLayoutAttributeLeading;
  content.distribution = NSStackViewDistributionFill;
  content.spacing = self.palette.space4;
  [widget addSubview:content];

  NSTextField *titleLabel = [self labelWithString:@"Intent"
                                             font:self.palette.smallFont
                                            color:self.palette.textMuted];
  NSTextField *intentLabel = [self wrappingLabelWithString:TLAWSOutageIntent
                                                      font:self.palette.messageBodyFont
                                                     color:self.palette.assistantMessageText];
  intentLabel.preferredMaxLayoutWidth = self.palette.messageMaxWidth * 0.5;

  TLGlassButton *sendButton = [[TLGlassButton alloc] initWithUsesGlassEffect:YES];
  sendButton.palette = self.palette;
  sendButton.image = [NSImage imageWithSystemSymbolName:@"arrow.up"
                               accessibilityDescription:@"Send intent"];
  sendButton.title = @"send";
  sendButton.font = self.palette.smallFont;
  sendButton.contentTintColor = self.palette.userMessageText;
  sendButton.glassTintColor = self.palette.userMessageSurface;
  sendButton.glassHoverTintColor = self.palette.blue600;
  sendButton.target = self;
  sendButton.action = @selector(sendAWSOutageIntent:);
  sendButton.toolTip = @"Send intent";

  [content addArrangedSubview:titleLabel];
  [content addArrangedSubview:intentLabel];
  [content setCustomSpacing:self.palette.space6 afterView:intentLabel];
  [content addArrangedSubview:sendButton];

  CGFloat inset = self.palette.space6;
  CGFloat buttonHeight = self.palette.space11 + self.palette.space3;
  NSLayoutConstraint *widgetWidth = [widget.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:0.62];
  widgetWidth.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    [widget.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [widget.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
    [widget.topAnchor constraintEqualToAnchor:row.topAnchor],
    [widget.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    widgetWidth,
    [content.leadingAnchor constraintEqualToAnchor:widget.leadingAnchor constant:inset],
    [content.trailingAnchor constraintEqualToAnchor:widget.trailingAnchor constant:-inset],
    [content.topAnchor constraintEqualToAnchor:widget.topAnchor constant:inset],
    [content.bottomAnchor constraintEqualToAnchor:widget.bottomAnchor constant:-inset],
    [titleLabel.widthAnchor constraintLessThanOrEqualToAnchor:content.widthAnchor],
    [intentLabel.widthAnchor constraintEqualToAnchor:content.widthAnchor],
    [sendButton.heightAnchor constraintEqualToConstant:buttonHeight],
  ]];

  return row;
}

- (void)updateMessageScrollInsets {
  [self.messageInput.superview layoutSubtreeIfNeeded];
  CGFloat inputHeight = NSHeight(self.messageInput.frame) > 0.0 ? NSHeight(self.messageInput.frame) : self.palette.composerButtonHeight;
  CGFloat slashCommandListHeight = (!self.slashCommandListView.hidden && self.slashCommandListHeightConstraint.constant > self.palette.space0)
    ? self.slashCommandListHeightConstraint.constant + self.palette.space5
    : self.palette.space0;
  CGFloat bottomClearance = inputHeight + slashCommandListHeight + self.palette.space10 + self.palette.space8;
  self.messageScrollView.contentInsets = NSEdgeInsetsMake(self.palette.space0,
                                                          self.palette.space0,
                                                          self.palette.space0,
                                                          self.palette.space0);
  self.messageStackMinimumBottomConstraint.constant = -bottomClearance;
  self.messageStackBottomConstraint.constant = -bottomClearance;
  [self.messageDocumentView setNeedsLayout:YES];
}

- (NSView *)cachedRowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)showsOutgoingTail {
  NSString *signature = [self rowSignatureForMessage:message showsOutgoingTail:showsOutgoingTail];
  NSView *row = [self.messageRowViews objectForKey:message];
  NSString *previousSignature = [self.messageRowSignatures objectForKey:message];

  if (row && [previousSignature isEqualToString:signature]) {
    return row;
  }

  if (row) {
    [self detachMessageRowFromStack:row];
  }

  row = [self rowForMessage:message showsOutgoingTail:showsOutgoingTail];
  [self.messageRowViews setObject:row forKey:message];
  [self.messageRowSignatures setObject:signature forKey:message];
  return row;
}

- (NSString *)rowSignatureForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)showsOutgoingTail {
  BOOL user = [message.role isEqualToString:TLRoleUser];
  BOOL hasResponseContent = message.content.length > 0;
  BOOL showThinking = !user && !hasResponseContent && message.thinking.length > 0;
  NSString *mode = showThinking ? @"thinking" : @"content";
  NSString *displayText = showThinking
    ? (message.thinking ?: @"")
    : (hasResponseContent ? message.content : ([message.role isEqualToString:TLRoleAssistant] ? @"..." : @""));
  if ([self messageShowsAWSOutageIntent:message]) {
    displayText = TLAWSOutageAgentMessage;
  }
  CGFloat layoutWidth = self.messageInputWidthConstraint.constant > 0.0
    ? self.messageInputWidthConstraint.constant
    : self.palette.messageInputMaxWidth;

  return [NSString stringWithFormat:@"%@\n--TLROW--\n%@\n--TLROW--\n%.0f\n--TLROW--\n%@\n--TLROW--\n%@",
                                    message.role ?: @"",
                                    mode,
                                    layoutWidth,
                                    showsOutgoingTail ? @"tail" : @"body",
                                    displayText ?: @""];
}

- (void)resetMessageRowCache {
  for (NSView *view in self.messageRowViews.objectEnumerator) {
    [self detachMessageRowFromStack:view];
  }
  self.messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
  self.messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
}

- (NSView *)emptyStateView {
  NSView *view = [[NSView alloc] init];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [view.heightAnchor constraintGreaterThanOrEqualToConstant:360.0].active = YES;

  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeCenterX;
  stack.spacing = self.palette.space6;
  [view addSubview:stack];

  if (self.isLoading) {
    [stack addArrangedSubview:[self labelWithString:@"Loading chats" font:self.palette.emptyTitleFont color:self.palette.appText]];
  } else if (self.errorMessage.length > 0) {
    [stack addArrangedSubview:[self labelWithString:self.errorMessage font:self.palette.emptyTitleFont color:self.palette.appText]];
  }

  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:view.leadingAnchor constant:24.0],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-24.0],
  ]];

  return view;
}

- (NSView *)rowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)showsOutgoingTail {
  BOOL user = [message.role isEqualToString:TLRoleUser];
  BOOL drawsOutgoingTail = user && showsOutgoingTail;
  NSView *row = [[NSView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [row setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
  [row setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

  TLMessageBubbleView *bubble = [[TLMessageBubbleView alloc] init];
  bubble.translatesAutoresizingMaskIntoConstraints = NO;
  bubble.palette = self.palette;
  bubble.drawsOutgoingTail = drawsOutgoingTail;
  bubble.fillColor = user ? self.palette.userMessageSurface : self.palette.transparentSurface;
  bubble.borderColor = self.palette.transparentSurface;
  bubble.borderEdges = TLBorderEdgeNone;
  bubble.borderWidth = self.palette.borderWidth;
  bubble.cornerRadius = user ? self.palette.space9 : self.palette.space0;
  bubble.wantsLayer = YES;
  bubble.layer.shadowColor = TLCGColor(self.palette.messageShadow);
  bubble.layer.shadowOpacity = user ? (self.palette.dark ? 0.24 : 0.07) : 0.0;
  bubble.layer.shadowRadius = user ? self.palette.space8 : self.palette.space0;
  bubble.layer.shadowOffset = NSMakeSize(self.palette.space0, user ? -self.palette.space2 : self.palette.space0);
  [bubble setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
  [bubble setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];

  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeWidth;
  stack.distribution = NSStackViewDistributionFill;
  stack.spacing = self.palette.space5;
  [stack setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
  [stack setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                  forOrientation:NSLayoutConstraintOrientationVertical];
  [bubble addSubview:stack];

  CGFloat widthMultiplier = user ? self.palette.userMessageMaxWidthMultiplier : self.palette.assistantMessageMaxWidthMultiplier;
  NSColor *textColor = user ? self.palette.userMessageText : self.palette.assistantMessageText;
  NSTextField *contentLabel = nil;
  CGFloat userLeadingInset = self.palette.space0;
  CGFloat userTrailingInset = self.palette.space0;
  CGFloat userTopInset = self.palette.space0;
  CGFloat userBottomInset = self.palette.space0;
  CGFloat userTextMaxWidth = self.palette.messageInputMaxWidth;
  CGFloat availableMessageWidth = self.messageInputWidthConstraint.constant > 0.0
    ? self.messageInputWidthConstraint.constant
    : self.palette.messageInputMaxWidth;

  BOOL hasResponseContent = message.content.length > 0;
  BOOL showThinking = !user && !hasResponseContent && message.thinking.length > 0;
  if (showThinking) {
    [stack addArrangedSubview:[self labelWithString:@"Thinking"
                                               font:self.palette.roleFont
                                              color:self.palette.thinkingText]];
    [stack addArrangedSubview:[self markdownViewWithString:message.thinking
                                                  textColor:self.palette.thinkingText
                                                   baseFont:self.palette.smallFont]];
  } else if (user) {
    NSString *content = hasResponseContent ? message.content : @"";
    TLUserMessageBubbleLayout userLayout = TLUserMessageBubbleLayoutForContent(content,
                                                                               self.palette,
                                                                               availableMessageWidth,
                                                                               widthMultiplier,
                                                                               drawsOutgoingTail);
    userLeadingInset = userLayout.leadingInset;
    userTrailingInset = userLayout.trailingInset;
    userTopInset = userLayout.topInset;
    userBottomInset = userLayout.bottomInset;
    userTextMaxWidth = userLayout.textMaxWidth;
    bubble.rendersAsPill = userLayout.rendersAsPill;
    bubble.outgoingTailHorizontalOffset = userLayout.tailHorizontalOffset;
    contentLabel = [self wrappingLabelWithString:content
                                            font:self.palette.messageBodyFont
                                           color:textColor];
    contentLabel.preferredMaxLayoutWidth = userTextMaxWidth;
    [contentLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [contentLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [stack addArrangedSubview:contentLabel];
  } else {
    NSString *content = hasResponseContent ? message.content : @"...";
    if ([self messageShowsAWSOutageIntent:message]) {
      content = TLAWSOutageAgentMessage;
      NSView *leadingSpacer = [[NSView alloc] init];
      leadingSpacer.translatesAutoresizingMaskIntoConstraints = NO;
      CGFloat lineHeight = ceil(self.palette.messageBodyFont.ascender -
                                self.palette.messageBodyFont.descender +
                                self.palette.messageBodyFont.leading);
      [leadingSpacer.heightAnchor constraintEqualToConstant:lineHeight * 3.0].active = YES;
      [stack addArrangedSubview:leadingSpacer];
    }
    [stack addArrangedSubview:[self markdownViewWithString:content textColor:textColor baseFont:self.palette.messageBodyFont]];
  }

  [row addSubview:bubble];
  NSLayoutConstraint *assistantWidth = [bubble.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:widthMultiplier];
  assistantWidth.priority = NSLayoutPriorityDefaultHigh + 1.0;

  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
    [bubble.topAnchor constraintEqualToAnchor:row.topAnchor],
    [bubble.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [bubble.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:widthMultiplier],
    [stack.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:user ? userLeadingInset : self.palette.space0],
    [stack.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:user ? -userTrailingInset : self.palette.space0],
    [stack.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:user ? userTopInset : self.palette.space0],
    [stack.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:user ? -userBottomInset : self.palette.space0],
  ]];
  if (contentLabel) {
    [constraints addObject:[contentLabel.widthAnchor constraintLessThanOrEqualToConstant:userTextMaxWidth]];
  }
  if (!user) {
    [constraints addObject:assistantWidth];
  }

  if (user) {
    [constraints addObject:[bubble.trailingAnchor constraintEqualToAnchor:row.trailingAnchor]];
    [constraints addObject:[bubble.leadingAnchor constraintGreaterThanOrEqualToAnchor:row.leadingAnchor]];
  } else {
    [constraints addObject:[bubble.leadingAnchor constraintEqualToAnchor:row.leadingAnchor]];
    [constraints addObject:[bubble.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
  }

  [NSLayoutConstraint activateConstraints:constraints];
  return row;
}

- (NSView *)markdownViewWithString:(NSString *)string textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont {
  TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:self.palette];
  __weak typeof(self) weakSelf = self;
  renderer.linkHandler = ^(NSURL *URL, NSEventModifierFlags modifierFlags) {
    [weakSelf handleLinkURL:URL modifierFlags:modifierFlags];
  };
  return [renderer viewForMarkdown:string ?: @"" textColor:textColor baseFont:baseFont];
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

  return self.palette.trafficLightLeftInset + self.palette.trafficLightReservedWidth - self.palette.space5 + self.sidebarToggleButton.intrinsicContentSize.width + self.palette.space0;
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

  [self.workspaceTabsController updateTabWidthsForAvailableWidth:[self availableTabStripWidthForLeadingConstant:self.tabStackLeadingConstraint.constant]];
}

- (CGFloat)contentLeadingPadding {
  return self.sidebarVisible ? self.palette.space3 : self.palette.space4;
}

- (CGFloat)contentLeadingOffsetForSidebarWidth:(CGFloat)sidebarWidth {
  return sidebarWidth + [self contentLeadingPadding];
}

- (CGFloat)sidebarActionStackHeight {
  return self.sidebarUserButton.intrinsicContentSize.height;
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
  if (self.messageInputWidthConstraint) {
    CGFloat targetInputWidth = [self messageInputWidthForWindowWidth:windowWidth
                                                         sidebarWidth:targetSidebarWidth
                                                contentLeadingPadding:targetContentLeading];
    self.messageInputWidthConstraint.constant = targetInputWidth;
    [self applyBrowserAddressInputWidth:targetInputWidth];
  }
  [self.workspaceTabsController updateTabWidthsForAvailableWidth:targetTabAvailableWidth];
}

- (void)toggleSidebar:(id)sender {
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
    owner.messageInputWidthConstraint.constant = startInputWidth + (targetInputWidth - startInputWidth) * progress;
    owner.sidebarView.alphaValue = startAlpha + ((hideAfterLayout ? 0 : 1) - startAlpha) * progress;
    [owner applyBrowserAddressInputWidth:owner.messageInputWidthConstraint.constant];
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
  NSString *title = chat.title.length > 0 ? chat.title : @"New chat";
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
  if (tab.kind == TLWorkspaceTabKindSettings) runtime.featureController = self.settingsTabController;
  self.workspaceTabRuntimes[TLWorkspaceTabRuntimeKey(tab.kind, tab.tabID)] = runtime;
}

- (void)removeRuntimeForKind:(TLWorkspaceTabKind)kind tabID:(NSInteger)tabID {
  [self.workspaceTabRuntimes removeObjectForKey:TLWorkspaceTabRuntimeKey(kind, tabID)];
}

- (NSView *)contentViewForTab:(TLWorkspaceTab *)tab {
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
  NSString *scheme = URL.scheme.lowercaseString;
  return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
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

- (BOOL)isChatWorkspaceActive {
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;
  return snapshot.activeTabKind == TLWorkspaceTabKindChat && self.activeChat && snapshot.activeTabID == self.activeChat.chatID;
}

- (void)addWorkspaceContentView:(NSView *)contentView {
  if (!contentView) {
    return;
  }
  if (contentView.superview == self.contentHost) {
    return;
  }
  [contentView removeFromSuperview];

  contentView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentHost addSubview:contentView];
  [NSLayoutConstraint activateConstraints:@[
    [contentView.leadingAnchor constraintEqualToAnchor:self.contentHost.leadingAnchor],
    [contentView.trailingAnchor constraintEqualToAnchor:self.contentHost.trailingAnchor],
    [contentView.topAnchor constraintEqualToAnchor:self.contentHost.topAnchor],
    [contentView.bottomAnchor constraintEqualToAnchor:self.contentHost.bottomAnchor],
  ]];
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
    return chat.title.length > 0 ? chat.title : @"New chat";
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
  return [self workspaceTabs];
}

- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller isTabActive:(TLWorkspaceTab *)tab {
  return [self isWorkspaceTabActive:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayTitleForTab:(TLWorkspaceTab *)tab {
  return [self displayTitleForWorkspaceTab:tab];
}

- (NSImage *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayImageForTab:(TLWorkspaceTab *)tab {
  return [self displayImageForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayIconForTab:(TLWorkspaceTab *)tab {
  return [self displayIconForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displaySystemIconNameForTab:(TLWorkspaceTab *)tab {
  return [self displaySystemIconNameForWorkspaceTab:tab];
}

- (NSString *)workspaceTabsController:(TLWorkspaceTabsController *)controller displayToolTipForTab:(TLWorkspaceTab *)tab {
  return [self displayToolTipForWorkspaceTab:tab];
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller openActionForTab:(TLWorkspaceTab *)tab {
  return [self runtimeForTab:tab].openAction;
}

- (SEL)workspaceTabsController:(TLWorkspaceTabsController *)controller closeActionForTab:(TLWorkspaceTab *)tab {
  return [self runtimeForTab:tab].closeAction;
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
  [self.appStateManager moveWorkspaceTabWithKind:tab.kind tabID:tab.tabID toIndex:index];
  // The drag controller clears its temporary translations before returning.
  // Apply the committed order now so it never paints the pre-drag positions.
  [self renderWorkspaceTabs];
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
    case TLWorkspaceTabKindDebug:
      return self.appStateManager.snapshot.activeTabKind == TLWorkspaceTabKindDebug &&
        self.debugTab &&
        self.appStateManager.snapshot.activeTabID == self.debugTab.tabID;
  }
}

- (void)updateWorkspaceMode {
  self.chatWorkspace.hidden = ![self isChatWorkspaceActive];
  self.historyPanelController.panelView.hidden = ![self isHistoryScreenActive];
  TLAppStateSnapshot *snapshot = self.appStateManager.snapshot;
  [self contentViewForTab:self.settingsTab].hidden = !(snapshot.activeTabKind == TLWorkspaceTabKindSettings);
  [self contentViewForTab:self.agentsTab].hidden = !(snapshot.activeTabKind == TLWorkspaceTabKindAgents);
  [self contentViewForTab:self.debugTab].hidden = !(snapshot.activeTabKind == TLWorkspaceTabKindDebug);

  for (TLWorkspaceTab *tab in [self workspaceTabsOfKind:TLWorkspaceTabKindBrowser]) {
    [self contentViewForTab:tab].hidden = !(snapshot.activeTabKind == TLWorkspaceTabKindBrowser && snapshot.activeTabID == tab.tabID);
  }

  if ([self isHistoryScreenActive]) {
    [self.historyPanelController deselectAll];
  }
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
  self.sidebarToggleButton.contentTintColor = foreground;
  self.createChatButton.palette = self.palette;
  self.createChatButton.contentTintColor = foreground;
  [self styleSidebarActionButtons];
}

- (void)styleSidebarActionButtons {
  self.sidebarActionStack.spacing = self.palette.space0;
  [self updateSidebarContentInsets];
  self.sidebarActionStackHeightConstraint.constant = [self sidebarActionStackHeight];

  self.sidebarUserButton.palette = self.palette;
  self.sidebarUserButton.displayName = @"Yaroslav";
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
  TLThemePreference themePreference = self.settings.theme;
  NSAppearance *requestedAppearance = nil;
  if (themePreference == TLThemePreferenceLight) {
    requestedAppearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
  } else if (themePreference == TLThemePreferenceDark) {
    requestedAppearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  }

  self.window.appearance = requestedAppearance;
  NSAppearance *effectiveAppearance = requestedAppearance ?: self.window.effectiveAppearance;
  self.palette = [TLThemePalette paletteForPreference:themePreference effectiveAppearance:effectiveAppearance];
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
  self.contentHost.layer.masksToBounds = YES;
  [self applyContentTopLeftCornerRadius:self.palette.space5];
  self.sidebarView.fillColor = self.palette.appBackground;
  [self applySidebarTilePalette];
  [self applySidebarInboxPalette];
  [self.historyPanelController applyPalette:self.palette];
  self.topbar.fillColor = self.palette.appBackground;
  self.topbar.borderColor = self.palette.topbarBorder;
  self.topbar.borderEdges = TLBorderEdgeNone;
  self.messagesBackground.fillColor = self.palette.tabBackground;
  [self.screensaverView updateBackgroundColor:self.palette.messagesSurface artColor:self.palette.textMuted];
  self.messageStack.spacing = self.palette.messageVerticalSpacing;
  self.messageInput.palette = self.palette;
  [self.onboardingDemoWindowController updatePalette:self.palette];
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
  [self.debugTerminalWindowController updatePalette:self.palette];
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
  [self.notchOverlayController updatePalette:self.palette];
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
  for (NSView *view in self.sidebarTileGrid.arrangedSubviews) {
    if ([view isKindOfClass:TLIconTileView.class]) {
      ((TLIconTileView *)view).palette = self.palette;
    }
  }
  [self styleSidebarActionButtons];
}

- (void)applySidebarInboxPalette {
  self.sidebarInboxStack.spacing = self.palette.space0;
  [self.sidebarInboxStack setCustomSpacing:self.palette.space5 afterView:self.sidebarShortcutsView];
  self.sidebarShortcutsView.palette = self.palette;
  self.sidebarInboxPaneView.palette = self.palette;

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

- (void)openFromNotchOverlay:(id)sender {
  [NSApp unhide:self];
  [self showWindow:sender];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)handleFileURLsDroppedOnNotch:(NSArray<NSURL *> *)fileURLs {
  [self openFromNotchOverlay:self.notchOverlayController];
  if (fileURLs.count == 0) {
    return;
  }

  NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:fileURLs.count];
  for (NSURL *fileURL in fileURLs) {
    if (fileURL.isFileURL && fileURL.path.length > 0) {
      [paths addObject:fileURL.path];
    }
  }
  if (paths.count == 0) {
    return;
  }

  NSMutableString *droppedFilesText = [NSMutableString stringWithString:paths.count == 1 ? @"Dropped file:" : @"Dropped files:"];
  for (NSString *path in paths) {
    [droppedFilesText appendFormat:@"\n- %@", path];
  }

  NSString *existingPrompt = self.promptTextView.string ?: @"";
  NSString *separator = [existingPrompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0 ? @"\n\n" : @"";
  self.promptTextView.string = [NSString stringWithFormat:@"%@%@%@", existingPrompt, separator, droppedFilesText];
  [self updateControlStates];
  [self.window makeFirstResponder:self.promptTextView];
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

- (void)updateControlStates {
  [self.messageInput recalculateHeight];
  [self updateMessageScrollInsets];

  if (self.widgetbookMode) {
    self.createChatButton.enabled = NO;
    self.sidebarToggleButton.enabled = NO;
    self.sidebarUserButton.enabled = NO;
    self.sendButton.enabled = NO;
    self.historyPanelController.enabled = NO;
    self.promptTextView.editable = NO;
    self.promptTextView.selectable = YES;
    self.createChatButton.alphaValue = self.palette.disabledOpacity;
    self.sidebarToggleButton.alphaValue = self.palette.disabledOpacity;
    self.sendButton.alphaValue = self.palette.disabledOpacity;
    [self styleSidebarActionButtons];
    [self.workspaceTabsController setControlsEnabled:NO disabledOpacity:self.palette.disabledOpacity];
    [self updateAgentControlStates];
    return;
  }

  NSString *prompt = [self.promptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  BOOL chatActive = [self isChatWorkspaceActive];
  if (!chatActive || prompt.length == 0 || self.isSending) {
    [self hideSlashCommandList];
  }
  self.createChatButton.enabled = YES;
  self.sidebarToggleButton.enabled = YES;
  self.sidebarUserButton.enabled = YES;
  self.sendButton.enabled = !self.isSending && chatActive && prompt.length > 0;
  self.historyPanelController.enabled = YES;
  self.promptTextView.editable = chatActive;
  self.promptTextView.selectable = YES;

  self.createChatButton.alphaValue = self.createChatButton.enabled ? 1.0 : self.palette.disabledOpacity;
  self.sidebarToggleButton.alphaValue = self.sidebarToggleButton.enabled ? 1.0 : self.palette.disabledOpacity;
  self.sendButton.alphaValue = self.sendButton.enabled ? 1.0 : self.palette.disabledOpacity;
  [self styleSidebarActionButtons];
  [self.workspaceTabsController setControlsEnabled:YES disabledOpacity:self.palette.disabledOpacity];
  [self updateAgentControlStates];
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectChatID:(NSInteger)chatID {
  if (self.widgetbookMode) {
    [self selectActiveChatInHistory];
    return;
  }
  if (![self isHistoryScreenActive]) {
    return;
  }

  [self loadChatWithID:chatID];
}

- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteChatID:(NSInteger)chatID {
  if (self.isSending || self.widgetbookMode || chatID <= 0) {
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

    [weakSelf deleteChatWithID:chatID];
  }];
}

- (void)deleteChatWithID:(NSInteger)chatID {
  if (self.isSending || self.widgetbookMode || chatID <= 0) {
    return;
  }

  BOOL deletingLoadedChat = self.activeChat && self.activeChat.chatID == chatID;
  NSUInteger closedIndex = [self indexOfSessionChatID:chatID];

  NSError *error = nil;
  if (![self.database deleteChatWithID:chatID error:&error]) {
    [self presentErrorMessage:error.localizedDescription ?: @"Could not delete conversation."];
    return;
  }

  [self.chatIconRequests removeObject:@(chatID)];
  if (closedIndex != NSNotFound) {
    [self.appStateManager removeWorkspaceTabWithKind:TLWorkspaceTabKindChat tabID:chatID];
    [self removeRuntimeForKind:TLWorkspaceTabKindChat tabID:chatID];
  }

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

- (void)reloadHistoryPanel {
  self.historyPanelController.chats = self.chats ?: @[];
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
  NSString *model = [self.settings.supportingModel stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (token.length == 0 || model.length == 0) {
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
    if (error || icon.length == 0) {
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

- (void)applySavedChatSummary:(TLChatSummary *)savedSummary {
  if (!savedSummary) {
    return;
  }

  for (NSUInteger index = 0; index < self.chats.count; index += 1) {
    if (self.chats[index].chatID == savedSummary.chatID) {
      self.chats[index] = savedSummary;
      break;
    }
  }

  if (self.activeChat.chatID == savedSummary.chatID) {
    self.activeChat.title = savedSummary.title;
    self.activeChat.icon = savedSummary.icon;
    self.activeChat.updatedAt = savedSummary.updatedAt;
  }

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
