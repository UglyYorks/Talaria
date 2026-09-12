#import "TLQuestionRequest.h"
#import "TLChatTabController.h"
#import "MarkdownRenderer.h"
#import "design_system/TLNotificationMessageCardView.h"
#import "TLEmptyStateTips.h"
#import "design_system/TLToolActivityView.h"
#import "design_system/TLAttachmentChipView.h"
#import "design_system/TLApprovalCardView.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLThinkingBubbleView.h"
#import "design_system/TLToolStatusPill.h"
#import <math.h>
static NSString *const TLAWSOutageChatTitle = @"AWS Oregon Outage";
static NSString *const TLAWSOutageAgentMessage = @"⚠️ AWS is reporting an outage in the Oregon region. Talaria traffic routed through US West is seeing elevated errors and intermittent request failures. Failover capacity is available in US Central.";
static NSString *const TLAWSOutageIntent = @"Route Talaria traffic to the US-central region";

@interface TLChatTabController ()
@property (nonatomic, strong) TLToolStatusPill *toolStatusPill;
@property (nonatomic, strong) NSView *thinkingRow;
@property (nonatomic, strong) TLThinkingBubbleView *thinkingBubble;
@property (nonatomic, strong, readwrite) TLFindBar *findBar;
@property (nonatomic, strong) NSMapTable<NSView *, NSLayoutConstraint *> *rowWidths;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSNumber *> *messageIndices;
@property (nonatomic, strong) NSMapTable<TLChatMessage *, NSNumber *> *messageRowIndices;
@property (nonatomic, strong) NSHashTable<TLChatMessage *> *dirtyMessages;
@property (nonatomic, strong) NSLayoutConstraint *findBarHeight;
@property (nonatomic, copy) NSArray<NSView *> *findViews;
@property (nonatomic, copy) NSArray<NSNumber *> *findCounts;
@property (nonatomic, strong) NSMapTable<NSView *, NSAttributedString *> *findOriginalText;
@property (nonatomic) NSUInteger findGeneration;
@property (nonatomic) NSInteger findMatchIndex;
@property (nonatomic) BOOL findRefreshScheduled;
@property (nonatomic) BOOL revealFindMatch;
@end

@implementation TLChatTabController
- (instancetype)init { return [self initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceSystem]]; }
- (instancetype)initWithPalette:(TLThemePalette *)palette {
  if ((self = [super initWithPalette:palette])) {
    _rowWidths = [NSMapTable weakToStrongObjectsMapTable];
    _messageIndices = [NSMapTable strongToStrongObjectsMapTable];
    _messageRowIndices = [NSMapTable strongToStrongObjectsMapTable];
    _dirtyMessages = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
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
    TLChatTabController *presentation = weakSelf;
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
    TLChatTabController *presentation = weakSelf;
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
- (void)pinMessageRowToStackWidth:(NSView *)row {
  if ([self.rowWidths objectForKey:row]) return;
  NSLayoutConstraint *constraint = [row.widthAnchor constraintEqualToAnchor:self.messageStack.widthAnchor];
  constraint.identifier = @"TLMessageRowWidthConstraint";
  constraint.active = YES;
  [self.rowWidths setObject:constraint forKey:row];
}

- (void)addMessageRowToStack:(NSView *)row {
  [self.messageStack addView:row inGravity:NSStackViewGravityTop];
}

- (void)placeMessageRow:(NSView *)row atIndex:(NSUInteger)index {
  NSArray<NSView *> *rows = self.messageStack.arrangedSubviews;
  if (index < rows.count && rows[index] == row) return;
  [self removeArrangedMessageRowIfNeeded:row];
  [self.messageStack insertView:row atIndex:index inGravity:NSStackViewGravityTop];
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
  TLChatMessage *message = self.messages[index];
  if ([message.role isEqual:TLRoleAssistant] && !message.content.length && !message.attachments.count &&
      !message.notification && !message.approvalRequest && !message.questions.count) return self.palette.space0;
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
  [[self.rowWidths objectForKey:row] setActive:NO];
  [self.rowWidths removeObjectForKey:row];
  [self removeArrangedMessageRowIfNeeded:row];
  if (row.superview) {
    [row removeFromSuperview];
  }
}

- (void)renderMessages {
  [self renderMessagesScrollingToBottom:YES];
}

- (void)markMessageDirty:(TLChatMessage *)message { if (message) [self.dirtyMessages addObject:message]; }

- (void)renderDirtyMessages {
  [self updateLiveActivity];
  if (!self.dirtyMessages.count || self.renderedMessages.count != self.messages.count) { [self renderMessagesScrollingToBottom:YES]; return; }
  for (TLChatMessage *message in self.dirtyMessages) {
    NSNumber *index = [self.messageIndices objectForKey:message];
    if (!index || index.unsignedIntegerValue >= self.messages.count || self.messages[index.unsignedIntegerValue] != message ||
        [self messageShowsAWSOutageIntent:message] || ![self.messageRowViews objectForKey:message]) {
      [self renderMessagesScrollingToBottom:YES]; return;
    }
  }
  self.streamingRenderScheduled = NO;
  self.streamingRenderGeneration++;
  for (TLChatMessage *message in self.dirtyMessages) {
    NSUInteger index = [[self.messageIndices objectForKey:message] unsignedIntegerValue];
    NSView *previous = [self.messageRowViews objectForKey:message];
    NSView *row = [self cachedRowForMessage:message showsOutgoingTail:[self showsOutgoingTailForMessageAtIndex:index]];
    if (row != previous) {
      [self placeMessageRow:row atIndex:[[self.messageRowIndices objectForKey:message] unsignedIntegerValue]];
      [self pinMessageRowToStackWidth:row];
      [self.messageStack setCustomSpacing:[self messageStackSpacingAfterMessageAtIndex:index] afterView:row];
    }
  }
  [self.dirtyMessages removeAllObjects];
  [self refreshFindResults];
  [self.messageDocumentView layoutSubtreeIfNeeded];
  if (self.notificationRevealHandler && self.notificationRevealHandler()) return;
  if (!self.findBarVisible && !self.suppressAutomaticScroll) [self.messageDocumentView scrollRectToVisible:NSMakeRect(0, MAX(0, NSHeight(self.messageDocumentView.bounds) - 1), 1, 1)];
}

- (void)scheduleStreamingMessageRender {
  if (self.streamingRenderScheduled || self.closed) return;
  self.streamingRenderScheduled = YES;
  NSUInteger generation = ++self.streamingRenderGeneration;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    TLChatTabController *owner = weakSelf;
    if (!owner || owner.closed || generation != owner.streamingRenderGeneration) return;
    [owner renderDirtyMessages];
  });
}

- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom {
  if (!self.messageStack || self.closed) { self.streamingRenderScheduled = NO; return; }
  [self updateLiveActivity];
  [self.dirtyMessages removeAllObjects];
  [self.messageIndices removeAllObjects];
  [self.messageRowIndices removeAllObjects];
  if (self.findBarVisible) scrollToBottom = NO;
  // Completion, navigation and theme changes render immediately and supersede a pending batch.
  self.streamingRenderScheduled = NO;
  self.streamingRenderGeneration += 1;
  NSPoint previousScrollOrigin = self.messageScrollView.contentView.bounds.origin;
  // Persistence replaces transient messages with stored records. Keep their
  // already-loaded views when the displayed message at that position is unchanged.
  NSHashTable *currentMessages = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
  NSMutableDictionary<NSNumber *, TLChatMessage *> *storedMessages = [NSMutableDictionary dictionary];
  for (TLChatMessage *message in self.messages) {
    [currentMessages addObject:message];
    if ([message isKindOfClass:TLStoredChatMessage.class] && [(TLStoredChatMessage *)message messageID]) storedMessages[@([(TLStoredChatMessage *)message messageID])] = message;
  }
  [self.renderedMessages enumerateObjectsUsingBlock:^(TLChatMessage *previous, NSUInteger index, BOOL *stop) {
    if (index >= self.messages.count || [currentMessages containsObject:previous]) return;
    TLChatMessage *current = [previous isKindOfClass:TLStoredChatMessage.class] ? storedMessages[@([(TLStoredChatMessage *)previous messageID])] : nil;
    if (!current) current = self.messages[index];
    NSView *row = [self.messageRowViews objectForKey:previous];
    if (!row || [self.messageRowViews objectForKey:current] ||
        ![previous.role isEqualToString:current.role] || ![previous.content isEqualToString:current.content] ||
        ![(previous.thinking ?: @"") isEqualToString:current.thinking ?: @""] ||
        ![previous.attachments isEqual:current.attachments] ||
        ![(previous.notification ?: @{}) isEqual:current.notification ?: @{}] ||
        ![previous.toolActivities isEqual:current.toolActivities] ||
        ![previous.questions isEqual:current.questions] ||
        ![(previous.approvalRequest ?: @{}) isEqual:current.approvalRequest ?: @{}]) return;
    [self.messageRowViews setObject:row forKey:current];
    [self.messageRowSignatures setObject:[self.messageRowSignatures objectForKey:previous] forKey:current];
    NSView *markdown = [self.messageMarkdownViews objectForKey:previous];
    if (markdown) [self.messageMarkdownViews setObject:markdown forKey:current];
    NSView *activity = [self.messageActivityViews objectForKey:previous];
    if (activity) [self.messageActivityViews setObject:activity forKey:current];
    [self.messageRowViews removeObjectForKey:previous];
    [self.messageRowSignatures removeObjectForKey:previous];
    [self.messageMarkdownViews removeObjectForKey:previous];
    [self.messageActivityViews removeObjectForKey:previous];
  }];
  self.renderedMessages = self.messages.copy;
  for (TLChatMessage *cachedMessage in self.messageRowViews.keyEnumerator.allObjects) {
    if (![currentMessages containsObject:cachedMessage]) {
      NSView *staleRow = [self.messageRowViews objectForKey:cachedMessage];
      [self detachMessageRowFromStack:staleRow];
      [self.messageRowViews removeObjectForKey:cachedMessage];
      [self.messageRowSignatures removeObjectForKey:cachedMessage];
      [self.messageMarkdownViews removeObjectForKey:cachedMessage];
      [self.messageActivityViews removeObjectForKey:cachedMessage];
    }
  }
  NSArray<NSView *> *previousRows = self.messageStack.arrangedSubviews.copy;

  TLStarryEmptyStateView *emptyStateView = self.emptyStateView;
  emptyStateView.palette = self.palette;
  emptyStateView.availableMessageWidth = self.messageInputWidthConstraint.constant;
  emptyStateView.hidden = self.isLoading || self.errorMessage.length > 0 || self.messages.count > 0;
  if (!emptyStateView.hidden) {
    emptyStateView.avatar = self.agentAvatar ?: @"🤖";
  }

  if (self.isLoading || self.errorMessage.length > 0 || self.messages.count == 0) {
    [self resetMessageRowCache];
    for (NSView *view in previousRows) {
      [self detachMessageRowFromStack:view];
    }
    if (self.isLoading || self.errorMessage.length > 0) {
      NSView *emptyState = [self loadingStateView];
      [self addMessageRowToStack:emptyState];
      [self pinMessageRowToStackWidth:emptyState];
    }
    [self refreshFindResults];
    return;
  }

  NSMutableSet<NSView *> *renderedRows = [NSMutableSet setWithCapacity:self.messages.count];
  NSUInteger rowIndex = 0;
  BOOL orderChanged = NO;
  for (NSUInteger index = 0; index < self.messages.count; index++) {
    TLChatMessage *message = self.messages[index];
    [self.messageIndices setObject:@(index) forKey:message];
    [self.messageRowIndices setObject:@(rowIndex) forKey:message];
    BOOL showsOutgoingTail = [self showsOutgoingTailForMessageAtIndex:index];
    NSView *row = [self cachedRowForMessage:message showsOutgoingTail:showsOutgoingTail];
    [renderedRows addObject:row];
    if (!orderChanged && rowIndex < previousRows.count && previousRows[rowIndex] == row) rowIndex++;
    else { orderChanged = YES; [self placeMessageRow:row atIndex:rowIndex++]; }
    [self pinMessageRowToStackWidth:row];
    if ([self messageShowsAWSOutageIntent:message]) {
      [self.messageStack setCustomSpacing:self.palette.space8 afterView:row];
      NSView *intentWidget = [self AWSOutageIntentWidget];
      [renderedRows addObject:intentWidget];
      [self placeMessageRow:intentWidget atIndex:rowIndex++];
      [self pinMessageRowToStackWidth:intentWidget];
      [self.messageStack setCustomSpacing:[self messageStackSpacingAfterMessageAtIndex:index] afterView:intentWidget];
    } else {
      [self.messageStack setCustomSpacing:[self messageStackSpacingAfterMessageAtIndex:index] afterView:row];
    }
  }

  for (NSView *view in self.messageStack.subviews.copy) {
    if (![renderedRows containsObject:view]) {
      [self detachMessageRowFromStack:view];
    }
  }

  [self updateLiveActivity];
  [self refreshFindResults];
  dispatch_async(dispatch_get_main_queue(), ^{
      [self updateMessageScrollInsets];
      [self.messageDocumentView layoutSubtreeIfNeeded];
      if (self.notificationRevealHandler && self.notificationRevealHandler()) return;
      if (scrollToBottom && !self.suppressAutomaticScroll) {
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
  return [self.chat.title isEqualToString:TLAWSOutageChatTitle] &&
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
  sendButton.action = @selector(sendIntent:);
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

- (void)updateLiveActivity {
  TLChatMessage *message = self.messages.lastObject;
  BOOL running = self.streamingProvider && self.streamingProvider() && !self.isLoading && !self.errorMessage.length &&
    [message.role isEqualToString:TLRoleAssistant] && !message.approvalRequest;
  for (TLQuestionRequest *question in message.questions) if (question.pending) running = NO;
  NSDictionary *active = nil;
  if (running) {
    for (NSDictionary *activity in message.toolActivities.reverseObjectEnumerator) {
      if ([@[@"preparing", @"running"] containsObject:activity[@"state"]]) { active = activity; break; }
    }
  }
  self.toolStatusPill.hidden = active == nil;
  if (active) [self.toolStatusPill setAvatar:self.agentAvatar activity:active];
  BOOL thinking = running && (active || message.thinkingActive || !message.content.length);
  if (thinking && self.messageStack) {
    if (!self.thinkingRow) {
      self.thinkingRow = [NSView new];
      self.thinkingRow.translatesAutoresizingMaskIntoConstraints = NO;
      self.thinkingBubble = [TLThinkingBubbleView new];
      [self.thinkingRow addSubview:self.thinkingBubble];
      [NSLayoutConstraint activateConstraints:@[
        [self.thinkingBubble.leadingAnchor constraintEqualToAnchor:self.thinkingRow.leadingAnchor],
        [self.thinkingBubble.topAnchor constraintEqualToAnchor:self.thinkingRow.topAnchor],
        [self.thinkingBubble.bottomAnchor constraintEqualToAnchor:self.thinkingRow.bottomAnchor],
        [self.thinkingBubble.trailingAnchor constraintLessThanOrEqualToAnchor:self.thinkingRow.trailingAnchor],
      ]];
    }
    self.thinkingBubble.palette = self.palette;
    if (![self.messageStack.arrangedSubviews containsObject:self.thinkingRow]) [self addMessageRowToStack:self.thinkingRow];
    [self pinMessageRowToStackWidth:self.thinkingRow];
  } else if (self.thinkingRow) [self detachMessageRowFromStack:self.thinkingRow];
  [self updateMessageScrollInsets];
}

- (void)updateMessageScrollInsets {
  CGFloat slashCommandListHeight = (!self.slashCommandListView.hidden && self.slashCommandListHeightConstraint.constant > self.palette.space0)
    ? self.slashCommandListHeightConstraint.constant + self.palette.space5
    : self.palette.space0;
  CGFloat activityHeight = self.toolStatusPill && !self.toolStatusPill.hidden ? self.palette.space9 * 2 + self.palette.space3 * 2 : 0;
  self.promptQueueBottomConstraint.constant = -self.palette.space3 - slashCommandListHeight - activityHeight;
  [self.messageInput.superview layoutSubtreeIfNeeded];
  CGFloat inputHeight = NSHeight(self.messageInput.frame) > 0.0 ? NSHeight(self.messageInput.frame) : self.palette.composerButtonHeight;
  CGFloat queueHeight = self.promptQueueView.preferredHeight;
  CGFloat bottomClearance = inputHeight + activityHeight + (queueHeight > 0 ? queueHeight + self.palette.space3 : 0) + slashCommandListHeight + self.palette.space10 + self.palette.space8 + self.palette.messageBottomSpacing;
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
    TLToolActivityView *activity = (id)[self.messageActivityViews objectForKey:message];
    activity.activities = message.toolActivities;
    NSView *markdown = [self.messageMarkdownViews objectForKey:message];
    if (markdown) {
      TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:self.palette];
      [renderer updateMarkdown:[self displayTextForMessage:message] inView:markdown];
    }
    return row;
  }

  if (row) {
    [self detachMessageRowFromStack:row];
  }

  BOOL activityExpanded = [(TLToolActivityView *)[self.messageActivityViews objectForKey:message] isExpanded];
  [self.messageMarkdownViews removeObjectForKey:message];
  [self.messageActivityViews removeObjectForKey:message];
  row = [self rowForMessage:message showsOutgoingTail:showsOutgoingTail];
  [(TLToolActivityView *)[self.messageActivityViews objectForKey:message] setExpanded:activityExpanded];
  [self.messageRowViews setObject:row forKey:message];
  [self.messageRowSignatures setObject:signature forKey:message];
  return row;
}

- (NSString *)displayTextForMessage:(TLChatMessage *)message {
  NSString *displayText = message.content ?: @"";
  // Older builds persisted the gateway's question array as visible JSON.
  // Repair only that exact envelope for display; keep stored content intact.
  NSString *suffix = @"Reply with your answer.";
  if ([message.role isEqual:TLRoleAssistant] && [displayText hasSuffix:suffix]) {
    NSString *json = [[displayText substringToIndex:displayText.length - suffix.length]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    id questions = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([questions isKindOfClass:NSArray.class] && [questions count]) {
      NSMutableArray *parts = [NSMutableArray array];
      BOOL valid = YES;
      for (id question in questions) {
        if (![question isKindOfClass:NSDictionary.class] || ![question[@"qid"] isKindOfClass:NSString.class] ||
            ![question[@"question"] isKindOfClass:NSString.class]) { valid = NO; break; }
        [parts addObject:question[@"question"]];
        if ([question[@"choices"] isKindOfClass:NSArray.class]) {
          for (id choice in question[@"choices"]) if ([choice isKindOfClass:NSString.class])
            [parts addObject:[@"- " stringByAppendingString:choice]];
        }
      }
      if (valid) displayText = [[parts componentsJoinedByString:@"\n\n"] stringByAppendingFormat:@"\n\n%@", suffix];
    }
  }
  if ([self messageShowsAWSOutageIntent:message]) {
    displayText = TLAWSOutageAgentMessage;
  }
  return displayText;
}

- (NSString *)rowSignatureForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)showsOutgoingTail {
  BOOL user = [message.role isEqualToString:TLRoleUser];
  NSString *mode = message.approvalRequest ? [@"approval:" stringByAppendingString:message.approvalRequest.description] : @"content";
  for (TLQuestionRequest *question in message.questions) mode = [mode stringByAppendingFormat:@" question:%@", question.presentation];
  if (message.notification) mode = [mode stringByAppendingFormat:@" notification:%@", message.notification];
  CGFloat layoutWidth = self.messageInputWidthConstraint.constant > 0.0
    ? self.messageInputWidthConstraint.constant
    : self.palette.messageInputMaxWidth;

  return [NSString stringWithFormat:@"%@\n--TLROW--\n%@\n--TLROW--\n%.0f\n--TLROW--\n%@\n--TLROW--\n%@",
                                    message.role ?: @"",
                                    [mode stringByAppendingFormat:@"\n%@\nactivity:%d\ncontent:%d", message.attachments ?: @[], message.toolActivities.count > 0, message.content.length > 0],
                                    layoutWidth,
                                    showsOutgoingTail ? @"tail" : @"body",
                                    user ? [self displayTextForMessage:message] : ([self messageShowsAWSOutageIntent:message] ? @"intent" : @"answer")];
}

- (void)resetMessageRowCache {
  [self.dirtyMessages removeAllObjects];
  [self.messageIndices removeAllObjects];
  [self.messageRowIndices removeAllObjects];
  self.streamingRenderScheduled = NO;
  self.streamingRenderGeneration += 1;
  for (NSView *view in self.messageRowViews.objectEnumerator) {
    [self detachMessageRowFromStack:view];
  }
  self.messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
  self.messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
  self.messageMarkdownViews = [NSMapTable strongToStrongObjectsMapTable];
  self.messageActivityViews = [NSMapTable strongToStrongObjectsMapTable];
  self.renderedMessages = @[];
}

- (NSView *)loadingStateView {
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
  bubble.cornerRadius = user ? self.palette.userMessageCornerRadius : self.palette.space0;
  bubble.wantsLayer = YES;
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
  TLAttachmentChipRow *attachmentRow = nil;
  CGFloat availableMessageWidth = self.messageInputWidthConstraint.constant > 0.0
    ? self.messageInputWidthConstraint.constant
    : self.palette.messageInputMaxWidth;

  BOOL hasResponseContent = message.content.length > 0;
  if (user) {
    NSString *content = hasResponseContent ? message.content : @"";
    userLeadingInset = self.palette.userMessageHorizontalPadding;
    userTrailingInset = self.palette.userMessageHorizontalPadding;
    userTopInset = self.palette.userMessageVerticalPadding;
    userBottomInset = self.palette.userMessageVerticalPadding +
      (drawsOutgoingTail ? self.palette.userMessageTailHeight : self.palette.space0);
    userTextMaxWidth = MAX(1.0, availableMessageWidth * widthMultiplier - userLeadingInset - userTrailingInset);
    contentLabel = [self wrappingLabelWithString:content
                                            font:self.palette.messageBodyFont
                                           color:textColor];
    contentLabel.selectable = YES;
    contentLabel.preferredMaxLayoutWidth = userTextMaxWidth;
    // Grow the padding symmetrically for tiny messages, keeping the label at
    // its natural width so punctuation stays centred in the rounded body.
    CGFloat minimumBubbleWidth = MIN(self.palette.userMessageMinWidth, availableMessageWidth * widthMultiplier);
    CGFloat minimumInset = (minimumBubbleWidth - contentLabel.intrinsicContentSize.width) * 0.5;
    userLeadingInset = MAX(userLeadingInset, minimumInset);
    userTrailingInset = MAX(userTrailingInset, minimumInset);
    userTextMaxWidth = MAX(1.0, availableMessageWidth * widthMultiplier - userLeadingInset - userTrailingInset);
    contentLabel.preferredMaxLayoutWidth = userTextMaxWidth;
    [contentLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [contentLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (hasResponseContent) {
      [stack addArrangedSubview:contentLabel];
      [self.messageMarkdownViews setObject:contentLabel forKey:message];
    } else contentLabel = nil;
  } else if (hasResponseContent) {
    NSString *content = [self displayTextForMessage:message];
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
    NSView *markdown = [self markdownViewWithString:content textColor:textColor baseFont:self.palette.messageBodyFont];
    [stack addArrangedSubview:markdown];
    [self.messageMarkdownViews setObject:markdown forKey:message];
  }

  if (message.attachments.count) {
    // Capture the originating presentation: split-pane focus may change before a click.
    __weak typeof(self) weakSelf = self;
    NSMutableArray<TLAttachmentChipView *> *chips = [NSMutableArray array];
    [message.attachments enumerateObjectsUsingBlock:^(NSDictionary *attachment, NSUInteger index, BOOL *stop) {
      TLAttachmentPreviewItem *item = self.previewItemProvider ? self.previewItemProvider(attachment) : [TLAttachmentPreviewItem new];
      TLAttachmentChipView *chip = [[TLAttachmentChipView alloc] init];
      chip.palette = self.palette; chip.showsRemoveButton = NO;
      chip.title = item.name; chip.toolTip = [NSString stringWithFormat:@"%@\n%@", item.name, item.detail];
      chip.image = [NSImage imageWithSystemSymbolName:item.directory ? @"folder" : @"doc" accessibilityDescription:nil];
      chip.activationHandler = ^{ if (weakSelf.attachmentPreviewHandler) weakSelf.attachmentPreviewHandler(message, index); };
      if (item.previewItemURL) [chip loadPreviewForURL:item.previewItemURL];
      [chips addObject:chip];
    }];
    attachmentRow = [[TLAttachmentChipRow alloc] initWithChips:chips palette:self.palette];
    attachmentRow.alignsTrailing = user;
    [row addSubview:attachmentRow];
  }

  if (!user && message.notification) {
    TLNotificationMessageCardView *card = [[TLNotificationMessageCardView alloc] initWithNotification:message.notification palette:self.palette];
    [stack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  }
  if (!user && message.approvalRequest) {
    TLApprovalCardView *card = [[TLApprovalCardView alloc] initWithRequest:message.approvalRequest palette:self.palette];
    NSString *requestID = message.approvalRequest[@"request_id"];
    __weak typeof(self) weakSelf = self;
    card.choiceHandler = ^BOOL(NSString *choice) { return weakSelf.approvalHandler ? weakSelf.approvalHandler(requestID, choice) : NO; };
    [stack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  }
  if (!user) for (TLQuestionRequest *question in message.questions) {
    TLQuestionCardView *card = [[TLQuestionCardView alloc] initWithRequest:question.presentation palette:self.palette];
    card.choiceHandler = ^BOOL(NSString *choice) { return [question respondWithOption:choice]; };
    [stack addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  }
  if (!stack.arrangedSubviews.count && !attachmentRow) {
    [row.heightAnchor constraintEqualToConstant:0].active = YES;
    return row;
  }
  BOOL hasBubble = stack.arrangedSubviews.count > 0;
  NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
  if (attachmentRow) {
    [constraints addObjectsFromArray:@[
      [attachmentRow.topAnchor constraintEqualToAnchor:hasBubble ? bubble.bottomAnchor : row.topAnchor constant:hasBubble ? self.palette.space5 : self.palette.space0],
      [attachmentRow.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
      [attachmentRow.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:widthMultiplier],
    ]];
    // Reserve the available row width; thumbnails can change chip widths after loading.
    NSLayoutConstraint *preferredWidth = [attachmentRow.widthAnchor constraintEqualToConstant:availableMessageWidth * widthMultiplier];
    preferredWidth.priority = NSLayoutPriorityDefaultHigh;
    [constraints addObject:preferredWidth];
    if (user) {
      [constraints addObject:[attachmentRow.trailingAnchor constraintEqualToAnchor:row.trailingAnchor]];
      [constraints addObject:[attachmentRow.leadingAnchor constraintGreaterThanOrEqualToAnchor:row.leadingAnchor]];
    } else {
      [constraints addObject:[attachmentRow.leadingAnchor constraintEqualToAnchor:row.leadingAnchor]];
      [constraints addObject:[attachmentRow.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
    }
  }
  if (!hasBubble) { [NSLayoutConstraint activateConstraints:constraints]; return row; }
  [row addSubview:bubble];
  NSLayoutConstraint *assistantWidth = [bubble.widthAnchor constraintEqualToAnchor:row.widthAnchor multiplier:widthMultiplier];
  assistantWidth.priority = NSLayoutPriorityDefaultHigh + 1.0;

  [constraints addObjectsFromArray:@[
    [bubble.topAnchor constraintEqualToAnchor:row.topAnchor],
    [bubble.widthAnchor constraintLessThanOrEqualToAnchor:row.widthAnchor multiplier:widthMultiplier],
    [stack.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:user ? userLeadingInset : self.palette.space0],
    [stack.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:user ? -userTrailingInset : self.palette.space0],
    [stack.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:user ? userTopInset : self.palette.space0],
    [stack.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:user ? -userBottomInset : self.palette.space0],
  ]];
  if (!attachmentRow) [constraints addObject:[bubble.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]];
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

- (void)setChatWorkspace:(NSView *)chatWorkspace { _chatWorkspace = chatWorkspace; if (chatWorkspace) self.view = chatWorkspace; }
- (void)sendIntent:(id)sender { if (self.intentHandler) self.intentHandler(); }
- (void)close {
  self.streamingRenderGeneration++;
  self.streamingRenderScheduled = NO;
  [self.slashCommandUpdateTimer invalidate];
  self.slashCommandUpdateTimer = nil;
  if (self.queuedPrompts.count || self.queuedPromptInFlight) {
    self.queuePaused = YES; self.queueInterruptPending = NO; self.chatWorkspace.hidden = YES;
    return;
  }
  [self.chatWorkspace removeFromSuperview];
  [super close];
}
- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.messagesBackground.fillColor = palette.tabBackground;
  self.messageStack.spacing = palette.messageVerticalSpacing;
  self.messageInput.palette = palette;
  self.toolStatusPill.palette = palette;
  self.thinkingBubble.palette = palette;

  self.slashCommandScrollView.palette = palette;
  self.slashCommandListView.palette = palette;
  [self applyFindPalette:palette];
  [self.screensaverView updateBackgroundColor:palette.messagesSurface artColor:palette.textMuted];
  [self resetMessageRowCache];
}
- (NSView *)markdownViewWithString:(NSString *)string textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont {
  TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:self.palette];
  renderer.linkHandler = self.linkHandler;
  renderer.linkContextMenuHandler = self.linkContextMenuHandler;
  __weak typeof(self) weakSelf = self;
  __block __weak NSView *weakView = nil;
  renderer.heightChangeHandler = ^{
    TLChatTabController *owner = weakSelf;
    if (!owner || owner.findBarVisible || ![weakView isDescendantOf:owner.messageStack]) return;
    [owner.messageDocumentView layoutSubtreeIfNeeded];
    if (owner.notificationRevealHandler && owner.notificationRevealHandler()) return;
    if (owner.suppressAutomaticScroll || !owner.streamingProvider || !owner.streamingProvider()) return;
    NSRect bottom = NSMakeRect(0, MAX(0, NSHeight(owner.messageDocumentView.bounds) - 1), 1, 1);
    [owner.messageDocumentView scrollRectToVisible:bottom];
  };
  NSView *view = [renderer viewForMarkdown:string ?: @"" textColor:textColor baseFont:baseFont];
  weakView = view;
  return view;
}
- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:string];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font; label.textColor = color;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}
- (NSTextField *)wrappingLabelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [self labelWithString:string font:font color:color];
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.maximumNumberOfLines = 0; label.usesSingleLineMode = NO;
  return label;
}
- (void)allowHorizontalWindowExpansionForView:(NSView *)view {
  [view setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
}
- (void)applyComposerPalette {
  self.slashCommandListView.palette = self.palette;
  self.slashCommandScrollView.palette = self.palette;
  self.slashCommandListBottomConstraint.constant = -self.palette.space5;
}
- (NSView *)buildChatWorkspace {
  NSView *chatWorkspace = [[NSView alloc] init];
  chatWorkspace.translatesAutoresizingMaskIntoConstraints = NO;
  [self allowHorizontalWindowExpansionForView:chatWorkspace];

  NSView *messagesView = [self buildMessagesView];
  [chatWorkspace addSubview:messagesView];
  [self installFindBarInView:chatWorkspace palette:self.palette];
  [chatWorkspace addSubview:[self buildSlashCommandListView]];
  [chatWorkspace addSubview:[self buildMessageInput]];
  TLStarryEmptyStateView *emptyState = [[TLStarryEmptyStateView alloc] init];
  emptyState.translatesAutoresizingMaskIntoConstraints = NO;
  emptyState.hidden = YES;
  NSArray<NSString *> *tips = TLEmptyStateTips();
  emptyState.tip = tips[arc4random_uniform((uint32_t)tips.count)];
  self.emptyStateView = emptyState;
  [chatWorkspace addSubview:emptyState positioned:NSWindowAbove relativeTo:messagesView];
  [NSLayoutConstraint activateConstraints:@[
    [emptyState.leadingAnchor constraintEqualToAnchor:messagesView.leadingAnchor],
    [emptyState.trailingAnchor constraintEqualToAnchor:messagesView.trailingAnchor],
    [emptyState.topAnchor constraintEqualToAnchor:messagesView.topAnchor],
    [emptyState.bottomAnchor constraintEqualToAnchor:self.messageInput.topAnchor constant:-self.palette.space12],
  ]];
  self.toolStatusPill = [TLToolStatusPill new];
  self.toolStatusPill.palette = self.palette;
  [chatWorkspace addSubview:self.toolStatusPill];
  [NSLayoutConstraint activateConstraints:@[
    [self.toolStatusPill.centerXAnchor constraintEqualToAnchor:self.messageInput.centerXAnchor],
    [self.toolStatusPill.bottomAnchor constraintEqualToAnchor:self.slashCommandListView.topAnchor constant:-self.palette.space3],
    [self.toolStatusPill.widthAnchor constraintLessThanOrEqualToAnchor:self.messageInput.widthAnchor],
  ]];
  TLChatTabController *presentation = self;
  presentation.promptQueueView = [TLPromptQueueView new];
  [chatWorkspace addSubview:presentation.promptQueueView];
  presentation.promptQueueView.sendNowHandler = self.queueSendNowHandler;
  presentation.promptQueueView.editHandler = self.queueEditHandler;
  presentation.promptQueueView.removeHandler = self.queueRemoveHandler;
  presentation.promptQueueView.resumeHandler = self.queueResumeHandler;
  presentation.promptQueueView.cancelEditHandler = self.queueCancelEditHandler;
  presentation.promptQueueBottomConstraint = [presentation.promptQueueView.bottomAnchor
    constraintEqualToAnchor:self.messageInput.topAnchor constant:-self.palette.space3];
  [NSLayoutConstraint activateConstraints:@[
    [presentation.promptQueueView.leadingAnchor constraintEqualToAnchor:self.messageInput.leadingAnchor],
    [presentation.promptQueueView.trailingAnchor constraintEqualToAnchor:self.messageInput.trailingAnchor],
    presentation.promptQueueBottomConstraint,
  ]];

  NSLayoutConstraint *messageInputLeadingConstraint = [self.messageInput.leadingAnchor constraintGreaterThanOrEqualToAnchor:chatWorkspace.leadingAnchor
                                                                                                                   constant:self.palette.space11];
  NSLayoutConstraint *messageInputTrailingConstraint = [self.messageInput.trailingAnchor constraintLessThanOrEqualToAnchor:chatWorkspace.trailingAnchor
                                                                                                                    constant:-self.palette.space11];
  // At the 200px window minimum, allow the composer to clip within its pane
  // rather than letting two preferred margins increase the window minimum.
  messageInputLeadingConstraint.priority = NSLayoutPriorityFittingSizeCompression;
  messageInputTrailingConstraint.priority = NSLayoutPriorityFittingSizeCompression;
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
    [messagesView.topAnchor constraintEqualToAnchor:self.findBar.bottomAnchor],
    [messagesView.bottomAnchor constraintEqualToAnchor:chatWorkspace.bottomAnchor],
    [self.messageInput.centerXAnchor constraintEqualToAnchor:chatWorkspace.centerXAnchor],
    [self.slashCommandListView.leadingAnchor constraintEqualToAnchor:self.messageInput.leadingAnchor constant:self.palette.space4],
    self.slashCommandListWidthConstraint,
    self.slashCommandListBottomConstraint,
    self.slashCommandListHeightConstraint,
    [self.messageStack.widthAnchor constraintEqualToAnchor:self.messageInput.widthAnchor],
    [self.messageInput.widthAnchor constraintGreaterThanOrEqualToConstant:0],
    [self.messageInput.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth],
    messageInputLeadingConstraint,
    messageInputTrailingConstraint,
    self.messageInputWidthConstraint,
    [self.messageInput.bottomAnchor constraintEqualToAnchor:chatWorkspace.bottomAnchor constant:-self.palette.space10],
  ]];

  self.chatWorkspace = chatWorkspace;
  return chatWorkspace;
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
- (NSView *)buildMessageInput {
  self.messageInput = [[TLGlassMessageInput alloc] init];
  ((TLGlassMessageInput *)self.messageInput).usesChatBackdrop = YES;
  self.messageInput.palette = self.palette;
  self.messageInput.attachmentsEnabled = YES;
  self.messageInput.showsSettingsButton = YES;
  self.messageInput.settingsButton.target = self.composerTarget;
  self.messageInput.settingsButton.action = self.settingsAction;
  self.messageInput.attachmentsChangeHandler = self.attachmentsChangedHandler;
  self.promptTextView = self.messageInput.textView;
  self.promptTextView.delegate = self.composerDelegate;
  self.sendButton = self.messageInput.sendButton;
  self.sendButton.target = self.composerTarget;
  self.sendButton.action = self.sendAction;
  return self.messageInput;
}
- (NSView *)buildSlashCommandListView {
  self.slashCommandListView = [[TLInputSuggestionPanelView alloc] init];
  self.slashCommandListView.translatesAutoresizingMaskIntoConstraints = NO;
  self.slashCommandListView.hidden = YES;
  self.slashCommandListView.wantsLayer = YES;
  self.slashCommandListView.layer.zPosition = 20.0;
  self.slashCommandListWidthConstraint = [self.slashCommandListView.widthAnchor constraintEqualToConstant:self.palette.space0];
  self.slashCommandListHeightConstraint = [self.slashCommandListView.heightAnchor constraintEqualToConstant:self.palette.space0];

  self.slashCommandScrollView = [[TLInputSuggestionListView alloc] init];
  __weak typeof(self) weakSelf = self;
  self.slashCommandScrollView.selectionHandler = ^(NSInteger index) { weakSelf.selectedSlashCommandIndex = index; };
  self.slashCommandScrollView.activationHandler = self.suggestionActivationHandler;
  [self.slashCommandListView addSubview:self.slashCommandScrollView];
  [NSLayoutConstraint activateConstraints:@[
    [self.slashCommandScrollView.leadingAnchor constraintEqualToAnchor:self.slashCommandListView.leadingAnchor constant:self.palette.space3],
    [self.slashCommandScrollView.trailingAnchor constraintEqualToAnchor:self.slashCommandListView.trailingAnchor constant:-self.palette.space3],
    [self.slashCommandScrollView.topAnchor constraintEqualToAnchor:self.slashCommandListView.topAnchor constant:self.palette.space2],
    [self.slashCommandScrollView.bottomAnchor constraintEqualToAnchor:self.slashCommandListView.bottomAnchor constant:-self.palette.space2],
  ]];

  [self applyComposerPalette];
  return self.slashCommandListView;
}
@end
