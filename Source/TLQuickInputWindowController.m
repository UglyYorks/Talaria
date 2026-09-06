#import "TLQuickInputWindowController.h"
#import "InputSuggestions.h"
#import "design_system/TLInputSuggestionListView.h"
#import "design_system/TLInputSuggestionPanelView.h"
#import "design_system/TLQuickInputPanel.h"

@interface TLQuickInputWindowController () <NSWindowDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLGlassMessageInput *messageInput;
@property (nonatomic, strong) TLInputSuggestionPanelView *suggestionPanel;
@property (nonatomic, strong) TLInputSuggestionListView *suggestionList;
@property (nonatomic, strong) NSScreen *presentationScreen;
@property (nonatomic) CGFloat inputHeight;
@property (nonatomic) NSRect anchorRect;
@property (nonatomic) BOOL layingOut;
@property (nonatomic, strong) NSMutableSet<NSMenu *> *trackingMenus;
@property (nonatomic) BOOL focusCheckPending;
@property (nonatomic) BOOL showingSettings;
@property (nonatomic) BOOL sheetInteractionActive;
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
    panel.title = @"Talaria Quick Input";
    panel.delegate = self;
    panel.opaque = NO;
    panel.hasShadow = YES;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.canHide = NO;
    panel.becomesKeyOnlyIfNeeded = NO;
    panel.level = NSFloatingWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    __weak typeof(self) weakSelf = self;
    panel.dismissHandler = ^{ [weakSelf dismiss]; };
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(menuDidBeginTracking:) name:NSMenuDidBeginTrackingNotification object:nil];
    [notifications addObserver:self selector:@selector(menuDidEndTracking:) name:NSMenuDidEndTrackingNotification object:nil];
    [notifications addObserver:self selector:@selector(focusMayHaveChanged:) name:NSApplicationDidResignActiveNotification object:NSApp];

    _messageInput = [[TLGlassMessageInput alloc] init];
    _messageInput.usesChatBackdrop = YES;
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
    [panel.contentView addSubview:_messageInput];
    [NSLayoutConstraint activateConstraints:@[
      [_messageInput.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor],
      [_messageInput.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor],
      [_messageInput.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor],
    ]];

    _suggestionPanel = [[TLInputSuggestionPanelView alloc] init];
    _suggestionPanel.translatesAutoresizingMaskIntoConstraints = YES;
    _suggestionPanel.hidden = YES;
    _suggestionList = [[TLInputSuggestionListView alloc] init];
    _suggestionList.activationHandler = ^(NSUInteger index) { [weakSelf performSuggestionAtIndex:index completing:NO]; };
    [_suggestionPanel addSubview:_suggestionList];
    [panel.contentView addSubview:_suggestionPanel];
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
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)windowDidResignKey:(NSNotification *)notification {
  [self focusMayHaveChanged:notification];
}

- (void)windowWillClose:(NSNotification *)notification {
  if (self.visibilityChangeHandler) self.visibilityChangeHandler(NO);
}

- (void)windowWillBeginSheet:(NSNotification *)notification {
  self.sheetInteractionActive = YES;
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
    [owner focusMayHaveChanged:notification];
  });
}

- (void)menuDidBeginTracking:(NSNotification *)notification {
  if (self.window.visible) [self.trackingMenus addObject:notification.object];
}

- (void)menuDidEndTracking:(NSNotification *)notification {
  [self.trackingMenus removeObject:notification.object];
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
        !owner.trackingMenus.count && !owner.showingSettings && !owner.sheetInteractionActive) {
      [owner dismiss];
    }
  });
}

- (void)presentOnScreen:(NSScreen *)screen {
  [self presentBelowRect:NSMakeRect(NSMidX(screen.frame), NSMaxY(screen.visibleFrame), 0, 0) onScreen:screen];
}

- (void)presentBelowRect:(NSRect)anchorRect onScreen:(NSScreen *)screen {
  if (self.window.attachedSheet) return;
  self.presentationScreen = screen;
  self.anchorRect = anchorRect;
  [self updateSuggestions];
  if (!self.window.visible && self.visibilityChangeHandler) self.visibilityChangeHandler(YES);
  [self.window makeKeyAndOrderFront:self];
  [self.window makeFirstResponder:self.messageInput.textView];
}

- (void)dismiss {
  BOOL wasVisible = self.window.visible;
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
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.transparentSurface;
  self.messageInput.palette = palette;
  self.suggestionPanel.palette = palette;
  self.suggestionList.palette = palette;
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
  self.messageInput.sendButton.enabled = trimmed.length > 0 || self.messageInput.attachmentURLs.count > 0;
  [self.messageInput recalculateHeight];
  [self layoutPanel];
}

- (void)layoutPanel {
  if (self.layingOut || !self.presentationScreen) return;
  self.layingOut = YES;
  TLThemePalette *palette = self.palette;
  NSRect visibleFrame = self.presentationScreen.visibleFrame;
  CGFloat width = MIN(palette.messageInputMaxWidth, NSWidth(visibleFrame) - palette.space11 * 2);
  CGFloat suggestionsHeight = self.suggestionPanel.hidden ? 0 :
    MIN(self.suggestionList.contentHeight + palette.space2 * 2, (palette.slashCommandRowHeight + palette.space2) * 8);
  self.suggestionList.scrollingEnabled = self.suggestionList.contentHeight + palette.space2 * 2 > suggestionsHeight;
  CGFloat gap = suggestionsHeight > 0 ? palette.space5 : 0;
  CGFloat x = MIN(MAX(NSMidX(self.anchorRect) - width / 2, NSMinX(visibleFrame)), NSMaxX(visibleFrame) - width);
  // Stay just below the clicked notch as text, attachments and suggestions grow down.
  CGFloat topEdge = MIN(NSMinY(self.anchorRect), NSMaxY(visibleFrame)) - palette.space5;
  // A width change may cause TextKit to update the input's height during layout.
  for (NSUInteger pass = 0; pass < 2; pass++) {
    CGFloat height = self.inputHeight + gap + suggestionsHeight;
    NSRect frame = NSMakeRect(x, MAX(NSMinY(visibleFrame), topEdge - height), width, height);
    [self.window setFrame:frame display:YES];
    self.suggestionPanel.frame = NSMakeRect(0, 0, width, suggestionsHeight);
    [self.window.contentView layoutSubtreeIfNeeded];
  }
  self.layingOut = NO;
}

- (BOOL)moveSelection:(NSInteger)offset {
  NSInteger count = self.suggestionList.suggestions.count;
  if (!count) return NO;
  NSInteger index = self.suggestionList.selectedIndex;
  for (NSInteger attempt = 0; attempt < count; attempt++) {
    index = index < 0 ? (offset < 0 ? count - 1 : 0) : (index + offset + count) % count;
    if ([self.suggestionList isSuggestionEnabledAtIndex:index]) {
      self.suggestionList.selectedIndex = index;
      break;
    }
  }
  return YES;
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
  if (!self.window.visible || self.window.attachedSheet) return;
  [self updateSuggestions];
  NSInteger index = self.suggestionList.selectedIndex;
  if (index >= 0 && [self performSuggestionAtIndex:index completing:NO]) return;
  [self submitAllowingAutomaticRouting:YES];
}

- (void)submitAllowingAutomaticRouting:(BOOL)allowAutomaticRouting {
  if (!self.window.visible || self.window.attachedSheet) return;
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
  @try {
    if (self.settingsHandler) self.settingsHandler();
  } @finally {
    self.showingSettings = NO;
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
