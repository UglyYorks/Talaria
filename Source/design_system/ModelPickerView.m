#import "ModelPickerView.h"

@interface TLModelPickerView () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<TLAgentModel *> *allModels;
@property (nonatomic, copy) NSArray<TLAgentModel *> *filteredModels;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *selectedLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *tableView;

@end

@implementation TLModelPickerView

- (instancetype)initWithTitle:(NSString *)title palette:(TLThemePalette *)palette selectedModelID:(NSString *)selectedModelID {
  self = [super init];
  if (self) {
    _title = [title copy];
    _palette = palette;
    _selectedModelID = [selectedModelID copy] ?: @"";
    _userInteractionEnabled = YES;
    _allModels = @[];
    _filteredModels = @[];
    [self buildInterface];
    [self setModels:@[]];
    [self updatePalette:palette];
  }
  return self;
}

- (void)buildInterface {
  self.translatesAutoresizingMaskIntoConstraints = NO;
  self.borderEdges = TLBorderEdgeAll;

  self.titleLabel = [NSTextField labelWithString:self.title];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.selectedLabel = [NSTextField labelWithString:@""];
  self.selectedLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.selectedLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
  self.statusLabel = [NSTextField labelWithString:@""];
  self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.searchField = [[NSSearchField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.placeholderString = @"Search models";
  self.searchField.target = self;
  self.searchField.action = @selector(searchChanged:);
  self.searchField.delegate = self;

  self.tableView = [[NSTableView alloc] init];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.headerView = nil;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = self.palette.composerButtonHeight;
  self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
  self.tableView.backgroundColor = self.palette.transparentSurface;
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"model"];
  column.resizingMask = NSTableColumnAutoresizingMask;
  [self.tableView addTableColumn:column];

  NSScrollView *scrollView = [[NSScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = self.tableView;
  scrollView.hasVerticalScroller = YES;
  scrollView.drawsBackground = NO;
  scrollView.borderType = NSNoBorder;

  [self addSubview:self.titleLabel];
  [self addSubview:self.selectedLabel];
  [self addSubview:self.searchField];
  [self addSubview:scrollView];
  [self addSubview:self.statusLabel];

  [NSLayoutConstraint activateConstraints:@[
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:self.palette.space6],
    [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-self.palette.space6],
    [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:self.palette.space6],
    [self.selectedLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.selectedLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-self.palette.space6],
    [self.selectedLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:self.palette.space2],
    [self.searchField.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.searchField.trailingAnchor constraintEqualToAnchor:self.selectedLabel.trailingAnchor],
    [self.searchField.topAnchor constraintEqualToAnchor:self.selectedLabel.bottomAnchor constant:self.palette.space5],
    [self.searchField.heightAnchor constraintEqualToConstant:self.palette.fieldHeight],
    [scrollView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:self.selectedLabel.trailingAnchor],
    [scrollView.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:self.palette.space5],
    [scrollView.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor constant:-self.palette.space4],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.selectedLabel.trailingAnchor],
    [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-self.palette.space5],
  ]];
}

- (void)setModels:(NSArray<TLAgentModel *> *)models {
  NSMutableArray<TLAgentModel *> *nextModels = [NSMutableArray arrayWithArray:models ?: @[]];

  self.allModels = nextModels;
  [self applyFilter];
}

- (BOOL)hasSelectableModel {
  for (TLAgentModel *model in self.allModels) {
    if ([model.modelID isEqualToString:self.selectedModelID]) return YES;
  }
  return NO;
}
- (void)focusSearch { [self.window makeFirstResponder:self.searchField]; }
- (void)setUserInteractionEnabled:(BOOL)enabled {
  _userInteractionEnabled = enabled;
  self.searchField.enabled = enabled;
  self.tableView.enabled = enabled;
}

- (void)searchChanged:(id)sender {
  [self applyFilter];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  [self applyFilter];
}

- (void)applyFilter {
  NSString *query = [[self.searchField.stringValue ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
  if (query.length == 0) {
    self.filteredModels = self.allModels;
  } else {
    NSMutableArray<TLAgentModel *> *matches = [NSMutableArray array];
    for (TLAgentModel *model in self.allModels) {
      NSString *haystack = [[NSString stringWithFormat:@"%@\n%@\n%@",
                                                        [model displayTitle],
                                                        model.modelID ?: @"",
                                                        model.modelDescription ?: @""] lowercaseString];
      if ([haystack containsString:query]) {
        [matches addObject:model];
      }
    }
    self.filteredModels = matches;
  }

  [self.tableView reloadData];
  [self updateSelectedLabel];
  [self selectCurrentModelInTable];
  [self updateEmptyStatusIfNeeded];
}

- (void)updateEmptyStatusIfNeeded {
  if (self.allModels.count > 0 && self.filteredModels.count == 0) {
    self.statusLabel.stringValue = @"No matching models";
  } else if ([self.statusLabel.stringValue isEqualToString:@"No matching models"]) {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu models available", (unsigned long)self.allModels.count];
  }
}

- (void)setStatusText:(NSString *)statusText {
  self.statusLabel.stringValue = statusText ?: @"";
  self.statusLabel.toolTip = statusText;
}

- (void)updateSelectedLabel {
  self.selectedLabel.stringValue = self.selectedModelID.length > 0
    ? [NSString stringWithFormat:@"Selected: %@", self.selectedModelID]
    : @"No model selected";
}

- (void)selectCurrentModelInTable {
  NSInteger selectedRow = NSNotFound;
  for (NSUInteger index = 0; index < self.filteredModels.count; index += 1) {
    if ([self.filteredModels[index].modelID isEqualToString:self.selectedModelID]) {
      selectedRow = (NSInteger)index;
      break;
    }
  }

  if (selectedRow == NSNotFound) {
    [self.tableView deselectAll:nil];
  } else {
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:selectedRow];
  }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return self.filteredModels.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ModelCell" owner:self];
  NSTextField *titleLabel = nil;
  NSTextField *detailLabel = nil;

  if (!cell) {
    cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, tableView.rowHeight)];
    cell.identifier = @"ModelCell";
    titleLabel = [NSTextField labelWithString:@""];
    detailLabel = [NSTextField labelWithString:@""];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    detailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    titleLabel.tag = 200;
    detailLabel.tag = 201;
    [cell addSubview:titleLabel];
    [cell addSubview:detailLabel];
    [NSLayoutConstraint activateConstraints:@[
      [titleLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space5],
      [titleLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space5],
      [titleLabel.topAnchor constraintEqualToAnchor:cell.topAnchor constant:self.palette.space4],
      [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
      [detailLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
      [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:self.palette.space2],
    ]];
  } else {
    titleLabel = [cell viewWithTag:200];
    detailLabel = [cell viewWithTag:201];
  }

  TLAgentModel *model = self.filteredModels[row];
  titleLabel.stringValue = [model displayTitle];
  titleLabel.font = self.palette.labelFont;
  titleLabel.textColor = self.palette.appText;
  detailLabel.stringValue = [model detailText];
  detailLabel.font = self.palette.smallFont;
  detailLabel.textColor = self.palette.textMuted;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSInteger selectedRow = self.tableView.selectedRow;
  if (selectedRow < 0 || selectedRow >= (NSInteger)self.filteredModels.count) {
    return;
  }

  self.selectedModelID = self.filteredModels[selectedRow].modelID;
  if (self.selectionChangeHandler) self.selectionChangeHandler(self.selectedModelID);
  [self updateSelectedLabel];
}

- (void)updatePalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.fillColor = palette.controlSurface;
  self.borderColor = palette.controlBorder;
  self.borderWidth = palette.borderWidth;
  self.cornerRadius = palette.radiusMedium;
  self.titleLabel.font = palette.labelFont;
  self.titleLabel.textColor = palette.labelText;
  self.selectedLabel.font = palette.smallFont;
  self.selectedLabel.textColor = palette.textMuted;
  self.statusLabel.font = palette.smallFont;
  self.statusLabel.textColor = palette.textMuted;
  self.searchField.font = palette.bodyFont;
  self.searchField.textColor = palette.controlText;
  self.searchField.backgroundColor = palette.controlSurface;
  self.tableView.backgroundColor = palette.transparentSurface;
  [self.tableView reloadData];
  [self setNeedsDisplay:YES];
}

@end
