#import "TLSkillsPicker.h"
#import "TLThemedButton.h"

@interface TLSkillsPicker () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong, readwrite) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) TLThemedButton *reloadButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleSkills;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *draftChanges;
@end

@implementation TLSkillsPicker

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _skills = @[];
    _visibleSkills = @[];
    _draftChanges = [NSMutableDictionary dictionary];
    _message = @"";
    _enabled = YES;
    [self buildInterface];
    [self applyPalette];
    [self reloadData];
  }
  return self;
}

- (void)buildInterface {
  TLThemePalette *p = self.palette;
  self.searchField = [[NSSearchField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.placeholderString = @"Search skills";
  self.searchField.accessibilityLabel = @"Search agent skills";
  self.searchField.delegate = self;
  [self addSubview:self.searchField];

  self.reloadButton = [TLThemedButton buttonWithTitle:@"Reload" target:self action:@selector(reload:)];
  self.reloadButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:self.reloadButton];

  self.tableView = [[NSTableView alloc] init];
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.headerView = nil;
  self.tableView.style = NSTableViewStyleFullWidth;
  self.tableView.allowsEmptySelection = YES;
  self.tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  self.tableView.accessibilityLabel = @"Agent skills";
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"skill"];
  column.width = p.settingsSheetWidth - p.space16 * 4;
  [self.tableView addTableColumn:column];
  self.scrollView = [[NSScrollView alloc] init];
  self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.autohidesScrollers = YES;
  self.scrollView.borderType = NSBezelBorder;
  self.scrollView.documentView = self.tableView;
  [self addSubview:self.scrollView];

  self.emptyLabel = [NSTextField wrappingLabelWithString:@""];
  self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLabel.alignment = NSTextAlignmentCenter;
  [self addSubview:self.emptyLabel];
  self.statusLabel = [NSTextField labelWithString:@""];
  self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:self.statusLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.searchField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.searchField.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.searchField.heightAnchor constraintEqualToConstant:p.fieldHeight],
    [self.searchField.trailingAnchor constraintEqualToAnchor:self.reloadButton.leadingAnchor constant:-p.space5],
    [self.reloadButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.reloadButton.centerYAnchor constraintEqualToAnchor:self.searchField.centerYAnchor],
    [self.scrollView.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:p.space5],
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.scrollView.heightAnchor constraintEqualToConstant:p.fieldHeight * 7],
    [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:p.space12],
    [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-p.space12],
    [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.scrollView.centerYAnchor],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
    [self.statusLabel.topAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:p.space5],
    [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
  ]];
}

- (NSDictionary<NSString *, NSNumber *> *)changes { return [self.draftChanges copy]; }
- (void)setSkills:(NSArray<NSDictionary *> *)skills {
  _skills = [skills copy] ?: @[];
  [self.draftChanges removeAllObjects];
  [self reloadData];
}
- (void)setLoading:(BOOL)loading { _loading = loading; [self reloadData]; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [self reloadData]; }
- (void)setMessage:(NSString *)message { _message = [message copy] ?: @""; [self reloadData]; }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyPalette]; [self reloadData]; }
- (void)controlTextDidChange:(NSNotification *)notification { [self reloadData]; }
- (void)reload:(id)sender { if (self.reloadButton.enabled && self.reloadHandler) self.reloadHandler(); }

- (void)reloadData {
  NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.visibleSkills = [self.skills filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *skill, NSDictionary *bindings) {
    return !query.length || [skill[@"name"] rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
  }]];
  self.searchField.enabled = self.enabled && !self.loading;
  self.reloadButton.enabled = self.enabled && !self.loading && !self.draftChanges.count;
  NSString *empty = self.loading ? @"Loading skills…" : self.message;
  if (!empty.length) empty = self.skills.count ? @"No matching skills" : @"No skills installed";
  self.emptyLabel.stringValue = empty;
  self.emptyLabel.hidden = self.visibleSkills.count > 0 && !self.loading && !self.message.length;
  self.tableView.hidden = self.loading || self.message.length > 0;
  NSUInteger enabledCount = 0;
  for (NSDictionary *skill in self.skills) {
    enabledCount += [self.draftChanges[skill[@"name"]] ?: skill[@"enabled"] boolValue];
  }
  self.statusLabel.stringValue = self.loading || self.message.length ? @"" :
    [NSString stringWithFormat:@"%lu of %lu enabled%@", (unsigned long)enabledCount, (unsigned long)self.skills.count,
      self.draftChanges.count ? @" · Unsaved changes" : @""];
  [self.tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleSkills.count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  NSDictionary *skill = self.visibleSkills[row];
  NSTableCellView *cell = [tableView makeViewWithIdentifier:@"skill" owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] init];
    cell.identifier = @"skill";
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [cell addSubview:label];
    cell.textField = label;
    TLThemedButton *button = [TLThemedButton buttonWithTitle:@"Enabled" target:self action:@selector(toggleSkill:)];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = 1;
    [cell addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
      [cell.textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space5],
      [cell.textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      [cell.textField.trailingAnchor constraintLessThanOrEqualToAnchor:button.leadingAnchor constant:-self.palette.space8],
      [button.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space5],
      [button.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
      [button.widthAnchor constraintEqualToConstant:self.palette.controlMinWidth + self.palette.space12],
    ]];
  }
  NSString *name = skill[@"name"];
  BOOL enabled = [self.draftChanges[name] ?: skill[@"enabled"] boolValue];
  NSString *reason = skill[@"locked_reason"] ?: @"";
  cell.textField.stringValue = name;
  cell.textField.font = self.palette.bodyFont;
  cell.textField.textColor = self.palette.controlText;
  cell.textField.toolTip = name;
  TLThemedButton *button = [cell viewWithTag:1];
  button.identifier = name;
  button.title = reason.length ? (enabled ? @"Required" : @"Managed off") : (enabled ? @"Enabled" : @"Disabled");
  button.primary = enabled;
  button.palette = self.palette;
  button.enabled = self.enabled && !self.loading && !reason.length;
  button.toolTip = reason.length ? reason : [NSString stringWithFormat:@"%@ %@", enabled ? @"Disable" : @"Enable", name];
  button.accessibilityLabel = [NSString stringWithFormat:@"%@, %@%@", name, enabled ? @"enabled" : @"disabled",
                             reason.length ? [@", " stringByAppendingString:reason] : @""];
  return cell;
}

- (void)toggleSkill:(NSButton *)sender {
  if (!sender.enabled || !self.enabled || self.loading) return;
  NSString *name = sender.identifier;
  for (NSDictionary *skill in self.skills) {
    if (![skill[@"name"] isEqual:name] || [skill[@"locked_reason"] length]) continue;
    BOOL value = ![self.draftChanges[name] ?: skill[@"enabled"] boolValue];
    if (value == [skill[@"enabled"] boolValue]) [self.draftChanges removeObjectForKey:name];
    else self.draftChanges[name] = @(value);
    break;
  }
  [self reloadData];
}

- (void)applyPalette {
  self.searchField.font = self.palette.bodyFont;
  self.searchField.textColor = self.palette.controlText;
  self.searchField.backgroundColor = self.palette.controlSurface;
  self.reloadButton.palette = self.palette;
  self.scrollView.backgroundColor = self.palette.controlSurface;
  self.tableView.backgroundColor = self.palette.controlSurface;
  self.tableView.gridColor = self.palette.controlBorder;
  self.tableView.rowHeight = self.palette.settingsActionHeight + self.palette.space8;
  for (NSTextField *label in @[self.statusLabel, self.emptyLabel]) {
    label.font = self.palette.smallFont;
    label.textColor = self.palette.textMuted;
  }
}
@end
