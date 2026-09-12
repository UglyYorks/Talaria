#import "design_system/TLProgressiveBlurView.h"
#import "TLBrowserContentColor.h"
#import <QuartzCore/QuartzCore.h>
#import "TLBrowserTabController.h"
#import "TLBrowserPreferences.h"
#import "BrowserConversation.h"
#import "InputSuggestions.h"
#import "UIComponents.h"
#import "design_system/TLBrowserChatPane.h"
#import "design_system/TLFindBar.h"

@interface TLBrowserTabController ()
@property (nonatomic, readwrite, getter=isLoading) BOOL loading;
@property (nonatomic, readwrite) double loadingProgress;
@property (nonatomic, strong) TLFindBar *findBar;
@property (nonatomic, strong) NSLayoutConstraint *findBarHeightConstraint;
@property (nonatomic) BOOL findHasQuery;
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic) NSInteger historyVisitID;
@property (nonatomic, copy) NSString *historyPageOrigin;
@property (nonatomic, copy) NSString *historyFaviconOrigin;
@property (nonatomic, copy) NSData *historyFaviconData;
@property (nonatomic, strong) TLBrowserPreferences *browserPreferences;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLWebKitBrowserController *browserService;
@property (nonatomic, strong) TLWebKitBrowserSession *browserSession;
@property (nonatomic, strong) TLBrowserViewportView *browserHostView;
@property TLProgressiveBlurView *bottomBlur;
@property NSLayoutConstraint *bottomBlurHeight;
@property (nonatomic, strong) TLBrowserAddressInput *browserAddressInput;
@property (nonatomic, strong) NSLayoutConstraint *browserAddressInputWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong) TLBrowserConversation *browserConversation;
@property (nonatomic, strong) TLBrowserChatPane *browserChatPane;
@property (nonatomic, strong, readwrite, nullable) NSImage *favicon;
@property (nonatomic, strong, readwrite, nullable) NSColor *headerContentColor;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSTimer *pageAppearanceTimer;
@property (nonatomic) NSUInteger extensionDocumentGeneration;
@property (nonatomic) BOOL footerColorInFlight;
@property (nonatomic) NSTimeInterval footerColorNext, footerCaptureNext;
@property (nonatomic) NSSize documentFooterContentSize;
@property (nonatomic) CGFloat addressInputHeight;
@end

@implementation TLBrowserTabController
- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                inputWidth:(CGFloat)inputWidth {
  return [self initWithURL:URL palette:palette database:database orchestrator:orchestrator
               inputWidth:inputWidth browserService:TLWebKitBrowserController.sharedController];
}

- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                inputWidth:(CGFloat)inputWidth browserService:(TLWebKitBrowserController *)browserService {
  self = [super initWithPalette:palette];
  if (self) {
    _database = database;
    _historyPageOrigin = TLBrowserHistoryOrigin(URL);
    _browserPreferences = TLBrowserPreferences.sharedPreferences;
    _agentOrchestrator = orchestrator;
    _browserService = browserService;
    _URL = URL;
    self.title = URL.host ?: URL.absoluteString;
    [self buildContentWithURL:URL inputWidth:inputWidth];
    [self updateAddressBarLabels];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(browserPreferencesChanged:) name:TLBrowserPreferencesDidChangeNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [_pageAppearanceTimer invalidate];
  _browserSession.devToolsVisibilityChangedHandler = nil;
  [_browserService closeSession:_browserSession];
}

- (void)close {
  if (self.isClosed) return;
  [super close];
  [self updateLoading:NO];
  self.loadingChangedHandler = nil;
  [self dismissFindBarRestoringFocus:NO];
  self.findBar.queryChangedHandler = nil;
  self.findBar.navigateHandler = nil;
  self.findBar.closeHandler = nil;
  self.browserSession.findResultsChangedHandler = nil;
  self.browserSession.documentStartedHandler = nil;
  [self.pageAppearanceTimer invalidate];
  self.pageAppearanceTimer = nil;
  [NSNotificationCenter.defaultCenter removeObserver:self name:TLBrowserPreferencesDidChangeNotification object:nil];
  self.browserConversation.changeHandler = nil;
  self.browserChatPane.linkHandler = nil;
  self.browserChatPane.linkContextMenuHandler = nil;
  self.browserChatPane.minimizeButton.target = nil;
  self.browserAddressInput.heightChangeHandler = nil;
  self.browserAddressInput.sendButton.target = nil;
  for (NSButton *button in @[self.browserAddressInput.backButton,
                             self.browserAddressInput.forwardButton,
                             self.browserAddressInput.reloadButton,
                             self.browserAddressInput.chatButton]) {
    button.target = nil;
  }
  self.browserSession.contextLinkHandler = nil;
  self.browserSession.devToolsVisibilityChangedHandler = nil;
  [self.browserService closeSession:self.browserSession];
  self.browserSession = nil;
  self.metadataChangedHandler = nil;
  self.historyChangedHandler = nil;
  self.faviconChangedHandler = nil;
  self.headerColorChangedHandler = nil;
  self.linkHandler = nil;
  self.contextLinkHandler = nil;
  self.settingsProvider = nil;
  self.settingsRequiredHandler = nil;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.view.layer.backgroundColor = TLCGColor(palette.tabBackground);
  self.footerColorNext = 0;
  self.browserHostView.palette = palette;
  self.bottomBlur.palette = palette;
  self.browserAddressInput.palette = palette;
  self.browserChatPane.palette = palette;
  self.findBar.palette = palette;
  if (self.findBarVisible) self.findBarHeightConstraint.constant = palette.fieldHeight + palette.space4 * 2;
  [self configureDocumentFooter];
}

- (void)setAddressInputWidth:(CGFloat)width {
  self.browserAddressInputWidthConstraint.constant = width;
}

- (void)buildContentWithURL:(NSURL *)URL inputWidth:(CGFloat)width {
  NSView *browserContentView = [[NSView alloc] init];
  browserContentView.translatesAutoresizingMaskIntoConstraints = NO;
  browserContentView.wantsLayer = YES;
  browserContentView.layer.backgroundColor = TLCGColor(self.palette.tabBackground);

  TLBrowserViewportView *browserHostView = [[TLBrowserViewportView alloc] init];
  browserHostView.palette = self.palette;
  browserHostView.translatesAutoresizingMaskIntoConstraints = NO;
  browserHostView.wantsLayer = YES;
  browserHostView.layer.masksToBounds = NO;
  [browserContentView addSubview:browserHostView];

  self.bottomBlur = [[TLProgressiveBlurView alloc] init];
  self.bottomBlur.palette = self.palette;
  self.bottomBlur.translatesAutoresizingMaskIntoConstraints = NO;
  [browserContentView addSubview:self.bottomBlur];
  self.bottomBlurHeight = [self.bottomBlur.heightAnchor constraintEqualToConstant:[self footerHeight]];
  [NSLayoutConstraint activateConstraints:@[
    [self.bottomBlur.leadingAnchor constraintEqualToAnchor:browserHostView.leadingAnchor],
    [self.bottomBlur.trailingAnchor constraintEqualToAnchor:browserHostView.trailingAnchor],
    [self.bottomBlur.bottomAnchor constraintEqualToAnchor:browserHostView.bottomAnchor], self.bottomBlurHeight]];
  self.browserHostView = browserHostView;
  self.view = browserContentView;

  TLBrowserAddressInput *addressInput = [[TLBrowserAddressInput alloc] init];
  addressInput.palette = self.palette;
  [addressInput setDisplayedAddress:[self displayAddressForBrowserURL:URL]];
  addressInput.sendButton.target = self;
  addressInput.sendButton.action = @selector(navigateBrowserFromAddressInput:);
  addressInput.textView.toolTip = URL.absoluteString;
  for (NSButton *button in @[addressInput.backButton,
                             addressInput.forwardButton,
                             addressInput.reloadButton,
                             addressInput.chatButton]) {
    button.target = self;
  }
  addressInput.backButton.action = @selector(navigateBrowserBack:);
  addressInput.forwardButton.action = @selector(navigateBrowserForward:);
  addressInput.reloadButton.action = @selector(reloadBrowser:);
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
  __weak typeof(self) weakSelf = self;
  addressInput.heightChangeHandler = ^(CGFloat height) {
    TLBrowserTabController *controller = weakSelf;
    controller.addressInputHeight = height;
    [controller configureDocumentFooter];
  };
  [self buildFindBar];
  [NSLayoutConstraint activateConstraints:@[
    [browserHostView.leadingAnchor constraintEqualToAnchor:browserContentView.leadingAnchor],
    [browserHostView.trailingAnchor constraintEqualToAnchor:browserContentView.trailingAnchor],
    [browserHostView.topAnchor constraintEqualToAnchor:self.findBar.bottomAnchor],
    browserHostBottomConstraint,
    [addressInput.centerXAnchor constraintEqualToAnchor:browserContentView.centerXAnchor],
    [addressInput.widthAnchor constraintGreaterThanOrEqualToConstant:0],
    [addressInput.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth],
    addressInputLeadingConstraint,
    addressInputTrailingConstraint,
    addressInputWidthConstraint,
    [addressInput.bottomAnchor constraintEqualToAnchor:browserContentView.bottomAnchor constant:-self.palette.space10],
  ]];

}

- (void)buildFindBar {
  self.findBar = [TLFindBar new];
  self.findBar.searchLabel = @"Find in page";
  self.findBar.translatesAutoresizingMaskIntoConstraints = NO;
  self.findBar.palette = self.palette;
  self.findBar.hidden = YES;
  [self.view addSubview:self.findBar];
  self.findBarHeightConstraint = [self.findBar.heightAnchor constraintEqualToConstant:0];
  [NSLayoutConstraint activateConstraints:@[
    [self.findBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.findBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.findBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    self.findBarHeightConstraint
  ]];
  __weak typeof(self) weakSelf = self;
  self.findBar.queryChangedHandler = ^{ [weakSelf updateFindQuery]; };
  self.findBar.navigateHandler = ^(BOOL forward) { [weakSelf findNext:forward]; };
  self.findBar.closeHandler = ^{ [weakSelf hideFindBar]; };
}

- (BOOL)findBarVisible { return !self.findBar.hidden; }
- (void)showFindBar {
  if (self.isClosed) return;
  BOOL wasVisible = self.findBarVisible;
  self.findBar.hidden = NO;
  self.findBarHeightConstraint.constant = self.palette.fieldHeight + self.palette.space4 * 2;
  [self.view layoutSubtreeIfNeeded];
  [self.findBar focusSearchField];
  if (!wasVisible) [self updateFindQuery];
}
- (void)updateFindQuery {
  if (!self.findBarVisible || self.isClosed) return;
  NSString *query = self.findBar.searchField.stringValue;
  self.findHasQuery = query.length > 0;
  [self.findBar setMatchCount:0 activeMatch:0 searching:self.findHasQuery];
  if (self.findHasQuery) [self.browserService findText:query inSession:self.browserSession forward:YES findNext:NO];
  else [self.browserService stopFindingInSession:self.browserSession];
}
- (void)findNext:(BOOL)forward {
  if (self.isClosed) return;
  if (!self.findBarVisible) { [self showFindBar]; return; }
  NSString *query = self.findBar.searchField.stringValue;
  if (!query.length) { [self.findBar focusSearchField]; return; }
  [self.browserService findText:query inSession:self.browserSession forward:forward findNext:self.findHasQuery];
  self.findHasQuery = YES;
}
- (void)hideFindBar { [self dismissFindBarRestoringFocus:YES]; }
- (void)dismissFindBarRestoringFocus:(BOOL)restoreFocus {
  if (!self.findBarVisible) return;
  NSResponder *responder = self.view.window.firstResponder;
  BOOL ownsFocus = responder == self.findBar.searchField.currentEditor ||
    ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.findBar]);
  if (ownsFocus) [self.view.window makeFirstResponder:nil];
  self.findBar.hidden = YES;
  self.findBarHeightConstraint.constant = 0;
  self.findHasQuery = NO;
  [self.browserService stopFindingInSession:self.browserSession];
  [self.findBar setMatchCount:0 activeMatch:0 searching:NO];
  [self.view layoutSubtreeIfNeeded];
  if (restoreFocus && ownsFocus) [self.browserService focusSession:self.browserSession];
}

- (void)startInWindow:(NSWindow *)window { [self startInWindow:window configuration:nil]; }
- (WKWebView *)startInWindow:(NSWindow *)window configuration:(WKWebViewConfiguration *)configuration {
  if (self.isClosed || self.browserSession) return self.browserSession.webView;
  [self.view.superview layoutSubtreeIfNeeded];
  [self.view layoutSubtreeIfNeeded];
  __weak typeof(self) weakSelf = self;
  self.browserSession = [self.browserService loadURL:self.URL inView:self.browserHostView.contentView fromWindow:window
    titleHandler:^(NSString *title) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed || title.length == 0) return;
      controller.title = title;
      if (controller.historyVisitID > 0) {
        NSError *error = nil;
        if (![controller.database updateBrowserVisitWithID:controller.historyVisitID title:title error:&error]) {
          NSLog(@"Unable to update browsing history: %@", error.localizedDescription);
        } else if (controller.historyChangedHandler) controller.historyChangedHandler();
      }
      [controller publishMetadata];
    } linkHandler:^(NSURL *URL, NSEventModifierFlags flags) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller.isClosed && controller.linkHandler) controller.linkHandler(URL, flags);
    } URLHandler:^(NSURL *URL) {
      TLBrowserTabController *controller = weakSelf;
      NSString *scheme = URL.scheme.lowercaseString;
      if (!controller || controller.isClosed) return;
      controller.historyVisitID = 0;
      controller.historyPageOrigin = TLBrowserHistoryOrigin(URL);
      if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return;
      // WebKit's committed navigation callback reports committed navigations, including
      // back/forward and same-document navigation. Metadata changes do not add visits.
      NSError *error = nil;
      controller.historyVisitID = [controller.database recordBrowserVisitToURL:URL title:@"" error:&error];
      [controller persistHistoryFavicon];
      if (error) NSLog(@"Unable to save browsing history: %@", error.localizedDescription);
      else if (controller.historyChangedHandler) controller.historyChangedHandler();
      controller.URL = URL;
      [controller.browserAddressInput updateDisplayedAddress:[controller displayAddressForBrowserURL:URL]];
      controller.browserAddressInput.textView.toolTip = URL.absoluteString;
      [controller publishMetadata];
    } faviconHandler:^(NSImage *favicon) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed || controller.favicon == favicon) return;
      controller.favicon = favicon;
      NSData *TIFF = favicon.TIFFRepresentation;
      NSBitmapImageRep *bitmap = TIFF ? [NSBitmapImageRep imageRepWithData:TIFF] : nil;
      controller.historyFaviconData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      controller.historyFaviconOrigin = controller.historyFaviconData ? controller.historyPageOrigin : nil;
      [controller persistHistoryFavicon];
      if (controller.historyFaviconData && controller.historyChangedHandler) controller.historyChangedHandler();
      if (controller.faviconChangedHandler) controller.faviconChangedHandler();
    } navigationHandler:^(BOOL canGoBack, BOOL canGoForward, BOOL loading) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed) return;
      controller.browserAddressInput.backButton.enabled = canGoBack;
      controller.browserAddressInput.forwardButton.enabled = canGoForward;
      controller.browserAddressInput.reloadButton.enabled = YES;
      [controller updateLoading:loading];
    } configuration:configuration];
  self.browserSession.createTabHandler = self.createTabHandler;
  self.browserSession.closeTabHandler = self.closeTabHandler;
  self.browserSession.contextLinkHandler = ^(NSURL *URL, TLBrowserLinkDestination destination) {
    TLBrowserTabController *controller = weakSelf;
    if (!controller.isClosed && controller.contextLinkHandler) controller.contextLinkHandler(URL, destination);
  };
  if (self.browserSession) {
    [self updateLoading:self.browserSession.webView.loading];
    self.browserSession.findResultsChangedHandler = ^(NSInteger count, NSInteger activeMatch, BOOL finalUpdate) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed || !controller.findBarVisible || !controller.findHasQuery) return;
      [controller.findBar setMatchCount:count activeMatch:activeMatch searching:!finalUpdate && count == 0];
    };
    self.browserSession.documentStartedHandler = ^{
      TLBrowserTabController *owner=weakSelf;
      owner.footerColorNext=0;owner.footerCaptureNext=0;
      if(owner.headerColorChangedHandler)owner.headerColorChangedHandler();
      [owner dismissFindBarRestoringFocus:NO];
    };
    self.browserSession.topColorChanged=^(NSArray *rgb){[weakSelf updateTabEdgeColor:[TLBrowserContentColor colorForRGB:rgb]];};
    self.browserSession.topScrollEnded=^{
      TLBrowserTabController *owner=weakSelf;if(!owner || owner.isClosed)return;
      owner.footerColorNext=0;owner.footerCaptureNext=0;
      [owner sampleFooterContentColor];
    };
    [self configureDocumentFooter];
    self.pageAppearanceTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed) { [timer invalidate]; return; }
      [controller samplePageAppearance];
    }];
    self.pageAppearanceTimer.tolerance = 0.01;
    [NSRunLoop.mainRunLoop addTimer:self.pageAppearanceTimer forMode:NSRunLoopCommonModes];
  }
  return self.browserSession.webView;
}

- (void)updateLoading:(BOOL)loading {
  double progress = loading ? self.browserSession.webView.estimatedProgress : 0;
  progress = isfinite(progress) ? MIN(1, MAX(0, progress)) : 0;
  if (self.loading == loading && self.loadingProgress == progress) return;
  self.loading = loading;
  self.loadingProgress = progress;
  [self.browserAddressInput setLoading:loading progress:progress];
  if (self.loadingChangedHandler) self.loadingChangedHandler();
}

- (void)persistHistoryFavicon {
  if (self.historyVisitID <= 0 || !self.historyFaviconData.length ||
      ![self.historyFaviconOrigin isEqualToString:self.historyPageOrigin]) return;
  NSError *error = nil;
  if (![self.database updateBrowserVisitWithID:self.historyVisitID faviconData:self.historyFaviconData error:&error])
    NSLog(@"Unable to save browsing favicon: %@", error.localizedDescription);
}

- (void)publishMetadata {
  if (!self.isClosed && self.metadataChangedHandler) self.metadataChangedHandler(self.title, self.URL);
}

- (void)navigateBrowserBack:(id)sender { [self.browserService goBackInSession:self.browserSession]; }
- (void)navigateBrowserForward:(id)sender { [self.browserService goForwardInSession:self.browserSession]; }
- (void)reloadBrowser:(id)sender { [self.browserService reloadSession:self.browserSession]; }

- (void)setTabColorSampleRect:(NSRect)rect {
  if(NSEqualRects(rect,_tabColorSampleRect))return;
  _tabColorSampleRect=rect;self.footerColorNext=0;self.footerCaptureNext=0;
  [self configureDocumentFooter];
}
- (CGFloat)footerHeight {
  return self.palette.browserReducedHeightSpacing + MAX(self.palette.composerButtonHeight, self.addressInputHeight ?: NSHeight(self.browserAddressInput.frame));
}
- (void)configureDocumentFooter {
  self.documentFooterContentSize = self.view.bounds.size;
  self.bottomBlurHeight.constant = [self footerHeight];
  [self.browserService configureDocumentFooter:@{
    @"enabled":@YES, @"height":@([self footerHeight]),
    @"width":@(MAX(1,NSWidth(self.browserHostView.bounds))), @"fallbackColor":[TLBrowserContentColor CSSStringForColor:self.palette.tabBackground],
    @"topRange":@[@(NSMinX(self.tabColorSampleRect)),@(NSWidth(self.tabColorSampleRect)>0 ? NSWidth(self.tabColorSampleRect) : 1)], @"banner":NSNull.null
  } inSession:self.browserSession completion:nil];
}
- (BOOL)canSamplePageAppearance {
  if (self.browserSession.fullscreen) return NO;
  return !self.isClosed && self.browserSession && self.view.window.isVisible &&
    !self.view.window.isMiniaturized && !self.view.isHiddenOrHasHiddenAncestor;
}
- (void)restoreHeaderContentColor:(NSColor *)color {
  if (!self.headerContentColor) self.headerContentColor = color;
}
- (BOOL)headerColorChangesAnimated {
  return self.headerContentColor != nil && self.browserSession != nil && !self.browserSession.webView.loading;
}
- (void)updateTabEdgeColor:(NSColor *)color {
  if(!color || self.isClosed || [color isEqual:self.headerContentColor])return;
  self.headerContentColor=color;
  if(self.headerColorChangedHandler)self.headerColorChangedHandler();
}
- (void)sampleFooterContentColor {
  NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
  if (![self canSamplePageAppearance] || self.footerColorInFlight || now < self.footerColorNext) return;
  BOOL capture = now >= self.footerCaptureNext;
  self.footerColorInFlight = YES; self.footerColorNext = now + 0.2;
  NSUInteger document = self.browserSession.documentGeneration;
  NSSize viewport = self.browserHostView.bounds.size;
  NSRect sampleRect = self.tabColorSampleRect;
  __weak typeof(self) weakSelf = self;
  [self.browserService sampleFooterColorInSession:self.browserSession allowCapture:capture completion:^(NSDictionary *result) {
    TLBrowserTabController *owner = weakSelf; if (!owner) return;
    owner.footerColorInFlight = NO;
    NSTimeInterval completed = NSProcessInfo.processInfo.systemUptime;
    if (![owner canSamplePageAppearance] || document != owner.browserSession.documentGeneration ||
        !NSEqualSizes(viewport,owner.browserHostView.bounds.size) || !NSEqualRects(sampleRect,owner.tabColorSampleRect)) return;
    if ([result[@"captureMS"] doubleValue] > 0) owner.footerCaptureNext = completed + MAX(1,[result[@"captureMS"] doubleValue]*0.025);
    owner.footerColorNext = completed + MAX(0.2,[result[@"cpuMS"] doubleValue]*0.04);
    [owner updateTabEdgeColor:[TLBrowserContentColor colorForRGB:result[@"top"][@"rgb"]]];
  }];
}
- (void)samplePageAppearance {
  if (self.extensionDocumentGeneration != self.browserSession.documentGeneration) {
    self.extensionDocumentGeneration = self.browserSession.documentGeneration;
    self.footerColorNext = 0;
    self.footerCaptureNext = 0;
    [self configureDocumentFooter];
  }
  if (!NSEqualSizes(self.documentFooterContentSize, self.view.bounds.size)) [self configureDocumentFooter];
  [self sampleFooterContentColor];
}

- (void)browserPreferencesChanged:(NSNotification *)notification { [self updateAddressBarLabels]; }

- (void)updateAddressBarLabels {
  BOOL search = [[self.browserPreferences localValue:@"addressBarMode"] isEqual:@"search"];
  self.browserAddressInput.textView.accessibilityLabel = search ? @"Search or enter a URL" : @"Give a task or enter a URL";
  self.browserAddressInput.sendButton.accessibilityLabel = search ? @"Search or navigate" : @"Send task or navigate";
  self.browserAddressInput.sendButton.toolTip = search ? @"Search or navigate" : @"Send task or navigate";
}

- (void)navigateBrowserFromAddressInput:(id)sender {
  if (self.isClosed) return;
  TLBrowserAddressInput *input = self.browserAddressInput;
  NSString *text = [input.textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0) return;
  NSURL *URL = input.hasUserDraft ? [TLInputSuggestions browserURLForInput:text] : self.URL;
  if (!URL && [[self.browserPreferences localValue:@"addressBarMode"] isEqual:@"search"]) URL = [self.browserPreferences searchURLForText:text];
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
  __weak typeof(self) weakSelf = self;
  self.browserChatPane.approvalHandler = ^BOOL(NSString *requestID, NSString *choice) {
    TLBrowserTabController *controller = weakSelf;
    if (!controller || controller.isClosed) return NO;
    TLAppSettings *settings = controller.settingsProvider ? controller.settingsProvider() : nil;
    if (!settings.selectedModel.length) return NO;
    return [controller.browserConversation respondToApproval:requestID choice:choice token:settings.openRouterToken model:settings.selectedModel];
  };
  [self.browserChatPane showApprovalRequest:conversation.pendingApproval];
  [self.browserChatPane showQuestions:conversation.questions];
  [self.browserChatPane showToolActivities:conversation.toolActivities];
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
  if (!settings.selectedModel.length) {
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
    pane.linkContextMenuHandler = ^dispatch_block_t(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point) {
      TLBrowserTabController *controller = weakSelf;
      if (controller.isClosed || !controller.contextLinkHandler) return nil;
      return [TLBrowserLinkActions configureNativeMenu:menu forURL:URL inView:view atPoint:point
        open:^(NSURL *link, TLBrowserLinkDestination destination) {
          TLBrowserTabController *current = weakSelf;
          if (!current.isClosed && current.contextLinkHandler) current.contextLinkHandler(link, destination);
        }];
    };
    pane.linkHandler = ^(NSURL *URL, NSEventModifierFlags flags) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller.isClosed && controller.linkHandler) controller.linkHandler(URL, flags);
    };
  }
  NSURL *pageURL = self.URL;
  TLWebKitBrowserSession *session = self.browserSession;
  TLWebKitBrowserController *service = self.browserService;
  BOOL started = [self.browserConversation sendPrompt:prompt token:settings.openRouterToken model:settings.selectedModel
    pageReader:^(void (^completion)(NSDictionary *, NSError *)) {
      [service readPageInSession:session expectedURL:pageURL completion:completion];
    }];
  if (started) [input setDisplayedAddress:[self displayAddressForBrowserURL:self.URL]];
}

- (NSString *)displayAddressForBrowserURL:(NSURL *)URL {
  return URL.absoluteString ?: @"";
}


@end
