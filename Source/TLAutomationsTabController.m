#import "TLAutomationsTabController.h"
#import "UIComponents.h"
#import "design_system/TLThemedButton.h"

static NSString *TLAutomationText(id value) {
  if (!value || value == NSNull.null) return @"";
  if ([value isKindOfClass:NSString.class]) return value;
  return [value description];
}

@interface TLAutomationsTabController () <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate, NSTextViewDelegate>
@property (nonatomic, copy) TLAutomationRequest request;
@property (nonatomic, copy) NSArray<TLAgentRecord *> *agents;
@property (nonatomic) NSInteger agentID;
@property (nonatomic, strong) NSPopUpButton *agentPicker;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSStackView *detail;
@property (nonatomic, strong) NSStackView *advanced;
@property (nonatomic, strong) NSStackView *report;
@property (nonatomic, strong) NSStackView *body;
@property (nonatomic, strong) NSScrollView *bodyScroll;
@property (nonatomic) BOOL layingOutDocument;
@property (nonatomic, strong) TLThemedButton *schedulerButton;
@property (nonatomic, strong) TLThemedButton *saveButton;
@property (nonatomic, strong) NSHashTable<TLThemedButton *> *buttons;
@property (nonatomic, copy) NSArray<NSDictionary *> *jobs;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleJobs;
@property (nonatomic, copy) NSArray<NSDictionary *> *fields;
@property (nonatomic, copy) NSDictionary *scheduler;
@property (nonatomic, copy, nullable) NSString *selectedID;
@property (nonatomic, copy) NSDictionary *originalValues;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *editors;
@property (nonatomic) BOOL creating;
@property (nonatomic) BOOL dirty;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL selecting;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation TLAutomationsTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette agents:(NSArray<TLAgentRecord *> *)agents
                        agentID:(NSInteger)agentID request:(TLAutomationRequest)request {
  self = [super initWithPalette:palette];
  if (self) {
    _agents = agents;
    _agentID = agentID;
    _request = [request copy];
    _buttons = [NSHashTable weakObjectsHashTable];
    _jobs = @[]; _fields = @[]; _visibleJobs = @[];
    _editors = [NSMutableDictionary dictionary];
    [self buildView];
    [self applyPalette:palette];
    __weak typeof(self) weakSelf = self;
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(NSTimer *timer) {
      typeof(self) controller = weakSelf;
      if (!controller) { [timer invalidate]; return; }
      if (controller.view.window.isVisible && !controller.view.isHiddenOrHasHiddenAncestor &&
          !controller.dirty && !controller.creating && controller.report.arrangedSubviews.count == 0) [controller refresh:nil];
    }];
  }
  return self;
}

- (void)close {
  [super close];
  self.generation++;
  [self.refreshTimer invalidate];
  self.refreshTimer = nil;
  self.request = nil;
}
- (void)dealloc { [_refreshTimer invalidate]; }

- (NSStackView *)stack:(NSUserInterfaceLayoutOrientation)orientation {
  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = orientation;
  stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
  stack.spacing = self.palette.space8;
  return stack;
}
- (void)add:(NSView *)view to:(NSStackView *)stack fill:(BOOL)fill {
  [stack addArrangedSubview:view];
  if (fill) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.palette = self.palette;
  button.enabled = !self.busy;
  [self.buttons addObject:button];
  return button;
}
- (void)clear:(NSStackView *)stack {
  for (NSView *view in stack.arrangedSubviews.copy) { [stack removeArrangedSubview:view]; [view removeFromSuperview]; }
}
- (NSScrollView *)scrollFor:(NSView *)document {
  NSScrollView *scroll = [[NSScrollView alloc] init];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = YES;
  scroll.autohidesScrollers = YES;
  scroll.drawsBackground = NO;
  scroll.documentView = document;
  return scroll;
}
- (void)buildView {
  TLTokenView *root = [[TLTokenView alloc] init];
  [self bindColorForObject:root keyPath:@"fillColor" token:@"tabBackground"];
  self.view = root;
  NSStackView *body = [self stack:NSUserInterfaceLayoutOrientationVertical];
  self.body = body;
  // Keep document sizing independent of the window's Auto Layout minimum.
  // Narrow windows scroll the toolbar/form instead of inheriting their width.
  body.translatesAutoresizingMaskIntoConstraints = YES;
  body.spacing = self.palette.space12;
  NSScrollView *scroll = [self scrollFor:body];
  self.bodyScroll = scroll;
  [root addSubview:scroll];
  CGFloat inset = self.palette.space16;
  [NSLayoutConstraint activateConstraints:@[
    [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:inset],
    [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-inset],
    [scroll.topAnchor constraintEqualToAnchor:root.topAnchor constant:inset],
    [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-inset]
  ]];
  [self add:[self labelWithString:@"Automations" font:self.palette.titleFont colorToken:@"appText"] to:body fill:NO];
  [self add:[self wrappingLabelWithString:@"Schedule work for Hermes. Review results and manage every run in one place."
    font:self.palette.bodyFont colorToken:@"textMuted"] to:body fill:YES];

  NSStackView *agentRow = [self stack:NSUserInterfaceLayoutOrientationHorizontal];
  [agentRow addArrangedSubview:[self labelWithString:@"Agent" font:self.palette.labelFont colorToken:@"labelText"]];
  self.agentPicker = [[NSPopUpButton alloc] init];
  self.agentPicker.font = self.palette.bodyFont;
  self.agentPicker.target = self; self.agentPicker.action = @selector(changeAgent:);
  for (TLAgentRecord *agent in self.agents) {
    [self.agentPicker addItemWithTitle:agent.name];
    self.agentPicker.lastItem.representedObject = @(agent.agentID);
    if (agent.agentID == self.agentID) [self.agentPicker selectItem:self.agentPicker.lastItem];
  }
  if (!self.agentPicker.numberOfItems) [self.agentPicker addItemWithTitle:@"No agents configured"];
  [agentRow addArrangedSubview:self.agentPicker];
  [self add:agentRow to:body fill:NO];

  self.statusLabel = [self wrappingLabelWithString:@"Loading scheduler status…" font:self.palette.smallFont colorToken:@"textMuted"];
  [self add:self.statusLabel to:body fill:YES];
  NSStackView *actions = [self stack:NSUserInterfaceLayoutOrientationHorizontal];
  TLThemedButton *newButton = [self button:@"New automation" action:@selector(newAutomation:)];
  newButton.primary = YES;
  [actions addArrangedSubview:newButton];
  [actions addArrangedSubview:[self button:@"Refresh" action:@selector(refresh:)]];
  self.schedulerButton = [self button:@"Start scheduler" action:@selector(toggleScheduler:)];
  [actions addArrangedSubview:self.schedulerButton];
  [actions addArrangedSubview:[self button:@"Diagnostics" action:@selector(diagnostics:)]];
  [actions addArrangedSubview:[self button:@"Incidents" action:@selector(incidents:)]];
  [self add:actions to:body fill:NO];
  self.messageLabel = [self wrappingLabelWithString:@"" font:self.palette.bodyFont colorToken:@"labelText"];
  [self add:self.messageLabel to:body fill:YES];
  self.searchField = [[NSSearchField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.placeholderString = @"Search automations";
  self.searchField.delegate = self;
  [self bindColorForObject:self.searchField keyPath:@"textColor" token:@"controlText"];
  [self bindColorForObject:self.searchField keyPath:@"backgroundColor" token:@"controlSurface"];
  [self add:self.searchField to:body fill:YES];

  self.table = [[NSTableView alloc] init];
  self.table.dataSource = self; self.table.delegate = self;
  self.table.rowHeight = self.palette.fieldHeight + self.palette.space4;
  self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  [self bindColorForObject:self.table keyPath:@"backgroundColor" token:@"tabBackground"];
  [self bindColorForObject:self.table keyPath:@"gridColor" token:@"controlBorder"];
  for (NSArray *definition in @[@[@"name", @"Automation", @(self.palette.controlMinWidth * 2)],
                                @[@"schedule", @"Schedule", @(self.palette.controlMinWidth * 2)],
                                @[@"state", @"State", @(self.palette.controlMinWidth)],
                                @[@"next_run_at", @"Next run", @(self.palette.controlMinWidth * 2)]]) {
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:definition[0]];
    column.title = definition[1]; column.width = [definition[2] doubleValue];
    [self.table addTableColumn:column];
  }
  NSScrollView *tableScroll = [self scrollFor:self.table];
  [tableScroll.heightAnchor constraintEqualToConstant:self.table.rowHeight * 4 + self.palette.fieldHeight].active = YES;
  [self add:tableScroll to:body fill:YES];
  self.detail = [self stack:NSUserInterfaceLayoutOrientationVertical];
  [self add:self.detail to:body fill:YES];
  self.report = [self stack:NSUserInterfaceLayoutOrientationVertical];
  [self add:self.report to:body fill:YES];
  [self renderDetail];
}

- (void)viewDidLayout {
  [super viewDidLayout];
  [self layoutDocument];
}
- (void)layoutDocument {
  if (self.layingOutDocument || !self.bodyScroll) return;
  self.layingOutDocument = YES;
  NSClipView *clip = self.bodyScroll.contentView;
  CGFloat topOffset = MAX(0, NSHeight(self.body.bounds) - NSMaxY(clip.bounds));
  CGFloat minimum = 0;
  for (NSView *view in self.body.arrangedSubviews) {
    if ([view isKindOfClass:NSStackView.class] && [(NSStackView *)view orientation] == NSUserInterfaceLayoutOrientationHorizontal)
      minimum = MAX(minimum, view.fittingSize.width);
  }
  CGFloat width = MAX(self.bodyScroll.contentSize.width, minimum);
  NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:self.body];
  while (queue.count) {
    NSView *view = queue.lastObject; [queue removeLastObject];
    if ([view isKindOfClass:NSTextField.class]) {
      NSTextField *field = (NSTextField *)view;
      [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
      if (field.maximumNumberOfLines == 0 && !field.usesSingleLineMode) field.preferredMaxLayoutWidth = width;
    }
    [queue addObjectsFromArray:view.subviews];
  }
  self.body.frame = NSMakeRect(0, 0, width, self.body.fittingSize.height);
  [self.body layoutSubtreeIfNeeded];
  self.body.frame = NSMakeRect(0, 0, width, self.body.fittingSize.height);
  [self.body layoutSubtreeIfNeeded];
  [clip scrollToPoint:NSMakePoint(NSMinX(clip.bounds), MAX(0, NSHeight(self.body.bounds) - NSHeight(clip.bounds) - topOffset))];
  [self.bodyScroll reflectScrolledClipView:clip];
  self.layingOutDocument = NO;
}

- (void)setBusy:(BOOL)busy {
  _busy = busy;
  for (TLThemedButton *button in self.buttons) button.enabled = !busy;
  self.agentPicker.enabled = !busy && self.agents.count > 0;
  self.table.enabled = !busy;
  for (NSView *editor in self.editors.allValues) {
    if ([editor isKindOfClass:NSTextView.class]) [(NSTextView *)editor setEditable:!busy];
    else if ([editor isKindOfClass:NSControl.class]) [(NSControl *)editor setEnabled:!busy];
  }
  self.schedulerButton.enabled = !busy && self.scheduler != nil && ![self.scheduler[@"external"] boolValue] &&
    [self.scheduler[@"provider"] isEqual:@"builtin"];
}
- (void)perform:(NSDictionary *)parameters completion:(void (^)(NSDictionary *))completion {
  if (self.busy || self.closed || !self.request) return;
  if (self.agentID <= 0) { self.messageLabel.stringValue = @"Create an agent in Agents before scheduling work."; return; }
  self.busy = YES;
  if (![parameters[@"action"] isEqual:@"list"]) self.messageLabel.stringValue = @"Working with Hermes…";
  NSUInteger generation = ++self.generation;
  __weak typeof(self) weakSelf = self;
  self.request(self.agentID, parameters, ^(NSDictionary *result, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) controller = weakSelf;
      if (!controller || controller.closed || controller.generation != generation) return;
      controller.busy = NO;
      if (error) { controller.messageLabel.stringValue = error.localizedDescription; [controller layoutDocument]; return; }
      if (!result) { controller.messageLabel.stringValue = @"Hermes returned no automation data."; return; }
      completion(result);
      [controller layoutDocument];
    });
  });
}
- (void)refresh:(id)sender {
  [self perform:@{@"action": @"list"} completion:^(NSDictionary *result) {
    if (![result[@"jobs"] isKindOfClass:NSArray.class] || ![result[@"fields"] isKindOfClass:NSArray.class]) {
      self.messageLabel.stringValue = @"Hermes returned invalid automation data. Update Hermes and retry."; return;
    }
    self.jobs = result[@"jobs"]; self.fields = result[@"fields"]; self.scheduler = result[@"scheduler"];
    [self renderScheduler];
    [self filterJobs];
    if (!self.dirty && !self.creating) [self renderDetail];
  }];
}
- (void)renderScheduler {
  BOOL running = [self.scheduler[@"running"] boolValue];
  NSString *where = [self.scheduler[@"external"] boolValue] ? @"Hermes gateway" : @"agent VM";
  self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@ · %@%@",
    self.jobs.count, self.jobs.count == 1 ? @"automation" : @"automations", running ? [NSString stringWithFormat:@"Scheduler running in %@. Jobs run while the VM is awake.", where]
                            : @"Scheduler stopped. Start it to run jobs on schedule.",
    TLAutomationText(self.scheduler[@"error"]).length ? [@"\n" stringByAppendingString:TLAutomationText(self.scheduler[@"error"])] : @""];
  self.schedulerButton.title = [self.scheduler[@"owned"] boolValue] ? @"Stop scheduler" : @"Start scheduler";
  self.busy = self.busy;
  [self layoutDocument];
}
- (void)filterJobs {
  NSString *query = self.searchField.stringValue;
  self.visibleJobs = query.length ? [self.jobs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *job, NSDictionary *bindings) {
    return [[NSString stringWithFormat:@"%@ %@ %@", job[@"name"], job[@"schedule"], job[@"state"]] localizedCaseInsensitiveContainsString:query];
  }]] : self.jobs;
  self.selecting = YES;
  [self.table reloadData];
  NSInteger index = [self.visibleJobs indexOfObjectPassingTest:^BOOL(NSDictionary *job, NSUInteger idx, BOOL *stop) {
    return [job[@"job_id"] isEqual:self.selectedID];
  }];
  if (index != NSNotFound) [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
  else [self.table deselectAll:nil];
  self.selecting = NO;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleJobs.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  return [self labelWithString:TLAutomationText(self.visibleJobs[row][column.identifier]) font:self.palette.bodyFont colorToken:@"appText"];
}
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
  TLHistoryRowView *view = [[TLHistoryRowView alloc] init];
  view.palette = self.palette;
  return view;
}
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView { return !self.busy; }
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (self.selecting || self.busy) return;
  NSInteger row = self.table.selectedRow;
  if (row < 0 || row >= (NSInteger)self.visibleJobs.count) return;
  NSString *next = self.visibleJobs[row][@"job_id"];
  if ([next isEqual:self.selectedID] && !self.creating) return;
  [self discardIfNeeded:^{ self.selectedID = next; self.creating = NO; [self renderDetail]; }];
}
- (void)discardIfNeeded:(void (^)(void))action {
  if (!self.dirty) { action(); return; }
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Discard unsaved changes?";
  alert.informativeText = @"Your automation has not been saved yet.";
  [alert addButtonWithTitle:@"Keep editing"]; [alert addButtonWithTitle:@"Discard changes"];
  [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    if (self.closed) return;
    if (response == NSAlertSecondButtonReturn) { self.dirty = NO; action(); }
    else [self filterJobs];
  }];
}
- (void)changeAgent:(id)sender {
  NSInteger agentID = [self.agentPicker.selectedItem.representedObject integerValue];
  for (NSMenuItem *item in self.agentPicker.itemArray) if ([item.representedObject integerValue] == self.agentID) [self.agentPicker selectItem:item];
  [self discardIfNeeded:^{
    self.agentID = agentID;
    for (NSMenuItem *item in self.agentPicker.itemArray) if ([item.representedObject integerValue] == agentID) [self.agentPicker selectItem:item];
    self.jobs = @[]; self.fields = @[]; self.scheduler = nil; self.selectedID = nil; self.creating = NO;
    self.messageLabel.stringValue = @""; [self clear:self.report];
    [self filterJobs]; [self renderDetail]; [self refresh:nil];
  }];
}
- (void)controlTextDidChange:(NSNotification *)notification {
  if (notification.object == self.searchField) [self filterJobs];
  else self.dirty = YES;
}
- (void)textDidChange:(NSNotification *)notification { self.dirty = YES; }
- (void)fieldChanged:(id)sender { self.dirty = YES; }
- (NSDictionary *)selectedJob {
  for (NSDictionary *job in self.jobs) if ([job[@"job_id"] isEqual:self.selectedID]) return job;
  return nil;
}
- (void)newAutomation:(id)sender {
  if (!self.fields.count) { self.messageLabel.stringValue = @"Load Hermes scheduling capabilities with Refresh first."; return; }
  [self discardIfNeeded:^{ self.selectedID = nil; self.creating = YES; [self filterJobs]; [self renderDetail]; }];
}
- (void)renderDetail {
  [self clear:self.detail]; [self clear:self.report]; [self.editors removeAllObjects];
  self.dirty = NO;
  NSDictionary *job = [self selectedJob];
  if (!self.creating && !job) {
    [self add:[self wrappingLabelWithString:self.jobs.count ? @"Select an automation to view its instructions, settings, and run history."
      : @"No automations yet. Create one to schedule a recurring task or a one-time reminder."
      font:self.palette.bodyFont colorToken:@"textMuted"] to:self.detail fill:YES];
    [self layoutDocument];
    return;
  }
  self.originalValues = self.creating ? @{} : job[@"values"] ?: @{};
  [self add:[self labelWithString:self.creating ? @"New automation" : TLAutomationText(job[@"name"])
    font:self.palette.labelFont colorToken:@"appText"] to:self.detail fill:YES];
  if (job) {
    NSString *metadata = [NSString stringWithFormat:@"%@ · %@\nNext run: %@\nLast run: %@ · %@%@",
      TLAutomationText(job[@"job_id"]), TLAutomationText(job[@"state"]), TLAutomationText(job[@"next_run_at"]),
      TLAutomationText(job[@"last_run_at"]), TLAutomationText(job[@"last_status"]),
      TLAutomationText(job[@"last_error"]).length ? [@"\n" stringByAppendingString:TLAutomationText(job[@"last_error"])] : @""];
    [self add:[self wrappingLabelWithString:metadata font:self.palette.smallFont colorToken:@"textMuted"] to:self.detail fill:YES];
    NSStackView *actions = [self stack:NSUserInterfaceLayoutOrientationHorizontal];
    [actions addArrangedSubview:[self button:@"Run now" action:@selector(runNow:)]];
    [actions addArrangedSubview:[self button:[job[@"enabled"] boolValue] ? @"Pause" : @"Resume" action:@selector(pauseResume:)]];
    [actions addArrangedSubview:[self button:@"Run history" action:@selector(runs:)]];
    [actions addArrangedSubview:[self button:@"Notepad" action:@selector(notes:)]];
    [actions addArrangedSubview:[self button:@"Delete" action:@selector(deleteAutomation:)]];
    [self add:actions to:self.detail fill:NO];
  }
  for (NSString *key in @[@"name", @"schedule", @"prompt", @"deliver"]) {
    for (NSDictionary *field in self.fields) if ([field[@"key"] isEqual:key]) [self addField:field to:self.detail];
  }
  [self add:[self wrappingLabelWithString:@"Schedules use the Hermes timezone. Examples: every 2h · weekdays at 9am · in 30m · 0 9 * * * · 2026-12-01T09:00:00+10:00. Delivery “local” saves results in Hermes."
    font:self.palette.smallFont colorToken:@"textMuted"] to:self.detail fill:YES];
  [self add:[self button:@"Advanced options ▸" action:@selector(toggleAdvanced:)] to:self.detail fill:NO];
  self.advanced = [self stack:NSUserInterfaceLayoutOrientationVertical];
  for (NSDictionary *field in self.fields) if (![@[@"name", @"schedule", @"prompt", @"deliver"] containsObject:field[@"key"]]) [self addField:field to:self.advanced];
  [self add:self.advanced to:self.detail fill:YES];
  self.advanced.hidden = YES;
  NSStackView *saveRow = [self stack:NSUserInterfaceLayoutOrientationHorizontal];
  self.saveButton = [self button:self.creating ? @"Create automation" : @"Save changes" action:@selector(save:)];
  self.saveButton.primary = YES;
  [saveRow addArrangedSubview:self.saveButton];
  [saveRow addArrangedSubview:[self button:@"Cancel" action:@selector(cancelEdit:)]];
  [self add:saveRow to:self.detail fill:NO];
  [self layoutDocument];
}
- (void)addField:(NSDictionary *)field to:(NSStackView *)stack {
  NSString *key = field[@"key"], *kind = field[@"type"];
  NSString *title = [@{@"prompt": @"Instructions", @"repeat": @"Run limit (0 = forever)", @"deliver": @"Delivery target",
    @"failure_deliver": @"Failure delivery target", @"no_agent": @"Script only (skip AI)", @"context_from": @"Context from jobs",
    @"continuity": @"Include previous run", @"attach_to_session": @"Allow replies to deliveries", @"workdir": @"Working directory",
    @"enabled_toolsets": @"Enabled toolsets", @"base_url": @"Provider base URL"} objectForKey:key] ?: [[key stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
  [self add:[self labelWithString:title font:self.palette.smallFont colorToken:@"labelText"] to:stack fill:YES];
  id original = self.originalValues[key];
  NSView *editor;
  if ([kind isEqual:@"boolean"]) {
    NSPopUpButton *popup = [[NSPopUpButton alloc] init];
    BOOL unset = !original || original == NSNull.null;
    if (unset) [popup addItemWithTitle:@"Default"];
    [popup addItemWithTitle:@"On"]; popup.lastItem.representedObject = @YES;
    [popup addItemWithTitle:@"Off"]; popup.lastItem.representedObject = @NO;
    [popup selectItemWithTitle:unset ? @"Default" : [original boolValue] ? @"On" : @"Off"];
    popup.target = self; popup.action = @selector(fieldChanged:); popup.font = self.palette.bodyFont;
    editor = popup;
  } else if ([key isEqual:@"prompt"]) {
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, self.palette.controlMinWidth, self.palette.fieldHeight * 4)];
    text.richText = NO; text.font = self.palette.bodyFont; text.delegate = self;
    text.string = TLAutomationText(original);
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.widthTracksTextView = YES;
    text.horizontallyResizable = NO; text.verticallyResizable = YES;
    [self bindColorForObject:text keyPath:@"textColor" token:@"controlText"];
    [self bindColorForObject:text keyPath:@"backgroundColor" token:@"controlSurface"];
    [self bindColorForObject:text keyPath:@"insertionPointColor" token:@"controlText"];
    NSScrollView *scroll = [self scrollFor:text]; scroll.hasHorizontalScroller = NO;
    [scroll.heightAnchor constraintEqualToConstant:self.palette.fieldHeight * 4].active = YES;
    [self add:scroll to:stack fill:YES];
    editor = text;
  } else {
    NSTextField *text = [[NSTextField alloc] init];
    text.font = self.palette.bodyFont; text.delegate = self;
    text.stringValue = [original isKindOfClass:NSArray.class] ? [original componentsJoinedByString:@", "] : TLAutomationText(original);
    if (self.creating && [key isEqual:@"deliver"]) text.stringValue = @"local";
    text.placeholderString = [kind isEqual:@"array"] ? @"Comma-separated names" : [key isEqual:@"schedule"] ? @"every day at 9am" : @"Optional";
    [self bindColorForObject:text keyPath:@"textColor" token:@"controlText"];
    [self bindColorForObject:text keyPath:@"backgroundColor" token:@"controlSurface"];
    editor = text;
  }
  editor.toolTip = field[@"description"];
  [editor setAccessibilityLabel:title];
  editor.identifier = key;
  self.editors[key] = editor;
  if (![key isEqual:@"prompt"]) { editor.translatesAutoresizingMaskIntoConstraints = NO; [self add:editor to:stack fill:YES]; }
}
- (void)toggleAdvanced:(TLThemedButton *)sender {
  self.advanced.hidden = !self.advanced.hidden;
  sender.title = self.advanced.hidden ? @"Advanced options ▸" : @"Advanced options ▾";
  [self layoutDocument];
}
- (void)cancelEdit:(id)sender { [self discardIfNeeded:^{ self.creating = NO; [self renderDetail]; }]; }
- (void)save:(id)sender {
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
  for (NSDictionary *field in self.fields) {
    NSString *key = field[@"key"], *kind = field[@"type"];
    NSView *editor = self.editors[key]; if (!editor) continue;
    id original = self.originalValues[key];
    if (original == NSNull.null) original = nil;
    id value;
    if ([editor isKindOfClass:NSPopUpButton.class]) {
      value = [(NSPopUpButton *)editor selectedItem].representedObject;
      if (!value) continue;
    } else {
      NSString *raw = [editor isKindOfClass:NSTextView.class] ? [(NSTextView *)editor string] : [(NSTextField *)editor stringValue];
      if (![key isEqual:@"prompt"]) raw = [raw stringByTrimmingCharactersInSet:whitespace];
      if ([kind isEqual:@"array"]) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *part in [raw componentsSeparatedByString:@","]) {
          NSString *item = [part stringByTrimmingCharactersInSet:whitespace]; if (item.length) [items addObject:item];
        }
        value = items;
      } else if ([kind isEqual:@"integer"]) {
        if (!raw.length && !original) continue;
        NSScanner *scanner = [NSScanner scannerWithString:raw]; long long number = 0;
        if (raw.length && (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < 0)) {
          self.messageLabel.stringValue = @"Run limit must be a whole number, 0 for forever, or blank for the default."; return;
        }
        value = @(number);
      } else value = raw;
    }
    if ([value isEqual:original] || (!original && ([value isEqual:@""] || [value isEqual:@[]]))) continue;
    values[key] = value;
  }
  if (self.creating && ![TLAutomationText(values[@"schedule"]) length]) {
    self.messageLabel.stringValue = @"Enter a schedule for this automation."; return;
  }
  if (!self.creating && !values.count) { self.messageLabel.stringValue = @"No changes to save."; return; }
  [self perform:@{@"action": self.creating ? @"create" : @"update", @"job_id": self.selectedID ?: @"", @"values": values}
    completion:^(NSDictionary *result) {
      self.selectedID = result[@"job_id"] ?: result[@"job"][@"job_id"] ?: self.selectedID;
      self.dirty = NO; self.creating = NO;
      self.messageLabel.stringValue = @"Automation saved.";
      [self refresh:nil];
    }];
}
- (void)mutate:(NSString *)action {
  if (!self.selectedID) return;
  [self perform:@{@"action": action, @"job_id": self.selectedID} completion:^(NSDictionary *result) {
    self.messageLabel.stringValue = [action isEqual:@"run"] ? @"Run requested. Open run history to check the outcome." : @"Automation updated.";
    if ([action isEqual:@"remove"]) { self.selectedID = nil; self.dirty = NO; }
    [self refresh:nil];
  }];
}
- (void)runNow:(id)sender { [self mutate:@"run"]; }
- (void)pauseResume:(id)sender { [self mutate:[[self selectedJob][@"enabled"] boolValue] ? @"pause" : @"resume"]; }
- (void)deleteAutomation:(id)sender {
  if (!self.selectedID) return;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = [NSString stringWithFormat:@"Delete “%@”?", [self selectedJob][@"name"]];
  alert.informativeText = @"This permanently removes the scheduled job from Hermes.";
  [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Delete automation"];
  [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
    if (!self.closed && response == NSAlertSecondButtonReturn) [self mutate:@"remove"];
  }];
}
- (void)toggleScheduler:(id)sender {
  [self perform:@{@"action": @"scheduler", @"enabled": @(![self.scheduler[@"owned"] boolValue])}
    completion:^(NSDictionary *result) { self.scheduler = result[@"scheduler"]; [self renderScheduler]; }];
}
- (void)showReport:(NSString *)title text:(NSString *)text {
  [self clear:self.report];
  [self add:[self labelWithString:title font:self.palette.labelFont colorToken:@"appText"] to:self.report fill:YES];
  NSTextField *body = [self wrappingLabelWithString:text font:self.palette.bodyFont colorToken:@"controlText"];
  body.selectable = YES;
  [self add:body to:self.report fill:YES];
  [self layoutDocument];
  [self.report scrollRectToVisible:self.report.bounds];
}
- (void)runs:(id)sender {
  [self perform:@{@"action": @"runs", @"job_id": self.selectedID} completion:^(NSDictionary *result) {
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *run in result[@"runs"]) {
      [text appendFormat:@"%@ · %@\n%@%@\n\n", TLAutomationText(run[@"claimed_at"]), TLAutomationText(run[@"status"]),
        TLAutomationText(run[@"id"]), TLAutomationText(run[@"error"]).length ? [@"\n" stringByAppendingString:TLAutomationText(run[@"error"])] : @""];
    }
    [self showReport:@"Run history · latest 100 attempts" text:text.length ? text : @"No runs recorded yet."];
    for (NSDictionary *output in result[@"outputs"]) {
      TLThemedButton *button = [self button:output[@"name"] action:@selector(openOutput:)];
      button.identifier = output[@"name"];
      [self add:button to:self.report fill:NO];
    }
  }];
}
- (void)openOutput:(NSButton *)sender {
  [self perform:@{@"action": @"output", @"job_id": self.selectedID, @"name": sender.identifier} completion:^(NSDictionary *result) {
    [self showReport:@"Run output" text:TLAutomationText(result[@"text"])];
  }];
}
- (void)diagnostics:(id)sender {
  [self perform:@{@"action": @"doctor"} completion:^(NSDictionary *result) {
    NSMutableString *text = [NSMutableString stringWithString:@"Schedule and script checks\n\n"];
    BOOL found = NO;
    for (NSDictionary *job in result[@"issues"]) if ([job[@"issues"] count]) {
      found = YES; [text appendFormat:@"%@\n%@\n\n", job[@"name"], [job[@"issues"] componentsJoinedByString:@"\n"]];
    }
    if (!found) [text appendString:@"No job configuration issues found."];
    [self showReport:@"Diagnostics" text:text];
  }];
}
- (void)incidents:(id)sender {
  [self perform:@{@"action": @"incidents"} completion:^(NSDictionary *result) { [self renderIncidents:result]; }];
}
- (void)renderIncidents:(NSDictionary *)result {
  [self showReport:@"Incidents" text:[result[@"incidents"] count] ? @"Failures reported by Hermes" : @"No incidents recorded."];
  for (NSDictionary *incident in result[@"incidents"]) {
    [self add:[self wrappingLabelWithString:[NSString stringWithFormat:@"%@ · %@\n%@", TLAutomationText(incident[@"job_name"]),
      TLAutomationText(incident[@"state"]), TLAutomationText(incident[@"error"])] font:self.palette.bodyFont colorToken:@"appText"] to:self.report fill:YES];
    if (![incident[@"state"] isEqual:@"closed"]) {
      TLThemedButton *button = [self button:@"Acknowledge" action:@selector(acknowledge:)];
      button.identifier = incident[@"id"]; [self add:button to:self.report fill:NO];
    }
  }
}
- (void)acknowledge:(NSButton *)sender {
  [self perform:@{@"action": @"incidents", @"incident_id": sender.identifier} completion:^(NSDictionary *result) { [self renderIncidents:result]; }];
}
- (void)notes:(id)sender {
  [self perform:@{@"action": @"notes", @"job_id": self.selectedID} completion:^(NSDictionary *result) { [self renderNotes:result]; }];
}
- (void)renderNotes:(NSDictionary *)result {
  [self showReport:@"Notepad" text:@"Persistent notes Hermes can use across runs."];
  for (NSDictionary *note in result[@"notes"]) {
    [self add:[self wrappingLabelWithString:[NSString stringWithFormat:@"%@\n%@", note[@"key"], note[@"value"]]
      font:self.palette.bodyFont colorToken:@"appText"] to:self.report fill:YES];
    TLThemedButton *remove = [self button:@"Delete note" action:@selector(deleteNote:)];
    remove.identifier = note[@"key"]; [self add:remove to:self.report fill:NO];
  }
  for (NSString *key in @[@"noteKey", @"noteValue"]) {
    NSTextField *field = [[NSTextField alloc] init]; field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = [key isEqual:@"noteKey"] ? @"Note key (existing key replaces its value)" : @"Note value";
    field.font = self.palette.bodyFont;
    [self bindColorForObject:field keyPath:@"textColor" token:@"controlText"];
    [self bindColorForObject:field keyPath:@"backgroundColor" token:@"controlSurface"];
    self.editors[key] = field; [self add:field to:self.report fill:YES];
  }
  [self add:[self button:@"Save note" action:@selector(saveNote:)] to:self.report fill:NO];
}
- (void)saveNote:(id)sender {
  NSString *key = [(NSTextField *)self.editors[@"noteKey"] stringValue];
  if (!key.length) { self.messageLabel.stringValue = @"Enter a note key."; return; }
  [self perform:@{@"action": @"notes", @"job_id": self.selectedID, @"operation": @"set", @"key": key,
    @"value": [(NSTextField *)self.editors[@"noteValue"] stringValue]} completion:^(NSDictionary *result) { [self renderNotes:result]; }];
}
- (void)deleteNote:(NSButton *)sender {
  [self perform:@{@"action": @"notes", @"job_id": self.selectedID, @"operation": @"delete", @"key": sender.identifier}
    completion:^(NSDictionary *result) { [self renderNotes:result]; }];
}
- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.view.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  for (TLThemedButton *button in self.buttons) button.palette = palette;
  [self filterJobs];
}
@end
