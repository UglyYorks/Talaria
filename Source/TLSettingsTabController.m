#import "TLSettingsTabController.h"
#import "AgentOrchestrator.h"
#import "ModelPickerView.h"

@interface TLSettingsTabController ()
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAppSettings *draftSettings;
@property (nonatomic, strong) NSSecureTextField *tokenField;
@property (nonatomic, strong) NSButton *rememberButton;
@property (nonatomic, strong) NSPopUpButton *themePopup;
@property (nonatomic, strong) NSTextField *catalogueStatusLabel;
@property (nonatomic, strong) TLModelPickerView *mainModelPicker;
@property (nonatomic, strong) TLModelPickerView *supportingModelPicker;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, copy) NSArray<NSButton *> *secondaryButtons;
@property (nonatomic) NSUInteger catalogueRequest;
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
    if (_tokenField.stringValue.length > 0) [self loadCatalogue:nil];
  }
  return self;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  [self.mainModelPicker updatePalette:palette];
  [self.supportingModelPicker updatePalette:palette];
  for (NSButton *button in self.secondaryButtons) {
    [self styleButton:button background:palette.secondaryActionSurface foreground:palette.secondaryActionText];
  }
  [self styleButton:self.saveButton background:palette.primaryActionSurface foreground:palette.primaryActionText];
  self.reloadButton.alphaValue = self.reloadButton.enabled ? 1.0 : palette.disabledOpacity;
}

- (void)close {
  [super close];
  self.catalogueRequest += 1;
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

- (void)loadCatalogue:(id)sender {
  if (self.isClosed) return;
  NSUInteger request = ++self.catalogueRequest;
  self.catalogueStatusLabel.stringValue = @"Loading OpenRouter catalogue";
  self.reloadButton.enabled = NO;
  self.reloadButton.alphaValue = self.palette.disabledOpacity;
  [self.mainModelPicker setStatusText:@"Loading catalogue"];
  [self.supportingModelPicker setStatusText:@"Loading catalogue"];
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator fetchModelCatalogueWithToken:self.tokenField.stringValue
    completion:^(NSArray<TLOpenRouterModel *> *models, NSError *error) {
      TLSettingsTabController *controller = weakSelf;
      if (!controller || controller.isClosed || controller.catalogueRequest != request) return;
      controller.reloadButton.enabled = YES;
      controller.reloadButton.alphaValue = 1.0;
      if (error) {
        controller.catalogueStatusLabel.stringValue = error.localizedDescription ?: @"Could not load OpenRouter catalogue.";
        [controller.mainModelPicker setStatusText:@"Catalogue unavailable"];
        [controller.supportingModelPicker setStatusText:@"Catalogue unavailable"];
        return;
      }
      [controller.mainModelPicker setModels:models];
      [controller.supportingModelPicker setModels:models];
      NSString *status = [NSString stringWithFormat:@"%lu OpenRouter text models loaded", (unsigned long)models.count];
      controller.catalogueStatusLabel.stringValue = status;
      [controller.mainModelPicker setStatusText:status];
      [controller.supportingModelPicker setStatusText:status];
    }];
}

- (void)save:(id)sender {
  if (self.isClosed) return;
  self.draftSettings.openRouterToken = self.tokenField.stringValue;
  self.draftSettings.rememberOpenRouterToken = self.rememberButton.state == NSControlStateValueOn;
  self.draftSettings.selectedModel = self.mainModelPicker.selectedModelID;
  self.draftSettings.supportingModel = self.supportingModelPicker.selectedModelID;
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
  NSTextField *catalogueStatusLabel = [self labelWithString:@"OpenRouter catalogue" font:palette.smallFont colorToken:@"textMuted"];
  NSSecureTextField *tokenField = [[NSSecureTextField alloc] init];
  NSButton *rememberButton = [NSButton checkboxWithTitle:@"Remember token" target:nil action:nil];
  NSPopUpButton *themePopup = [[NSPopUpButton alloc] init];
  NSButton *closeButton = [self buttonWithTitle:@"Close" action:@selector(requestClose:)];
  NSButton *saveButton = [self buttonWithTitle:@"Save" action:@selector(save:)];
  NSButton *reloadButton = [self buttonWithTitle:@"Refresh catalogue" action:@selector(loadCatalogue:)];
  NSButton *onboardingButton = [self buttonWithTitle:@"Set up a fresh Hermes VM" action:@selector(requestOnboarding:)];
  TLModelPickerView *mainModelPicker = [[TLModelPickerView alloc] initWithTitle:@"Main model"
                                                                        palette:palette
                                                                selectedModelID:draftSettings.selectedModel];
  TLModelPickerView *supportingModelPicker = [[TLModelPickerView alloc] initWithTitle:@"Supporting small model"
                                                                              palette:palette
                                                                      selectedModelID:draftSettings.supportingModel];

  tokenField.translatesAutoresizingMaskIntoConstraints = NO;
  rememberButton.translatesAutoresizingMaskIntoConstraints = NO;
  themePopup.translatesAutoresizingMaskIntoConstraints = NO;
  catalogueStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
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
    catalogueStatusLabel,
    tokenLabel,
    tokenField,
    rememberButton,
    themeLabel,
    themePopup,
    reloadButton,
    onboardingButton,
    mainModelPicker,
    supportingModelPicker,
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

    [reloadButton.trailingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
    [reloadButton.topAnchor constraintEqualToAnchor:rememberButton.bottomAnchor constant:palette.space8],
    [reloadButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth * 2.0],
    [reloadButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],

    [onboardingButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [onboardingButton.centerYAnchor constraintEqualToAnchor:reloadButton.centerYAnchor],
    [onboardingButton.widthAnchor constraintGreaterThanOrEqualToConstant:palette.controlMinWidth * 2.0],
    [onboardingButton.heightAnchor constraintEqualToConstant:palette.settingsActionHeight],

    [catalogueStatusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:onboardingButton.trailingAnchor constant:palette.space5],
    [catalogueStatusLabel.trailingAnchor constraintEqualToAnchor:reloadButton.leadingAnchor constant:-palette.space5],
    [catalogueStatusLabel.centerYAnchor constraintEqualToAnchor:reloadButton.centerYAnchor],

    [mainModelPicker.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
    [mainModelPicker.topAnchor constraintEqualToAnchor:reloadButton.bottomAnchor constant:palette.space6],
    [mainModelPicker.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-palette.space12],
    [supportingModelPicker.leadingAnchor constraintEqualToAnchor:mainModelPicker.trailingAnchor constant:palette.space6],
    [supportingModelPicker.trailingAnchor constraintEqualToAnchor:closeButton.trailingAnchor],
    [supportingModelPicker.topAnchor constraintEqualToAnchor:mainModelPicker.topAnchor],
    [supportingModelPicker.bottomAnchor constraintEqualToAnchor:mainModelPicker.bottomAnchor],
    [supportingModelPicker.widthAnchor constraintEqualToAnchor:mainModelPicker.widthAnchor],
  ]];

  self.view = content;
  self.tokenField = tokenField;
  self.rememberButton = rememberButton;
  self.themePopup = themePopup;
  self.catalogueStatusLabel = catalogueStatusLabel;
  self.mainModelPicker = mainModelPicker;
  self.supportingModelPicker = supportingModelPicker;
  self.saveButton = saveButton;
  self.reloadButton = reloadButton;
  self.secondaryButtons = @[closeButton, reloadButton, onboardingButton];
  [self applyPalette:palette];
  return content;
}


- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
  NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bordered = NO;
  button.wantsLayer = YES;
  button.font = self.palette.labelFont;
  button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
  return button;
}

- (void)styleButton:(NSButton *)button background:(NSColor *)background foreground:(NSColor *)foreground {
  button.font = self.palette.labelFont;
  button.contentTintColor = foreground;
  button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
    NSForegroundColorAttributeName: foreground,
    NSFontAttributeName: self.palette.labelFont,
  }];
  button.layer.backgroundColor = TLCGColor(background);
  button.layer.cornerRadius = self.palette.radiusMedium;
}
@end
