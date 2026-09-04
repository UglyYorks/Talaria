#import "TLVMDebugTerminalWindowController.h"
#import "design_system/UIComponents.h"

@interface TLVMDebugTerminalWindowController () <NSTextFieldDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, strong) TLTokenView *rootView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSScrollView *outputScrollView;
@property (nonatomic, strong) NSTextView *outputView;
@property (nonatomic, strong) NSTextField *commandField;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *runButton;
@property (nonatomic) BOOL runningCommand;
@end

@implementation TLVMDebugTerminalWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette
               agentOrchestrator:(TLAgentOrchestrator *)agentOrchestrator {
  TLThemePalette *resolvedPalette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
                                                                      resolvedPalette.settingsSheetWidth,
                                                                      resolvedPalette.settingsSheetHeight)
                                                  styleMask:NSWindowStyleMaskTitled |
                                                            NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
  window.title = @"VM Terminal";
  window.releasedWhenClosed = NO;
  window.backgroundColor = resolvedPalette.tabBackground;
  self = [super initWithWindow:window];
  if (self) {
    _palette = resolvedPalette;
    _agentOrchestrator = agentOrchestrator;
    _sessionID = NSUUID.UUID.UUIDString;
    [self buildInterface];
  }
  return self;
}

- (NSTextField *)labelWithText:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
  NSTextField *label = [NSTextField labelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font;
  label.textColor = color;
  return label;
}

- (void)buildInterface {
  TLTokenView *root = [[TLTokenView alloc] init];
  self.rootView = root;
  root.fillColor = self.palette.tabBackground;

  NSTextField *titleLabel = [self labelWithText:@"Hermes VM terminal"
                                           font:self.palette.titleFont
                                          color:self.palette.appText];
  self.titleLabel = titleLabel;
  self.statusLabel = [self labelWithText:@"A new shell session will use the active agent VM."
                                    font:self.palette.smallFont
                                   color:self.palette.textMuted];

  NSScrollView *scrollView = [[NSScrollView alloc] init];
  self.outputScrollView = scrollView;
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.hasVerticalScroller = YES;
  scrollView.borderType = NSBezelBorder;
  scrollView.drawsBackground = YES;
  scrollView.backgroundColor = self.palette.controlSurface;

  self.outputView = [[NSTextView alloc] init];
  self.outputView.editable = NO;
  self.outputView.selectable = YES;
  self.outputView.font = self.palette.markdownCodeFont;
  self.outputView.textColor = self.palette.controlText;
  self.outputView.backgroundColor = self.palette.controlSurface;
  self.outputView.textContainerInset = NSMakeSize(self.palette.space5, self.palette.space5);
  scrollView.documentView = self.outputView;

  self.commandField = [[NSTextField alloc] init];
  self.commandField.translatesAutoresizingMaskIntoConstraints = NO;
  self.commandField.placeholderString = @"Enter a command, for example: ls -la";
  self.commandField.font = self.palette.markdownCodeFont;
  self.commandField.bezeled = YES;
  self.commandField.bezelStyle = NSTextFieldRoundedBezel;
  self.commandField.target = self;
  self.commandField.action = @selector(runCommand:);
  self.commandField.delegate = self;

  self.runButton = [NSButton buttonWithTitle:@"Run" target:self action:@selector(runCommand:)];
  self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.runButton.bezelStyle = NSBezelStyleRounded;
  self.runButton.controlSize = NSControlSizeLarge;
  self.runButton.font = self.palette.labelFont;
  self.runButton.bezelColor = self.palette.primaryActionSurface;
  self.runButton.contentTintColor = self.palette.primaryActionText;

  for (NSView *view in @[titleLabel, self.statusLabel, scrollView, self.commandField, self.runButton]) {
    [root addSubview:view];
  }
  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:self.palette.space12],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-self.palette.space12],
    [titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:self.palette.space11],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-self.palette.space12],
    [self.statusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:self.palette.space2],
    [scrollView.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-self.palette.space12],
    [scrollView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:self.palette.space8],
    [self.commandField.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
    [self.commandField.trailingAnchor constraintEqualToAnchor:self.runButton.leadingAnchor constant:-self.palette.space5],
    [self.commandField.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:self.palette.space6],
    [self.commandField.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-self.palette.space11],
    [self.commandField.heightAnchor constraintEqualToConstant:self.palette.fieldHeight],
    [self.runButton.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
    [self.runButton.centerYAnchor constraintEqualToAnchor:self.commandField.centerYAnchor],
    [self.runButton.widthAnchor constraintGreaterThanOrEqualToConstant:self.palette.controlMinWidth],
    [self.runButton.heightAnchor constraintEqualToConstant:self.palette.settingsActionHeight],
  ]];
  self.window.contentView = root;
  [self appendText:@"Talaria VM debug shell\nCommands run inside the active VM. Type ‘exit’ to close this window.\n"];
}

- (void)appendText:(NSString *)text {
  if (!text.length) return;
  NSDictionary *attributes = @{
    NSFontAttributeName: self.palette.markdownCodeFont,
    NSForegroundColorAttributeName: self.palette.controlText,
  };
  [self.outputView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text
                                                                                      attributes:attributes]];
  [self.outputView scrollRangeToVisible:NSMakeRange(self.outputView.string.length, 0)];
}

- (void)runCommand:(id)sender {
  if (self.runningCommand) return;
  NSString *command = [self.commandField.stringValue
    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!command.length) return;
  self.commandField.stringValue = @"";
  if ([command isEqualToString:@"clear"]) {
    self.outputView.string = @"";
    return;
  }
  if ([command isEqualToString:@"exit"]) {
    [self.window close];
    return;
  }

  [self appendText:[NSString stringWithFormat:@"\n$ %@\n", command]];
  self.runningCommand = YES;
  self.commandField.enabled = NO;
  self.runButton.enabled = NO;
  self.statusLabel.stringValue = @"Running command in the active VM…";
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator runShellCommandWithDefaultAgentSessionID:self.sessionID
                                                           command:command
                                                            output:^(NSString *text) {
    [weakSelf appendText:text];
  } completion:^(NSError *error) {
    TLVMDebugTerminalWindowController *strongSelf = weakSelf;
    if (!strongSelf) return;
    if (error) {
      [strongSelf appendText:[NSString stringWithFormat:@"Error: %@\n", error.localizedDescription]];
      strongSelf.statusLabel.stringValue = @"The command failed.";
    } else {
      [strongSelf appendText:@"\n"];
      strongSelf.statusLabel.stringValue = @"Connected to the active agent VM.";
    }
    strongSelf.runningCommand = NO;
    strongSelf.commandField.enabled = YES;
    strongSelf.runButton.enabled = YES;
    [strongSelf.window makeFirstResponder:strongSelf.commandField];
  }];
}

- (void)showFromWindow:(NSWindow *)parentWindow {
  if (parentWindow && !self.window.isVisible) {
    [self.window setFrameOrigin:NSMakePoint(NSMidX(parentWindow.frame) - NSWidth(self.window.frame) / 2.0,
                                            NSMidY(parentWindow.frame) - NSHeight(self.window.frame) / 2.0)];
  }
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [self.window makeFirstResponder:self.commandField];
}

- (void)updatePalette:(TLThemePalette *)palette {
  if (!palette) return;
  self.palette = palette;
  self.window.backgroundColor = palette.tabBackground;
  self.rootView.fillColor = palette.tabBackground;
  self.titleLabel.font = palette.titleFont;
  self.titleLabel.textColor = palette.appText;
  self.statusLabel.font = palette.smallFont;
  self.statusLabel.textColor = palette.textMuted;
  self.outputScrollView.backgroundColor = palette.controlSurface;
  self.outputView.font = palette.markdownCodeFont;
  self.outputView.textColor = palette.controlText;
  self.outputView.backgroundColor = palette.controlSurface;
  if (self.outputView.string.length > 0) {
    [self.outputView.textStorage addAttributes:@{NSFontAttributeName: palette.markdownCodeFont,
                                                 NSForegroundColorAttributeName: palette.controlText}
                                       range:NSMakeRange(0, self.outputView.string.length)];
  }
  self.commandField.font = palette.markdownCodeFont;
  self.runButton.font = palette.labelFont;
  self.runButton.bezelColor = palette.primaryActionSurface;
  self.runButton.contentTintColor = palette.primaryActionText;
  [self.rootView setNeedsDisplay:YES];
}

@end
