#import "TLProviderSetupWindowController.h"
#import "design_system/ModelPickerView.h"
#import "design_system/TLThemedButton.h"

@interface TLProviderSetupWindowController () <NSTextFieldDelegate>
@property TLAgentRecord *agent;
@property TLAgentOrchestrator *orchestrator;
@property TLThemePalette *palette;
@property NSStackView *body;
@property NSTextField *stageLabel;
@property NSTextField *statusLabel;
@property NSPopUpButton *providerPicker;
@property TLModelPickerView *modelPicker;
@property NSTextField *manualModel;
@property NSMutableDictionary<NSString *, NSTextField *> *fields;
@property NSArray<NSDictionary *> *providers;
@property NSDictionary *provider;
@property TLThemedButton *nextButton;
@property TLThemedButton *backButton;
@property TLThemedButton *cancelButton;
@property TLThemedButton *loginButton;
@property NSSecureTextField *loginInput;
@property NSTextView *loginOutput;
@property NSString *loginSession;
@property NSString *loginURL;
@property NSTimer *pollTimer;
@property NSInteger stage;
@property NSUInteger generation;
@property BOOL busy;
@property BOOL dismissed;
@property BOOL needsInstall;
@property NSString *confirmedSelection;
@property NSDictionary *customValues;
@end

@implementation TLProviderSetupWindowController
- (instancetype)initWithAgent:(TLAgentRecord *)agent orchestrator:(TLAgentOrchestrator *)orchestrator palette:(TLThemePalette *)palette {
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, palette.settingsSheetWidth, palette.settingsSheetHeight)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self = [super initWithWindow:panel];
  if (!self) return nil;
  _agent = agent; _orchestrator = orchestrator; _palette = palette;
  panel.title = [NSString stringWithFormat:@"Set up %@", agent.name];
  panel.releasedWhenClosed = NO;
  TLTokenView *root = [[TLTokenView alloc] init];
  panel.contentView = root;
  self.stageLabel = [self label:@"1  Provider   →   2  Credentials   →   3  Model"];
  self.stageLabel.font = palette.labelFont;
  self.body = [[NSStackView alloc] init];
  self.body.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.body.alignment = NSLayoutAttributeLeading;
  self.body.spacing = palette.space5;
  NSScrollView *bodyScroll = [[NSScrollView alloc] init];
  bodyScroll.hasVerticalScroller = YES; bodyScroll.autohidesScrollers = YES; bodyScroll.drawsBackground = NO;
  TLFlippedView *document = [[TLFlippedView alloc] init];
  document.translatesAutoresizingMaskIntoConstraints = NO;
  bodyScroll.documentView = document; [document addSubview:self.body];
  self.body.translatesAutoresizingMaskIntoConstraints = NO;
  [document.widthAnchor constraintEqualToAnchor:bodyScroll.contentView.widthAnchor].active = YES;
  [NSLayoutConstraint activateConstraints:@[
    [self.body.topAnchor constraintEqualToAnchor:document.topAnchor],
    [self.body.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
    [self.body.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
    [self.body.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
  ]];
  self.statusLabel = [self label:@""];
  self.nextButton = [self button:@"Continue" action:@selector(next:)];
  self.nextButton.primary = YES;
  self.nextButton.keyEquivalent = @"\r";
  self.backButton = [self button:@"Back" action:@selector(back:)];
  self.cancelButton = [self button:@"Close" action:@selector(cancel:)];
  self.cancelButton.keyEquivalent = @"\e";
  NSStackView *actions = [NSStackView stackViewWithViews:@[self.cancelButton, self.backButton, self.nextButton]];
  actions.spacing = palette.space5;
  for (NSView *view in @[self.stageLabel, bodyScroll, self.statusLabel, actions]) {
    view.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:view];
  }
  CGFloat pad = palette.space12;
  [NSLayoutConstraint activateConstraints:@[
    [self.stageLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:pad],
    [self.stageLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:pad],
    [self.stageLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-pad],
    [bodyScroll.topAnchor constraintEqualToAnchor:self.stageLabel.bottomAnchor constant:palette.space8],
    [bodyScroll.leadingAnchor constraintEqualToAnchor:self.stageLabel.leadingAnchor],
    [bodyScroll.trailingAnchor constraintEqualToAnchor:self.stageLabel.trailingAnchor],
    [bodyScroll.bottomAnchor constraintEqualToAnchor:self.statusLabel.topAnchor constant:-palette.space8],
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:bodyScroll.leadingAnchor],
    [self.statusLabel.trailingAnchor constraintEqualToAnchor:bodyScroll.trailingAnchor],
    [self.statusLabel.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-palette.space5],
    [actions.trailingAnchor constraintEqualToAnchor:bodyScroll.trailingAnchor],
    [actions.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-pad],
  ]];
  [self applyPalette:palette];
  return self;
}
- (NSTextField *)label:(NSString *)text {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.font = self.palette.bodyFont; label.textColor = self.palette.appText;
  return label;
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  button.palette = self.palette; return button;
}
- (void)add:(NSView *)view {
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [self.body addArrangedSubview:view];
  [view.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;
}
- (void)clearBody {
  for (NSView *view in self.body.arrangedSubviews.copy) { [self.body removeArrangedSubview:view]; [view removeFromSuperview]; }
  self.statusLabel.stringValue = @"";
  self.nextButton.title = self.stage == 2 ? @"Use model" : @"Continue";
  self.backButton.hidden = self.stage == 0;
  self.stageLabel.stringValue = @[@"1  Provider   →   2  Credentials   →   3  Model",
    @"1  Provider   →   2  Credentials (current)   →   3  Model",
    @"1  Provider   →   2  Credentials   →   3  Model (current)"][self.stage];
}
- (void)setWorking:(BOOL)working {
  self.busy = working; self.cancelButton.enabled = !working; self.nextButton.enabled = !working; self.backButton.enabled = !working;
  self.providerPicker.enabled = !working; self.loginButton.enabled = !working;
  self.modelPicker.userInteractionEnabled = !working;
  for (NSTextField *field in self.fields.allValues) field.enabled = !working;
}
- (void)request:(NSDictionary *)params completion:(void (^)(NSDictionary *, NSError *))completion {
  NSUInteger generation = self.generation;
  __weak typeof(self) weakSelf = self;
  [self.orchestrator hermesProvidersForAgentID:self.agent.agentID parameters:params completion:^(NSDictionary *result, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.dismissed || generation != owner.generation) return;
      completion(result, error);
    });
  }];
}
- (void)presentForWindow:(NSWindow *)window {
  [window beginSheet:self.window completionHandler:nil];
  if ([self.orchestrator hasHermesInstallationForAgent:self.agent]) { [self showProviders]; return; }
  [self prepareRuntime];
}
- (void)prepareRuntime {
  self.needsInstall = YES;
  [self setWorking:YES];
  self.statusLabel.stringValue = @"Preparing your private Hermes VM…";
  __weak typeof(self) weakSelf = self;
  [self.orchestrator installHermesForAgentWithID:self.agent.agentID progress:^(NSString *text) {
    if (!weakSelf.dismissed) weakSelf.statusLabel.stringValue = text;
  } completion:^(TLAgentRecord *agent, NSError *error) {
    typeof(self) owner = weakSelf;
    if (!owner || owner.dismissed) return;
    [owner setWorking:NO];
    if (error) { owner.statusLabel.stringValue = error.localizedDescription; owner.nextButton.title = @"Retry setup"; return; }
    owner.needsInstall = NO;
    [owner showProviders];
  }];
}
- (void)showProviders {
  self.stage = 0; self.providers = @[]; [self clearBody];
  [self add:[self label:@"Choose your model provider"]];
  self.providerPicker = [[NSPopUpButton alloc] init];
  self.providerPicker.accessibilityLabel = @"Model provider";
  [self add:self.providerPicker];
  [self add:[self label:@"Use an API key, sign in to a supported account, or connect a local endpoint. Providers are supplied by your installed Hermes."]];
  [self setWorking:YES]; self.statusLabel.stringValue = @"Loading providers…";
  [self request:@{@"action": @"list"} completion:^(NSDictionary *result, NSError *error) {
    [self setWorking:NO];
    if (error) { self.statusLabel.stringValue = error.localizedDescription; self.nextButton.title = @"Retry"; return; }
    self.providers = result[@"providers"] ?: @[];
    for (NSDictionary *provider in self.providers) [self.providerPicker addItemWithTitle:provider[@"name"] ?: provider[@"slug"]];
    self.nextButton.enabled = self.providers.count > 0;
    self.statusLabel.stringValue = self.providers.count ? @"" : @"Hermes returned no providers. Update Hermes and retry.";
  }];
}
- (void)showCredentials {
  self.stage = 1; [self clearBody];
  self.fields = [NSMutableDictionary dictionary];
  self.customValues = nil;
  [self add:[self label:[NSString stringWithFormat:@"Connect %@", self.provider[@"name"] ?: self.provider[@"slug"]]]];
  [self add:[self label:self.provider[@"description"] ?: @"Credentials are stored by Hermes inside this agent’s VM."]];
  if ([self.provider[@"authenticated"] boolValue]) [self add:[self label:@"Already configured in Hermes. Continue to models, or update credentials below."]];
  if ([self.provider[@"keyless"] boolValue] || [@[@"local", @"virtual"] containsObject:self.provider[@"auth_type"]]) {
    [self add:[self label:@"This provider does not require an API key. Its endpoint must be reachable from the agent VM."]];
    if ([self.provider[@"auth_type"] isEqual:@"virtual"]) {
      self.loginButton = [self button:@"Configure in Hermes…" action:@selector(login:)];
      [self.body addArrangedSubview:self.loginButton];
    }
  } else {
    NSMutableArray *keys = [NSMutableArray arrayWithArray:self.provider[@"custom_fields"] ?: self.provider[@"api_key_env_vars"] ?: @[]];
    NSString *base = self.provider[@"base_url_env_var"];
    if (base.length && ![keys containsObject:base]) [keys addObject:base];
    // Alternative credential variables are optional; Hermes decides which apply.
    for (NSString *key in keys) {
      [self add:[self label:key]];
      NSDictionary *info = self.provider[@"credential_fields"][key];
      BOOL plain = (info && ![info[@"is_password"] boolValue]) || [key isEqual:base] || [@[@"name", @"base_url"] containsObject:key];
      NSTextField *field = plain ? [[NSTextField alloc] init] : [[NSSecureTextField alloc] init];
      field.accessibilityLabel = key;
      field.placeholderString = [key isEqual:base] || [key isEqual:@"base_url"] ? @"Endpoint URL reachable from the agent VM" : @"Leave empty to keep the saved value";
      self.fields[key] = field; [self add:field];
    }
    if (![self.provider[@"custom_fields"] count]) {
      self.loginButton = [self button:@"Sign in with Hermes…" action:@selector(login:)];
      [self.body addArrangedSubview:self.loginButton];
    }
    if (![self.provider[@"auth_type"] isEqual:@"api_key"] || !keys.count) {
      [self add:[self label:@"Use Hermes sign-in for account or external credentials. Follow the provider’s prompts here."]];
    }
  }
  [self applyPalette:self.palette];
}
- (void)next:(id)sender {
  if (self.busy) return;
  if (self.needsInstall) { [self prepareRuntime]; return; }
  if (self.stage == 0) {
    NSInteger index = self.providerPicker.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.providers.count) { [self showProviders]; return; }
    self.provider = self.providers[index]; [self showCredentials]; return;
  }
  if (self.stage == 1) {
    if (self.loginSession.length) { self.statusLabel.stringValue = @"Finish sign-in before continuing."; return; }
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in self.fields) if (self.fields[key].stringValue.length) values[key] = self.fields[key].stringValue;
    if ([self.provider[@"custom_fields"] count]) {
      if (![values[@"name"] length] || ![values[@"base_url"] length]) { self.statusLabel.stringValue = @"Enter an endpoint name and URL."; return; }
      self.customValues = values;
      for (NSTextField *field in self.fields.allValues) field.stringValue = @"";
      [self showModels]; return;
    }
    if (!values.count) { [self showModels]; return; }
    [self setWorking:YES]; self.statusLabel.stringValue = @"Saving credentials in Hermes…";
    [self request:@{@"action": @"configure", @"slug": self.provider[@"slug"], @"values": values} completion:^(NSDictionary *result, NSError *error) {
      [self setWorking:NO];
      if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
      for (NSTextField *field in self.fields.allValues) field.stringValue = @"";
      [self showModels];
    }]; return;
  }
  NSString *raw = [self.manualModel.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *selection = raw.length ? [NSString stringWithFormat:@"%@::%@", self.provider[@"slug"], raw] : self.modelPicker.selectedModelID;
  if (!selection.length) { self.statusLabel.stringValue = @"Choose a model or enter its ID."; return; }
  [self setWorking:YES]; self.cancelButton.enabled = NO;
  [self request:@{@"action": @"select", @"selection": selection, @"confirmed": @([self.confirmedSelection isEqual:selection]), @"custom": self.customValues ?: @{}} completion:^(NSDictionary *result, NSError *error) {
    [self setWorking:NO]; self.cancelButton.enabled = YES;
    if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
    if ([result[@"confirm_required"] boolValue]) {
      self.statusLabel.stringValue = result[@"confirm_message"] ?: @"Hermes requires confirmation for this model.";
      self.confirmedSelection = selection; self.nextButton.title = @"Confirm model"; return;
    }
    [self cancel:nil];
    if (self.completionHandler) self.completionHandler(result[@"selection"] ?: selection);
  }];
}
- (void)controlTextDidChange:(NSNotification *)notification {
  self.confirmedSelection = nil; self.nextButton.title = @"Use model";
}
- (void)showModels {
  self.stage = 2; self.confirmedSelection = nil; [self clearBody];
  self.modelPicker = [[TLModelPickerView alloc] initWithTitle:self.provider[@"name"] ?: @"Models" palette:self.palette selectedModelID:@""];
  [self add:self.modelPicker];
  [self.modelPicker.heightAnchor constraintEqualToConstant:self.palette.settingsSheetHeight * 0.48].active = YES;
  [self add:[self label:@"Or enter a model ID (for custom or local models)"]];
  self.manualModel = [[NSTextField alloc] init]; self.manualModel.accessibilityLabel = @"Custom model ID"; self.manualModel.delegate = self;
  [self add:self.manualModel];
  __weak typeof(self) weakSelf = self;
  self.modelPicker.selectionChangeHandler = ^(NSString *model) { weakSelf.confirmedSelection = nil; weakSelf.nextButton.title = @"Use model"; weakSelf.manualModel.stringValue = @""; };
  if (self.customValues) {
    [self.modelPicker setStatusText:@"Enter the model ID served by your endpoint."];
    [self applyPalette:self.palette]; return;
  }
  [self setWorking:YES]; self.statusLabel.stringValue = @"Loading models from Hermes…";
  [self request:@{@"action": @"models", @"slug": self.provider[@"slug"]} completion:^(NSDictionary *result, NSError *error) {
    [self setWorking:NO];
    if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    NSArray *models = TLParseHermesModelOptions(data, nil);
    [self.modelPicker setModels:models ?: @[]];
    [self.modelPicker setStatusText:models.count ? @"" : @"No listed models. Enter an ID or go Back to check credentials."];
    self.statusLabel.stringValue = @"";
  }];
  [self applyPalette:self.palette];
}
- (void)login:(id)sender {
  if (self.loginSession.length) return;
  [self setWorking:YES]; self.statusLabel.stringValue = @"Starting Hermes sign-in…";
  [self request:@{@"action": @"login.start", @"slug": self.provider[@"slug"]} completion:^(NSDictionary *result, NSError *error) {
    [self setWorking:NO];
    if (error) { self.statusLabel.stringValue = error.localizedDescription; return; }
    self.loginSession = result[@"session_id"];
    self.loginURL = result[@"verification_url"];
    for (NSView *view in self.body.arrangedSubviews.copy) { [self.body removeArrangedSubview:view]; [view removeFromSuperview]; }
    self.fields = [NSMutableDictionary dictionary];
    if (self.loginURL.length) {
      [self add:[self label:[NSString stringWithFormat:@"Open the sign-in page and enter code: %@", result[@"user_code"] ?: @""]]];
      [self.body addArrangedSubview:[self button:@"Open sign-in page" action:@selector(openLogin:)]];
    } else {
      NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.hasVerticalScroller = YES;
      self.loginOutput = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, self.palette.settingsSheetWidth - self.palette.space12 * 2, 260)];
      self.loginOutput.editable = NO; self.loginOutput.richText = NO; self.loginOutput.automaticLinkDetectionEnabled = YES;
      scroll.documentView = self.loginOutput; [self add:scroll];
      [scroll.heightAnchor constraintEqualToConstant:self.palette.settingsSheetHeight * 0.4].active = YES;
      self.loginInput = [[NSSecureTextField alloc] init]; self.loginInput.placeholderString = @"Reply to the Hermes prompt";
      self.loginInput.accessibilityLabel = @"Hermes sign-in response"; [self add:self.loginInput];
      [self.body addArrangedSubview:[self button:@"Send response" action:@selector(sendLoginInput:)]];
    }
    self.nextButton.enabled = NO;
    self.statusLabel.stringValue = @"Waiting for sign-in…";
    [self applyPalette:self.palette];
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:MAX(1, [result[@"poll_interval"] doubleValue]) repeats:YES block:^(NSTimer *timer) { [weakSelf pollLogin]; }];
  }];
}
- (void)openLogin:(id)sender {
  NSURL *url = [NSURL URLWithString:self.loginURL];
  if ([url.scheme isEqual:@"https"]) [NSWorkspace.sharedWorkspace openURL:url];
}
- (void)sendLoginInput:(id)sender {
  NSString *input = self.loginInput.stringValue; self.loginInput.stringValue = @"";
  [self request:@{@"action": @"login.input", @"slug": self.provider[@"slug"], @"session_id": self.loginSession, @"input": input}
    completion:^(NSDictionary *result, NSError *error) { [self consumeLogin:result error:error]; }];
}
- (void)pollLogin {
  if (!self.loginSession.length || self.busy) return;
  self.busy = YES;
  [self request:@{@"action": @"login.poll", @"slug": self.provider[@"slug"], @"session_id": self.loginSession}
    completion:^(NSDictionary *result, NSError *error) { self.busy = NO; [self consumeLogin:result error:error]; }];
}
- (void)consumeLogin:(NSDictionary *)result error:(NSError *)error {
  if ([result[@"text"] length]) {
    NSString *text = result[@"text"];
    NSRegularExpression *ansi = [NSRegularExpression regularExpressionWithPattern:@"\\x1b\\[[0-?]*[ -/]*[@-~]" options:0 error:nil];
    text = [ansi stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    [self.loginOutput.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName:self.palette.controlText, NSFontAttributeName:self.palette.smallFont}]];
    [self.loginOutput scrollRangeToVisible:NSMakeRange(self.loginOutput.string.length, 0)];
  }
  NSString *status = result[@"status"];
  if (error || [@[@"error", @"expired", @"approved"] containsObject:status]) {
    [self stopLogin]; [self setWorking:NO];
    if ([status isEqual:@"approved"] && !error) { [self showModels]; return; }
    [self showCredentials]; self.statusLabel.stringValue = error.localizedDescription ?: @"Sign-in failed or expired. Try again.";
  }
}
- (void)stopLogin {
  [self.pollTimer invalidate]; self.pollTimer = nil;
  if (self.loginSession.length) {
    [self.orchestrator hermesProvidersForAgentID:self.agent.agentID parameters:@{@"action": @"login.cancel", @"slug": self.provider[@"slug"], @"session_id":self.loginSession} completion:^(NSDictionary *result, NSError *error) {}];
  }
  self.loginSession = nil; self.loginInput.stringValue = @""; self.loginOutput.string = @"";
}
- (void)back:(id)sender {
  ++self.generation; [self stopLogin]; [self setWorking:NO];
  if (self.stage == 2) [self showCredentials]; else [self showProviders];
}
- (void)cancel:(id)sender {
  ++self.generation; [self stopLogin]; self.dismissed = YES; self.customValues = nil;
  for (NSTextField *field in self.fields.allValues) field.stringValue = @"";
  [self.window.sheetParent endSheet:self.window]; [self.window orderOut:nil];
}
- (void)themeView:(NSView *)view {
  if ([view isKindOfClass:TLModelPickerView.class]) { [(TLModelPickerView *)view updatePalette:self.palette]; return; }
  if ([view isKindOfClass:TLTokenView.class]) ((TLTokenView *)view).fillColor = self.palette.tabBackground;
  if ([view isKindOfClass:TLThemedButton.class]) ((TLThemedButton *)view).palette = self.palette;
  if ([view isKindOfClass:NSTextField.class]) { ((NSTextField *)view).textColor = self.palette.controlText; ((NSTextField *)view).backgroundColor = self.palette.controlSurface; }
  if ([view isKindOfClass:NSTextView.class]) { ((NSTextView *)view).textColor = self.palette.controlText; ((NSTextView *)view).backgroundColor = self.palette.controlSurface; }
  for (NSView *child in view.subviews) [self themeView:child];
}
- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette; self.window.backgroundColor = palette.tabBackground;
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  [self themeView:self.window.contentView];
}
@end
