#import "TLAgentTableCells.h"

@interface TLAgentNameCellView ()
@property (nonatomic, strong) NSTextField *avatarLabel;
@property (nonatomic, strong) NSTextField *currentLabel;
@end

@implementation TLAgentNameCellView

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    self.avatarLabel = [NSTextField labelWithString:@""];
    self.avatarLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarLabel.alignment = NSTextAlignmentCenter;
    [self addSubview:self.avatarLabel];
    NSTextField *label = [NSTextField labelWithString:@""];
    self.textField = label;
    self.textField.lineBreakMode = NSLineBreakByWordWrapping;
    self.textField.maximumNumberOfLines = 2;
    self.textField.cell.wraps = YES;
    self.textField.cell.scrollable = NO;
    self.currentLabel = [NSTextField labelWithString:@"Current"];
    NSStackView *labels = [NSStackView stackViewWithViews:@[label, self.currentLabel]];
    labels.translatesAutoresizingMaskIntoConstraints = NO;
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = palette.space2;
    [self addSubview:labels];
    [NSLayoutConstraint activateConstraints:@[
      [self.avatarLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space4],
      [self.avatarLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [self.avatarLabel.widthAnchor constraintEqualToConstant:palette.agentListAvatarFont.pointSize + palette.space5],
      [labels.leadingAnchor constraintEqualToAnchor:self.avatarLabel.trailingAnchor constant:palette.space5],
      [labels.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space4],
      [labels.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [self.textField.widthAnchor constraintEqualToAnchor:labels.widthAnchor],
    ]];
  }
  return self;
}

- (void)configureWithName:(NSString *)name avatar:(NSString *)avatar current:(BOOL)current palette:(TLThemePalette *)palette {
  self.textField.stringValue = name;
  self.textField.font = palette.bodyFont;
  self.textField.textColor = palette.appText;
  self.textField.toolTip = name;
  self.avatarLabel.stringValue = avatar;
  self.avatarLabel.font = palette.agentListAvatarFont;
  self.avatarLabel.textColor = palette.appText;
  self.currentLabel.hidden = !current;
  self.currentLabel.font = palette.smallFont;
  self.currentLabel.textColor = palette.textMuted;
  self.currentLabel.toolTip = @"Used for chats, model requests, and the VM terminal.";
}

@end

@interface TLAgentStatusCellView ()
@property (nonatomic, strong) NSTextField *dotLabel;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation TLAgentStatusCellView

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.spinner.accessibilityElement = NO;
    [self addSubview:self.spinner];
    self.dotLabel = [NSTextField labelWithString:@"●"];
    self.dotLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dotLabel.accessibilityElement = NO;
    self.dotLabel.alignment = NSTextAlignmentCenter;
    NSTextField *label = [NSTextField labelWithString:@""];
    self.textField = label;
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.lineBreakMode = NSLineBreakByWordWrapping;
    self.textField.maximumNumberOfLines = 2;
    self.textField.cell.wraps = YES;
    self.textField.cell.scrollable = NO;
    [self addSubview:self.dotLabel];
    [self addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [self.dotLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space4],
      [self.dotLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [self.dotLabel.widthAnchor constraintEqualToConstant:palette.space8],
      [self.spinner.centerXAnchor constraintEqualToAnchor:self.dotLabel.centerXAnchor],
      [self.spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [self.spinner.widthAnchor constraintEqualToConstant:palette.space8],
      [self.spinner.heightAnchor constraintEqualToConstant:palette.space8],
      [self.textField.leadingAnchor constraintEqualToAnchor:self.dotLabel.trailingAnchor constant:palette.space4],
      [self.textField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space4],
      [self.textField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    [self.dotLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.dotLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
  }
  return self;
}

- (void)configureWithStatus:(NSString *)status running:(BOOL)running initializing:(BOOL)initializing setupRequired:(BOOL)setupRequired palette:(TLThemePalette *)palette {
  self.textField.stringValue = status;
  self.textField.font = palette.bodyFont;
  self.textField.textColor = palette.appText;
  self.dotLabel.hidden = initializing;
  if (initializing) [self.spinner startAnimation:nil];
  else [self.spinner stopAnimation:nil];
  self.dotLabel.font = palette.smallFont;
  self.dotLabel.textColor = setupRequired ? palette.agentSetupRequiredIndicator : (running ? palette.agentRunningIndicator : palette.textMuted);
}

@end
