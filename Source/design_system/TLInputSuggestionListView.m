#import "TLInputSuggestionListView.h"
#import "UIComponents.h"

@interface TLInputSuggestionTableView : NSTableView
@end
@implementation TLInputSuggestionTableView
- (BOOL)acceptsFirstResponder { return NO; }
@end

@interface TLInputSuggestionListView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTrackingArea *pointerTrackingArea;
@end

@implementation TLInputSuggestionListView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _suggestions = @[];
    _selectedIndex = -1;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.drawsBackground = NO;
    self.hasVerticalScroller = NO;
    self.verticalScrollElasticity = NSScrollElasticityNone;
    self.horizontalScrollElasticity = NSScrollElasticityNone;
    self.autohidesScrollers = YES;
    _table = [[TLInputSuggestionTableView alloc] initWithFrame:self.bounds];
    _table.headerView = nil;
    _table.style = NSTableViewStylePlain;
    _table.autoresizingMask = NSViewWidthSizable;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.usesAutomaticRowHeights = NO;
    _table.dataSource = self;
    _table.delegate = self;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"suggestion"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    self.documentView = _table;
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  }
  return self;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.pointerTrackingArea) [self removeTrackingArea:self.pointerTrackingArea];
  self.pointerTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
    options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
    owner:self userInfo:nil];
  [self addTrackingArea:self.pointerTrackingArea];
}

- (void)mouseMoved:(NSEvent *)event {
  // Only actual pointer movement takes selection from the keyboard. Enter/exit
  // events caused by scrolling or recycled cells must not change selection.
  NSPoint point = [self.table convertPoint:event.locationInWindow fromView:nil];
  NSInteger row = [self.table rowAtPoint:point];
  if (row >= 0 && [self isSuggestionEnabledAtIndex:(NSUInteger)row]) self.selectedIndex = row;
}

- (CGFloat)contentHeight {
  // NSTableView includes intercell spacing in every row, including the last one.
  return ceil(self.suggestions.count * (self.table.rowHeight + self.table.intercellSpacing.height));
}

- (void)setScrollingEnabled:(BOOL)enabled {
  _scrollingEnabled = enabled;
  self.hasVerticalScroller = enabled;
  if (!enabled) [self.contentView scrollToPoint:NSZeroPoint];
}

- (void)scrollWheel:(NSEvent *)event {
  if (self.scrollingEnabled) [super scrollWheel:event];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.table.backgroundColor = palette.slashCommandItemSurface;
  self.table.rowHeight = palette.slashCommandRowHeight;
  self.table.intercellSpacing = NSMakeSize(palette.space0, palette.space2);
  [self.table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) {
    NSView *view = [self.table viewAtColumn:0 row:index makeIfNecessary:NO];
    if ([view isKindOfClass:TLSlashCommandItemView.class]) {
      ((TLSlashCommandItemView *)view).palette = palette;
    } else if ([view isKindOfClass:NSTableCellView.class]) {
      NSTextField *label = ((NSTableCellView *)view).textField;
      label.font = palette.bodyFont;
      label.textColor = palette.textMuted;
    }
  }];
}

- (void)setSuggestions:(NSArray<NSDictionary<NSString *, NSString *> *> *)suggestions {
  if ([_suggestions isEqualToArray:suggestions]) return;
  _suggestions = [suggestions copy];
  _selectedIndex = -1;
  [self.table reloadData];
  [self.contentView scrollToPoint:NSZeroPoint];
}

- (BOOL)isSuggestionEnabledAtIndex:(NSUInteger)index {
  if (index >= self.suggestions.count) return NO;
  NSDictionary *item = self.suggestions[index];
  return ![item[@"kind"] isEqualToString:@"status"] &&
    (![item[@"kind"] isEqualToString:@"web"] || [item[@"URL"] length] > 0);
}

- (void)setSelectedIndex:(NSInteger)index {
  _selectedIndex = index >= 0 && [self isSuggestionEnabledAtIndex:(NSUInteger)index] ? index : -1;
  if (_selectedIndex >= 0) [self.table scrollRowToVisible:_selectedIndex];
  [self.table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger rowIndex) {
    NSView *cell = [self.table viewAtColumn:0 row:rowIndex makeIfNecessary:NO];
    if ([cell isKindOfClass:TLSlashCommandItemView.class]) {
      ((TLSlashCommandItemView *)cell).selected = rowIndex == self.selectedIndex;
    }
  }];
  if (self.selectionHandler) self.selectionHandler(_selectedIndex);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.suggestions.count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
  NSDictionary *item = self.suggestions[index];
  if ([item[@"kind"] isEqualToString:@"status"]) {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"status-text" owner:self];
    if (!cell) {
      cell = [[NSTableCellView alloc] init];
      cell.identifier = @"status-text";
      NSTextField *label = [NSTextField labelWithString:@""];
      label.translatesAutoresizingMaskIntoConstraints = NO;
      label.selectable = NO;
      label.lineBreakMode = NSLineBreakByTruncatingTail;
      label.usesSingleLineMode = YES;
      cell.textField = label;
      [cell addSubview:label];
      [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space8],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      ]];
    }
    cell.textField.stringValue = item[@"command"] ?: @"";
    cell.textField.font = self.palette.bodyFont;
    cell.textField.textColor = self.palette.textMuted;
    cell.toolTip = item[@"title"] ?: cell.textField.stringValue;
    return cell;
  }
  TLSlashCommandItemView *view = [tableView makeViewWithIdentifier:@"suggestion" owner:self];
  if (!view) {
    view = [[TLSlashCommandItemView alloc] init];
    view.identifier = @"suggestion";
    // NSTableView owns the root cell frame; only its children use Auto Layout.
    view.translatesAutoresizingMaskIntoConstraints = YES;
  }
  view.selectionManagedExternally = YES;
  view.palette = self.palette;
  view.command = item[@"command"] ?: @"";
  view.commandDescription = item[@"description"] ?: @"";
  view.systemIconName = item[@"icon"] ?: @"text.bubble";
  view.enabled = [self isSuggestionEnabledAtIndex:index];
  view.selected = index == self.selectedIndex;
  view.toolTip = item[@"title"];
  view.tag = index;
  view.target = self;
  view.action = @selector(activateSuggestion:);
  return view;
}

- (void)activateSuggestion:(TLSlashCommandItemView *)sender {
  NSUInteger index = sender.tag;
  if ([self isSuggestionEnabledAtIndex:index] && self.activationHandler) self.activationHandler(index);
}
@end
