#import "TLChatPresentation.h"
#import "MarkdownRenderer.h"

@interface TLChatPresentation ()
@property (nonatomic, strong, readwrite) TLFindBar *findBar;
@property (nonatomic, strong) NSLayoutConstraint *findBarHeight;
@property (nonatomic, copy) NSArray<NSView *> *findViews;
@property (nonatomic, copy) NSArray<NSNumber *> *findCounts;
@property (nonatomic, strong) NSMapTable<NSView *, NSAttributedString *> *findOriginalText;
@property (nonatomic) NSUInteger findGeneration;
@property (nonatomic) NSInteger findMatchIndex;
@property (nonatomic) BOOL findRefreshScheduled;
@property (nonatomic) BOOL revealFindMatch;
@end

@implementation TLChatPresentation
- (instancetype)init {
  if ((self = [super init])) {
    _messages = [NSMutableArray array];
    _queuedPrompts = [NSMutableArray array];
    _messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
    _messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
    _messageMarkdownViews = [NSMapTable strongToStrongObjectsMapTable];
    _messageActivityViews = [NSMapTable strongToStrongObjectsMapTable];
    _errorMessage = @"";
  }
  return self;
}
- (void)installFindBarInView:(NSView *)view palette:(TLThemePalette *)palette {
  self.findBar = [TLFindBar new];
  self.findBar.searchLabel = @"Find in chat";
  self.findBar.palette = palette;
  self.findBar.hidden = YES;
  self.findBar.translatesAutoresizingMaskIntoConstraints = NO;
  [view addSubview:self.findBar];
  self.findBarHeight = [self.findBar.heightAnchor constraintEqualToConstant:0];
  [NSLayoutConstraint activateConstraints:@[
    [self.findBar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
    [self.findBar.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
    [self.findBar.topAnchor constraintEqualToAnchor:view.topAnchor], self.findBarHeight
  ]];
  self.findOriginalText = [NSMapTable weakToStrongObjectsMapTable];
  __weak typeof(self) weakSelf = self;
  self.findBar.queryChangedHandler = ^{
    weakSelf.findMatchIndex = 0;
    weakSelf.revealFindMatch = YES;
    [weakSelf refreshFindResults];
  };
  self.findBar.navigateHandler = ^(BOOL forward) { [weakSelf findNext:forward]; };
  self.findBar.closeHandler = ^{ [weakSelf hideFindBar]; };
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(findDocumentChanged:)
    name:TLMarkdownContentDidChangeNotification object:nil];
}
- (void)findDocumentChanged:(NSNotification *)notification {
  if ([notification.object isKindOfClass:NSView.class] && [notification.object isDescendantOf:self.messageStack]) [self refreshFindResults];
}
- (BOOL)findBarVisible { return self.findBar && !self.findBar.hidden; }
- (void)applyFindPalette:(TLThemePalette *)palette {
  self.findBar.palette = palette;
  self.findBarHeight.constant = self.findBarVisible ? palette.fieldHeight + palette.space4 * 2 : 0;
}
- (void)showFindBar {
  BOOL wasVisible = self.findBarVisible;
  self.findBar.hidden = NO;
  [self applyFindPalette:self.findBar.palette];
  [self.findBar.superview layoutSubtreeIfNeeded];
  [self.findBar focusSearchField];
  if (!wasVisible) { self.findMatchIndex = 0; self.revealFindMatch = YES; [self refreshFindResults]; }
}
- (NSArray<NSValue *> *)rangesForText:(NSString *)text {
  NSString *query = self.findBar.searchField.stringValue;
  NSMutableArray *ranges = [NSMutableArray array];
  if (!query.length) return ranges;
  NSUInteger start = 0;
  while (start < text.length) {
    NSRange range = [text rangeOfString:query options:NSCaseInsensitiveSearch range:NSMakeRange(start, text.length - start)];
    if (range.location == NSNotFound) break;
    [ranges addObject:[NSValue valueWithRange:range]];
    start = NSMaxRange(range);
  }
  return ranges;
}
- (void)clearFindInView:(NSView *)view {
  if ([view isKindOfClass:NSTextField.class]) {
    NSAttributedString *original = [self.findOriginalText objectForKey:view];
    if (original) ((NSTextField *)view).attributedStringValue = original;
  } else [TLMarkdownRenderer findText:@"" inView:view completion:^(NSInteger count) {}];
}
- (void)hideFindBar {
  if (!self.findBarVisible) return;
  NSResponder *responder = self.findBar.window.firstResponder;
  BOOL ownsFocus = responder == self.findBar.searchField.currentEditor ||
    ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.findBar]);
  if (ownsFocus) [self.findBar.window makeFirstResponder:nil];
  self.findBar.hidden = YES;
  self.findBarHeight.constant = 0;
  self.findGeneration++;
  for (NSView *view in self.findViews) [self clearFindInView:view];
  self.findViews = @[]; self.findCounts = @[];
  [self.findOriginalText removeAllObjects];
  [self.findBar setMatchCount:0 activeMatch:0 searching:NO];
  [self.findBar.superview layoutSubtreeIfNeeded];
  if (ownsFocus) [self.findBar.window makeFirstResponder:self.promptTextView];
}
- (void)refreshFindResults {
  if (!self.findBarVisible) return;
  self.findGeneration++;
  self.findCounts = @[];
  [self.findBar setMatchCount:0 activeMatch:0 searching:self.findBar.searchField.stringValue.length > 0];
  if (self.findRefreshScheduled) return;
  self.findRefreshScheduled = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    TLChatPresentation *presentation = weakSelf;
    presentation.findRefreshScheduled = NO;
    if (presentation.findBarVisible) [presentation collectFindResults];
  });
}
- (void)collectFindResults {
  NSUInteger generation = self.findGeneration;
  NSString *query = self.findBar.searchField.stringValue;
  NSMutableArray<NSView *> *views = [NSMutableArray array];
  for (TLChatMessage *message in self.messages) {
    NSView *view = [self.messageMarkdownViews objectForKey:message];
    if (view && [view isDescendantOf:self.messageStack]) [views addObject:view];
  }
  for (NSView *old in self.findViews) if (![views containsObject:old]) [self clearFindInView:old];
  self.findViews = views;
  NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
  for (NSUInteger index = 0; index < views.count; index++) [counts addObject:@0];
  [self.findBar setMatchCount:0 activeMatch:0 searching:query.length && views.count];
  dispatch_group_t group = dispatch_group_create();
  [views enumerateObjectsUsingBlock:^(NSView *view, NSUInteger index, BOOL *stop) {
    if ([view isKindOfClass:NSTextField.class]) {
      NSTextField *label = (id)view;
      if (![self.findOriginalText objectForKey:view]) [self.findOriginalText setObject:label.attributedStringValue forKey:view];
      counts[index] = @([self rangesForText:label.stringValue].count);
    } else {
      dispatch_group_enter(group);
      [TLMarkdownRenderer findText:query inView:view completion:^(NSInteger count) {
        counts[index] = @(count);
        dispatch_group_leave(group);
      }];
    }
  }];
  __weak typeof(self) weakSelf = self;
  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    TLChatPresentation *presentation = weakSelf;
    if (!presentation.findBarVisible || presentation.findGeneration != generation) return;
    presentation.findCounts = counts;
    [presentation displayFindMatch];
  });
}
- (NSInteger)findMatchCount {
  NSInteger count = 0;
  for (NSNumber *value in self.findCounts) count += value.integerValue;
  return count;
}
- (void)findNext:(BOOL)forward {
  if (!self.findBarVisible) { [self showFindBar]; return; }
  if (!self.findBar.searchField.stringValue.length) { [self.findBar focusSearchField]; return; }
  NSInteger count = [self findMatchCount];
  if (!count) return;
  self.findMatchIndex = (self.findMatchIndex + (forward ? 1 : count - 1)) % count;
  self.revealFindMatch = YES;
  [self displayFindMatch];
}
- (void)revealFindRect:(NSRect)rect inView:(NSView *)view generation:(NSUInteger)generation {
  if (!self.findBarVisible || generation != self.findGeneration || NSIsEmptyRect(rect)) return;
  if (NSMinY(rect) < 0 || NSMaxY(rect) > NSHeight(view.bounds) + 1) return;
  [self.messageDocumentView layoutSubtreeIfNeeded];
  NSRect target = [view convertRect:rect toView:self.messageDocumentView];
  // Center above the floating composer, including matches deep inside a long message.
  CGFloat visibleHeight = NSHeight(self.messageScrollView.contentView.bounds);
  CGFloat availableHeight = MAX(1, visibleHeight - NSHeight(self.messageInput.bounds) - self.findBar.palette.space10);
  CGFloat maximumY = MAX(0, NSHeight(self.messageDocumentView.bounds) - visibleHeight);
  NSPoint point = NSMakePoint(0, MIN(maximumY, MAX(0, NSMidY(target) - availableHeight / 2)));
  [self.messageScrollView.contentView scrollToPoint:point];
  [self.messageScrollView reflectScrolledClipView:self.messageScrollView.contentView];
  self.revealFindMatch = NO;
}
- (void)displayFindMatch {
  NSInteger total = [self findMatchCount];
  self.findMatchIndex = total ? MIN(self.findMatchIndex, total - 1) : 0;
  [self.findBar setMatchCount:total activeMatch:total ? self.findMatchIndex + 1 : 0 searching:NO];
  NSInteger offset = 0;
  BOOL reveal = self.revealFindMatch;
  NSUInteger generation = self.findGeneration;
  for (NSUInteger i = 0; i < self.findViews.count; i++) {
    NSView *view = self.findViews[i];
    NSInteger count = self.findCounts[i].integerValue;
    NSInteger local = self.findMatchIndex >= offset && self.findMatchIndex < offset + count ? self.findMatchIndex - offset : -1;
    offset += count;
    if ([view isKindOfClass:NSTextField.class]) {
      NSTextField *label = (id)view;
      NSMutableAttributedString *text = [[self.findOriginalText objectForKey:view] mutableCopy];
      NSArray<NSValue *> *ranges = [self rangesForText:text.string];
      TLThemePalette *palette = self.findBar.palette;
      [ranges enumerateObjectsUsingBlock:^(NSValue *value, NSUInteger index, BOOL *stop) {
        [text addAttributes:@{NSBackgroundColorAttributeName:(NSInteger)index == local ? palette.findActiveMatchSurface : palette.findMatchSurface,
          NSForegroundColorAttributeName:palette.findMatchText} range:value.rangeValue];
      }];
      label.attributedStringValue = text;
      if (reveal && local >= 0) {
        NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:text];
        NSLayoutManager *layout = [NSLayoutManager new];
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(NSWidth(label.bounds), CGFLOAT_MAX)];
        container.lineFragmentPadding = 0;
        [storage addLayoutManager:layout]; [layout addTextContainer:container];
        NSRect rect = [layout boundingRectForGlyphRange:[layout glyphRangeForCharacterRange:ranges[local].rangeValue actualCharacterRange:NULL] inTextContainer:container];
        if (!label.isFlipped) rect.origin.y = NSHeight(label.bounds) - NSMaxY(rect);
        [self revealFindRect:rect inView:view generation:generation];
      }
    } else {
      __weak typeof(self) weakSelf = self;
      [TLMarkdownRenderer selectFindMatch:local inView:view reveal:reveal && local >= 0 completion:^(NSRect rect) {
        if (reveal && local >= 0) [weakSelf revealFindRect:rect inView:view generation:generation];
      }];
    }
  }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [_slashCommandUpdateTimer invalidate]; }
@end
