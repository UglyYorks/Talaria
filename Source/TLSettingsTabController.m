#import "TLSettingsTabController.h"
#import "AgentOrchestrator.h"
#import "UIComponents.h"
#import "design_system/TLThemedButton.h"

@interface TLSettingsTabController ()
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAppSettings *draftSettings;
@property (nonatomic, strong) NSSecureTextField *tokenField;
@property (nonatomic, strong) NSButton *rememberButton;
@property (nonatomic, strong) NSPopUpButton *themePopup;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, copy) NSArray<NSButton *> *secondaryButtons;
@end

@implementation TLSettingsTabController
- (instancetype)initWithSettings:(TLAppSettings *)settings
                       database:(TLDatabase *)database
                   orchestrator:(TLAgentOrchestrator *)orchestrator
                        palette:(TLThemePalette *)palette {
  self = [super initWithPalette:palette];
  if (self) {
    _database = database;
    _agentOrchestrator = orchestrator;
    _draftSettings = [settings copy];
    [self buildSettingsTabContent];
  }
  return self;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  for (NSButton *button in self.secondaryButtons) {
    [self styleButton:button background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  }
  [self styleButton:self.saveButton background:palette.primaryActionSurface foreground:palette.primaryActionText];
}

- (void)close {
  [super close];
  self.closeHandler = nil;
  self.onboardingHandler = nil;
  self.settingsSavedHandler = nil;
  self.errorHandler = nil;
}

- (void)requestClose:(id)sender {
  if (self.closeHandler) self.closeHandler();
}

- (void)requestOnboarding:(id)sender {
  if (self.onboardingHandler) self.onboardingHandler();
}

- (void)save:(id)sender {
  if (self.isClosed) return;
  self.draftSettings.openRouterToken = self.tokenField.stringValue;
  self.draftSettings.rememberOpenRouterToken = self.rememberButton.state == NSControlStateValueOn;
  TLAppSettings *latest = [self.database appSettings:nil];
  if (latest) {
    self.draftSettings.selectedModel = latest.selectedModel;
    self.draftSettings.supportingModel = latest.supportingModel;
  }
  self.draftSettings.theme = self.themePopup.indexOfSelectedItem;
  NSError *error = nil;
  TLAppSettings *saved = [self.database saveAppSettings:self.draftSettings error:&error];
  if (!saved) {
    if (self.errorHandler) self.errorHandler(error.localizedDescription ?: @"Could not save settings.");
    return;
  }
  if (self.settingsSavedHandler) self.settingsSavedHandler(saved);
}

- (NSView *)buildSettingsTabContent {
  TLAppSettings *draftSettings = self.draftSettings;
  TLThemePalette *palette = self.palette;

  TLTokenView *content = [[TLTokenView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:content keyPath:@"fillColor" token:@"tabBackground"];

  NSTextField *titleLabel = [self labelWithString:@"Settings" font:palette.titleFont colorToken:@"appText"];
  NSTextField *subtitleLabel = [self labelWithString:@"Configure your Hermes VM, model provider, and appearance."
                                                font:palette.bodyFont colorToken:@"textMuted"];
  NSTextField *providerSectionLabel = [self labelWithString:@"AI provider" font:palette.labelFont colorToken:@"appText"];
  NSTextField *appearanceSectionLabel = [self labelWithString:@"Appearance" font:palette.labelFont colorToken:@"appText"];
  NSSecureTextField *tokenField = [[NSSecureTextField alloc] init];
  NSButton *rememberButton = [NSButton checkboxWithTitle:@"Remember token" target:nil action:nil];
  NSPopUpButton *themePopup = [[NSPopUpButton alloc] init];
  NSButton *closeButton = [self buttonWithTitle:@"Close" action:@selector(requestClose:)];
  NSButton *saveButton = [self buttonWithTitle:@"Save" action:@selector(save:)];
  NSButton *onboardingButton = [self buttonWithTitle:@"Set up a fresh Hermes VM" action:@selector(requestOnboarding:)];
  tokenField.translatesAutoresizingMaskIntoConstraints = NO;
  rememberButton.translatesAutoresizingMaskIntoConstraints = NO;
  themePopup.translatesAutoresizingMaskIntoConstraints = NO;
  tokenField.stringValue = draftSettings.openRouterToken;
  tokenField.placeholderString = @"sk-or-v1-...";
  tokenField.font = palette.bodyFont;
  [self bindColorForObject:tokenField keyPath:@"textColor" token:@"controlText"];
  [self bindColorForObject:tokenField keyPath:@"backgroundColor" token:@"controlSurface"];
  rememberButton.state = draftSettings.rememberOpenRouterToken ? NSControlStateValueOn : NSControlStateValueOff;
  rememberButton.font = palette.bodyFont;
  [self bindColorForObject:rememberButton keyPath:@"contentTintColor" token:@"controlText"];
  [themePopup addItemsWithTitles:@[@"System", @"Light", @"Dark"]];
  [themePopup selectItemAtIndex:draftSettings.theme];
  themePopup.font = palette.bodyFont;

  NSTextField *tokenLabel = [self labelWithString:@"OpenRouter token" font:palette.labelFont colorToken:@"labelText"];
  NSTextField *themeLabel = [self labelWithString:@"Theme" font:palette.labelFont colorToken:@"labelText"];

  for (NSView *view in @[
    titleLabel,
    subtitleLabel,
    providerSectionLabel,
    appearanceSectionLabel,
    tokenLabel,
    tokenField,
    rememberButton,
    themeLabel,
    themePopup,
    onboardingButton,
    closeButton,
    saveButton,
  ]) {
    [content addSubview:view];
  }

  [NSLayoutConstraint activateConstraints:@[
    [titleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:palette.space12],
    [titleLabel.topAnchor constraintEqualToAnchor:content.topAnchor constant:palette.space11],
    [closeButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-palette.space12],
    [closeButton.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
    [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth],
    [closeButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
    [saveButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-palette.space5],
    [saveButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
    [saveButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth],
    [saveButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],
    [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:palette.space2],
    [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:saveButton.leadingAnchor constant:-palette.space8],
    [providerSectionLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [providerSectionLabel.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:palette.space8],
    [appearanceSectionLabel.leadingAnchor constraintEqualToAnchor:content.centerXAnchor constant:palette.space6],
    [appearanceSectionLabel.centerYAnchor constraintEqualToAnchor:providerSectionLabel.centerYAnchor],

    [tokenLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [tokenLabel.trailingAnchor constraintEqualToAnchor:content.centerXAnchor constant:-palette.space6],
    [tokenLabel.topAnchor constraintEqualToAnchor:providerSectionLabel.bottomAnchor constant:palette.space4],
    [tokenField.leadingAnchor constraintEqualToAnchor:tokenLabel.leadingAnchor],
    [tokenField.trailingAnchor constraintEqualToAnchor:tokenLabel.trailingAnchor],
    [tokenField.topAnchor constraintEqualToAnchor:tokenLabel.bottomAnchor constant:palette.space4],
    [tokenField.heightAnchor constraintEqualToConstant:palette.fieldHeight],

    [rememberButton.leadingAnchor constraintEqualToAnchor:tokenLabel.leadingAnchor],
    [rememberButton.topAnchor constraintEqualToAnchor:tokenField.bottomAnchor constant:palette.space5],

    [themeLabel.leadingAnchor constraintEqualToAnchor:content.centerXAnchor constant:palette.space6],
    [themeLabel.trailingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
    [themeLabel.topAnchor constraintEqualToAnchor:appearanceSectionLabel.bottomAnchor constant:palette.space4],
    [themePopup.leadingAnchor constraintEqualToAnchor:themeLabel.leadingAnchor],
    [themePopup.trailingAnchor constraintEqualToAnchor:themeLabel.trailingAnchor],
    [themePopup.topAnchor constraintEqualToAnchor:themeLabel.bottomAnchor constant:palette.space4],
    [themePopup.heightAnchor constraintEqualToConstant:palette.fieldHeight],

    [onboardingButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [onboardingButton.topAnchor constraintEqualToAnchor:rememberButton.bottomAnchor constant:palette.space8],
    [onboardingButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth * 2.0],
    [onboardingButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],

  ]];

  self.view = content;
  self.tokenField = tokenField;
  self.rememberButton = rememberButton;
  self.themePopup = themePopup;
  self.saveButton = saveButton;
  self.secondaryButtons = @[closeButton, onboardingButton];
  [self applyPalette:palette];
  return content;
}


- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [[TLThemedButton alloc] init];
  button.title = title;
  button.target = self;
  button.action = action;
  button.palette = self.palette;
  button.translatesAutoresizingMaskIntoConstraints = NO;
  return button;
}

- (void)styleButton:(NSButton *)button background:(NSColor *)background foreground:(NSColor *)foreground {
  TLThemedButton *themed = (TLThemedButton *)button;
  themed.palette = self.palette;
  themed.primary = button == self.saveButton;
}
@end
