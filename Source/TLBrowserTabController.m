#import "TLBrowserTabController.h"
#import "TLBrowserHeightTransition.h"
#import "BrowserConversation.h"
#import "InputSuggestions.h"
#import "UIComponents.h"
#import "design_system/TLBrowserChatPane.h"

@interface TLBrowserTabController ()
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLChromiumBrowserController *browserService;
@property (nonatomic, strong) TLChromiumBrowserSession *browserSession;
@property (nonatomic, strong) NSView *browserHostView;
@property (nonatomic, strong) TLBrowserAddressInput *browserAddressInput;
@property (nonatomic, strong) NSLayoutConstraint *browserAddressInputWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong) TLBrowserHeightTransition *heightTransition;
@property (nonatomic, strong) TLBrowserConversation *browserConversation;
@property (nonatomic, strong) TLBrowserChatPane *browserChatPane;
@property (nonatomic, strong, readwrite, nullable) NSImage *favicon;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic) BOOL browserUsesReducedHeight;
@end

@implementation TLBrowserTabController
- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                inputWidth:(CGFloat)inputWidth {
  return [self initWithURL:URL palette:palette database:database orchestrator:orchestrator
               inputWidth:inputWidth browserService:TLChromiumBrowserController.sharedController];
}

- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                inputWidth:(CGFloat)inputWidth browserService:(TLChromiumBrowserController *)browserService {
  self = [super initWithPalette:palette];
  if (self) {
    _database = database;
    _agentOrchestrator = orchestrator;
    _browserService = browserService;
    _URL = URL;
    self.title = URL.host ?: URL.absoluteString;
    [self buildContentWithURL:URL inputWidth:inputWidth];
  }
  return self;
}

- (void)dealloc {
  [_heightTransition cancel];
  [_browserService closeSession:_browserSession];
}

- (void)close {
  if (self.isClosed) return;
  [super close];
  [self.heightTransition cancel];
  self.browserConversation.changeHandler = nil;
  self.browserChatPane.linkHandler = nil;
  self.browserChatPane.minimizeButton.target = nil;
  self.browserAddressInput.heightChangeHandler = nil;
  self.browserAddressInput.sendButton.target = nil;
  for (NSButton *button in @[self.browserAddressInput.backButton,
                             self.browserAddressInput.forwardButton,
                             self.browserAddressInput.reloadButton,
                             self.browserAddressInput.heightToggleButton,
                             self.browserAddressInput.chatButton]) {
    button.target = nil;
  }
  [self.browserService closeSession:self.browserSession];
  self.browserSession = nil;
  self.metadataChangedHandler = nil;
  self.faviconChangedHandler = nil;
  self.linkHandler = nil;
  self.settingsProvider = nil;
  self.settingsRequiredHandler = nil;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.view.layer.backgroundColor = TLCGColor(palette.tabBackground);
  self.browserAddressInput.palette = palette;
  self.browserChatPane.palette = palette;
  CGFloat reducedInset = palette.browserReducedHeightSpacing + MAX(palette.composerButtonHeight, NSHeight(self.browserAddressInput.frame));
  [self.heightTransition setBrowserBottomInset:self.browserUsesReducedHeight ? -reducedInset : palette.space0 duration:0 overshoot:0];
  self.browserAddressInput.reducedHeight = self.browserUsesReducedHeight;
}

- (void)setAddressInputWidth:(CGFloat)width {
  self.browserAddressInputWidthConstraint.constant = width;
}

- (void)buildContentWithURL:(NSURL *)URL inputWidth:(CGFloat)width {
  NSView *browserContentView = [[NSView alloc] init];
  browserContentView.translatesAutoresizingMaskIntoConstraints = NO;
  browserContentView.wantsLayer = YES;
  browserContentView.layer.backgroundColor = TLCGColor(self.palette.tabBackground);

  NSView *browserHostView = [[NSView alloc] init];
  browserHostView.translatesAutoresizingMaskIntoConstraints = NO;
  browserHostView.wantsLayer = YES;
  browserHostView.layer.masksToBounds = YES;
  [browserContentView addSubview:browserHostView];

  TLBrowserBackdropView *browserBackdropView = [[TLBrowserBackdropView alloc] init];
  [browserContentView addSubview:browserBackdropView];

  self.browserHostView = browserHostView;
  self.view = browserContentView;

  TLBrowserAddressInput *addressInput = [[TLBrowserAddressInput alloc] init];
  addressInput.palette = self.palette;
  addressInput.reducedHeight = NO;
  [addressInput setDisplayedAddress:[self displayAddressForBrowserURL:URL]];
  addressInput.sendButton.target = self;
  addressInput.sendButton.action = @selector(navigateBrowserFromAddressInput:);
  addressInput.textView.toolTip = URL.absoluteString;
  for (NSButton *button in @[addressInput.backButton,
                             addressInput.forwardButton,
                             addressInput.reloadButton,
                             addressInput.chatButton,
                             addressInput.heightToggleButton]) {
    button.target = self;
  }
  addressInput.backButton.action = @selector(navigateBrowserBack:);
  addressInput.forwardButton.action = @selector(navigateBrowserForward:);
  addressInput.reloadButton.action = @selector(reloadBrowser:);
  addressInput.heightToggleButton.action = @selector(toggleBrowserHeightMode:);
  addressInput.chatButton.action = @selector(restoreBrowserChat:);
  [browserContentView addSubview:addressInput];
  self.browserAddressInput = addressInput;

  NSLayoutConstraint *addressInputWidthConstraint = [addressInput.widthAnchor constraintEqualToConstant:width];
  addressInputWidthConstraint.priority = NSLayoutPriorityWindowSizeStayPut - 1.0;
  self.browserAddressInputWidthConstraint = addressInputWidthConstraint;
  NSLayoutConstraint *addressInputLeadingConstraint = [addressInput.leadingAnchor constraintGreaterThanOrEqualToAnchor:browserContentView.leadingAnchor
                                                                                                           constant:self.palette.space11];
  NSLayoutConstraint *addressInputTrailingConstraint = [addressInput.trailingAnchor constraintLessThanOrEqualToAnchor:browserContentView.trailingAnchor
                                                                                                             constant:-self.palette.space11];
  addressInputLeadingConstraint.priority = NSLayoutPriorityDefaultLow;
  addressInputTrailingConstraint.priority = NSLayoutPriorityDefaultLow;
  NSLayoutConstraint *browserHostBottomConstraint =
    [browserHostView.bottomAnchor constraintEqualToAnchor:browserContentView.bottomAnchor];
  self.browserHostBottomConstraint = browserHostBottomConstraint;
  self.heightTransition = [[TLBrowserHeightTransition alloc] initWithContentView:browserContentView bottomConstraint:browserHostBottomConstraint];
  __weak typeof(self) weakSelf = self;
  addressInput.heightChangeHandler = ^(CGFloat height) {
    TLBrowserTabController *controller = weakSelf;
    if (controller.browserUsesReducedHeight && !controller.isClosed) {
      [controller.heightTransition setBrowserBottomInset:-(controller.palette.browserReducedHeightSpacing + height)
        duration:NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : controller.palette.browserHeightTransitionDuration
        overshoot:0];
    }
  };
  [NSLayoutConstraint activateConstraints:@[
    [browserHostView.leadingAnchor constraintEqualToAnchor:browserContentView.leadingAnchor],
    [browserHostView.trailingAnchor constraintEqualToAnchor:browserContentView.trailingAnchor],
    [browserHostView.topAnchor constraintEqualToAnchor:browserContentView.topAnchor],
    browserHostBottomConstraint,
    [browserBackdropView.leadingAnchor constraintEqualToAnchor:browserContentView.leadingAnchor],
    [browserBackdropView.trailingAnchor constraintEqualToAnchor:browserContentView.trailingAnchor],
    [browserBackdropView.bottomAnchor constraintEqualToAnchor:browserContentView.bottomAnchor],
    [browserBackdropView.heightAnchor constraintEqualToConstant:self.palette.browserBackdropHeight],
    [addressInput.centerXAnchor constraintEqualToAnchor:browserContentView.centerXAnchor],
    [addressInput.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.messageInputMinWidth],
    [addressInput.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth],
    addressInputLeadingConstraint,
    addressInputTrailingConstraint,
    addressInputWidthConstraint,
    [addressInput.bottomAnchor constraintEqualToAnchor:browserContentView.bottomAnchor constant:-self.palette.space10],
  ]];

}

- (void)startInWindow:(NSWindow *)window {
  if (self.isClosed || self.browserSession) return;
  [self.view.superview layoutSubtreeIfNeeded];
  [self.view layoutSubtreeIfNeeded];
  __weak typeof(self) weakSelf = self;
  self.browserSession = [self.browserService loadURL:self.URL inView:self.browserHostView fromWindow:window
    titleHandler:^(NSString *title) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed || title.length == 0) return;
      controller.title = title;
      [controller publishMetadata];
    } linkHandler:^(NSURL *URL, NSEventModifierFlags flags) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller.isClosed && controller.linkHandler) controller.linkHandler(URL, flags);
    } URLHandler:^(NSURL *URL) {
      TLBrowserTabController *controller = weakSelf;
      NSString *scheme = URL.scheme.lowercaseString;
      if (!controller || controller.isClosed || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
      controller.URL = URL;
      [controller.browserAddressInput updateDisplayedAddress:[controller displayAddressForBrowserURL:URL]];
      controller.browserAddressInput.textView.toolTip = URL.absoluteString;
      [controller publishMetadata];
    } faviconHandler:^(NSImage *favicon) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed || controller.favicon == favicon) return;
      controller.favicon = favicon;
      if (controller.faviconChangedHandler) controller.faviconChangedHandler();
    } navigationHandler:^(BOOL canGoBack, BOOL canGoForward, BOOL loading) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed) return;
      controller.browserAddressInput.backButton.enabled = canGoBack;
      controller.browserAddressInput.forwardButton.enabled = canGoForward;
      controller.browserAddressInput.reloadButton.enabled = YES;
    }];
}

- (void)publishMetadata {
  if (!self.isClosed && self.metadataChangedHandler) self.metadataChangedHandler(self.title, self.URL);
}

- (void)navigateBrowserBack:(id)sender { [self.browserService goBackInSession:self.browserSession]; }
- (void)navigateBrowserForward:(id)sender { [self.browserService goForwardInSession:self.browserSession]; }
- (void)reloadBrowser:(id)sender { [self.browserService reloadSession:self.browserSession]; }

- (void)toggleBrowserHeightMode:(id)sender {
  self.browserUsesReducedHeight = !self.browserUsesReducedHeight;
  CGFloat reducedInset = self.palette.browserReducedHeightSpacing + NSHeight(self.browserAddressInput.frame);
  self.browserAddressInput.reducedHeight = self.browserUsesReducedHeight;
  [self.heightTransition setBrowserBottomInset:self.browserUsesReducedHeight ? -reducedInset : self.palette.space0
    duration:NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : self.palette.browserHeightTransitionDuration
    overshoot:self.browserUsesReducedHeight ? self.palette.browserHeightTransitionOvershoot : 0];
}

- (void)navigateBrowserFromAddressInput:(id)sender {
  if (self.isClosed) return;
  TLBrowserAddressInput *input = self.browserAddressInput;
  NSString *text = [input.textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0) return;
  NSURL *URL = input.hasUserDraft ? [TLInputSuggestions browserURLForInput:text] : self.URL;
  if (!URL) { [self sendBrowserPrompt:text]; return; }
  [input setDisplayedAddress:[self displayAddressForBrowserURL:URL]];
  input.textView.toolTip = URL.absoluteString;
  [self.view.window makeFirstResponder:self.browserHostView];
  self.URL = URL;
  [self publishMetadata];
  [self.browserService navigateSession:self.browserSession toURL:URL];
}

- (void)updateBrowserChat {
  if (self.isClosed) return;
  TLBrowserConversation *conversation = self.browserConversation;
  [self.browserChatPane setPresented:!conversation.minimized animated:YES];
  self.browserChatPane.title = conversation.title;
  [self.browserChatPane showMarkdown:conversation.markdown loading:conversation.loading];
  self.browserAddressInput.chatVisible = conversation.minimized;
  self.browserAddressInput.responseCount = conversation.responseCount;
}

- (void)minimizeBrowserChat:(id)sender {
  self.browserConversation.minimized = YES;
  [self.browserAddressInput setDisplayedAddress:[self displayAddressForBrowserURL:self.URL]];
  [self updateBrowserChat];
}

- (void)restoreBrowserChat:(id)sender {
  if (!self.browserConversation) return;
  self.browserConversation.minimized = NO;
  [self updateBrowserChat];
  [self.browserAddressInput beginPromptEditing];
}

- (void)sendBrowserPrompt:(NSString *)prompt {
  if (self.browserConversation.busy) { NSBeep(); return; }
  TLAppSettings *settings = self.settingsProvider ? self.settingsProvider() : nil;
  if (!settings.openRouterToken.length || !settings.selectedModel.length) {
    if (self.settingsRequiredHandler) self.settingsRequiredHandler();
    return;
  }
  TLBrowserAddressInput *input = self.browserAddressInput;
  if (!self.browserConversation) {
    self.browserConversation = [[TLBrowserConversation alloc] initWithDatabase:self.database orchestrator:self.agentOrchestrator];
    TLBrowserChatPane *pane = [[TLBrowserChatPane alloc] init];
    pane.palette = self.palette;
    pane.minimizeButton.target = self;
    pane.minimizeButton.action = @selector(minimizeBrowserChat:);
    self.browserChatPane = pane;
    [self.view addSubview:pane positioned:NSWindowAbove relativeTo:input];
    NSLayoutConstraint *height = [pane.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:self.palette.browserChatPaneHeightFraction];
    height.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
      [pane.leadingAnchor constraintEqualToAnchor:input.leadingAnchor],
      [pane.widthAnchor constraintEqualToAnchor:input.widthAnchor],
      [pane.bottomAnchor constraintEqualToAnchor:input.topAnchor constant:-self.palette.space4],
      [pane.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.topAnchor constant:self.palette.space4],
      height,
    ]];
    __weak typeof(self) weakSelf = self;
    self.browserConversation.changeHandler = ^{ [weakSelf updateBrowserChat]; };
    pane.linkHandler = ^(NSURL *URL, NSEventModifierFlags flags) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller.isClosed && controller.linkHandler) controller.linkHandler(URL, flags);
    };
  }
  NSURL *pageURL = self.URL;
  TLChromiumBrowserSession *session = self.browserSession;
  TLChromiumBrowserController *service = self.browserService;
  BOOL started = [self.browserConversation sendPrompt:prompt token:settings.openRouterToken model:settings.selectedModel
    pageReader:^(void (^completion)(NSDictionary *, NSError *)) {
      [service readPageInSession:session expectedURL:pageURL completion:completion];
    }];
  if (started) [input setDisplayedAddress:[self displayAddressForBrowserURL:self.URL]];
}

- (NSString *)displayAddressForBrowserURL:(NSURL *)URL {
  NSString *address = URL.absoluteString ?: @"";
  NSString *scheme = URL.scheme.lowercaseString;
  if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
    address = [address substringFromIndex:scheme.length + 3];
  }
  if ([address rangeOfString:@"www."
                     options:NSAnchoredSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
    address = [address substringFromIndex:4];
  }
  if ([address hasSuffix:@"/"]) {
    address = [address substringToIndex:address.length - 1];
  }
  return address;
}


@end
