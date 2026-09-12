#import "TLQuickInputWindowController.h"
#import "InputSuggestions.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLQuickInputPanel.h"
#import "design_system/TLNotchSurfaceView.h"
#import "design_system/TLTransitionCoordinator.h"
#import "design_system/TLScreenRegionSelectionView.h"
#import "TLScreenCapture.h"
#import <QuartzCore/QuartzCore.h>

@interface TLQuickInputWindowController () <NSWindowDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLGlassMessageInput *messageInput;
@property (nonatomic, strong) TLInputSuggestionPanelView *suggestionPanel;
@property (nonatomic, strong) TLInputSuggestionListView *suggestionList;
@property (nonatomic, strong) NSScreen *presentationScreen;
@property (nonatomic) CGFloat inputHeight;
@property (nonatomic) BOOL layingOut;
@property (nonatomic, strong) NSMutableSet<NSMenu *> *trackingMenus;
@property (nonatomic) BOOL focusCheckPending;
@property (nonatomic) BOOL showingSettings;
@property (nonatomic) BOOL sheetInteractionActive;
@property (nonatomic, strong) TLNotchSurfaceView *notchSurface;
@property (nonatomic, strong) NSView *inputContainer;
@property (nonatomic, strong) TLTransitionCoordinator *notchTransition;
@property (nonatomic) NSRect notchTargetFrame;
@property (nonatomic, strong) NSLayoutConstraint *inputLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputTopConstraint;
@property (nonatomic, strong) NSPanel *selectionWindow;
@property (nonatomic, strong) TLScreenRegionSelectionView *selectionView;
@property (nonatomic, strong) TLScreenCapture *screenCapture;
@property (nonatomic) BOOL captureInProgress;
@property (nonatomic) NSUInteger captureGeneration;
@end

@implementation TLQuickInputWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  TLQuickInputPanel *panel = [[TLQuickInputPanel alloc] initWithContentRect:NSMakeRect(0, 0, palette.messageInputMaxWidth, palette.composerButtonHeight)
    styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
  self = [super initWithWindow:panel];
  if (self) {
    _palette = palette;
    _model = @"";
    _supportingModel = @"";
    _commands = @[];
    _trackingMenus = [NSMutableSet set];
    _inputHeight = palette.composerButtonHeight;
    _notchTransition = [[TLTransitionCoordinator alloc] init];
    panel.title = @"Talaria Notch Input";
    panel.delegate = self;
    panel.opaque = NO;
    panel.hasShadow = NO;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.canHide = NO;
    panel.becomesKeyOnlyIfNeeded = NO;
    panel.level = NSStatusWindowLevel + 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.contentView.wantsLayer = YES;
    panel.contentView.layer.masksToBounds = YES;
    panel.animationBehavior = NSWindowAnimationBehaviorNone;
    __weak typeof(self) weakSelf = self;
    panel.dismissHandler = ^{ [weakSelf dismiss]; };
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(menuDidBeginTracking:) name:NSMenuDidBeginTrackingNotification object:nil];
    [notifications addObserver:self selector:@selector(menuDidEndTracking:) name:NSMenuDidEndTrackingNotification object:nil];
    [notifications addObserver:self selector:@selector(focusMayHaveChanged:) name:NSApplicationDidResignActiveNotification object:NSApp];
    [notifications addObserver:self selector:@selector(screenParametersDidChange:) name:NSApplicationDidChangeScreenParametersNotification object:nil];

    _notchSurface = [[TLNotchSurfaceView alloc] initWithFrame:panel.contentView.bounds];
    _notchSurface.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [panel.contentView addSubview:_notchSurface];
    // Keep the input at its final width while the surrounding notch resizes.
    _inputContainer = [[NSView alloc] initWithFrame:panel.contentView.bounds];
    _inputContainer.wantsLayer = YES;
    [panel.contentView addSubview:_inputContainer];
    _screenCapture = [[TLScreenCapture alloc] init];

    _messageInput = [[TLGlassMessageInput alloc] init];
    _messageInput.showsBackground = NO;
    _messageInput.attachmentsEnabled = YES;
    _messageInput.showsSettingsButton = YES;
    _messageInput.textView.delegate = self;
    _messageInput.sendButton.target = self;
    _messageInput.sendButton.action = @selector(submit:);
    _messageInput.settingsButton.target = self;
    _messageInput.settingsButton.action = @selector(showSettings:);
    _messageInput.textChangeHandler = ^{ [weakSelf updateSuggestions]; };
    _messageInput.attachmentsChangeHandler = ^{ [weakSelf updateSuggestions]; };
    _messageInput.heightChangeHandler = ^(CGFloat height) {
      weakSelf.inputHeight = height;
      [weakSelf layoutPanel];
    };
    [_inputContainer addSubview:_messageInput];
    _inputLeadingConstraint = [_messageInput.leadingAnchor constraintEqualToAnchor:_inputContainer.leadingAnchor];
    _inputTrailingConstraint = [_messageInput.trailingAnchor constraintEqualToAnchor:_inputContainer.trailingAnchor];
    _inputTopConstraint = [_messageInput.topAnchor constraintEqualToAnchor:_inputContainer.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
      _inputLeadingConstraint, _inputTrailingConstraint, _inputTopConstraint,
    ]];

    _suggestionPanel = [[TLInputSuggestionPanelView alloc] init];
    _suggestionPanel.translatesAutoresizingMaskIntoConstraints = YES;
    _suggestionPanel.hidden = YES;
    _suggestionList = [[TLInputSuggestionListView alloc] init];
    _suggestionList.activationHandler = ^(NSUInteger index) { [weakSelf performSuggestionAtIndex:index completing:NO]; };
    [_suggestionPanel addSubview:_suggestionList];
    [_inputContainer addSubview:_suggestionPanel];
    [NSLayoutConstraint activateConstraints:@[
      [_suggestionList.leadingAnchor constraintEqualToAnchor:_suggestionPanel.leadingAnchor constant:palette.space3],
      [_suggestionList.trailingAnchor constraintEqualToAnchor:_suggestionPanel.trailingAnchor constant:-palette.space3],
      [_suggestionList.topAnchor constraintEqualToAnchor:_suggestionPanel.topAnchor constant:palette.space2],
      [_suggestionList.bottomAnchor constraintEqualToAnchor:_suggestionPanel.bottomAnchor constant:-palette.space2],
    ]];
    [self applyPalette:palette];
    [self updateSuggestions];
  }
  return self;
}

- (void)dealloc {
  [_notchTransition cancelAllTransitions];
  [_screenCapture cancel];
  [_selectionWindow orderOut:nil];
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)screenParametersDidChange:(NSNotification *)notification { [self dismiss]; }

- (void)windowDidResignKey:(NSNotification *)notification {
  [self focusMayHaveChanged:notification];
}

- (void)windowWillClose:(NSNotification *)notification {
  [self cancelNotchTransition];
  [self cancelCapture];
  [self.selectionWindow orderOut:self];
  if (self.visibilityChangeHandler) self.visibilityChangeHandler(NO);
}

- (void)windowWillBeginSheet:(NSNotification *)notification {
  self.sheetInteractionActive = YES;
  [self updateSelectionWindow];
}

- (void)windowDidEndSheet:(NSNotification *)notification {
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    typeof(self) owner = weakSelf;
    if (!owner) return;
    // A nonactivating panel may not regain key status automatically after an
    // NSOpenPanel closes. Return to the draft once AppKit has detached the sheet.
    if (owner.window.visible) {
      [owner.window makeKeyAndOrderFront:owner];
      [owner.window makeFirstResponder:owner.messageInput.textView];
    }
    owner.sheetInteractionActive = NO;
    [owner updateSelectionWindow];
    [owner focusMayHaveChanged:notification];
  });
}

- (void)menuDidBeginTracking:(NSNotification *)notification {
  if (self.window.visible) [self.trackingMenus addObject:notification.object];
  [self updateSelectionWindow];
}

- (void)menuDidEndTracking:(NSNotification *)notification {
  [self.trackingMenus removeObject:notification.object];
  [self updateSelectionWindow];
  [self focusMayHaveChanged:notification];
}

- (void)focusMayHaveChanged:(NSNotification *)notification {
  if (!self.window.visible || self.focusCheckPending) return;
  self.focusCheckPending = YES;
  __weak typeof(self) weakSelf = self;
  // AppKit can resign key before attaching a sheet or beginning menu tracking.
  // Recheck after that transition, including any focus restored when it ends.
  dispatch_async(dispatch_get_main_queue(), ^{
    typeof(self) owner = weakSelf;
    if (!owner) return;
    owner.focusCheckPending = NO;
    if (owner.window.visible && !owner.window.keyWindow && !owner.window.attachedSheet &&
        !owner.trackingMenus.count && !owner.showingSettings && !owner.sheetInteractionActive && !owner.captureInProgress) {
      [owner dismiss];
    }
  });
}

- (void)presentInNotchOnScreen:(NSScreen *)screen {
  [self presentInNotchOnScreen:screen fromFrame:NSZeroRect];
}

- (void)presentInNotchOnScreen:(NSScreen *)screen fromFrame:(NSRect)frame {
  if (self.window.attachedSheet || self.captureInProgress) return;
  if (self.presentationScreen != screen) [self cancelNotchTransition];
  BOOL wasVisible = self.window.visible;
  self.presentationScreen = screen;
  [self applyPalette:self.palette];
  [self updateSuggestions];
  if (!wasVisible && !NSIsEmptyRect(frame)) {
    [self expandNotchFromFrame:frame];
  }
  [self.window makeKeyAndOrderFront:self];
  [self.window makeFirstResponder:self.messageInput.textView];
  // Cover the compact notch at its current size before its tracking window hides.
  if (!wasVisible && self.visibilityChangeHandler) self.visibilityChangeHandler(YES);
  [self updateSelectionWindow];
}

- (void)dismiss {
  BOOL wasVisible = self.window.visible;
  [self cancelNotchTransition];
  [self cancelCapture];
  [self.selectionWindow orderOut:self];
  // Keep the live composer (including its attachment URLs) as the next draft.
  [self.trackingMenus removeAllObjects];
  NSWindow *sheet = self.window.attachedSheet;
  if (sheet) {
    [self.window endSheet:sheet returnCode:NSModalResponseCancel];
    [sheet orderOut:self];
  }
  [self.window orderOut:self];
  if (wasVisible && self.visibilityChangeHandler) self.visibilityChangeHandler(NO);
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  // The hardware notch remains black in both app themes; resolve its content for that surface.
  TLThemePalette *contentPalette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  self.window.appearance = [NSAppearance appearanceNamed:contentPalette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.transparentSurface;
  self.notchSurface.palette = palette;
  self.messageInput.palette = contentPalette;
  self.suggestionPanel.palette = contentPalette;
  self.suggestionList.palette = contentPalette;
  self.selectionView.palette = palette;
  [self layoutPanel];
}

- (void)setCommands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands {
  _commands = [commands copy];
  [self updateSuggestions];
}

- (void)updateSuggestions {
  NSString *text = self.messageInput.textView.string ?: @"";
  NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSArray *suggestions = self.messageInput.attachmentURLs.count ? @[] :
    ([trimmed hasPrefix:@"/"] ? [TLInputSuggestions slashCommandsForInput:text commands:self.commands]
                              : [TLInputSuggestions webSuggestionsForInput:trimmed]);
  BOOL changed = ![self.suggestionList.suggestions isEqualToArray:suggestions];
  self.suggestionList.suggestions = suggestions;
  if (changed) self.suggestionList.selectedIndex = -1;
  self.suggestionPanel.hidden = suggestions.count == 0;
  self.messageInput.sendButton.enabled = !self.captureInProgress && (trimmed.length > 0 || self.messageInput.attachmentURLs.count > 0);
  [self.messageInput recalculateHeight];
  [self layoutPanel];
}

- (void)layoutPanel {
  if (self.layingOut || !self.presentationScreen) return;
  self.layingOut = YES;
  TLThemePalette *palette = self.palette;
  NSRect visibleFrame = self.presentationScreen.visibleFrame;
  CGFloat inset = palette.notchOverlayTopFlareOutset + palette.space4;
  CGFloat inputWidth = palette.notchInputMaxWidth;
  CGFloat width = MIN(inputWidth + inset * 2, NSWidth(visibleFrame) - palette.space11 * 2);
  CGFloat cameraInset = self.presentationScreen.safeAreaInsets.top;
  CGFloat topPadding = cameraInset > 0 ? MAX(cameraInset, palette.notchOverlayMinimumHeight) : palette.notchInputVerticalPadding;
  CGFloat bottomPadding = palette.notchInputVerticalPadding;
  self.inputLeadingConstraint.constant = inset;
  self.inputTrailingConstraint.constant = -inset;
  self.inputTopConstraint.constant = topPadding;
  CGFloat suggestionsHeight = self.suggestionPanel.hidden ? 0 :
    MIN(self.suggestionList.contentHeight + palette.space2 * 2, (palette.slashCommandRowHeight + palette.space2) * 8);
  self.suggestionList.scrollingEnabled = self.suggestionList.contentHeight + palette.space2 * 2 > suggestionsHeight;
  CGFloat gap = suggestionsHeight > 0 ? palette.space5 : 0;
  CGFloat x = MIN(MAX(NSMidX(self.presentationScreen.frame) - width / 2, NSMinX(visibleFrame)), NSMaxX(visibleFrame) - width);
  CGFloat topEdge = NSMaxY(self.presentationScreen.frame);
  // A width change may cause TextKit to update the input's height during layout.
  for (NSUInteger pass = 0; pass < 2; pass++) {
    CGFloat height = topPadding + self.inputHeight + gap + suggestionsHeight + bottomPadding;
    NSRect frame = NSMakeRect(x, MAX(NSMinY(visibleFrame), topEdge - height), width, height);
    self.notchTargetFrame = frame;
    self.inputContainer.frame = NSMakeRect(0, 0, width, height);
    if (!self.notchTransition.hasTransitions) [self.window setFrame:frame display:YES];
    [self positionInputContainer];
    self.suggestionPanel.frame = NSMakeRect(inset, bottomPadding, width - inset * 2, suggestionsHeight);
    [self.inputContainer layoutSubtreeIfNeeded];
  }
  self.layingOut = NO;
  [self updateSelectionWindow];
}

- (void)positionInputContainer {
  NSSize available = self.window.contentView.bounds.size;
  NSSize content = self.inputContainer.frame.size;
  [self.inputContainer setFrameOrigin:NSMakePoint((available.width - content.width) * 0.5,
                                                 available.height - content.height)];
}

- (void)interpolateNotchFromFrame:(NSRect)start toFrame:(NSRect)target progress:(CGFloat)progress {
  NSRect frame = NSMakeRect(start.origin.x + (target.origin.x - start.origin.x) * progress,
    start.origin.y + (target.origin.y - start.origin.y) * progress,
    start.size.width + (target.size.width - start.size.width) * progress,
    start.size.height + (target.size.height - start.size.height) * progress);
  [self.window setFrame:frame display:YES];
  [self positionInputContainer];
  self.notchSurface.needsDisplay = YES;
}

- (void)expandNotchFromFrame:(NSRect)start {
  self.inputContainer.alphaValue = 0.0;
  __weak typeof(self) weakSelf = self;
  [self.notchTransition startTransitionForKey:@"notchExpansion"
    duration:self.palette.notchInputExpansionDuration curve:TLTransitionCurveEaseInOut
    update:^(CGFloat progress) {
      typeof(self) owner = weakSelf;
      if (!owner) return;
      NSRect target = owner.notchTargetFrame;
      CGFloat width = NSWidth(target) * owner.palette.notchInputOvershootScale;
      CGFloat height = NSHeight(target) * owner.palette.notchInputOvershootScale;
      NSRect overshoot = NSMakeRect(NSMidX(target) - width * 0.5, NSMaxY(target) - height, width, height);
      [owner interpolateNotchFromFrame:start toFrame:overshoot progress:progress];
    } completion:^(BOOL finished) {
      if (!finished) return;
      NSRect overshoot = weakSelf.window.frame;
      [weakSelf.notchTransition startTransitionForKey:@"notchInputReveal"
        duration:weakSelf.palette.notchInputRevealDuration update:^(CGFloat progress) {
          [weakSelf interpolateNotchFromFrame:overshoot toFrame:weakSelf.notchTargetFrame progress:progress];
          weakSelf.inputContainer.alphaValue = progress;
        } completion:^(BOOL settled) {
          if (settled) [weakSelf layoutPanel];
        }];
    }];
}

- (void)cancelNotchTransition {
  [self.notchTransition cancelAllTransitions];
  self.inputContainer.alphaValue = 1.0;
}

- (void)updateSelectionWindow {
  BOOL enabled = self.window.visible && !self.captureInProgress &&
    !self.sheetInteractionActive && !self.window.attachedSheet && !self.trackingMenus.count && !self.showingSettings;
  if (!enabled) { [self.selectionWindow orderOut:self]; return; }
  if (!self.selectionWindow) {
    NSPanel *panel = [[TLScreenRegionSelectionPanel alloc] initWithContentRect:NSZeroRect
      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.opaque = NO;
    panel.hasShadow = NO;
    panel.hidesOnDeactivate = NO;
    panel.canHide = NO;
    panel.releasedWhenClosed = NO;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.ignoresMouseEvents = NO;
    panel.animationBehavior = NSWindowAnimationBehaviorNone;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.selectionWindow = panel;
    self.selectionView = [[TLScreenRegionSelectionView alloc] init];
    panel.contentView = self.selectionView;
    __weak typeof(self) weakSelf = self;
    self.selectionView.selectionHandler = ^(NSRect rect) { [weakSelf captureSelection:rect]; };
    self.selectionView.cancelHandler = ^{ [weakSelf dismiss]; };
  }
  self.selectionWindow.backgroundColor = self.palette.transparentSurface;
  self.selectionView.palette = self.palette;
  self.selectionWindow.level = self.window.level - 1;
  [self.selectionWindow setFrame:self.presentationScreen.frame display:YES];
  [self.selectionWindow orderWindow:NSWindowBelow relativeTo:self.window.windowNumber];
}

- (void)cancelCapture {
  self.captureGeneration++;
  [self.screenCapture cancel];
  self.captureInProgress = NO;
  self.messageInput.attachmentsEditable = YES;
  [self.selectionView resetSelection];
}

- (void)captureSelection:(NSRect)rect {
  if (self.captureInProgress || !self.window.visible) return;
  [self.notchTransition finishAllTransitions];
  self.captureInProgress = YES;
  NSUInteger generation = ++self.captureGeneration;
  self.messageInput.attachmentsEditable = NO;
  self.messageInput.sendButton.enabled = NO;
  [self.selectionWindow orderOut:self];
  NSArray<NSNumber *> *excludedWindows = @[@(self.window.windowNumber), @(self.selectionWindow.windowNumber)];
  [self.selectionView resetSelection];
  [CATransaction flush];
  __weak typeof(self) weakSelf = self;
  // Let the selection border clear; the notch stays visible and is filtered from capture.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    typeof(self) owner = weakSelf;
    if (!owner || owner.captureGeneration != generation || !owner.window.visible) return;
    [owner.screenCapture captureRect:rect excludingWindowIDs:excludedWindows completion:^(NSURL *URL, NSError *error) {
      typeof(self) current = weakSelf;
      if (!current || current.captureGeneration != generation || !current.window.visible) return;
      [current cancelCapture];
      if (URL) [current.messageInput addAttachmentURLs:@[URL]];
      if (error) {
        current.showingSettings = YES;
        [NSApp presentError:error];
        current.showingSettings = NO;
      }
      [current.window makeKeyAndOrderFront:current];
      [current.window makeFirstResponder:current.messageInput.textView];
      [current updateSuggestions];
    }];
  });
}

- (BOOL)moveSelection:(NSInteger)offset {
  return [self.suggestionList moveSelectionByOffset:offset];
}

- (BOOL)performSuggestionAtIndex:(NSUInteger)index completing:(BOOL)completing {
  if (index >= self.suggestionList.suggestions.count || ![self.suggestionList isSuggestionEnabledAtIndex:index]) return NO;
  NSDictionary *suggestion = self.suggestionList.suggestions[index];
  if ([suggestion[@"kind"] isEqualToString:@"hermes"]) {
    NSString *command = suggestion[@"command"];
    NSString *text = [self.messageInput.textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (completing || [text caseInsensitiveCompare:command] != NSOrderedSame) {
      self.messageInput.textView.string = [command stringByAppendingString:@" "];
      [self updateSuggestions];
      [self.window makeFirstResponder:self.messageInput.textView];
      [self.messageInput.textView setSelectedRange:NSMakeRange(self.messageInput.textView.string.length, 0)];
    } else {
      [self submitAllowingAutomaticRouting:NO];
    }
  } else {
    if (completing) return NO;
    [self submitAllowingAutomaticRouting:![suggestion[@"kind"] isEqualToString:@"prompt"]];
  }
  return YES;
}

- (void)submit:(id)sender {
  if (!self.window.visible || self.window.attachedSheet || self.captureInProgress) return;
  [self updateSuggestions];
  NSInteger index = self.suggestionList.selectedIndex;
  if (index >= 0 && [self performSuggestionAtIndex:index completing:NO]) return;
  [self submitAllowingAutomaticRouting:YES];
}

- (void)submitAllowingAutomaticRouting:(BOOL)allowAutomaticRouting {
  if (!self.window.visible || self.window.attachedSheet || self.captureInProgress) return;
  NSString *text = [self.messageInput.textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSArray<NSURL *> *files = self.messageInput.attachmentURLs;
  if ((!text.length && !files.count) || !self.submissionHandler) return;
  [self dismiss];
  self.messageInput.textView.string = @"";
  [self.messageInput setAttachmentURLs:@[] animated:NO];
  [self updateSuggestions];
  self.submissionHandler(text, files, allowAutomaticRouting);
}

- (void)showSettings:(id)sender {
  self.showingSettings = YES;
  [self updateSelectionWindow];
  @try {
    if (self.settingsHandler) self.settingsHandler();
  } @finally {
    self.showingSettings = NO;
    [self updateSelectionWindow];
    [self focusMayHaveChanged:nil];
  }
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(cancelOperation:)) { [self dismiss]; return YES; }
  if (commandSelector == @selector(moveUp:)) return [self moveSelection:-1];
  if (commandSelector == @selector(moveDown:)) return [self moveSelection:1];
  if (commandSelector == @selector(insertTab:) && self.suggestionList.suggestions.count) {
    if (self.suggestionList.selectedIndex < 0) [self moveSelection:1];
    return [self performSuggestionAtIndex:self.suggestionList.selectedIndex completing:YES];
  }
  if (commandSelector == @selector(insertNewline:) && !(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)) {
    [self submit:textView];
    return YES;
  }
  return NO;
}
@end
