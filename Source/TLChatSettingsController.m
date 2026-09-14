#import "TLChatSettingsController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLModelDropdown.h"
#import "design_system/TLThinkingSlider.h"

@interface TLChatSettingsController () <NSPopoverDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLAgentOrchestrator *orchestrator;
@property (nonatomic) NSInteger agentID;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *supportingModel;
@property (nonatomic, copy) NSString *reasoningEffort;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *thinkingDrafts;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSStackView *body;
@property (nonatomic, strong) TLModelDropdown *modelDropdown;
@property (nonatomic, strong) TLModelDropdown *supportingDropdown;
@property (nonatomic, strong) TLThinkingSlider *thinkingSlider;
@property (nonatomic, strong) NSTextField *thinkingValue;
@property (nonatomic, strong) NSTextField *thinkingNote;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSStackView *tickLabels;
@property (nonatomic, copy) NSArray<NSString *> *sliderLevels;
@property (nonatomic, strong) TLThemedButton *saveButton;
@property (nonatomic, strong) TLThemedButton *cancelButton;
@property (nonatomic, strong) TLThemedButton *refreshButton;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL dismissed;
@end

@implementation TLChatSettingsController
- (instancetype)initWithModel:(NSString *)model supportingModel:(NSString *)supportingModel
             reasoningEffort:(NSString *)reasoningEffort agentID:(NSInteger)agentID token:(NSString *)token
                orchestrator:(TLAgentOrchestrator *)orchestrator palette:(TLThemePalette *)palette {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _model = [model copy]; _supportingModel = [supportingModel copy]; _reasoningEffort = [reasoningEffort copy];
    _agentID = agentID; _token = [token copy]; _orchestrator = orchestrator; _palette = palette;
    _thinkingDrafts = [NSMutableDictionary dictionary]; _sliderLevels = @[];
  }
  return self;
}
- (NSTextField *)label:(NSString *)text {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.font = self.palette.labelFont;
  label.textColor = self.palette.labelText;
  return label;
}
- (void)loadView {
  TLThemePalette *p = self.palette;
  self.view = [[TLTokenView alloc] initWithFrame:NSMakeRect(0, 0, p.settingsSheetWidth / 2, p.fieldHeight * 12)];
  self.modelDropdown = [TLModelDropdown new];
  self.modelDropdown.selectedModelID = self.model;
  self.modelDropdown.accessibilityLabel = @"Large model";
  self.supportingDropdown = [TLModelDropdown new];
  self.supportingDropdown.selectedModelID = self.supportingModel;
  self.supportingDropdown.accessibilityLabel = @"Small model";
  self.thinkingValue = [self label:@""];
  self.thinkingValue.alignment = NSTextAlignmentRight;
  NSView *spacer = [NSView new];
  NSStackView *thinkingHeading = [NSStackView stackViewWithViews:@[[self label:@"Thinking"], spacer, self.thinkingValue]];
  [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.thinkingSlider = [TLThinkingSlider new];
  self.thinkingSlider.target = self;
  self.thinkingSlider.action = @selector(thinkingChanged:);
  self.tickLabels = [NSStackView new];
  self.tickLabels.distribution = NSStackViewDistributionEqualCentering;
  self.thinkingNote = [self label:@""];
  self.thinkingNote.font = p.bodyFont;
  self.statusLabel = [self label:@"Loading models…"];
  self.statusLabel.font = p.bodyFont;
  self.saveButton = [TLThemedButton buttonWithTitle:@"Save" target:self action:@selector(save:)];
  self.saveButton.primary = YES;
  self.saveButton.keyEquivalent = @"\r";
  self.cancelButton = [TLThemedButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
  self.cancelButton.keyEquivalent = @"\033";
  self.refreshButton = [TLThemedButton buttonWithTitle:@"Refresh" target:self action:@selector(reload:)];
  NSStackView *actions = [NSStackView stackViewWithViews:@[self.refreshButton, [NSView new], self.cancelButton, self.saveButton]];
  actions.spacing = p.space5;
  self.body = [NSStackView stackViewWithViews:@[[self label:@"Chat settings"], [self label:@"Large model"],
    self.modelDropdown, thinkingHeading, self.thinkingSlider, self.tickLabels, self.thinkingNote,
    [self label:@"Small model"], self.supportingDropdown, self.statusLabel, actions]];
  self.body.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.body.alignment = NSLayoutAttributeLeading;
  self.body.spacing = p.space5;
  [self.body setCustomSpacing:p.space8 afterView:self.body.arrangedSubviews.firstObject];
  self.body.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:self.body];
  for (NSView *view in @[self.modelDropdown, self.supportingDropdown, thinkingHeading, self.thinkingSlider,
                         self.tickLabels, self.thinkingNote, self.statusLabel, actions]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;
  }
  [NSLayoutConstraint activateConstraints:@[
    [self.body.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:p.space8],
    [self.body.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-p.space8],
    [self.body.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:p.space8],
    [self.body.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-p.space8],
    [self.thinkingSlider.heightAnchor constraintEqualToConstant:p.fieldHeight],
  ]];
  __weak typeof(self) weakSelf = self;
  self.modelDropdown.selectionHandler = ^{
    typeof(self) owner = weakSelf;
    if (!owner) return;
    owner.model = owner.modelDropdown.selectedModelID;
    owner.reasoningEffort = owner.thinkingDrafts[owner.model] ?: @"";
    [owner updateThinking]; [owner updateControls];
  };
  self.supportingDropdown.selectionHandler = ^{ [weakSelf updateControls]; };
  [self updateThinking];
  [self applyPalette:p];
  [self updateControls];
}
- (void)presentRelativeToView:(NSView *)anchor {
  self.dismissed = NO;
  self.popover = [NSPopover new];
  self.popover.behavior = NSPopoverBehaviorSemitransient;
  self.popover.delegate = self;
  self.popover.contentViewController = self;
  self.popover.appearance = self.view.appearance;
  [self sizeToFit];
  [self.popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
  [self reload:nil];
}
- (void)sizeToFit {
  [self.view layoutSubtreeIfNeeded];
  self.preferredContentSize = NSMakeSize(self.palette.settingsSheetWidth / 2,
    ceil(self.body.fittingSize.height + self.palette.space8 * 2));
  self.popover.contentSize = self.preferredContentSize;
}
- (void)reload:(id)sender {
  if (self.saving) return;
  NSUInteger generation = ++self.generation;
  self.loading = YES;
  self.statusLabel.stringValue = @"Loading models…";
  self.statusLabel.hidden = NO;
  [self updateControls]; [self sizeToFit];
  __weak typeof(self) weakSelf = self;
  [self.orchestrator fetchModelCatalogueWithAgentID:self.agentID token:self.token completion:^(NSArray<TLAgentModel *> *models, NSError *error) {
    typeof(self) owner = weakSelf;
    if (!owner || owner.dismissed || owner.generation != generation) return;
    owner.loading = NO;
    if (error) {
      owner.statusLabel.stringValue = error.localizedDescription;
      owner.modelDropdown.models = @[];
      owner.supportingDropdown.models = @[];
    } else {
      owner.modelDropdown.models = models;
      owner.supportingDropdown.models = models;
      owner.statusLabel.stringValue = models.count ? @"" : @"No models available. Check your provider setup.";
      owner.statusLabel.hidden = models.count > 0;
    }
    [owner updateThinking]; [owner updateControls]; [owner sizeToFit];
  }];
}
- (void)updateThinking {
  TLAgentModel *model = self.modelDropdown.selectedModel;
  NSArray *levels = model.thinkingLevels ?: @[];
  if (levels.count && ![levels containsObject:self.reasoningEffort]) self.reasoningEffort = model.defaultThinkingLevel;
  if (levels.count) {
    self.model = model.modelID;
    self.thinkingDrafts[self.model] = self.reasoningEffort;
  }
  self.sliderLevels = TLThinkingSliderLevels(levels, self.reasoningEffort);
  self.thinkingSlider.minValue = 0;
  self.thinkingSlider.maxValue = MAX((NSInteger)self.sliderLevels.count - 1, 1);
  self.thinkingSlider.numberOfTickMarks = self.sliderLevels.count;
  NSUInteger index = [self.sliderLevels indexOfObject:self.reasoningEffort];
  self.thinkingSlider.integerValue = index == NSNotFound ? 0 : index;
  self.thinkingSlider.enabled = !self.loading && !self.saving && self.sliderLevels.count > 1;
  self.thinkingValue.stringValue = levels.count ? TLThinkingLevelTitle(self.reasoningEffort) : @"Unavailable";
  self.thinkingSlider.accessibilityValueDescription = self.thinkingValue.stringValue;
  self.thinkingNote.stringValue = !levels.count ? (model.thinkingUnavailableReason ?: @"Select a model to see its thinking levels.") :
    levels.count == 1 ? @"This model has one thinking level." : @"Higher thinking levels can take longer.";
  for (NSView *view in self.tickLabels.arrangedSubviews.copy) { [self.tickLabels removeArrangedSubview:view]; [view removeFromSuperview]; }
  for (NSString *level in self.sliderLevels) {
    NSTextField *label = [self label:TLThinkingLevelTitle(level)];
    label.font = self.palette.smallFont;
    label.textColor = self.palette.textMuted;
    label.alignment = NSTextAlignmentCenter;
    [self.tickLabels addArrangedSubview:label];
  }
  self.tickLabels.hidden = !levels.count;
  [self sizeToFit];
}
- (void)thinkingChanged:(id)sender {
  NSInteger index = self.thinkingSlider.integerValue;
  if (!self.thinkingSlider.enabled || index < 0 || index >= (NSInteger)self.sliderLevels.count) return;
  self.reasoningEffort = self.sliderLevels[index];
  self.thinkingDrafts[self.model] = self.reasoningEffort;
  self.thinkingValue.stringValue = TLThinkingLevelTitle(self.reasoningEffort);
  self.thinkingSlider.accessibilityValueDescription = self.thinkingValue.stringValue;
}
- (void)updateControls {
  BOOL available = !self.loading && !self.saving;
  self.modelDropdown.enabled = available && self.modelDropdown.models.count;
  self.supportingDropdown.enabled = available && self.supportingDropdown.models.count;
  self.saveButton.enabled = available && self.modelDropdown.selectedModel && self.supportingDropdown.selectedModel;
  self.refreshButton.enabled = available;
  self.cancelButton.enabled = !self.saving;
  NSString *missingSelection = @"Choose an available large and small model.";
  if (available && self.modelDropdown.models.count && !self.saveButton.enabled) {
    self.statusLabel.stringValue = missingSelection;
    self.statusLabel.hidden = NO;
  } else if ([self.statusLabel.stringValue isEqual:missingSelection]) self.statusLabel.hidden = YES;
  self.thinkingSlider.enabled = available && self.sliderLevels.count > 1;
}
- (void)save:(id)sender {
  if (!self.saveButton.enabled || !self.selectionHandler) return;
  self.saving = YES;
  self.statusLabel.hidden = NO;
  self.statusLabel.stringValue = @"Saving chat settings…";
  [self updateControls]; [self sizeToFit];
  __weak typeof(self) weakSelf = self;
  NSString *effort = self.reasoningEffort ?: @"";
  self.selectionHandler(self.modelDropdown.selectedModel.modelID, self.supportingDropdown.selectedModel.modelID, effort, ^(NSError *error) {
    typeof(self) owner = weakSelf;
    if (!owner) return;
    owner.saving = NO;
    if (error) {
      owner.statusLabel.stringValue = error.localizedDescription;
      [owner updateControls]; [owner sizeToFit];
    } else [owner cancel:nil];
  });
}
- (void)cancel:(id)sender {
  if (self.saving) return;
  self.dismissed = YES; self.generation++;
  [self.popover close];
}
- (void)cancelOperation:(id)sender { [self cancel:sender]; }
- (BOOL)popoverShouldClose:(NSPopover *)popover { return !self.saving; }
- (void)popoverDidClose:(NSNotification *)notification {
  self.dismissed = YES; self.generation++; self.popover = nil;
  if (self.closeHandler) self.closeHandler();
}
- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  if (!self.isViewLoaded) return;
  self.view.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.popover.appearance = self.view.appearance;
  ((TLTokenView *)self.view).fillColor = palette.tabBackground;
  NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:self.view];
  while (views.count) {
    NSView *view = views.lastObject; [views removeLastObject]; [views addObjectsFromArray:view.subviews];
    if ([view isKindOfClass:NSTextField.class]) ((NSTextField *)view).textColor = palette.labelText;
    if ([view isKindOfClass:TLThemedButton.class]) ((TLThemedButton *)view).palette = palette;
  }
  self.thinkingNote.textColor = palette.textMuted;
  self.statusLabel.textColor = palette.textMuted;
  self.thinkingSlider.palette = palette;
  for (NSTextField *label in self.tickLabels.arrangedSubviews) label.textColor = palette.textMuted;
}
@end
