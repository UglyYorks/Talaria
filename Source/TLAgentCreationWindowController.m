#import "design_system/TLThemedButton.h"
#import "TLAgentCreationWindowController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLEmojiPicker.h"
#import "design_system/TLFolderAccessPicker.h"

@interface TLAgentCreationWindowController () <NSWindowDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLAgentOrchestrator *orchestrator;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) TLEmojiPicker *avatarPicker;
@property (nonatomic, strong) NSTextView *soulView;
@property (nonatomic, strong) TLFolderAccessPicker *folderPicker;
@property (nonatomic, strong) NSButton *createButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy, readonly) NSArray<NSString *> *folderPaths;
@property (nonatomic) NSInteger createdAgentID;
@property (nonatomic) NSInteger editingAgentID;
@end

@implementation TLAgentCreationWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator {
  return [self initWithAgent:nil palette:palette orchestrator:orchestrator];
}

- (instancetype)initWithAgent:(TLAgentRecord *)agent palette:(TLThemePalette *)palette orchestrator:(TLAgentOrchestrator *)orchestrator {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.settingsSheetWidth - palette.space16 * 2,
    agent ? palette.settingsSheetHeight - palette.space16 * 3 : palette.settingsSheetHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self = [super initWithWindow:window];
  if (self) {
    _editingAgentID = agent.agentID;
    _palette = palette;
    _orchestrator = orchestrator;
    window.title = agent ? @"Agent Settings" : @"Create Agent";
    window.releasedWhenClosed = NO;
    window.delegate = self;
    [self buildInterface];
    if (agent) {
      self.nameField.stringValue = agent.name;
      self.avatarPicker.emoji = agent.avatar;
      self.soulView.string = agent.soul;
    }
    [self applyPalette:palette];
  }
  return self;
}

- (NSTextField *)label:(NSString *)text secondary:(BOOL)secondary {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = secondary ? self.palette.smallFont : self.palette.labelFont;
  label.textColor = secondary ? self.palette.textMuted : self.palette.appText;
  label.alignment = NSTextAlignmentLeft;
  label.identifier = secondary ? @"secondary" : @"label";
  return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
  NSButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bezelStyle = NSBezelStyleRounded;
  button.font = self.palette.labelFont;
  [button.heightAnchor constraintEqualToConstant:self.palette.settingsActionHeight].active = YES;
  return button;
}

- (NSStackView *)verticalStack {
  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = self.palette.space3;
  return stack;
}

- (void)buildInterface {
  TLThemePalette *p = self.palette;
  TLTokenView *root = [[TLTokenView alloc] init];
  self.window.contentView = root;
  NSStackView *body = [self verticalStack];
  body.spacing = p.space10;
  [root addSubview:body];

  NSStackView *header = [self verticalStack];
  NSTextField *title = [self label:self.editingAgentID ? @"Agent Settings" : @"Create Agent" secondary:NO];
  title.font = p.titleFont;
  [header addArrangedSubview:title];
  [header addArrangedSubview:[self label:self.editingAgentID ? @"Make this agent your own. Soul changes apply to new chats." : @"Your own Hermes agent, running locally in a private VM." secondary:YES]];
  [body addArrangedSubview:header];

  NSStackView *identity = [[NSStackView alloc] init];
  identity.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  identity.alignment = NSLayoutAttributeTop;
  identity.spacing = p.space10;
  NSStackView *avatar = [self verticalStack];
  [avatar addArrangedSubview:[self label:@"Avatar" secondary:NO]];
  self.avatarPicker = [[TLEmojiPicker alloc] init];
  self.avatarPicker.palette = p;
  [avatar addArrangedSubview:self.avatarPicker];
  [self.avatarPicker.heightAnchor constraintEqualToConstant:p.fieldHeight].active = YES;
  [identity addArrangedSubview:avatar];
  NSStackView *name = [self verticalStack];
  [name addArrangedSubview:[self label:@"Name" secondary:NO]];
  self.nameField = [[NSTextField alloc] init];
  self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
  self.nameField.placeholderString = @"e.g. Atlas";
  self.nameField.accessibilityLabel = @"Agent name";
  self.nameField.font = p.bodyFont;
  self.nameField.bezelStyle = NSTextFieldRoundedBezel;
  [name addArrangedSubview:self.nameField];
  [self.nameField.widthAnchor constraintEqualToAnchor:name.widthAnchor].active = YES;
  [self.nameField.heightAnchor constraintEqualToConstant:p.fieldHeight].active = YES;
  [identity addArrangedSubview:name];
  [name.widthAnchor constraintEqualToAnchor:identity.widthAnchor
    constant:-(self.avatarPicker.intrinsicContentSize.width + p.space10)].active = YES;
  [body addArrangedSubview:identity];

  NSStackView *soul = [self verticalStack];
  [soul addArrangedSubview:[self label:@"Soul" secondary:NO]];
  [soul addArrangedSubview:[self label:@"Personality, values, and how your agent should work with you." secondary:YES]];
  NSScrollView *soulScroll = [[NSScrollView alloc] init];
  soulScroll.translatesAutoresizingMaskIntoConstraints = NO;
  soulScroll.hasVerticalScroller = YES;
  soulScroll.autohidesScrollers = YES;
  soulScroll.borderType = NSBezelBorder;
  CGFloat soulHeight = p.fieldHeight * (self.editingAgentID ? 5.0 : 2.5);
  self.soulView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, p.settingsSheetWidth - p.space16 * 2 - p.space12 * 2, soulHeight)];
  self.soulView.richText = NO;
  self.soulView.font = p.bodyFont;
  self.soulView.string = @"You are a thoughtful, resourceful assistant. Be clear, curious, and honest. Help me turn ideas into useful work.";
  self.soulView.accessibilityLabel = @"Agent soul";
  self.soulView.textContainerInset = NSMakeSize(p.space5, p.space5);
  self.soulView.verticallyResizable = YES;
  self.soulView.horizontallyResizable = NO;
  self.soulView.autoresizingMask = NSViewWidthSizable;
  self.soulView.textContainer.widthTracksTextView = YES;
  soulScroll.documentView = self.soulView;
  [soul addArrangedSubview:soulScroll];
  [soulScroll.widthAnchor constraintEqualToAnchor:soul.widthAnchor].active = YES;
  [soulScroll.heightAnchor constraintEqualToConstant:soulHeight].active = YES;
  [body addArrangedSubview:soul];

  if (!self.editingAgentID) {
    NSStackView *folders = [self verticalStack];
    [folders addArrangedSubview:[self label:@"Folder Access" secondary:NO]];
    [folders addArrangedSubview:[self label:@"Saved for future VM mounts. Folder access is not enabled yet." secondary:YES]];
    self.folderPicker = [[TLFolderAccessPicker alloc] init];
    self.folderPicker.palette = p;
    [folders addArrangedSubview:self.folderPicker];
    [self.folderPicker.widthAnchor constraintEqualToAnchor:folders.widthAnchor].active = YES;
    [folders setCustomSpacing:p.space5 afterView:folders.arrangedSubviews[1]];
    [body addArrangedSubview:folders];
  }
  for (NSView *section in body.arrangedSubviews) {
    [section.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
  }

  TLTokenView *separator = [[TLTokenView alloc] init];
  separator.translatesAutoresizingMaskIntoConstraints = NO;
  separator.identifier = @"separator";
  [root addSubview:separator];
  NSStackView *actions = [[NSStackView alloc] init];
  actions.translatesAutoresizingMaskIntoConstraints = NO;
  actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  actions.spacing = p.space5;
  self.cancelButton = [self button:@"Cancel" action:@selector(closeSheet:)];
  self.cancelButton.keyEquivalent = @"\e";
  self.createButton = [self button:self.editingAgentID ? @"Save" : @"Create Agent" action:@selector(create:)];
  self.createButton.keyEquivalent = @"\r";
  [actions addArrangedSubview:self.cancelButton];
  [actions addArrangedSubview:self.createButton];
  [root addSubview:actions];

  self.statusLabel = [self label:@"" secondary:YES];
  self.statusLabel.maximumNumberOfLines = 2;
  [root addSubview:self.statusLabel];
  [NSLayoutConstraint activateConstraints:@[
    [body.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:p.space12],
    [body.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-p.space12],
    [body.topAnchor constraintEqualToAnchor:root.topAnchor constant:p.space12],
    [body.bottomAnchor constraintLessThanOrEqualToAnchor:separator.topAnchor constant:-p.space10],
    [separator.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
    [separator.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
    [separator.heightAnchor constraintEqualToConstant:p.borderWidth],
    [separator.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-p.space10],
    [actions.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
    [actions.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-p.space10],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:body.leadingAnchor],
    [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-p.space8],
    [self.statusLabel.centerYAnchor constraintEqualToAnchor:actions.centerYAnchor],
  ]];
}

- (NSArray<NSString *> *)folderPaths { return self.folderPicker.folderPaths; }

- (void)create:(id)sender {
  if (self.createdAgentID) return;
  NSError *error = nil;
  if (self.editingAgentID) {
    TLAgentRecord *agent = [self.orchestrator updateAgentWithID:self.editingAgentID name:self.nameField.stringValue
      avatar:self.avatarPicker.emoji soul:self.soulView.string error:&error];
    if (!agent) { self.statusLabel.stringValue = error.localizedDescription ?: @"Could not save agent settings."; return; }
    self.createdAgentID = agent.agentID;
    [self closeSheet:sender];
    if (self.agentUpdatedHandler) self.agentUpdatedHandler(agent);
    return;
  }
  TLAgentRecord *agent = [self.orchestrator createAgentWithName:self.nameField.stringValue
    avatar:self.avatarPicker.emoji soul:self.soulView.string folderPaths:self.folderPaths error:&error];
  if (!agent) { self.statusLabel.stringValue = error.localizedDescription ?: @"Could not create agent."; return; }
  self.createdAgentID = agent.agentID;
  [self closeSheet:sender];
  if (self.agentCreatedHandler) self.agentCreatedHandler(agent);
}

- (void)closeSheet:(id)sender {
  [self.window.sheetParent endSheet:self.window];
  [self.window orderOut:nil];
}

- (void)showFromWindow:(NSWindow *)parent {
  [parent beginSheet:self.window completionHandler:nil];
  [self.window makeFirstResponder:self.nameField];
}

- (void)applyPaletteToView:(NSView *)view {
  if ([view isKindOfClass:TLFolderAccessPicker.class]) {
    ((TLFolderAccessPicker *)view).palette = self.palette;
    return;
  }
  if ([view isKindOfClass:TLEmojiPicker.class]) {
    ((TLEmojiPicker *)view).palette = self.palette;
    return;
  }
  if ([view isKindOfClass:TLTokenView.class]) ((TLTokenView *)view).fillColor =
    [view.identifier isEqualToString:@"separator"] ? self.palette.controlBorder : self.palette.tabBackground;
  if ([view isKindOfClass:NSTextField.class]) {
    NSTextField *field = (NSTextField *)view;
    field.textColor = [field.identifier isEqualToString:@"secondary"] ? self.palette.textMuted : self.palette.appText;
    field.backgroundColor = self.palette.controlSurface;
  }
  if ([view isKindOfClass:NSTextView.class]) {
    NSTextView *text = (NSTextView *)view;
    text.textColor = self.palette.controlText;
    text.backgroundColor = self.palette.controlSurface;
    text.insertionPointColor = self.palette.controlText;
  }
  if ([view isKindOfClass:NSScrollView.class]) ((NSScrollView *)view).backgroundColor = self.palette.controlSurface;
  if ([view isKindOfClass:TLThemedButton.class]) {
    TLThemedButton *button = (TLThemedButton *)view;
    button.primary = button == self.createButton;
    button.palette = self.palette;
  }
  for (NSView *child in view.subviews) [self applyPaletteToView:child];
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.tabBackground;
  [self applyPaletteToView:self.window.contentView];
}
@end
