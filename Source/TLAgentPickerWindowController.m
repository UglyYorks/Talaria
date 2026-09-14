#import "TLAgentPickerWindowController.h"
#import "design_system/TLThemedButton.h"
#import "design_system/UIComponents.h"

@interface TLAgentPickerWindowController ()
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSMutableArray<NSTextField *> *detailLabels;
@property (nonatomic, strong) NSMutableArray<NSTextField *> *nameLabels;
@property (nonatomic, strong) NSMutableArray<TLTokenView *> *cards;
@property (nonatomic, strong) NSMutableArray<TLThemedButton *> *buttons;
@end

@implementation TLAgentPickerWindowController

- (instancetype)initWithAgents:(NSArray<TLAgentRecord *> *)agents currentAgentID:(NSInteger)currentAgentID
             selectionEnabled:(BOOL)selectionEnabled palette:(TLThemePalette *)palette {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
    palette.settingsSheetWidth - palette.space16 * 2, palette.settingsSheetHeight - palette.space16)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self = [super initWithWindow:window];
  if (!self) return nil;
  _palette = palette;
  _detailLabels = [NSMutableArray array];
  _nameLabels = [NSMutableArray array];
  _cards = [NSMutableArray array];
  _buttons = [NSMutableArray array];
  window.title = @"Choose Agent";
  window.releasedWhenClosed = NO;
  TLTokenView *root = [[TLTokenView alloc] init];
  window.contentView = root;
  self.titleLabel = [NSTextField labelWithString:@"Choose an agent"];
  NSTextField *subtitle = [self detailLabel:selectionEnabled ?
    @"Choose who to work with. Projects are the folders shared with each agent." :
    @"You can switch agents once the current responses finish."];

  self.subtitleLabel = subtitle;

  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.drawsBackground = NO;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  NSStackView *list = [[NSStackView alloc] init];
  list.translatesAutoresizingMaskIntoConstraints = NO;
  list.orientation = NSUserInterfaceLayoutOrientationVertical;
  list.alignment = NSLayoutAttributeWidth;
  list.spacing = palette.space6;
  scroll.documentView = list;
  for (TLAgentRecord *agent in agents) {
    TLTokenView *card = [[TLTokenView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cards addObject:card];
    NSString *name = [NSString stringWithFormat:@"%@  %@", agent.avatar.length ? agent.avatar : @"🤖", agent.name];
    NSTextField *nameLabel = [NSTextField wrappingLabelWithString:name];
    [self.nameLabels addObject:nameLabel];
    BOOL current = agent.agentID == currentAgentID;
    TLThemedButton *select = [self button:current ? @"Current" : @"Select" action:@selector(selectAgent:)];
    select.tag = agent.agentID;
    select.primary = current;
    select.enabled = selectionEnabled && !current;
    select.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", current ? @"Current agent:" : @"Select", agent.name];
    NSString *access = agent.folderPaths.count ? [NSString stringWithFormat:
      @"Access: Internet · Read and write to %lu shared %@", (unsigned long)agent.folderPaths.count,
      agent.folderPaths.count == 1 ? @"folder" : @"folders"] : @"Access: Internet · No shared Mac folders";
    NSTextField *accessLabel = [self detailLabel:access];
    NSMutableArray<NSString *> *projects = [NSMutableArray array];
    for (NSString *path in agent.folderPaths) {
      [projects addObject:[NSString stringWithFormat:@"%@ — %@", path.lastPathComponent.length ? path.lastPathComponent : path,
        path.stringByAbbreviatingWithTildeInPath]];
    }
    NSTextField *projectLabel = [self detailLabel:projects.count ?
      [@"Projects\n" stringByAppendingString:[projects componentsJoinedByString:@"\n"]] : @"Projects: No shared folders"];
    projectLabel.selectable = YES;
    for (NSView *view in @[nameLabel, select, accessLabel, projectLabel]) {
      view.translatesAutoresizingMaskIntoConstraints = NO;
      [card addSubview:view];
    }
    [select setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [select setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [list addArrangedSubview:card];
    NSLayoutConstraint *accessTop = [accessLabel.topAnchor constraintEqualToAnchor:select.bottomAnchor constant:palette.space5];
    accessTop.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
      [card.widthAnchor constraintEqualToAnchor:list.widthAnchor],
      [nameLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:palette.space8],
      [nameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:palette.space8],
      [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:select.leadingAnchor constant:-palette.space6],
      [select.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-palette.space8],
      [select.topAnchor constraintEqualToAnchor:nameLabel.topAnchor],
      [accessLabel.topAnchor constraintGreaterThanOrEqualToAnchor:nameLabel.bottomAnchor constant:palette.space5],
      [accessLabel.topAnchor constraintGreaterThanOrEqualToAnchor:select.bottomAnchor constant:palette.space5],
      accessTop,
      [accessLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
      [accessLabel.trailingAnchor constraintEqualToAnchor:select.trailingAnchor],
      [projectLabel.topAnchor constraintEqualToAnchor:accessLabel.bottomAnchor constant:palette.space6],
      [projectLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
      [projectLabel.trailingAnchor constraintEqualToAnchor:select.trailingAnchor],
      [projectLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-palette.space8],
    ]];
  }
  if (!agents.count) {
    NSTextField *empty = [self detailLabel:@"No agents yet. Open Manage Agents to create your first agent."];
    [list addArrangedSubview:empty];
    [empty.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
  }
  TLThemedButton *manage = [self button:@"Manage Agents…" action:@selector(manageAgents:)];
  TLThemedButton *done = [self button:@"Done" action:@selector(dismiss:)];
  done.keyEquivalent = @"\e";
  for (NSView *view in @[self.titleLabel, subtitle, scroll, manage, done]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:view];
  }
  [NSLayoutConstraint activateConstraints:@[
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:palette.space12],
    [self.titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:palette.space12],
    [self.titleLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-palette.space12],
    [subtitle.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [subtitle.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
    [subtitle.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:palette.space4],
    [scroll.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [scroll.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
    [scroll.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:palette.space8],
    [scroll.bottomAnchor constraintEqualToAnchor:done.topAnchor constant:-palette.space8],
    [list.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
    [list.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
    [list.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    [manage.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [manage.centerYAnchor constraintEqualToAnchor:done.centerYAnchor],
    [manage.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-palette.space6],
    [done.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
    [done.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-palette.space10],
  ]];
  [self applyPalette:palette];
  return self;
}

- (NSTextField *)detailLabel:(NSString *)text {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  [self.detailLabels addObject:label];
  return label;
}

- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  [self.buttons addObject:button];
  return button;
}

- (void)selectAgent:(NSControl *)sender {
  if (self.selectionHandler && self.selectionHandler(sender.tag)) [self dismiss:sender];
}

- (void)manageAgents:(id)sender {
  [self dismiss:sender];
  if (self.manageHandler) self.manageHandler();
}

- (void)dismiss:(id)sender {
  [self.window.sheetParent endSheet:self.window];
  [self.window orderOut:nil];
}

- (void)showErrorMessage:(NSString *)message {
  self.subtitleLabel.stringValue = message;
}

- (void)showFromWindow:(NSWindow *)parent {
  [parent beginSheet:self.window completionHandler:nil];
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.tabBackground;
  ((TLTokenView *)self.window.contentView).fillColor = palette.tabBackground;
  self.titleLabel.font = palette.titleFont;
  self.titleLabel.textColor = palette.appText;
  for (NSTextField *label in self.nameLabels) { label.font = palette.labelFont; label.textColor = palette.appText; }
  for (NSTextField *label in self.detailLabels) { label.font = palette.smallFont; label.textColor = palette.textMuted; }
  for (TLTokenView *card in self.cards) { card.fillColor = palette.controlSurface; card.cornerRadius = palette.radiusMedium; }
  for (TLThemedButton *button in self.buttons) button.palette = palette;
}
@end
