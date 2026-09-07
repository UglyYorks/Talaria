#import "TLSkillsPicker.h"
#import "TLThemedButton.h"

@interface TLSkillRowView : NSTableCellView
@property (nonatomic, strong) NSSwitch *toggle;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) NSTextField *lockLabel;
@property (nonatomic, strong) TLThemePalette *palette;
- (void)configureWithSkill:(NSDictionary *)skill palette:(TLThemePalette *)palette;
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply;
@end

@implementation TLSkillRowView
- (instancetype)init {
  self = [super initWithFrame:NSZeroRect];
  if (!self) return nil;
  NSTextField *name = [NSTextField labelWithString:@""];
  name.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [self addSubview:name];
  self.textField = name;
  self.descriptionLabel = [NSTextField wrappingLabelWithString:@""];
  self.descriptionLabel.maximumNumberOfLines = 3;
  self.descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
  self.descriptionLabel.cell.wraps = YES;
  self.descriptionLabel.cell.scrollable = NO;
  self.descriptionLabel.tag = 2;
  self.lockLabel = [NSTextField wrappingLabelWithString:@""];
  self.lockLabel.tag = 3;
  self.toggle = [[NSSwitch alloc] init];
  self.toggle.tag = 1;
  for (NSView *view in @[self.descriptionLabel, self.lockLabel, self.toggle]) [self addSubview:view];
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)configureWithSkill:(NSDictionary *)skill palette:(TLThemePalette *)palette {
  self.palette = palette;
  // Match the native switches elsewhere in Settings to the resolved appearance.
  self.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.textField.stringValue = skill[@"name"];
  self.textField.toolTip = skill[@"name"];
  self.textField.font = palette.labelFont;
  self.textField.textColor = palette.controlText;
  self.descriptionLabel.stringValue = skill[@"description"] ?: @"";
  self.descriptionLabel.toolTip = self.descriptionLabel.stringValue;
  self.lockLabel.stringValue = skill[@"locked_reason"] ?: @"";
  for (NSTextField *label in @[self.descriptionLabel, self.lockLabel]) {
    label.font = palette.smallFont;
    label.textColor = palette.textMuted;
    label.hidden = !label.stringValue.length;
  }
  self.needsLayout = YES;
}
- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply {
  TLThemePalette *p = self.palette;
  CGFloat inset = p.space8;
  CGFloat available = MAX(0, width - inset * 2);
  NSSize toggleSize = self.toggle.intrinsicContentSize;
  BOOL compact = width < p.controlMinWidth * 3;
  CGFloat textWidth = compact ? available : MAX(0, available - toggleSize.width - p.space8);
  CGFloat titleHeight = ceil(self.textField.intrinsicContentSize.height);
  CGFloat topHeight = compact ? titleHeight : MAX(titleHeight, toggleSize.height);
  CGFloat y = inset + topHeight;
  if (apply) self.textField.frame = NSMakeRect(inset, inset + (topHeight - titleHeight) / 2, textWidth, titleHeight);
  for (NSTextField *label in @[self.descriptionLabel, self.lockLabel]) {
    if (label.hidden) continue;
    CGFloat height = ceil([label.cell cellSizeForBounds:NSMakeRect(0, 0, textWidth, CGFLOAT_MAX)].height);
    y += p.space2;
    if (apply) label.frame = NSMakeRect(inset, y, textWidth, height);
    y += height;
  }
  CGFloat toggleY = inset;
  if (compact) { toggleY = y + p.space4; y = toggleY + toggleSize.height; }
  if (apply) self.toggle.frame = NSMakeRect(MAX(inset, width - inset - toggleSize.width), toggleY, toggleSize.width, toggleSize.height);
  return ceil(y + inset);
}
- (void)layout { [super layout]; [self layoutForWidth:NSWidth(self.bounds) apply:YES]; }
@end

@interface TLSkillsPicker () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong, readwrite) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) TLThemedButton *reloadButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleSkills;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *draftChanges;
@property (nonatomic) CGFloat lastRowWidth;
@property (nonatomic, strong) TLSkillRowView *sizingRow;
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
    _sizingRow = [[TLSkillRowView alloc] init];
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
  self.statusLabel = [NSTextField wrappingLabelWithString:@""];
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
    [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
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

- (void)layout {
  [super layout];
  CGFloat width = self.tableView.tableColumns.firstObject.width;
  if (fabs(width - self.lastRowWidth) > 0.5) {
    self.lastRowWidth = width;
    [self.tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.visibleSkills.count)]];
  }
}

- (void)reloadData {
  NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  self.visibleSkills = [self.skills filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *skill, NSDictionary *bindings) {
    NSString *searchable = [NSString stringWithFormat:@"%@ %@", skill[@"name"], skill[@"description"] ?: @""];
    return !query.length || [searchable rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
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
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  [self.sizingRow configureWithSkill:self.visibleSkills[row] palette:self.palette];
  return [self.sizingRow layoutForWidth:tableView.tableColumns.firstObject.width apply:NO];
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  NSDictionary *skill = self.visibleSkills[row];
  TLSkillRowView *cell = [tableView makeViewWithIdentifier:@"skill" owner:self];
  if (!cell) {
    cell = [[TLSkillRowView alloc] init];
    cell.identifier = @"skill";
    cell.toggle.target = self;
    cell.toggle.action = @selector(toggleSkill:);
  }
  NSString *name = skill[@"name"];
  BOOL enabled = [self.draftChanges[name] ?: skill[@"enabled"] boolValue];
  NSString *reason = skill[@"locked_reason"] ?: @"";
  [cell configureWithSkill:skill palette:self.palette];
  cell.toggle.identifier = name;
  cell.toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
  cell.toggle.enabled = self.enabled && !self.loading && !reason.length;
  cell.toggle.toolTip = reason.length ? reason : [NSString stringWithFormat:@"%@ %@", enabled ? @"Disable" : @"Enable", name];
  cell.toggle.accessibilityLabel = name;
  cell.toggle.accessibilityHelp = reason.length ? reason : (skill[@"description"] ?: @"");
  return cell;
}

- (void)toggleSkill:(NSSwitch *)sender {
  if (!sender.enabled || !self.enabled || self.loading) return;
  NSString *name = sender.identifier;
  for (NSDictionary *skill in self.skills) {
    if (![skill[@"name"] isEqual:name] || [skill[@"locked_reason"] length]) continue;
    BOOL value = sender.state == NSControlStateValueOn;
    if (value == [skill[@"enabled"] boolValue]) [self.draftChanges removeObjectForKey:name];
    else self.draftChanges[name] = @(value);
    break;
  }
  [self reloadData];
  if (self.changesHandler) self.changesHandler();
}

- (void)applyPalette {
  self.searchField.font = self.palette.bodyFont;
  self.searchField.textColor = self.palette.controlText;
  self.searchField.backgroundColor = self.palette.controlSurface;
  self.reloadButton.palette = self.palette;
  self.scrollView.backgroundColor = self.palette.controlSurface;
  self.tableView.backgroundColor = self.palette.controlSurface;
  self.tableView.gridColor = self.palette.controlBorder;
  for (NSTextField *label in @[self.statusLabel, self.emptyLabel]) {
    label.font = self.palette.smallFont;
    label.textColor = self.palette.textMuted;
  }
}
@end
