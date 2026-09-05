#import "TLInputSuggestionListView.h"
#import "UIComponents.h"

@interface TLInputSuggestionTableView : NSTableView
@end
@implementation TLInputSuggestionTableView
- (BOOL)acceptsFirstResponder { return NO; }
@end

@interface TLInputSuggestionListView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSTableView *table;
@end

@implementation TLInputSuggestionListView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _suggestions = @[];
    _selectedIndex = -1;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.drawsBackground = NO;
    self.hasVerticalScroller = YES;
    self.autohidesScrollers = YES;
    _table = [[TLInputSuggestionTableView alloc] initWithFrame:self.bounds];
    _table.headerView = nil;
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

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.table.backgroundColor = palette.slashCommandItemSurface;
  self.table.rowHeight = palette.slashCommandRowHeight;
  self.table.intercellSpacing = NSMakeSize(palette.space0, palette.space2);
  [self.table enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *row, NSInteger index) {
    TLSlashCommandItemView *view = [self.table viewAtColumn:0 row:index makeIfNecessary:NO];
    view.palette = palette;
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
  NSInteger previous = _selectedIndex;
  _selectedIndex = index >= 0 && index < (NSInteger)self.suggestions.count ? index : -1;
  if (previous >= 0 && previous < (NSInteger)self.suggestions.count) {
    TLSlashCommandItemView *old = [self.table viewAtColumn:0 row:previous makeIfNecessary:NO];
    old.selected = NO;
  }
  if (_selectedIndex >= 0) {
    [self.table scrollRowToVisible:_selectedIndex];
    TLSlashCommandItemView *view = [self.table viewAtColumn:0 row:_selectedIndex makeIfNecessary:NO];
    view.selected = YES;
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.suggestions.count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
  TLSlashCommandItemView *view = [tableView makeViewWithIdentifier:@"suggestion" owner:self];
  if (!view) {
    view = [[TLSlashCommandItemView alloc] init];
    view.identifier = @"suggestion";
  }
  NSDictionary *item = self.suggestions[index];
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
