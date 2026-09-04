#import "TLHermesOnboardingWindowController.h"
#import "design_system/UIComponents.h"

@interface TLHermesOnboardingWindowController ()
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSSecureTextField *tokenField;
@property (nonatomic, strong) NSTextField *modelField;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextView *progressView;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSButton *doneButton;
@end

@implementation TLHermesOnboardingWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette token:(NSString *)token model:(NSString *)model {
  TLThemePalette *resolved = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, resolved.settingsSheetWidth, resolved.settingsSheetHeight)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO];
  window.title = @"Set up Talaria";
  window.releasedWhenClosed = NO;
  window.backgroundColor = resolved.tabBackground;
  [window center];
  self = [super initWithWindow:window];
  if (self) {
    _palette = resolved;
    [self buildInterfaceWithToken:token model:model];
  }
  return self;
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font;
  label.textColor = color;
  return label;
}

- (void)buildInterfaceWithToken:(NSString *)token model:(NSString *)model {
  TLTokenView *root = [[TLTokenView alloc] init];
  root.fillColor = self.palette.tabBackground;
  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = self.palette.space8;
  [root addSubview:stack];

  [stack addArrangedSubview:[self label:@"Your private Hermes VM" font:self.palette.titleFont color:self.palette.appText]];
  NSTextField *intro = [self label:@"Create a fresh Linux VM, install Hermes Agent from the official source, and keep every Talaria chat in its own Hermes session."
                                font:self.palette.bodyFont color:self.palette.textMuted];
  intro.maximumNumberOfLines = 0;
  intro.lineBreakMode = NSLineBreakByWordWrapping;
  [stack addArrangedSubview:intro];

  NSStackView *steps = [[NSStackView alloc] init];
  steps.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  steps.distribution = NSStackViewDistributionFillEqually;
  steps.spacing = self.palette.space5;
  for (NSString *text in @[@"1  Create isolated VM", @"2  Install Hermes Agent", @"3  Start session-native chats"]) {
    TLTokenView *card = [[TLTokenView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.fillColor = self.palette.controlSurface;
    card.cornerRadius = self.palette.radiusMedium;
    NSTextField *label = [self label:text font:self.palette.labelFont color:self.palette.controlText];
    [card addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:self.palette.space5],
      [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-self.palette.space5],
      [label.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
      [card.heightAnchor constraintEqualToConstant:self.palette.fieldHeight + self.palette.space5],
    ]];
    [steps addArrangedSubview:card];
  }
  [stack addArrangedSubview:steps];
  [steps.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

  [stack addArrangedSubview:[self label:@"OpenRouter API key" font:self.palette.labelFont color:self.palette.labelText]];
  self.tokenField = [[NSSecureTextField alloc] init];
  self.tokenField.translatesAutoresizingMaskIntoConstraints = NO;
  self.tokenField.stringValue = token ?: @"";
  self.tokenField.placeholderString = @"sk-or-v1-…";
  self.tokenField.font = self.palette.bodyFont;
  self.tokenField.bezeled = YES;
  self.tokenField.bezelStyle = NSTextFieldRoundedBezel;
  [stack addArrangedSubview:self.tokenField];
  [self.tokenField.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  [self.tokenField.heightAnchor constraintEqualToConstant:self.palette.fieldHeight].active = YES;

  [stack addArrangedSubview:[self label:@"Default model" font:self.palette.labelFont color:self.palette.labelText]];
  self.modelField = [[NSTextField alloc] init];
  self.modelField.translatesAutoresizingMaskIntoConstraints = NO;
  self.modelField.stringValue = model ?: @"";
  self.modelField.placeholderString = @"anthropic/claude-sonnet-4";
  self.modelField.font = self.palette.bodyFont;
  self.modelField.bezeled = YES;
  self.modelField.bezelStyle = NSTextFieldRoundedBezel;
  [stack addArrangedSubview:self.modelField];
  [self.modelField.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  [self.modelField.heightAnchor constraintEqualToConstant:self.palette.fieldHeight].active = YES;

  self.statusLabel = [self label:@"Ready to create a new VM" font:self.palette.smallFont color:self.palette.textMuted];
  [stack addArrangedSubview:self.statusLabel];

  NSScrollView *progressScroll = [[NSScrollView alloc] init];
  progressScroll.translatesAutoresizingMaskIntoConstraints = NO;
  progressScroll.hasVerticalScroller = YES;
  progressScroll.drawsBackground = YES;
  progressScroll.backgroundColor = self.palette.controlSurface;
  self.progressView = [[NSTextView alloc] init];
  self.progressView.editable = NO;
  self.progressView.font = self.palette.smallFont;
  self.progressView.textColor = self.palette.controlText;
  self.progressView.backgroundColor = self.palette.controlSurface;
  progressScroll.documentView = self.progressView;
  progressScroll.hidden = YES;
  [stack addArrangedSubview:progressScroll];
  [progressScroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  [progressScroll.heightAnchor constraintEqualToConstant:self.palette.space16 * 2.0].active = YES;

  NSStackView *actions = [[NSStackView alloc] init];
  actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  actions.alignment = NSLayoutAttributeCenterY;
  actions.spacing = self.palette.space5;
  self.startButton = [NSButton buttonWithTitle:@"Create VM & install Hermes" target:self action:@selector(start:)];
  self.doneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(done:)];
  self.doneButton.hidden = YES;
  for (NSButton *button in @[self.startButton, self.doneButton]) {
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeLarge;
    button.font = self.palette.labelFont;
    button.contentTintColor = self.palette.primaryActionText;
    button.bezelColor = self.palette.primaryActionSurface;
    [button.heightAnchor constraintEqualToConstant:self.palette.settingsActionHeight].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.controlMinWidth * 2.0].active = YES;
  }
  [actions addArrangedSubview:self.startButton];
  [actions addArrangedSubview:self.doneButton];
  [stack addArrangedSubview:actions];

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:self.palette.space12],
    [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-self.palette.space12],
    [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:self.palette.space12],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-self.palette.space12],
  ]];
  self.window.contentView = root;
}

- (void)start:(id)sender {
  NSString *token = [self.tokenField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *model = [self.modelField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!token.length || !model.length) {
    self.statusLabel.stringValue = @"Enter an API key and model to continue.";
    return;
  }
  self.startButton.enabled = NO;
  self.tokenField.enabled = NO;
  self.modelField.enabled = NO;
  self.statusLabel.stringValue = @"Creating VM and installing Hermes Agent…";
  ((NSScrollView *)self.progressView.enclosingScrollView).hidden = NO;
  if (self.startHandler) self.startHandler(token, model);
}

- (void)appendProgress:(NSString *)text {
  if (!text.length) return;
  [self.progressView.textStorage appendAttributedString:[[NSAttributedString alloc]
    initWithString:text attributes:@{NSFontAttributeName: self.palette.smallFont,
                                     NSForegroundColorAttributeName: self.palette.controlText}]];
  [self.progressView scrollRangeToVisible:NSMakeRange(self.progressView.string.length, 0)];
}

- (void)finishWithError:(NSError *)error {
  if (error) {
    self.statusLabel.stringValue = error.localizedDescription ?: @"Hermes Agent installation failed.";
    self.startButton.enabled = YES;
    self.tokenField.enabled = YES;
    self.modelField.enabled = YES;
    return;
  }
  self.statusLabel.stringValue = @"Hermes Agent is installed and ready.";
  self.doneButton.hidden = NO;
  self.startButton.hidden = YES;
}

- (void)done:(id)sender {
  [self.window close];
  if (self.closeHandler) self.closeHandler();
}

- (void)showFromWindow:(NSWindow *)parentWindow {
  if (parentWindow) [self.window setFrameOrigin:NSMakePoint(NSMidX(parentWindow.frame) - NSWidth(self.window.frame) / 2.0,
                                                            NSMidY(parentWindow.frame) - NSHeight(self.window.frame) / 2.0)];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

@end
