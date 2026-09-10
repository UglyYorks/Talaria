#import "TLSettingsTabController.h"
#import "TLProviderSetupWindowController.h"
#import "TLBrowserSettingsController.h"
#import "TLApplicationSettingsController.h"
#import "AgentOrchestrator.h"
#import "WebKitBrowserController.h"
#import "TLModelSelectionWindowController.h"
#import "UIComponents.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLSettingsWorkspaceView.h"
#import "design_system/TLWrappingActionView.h"
#import "design_system/TLSettingsRowView.h"
#import "design_system/TLSkillsPicker.h"

@interface TLSettingsTabController () <NSTextFieldDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAppSettings *draftSettings;
@property (nonatomic, strong) TLSettingsWorkspaceView *workspace;
@property (nonatomic, strong) TLThemedButton *saveButton;
@property (nonatomic, strong) NSTextField *footerLabel;
@property (nonatomic, strong) NSMutableArray<TLThemedButton *> *buttons;
@property (nonatomic, strong) NSMutableArray<TLSidebarNavigationButton *> *navigation;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *pages;
@property (nonatomic, copy) NSString *selectedPage;
@property (nonatomic) NSInteger sectionIndex;
@property (nonatomic) NSInteger agentPageIndex;
@property (nonatomic) NSInteger browserPageIndex;
@property TLApplicationSettingsController *applicationSettingsController;
@property (nonatomic, strong) NSMutableArray<TLThemedButton *> *modelButtons;
@property (nonatomic) BOOL largeModelChanged;
@property (nonatomic) BOOL smallModelChanged;
@property (nonatomic, strong) TLModelSelectionWindowController *modelSelection;
@property (nonatomic, strong) TLProviderSetupWindowController *providerSetup;
@property (nonatomic, strong) NSStackView *credentialRows;
@property (nonatomic, strong) NSSearchField *credentialSearch;
@property (nonatomic, strong) NSPopUpButton *credentialCategory;
@property (nonatomic, strong) NSTextField *credentialStatus;
@property (nonatomic, strong) TLThemedButton *refreshCredentialsButton;
@property (nonatomic, copy) NSArray<NSDictionary *> *credentials;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTextField *> *credentialFields;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *credentialDrafts;
@property (nonatomic) NSUInteger credentialGeneration;
@property (nonatomic) NSInteger credentialAgentID;
@property (nonatomic) BOOL credentialBusy;
@property (nonatomic, strong) TLSkillsPicker *skillsPicker;
@property (nonatomic) NSInteger skillsAgentID;
@property (nonatomic) NSUInteger skillsGeneration;
@property (nonatomic) BOOL skillsBusy;
@property (nonatomic) BOOL skillsLoaded;
@property (nonatomic, copy) NSString *skillsStatus;
@property TLBrowserSettingsController *browserSettingsController;
@property NSStackView *pluginRows;
@property NSSearchField *pluginSearch;
@property NSTextField *pluginStatus;
@property TLThemedButton *refreshPluginsButton;
@property TLWrappingActionView *pluginActions;
@property (nonatomic, copy) NSArray<NSDictionary *> *plugins;
@property (nonatomic) NSInteger pluginsAgentID;
@property (nonatomic) NSUInteger pluginsGeneration;
@property (nonatomic) BOOL pluginsBusy;
@property (nonatomic) BOOL pluginsManaged;
@end

@implementation TLSettingsTabController
- (instancetype)initWithSettings:(TLAppSettings *)settings database:(TLDatabase *)database
                   orchestrator:(TLAgentOrchestrator *)orchestrator palette:(TLThemePalette *)palette {
  self = [super initWithPalette:palette];
  if (!self) return nil;
  _browserPreferences = TLBrowserPreferences.sharedPreferences;
  _database = database;
  _agentOrchestrator = orchestrator;
  _draftSettings = [settings copy];
  _buttons = [NSMutableArray array];
  _navigation = [NSMutableArray array];
  _pages = [NSMutableDictionary dictionary];
  _modelButtons = [NSMutableArray array];
  _credentialFields = [NSMutableDictionary dictionary];
  _credentialDrafts = [NSMutableDictionary dictionary];
  [self buildSettingsTabContent];
  return self;
}

- (TLApplicationPreferences *)applicationPreferences {
  return _applicationPreferences ?: TLApplicationPreferences.sharedPreferences;
}
- (NSArray<NSString *> *)pageNames {
  if (self.sectionIndex == 1) return TLBrowserPreferences.categories;
  if (self.sectionIndex == 2) return @[];
  return @[@"Model", @"Tools & Keys", @"Skills", @"Plugins"];
}

- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [[TLThemedButton alloc] init];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.title = title; button.target = self; button.action = action; button.palette = self.palette;
  [self.buttons addObject:button];
  return button;
}
- (NSStackView *)stack:(NSArray<NSView *> *)views vertical:(BOOL)vertical {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
  stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
  stack.spacing = self.palette.space8;
  return stack;
}
- (void)pin:(NSView *)view in:(NSView *)parent inset:(CGFloat)inset {
  view.translatesAutoresizingMaskIntoConstraints = NO;
  [parent addSubview:view];
  [NSLayoutConstraint activateConstraints:@[
    [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:inset],
    [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-inset],
    [view.topAnchor constraintEqualToAnchor:parent.topAnchor constant:inset],
    [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-inset],
  ]];
}
- (NSTextField *)description:(NSString *)text {
  return [self wrappingLabelWithString:text font:self.palette.bodyFont colorToken:@"textMuted"];
}
- (NSView *)card:(NSString *)title description:(NSString *)description controls:(NSArray<NSView *> *)controls {
  NSMutableArray *labels = [NSMutableArray array];
  if (title.length) [labels addObject:[self labelWithString:title font:self.palette.labelFont colorToken:@"appText"]];
  if (description.length) [labels addObject:[self description:description]];
  NSStackView *summary = [self stack:labels vertical:YES];
  NSStackView *fields = [self stack:controls vertical:YES];
  TLSettingsRowView *card = [[TLSettingsRowView alloc] initWithSummary:summary controls:fields palette:self.palette];
  card.cornerRadius = self.palette.radiusMedium;
  card.borderWidth = self.palette.borderWidth;
  [self bindColorForObject:card keyPath:@"fillColor" token:@"controlSurface"];
  [self bindColorForObject:card keyPath:@"borderColor" token:@"controlBorder"];
  for (NSTextField *label in labels) [label.widthAnchor constraintEqualToAnchor:summary.widthAnchor].active = YES;
  for (NSView *view in controls) {
    if ([view isKindOfClass:NSTextField.class] || [view isKindOfClass:NSStackView.class] || [view isKindOfClass:TLWrappingActionView.class])
      [view.widthAnchor constraintEqualToAnchor:fields.widthAnchor].active = YES;
  }
  return card;
}
- (NSScrollView *)scrollPageWithStack:(NSStackView *)stack {
  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.drawsBackground = NO; scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES; scroll.borderType = NSNoBorder;
  TLFlippedView *document = [[TLFlippedView alloc] init];
  document.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.documentView = document;
  [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
  [document addSubview:stack];
  NSLayoutConstraint *fillWidth = [stack.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-self.palette.space12 * 2];
  fillWidth.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:document.leadingAnchor constant:self.palette.space8],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:document.trailingAnchor constant:-self.palette.space8],
    [stack.widthAnchor constraintLessThanOrEqualToConstant:self.palette.settingsContentMaxWidth],
    fillWidth,
    [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:self.palette.space8],
    [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-self.palette.space8],
  ]];
  for (NSView *view in stack.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  return scroll;
}
- (void)styleField:(NSTextField *)field {
  field.translatesAutoresizingMaskIntoConstraints = NO;
  field.font = self.palette.bodyFont;
  [self bindColorForObject:field keyPath:@"textColor" token:@"controlText"];
  [self bindColorForObject:field keyPath:@"backgroundColor" token:@"controlSurface"];
  [field.heightAnchor constraintEqualToConstant:self.palette.fieldHeight].active = YES;
}

- (void)buildSettingsTabContent {
  self.workspace = [[TLSettingsWorkspaceView alloc] init];
  self.workspace.translatesAutoresizingMaskIntoConstraints = NO;
  self.view = self.workspace;
  self.workspace.palette = self.palette;
  self.workspace.sectionTabs.target = self;
  self.workspace.sectionTabs.action = @selector(selectSection:);
  self.workspace.pageMenu.target = self; self.workspace.pageMenu.action = @selector(selectPage:);

  self.saveButton = [self button:@"Save" action:@selector(save:)];
  self.saveButton.primary = YES;
  self.footerLabel = [self labelWithString:@"" font:self.palette.smallFont colorToken:@"textMuted"];
  NSStackView *footer = [self stack:@[self.footerLabel, self.saveButton] vertical:NO];
  [self pin:footer in:self.workspace.footer inset:self.palette.space8];
  [self.footerLabel setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.footerLabel setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.pages[@"Model"] = [self buildModelPage];
  [self showSectionAtIndex:0];
}

- (NSView *)buildModelPage {
  NSView *provider = [self card:@"Model provider" description:@"Choose a provider, connect your account or credentials, then select a model for this agent."
    controls:@[[self button:@"Configure provider…" action:@selector(configureProvider:)]]];
  NSMutableArray *modelCards = [NSMutableArray array];
  for (NSUInteger i = 0; i < 2; i++) {
    TLThemedButton *choose = [self button:@"Choose model…" action:@selector(chooseModel:)];
    choose.tag = i;
    [self.modelButtons addObject:choose];
    NSTextField *model = [self labelWithString:i ? self.draftSettings.supportingModel : self.draftSettings.selectedModel
      font:self.palette.bodyFont colorToken:@"appText"];
    model.identifier = i ? @"smallModelLabel" : @"largeModelLabel";
    [modelCards addObject:[self card:i ? @"Small model" : @"Large model"
      description:i ? @"A lightweight model for supporting tasks, including chat icons."
                    : @"The default model for new conversations. Existing chats keep their own selection."
      controls:@[model, choose]]];
  }
  TLThemedButton *setup = [self button:@"Set up Hermes…" action:@selector(requestOnboarding:)];
  NSView *runtime = [self card:@"Hermes runtime" description:@"Set up a fresh Hermes VM for your agent." controls:@[setup]];
  return [self scrollPageWithStack:[self stack:@[provider, modelCards[0], modelCards[1], runtime] vertical:YES]];
}
- (void)rebuildNavigation {
  for (NSView *view in self.workspace.sidebar.subviews.copy) [view removeFromSuperview];
  [self.navigation removeAllObjects];
  [self.workspace.pageMenu removeAllItems];
  [self.workspace.pageMenu addItemsWithTitles:self.pageNames];
  self.workspace.showsSidebar = self.sectionIndex != 2;
  if (!self.workspace.showsSidebar) return;
  NSString *section = self.sectionIndex == 0 ? @"Agent" : @"Browser";
  NSTextField *label = [self labelWithString:section font:self.palette.labelFont colorToken:@"textMuted"];
  NSMutableArray *items = [NSMutableArray arrayWithObject:label];
  NSArray *icons = self.sectionIndex == 0 ? @[@"cube", @"key.horizontal", @"sparkles", @"puzzlepiece.extension"] :
    @[@"lock.shield", @"hand.raised", @"person.text.rectangle", @"magnifyingglass", @"textformat",
      @"power", @"speedometer", @"character.bubble", @"arrow.down.circle", @"accessibility",
      @"gearshape", @"arrow.counterclockwise", @"square.and.arrow.down"];
  for (NSUInteger i = 0; i < self.pageNames.count; i++) {
    TLSidebarNavigationButton *button = [[TLSidebarNavigationButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = self.pageNames[i]; button.toolTip = button.title; button.systemIconName = icons[i]; button.palette = self.palette;
    button.target = self; button.action = @selector(selectPage:); button.tag = i;
    [button.heightAnchor constraintEqualToConstant:self.palette.settingsActionHeight].active = YES;
    [items addObject:button]; [self.navigation addObject:button];
  }
  NSStackView *nav = [self stack:items vertical:YES];
  nav.spacing = self.palette.space4;
  [nav setCustomSpacing:self.palette.space8 afterView:label];
  NSScrollView *scroll = [self scrollPageWithStack:nav];
  [self pin:scroll in:self.workspace.sidebar inset:0];
}
- (void)selectSection:(NSSegmentedControl *)sender { [self showSectionAtIndex:sender.selectedSegment]; }
- (void)showSectionAtIndex:(NSInteger)index {
  if (self.isClosed || index < 0 || index > 2) return;
  [self.applicationSettingsController cancelShortcutRecording];
  self.sectionIndex = index;
  self.workspace.sectionTabs.selectedSegment = index;
  [self rebuildNavigation];
  [self showPageAtIndex:index == 0 ? self.agentPageIndex : index == 1 ? self.browserPageIndex : 0];
}
- (void)selectPage:(id)sender {
  [self showPageAtIndex:sender == self.workspace.pageMenu ? self.workspace.pageMenu.indexOfSelectedItem : [sender tag]];
}
- (void)showPageAtIndex:(NSInteger)index {
  if (self.isClosed || index < 0 || (self.sectionIndex != 2 && index >= (NSInteger)self.pageNames.count)) return;
  NSString *title, *detail;
  if (self.sectionIndex == 0) {
    self.agentPageIndex = index;
    self.selectedPage = self.pageNames[index]; title = self.selectedPage;
    detail = index == 0 ? @"Choose the models and provider behind your conversations." : index == 1
      ? @"Connect your tools with credentials stored in Hermes." : index == 2 ? @"Choose which installed skills your agent can use."
      : @"Manage the plugins installed for your selected agent.";
    if (!self.pages[self.selectedPage]) self.pages[self.selectedPage] = index == 3 ? [self buildPluginsPage] :
      index == 2 ? [self buildSkillsPage] : [self buildCredentialsPage];
  } else if (self.sectionIndex == 1) {
    self.browserPageIndex = index;
    self.selectedPage = @"Browser"; title = self.pageNames[index];
    detail = @"Preferences for Talaria’s built-in browser.";
    if (!self.pages[self.selectedPage]) self.pages[self.selectedPage] = [self buildBrowserPage];
    self.browserSettingsController.selectedCategoryIndex = index;
  } else {
    self.selectedPage = @"Application"; title = @"Application";
    detail = @"Make Talaria part of your day.";
    if (!self.applicationSettingsController) {
      self.applicationSettingsController = [[TLApplicationSettingsController alloc] initWithPalette:self.palette preferences:self.applicationPreferences];
      [self addChildViewController:self.applicationSettingsController];
      self.pages[self.selectedPage] = self.applicationSettingsController.view;
    }
    [self.applicationSettingsController refresh];
  }
  NSView *page = self.pages[self.selectedPage];
  if (!page.superview) [self pin:page in:self.workspace.pageHost inset:0];
  for (NSString *name in self.pages) self.pages[name].hidden = ![name isEqual:self.selectedPage];
  for (NSUInteger i = 0; i < self.navigation.count; i++) self.navigation[i].selected = i == (NSUInteger)index;
  if (self.workspace.showsSidebar) [self.workspace.pageMenu selectItemAtIndex:index];
  self.workspace.pageTitle.stringValue = title;
  self.workspace.pageDescription.stringValue = detail;
  self.workspace.footer.hidden = ![self.selectedPage isEqual:@"Model"] && ![self.selectedPage isEqual:@"Skills"];
  self.workspace.needsLayout = YES;
  self.footerLabel.stringValue = @"Changes apply when saved.";
  self.footerLabel.toolTip = nil;
  self.saveButton.enabled = YES;
  if ([self.selectedPage isEqual:@"Tools & Keys"] && !self.credentialBusy && (!self.credentials || self.credentialAgentID != self.database.currentAgentID)) [self reloadCredentials:nil];
  if ([self.selectedPage isEqual:@"Skills"]) {
    if (!self.skillsBusy && (!self.skillsLoaded || self.skillsAgentID != self.database.currentAgentID)) [self requestSkillsWithChanges:nil];
    [self updateSkillsFooter];
  }
  if ([self.selectedPage isEqual:@"Plugins"]) [self refreshPluginsForSelectedAgent];
}

- (NSView *)buildPluginsPage {
  self.pluginSearch = [[NSSearchField alloc] init];
  [self styleField:self.pluginSearch]; self.pluginSearch.delegate = self;
  self.pluginSearch.placeholderString = @"Search plugins";
  self.pluginSearch.accessibilityLabel = @"Search plugins";
  self.refreshPluginsButton = [self button:@"Refresh" action:@selector(reloadPlugins:)];
  self.pluginActions = [[TLWrappingActionView alloc] initWithViews:@[self.refreshPluginsButton] palette:self.palette];
  self.pluginSearch.appearance = [NSAppearance appearanceNamed:self.palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.pluginStatus = [self description:@""];
  self.pluginRows = [self stack:@[] vertical:YES];
  NSTextField *detail = [self description:@"Changes save immediately. Restart the agent to apply them to existing sessions."];
  self.pluginStatus.hidden = YES;
  return [self scrollPageWithStack:[self stack:@[self.pluginSearch, self.pluginActions, detail,
    self.pluginStatus, self.pluginRows] vertical:YES]];
}

- (void)refreshPluginsForSelectedAgent {
  if (self.isClosed || !self.pluginRows) return;
  NSInteger agentID = self.database.currentAgentID;
  if (agentID != self.pluginsAgentID) {
    self.pluginsGeneration++;
    self.pluginsBusy = NO; self.plugins = nil; self.pluginsManaged = NO;
    self.pluginsAgentID = agentID;
    self.pluginSearch.stringValue = @"";
    self.pluginStatus.stringValue = @"";
    [self renderPlugins];
  }
  if ([self.selectedPage isEqual:@"Plugins"] && !self.plugins && !self.pluginsBusy) [self reloadPlugins:nil];
}

- (void)renderPlugins {
  for (NSView *row in self.pluginRows.arrangedSubviews.copy) {
    [self.pluginRows removeArrangedSubview:row]; [row removeFromSuperview];
  }
  self.refreshPluginsButton.enabled = !self.pluginsBusy;
  self.pluginStatus.hidden = !self.pluginStatus.stringValue.length;
  NSString *query = self.pluginSearch.stringValue;
  for (NSDictionary *plugin in self.plugins) {
    NSString *searchable = [NSString stringWithFormat:@"%@ %@ %@", plugin[@"name"], plugin[@"id"], plugin[@"description"]];
    if (query.length && [searchable rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
    NSMutableArray<NSView *> *controls = [NSMutableArray array];
    if (![plugin[@"read_only"] boolValue]) {
      NSSwitch *toggle = [[NSSwitch alloc] init];
      toggle.appearance = [NSAppearance appearanceNamed:self.palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
      toggle.identifier = plugin[@"id"]; toggle.target = self; toggle.action = @selector(togglePlugin:);
      toggle.state = [plugin[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
      toggle.enabled = !self.pluginsBusy && !self.pluginsManaged;
      toggle.accessibilityLabel = [NSString stringWithFormat:@"Enable %@", plugin[@"name"]];
      [controls addObject:toggle];
    }
    NSString *origin = [plugin[@"source"] isEqual:@"talaria"] ? @"Bundled with Talaria" :
      ([plugin[@"source"] isEqual:@"bundled"] ? @"Built-in" : @"Installed");
    NSString *version = [plugin[@"version"] length] ? [@" · " stringByAppendingString:plugin[@"version"]] : @"";
    NSString *state = [plugin[@"restart_required"] boolValue] ? @"Restart agent to apply" :
      ([plugin[@"enabled"] boolValue] ? @"Enabled" : @"Disabled");
    if ([plugin[@"enabled"] boolValue] && ![plugin[@"restart_required"] boolValue] && [plugin[@"error"] length]) state = plugin[@"error"];
    if ([plugin[@"scope"] isEqual:@"incognito"]) state = @"Automatic in Incognito windows";
    NSTextField *metadata = [self description:[NSString stringWithFormat:@"%@%@ · %@", origin, version, state]];
    [controls addObject:metadata];
    NSString *description = [plugin[@"description"] length] ? plugin[@"description"] : plugin[@"id"];
    NSView *row = [self card:plugin[@"name"] description:description controls:controls];
    [self.pluginRows addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:self.pluginRows.widthAnchor].active = YES;
  }
  if (self.plugins && !self.pluginRows.arrangedSubviews.count) {
    NSTextField *empty = [self description:self.plugins.count ? @"No plugins match your search." : @"No plugins installed for this agent."];
    [self.pluginRows addArrangedSubview:empty];
    [empty.widthAnchor constraintEqualToAnchor:self.pluginRows.widthAnchor].active = YES;
  }
}

- (void)reloadPlugins:(id)sender { [self requestPlugins:@{@"action": @"list"}]; }
- (void)togglePlugin:(NSSwitch *)sender {
  if (self.pluginsBusy || self.pluginsManaged || self.isClosed) return;
  for (NSDictionary *plugin in self.plugins)
    if ([plugin[@"id"] isEqual:sender.identifier] && [plugin[@"read_only"] boolValue]) return;
  if (self.pluginsAgentID != self.database.currentAgentID) { [self refreshPluginsForSelectedAgent]; return; }
  [self requestPlugins:@{@"action": @"set_enabled", @"id": sender.identifier,
    @"enabled": @(sender.state == NSControlStateValueOn)}];
}
- (void)requestPlugins:(NSDictionary *)parameters {
  if (self.isClosed || self.pluginsBusy) return;
  NSInteger agentID = self.database.currentAgentID;
  if (agentID != self.pluginsAgentID) { [self refreshPluginsForSelectedAgent]; return; }
  if (agentID <= 0) { self.pluginStatus.stringValue = @"Select an agent to view its plugins."; self.pluginStatus.hidden = NO; return; }
  self.pluginsBusy = YES;
  self.pluginStatus.stringValue = [parameters[@"action"] isEqual:@"list"] ? @"Loading plugins…" : @"Saving plugin setting…";
  [self renderPlugins];
  NSUInteger generation = ++self.pluginsGeneration;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesPluginsWithParameters:parameters agentID:agentID token:self.draftSettings.openRouterToken
    model:self.draftSettings.selectedModel completion:^(NSDictionary *result, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.isClosed || generation != owner.pluginsGeneration) return;
      owner.pluginsBusy = NO;
      if (agentID != owner.database.currentAgentID) { [owner refreshPluginsForSelectedAgent]; return; }
      BOOL valid = [result[@"plugins"] isKindOfClass:NSArray.class];
      if (valid) for (id item in result[@"plugins"]) {
        if (![item isKindOfClass:NSDictionary.class]) { valid = NO; break; }
        for (NSString *key in @[@"id", @"name", @"description", @"version", @"source", @"error"])
          if (![item[key] isKindOfClass:NSString.class]) valid = NO;
        for (NSString *key in @[@"enabled", @"restart_required"])
          if (![item[key] isKindOfClass:NSNumber.class]) valid = NO;
        if (item[@"read_only"] && ![item[@"read_only"] isKindOfClass:NSNumber.class]) valid = NO;
        if (item[@"scope"] && ![item[@"scope"] isKindOfClass:NSString.class]) valid = NO;
      }
      if (error || !valid) {
        owner.pluginStatus.stringValue = error.localizedDescription ?: @"Hermes returned an invalid plugin list. Refresh to retry.";
      } else {
        owner.plugins = result[@"plugins"]; owner.pluginsManaged = [result[@"managed"] boolValue];
        owner.pluginStatus.stringValue = owner.pluginsManaged ? @"Plugin settings are managed by your administrator." :
          ([result[@"restart_required"] boolValue] ? @"Saved. Restart the agent to apply changes to existing sessions." : @"");
      }
      [owner renderPlugins];
    });
  }];
}

- (void)updateModelLabelsInView:(NSView *)view {
  if ([view.identifier isEqual:@"largeModelLabel"]) [(NSTextField *)view setStringValue:self.draftSettings.selectedModel];
  if ([view.identifier isEqual:@"smallModelLabel"]) [(NSTextField *)view setStringValue:self.draftSettings.supportingModel];
  for (NSView *child in view.subviews) [self updateModelLabelsInView:child];
}
- (void)configureProvider:(id)sender {
  if (!self.view.window || self.view.window.attachedSheet) return;
  TLAgentRecord *agent = [self.agentOrchestrator defaultAgentCreatingIfNeeded:nil];
  if (!agent) return;
  self.providerSetup = [[TLProviderSetupWindowController alloc] initWithAgent:agent orchestrator:self.agentOrchestrator palette:self.palette];
  __weak typeof(self) weakSelf = self;
  self.providerSetup.completionHandler = ^(NSString *selection) {
    typeof(self) owner = weakSelf;
    if (!owner || owner.isClosed) return;
    TLAppSettings *latest = [owner.database appSettings:nil];
    owner.draftSettings.selectedModel = latest.selectedModel;
    owner.draftSettings.supportingModel = latest.supportingModel;
    owner.largeModelChanged = NO; owner.smallModelChanged = NO;
    [owner updateModelLabelsInView:owner.pages[@"Model"]];
    if (owner.settingsSavedHandler) owner.settingsSavedHandler(latest);
  };
  [self.providerSetup presentForWindow:self.view.window];
}
- (void)chooseModel:(NSButton *)sender {
  if (!self.view.window || self.view.window.attachedSheet) return;
  BOOL small = sender.tag == 1;
  self.modelSelection = [[TLModelSelectionWindowController alloc] initWithSmallModel:small
    selectedModel:small ? self.draftSettings.supportingModel : self.draftSettings.selectedModel
    token:self.draftSettings.openRouterToken orchestrator:self.agentOrchestrator palette:self.palette];
  __weak typeof(self) weakSelf = self;
  self.modelSelection.selectionHandler = ^(NSString *model, void (^completion)(NSError *)) {
    typeof(self) owner = weakSelf;
    if (!owner || owner.isClosed) return;
    if (small) { owner.draftSettings.supportingModel = model; owner.smallModelChanged = YES; }
    else { owner.draftSettings.selectedModel = model; owner.largeModelChanged = YES; }
    [owner updateModelLabelsInView:owner.pages[@"Model"]];
    completion(nil);
  };
  [self.modelSelection configureForDefaultSelection:small];
  [self.modelSelection presentForWindow:self.view.window];
}
- (void)save:(id)sender {
  if (self.isClosed) return;
  if ([self.selectedPage isEqual:@"Skills"]) {
    if (self.skillsAgentID != self.database.currentAgentID) [self requestSkillsWithChanges:nil];
    else if (self.skillsPicker.changes.count) [self requestSkillsWithChanges:self.skillsPicker.changes];
    return;
  }
  TLAppSettings *latest = [self.database appSettings:nil];
  if (latest) {
    if (!self.largeModelChanged) self.draftSettings.selectedModel = latest.selectedModel;
    if (!self.smallModelChanged) self.draftSettings.supportingModel = latest.supportingModel;
  }
  self.draftSettings.theme = TLThemePreferenceSystem;
  NSError *error = nil;
  TLAppSettings *saved = [self.database saveAppSettings:self.draftSettings error:&error];
  if (!saved) { if (self.errorHandler) self.errorHandler(error.localizedDescription ?: @"Could not save settings."); return; }
  self.draftSettings = [saved copy];
  self.largeModelChanged = NO; self.smallModelChanged = NO;
  [self updateModelLabelsInView:self.pages[@"Model"]];
  self.footerLabel.stringValue = @"Changes saved.";
  if (self.settingsSavedHandler) self.settingsSavedHandler(saved);
}
- (void)requestOnboarding:(id)sender { if (self.onboardingHandler) self.onboardingHandler(); }

- (NSView *)buildSkillsPage {
  self.skillsPicker = [[TLSkillsPicker alloc] init];
  self.skillsPicker.palette = self.palette;
  __weak typeof(self) weakSelf = self;
  self.skillsPicker.reloadHandler = ^{ [weakSelf requestSkillsWithChanges:nil]; };
  self.skillsPicker.changesHandler = ^{
    weakSelf.skillsStatus = nil;
    [weakSelf updateSkillsFooter];
  };
  NSTextField *detail = [self description:@"Talaria keeps grounded-citations disabled. Skills already loaded in a conversation can remain in its history."];
  return [self scrollPageWithStack:[self stack:@[self.skillsPicker, detail] vertical:YES]];
}

- (void)updateSkillsFooter {
  if (![self.selectedPage isEqual:@"Skills"]) return;
  self.saveButton.enabled = self.skillsLoaded && !self.skillsBusy && self.skillsPicker.changes.count > 0;
  self.footerLabel.stringValue = self.skillsStatus ?: @"Changes apply when saved.";
  self.footerLabel.toolTip = self.footerLabel.stringValue;
}

- (void)requestSkillsWithChanges:(NSDictionary<NSString *, NSNumber *> *)changes {
  if (self.isClosed || self.skillsBusy) return;
  NSInteger agentID = self.database.currentAgentID;
  if (self.skillsAgentID != agentID) {
    self.skillsPicker.skills = @[];
    self.skillsLoaded = NO;
    changes = nil;
  }
  self.skillsAgentID = agentID;
  self.skillsBusy = YES;
  self.skillsPicker.enabled = NO;
  self.skillsPicker.loading = changes == nil;
  self.skillsPicker.message = @"";
  self.skillsStatus = changes ? @"Saving skills…" : @"Loading skills…";
  [self updateSkillsFooter];
  NSUInteger generation = ++self.skillsGeneration;
  BOOL saving = changes != nil;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesSkillsForAgentWithID:agentID changes:changes completion:^(NSDictionary *result, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.isClosed || generation != owner.skillsGeneration) return;
      owner.skillsBusy = NO;
      owner.skillsPicker.enabled = YES;
      owner.skillsPicker.loading = NO;
      if (owner.database.currentAgentID != agentID) { [owner requestSkillsWithChanges:nil]; return; }
      if (error || ![result[@"skills"] isKindOfClass:NSArray.class]) {
        owner.skillsStatus = error.localizedDescription ?: @"Hermes returned an invalid skill catalogue.";
        if (!saving) { owner.skillsLoaded = NO; owner.skillsPicker.message = owner.skillsStatus; }
      } else {
        owner.skillsPicker.skills = result[@"skills"];
        owner.skillsLoaded = YES;
        owner.skillsStatus = saving ? @"Changes saved." : @"Changes apply when saved.";
        if (saving && owner.skillsSavedHandler) owner.skillsSavedHandler(agentID);
      }
      [owner updateSkillsFooter];
    });
  }];
}

- (NSView *)buildBrowserPage {
  self.browserSettingsController = [[TLBrowserSettingsController alloc] initWithPalette:self.palette preferences:self.browserPreferences];
  [self addChildViewController:self.browserSettingsController];
  [self.browserSettingsController prepareInWindow:self.view.window];
  return self.browserSettingsController.view;
}

- (NSView *)buildCredentialsPage {
  self.credentialSearch = [[NSSearchField alloc] init];
  [self styleField:self.credentialSearch];
  self.credentialSearch.placeholderString = @"Search tools and keys";
  self.credentialSearch.accessibilityLabel = @"Search tools and keys";
  self.credentialSearch.delegate = self;
  self.credentialCategory = [[NSPopUpButton alloc] init];
  [self.credentialCategory addItemsWithTitles:@[@"Tools", @"Settings"]];
  self.credentialCategory.font = self.palette.bodyFont;
  self.credentialCategory.accessibilityLabel = @"Credential category";
  self.credentialCategory.target = self; self.credentialCategory.action = @selector(filterCredentials:);
  self.refreshCredentialsButton = [self button:@"Refresh" action:@selector(reloadCredentials:)];
  TLWrappingActionView *filters = [[TLWrappingActionView alloc] initWithViews:@[self.credentialCategory, self.refreshCredentialsButton] palette:self.palette];
  self.credentialStatus = [self description:@"Loading credentials from Hermes…"];
  self.credentialRows = [self stack:@[] vertical:YES];
  NSStackView *stack = [self stack:@[self.credentialSearch, filters, self.credentialStatus, self.credentialRows] vertical:YES];
  return [self scrollPageWithStack:stack];
}
- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == self.pluginSearch) { [self renderPlugins]; return; }
  if (notification.object == self.credentialSearch) { [self renderCredentials]; return; }
  NSTextField *field = notification.object;
  if (field.identifier.length) self.credentialDrafts[field.identifier] = field.stringValue;
}
- (void)filterCredentials:(id)sender { [self renderCredentials]; }
- (void)reloadCredentials:(id)sender {
  if (self.credentialBusy || self.isClosed) return;
  NSInteger agentID = self.database.currentAgentID;
  if (self.credentialAgentID != agentID) { self.credentials = nil; [self.credentialFields removeAllObjects]; [self.credentialDrafts removeAllObjects]; }
  self.credentialAgentID = agentID;
  self.credentialBusy = YES;
  self.refreshCredentialsButton.enabled = NO;
  self.credentialStatus.stringValue = @"Loading credentials from Hermes…";
  [self renderCredentials];
  NSUInteger generation = ++self.credentialGeneration;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesCredentialsWithAction:@"list" key:@"" value:@"" token:self.draftSettings.openRouterToken
    completion:^(NSDictionary *result, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (!owner || owner.isClosed || generation != owner.credentialGeneration) return;
        owner.credentialBusy = NO;
        owner.refreshCredentialsButton.enabled = YES;
        if (owner.database.currentAgentID != agentID) { [owner reloadCredentials:nil]; return; }
        id entries = result[@"entries"];
        NSError *resultError = error;
        if (!resultError && ![entries isKindOfClass:NSArray.class]) resultError = [NSError errorWithDomain:@"Talaria.Settings" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Hermes returned an invalid credential catalogue."}];
        if (resultError) {
          [owner renderCredentials];
          owner.credentialStatus.stringValue = resultError.localizedDescription; return;
        }
        owner.credentials = entries;
        [owner renderCredentials];
      });
    }];
}
- (void)renderCredentials {
  // Keep drafts while filtering, without ever requesting saved secret values.
  for (NSString *key in self.credentialFields) self.credentialDrafts[key] = self.credentialFields[key].stringValue;
  for (NSView *view in self.credentialRows.arrangedSubviews.copy) { [self.credentialRows removeArrangedSubview:view]; [view removeFromSuperview]; }
  [self.buttons filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TLThemedButton *button, NSDictionary *bindings) {
    return !button.identifier.length;
  }]];
  [self.credentialFields removeAllObjects];
  NSString *category = self.credentialCategory.indexOfSelectedItem == 1 ? @"setting" : @"tool";
  NSString *query = [self.credentialSearch.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSUInteger matches = 0, configured = 0;
  for (NSDictionary *entry in self.credentials) {
    if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"key"] isKindOfClass:NSString.class]) continue;
    if (![entry[@"category"] isEqual:category]) continue;
    NSString *key = entry[@"key"];
    NSString *description = [entry[@"description"] isKindOfClass:NSString.class] ? entry[@"description"] : @"";
    NSString *searchable = [NSString stringWithFormat:@"%@ %@ %@", key, description, entry[@"tools"] ?: @""];
    if (query.length && [searchable rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
    matches++;
    BOOL isSet = [entry[@"is_set"] boolValue]; if (isSet) configured++;
    NSString *name = key;
    for (NSString *suffix in @[@"_API_KEY", @"_TOKEN", @"_KEY"]) if ([name hasSuffix:suffix]) { name = [name substringToIndex:name.length - suffix.length]; break; }
    name = [[name stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
    NSTextField *status = [self labelWithString:isSet ? @"●  Configured" : @"○  Not configured" font:self.palette.smallFont colorToken:isSet ? @"appText" : @"textMuted"];
    NSTextField *field = [entry[@"is_password"] boolValue] ? [[NSSecureTextField alloc] init] : [[NSTextField alloc] init];
    [self styleField:field];
    field.identifier = key; field.accessibilityLabel = name;
    field.placeholderString = isSet ? @"Enter a replacement value" : @"Enter a value";
    field.stringValue = self.credentialDrafts[key] ?: @"";
    field.delegate = self; field.enabled = !self.credentialBusy;
    self.credentialFields[key] = field;
    TLThemedButton *save = [self button:@"Save" action:@selector(saveCredential:)]; save.identifier = key;
    TLThemedButton *remove = [self button:@"Remove" action:@selector(removeCredential:)]; remove.identifier = key;
    save.enabled = !self.credentialBusy; remove.enabled = isSet && !self.credentialBusy;
    NSMutableArray *actions = [NSMutableArray arrayWithObjects:save, remove, nil];
    NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
    if ([url hasPrefix:@"https://"]) {
      TLThemedButton *docs = [self button:@"Get key ↗" action:@selector(openCredentialHelp:)];
      docs.identifier = url; [actions addObject:docs];
    }
    // Compact actions wrap onto their own line; the input always gets the full width.
    NSView *card = [self card:name description:description controls:@[status, field, [[TLWrappingActionView alloc] initWithViews:actions palette:self.palette]]];
    [self.credentialRows addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:self.credentialRows.widthAnchor].active = YES;
  }
  if (!self.credentialBusy && self.credentials) self.credentialStatus.stringValue = matches
    ? [NSString stringWithFormat:@"%lu credentials · %lu configured", (unsigned long)matches, (unsigned long)configured]
    : query.length ? @"No matching credentials. Try another search." : @"No credentials in this category for the installed Hermes version.";
}
- (void)saveCredential:(NSButton *)sender {
  NSString *value = self.credentialFields[sender.identifier].stringValue;
  if (!value.length) { self.credentialStatus.stringValue = @"Enter a value before saving."; return; }
  [self changeCredential:sender.identifier value:value action:@"set"];
}
- (void)removeCredential:(NSButton *)sender {
  if (self.credentialBusy) return;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Remove this credential?";
  alert.informativeText = [NSString stringWithFormat:@"Hermes will no longer have a saved value for %@.", sender.identifier];
  [alert addButtonWithTitle:@"Remove"]; [alert addButtonWithTitle:@"Cancel"];
  __weak typeof(self) weakSelf = self;
  [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    if (response == NSAlertFirstButtonReturn) [weakSelf changeCredential:sender.identifier value:@"" action:@"remove"];
  }];
}
- (void)changeCredential:(NSString *)key value:(NSString *)value action:(NSString *)action {
  if (self.credentialBusy || self.isClosed) return;
  if (self.database.currentAgentID != self.credentialAgentID) { [self reloadCredentials:nil]; return; }
  NSInteger agentID = self.credentialAgentID;
  self.credentialBusy = YES; self.refreshCredentialsButton.enabled = NO;
  [self renderCredentials];
  self.credentialStatus.stringValue = [action isEqual:@"set"] ? @"Saving credential…" : @"Removing credential…";
  NSUInteger generation = ++self.credentialGeneration;
  __weak typeof(self) weakSelf = self;
  [self.agentOrchestrator hermesCredentialsWithAction:action key:key value:value token:self.draftSettings.openRouterToken
    completion:^(NSDictionary *result, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (!owner || owner.isClosed || generation != owner.credentialGeneration) return;
        owner.credentialBusy = NO; owner.refreshCredentialsButton.enabled = YES;
        if (owner.database.currentAgentID != agentID) { [owner reloadCredentials:nil]; return; }
        if (error || ![result[@"ok"] boolValue]) {
          [owner renderCredentials];
          owner.credentialStatus.stringValue = error.localizedDescription ?: @"Hermes could not save this credential. Try again.";
          return;
        }
        owner.credentialFields[key].stringValue = @"";
        [owner.credentialDrafts removeObjectForKey:key];
        [owner reloadCredentials:nil];
      });
    }];
}
- (void)openCredentialHelp:(NSButton *)sender {
  NSURL *url = [NSURL URLWithString:sender.identifier];
  if ([url.scheme isEqual:@"https"]) [TLWebKitBrowserController.sharedController openURL:url fromWindow:self.view.window];
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.workspace.palette = palette;
  for (TLThemedButton *button in self.buttons) button.palette = palette;
  for (TLSidebarNavigationButton *button in self.navigation) button.palette = palette;
  [self.modelSelection applyPalette:palette];
  [self.providerSetup applyPalette:palette];
  [self.browserSettingsController applyPalette:palette];
  [self.applicationSettingsController applyPalette:palette];
  self.skillsPicker.palette = palette;
  self.pluginActions.palette = palette;
  self.pluginSearch.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  if (self.pluginRows) [self renderPlugins];
  [TLWebKitBrowserController.sharedController applyDarkAppearance:palette.dark];
}
- (void)close {
  if (self.isClosed) return;
  [super close];
  [self.browserSettingsController close];
  [self.applicationSettingsController close];
  self.workspace.sectionTabs.target = nil;
  self.workspace.pageMenu.target = nil;
  self.credentialGeneration++;
  self.skillsGeneration++;
  self.pluginsGeneration++;
  self.pluginSearch.delegate = nil;
  self.skillsPicker.reloadHandler = nil;
  self.skillsPicker.changesHandler = nil;
  [self.credentialDrafts removeAllObjects];
  for (NSTextField *field in self.credentialFields.allValues) field.stringValue = @"";
  [self.modelSelection.window.sheetParent endSheet:self.modelSelection.window];
  [self.modelSelection close];
  self.onboardingHandler = nil; self.settingsSavedHandler = nil; self.errorHandler = nil;
  self.skillsSavedHandler = nil;
}
@end
