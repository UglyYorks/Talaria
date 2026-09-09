#import "TLSettingsTabController.h"
#import "TLBrowserSettingsController.h"
#import "TLApplicationSettingsController.h"
#import "AgentOrchestrator.h"
#import "ChromiumBrowserController.h"
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
@property (nonatomic, strong) NSSecureTextField *tokenField;
@property (nonatomic, strong) NSButton *rememberButton;
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
  return @[@"Model", @"Tools & Keys", @"Skills"];
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
  self.tokenField = [[NSSecureTextField alloc] init];
  [self styleField:self.tokenField];
  self.tokenField.stringValue = self.draftSettings.openRouterToken;
  self.tokenField.placeholderString = @"OpenRouter API key";
  self.tokenField.accessibilityLabel = @"OpenRouter API key";
  self.rememberButton = [NSButton checkboxWithTitle:@"Remember token" target:nil action:nil];
  self.rememberButton.font = self.palette.bodyFont;
  [self bindColorForObject:self.rememberButton keyPath:@"contentTintColor" token:@"controlText"];
  self.rememberButton.state = self.draftSettings.rememberOpenRouterToken ? NSControlStateValueOn : NSControlStateValueOff;
  NSView *provider = [self card:@"OpenRouter" description:@"Your API key connects Hermes to your model provider."
    controls:@[self.tokenField, self.rememberButton]];
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
  NSArray *icons = self.sectionIndex == 0 ? @[@"cube", @"key.horizontal", @"sparkles"] :
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
      ? @"Connect your tools with credentials stored in Hermes." : @"Choose which installed skills your agent can use.";
    if (!self.pages[self.selectedPage]) self.pages[self.selectedPage] = index == 2 ? [self buildSkillsPage] : [self buildCredentialsPage];
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
}

- (void)updateModelLabelsInView:(NSView *)view {
  if ([view.identifier isEqual:@"largeModelLabel"]) [(NSTextField *)view setStringValue:self.draftSettings.selectedModel];
  if ([view.identifier isEqual:@"smallModelLabel"]) [(NSTextField *)view setStringValue:self.draftSettings.supportingModel];
  for (NSView *child in view.subviews) [self updateModelLabelsInView:child];
}
- (void)chooseModel:(NSButton *)sender {
  if (!self.view.window || self.view.window.attachedSheet) return;
  BOOL small = sender.tag == 1;
  self.modelSelection = [[TLModelSelectionWindowController alloc] initWithSmallModel:small
    selectedModel:small ? self.draftSettings.supportingModel : self.draftSettings.selectedModel
    token:self.tokenField.stringValue orchestrator:self.agentOrchestrator palette:self.palette];
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
  self.draftSettings.openRouterToken = self.tokenField.stringValue;
  self.draftSettings.rememberOpenRouterToken = self.rememberButton.state == NSControlStateValueOn;
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
  [self.agentOrchestrator hermesCredentialsWithAction:@"list" key:@"" value:@"" token:self.tokenField.stringValue
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
  [self.agentOrchestrator hermesCredentialsWithAction:action key:key value:value token:self.tokenField.stringValue
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
  if ([url.scheme isEqual:@"https"]) [TLChromiumBrowserController.sharedController openURL:url fromWindow:self.view.window];
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.workspace.palette = palette;
  for (TLThemedButton *button in self.buttons) button.palette = palette;
  for (TLSidebarNavigationButton *button in self.navigation) button.palette = palette;
  [self.modelSelection applyPalette:palette];
  [self.browserSettingsController applyPalette:palette];
  [self.applicationSettingsController applyPalette:palette];
  self.skillsPicker.palette = palette;
  [TLChromiumBrowserController.sharedController applyDarkAppearance:palette.dark];
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
