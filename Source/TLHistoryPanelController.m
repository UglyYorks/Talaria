#import "TLHistoryPanelController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLTabIconView.h"

@interface TLHistoryTableView : NSTableView

@property (nonatomic) NSInteger contextMenuRow;

@end

@implementation TLHistoryTableView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _contextMenuRow = -1;
  }
  return self;
}

- (instancetype)init {
  return [self initWithFrame:NSZeroRect];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  NSInteger row = [self rowAtPoint:point];
  if (!self.enabled || row < 0 || row >= self.numberOfRows) {
    self.contextMenuRow = -1;
    return nil;
  }

  self.contextMenuRow = row;
  return [super menuForEvent:event];
}

@end

@interface TLHistoryPanelController () <NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation, NSSearchFieldDelegate>

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLTokenView *panelView;
@property (nonatomic, strong) TLTokenView *headerView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) TLHistoryTableView *tableView;
@property (nonatomic) BOOL selectingProgrammatically;
@property (nonatomic, copy) NSArray *filteredEntries;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) TLThemedButton *refreshButton;
@property (nonatomic, copy) NSArray<TLThemedButton *> *filterButtons;

@end

@implementation TLHistoryPanelController

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super init];
  if (self) {
    _palette = palette;
    _chats = @[];
    _filteredEntries = @[];
    _browsingHistory = @[];
    _browsingStatusMessage = @"";
    _statusMessage = @"";
    _searchPreviews = @{};
    _enabled = YES;
    [self buildView];
    [self applyPalette:palette];
  }
  return self;
}

- (void)setEnabled:(BOOL)enabled {
  _enabled = enabled;
  self.tableView.enabled = enabled;
}

- (void)setLoading:(BOOL)loading {
  _loading = loading;
  self.tableView.enabled = self.enabled;
  self.refreshButton.enabled = !loading;
  [self updateStatus];
}

- (void)setStatusMessage:(NSString *)statusMessage {
  _statusMessage = [statusMessage copy];
  [self updateStatus];
}

- (void)setBrowsingStatusMessage:(NSString *)message {
  _browsingStatusMessage = [message copy];
  [self updateStatus];
}

- (void)updateStatus {
  NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSMutableArray *messages = [NSMutableArray array];
  if (self.filter != TLHistoryFilterBrowsing) {
    if (self.statusMessage.length) [messages addObject:self.statusMessage];
    else if (self.loading) [messages addObject:@"Loading Hermes sessions…"];
  }
  if (self.filter != TLHistoryFilterChats && self.browsingStatusMessage.length) [messages addObject:self.browsingStatusMessage];
  if (!messages.count && !self.filteredEntries.count) {
    NSString *kind = self.filter == TLHistoryFilterChats ? @"chats" :
      (self.filter == TLHistoryFilterBrowsing ? @"browsing history" : @"history");
    [messages addObject:query.length ? [NSString stringWithFormat:@"No matching %@", kind] :
      [NSString stringWithFormat:@"No %@ yet", kind]];
  }
  self.statusLabel.stringValue = [messages componentsJoinedByString:@"\n"];
  self.statusLabel.hidden = self.statusLabel.stringValue.length == 0;
}

- (void)setFilter:(TLHistoryFilter)filter {
  _filter = filter;
  for (TLThemedButton *button in self.filterButtons) {
    button.primary = button.tag == filter;
    [button setAccessibilityValue:@(button.primary)];
  }
  [self reloadData];
}

- (void)changeFilter:(TLThemedButton *)sender { self.filter = sender.tag; }

- (void)reloadData {
  NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSMutableArray *matches = [NSMutableArray array];
  if (self.filter != TLHistoryFilterBrowsing) for (TLChatSummary *chat in self.chats) {
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", chat.title, chat.hermesSessionID,
                      self.searchPreviews[@(chat.chatID)] ?: @""];
    if (!query.length || [text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
      [matches addObject:chat];
    }
  }
  if (self.filter != TLHistoryFilterChats) for (TLBrowserHistoryEntry *entry in self.browsingHistory) {
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", entry.title, entry.URLString, entry.URLString.stringByRemovingPercentEncoding ?: @""];
    if (!query.length || [text rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
      [matches addObject:entry];
    }
  }
  // Both stores use UTC timestamps. Stable sorting preserves each store's tie order.
  [matches sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
    NSString *first = [a isKindOfClass:TLChatSummary.class] ? [a updatedAt] : [a visitedAt];
    NSString *second = [b isKindOfClass:TLChatSummary.class] ? [b updatedAt] : [b visitedAt];
    return [second compare:first];
  }];
  self.selectingProgrammatically = YES;
  self.filteredEntries = matches;
  self.tableView.contextMenuRow = -1;
  [self.tableView deselectAll:nil];
  [self.tableView reloadData];
  self.selectingProgrammatically = NO;
  [self updateStatus];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == self.searchField) [self reloadData];
}

- (void)refreshHistory:(id)sender {
  if ([self.delegate respondsToSelector:@selector(historyPanelControllerDidRequestRefresh:)]) {
    [self.delegate historyPanelControllerDidRequestRefresh:self];
  }
}

- (void)deselectAll {
  self.selectingProgrammatically = YES;
  [self.tableView deselectAll:nil];
  self.selectingProgrammatically = NO;
}

- (void)selectChatWithID:(NSInteger)chatID {
  NSInteger row = NSNotFound;
  for (NSUInteger index = 0; index < self.filteredEntries.count; index += 1) {
    if ([self.filteredEntries[index] isKindOfClass:TLChatSummary.class] && [self.filteredEntries[index] chatID] == chatID) {
      row = (NSInteger)index;
      break;
    }
  }

  self.selectingProgrammatically = YES;
  if (row != NSNotFound) {
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];
  } else {
    [self.tableView deselectAll:nil];
  }
  self.selectingProgrammatically = NO;
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.panelView.fillColor = palette.tabBackground;
  self.panelView.borderColor = palette.sidebarBorder;
  self.panelView.borderEdges = TLBorderEdgeNone;
  self.headerView.fillColor = palette.tabBackground;
  self.headerView.borderColor = palette.sidebarBorder;
  self.headerView.borderEdges = TLBorderEdgeBottom;
  self.titleLabel.textColor = palette.labelText;
  self.titleLabel.font = palette.labelFont;
  self.tableView.rowHeight = palette.historyRowHeight;
  self.tableView.backgroundColor = palette.transparentSurface;
  self.searchField.font = palette.bodyFont;
  self.searchField.textColor = palette.controlText;
  self.searchField.backgroundColor = palette.controlSurface;
  self.statusLabel.textColor = palette.textMuted;
  self.statusLabel.font = palette.roleFont;
  self.refreshButton.palette = palette;
  for (TLThemedButton *button in self.filterButtons) button.palette = palette;
  [self.panelView setNeedsDisplay:YES];
  [self.headerView setNeedsDisplay:YES];
  [self.tableView reloadData];
}

- (void)buildView {
  self.panelView = [[TLTokenView alloc] init];
  self.panelView.translatesAutoresizingMaskIntoConstraints = NO;

  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeWidth;
  stack.spacing = 0.0;
  [self.panelView addSubview:stack];

  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:self.panelView.centerXAnchor],
    [stack.widthAnchor constraintLessThanOrEqualToConstant:self.palette.messageInputMaxWidth],
    [stack.widthAnchor constraintLessThanOrEqualToAnchor:self.panelView.widthAnchor],
    [stack.topAnchor constraintEqualToAnchor:self.panelView.topAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:self.panelView.bottomAnchor],
  ]];

  NSLayoutConstraint *preferredWidth = [stack.widthAnchor constraintEqualToAnchor:self.panelView.widthAnchor];
  preferredWidth.priority = NSLayoutPriorityWindowSizeStayPut - 1.0;
  preferredWidth.active = YES;

  self.headerView = [[TLTokenView alloc] init];
  self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerView.heightAnchor constraintEqualToConstant:self.palette.topbarHeight].active = YES;

  self.titleLabel = [self labelWithString:@"History" font:self.palette.labelFont color:self.palette.labelText];
  [self.headerView addSubview:self.titleLabel];
  self.refreshButton = [TLThemedButton buttonWithTitle:@"Refresh" target:self action:@selector(refreshHistory:)];
  self.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.headerView addSubview:self.refreshButton];
  [NSLayoutConstraint activateConstraints:@[
    [self.refreshButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-self.palette.space6],
    [self.refreshButton.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
  ]];
  [NSLayoutConstraint activateConstraints:@[
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:self.palette.space12],
    [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
    [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.refreshButton.leadingAnchor constant:-self.palette.space3],
  ]];

  self.tableView = [[TLHistoryTableView alloc] init];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.headerView = nil;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"chat"];
  column.resizingMask = NSTableColumnAutoresizingMask;
  [self.tableView addTableColumn:column];

  NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:@"History"];
  NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete Conversation"
                                                      action:@selector(deleteContextMenuChat:)
                                               keyEquivalent:@""];
  deleteItem.target = self;
  [contextMenu addItem:deleteItem];
  self.tableView.menu = contextMenu;

  NSScrollView *scrollView = [[NSScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = self.tableView;
  scrollView.hasVerticalScroller = YES;
  scrollView.drawsBackground = NO;

  NSView *searchContainer = [[NSView alloc] init];
  searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField = [[NSSearchField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.placeholderString = @"Search history";
  self.searchField.delegate = self;
  self.searchField.sendsSearchStringImmediately = YES;
  [self.searchField setAccessibilityLabel:@"Search chats and browsing history"];
  [searchContainer addSubview:self.searchField];
  [NSLayoutConstraint activateConstraints:@[
    [self.searchField.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor constant:self.palette.space6],
    [self.searchField.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor constant:-self.palette.space6],
    [self.searchField.topAnchor constraintEqualToAnchor:searchContainer.topAnchor constant:self.palette.space6],
    [self.searchField.bottomAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:-self.palette.space6],
  ]];
  NSStackView *filters = [[NSStackView alloc] init];
  filters.translatesAutoresizingMaskIntoConstraints = NO;
  filters.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  filters.spacing = self.palette.space3;
  filters.distribution = NSStackViewDistributionFillProportionally;
  NSMutableArray *buttons = [NSMutableArray array];
  for (NSString *title in @[@"All", @"Chats", @"Browsing"]) {
    TLThemedButton *button = [TLThemedButton buttonWithTitle:title target:self action:@selector(changeFilter:)];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = buttons.count;
    button.primary = button.tag == self.filter;
    [button setAccessibilityLabel:[NSString stringWithFormat:@"Show %@ history", title.lowercaseString]];
    [button setAccessibilityValue:@(button.primary)];
    [button setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [buttons addObject:button];
    [filters addArrangedSubview:button];
  }
  self.filterButtons = buttons;
  NSView *filterContainer = [[NSView alloc] init];
  filterContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [filterContainer addSubview:filters];
  [NSLayoutConstraint activateConstraints:@[
    [filters.leadingAnchor constraintEqualToAnchor:filterContainer.leadingAnchor constant:self.palette.space6],
    [filters.trailingAnchor constraintLessThanOrEqualToAnchor:filterContainer.trailingAnchor constant:-self.palette.space6],
    [filters.topAnchor constraintEqualToAnchor:filterContainer.topAnchor],
    [filters.bottomAnchor constraintEqualToAnchor:filterContainer.bottomAnchor constant:-self.palette.space6],
  ]];
  self.statusLabel = [self labelWithString:@"" font:self.palette.roleFont color:self.palette.textMuted];
  self.statusLabel.alignment = NSTextAlignmentCenter;
  self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
  self.statusLabel.maximumNumberOfLines = 0;
  [stack addArrangedSubview:self.headerView];
  [stack addArrangedSubview:searchContainer];
  [stack addArrangedSubview:filterContainer];
  [stack addArrangedSubview:self.statusLabel];
  [stack addArrangedSubview:scrollView];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredEntries.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ChatCell" owner:self];
  TLTabIconView *iconView = nil;
  NSTextField *titleLabel = nil;
  NSTextField *dateLabel = nil;

  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 56.0)];
    cell.identifier = @"ChatCell";
    iconView = [[TLTabIconView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel = [self labelWithString:@"" font:self.palette.labelFont color:self.palette.appText];
    dateLabel = [self labelWithString:@"" font:self.palette.roleFont color:self.palette.textMuted];
    iconView.identifier = @"HistoryIcon";
    titleLabel.tag = 101;
    dateLabel.tag = 102;
    [cell addSubview:iconView];
    [cell addSubview:titleLabel];
    [cell addSubview:dateLabel];
    [NSLayoutConstraint activateConstraints:@[
      [iconView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space6],
      [iconView.topAnchor constraintEqualToAnchor:cell.topAnchor constant:self.palette.space5],
      [iconView.widthAnchor constraintEqualToConstant:self.palette.space10],
      [iconView.heightAnchor constraintEqualToConstant:self.palette.space10],
      [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:self.palette.space5],
      [titleLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space6],
      [titleLabel.topAnchor constraintEqualToAnchor:cell.topAnchor constant:self.palette.space5],
      [dateLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
      [dateLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
      [dateLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:self.palette.space3],
    ]];
  } else {
    iconView = (TLTabIconView *)cell.subviews.firstObject;
    titleLabel = [cell viewWithTag:101];
    dateLabel = [cell viewWithTag:102];
  }

  id entry = self.filteredEntries[row];
  TLChatSummary *chat = [entry isKindOfClass:TLChatSummary.class] ? entry : nil;
  TLBrowserHistoryEntry *visit = chat ? nil : entry;
  iconView.icon = chat ? (chat.icon.length > 0 ? chat.icon : TLDefaultChatIcon()) : @"🌐";
  iconView.image = visit.faviconData.length ? [[NSImage alloc] initWithData:visit.faviconData] : nil;
  iconView.palette = self.palette;
  iconView.contentTintColor = self.palette.appText;
  titleLabel.stringValue = chat ? chat.title : (visit.title.length ? visit.title : visit.URLString);
  titleLabel.textColor = self.palette.appText;
  titleLabel.font = self.palette.labelFont;
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  dateLabel.stringValue = chat ? [NSString stringWithFormat:@"Chat · %@", [self shortDate:chat.updatedAt]] :
    [NSString stringWithFormat:@"%@ · %@", [self shortDate:visit.visitedAt], visit.URLString];
  cell.toolTip = chat ? chat.title : visit.URLString;
  [cell setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@, %@", chat ? @"Chat" : @"Browsing", titleLabel.stringValue, dateLabel.stringValue]];
  dateLabel.textColor = self.palette.textMuted;
  dateLabel.font = self.palette.roleFont;
  return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
  TLHistoryRowView *rowView = [tableView makeViewWithIdentifier:@"HistoryRow" owner:self];

  if (!rowView) {
    rowView = [[TLHistoryRowView alloc] init];
    rowView.identifier = @"HistoryRow";
  }

  rowView.palette = self.palette;
  return rowView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (self.selectingProgrammatically || self.tableView.selectedRow < 0) {
    return;
  }
  NSInteger row = self.tableView.selectedRow;
  if (row >= (NSInteger)self.filteredEntries.count) {
    return;
  }
  id entry = self.filteredEntries[row];
  if ([entry isKindOfClass:TLChatSummary.class]) {
    if (!self.loading && self.enabled) [self.delegate historyPanelController:self didSelectChatID:[entry chatID]];
  } else if (self.enabled && [self.delegate respondsToSelector:@selector(historyPanelController:didSelectBrowserURL:)]) {
    NSURL *URL = [NSURL URLWithString:[entry URLString]];
    if (URL) [self.delegate historyPanelController:self didSelectBrowserURL:URL];
  }
}

- (void)deleteContextMenuChat:(id)sender {
  NSInteger row = self.tableView.contextMenuRow;
  if (![self canDeleteContextMenuRow:row]) {
    return;
  }

  id entry = self.filteredEntries[row];
  if ([entry isKindOfClass:TLChatSummary.class]) [self.delegate historyPanelController:self didRequestDeleteChatID:[entry chatID]];
  else if ([self.delegate respondsToSelector:@selector(historyPanelController:didRequestDeleteBrowserVisitID:)])
    [self.delegate historyPanelController:self didRequestDeleteBrowserVisitID:[entry visitID]];
  self.tableView.contextMenuRow = -1;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
  if (menuItem.action == @selector(deleteContextMenuChat:)) {
    NSInteger row = self.tableView.contextMenuRow;
    BOOL browsing = row >= 0 && row < (NSInteger)self.filteredEntries.count &&
      [self.filteredEntries[row] isKindOfClass:TLBrowserHistoryEntry.class];
    menuItem.title = browsing ? @"Delete Browsing Entry" : @"Delete Conversation";
    return [self canDeleteContextMenuRow:row];
  }

  return YES;
}

- (BOOL)canDeleteContextMenuRow:(NSInteger)row {
  if (!self.enabled || row < 0 || row >= (NSInteger)self.filteredEntries.count) return NO;
  return [self.filteredEntries[row] isKindOfClass:TLBrowserHistoryEntry.class] || !self.loading;
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:string];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font;
  label.textColor = color;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (NSString *)shortDate:(NSString *)value {
  NSDateFormatter *parser = [[NSDateFormatter alloc] init];
  parser.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  parser.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  parser.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  NSDate *date = [parser dateFromString:value];
  if (!date) {
    return @"";
  }

  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateStyle = NSDateFormatterNoStyle;
  formatter.timeStyle = NSDateFormatterShortStyle;
  formatter.dateFormat = @"MMM d, h:mm a";
  return [formatter stringFromDate:date];
}

@end
