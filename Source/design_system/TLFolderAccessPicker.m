#import "TLThemedButton.h"
#import "TLFolderAccessPicker.h"

@interface TLFolderAccessPicker () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong, readwrite) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *tableScroll;
@property (nonatomic, strong) NSTextField *emptyLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *removeButton;
@property (nonatomic, copy) NSArray<NSButton *> *shortcutButtons;
@property (nonatomic, strong) NSStackView *shortcuts;
@property (nonatomic, strong) NSStackView *actions;
@end

@implementation TLFolderAccessPicker

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _enabled = YES;
    _folderPaths = @[];
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    [self buildInterface];
    [self applyPalette];
    [self updateControlStates];
  }
  return self;
}

- (NSButton *)button:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
  NSButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bezelStyle = NSBezelStyleRounded;
  button.controlSize = NSControlSizeSmall;
  if (symbol.length) {
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    button.imagePosition = NSImageLeading;
    button.imageHugsTitle = YES;
  }
  return button;
}

- (void)buildInterface {
  TLThemePalette *p = self.palette;
  self.shortcuts = [[NSStackView alloc] init];
  self.shortcuts.translatesAutoresizingMaskIntoConstraints = NO;
  self.shortcuts.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  self.shortcuts.spacing = p.space4;
  NSMutableArray *buttons = [NSMutableArray array];
  for (NSArray *item in @[@[@"Full hard drive", @"internaldrive", @"disk"],
                          @[@"Home", @"house", @"home"], @[@"Desktop", @"menubar.dock.rectangle", @"desktop"],
                          @[@"Documents", @"doc", @"documents"], @[@"Downloads", @"arrow.down.circle", @"downloads"]]) {
    NSButton *button = [self button:item[0] symbol:item[1] action:@selector(addShortcut:)];
    button.identifier = item[2];
    button.toolTip = [NSString stringWithFormat:@"Add %@ to the folder list", item[0]];
    [buttons addObject:button];
    [self.shortcuts addArrangedSubview:button];
  }
  self.shortcutButtons = buttons;
  [self addSubview:self.shortcuts];

  self.tableView = [[NSTableView alloc] init];
  self.tableView.delegate = self;
  self.tableView.dataSource = self;
  self.tableView.style = NSTableViewStyleFullWidth;
  self.tableView.allowsMultipleSelection = YES;
  self.tableView.allowsEmptySelection = YES;
  self.tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  self.tableView.rowHeight = p.fieldHeight;
  self.tableView.intercellSpacing = NSMakeSize(p.space5, p.space2);
  self.tableView.accessibilityLabel = @"Folders available for future VM mounts";
  NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
  name.title = @"Folder";
  name.width = p.controlMinWidth * 1.7;
  name.minWidth = p.controlMinWidth;
  NSTableColumn *path = [[NSTableColumn alloc] initWithIdentifier:@"path"];
  path.title = @"Location";
  path.width = p.controlMinWidth * 3;
  path.minWidth = p.controlMinWidth;
  [self.tableView addTableColumn:name];
  [self.tableView addTableColumn:path];
  self.tableScroll = [[NSScrollView alloc] init];
  self.tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableScroll.documentView = self.tableView;
  self.tableScroll.hasVerticalScroller = YES;
  self.tableScroll.autohidesScrollers = YES;
  self.tableScroll.borderType = NSBezelBorder;
  [self addSubview:self.tableScroll];

  self.emptyLabel = [NSTextField labelWithString:@"No folders selected"];
  self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLabel.alignment = NSTextAlignmentCenter;
  [self addSubview:self.emptyLabel];

  self.actions = [[NSStackView alloc] init];
  self.actions.translatesAutoresizingMaskIntoConstraints = NO;
  self.actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  self.actions.spacing = p.space4;
  self.addButton = [self button:@"Add Folder…" symbol:@"plus" action:@selector(chooseFolders:)];
  self.removeButton = [self button:@"Remove" symbol:@"minus" action:@selector(removeFolders:)];
  [self.actions addArrangedSubview:self.addButton];
  [self.actions addArrangedSubview:self.removeButton];
  [self addSubview:self.actions];
  self.countLabel = [NSTextField labelWithString:@""];
  self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:self.countLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.shortcuts.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.shortcuts.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.shortcuts.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
    [self.tableScroll.topAnchor constraintEqualToAnchor:self.shortcuts.bottomAnchor constant:p.space5],
    [self.tableScroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.tableScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.tableScroll.heightAnchor constraintEqualToConstant:p.fieldHeight * 4 + p.space12],
    [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableScroll.centerXAnchor],
    [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableScroll.centerYAnchor constant:p.space5],
    [self.actions.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.actions.topAnchor constraintEqualToAnchor:self.tableScroll.bottomAnchor constant:p.space4],
    [self.actions.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [self.countLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.countLabel.centerYAnchor constraintEqualToAnchor:self.actions.centerYAnchor],
    [self.countLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.actions.trailingAnchor constant:p.space5],
  ]];
}

- (void)setFolderPaths:(NSArray<NSString *> *)folderPaths {
  NSMutableOrderedSet *paths = [NSMutableOrderedSet orderedSet];
  for (NSString *path in folderPaths) {
    if (path.isAbsolutePath) [paths addObject:path.stringByStandardizingPath];
  }
  _folderPaths = paths.array;
  [self.tableView reloadData];
  [self updateControlStates];
}

- (void)addPaths:(NSArray<NSString *> *)paths {
  if (!self.enabled) return;
  self.folderPaths = [self.folderPaths arrayByAddingObjectsFromArray:paths];
}

- (void)addShortcut:(NSButton *)sender {
  if (!self.enabled) return;
  NSString *path = nil;
  if ([sender.identifier isEqualToString:@"disk"]) path = @"/";
  else if ([sender.identifier isEqualToString:@"home"]) path = NSFileManager.defaultManager.homeDirectoryForCurrentUser.path;
  else {
    NSSearchPathDirectory directory = NSDocumentDirectory;
    if ([sender.identifier isEqualToString:@"desktop"]) directory = NSDesktopDirectory;
    else if ([sender.identifier isEqualToString:@"downloads"]) directory = NSDownloadsDirectory;
    path = [NSFileManager.defaultManager URLsForDirectory:directory inDomains:NSUserDomainMask].firstObject.path;
  }
  if (path.length) [self addPaths:@[path]];
}

- (void)chooseFolders:(id)sender {
  if (!self.enabled) return;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.allowsMultipleSelection = YES;
  panel.prompt = @"Add Folders";
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !self.enabled) return;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *url in panel.URLs) if (url.isFileURL) [paths addObject:url.path];
    [self addPaths:paths];
  }];
}

- (void)removeFolders:(id)sender {
  if (!self.enabled) return;
  NSMutableArray *paths = self.folderPaths.mutableCopy;
  [self.tableView.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger index, BOOL *stop) {
    if (index < paths.count) [paths removeObjectAtIndex:index];
  }];
  [self.tableView deselectAll:nil];
  self.folderPaths = paths;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.folderPaths.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  if (row < 0 || row >= (NSInteger)self.folderPaths.count) return nil;
  BOOL nameColumn = [column.identifier isEqualToString:@"name"];
  NSTableCellView *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
  if (!cell) {
    cell = [[NSTableCellView alloc] init];
    cell.identifier = column.identifier;
    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.textField = label;
    [cell addSubview:label];
    NSLayoutXAxisAnchor *leading = cell.leadingAnchor;
    if (nameColumn) {
      NSImageView *icon = [[NSImageView alloc] init];
      icon.translatesAutoresizingMaskIntoConstraints = NO;
      cell.imageView = icon;
      [cell addSubview:icon];
      [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space4],
        [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:self.palette.sidebarActionIconSize],
        [icon.heightAnchor constraintEqualToAnchor:icon.widthAnchor],
      ]];
      leading = icon.trailingAnchor;
    }
    [NSLayoutConstraint activateConstraints:@[
      [label.leadingAnchor constraintEqualToAnchor:leading constant:self.palette.space5],
      [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space4],
      [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
  }
  NSString *path = self.folderPaths[(NSUInteger)row];
  BOOL root = [path isEqualToString:@"/"];
  BOOL home = [path isEqualToString:NSFileManager.defaultManager.homeDirectoryForCurrentUser.path];
  cell.textField.stringValue = nameColumn ? (root ? @"Full hard drive" : home ? @"Home" : path.lastPathComponent) : path;
  cell.textField.font = self.palette.smallFont;
  cell.textField.textColor = nameColumn ? self.palette.controlText : self.palette.textMuted;
  cell.toolTip = path;
  cell.imageView.image = [NSImage imageWithSystemSymbolName:root ? @"internaldrive" : home ? @"house" : @"folder" accessibilityDescription:nil];
  cell.imageView.contentTintColor = self.palette.textMuted;
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateControlStates]; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [self updateControlStates]; }

- (void)updateControlStates {
  self.emptyLabel.hidden = self.folderPaths.count > 0;
  self.countLabel.stringValue = [NSString stringWithFormat:@"%lu folder%@", (unsigned long)self.folderPaths.count, self.folderPaths.count == 1 ? @"" : @"s"];
  self.addButton.enabled = self.enabled;
  self.removeButton.enabled = self.enabled && self.tableView.selectedRowIndexes.count > 0;
  for (NSButton *button in self.shortcutButtons) button.enabled = self.enabled;
}

- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyPalette]; }

- (void)applyPalette {
  self.tableView.backgroundColor = self.palette.controlSurface;
  self.tableScroll.backgroundColor = self.palette.controlSurface;
  self.emptyLabel.font = self.palette.smallFont;
  self.emptyLabel.textColor = self.palette.textMuted;
  self.countLabel.font = self.palette.smallFont;
  self.countLabel.textColor = self.palette.textMuted;
  for (NSButton *button in [self.shortcutButtons arrayByAddingObjectsFromArray:@[self.addButton, self.removeButton]]) {
    button.font = self.palette.smallFont;
    ((TLThemedButton *)button).palette = self.palette;
  }
  NSIndexSet *selection = self.tableView.selectedRowIndexes;
  [self.tableView reloadData];
  [self.tableView selectRowIndexes:selection byExtendingSelection:NO];
}
@end
