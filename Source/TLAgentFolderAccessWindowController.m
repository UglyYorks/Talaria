#import "design_system/TLThemedButton.h"
#import "TLAgentFolderAccessWindowController.h"
#import "design_system/TLFolderAccessPicker.h"
#import "design_system/UIComponents.h"

@interface TLAgentFolderAccessWindowController ()
@property (nonatomic) NSInteger agentID;
@property (nonatomic, strong) TLAgentOrchestrator *orchestrator;
@property (nonatomic, strong) TLFolderAccessPicker *folderPicker;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) TLTokenView *separator;
@end

@implementation TLAgentFolderAccessWindowController

- (instancetype)initWithAgent:(TLAgentRecord *)agent palette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
    palette.settingsSheetWidth - palette.space16 * 2, palette.settingsSheetHeight - palette.space16 * 4)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self = [super initWithWindow:window];
  if (self) {
    _agentID = agent.agentID;
    _orchestrator = orchestrator;
    window.title = @"Folder Access";
    window.releasedWhenClosed = NO;
    TLTokenView *root = [[TLTokenView alloc] init];
    window.contentView = root;
    self.titleLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%@  %@ — Folder Access", agent.avatar, agent.name]];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.toolTip = agent.name;
    self.detailLabel = [NSTextField wrappingLabelWithString:@"Choose folders for this agent. Saved for future VM mounts; folder access is not enabled yet."];
    self.folderPicker = [[TLFolderAccessPicker alloc] init];
    self.folderPicker.palette = palette;
    self.folderPicker.folderPaths = agent.folderPaths;
    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.maximumNumberOfLines = 2;
    self.separator = [[TLTokenView alloc] init];
    self.cancelButton = [TLThemedButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    self.cancelButton.keyEquivalent = @"\e";
    self.saveButton = [TLThemedButton buttonWithTitle:@"Save" target:self action:@selector(save:)];
    self.saveButton.keyEquivalent = @"\r";
    for (NSButton *button in @[self.cancelButton, self.saveButton]) {
      button.bezelStyle = NSBezelStyleRounded;
      button.font = palette.labelFont;
    }
    NSStackView *actions = [NSStackView stackViewWithViews:@[self.cancelButton, self.saveButton]];
    actions.spacing = palette.space5;
    for (NSView *view in @[self.titleLabel, self.detailLabel, self.folderPicker, self.separator, self.statusLabel, actions]) {
      view.translatesAutoresizingMaskIntoConstraints = NO;
      [root addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
      [self.titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:palette.space12],
      [self.titleLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-palette.space12],
      [self.titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:palette.space12],
      [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
      [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
      [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:palette.space4],
      [self.folderPicker.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
      [self.folderPicker.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
      [self.folderPicker.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:palette.space10],
      [self.folderPicker.bottomAnchor constraintLessThanOrEqualToAnchor:self.separator.topAnchor constant:-palette.space10],
      [self.separator.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
      [self.separator.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
      [self.separator.heightAnchor constraintEqualToConstant:palette.borderWidth],
      [self.separator.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-palette.space10],
      [actions.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
      [actions.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-palette.space10],
      [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
      [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-palette.space8],
      [self.statusLabel.centerYAnchor constraintEqualToAnchor:actions.centerYAnchor],
    ]];
    [self applyPalette:palette];
  }
  return self;
}

- (void)save:(id)sender {
  NSError *error = nil;
  if (![self.orchestrator updateAgentWithID:self.agentID folderPaths:self.folderPicker.folderPaths error:&error]) {
    self.statusLabel.stringValue = error.localizedDescription ?: @"Could not save folder access.";
    return;
  }
  [self cancel:sender];
  if (self.savedHandler) self.savedHandler();
}

- (void)cancel:(id)sender {
  [self.window.sheetParent endSheet:self.window];
  [self.window orderOut:nil];
}

- (void)showFromWindow:(NSWindow *)parent {
  [parent beginSheet:self.window completionHandler:nil];
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.tabBackground;
  ((TLTokenView *)self.window.contentView).fillColor = palette.tabBackground;
  self.titleLabel.font = palette.titleFont;
  self.titleLabel.textColor = palette.appText;
  self.detailLabel.font = palette.smallFont;
  self.detailLabel.textColor = palette.textMuted;
  self.statusLabel.font = palette.smallFont;
  self.statusLabel.textColor = palette.textMuted;
  self.separator.fillColor = palette.controlBorder;
  self.folderPicker.palette = palette;
  ((TLThemedButton *)self.saveButton).primary = YES;
  ((TLThemedButton *)self.saveButton).palette = palette;
  ((TLThemedButton *)self.cancelButton).palette = palette;
}
@end
