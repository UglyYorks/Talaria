#import "TLBrowserSettingsController.h"
#import "TLBrowserProfileImporter.h"
#import "UIComponents.h"
#import "design_system/TLSettingsRowView.h"
#import "design_system/TLWrappingActionView.h"
#import "design_system/TLThemedButton.h"
@interface TLBrowserSettingsController () <NSTextFieldDelegate, NSSearchFieldDelegate>
@property id<TLBrowserPreferencesService> preferences;
@property NSSearchField *search;
@property NSTextField *status;
@property NSTextField *empty;
@property NSStackView *rows;
@property NSMutableDictionary<NSString *, NSControl *> *controls;
@property NSMutableDictionary<NSString *, NSView *> *cards;
@property NSMutableArray<TLThemedButton *> *buttons;
@property NSMutableArray<NSDictionary *> *extraRows;
@property NSMutableDictionary<NSString *, NSDictionary *> *importSources;
@property NSMutableDictionary<NSString *, NSPopUpButton *> *profilePickers;
@property BOOL ready;
@property TLThemedButton *defaultBrowserButton;
@property NSTextField *defaultBrowserStatus;
@property BOOL requestingDefaultBrowser;
@property (nonatomic) BOOL busy;
@end
@implementation TLBrowserSettingsController
- (instancetype)initWithPalette:(TLThemePalette *)palette preferences:(id<TLBrowserPreferencesService>)preferences {
  if (!(self = [super initWithPalette:palette])) return nil;
  _preferences = preferences; _controls = [NSMutableDictionary dictionary]; _cards = [NSMutableDictionary dictionary];
  _buttons = [NSMutableArray array]; _extraRows = [NSMutableArray array];
  _importSources = [NSMutableDictionary dictionary]; _profilePickers = [NSMutableDictionary dictionary];
  [self buildContent];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshDefaultBrowser) name:NSApplicationDidBecomeActiveNotification object:nil];
  return self;
}
- (NSStackView *)stack:(NSArray *)views {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.translatesAutoresizingMaskIntoConstraints = NO; stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading; stack.spacing = self.palette.space8;
  return stack;
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier {
  TLThemedButton *button = [[TLThemedButton alloc] init]; button.title = title;
  button.target = self; button.action = action; button.identifier = identifier; button.palette = self.palette;
  button.translatesAutoresizingMaskIntoConstraints = NO; [self.buttons addObject:button]; return button;
}
- (void)styleField:(NSTextField *)field {
  field.font = self.palette.bodyFont; field.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:field keyPath:@"textColor" token:@"controlText"];
  [self bindColorForObject:field keyPath:@"backgroundColor" token:@"controlSurface"];
}
- (NSView *)card:(NSString *)title detail:(NSString *)detail controls:(NSArray *)controls {
  NSTextField *label = [self wrappingLabelWithString:title font:self.palette.labelFont colorToken:@"appText"];
  NSTextField *description = [self wrappingLabelWithString:detail font:self.palette.bodyFont colorToken:@"textMuted"];
  NSStackView *summary = [self stack:@[label,description]], *fields = [self stack:controls];
  TLSettingsRowView *row = [[TLSettingsRowView alloc] initWithSummary:summary controls:fields palette:self.palette];
  row.cornerRadius = self.palette.radiusMedium; row.borderWidth = self.palette.borderWidth;
  [self bindColorForObject:row keyPath:@"fillColor" token:@"controlSurface"];
  [self bindColorForObject:row keyPath:@"borderColor" token:@"controlBorder"];
  for (NSView *view in summary.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:summary.widthAnchor].active = YES;
  for (NSView *view in controls) {
    if (![view isKindOfClass:NSSwitch.class] && (![view isKindOfClass:NSButton.class] || [view isKindOfClass:NSPopUpButton.class])) [view.widthAnchor constraintEqualToAnchor:fields.widthAnchor].active = YES;
  }
  return row;
}
- (void)addRow:(NSView *)row {
  [self.rows addArrangedSubview:row]; [row.widthAnchor constraintEqualToAnchor:self.rows.widthAnchor].active = YES;
}
- (void)buildContent {
  TLTokenView *root = [[TLTokenView alloc] init]; self.view = root;
  [self bindColorForObject:root keyPath:@"fillColor" token:@"tabBackground"];
  NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.drawsBackground = NO;
  scroll.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:scroll];
  scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.borderType = NSNoBorder;
  [NSLayoutConstraint activateConstraints:@[
    [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
    [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
    [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
  TLFlippedView *document = [[TLFlippedView alloc] init]; document.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.documentView = document; [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
  self.search = [[NSSearchField alloc] init]; [self styleField:self.search]; self.search.delegate = self;
  self.search.placeholderString = @"Search browser settings"; self.search.accessibilityLabel = @"Search browser settings";
  self.status = [self wrappingLabelWithString:@"Starting the built-in browser…" font:self.palette.smallFont colorToken:@"textMuted"];
  self.rows = [self stack:@[]];
  NSStackView *content = [self stack:@[self.search,self.status,self.rows]];
  [document addSubview:content];
  NSLayoutConstraint *width = [content.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-2*self.palette.space12];
  width.priority = NSLayoutPriorityRequired - 1;
  [NSLayoutConstraint activateConstraints:@[
    [content.centerXAnchor constraintEqualToAnchor:document.centerXAnchor], width,
    [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:document.leadingAnchor constant:self.palette.space8],
    [content.trailingAnchor constraintLessThanOrEqualToAnchor:document.trailingAnchor constant:-self.palette.space8],
    [content.widthAnchor constraintLessThanOrEqualToConstant:self.palette.settingsContentMaxWidth],
    [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:self.palette.space8],
    [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-self.palette.space8]]];
  for (NSView *view in content.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:content.widthAnchor].active = YES;
  self.defaultBrowserButton = [self button:@"Make Talaria my default browser" action:@selector(makeDefaultBrowser:) identifier:@"defaultBrowser"];
  self.defaultBrowserStatus = [self wrappingLabelWithString:@"" font:self.palette.smallFont colorToken:@"textMuted"];
  NSView *defaultRow = [self card:@"Default browser" detail:@"Open web links from other apps in Talaria." controls:@[self.defaultBrowserButton, self.defaultBrowserStatus]];
  [self.extraRows addObject:@{@"category":@"Default browser", @"search":@"Default browser Make Talaria my default browser Open web links from other apps", @"row":defaultRow}];
  [self addRow:defaultRow];
  [self refreshDefaultBrowser];
  for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
    NSString *identifier = setting[@"id"], *type = setting[@"type"];
    NSControl *control; NSMutableArray *views = [NSMutableArray array];
    if ([type isEqual:@"bool"]) {
      NSSwitch *toggle = [[NSSwitch alloc] init]; toggle.target = self; toggle.action = @selector(change:); control = toggle;
    } else if ([type isEqual:@"choice"] || [type isEqual:@"font"]) {
      NSPopUpButton *popup = [[NSPopUpButton alloc] init]; popup.font = self.palette.bodyFont;
      [popup addItemsWithTitles:[type isEqual:@"font"] ? [NSFontManager.sharedFontManager.availableFontFamilies sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] : setting[@"labels"]];
      popup.target = self; popup.action = @selector(change:); control = popup;
    } else {
      NSTextField *field = [[NSTextField alloc] init]; [self styleField:field]; field.target = self; field.action = @selector(change:);
      BOOL multiline = [type isEqual:@"multiline"];
      field.usesSingleLineMode = !multiline; field.cell.wraps = multiline; field.lineBreakMode = multiline ? NSLineBreakByWordWrapping : NSLineBreakByClipping;
      [field.heightAnchor constraintEqualToConstant:self.palette.fieldHeight*(multiline ? 3 : 1)].active = YES;
      if ([type isEqual:@"directory"]) field.editable = NO;
      control = field;
    }
    control.identifier = identifier; control.accessibilityLabel = setting[@"title"];
    control.enabled = NO; self.controls[identifier] = control; [views addObject:control];
    if ([@[@"text",@"multiline",@"directory"] containsObject:type]) {
      TLThemedButton *apply = [self button:[type isEqual:@"directory"] ? @"Choose folder…" : @"Apply" action:[type isEqual:@"directory"] ? @selector(chooseFolder:) : @selector(change:) identifier:identifier];
      apply.enabled = NO; [views addObject:apply];
    }
    NSView *row = [self card:setting[@"title"] detail:setting[@"detail"] controls:views];
    self.cards[identifier] = row; [self addRow:row];
  }
  for (NSArray *action in @[
    @[@"cookies",@"Privacy & security",@"Clear cookies",@"Delete cookies for every site in Talaria. This signs you out of websites.",@"Clear cookies…"],
    @[@"cache",@"Privacy & security",@"Clear cached files",@"Remove cached pages, images, and other network responses.",@"Clear cache…"],
    @[@"reset",@"Reset settings",@"Restore browser defaults",@"Reset the settings on these pages. Cookies, saved logins, and your Talaria chats are kept. Restart Talaria to apply system changes.",@"Restore defaults…"]]) {
    TLThemedButton *button = [self button:action[4] action:@selector(confirmDataAction:) identifier:action[0]]; button.enabled = NO; button.tag = 1;
    NSView *row = [self card:action[2] detail:action[3] controls:@[button]];
    [self.extraRows addObject:@{@"category":action[1],@"search":[NSString stringWithFormat:@"%@ %@",action[2],action[3]],@"detail":action[3],@"row":row}]; [self addRow:row];
  }
  [self reloadImportSources:nil];
  self.empty = [self wrappingLabelWithString:@"No matching settings. Try another search." font:self.palette.bodyFont colorToken:@"textMuted"];
  [self addRow:self.empty]; [self filter:nil];
}
// Overridable workspace boundary keeps tests from changing the user's defaults.
- (NSWorkspace *)browserWorkspace { return NSWorkspace.sharedWorkspace; }
- (NSURL *)browserApplicationURL { return NSBundle.mainBundle.bundleURL; }
- (BOOL)isDefaultForScheme:(NSString *)scheme {
  NSURL *handler = [[self browserWorkspace] URLForApplicationToOpenURL:[NSURL URLWithString:[scheme stringByAppendingString:@"://example.com"]]];
  if (!handler) return NO;
  NSString *identifier = [NSBundle bundleWithURL:[self browserApplicationURL]].bundleIdentifier;
  return identifier.length && [[NSBundle bundleWithURL:handler].bundleIdentifier isEqual:identifier];
}
- (void)refreshDefaultBrowser {
  if (self.isClosed) return;
  BOOL isDefault = [self isDefaultForScheme:@"http"] && [self isDefaultForScheme:@"https"];
  self.defaultBrowserButton.enabled = !isDefault && !self.requestingDefaultBrowser;
  if (!self.requestingDefaultBrowser) self.defaultBrowserStatus.stringValue = isDefault ? @"Talaria is your default browser." : @"";
}
- (void)makeDefaultBrowser:(id)sender {
  if (self.requestingDefaultBrowser || self.isClosed) return;
  self.requestingDefaultBrowser = YES;
  self.defaultBrowserButton.enabled = NO;
  self.defaultBrowserStatus.stringValue = @"Confirm your choice in macOS.";
  [self requestDefaultBrowserSchemeAtIndex:0];
}
- (void)requestDefaultBrowserSchemeAtIndex:(NSUInteger)index {
  NSArray *schemes = @[@"http", @"https"];
  if (index == schemes.count) {
    self.requestingDefaultBrowser = NO;
    [self refreshDefaultBrowser];
    if (self.defaultBrowserButton.enabled) self.defaultBrowserStatus.stringValue = @"The default browser was not changed. You can try again.";
    return;
  }
  NSString *scheme = schemes[index];
  if ([self isDefaultForScheme:scheme]) { [self requestDefaultBrowserSchemeAtIndex:index + 1]; return; }
  __weak typeof(self) weakSelf = self;
  [[self browserWorkspace] setDefaultApplicationAtURL:[self browserApplicationURL] toOpenURLsWithScheme:scheme completionHandler:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf;
      if (!owner || owner.isClosed) return;
      if (error) {
        owner.requestingDefaultBrowser = NO;
        [owner refreshDefaultBrowser];
        if (owner.defaultBrowserButton.enabled) owner.defaultBrowserStatus.stringValue = error.localizedDescription ?: @"The default browser was not changed.";
      } else [owner requestDefaultBrowserSchemeAtIndex:index + 1];
    });
  }];
}
- (void)prepareInWindow:(NSWindow *)window {
  [self refreshDefaultBrowser];
  if (self.ready || self.busy || self.isClosed) return;
  self.busy = YES; __weak typeof(self) weakSelf = self;
  [self.preferences prepareInWindow:window completion:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf; if (!owner || owner.isClosed) return;
      owner.busy = NO; owner.ready = !error;
      owner.status.stringValue = error.localizedDescription ?: @"Changes save to Talaria’s browser. Use Apply after editing text.";
      if (!error) [owner refreshControls];
    });
  }];
}
- (void)setBusy:(BOOL)busy {
  _busy = busy;
  for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
    self.controls[setting[@"id"]].enabled = !busy && self.ready && [[self.preferences stateForSetting:setting][@"available"] boolValue];
  }
  for (TLThemedButton *button in self.buttons) button.enabled = !busy && self.ready && (button.tag == 1 || !self.controls[button.identifier] || self.controls[button.identifier].enabled);
  for (NSPopUpButton *picker in self.profilePickers.allValues) picker.enabled = !busy;
  [self refreshDefaultBrowser];
}
- (NSArray<NSDictionary *> *)detectedImportBrowsers { return [TLBrowserProfileImporter installedBrowsers]; }
- (void)reloadImportSources:(id)sender {
  if (self.busy) return;
  for (NSDictionary *entry in self.extraRows.copy) if ([entry[@"category"] isEqual:@"Import profiles"]) {
    NSView *row = entry[@"row"];
    for (TLThemedButton *button in self.buttons.copy) if ([button isDescendantOf:row]) [self.buttons removeObject:button];
    [self.rows removeArrangedSubview:row]; [row removeFromSuperview]; [self.extraRows removeObject:entry];
  }
  [self.importSources removeAllObjects]; [self.profilePickers removeAllObjects];
  TLThemedButton *refresh = [self button:@"Refresh" action:@selector(reloadImportSources:) identifier:@"refreshBrowsers"];
  NSView *intro = [self card:@"Import browser profiles" detail:@"Import while your browser stays open. Cookies apply now; local storage applies after restarting Talaria. Imports replace matching site data. macOS may request access when needed." controls:@[refresh]];
  [self addImportRow:intro search:@"Import browser profiles cookies local storage refresh"];
  NSArray *browsers = [self detectedImportBrowsers];
  for (NSDictionary *browser in browsers) {
    NSString *identifier = browser[@"bundleID"]; NSArray *profiles = browser[@"profiles"];
    self.importSources[identifier] = browser;
    NSMutableArray *controls = [NSMutableArray array];
    NSString *detail = @"Import cookies and local storage from the selected profile.";
    if ([browser[@"engine"] isEqual:@"unsupported"]) detail = @"Installed. Importing cookies and local storage from this browser is not supported.";
    else if (browser[@"discoveryError"]) {
      detail = @"Import cookies and local storage. macOS needs access to this browser’s profile folder to continue.";
      TLThemedButton *access = [self button:@"Import" action:@selector(importProfile:) identifier:identifier];
      access.accessibilityLabel = [@"Import profile from " stringByAppendingString:browser[@"name"]];
      access.toolTip = [browser[@"discoveryError"] localizedDescription];
      [controls addObject:access];
    }
    else if (!profiles.count) detail = @"No profile was found. Open this browser once, then refresh.";
    else {
      NSPopUpButton *picker = [[NSPopUpButton alloc] init]; picker.font = self.palette.bodyFont;
      picker.accessibilityLabel = [browser[@"name"] stringByAppendingString:@" profile"];
      for (NSDictionary *profile in profiles) {
        // Distinguish profiles even when users have given them identical names.
        [picker addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)", profile[@"name"], [profile[@"URL"] lastPathComponent]]];
        picker.lastItem.representedObject = profile;
      }
      self.profilePickers[identifier] = picker; self.importSources[identifier] = browser;
      TLThemedButton *button = [self button:@"Import" action:@selector(importProfile:) identifier:identifier];
      button.accessibilityLabel = [@"Import profile from " stringByAppendingString:browser[@"name"]];
      button.enabled = self.ready;
      [controls addObjectsFromArray:@[picker,button]];
    }
    NSView *row = [self card:browser[@"name"] detail:detail controls:controls];
    [self addImportRow:row search:[NSString stringWithFormat:@"Import profiles %@ cookies local storage %@",browser[@"name"],detail]];
  }
  if (!browsers.count) [self addImportRow:[self card:@"No browsers detected" detail:@"Install or open a supported browser, then refresh this list." controls:@[]] search:@"Import profiles no browsers detected"];
  [self filter:nil];
}
- (void)addImportRow:(NSView *)row search:(NSString *)search {
  [self.extraRows addObject:@{@"category":@"Import profiles",@"search":search,@"row":row}];
  [self addRow:row];
}
- (void)grantImportAccess:(NSButton *)sender {
  if(self.busy) return;
  NSDictionary *browser = self.importSources[sender.identifier];
  NSURL *root = browser[@"profileRootURL"];
  if(!root || !self.view.window) return;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.canCreateDirectories = NO;
  panel.allowsMultipleSelection = NO; panel.showsHiddenFiles = YES;
  panel.directoryURL = root; panel.prompt = @"Continue";
  panel.message = [NSString stringWithFormat:@"Select the %@ folder to let Talaria find %@ profiles. Cookies and local storage are imported only when you click Import.",root.lastPathComponent,browser[@"name"]];
  self.busy = YES;
  __weak typeof(self) weakSelf = self;
  [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    typeof(self) owner = weakSelf; if(!owner || owner.isClosed) return;
    owner.busy = NO;
    if(response != NSModalResponseOK) return;
    NSError *error = nil;
    if(![TLBrowserProfileImporter grantAccessToBrowser:browser directoryURL:panel.URL error:&error]) {
      owner.status.stringValue = error.localizedDescription ?: @"Could not access this browser’s profile folder."; return;
    }
    [owner reloadImportSources:nil];
    NSDictionary *updated = owner.importSources[browser[@"bundleID"]];
    if(updated[@"discoveryError"]) owner.status.stringValue = [updated[@"discoveryError"] localizedDescription];
    else if([updated[@"profiles"] count]==1) [owner importProfile:sender];
    else owner.status.stringValue = [updated[@"profiles"] count] ? @"Choose a profile, then click Import." : @"No profile was found. Open the source browser once, then refresh.";
  }];
}
- (void)importProfile:(NSButton *)sender {
  if (self.busy || !self.ready) return;
  NSDictionary *browser = self.importSources[sender.identifier];
  if(browser[@"discoveryError"]) { [self grantImportAccess:sender]; return; }
  NSDictionary *profile = self.profilePickers[sender.identifier].selectedItem.representedObject;
  if (!browser || !profile) return;
  self.busy = YES; self.status.stringValue = [NSString stringWithFormat:@"Importing %@ — %@…",browser[@"name"],profile[@"name"]];
  __weak typeof(self) weakSelf = self;
  [self.preferences importProfile:profile fromBrowser:browser completion:^(NSString *message) {
    typeof(self) owner = weakSelf; if (!owner || owner.isClosed) return;
    owner.busy = NO; owner.status.stringValue = message;
  }];
}
- (void)refreshControls {
  for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
    NSString *identifier = setting[@"id"], *type = setting[@"type"];
    NSDictionary *state = [self.preferences stateForSetting:setting]; NSControl *control = self.controls[identifier];
    control.enabled = self.ready && [state[@"available"] boolValue];
    control.toolTip = control.enabled ? setting[@"detail"] : state[@"reason"];
    id value = state[@"value"] ?: setting[@"default"];
    if ([type isEqual:@"bool"]) [(NSSwitch *)control setState:[value boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
    else if ([type isEqual:@"choice"]) {
      NSUInteger index = [setting[@"values"] indexOfObject:value];
      NSPopUpButton *popup = (id)control;
      if (index != NSNotFound) [popup selectItemAtIndex:index];
      else { NSString *title = [NSString stringWithFormat:@"Current: %@",value]; if (![popup itemWithTitle:title]) [popup addItemWithTitle:title]; [popup selectItemWithTitle:title]; }
    } else if ([type isEqual:@"font"]) [(NSPopUpButton *)control selectItemWithTitle:value];
    else [(NSTextField *)control setStringValue:[value isKindOfClass:NSString.class] ? value : [value description]];
  }
  for (TLThemedButton *button in self.buttons) button.enabled = self.ready && (button.tag == 1 || !self.controls[button.identifier] || self.controls[button.identifier].enabled);
  [self refreshDefaultBrowser];
}
- (void)change:(NSControl *)sender {
  if (!self.ready || self.busy) return;
  NSDictionary *setting = [TLBrowserPreferences settingWithID:sender.identifier]; NSControl *control = self.controls[sender.identifier];
  NSString *type = setting[@"type"]; id value;
  if ([type isEqual:@"bool"]) value = @([(NSSwitch *)control state] == NSControlStateValueOn);
  else if ([type isEqual:@"choice"]) {
    NSInteger index = [(NSPopUpButton *)control indexOfSelectedItem];
    if (index < 0 || index >= (NSInteger)[setting[@"values"] count]) return; value = setting[@"values"][index];
  } else if ([type isEqual:@"font"]) value = [(NSPopUpButton *)control titleOfSelectedItem];
  else value = [(NSTextField *)control stringValue];
  NSError *error = nil;
  if (![self.preferences saveValue:value forSetting:setting error:&error]) {
    self.status.stringValue = error.localizedDescription ?: @"Could not save this browser setting.";
    // Keep text drafts for correction. Restore toggles/menus to the value that actually saved.
    if ([@[@"bool",@"choice",@"font"] containsObject:type]) {
      id saved = [self.preferences stateForSetting:setting][@"value"] ?: setting[@"default"];
      if ([type isEqual:@"bool"]) [(NSSwitch *)control setState:[saved boolValue]];
      else if ([type isEqual:@"font"]) [(NSPopUpButton *)control selectItemWithTitle:saved];
      else { NSUInteger index = [setting[@"values"] indexOfObject:saved]; if (index != NSNotFound) [(NSPopUpButton *)control selectItemAtIndex:index]; }
    }
    return;
  }
  self.status.stringValue = [sender.identifier isEqual:@"hardwareAcceleration"] ? @"Saved. Restart Talaria to apply hardware acceleration." : @"Saved to Talaria’s browser.";
}
- (void)chooseFolder:(NSButton *)sender {
  NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseFiles = NO; panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES; panel.allowsMultipleSelection = NO;
  panel.directoryURL = [NSURL fileURLWithPath:[(NSTextField *)self.controls[sender.identifier] stringValue]];
  __weak typeof(self) weakSelf = self;
  [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    typeof(self) owner = weakSelf; if (!owner || owner.isClosed || response != NSModalResponseOK) return;
    [(NSTextField *)owner.controls[sender.identifier] setStringValue:panel.URL.path]; [owner change:sender];
  }];
}
- (void)confirmDataAction:(NSButton *)sender {
  if (self.busy || !self.ready || !self.view.window || self.view.window.attachedSheet) return;
  NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = [[sender.title stringByReplacingOccurrencesOfString:@"…" withString:@""] stringByAppendingString:@"?"];
  NSDictionary *row;
  for (NSDictionary *candidate in self.extraRows) if ([candidate[@"row"] isDescendantOf:self.rows] && [sender isDescendantOf:candidate[@"row"]]) row = candidate;
  alert.informativeText = row[@"detail"] ?: @"This affects only Talaria’s browser profile.";
  [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:[sender.title stringByReplacingOccurrencesOfString:@"…" withString:@""]];
  __weak typeof(self) weakSelf = self;
  [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    typeof(self) owner = weakSelf; if (!owner || owner.isClosed || response != NSAlertSecondButtonReturn) return;
    owner.busy = YES; sender.enabled = NO; owner.status.stringValue = @"Updating browser data…";
    void (^completion)(NSError *) = ^(NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) owner = weakSelf; if (!owner || owner.isClosed) return;
      owner.busy = NO; sender.enabled = YES;
      owner.status.stringValue = error.localizedDescription ?: @"Browser data updated.";
      if (!error && [sender.identifier isEqual:@"reset"]) [owner refreshControls];
    }); };
    if ([sender.identifier isEqual:@"reset"]) { NSError *error; [owner.preferences resetDefaults:&error]; completion(error); }
    else [owner.preferences clearData:sender.identifier completion:completion];
  }];
}
- (void)setSelectedCategoryIndex:(NSInteger)selectedCategoryIndex {
  if (selectedCategoryIndex < 0 || selectedCategoryIndex >= (NSInteger)TLBrowserPreferences.categories.count) return;
  _selectedCategoryIndex = selectedCategoryIndex;
  self.search.stringValue = @"";
  [self filter:nil];
  NSScrollView *scroll = self.search.enclosingScrollView;
  [scroll.contentView scrollToPoint:NSZeroPoint];
  [scroll reflectScrolledClipView:scroll.contentView];
}
- (void)filter:(id)sender {
  NSString *query = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *category = TLBrowserPreferences.categories[self.selectedCategoryIndex];
  NSUInteger count = 0;
  for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@",setting[@"title"],setting[@"detail"],setting[@"category"]];
    BOOL show = query.length ? [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound : [setting[@"category"] isEqual:category];
    self.cards[setting[@"id"]].hidden = !show; if (show) count++;
  }
  for (NSDictionary *row in self.extraRows) {
    BOOL show = query.length ? [row[@"search"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound : [row[@"category"] isEqual:category];
    [row[@"row"] setHidden:!show]; if (show) count++;
  }
  self.empty.hidden = count > 0;
}
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object == self.search) [self filter:nil]; }
- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  for (TLThemedButton *button in self.buttons) button.palette = palette;
}
- (void)close {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [super close]; self.search.delegate = nil;
  for (NSControl *control in self.controls.allValues) { control.target = nil; }
  for (TLThemedButton *button in self.buttons) button.target = nil;
}
@end
