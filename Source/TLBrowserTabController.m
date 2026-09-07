#import "TLBrowserContentColor.h"
#import <QuartzCore/QuartzCore.h>
#import "TLBrowserTabController.h"
#import "TLBrowserHeightTransition.h"
#import "TLBrowserOverlayPolicy.h"
#import "BrowserConversation.h"
#import "InputSuggestions.h"
#import "UIComponents.h"
#import "design_system/TLBrowserChatPane.h"

@interface TLBrowserTabController ()
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLChromiumBrowserController *browserService;
@property (nonatomic, strong) TLChromiumBrowserSession *browserSession;
@property (nonatomic, strong) TLBrowserViewportView *browserHostView;
@property (nonatomic, strong) TLBrowserAddressInput *browserAddressInput;
@property (nonatomic, strong) NSLayoutConstraint *browserAddressInputWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong) TLBrowserHeightTransition *heightTransition;
@property (nonatomic, strong) TLBrowserConversation *browserConversation;
@property (nonatomic, strong) TLBrowserChatPane *browserChatPane;
@property (nonatomic, strong, readwrite, nullable) NSImage *favicon;
@property (nonatomic, strong, readwrite, nullable) NSColor *headerContentColor;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic) BOOL browserUsesReducedHeight;
@property (nonatomic, strong) TLBrowserOverlayPolicy *overlayPolicy;
@property (nonatomic, strong) NSTimer *overlayTimer;
@property (nonatomic) BOOL overlayInFlight;
@property (nonatomic) BOOL overlayDismissalProbePending;
@property (nonatomic) NSTimeInterval overlayDismissalProbeAfter;
@property (nonatomic) NSRect overlayProofRect;
@property (nonatomic) NSSize overlayProofContentSize;
@property (nonatomic) NSUInteger overlayGeneration, overlayDocumentGeneration;
@property (nonatomic) NSTimeInterval overlayNotBefore, overlayNextProbe, overlayNextFullProbe, overlayQuickDelay, overlayClearProofUntil;
@property (nonatomic, strong) NSView *footerContentView;
@property (nonatomic, strong) NSColor *footerContentColor;
@property (nonatomic, copy) NSDictionary *footerBanner;
@property (nonatomic) NSUInteger footerBannerGeneration;
@property (nonatomic) BOOL footerColorInFlight, footerColorPrimed;
@property (nonatomic) NSTimeInterval footerColorNext, footerCaptureNext;
@property (nonatomic) NSTimeInterval footerColorImmediateUntil;
@property (nonatomic) NSUInteger footerRevealGeneration;
@property (nonatomic, copy) dispatch_block_t footerColorReady;
@property (nonatomic) NSSize documentFooterContentSize;
@property (nonatomic) BOOL footerTransitionPending;
@property (nonatomic) CGFloat addressInputHeight;
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
    _overlayPolicy = [TLBrowserOverlayPolicy new];
    self.title = URL.host ?: URL.absoluteString;
    [self buildContentWithURL:URL inputWidth:inputWidth];
  }
  return self;
}

- (void)dealloc {
  [_overlayTimer invalidate];
  [_heightTransition cancel];
  _browserSession.devToolsVisibilityChangedHandler = nil;
  [_browserService closeSession:_browserSession];
}

- (void)close {
  if (self.isClosed) return;
  [super close];
  [self.overlayTimer invalidate];
  self.overlayTimer = nil;
  self.overlayGeneration++;
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
  self.browserSession.devToolsVisibilityChangedHandler = nil;
  [self.browserService closeSession:self.browserSession];
  self.browserSession = nil;
  self.metadataChangedHandler = nil;
  self.faviconChangedHandler = nil;
  self.headerColorChangedHandler = nil;
  self.linkHandler = nil;
  self.settingsProvider = nil;
  self.settingsRequiredHandler = nil;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.footerRevealGeneration++; self.footerTransitionPending=NO; self.footerColorReady=nil;
  self.view.layer.backgroundColor = TLCGColor(palette.tabBackground);
  [self updateFooterContentColor:self.footerContentColor animated:NO];
  self.footerColorNext = 0;
  self.overlayClearProofUntil = 0;
  self.browserHostView.palette = palette;
  self.browserAddressInput.palette = palette;
  self.browserChatPane.palette = palette;
  CGFloat reducedInset = palette.browserReducedHeightSpacing + MAX(palette.composerButtonHeight, NSHeight(self.browserAddressInput.frame));
  [self.heightTransition setBrowserBottomInset:self.browserUsesReducedHeight ? -reducedInset : palette.space0 duration:0 overshoot:0];
  self.browserAddressInput.reducedHeight = self.browserUsesReducedHeight;
  [self configureDocumentFooter];
  [self updateHeightDescription];
}

- (void)setAddressInputWidth:(CGFloat)width {
  self.browserAddressInputWidthConstraint.constant = width;
  self.overlayClearProofUntil = 0;
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
  NSView *extension = [NSView new];
  extension.translatesAutoresizingMaskIntoConstraints = NO; extension.wantsLayer = YES;
  extension.layer.backgroundColor = TLCGColor(self.palette.tabBackground);
  [browserContentView addSubview:extension]; self.footerContentView = extension;
  [browserContentView addSubview:browserHostView];
  [NSLayoutConstraint activateConstraints:@[
    [extension.leadingAnchor constraintEqualToAnchor:browserContentView.leadingAnchor],
    [extension.trailingAnchor constraintEqualToAnchor:browserContentView.trailingAnchor],
    [extension.bottomAnchor constraintEqualToAnchor:browserContentView.bottomAnchor],
    [extension.topAnchor constraintEqualToAnchor:browserContentView.topAnchor]
  ]];

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
  self.heightTransition.insetChanged = ^(CGFloat inset) {
    TLBrowserTabController *controller = weakSelf;
    controller.browserHostView.footerRevealFraction = -inset / MAX(1, [controller footerHeight]);
  };
  addressInput.heightChangeHandler = ^(CGFloat height) {
    TLBrowserTabController *controller = weakSelf;
    controller.overlayClearProofUntil = 0;
    controller.addressInputHeight=height;
    [controller configureDocumentFooter];
    if (controller.browserUsesReducedHeight && !controller.isClosed && !controller.footerTransitionPending) {
      NSTimeInterval duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : controller.palette.browserHeightTransitionDuration;
      controller.overlayNotBefore = NSProcessInfo.processInfo.systemUptime + duration + 0.15;
      [controller.heightTransition setBrowserBottomInset:-(controller.palette.browserReducedHeightSpacing + height)
        duration:duration
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
    [addressInput.widthAnchor constraintGreaterThanOrEqualToConstant:0],
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
  self.browserSession = [self.browserService loadURL:self.URL inView:self.browserHostView.contentView fromWindow:window
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
  if (self.browserSession) {
    self.browserSession.devToolsVisibilityChangedHandler = ^{
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed) return;
      controller.overlayGeneration++;
      controller.overlayClearProofUntil = 0;
      controller.overlayNextProbe = 0;
      controller.overlayNextFullProbe = 0;
      [controller.overlayPolicy observe:nil atTime:NSProcessInfo.processInfo.systemUptime];
      [controller applyHeightMode];
    };
    self.overlayDocumentGeneration = self.browserSession.documentGeneration;
    [self configureDocumentFooter];
    [self updateHeightDescription];
    self.overlayTimer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
      TLBrowserTabController *controller = weakSelf;
      if (!controller || controller.isClosed) { [timer invalidate]; return; }
      [controller sampleOverlay];
    }];
    self.overlayTimer.tolerance = 0.01;
    [NSRunLoop.mainRunLoop addTimer:self.overlayTimer forMode:NSRunLoopCommonModes];
  }
}

- (void)publishMetadata {
  if (!self.isClosed && self.metadataChangedHandler) self.metadataChangedHandler(self.title, self.URL);
}

- (void)navigateBrowserBack:(id)sender { [self.browserService goBackInSession:self.browserSession]; }
- (void)navigateBrowserForward:(id)sender { [self.browserService goForwardInSession:self.browserSession]; }
- (void)reloadBrowser:(id)sender { [self.browserService reloadSession:self.browserSession]; }

- (void)updateHeightDescription {
  BOOL inspecting = self.browserSession.devToolsVisible;
  self.browserAddressInput.heightToggleButton.enabled = !inspecting;
  if (inspecting) {
    NSString *description = @"Address bar stays below page while DevTools is open";
    self.browserAddressInput.heightToggleButton.toolTip = description;
    [self.browserAddressInput.heightToggleButton setAccessibilityLabel:description];
    return;
  }
  NSString *action = self.browserUsesReducedHeight ? @"Show address bar over page" : @"Show address bar below page";
  self.browserAddressInput.heightToggleButton.toolTip = [NSString stringWithFormat:@"%@ (%@)", action,
    self.overlayPolicy.manuallyOverridden ? @"Manual until next page" : @"Automatic"];
  [self.browserAddressInput.heightToggleButton setAccessibilityLabel:action];
}
- (CGFloat)footerHeight {
  return self.palette.browserReducedHeightSpacing + MAX(self.palette.composerButtonHeight, self.addressInputHeight ?: NSHeight(self.browserAddressInput.frame));
}
- (void)configureDocumentFooter {
  [self configureDocumentFooterWithCompletion:nil];
}
- (void)configureDocumentFooterWithCompletion:(void (^)(BOOL))completion {
  self.documentFooterContentSize = self.view.bounds.size;
  [self.browserService configureDocumentFooter:@{
    @"enabled":@(!self.browserUsesReducedHeight && !self.footerTransitionPending), @"height":@([self footerHeight]),
    @"width":@(MAX(1,NSWidth(self.browserHostView.bounds))), @"fallbackColor":[TLBrowserContentColor CSSStringForColor:self.palette.tabBackground],
    @"banner":self.footerBanner ?: NSNull.null
  } inSession:self.browserSession completion:completion];
}
- (void)applyHeightMode {
  NSUInteger reveal = ++self.footerRevealGeneration;
  self.overlayDismissalProbePending = NO;
  BOOL reducedHeight = self.browserSession.devToolsVisible || self.overlayPolicy.reducedHeight;
  BOOL changed = self.browserUsesReducedHeight != reducedHeight;
  if (changed) self.footerColorNext = 0;
  self.browserUsesReducedHeight = reducedHeight;
  self.browserAddressInput.reducedHeight = self.browserUsesReducedHeight;
  CGFloat inset = self.browserUsesReducedHeight ? -[self footerHeight] : 0;
  if (!changed && !self.footerTransitionPending && self.browserHostBottomConstraint.constant == inset) {
    [self configureDocumentFooter]; [self updateHeightDescription]; return;
  }
  self.footerTransitionPending = YES;
  self.footerColorReady = nil;
  NSTimeInterval duration = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : self.palette.browserHeightTransitionDuration;
  self.overlayNotBefore = NSProcessInfo.processInfo.systemUptime + duration + 0.15;
  __weak typeof(self) weakSelf = self;
  // Remove the document spacer in Chromium before exposing any native footer.
  [self configureDocumentFooterWithCompletion:^(BOOL applied) {
    TLBrowserTabController *owner=weakSelf;
    if(!owner || owner.isClosed || owner.footerRevealGeneration!=reveal)return;
    if(!applied){ owner.footerTransitionPending=NO; return; }
    __block BOOL finished=NO;
    dispatch_block_t move=^{
      TLBrowserTabController *current=weakSelf;
      if(finished || !current || current.isClosed || current.footerRevealGeneration!=reveal)return;
      finished=YES;current.footerColorReady=nil;
      current.overlayNotBefore=NSProcessInfo.processInfo.systemUptime+duration+0.15;
      current.footerColorImmediateUntil=current.overlayNotBefore;
      [current updateFooterContentColor:current.footerContentColor animated:NO];
      [current.heightTransition setBrowserBottomInset:current.browserUsesReducedHeight ? -[current footerHeight] : 0
        duration:duration overshoot:current.browserUsesReducedHeight ? current.palette.browserHeightTransitionOvershoot : 0 completion:^{
          TLBrowserTabController *settled=weakSelf;
          if(!settled || settled.isClosed || settled.footerRevealGeneration!=reveal)return;
          settled.footerTransitionPending=NO;
          // Only restore the spacer after the native footer is completely gone.
          [settled configureDocumentFooter];
        }];
    };
    if(owner.browserUsesReducedHeight && [owner canSampleOverlay]) {
      owner.footerColorReady=move;owner.footerColorNext=0;owner.footerCaptureNext=0;
      [owner sampleFooterContentColor];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),move);
    } else move();
  }];
  [self updateHeightDescription];
}
- (void)toggleBrowserHeightMode:(id)sender {
  if (self.browserSession.devToolsVisible) return;
  self.overlayGeneration++;
  [self.overlayPolicy setManualReducedHeight:!self.browserUsesReducedHeight];
  [self applyHeightMode];
}
- (BOOL)canSampleOverlay {
  if (self.browserSession.fullscreen) return NO;
  return !self.isClosed && self.browserSession && self.view.window.isVisible &&
    !self.view.window.isMiniaturized && !self.view.isHiddenOrHasHiddenAncestor;
}
- (void)updateFooterContentColor:(NSColor *)color animated:(BOOL)animated {
  CALayer *layer = self.footerContentView.layer;
  if (!layer) return;
  NSColor *next = color ?: self.palette.tabBackground;
  CGColorRef from = ((CALayer *)layer.presentationLayer ?: layer).backgroundColor;
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
  fade.fromValue = (__bridge id)from; fade.toValue = (__bridge id)next.CGColor;
  fade.duration = self.palette.browserFooterColorTransitionDuration;
  layer.backgroundColor = next.CGColor;
  [layer removeAnimationForKey:@"talaria.contentColor"];
  if (animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
    [layer addAnimation:fade forKey:@"talaria.contentColor"];
  [CATransaction commit];
  self.footerContentColor = color;
}
- (void)useFooterBanner:(NSDictionary *)banner {
  if([self.footerBanner isEqual:banner] || (!banner && !self.footerBanner))return;
  self.footerBanner=banner;self.footerBannerGeneration++;self.footerColorNext=0;
  [self configureDocumentFooter];
  NSColor *color=[TLBrowserContentColor colorForRGB:banner[@"rgb"]];
  if(color && ![color isEqual:self.footerContentColor])
    [self updateFooterContentColor:color animated:self.browserUsesReducedHeight && !self.footerTransitionPending && NSProcessInfo.processInfo.systemUptime>=self.footerColorImmediateUntil];
}
- (void)sampleFooterContentColor {
  NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
  if (self.footerBanner[@"rgb"] && self.footerColorReady) self.footerColorReady();
  if (self.heightTransition.isAnimating || ![self canSampleOverlay] || self.footerColorInFlight || now < self.footerColorNext) return;
  BOOL capture = now >= self.footerCaptureNext;
  self.footerColorInFlight = YES; self.footerColorNext = now + 0.2;
  NSUInteger document = self.browserSession.documentGeneration;
  NSUInteger reveal = self.footerRevealGeneration, bannerGeneration=self.footerBannerGeneration;
  NSSize viewport = self.browserHostView.bounds.size;
  __weak typeof(self) weakSelf = self;
  [self.browserService sampleFooterColorInSession:self.browserSession allowCapture:capture completion:^(NSDictionary *result) {
    TLBrowserTabController *owner = weakSelf; if (!owner) return;
    owner.footerColorInFlight = NO;
    NSTimeInterval completed = NSProcessInfo.processInfo.systemUptime;
    if (![owner canSampleOverlay] || bannerGeneration!=owner.footerBannerGeneration || document != owner.browserSession.documentGeneration ||
        !NSEqualSizes(viewport,owner.browserHostView.bounds.size)) return;
    if ([result[@"captureMS"] doubleValue] > 0) owner.footerCaptureNext = completed + MAX(1,[result[@"captureMS"] doubleValue]*0.025);
    owner.footerColorNext = completed + MAX(0.2,[result[@"cpuMS"] doubleValue]*0.04);
    NSColor *top=[TLBrowserContentColor colorForRGB:result[@"top"][@"rgb"]];
    if(top && ![top isEqual:owner.headerContentColor]) {
      owner.headerContentColor=top;
      if(owner.headerColorChangedHandler)owner.headerColorChangedHandler();
    }
    if ([result[@"busy"] boolValue]) return;
    owner.footerColorPrimed = result[@"viewState"] != nil;
    NSColor *color = [TLBrowserContentColor colorForRGB:result[@"rgb"]];
    BOOL animate = owner.browserUsesReducedHeight &&
      !owner.footerColorReady && completed >= owner.footerColorImmediateUntil;
    if (color && ![color isEqual:owner.footerContentColor]) [owner updateFooterContentColor:color animated:animate];
    if (owner.footerColorReady && reveal != owner.footerRevealGeneration) {
      owner.footerColorNext = 0;
      [owner sampleFooterContentColor];
    } else if (color && owner.footerColorReady) owner.footerColorReady();
  }];
}
- (NSRect)overlayRect {
  NSRect rect = [self.browserAddressInput convertRect:self.browserAddressInput.bounds toView:self.view];
  if (self.view.isFlipped) rect.origin.y = NSHeight(self.view.bounds)-NSMaxY(rect);
  return rect;
}
- (void)sampleOverlay {
  NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
  if (self.overlayDocumentGeneration != self.browserSession.documentGeneration) {
      self.overlayDocumentGeneration = self.browserSession.documentGeneration;
    [self useFooterBanner:nil];
    self.headerContentColor=nil;
    if(self.headerColorChangedHandler)self.headerColorChangedHandler();
    self.footerColorNext = 0; self.footerCaptureNext = 0; self.footerColorPrimed = NO;
    [self updateFooterContentColor:nil animated:NO];
    self.overlayGeneration++; self.overlayNextProbe = 0; self.overlayNextFullProbe = 0; self.overlayClearProofUntil = 0;
    self.overlayQuickDelay = 0; // A slow previous document must not delay this one's confirmation.
    self.overlayDismissalProbePending = NO; self.overlayDismissalProbeAfter = 0;
    [self.overlayPolicy resetForNavigation];
    [self applyHeightMode];
  }
  if (!self.footerTransitionPending && !self.heightTransition.isAnimating && self.browserHostBottomConstraint.constant != (self.browserUsesReducedHeight ? -[self footerHeight] : 0)) [self applyHeightMode];
  if (!NSEqualSizes(self.documentFooterContentSize,self.view.bounds.size)) [self configureDocumentFooter];
  [self.overlayPolicy updateContentSize:self.view.bounds.size];
  [self sampleFooterContentColor];
  if (![self canSampleOverlay] || self.heightTransition.isAnimating || now < self.overlayNotBefore) {
    self.overlayClearProofUntil = 0;
    [self.overlayPolicy observe:nil atTime:now]; return;
  }
  if (self.browserSession.devToolsVisible) return;
  if (self.overlayInFlight || (self.overlayPolicy.manuallyOverridden && !self.footerBanner) || now < self.overlayNextProbe) return;
  [self.view layoutSubtreeIfNeeded];
  BOOL dismissal = self.overlayDismissalProbePending;
  BOOL quick = !dismissal && now < self.overlayNextFullProbe;
  self.overlayDismissalProbePending = NO;
  NSRect rect = [self overlayRect];
  NSSize contentSize = self.view.bounds.size, viewport = self.browserHostView.bounds.size;
  NSUInteger generation = self.overlayGeneration, document = self.browserSession.documentGeneration;
  self.overlayInFlight = YES;
  __weak typeof(self) weakSelf = self;
  [self.browserService probeOverlayInSession:self.browserSession overlayRect:rect viewportSize:viewport quick:quick completion:^(NSDictionary *result) {
    TLBrowserTabController *controller = weakSelf;
    if (!controller) return;
    controller.overlayInFlight = NO;
    NSTimeInterval completedAt = NSProcessInfo.processInfo.systemUptime;
    if (![controller canSampleOverlay] || controller.overlayGeneration != generation ||
        controller.browserSession.documentGeneration != document || completedAt < controller.overlayNotBefore ||
        !NSEqualSizes(contentSize, controller.view.bounds.size) || !NSEqualSizes(viewport, controller.browserHostView.bounds.size) ||
        !NSEqualRects(rect, [controller overlayRect])) {
      controller.overlayClearProofUntil = 0;
      [controller.overlayPolicy observe:nil atTime:completedAt]; return;
    }
    id value = result[@"obstructed"];
    NSNumber *known = [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ? value : nil;
    double cost = [result[@"costMS"] doubleValue];
    if (quick) {
      // An incomplete opaque fallback is not proof of clearance, but a finished
      // DOM scan can keep looking for ordinary banners while that fallback rests.
      controller.overlayQuickDelay = [TLBrowserOverlayPolicy quickDelayForCostMS:cost
        known:known != nil || [result[@"scanComplete"] boolValue]];
    } else {
      // A dismissal may borrow one full scan from the future. Repay it by
      // extending the existing deadline, and forbid another loan until then.
      NSTimeInterval base = dismissal ? MAX(completedAt, controller.overlayNextFullProbe) : completedAt;
      controller.overlayNextFullProbe = base + [TLBrowserOverlayPolicy delayForCostMS:cost known:known != nil];
      if (dismissal) controller.overlayDismissalProbeAfter = controller.overlayNextFullProbe;
      // A complete scan provides short-lived clearance; subsequent quick checks
      // can confirm its stability without repeating expensive full scans.
      controller.overlayClearProofUntil = [known isEqual:@NO] ? completedAt + 3.0 : 0;
      controller.overlayProofRect = rect; controller.overlayProofContentSize = contentSize;
    }
    controller.overlayPolicy.observationInterval = MAX(0.2, controller.overlayQuickDelay);
    controller.overlayNextProbe = completedAt + controller.overlayPolicy.observationInterval;
    if (!known || known.boolValue) controller.overlayClearProofUntil = 0;
    if (quick && [known isEqual:@NO] && (completedAt > controller.overlayClearProofUntil ||
        !NSEqualRects(rect, controller.overlayProofRect) || !NSEqualSizes(contentSize, controller.overlayProofContentSize))) {
      if (controller.overlayPolicy.reducedHeight && !controller.overlayPolicy.latchedReducedHeight &&
          completedAt >= controller.overlayDismissalProbeAfter) {
        controller.overlayDismissalProbePending = YES;
        controller.overlayNextProbe = completedAt;
      }
      known = nil;
    }
    if([known isEqual:@YES]) [controller useFooterBanner:[result[@"banner"] isKindOfClass:NSDictionary.class] ? result[@"banner"] : nil];
    BOOL placementChanged=[controller.overlayPolicy observe:known atTime:completedAt];
    if([known isEqual:@NO] && (!controller.overlayPolicy.reducedHeight || (!quick && (controller.overlayPolicy.manuallyOverridden || controller.overlayPolicy.latchedReducedHeight)))) [controller useFooterBanner:nil];
    if(placementChanged) [controller applyHeightMode];
    // Schedule from completion. A repeating tick otherwise rounds a 200ms
    // deadline up to almost 400ms because the reply arrives after the tick.
    controller.overlayTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:
      MAX(0.01, MAX(controller.overlayNextProbe, controller.overlayNotBefore)-NSProcessInfo.processInfo.systemUptime)];
  }];
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
  __weak typeof(self) weakSelf = self;
  self.browserChatPane.approvalHandler = ^BOOL(NSString *requestID, NSString *choice) {
    TLBrowserTabController *controller = weakSelf;
    if (!controller || controller.isClosed) return NO;
    TLAppSettings *settings = controller.settingsProvider ? controller.settingsProvider() : nil;
    if (!settings.openRouterToken.length || !settings.selectedModel.length) return NO;
    return [controller.browserConversation respondToApproval:requestID choice:choice token:settings.openRouterToken model:settings.selectedModel];
  };
  [self.browserChatPane showApprovalRequest:conversation.pendingApproval];
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
  return URL.absoluteString ?: @"";
}


@end
