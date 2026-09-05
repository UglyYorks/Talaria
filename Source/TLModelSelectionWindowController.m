#import "TLModelSelectionWindowController.h"
#import "design_system/ModelPickerView.h"
#import "design_system/TLThemedButton.h"

@interface TLModelSelectionWindowController ()
@property (nonatomic, strong) TLAgentOrchestrator *orchestrator;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLTokenView *surface;
@property (nonatomic, strong) TLTokenView *footer;
@property (nonatomic, strong) NSImageView *symbol;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) TLModelPickerView *picker;
@property (nonatomic, strong) TLThemedButton *cancelButton;
@property (nonatomic, strong) TLThemedButton *switchButton;
@property (nonatomic, strong) TLThemedButton *reloadButton;
@property (nonatomic) NSUInteger requestGeneration;
@property (nonatomic) BOOL dismissed;
@property (nonatomic) BOOL switchingModel;
@end

@implementation TLModelSelectionWindowController
- (instancetype)initWithSmallModel:(BOOL)small selectedModel:(NSString *)model
                            token:(NSString *)token orchestrator:(TLAgentOrchestrator *)orchestrator
                          palette:(TLThemePalette *)palette {
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 620)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
    backing:NSBackingStoreBuffered defer:NO];
  panel.releasedWhenClosed = NO;
  panel.title = small ? @"Small model" : @"Large model";
  panel.titleVisibility = NSWindowTitleHidden;
  panel.titlebarAppearsTransparent = YES;
  self = [super initWithWindow:panel];
  if (!self) return nil;
  _orchestrator = orchestrator;
  _token = [token copy];
  _palette = palette;
  _surface = [[TLTokenView alloc] init];
  panel.contentView = _surface;
  _symbol = [[NSImageView alloc] init];
  _symbol.image = [NSImage imageWithSystemSymbolName:small ? @"sparkle" : @"brain" accessibilityDescription:nil];
  _symbol.imageScaling = NSImageScaleProportionallyUpOrDown;
  _titleLabel = [NSTextField labelWithString:small ? @"Choose a small model" : @"Choose a large model"];
  _descriptionLabel = [NSTextField wrappingLabelWithString:small
    ? @"Choose an OpenRouter model for chat icons."
    : @"Choose an OpenRouter model for replies. Changes apply to your next message in this chat."];
  _picker = [[TLModelPickerView alloc] initWithTitle:@"OpenRouter models" palette:palette selectedModelID:model];
  _footer = [[TLTokenView alloc] init];
  _footer.borderEdges = TLBorderEdgeTop;
  _cancelButton = [self button:@"Cancel" action:@selector(cancel:)];
  _cancelButton.keyEquivalent = @"\e";
  _switchButton = [self button:@"Switch model" action:@selector(switchModel:)];
  _switchButton.primary = YES;
  _switchButton.keyEquivalent = @"\r";
  _switchButton.enabled = NO;
  _reloadButton = [self button:@"Refresh" action:@selector(loadCatalogue:)];
  for (NSView *view in @[_symbol, _titleLabel, _descriptionLabel, _picker, _footer]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [_surface addSubview:view];
  }
  for (NSView *view in @[_cancelButton, _switchButton, _reloadButton]) [_footer addSubview:view];
  CGFloat padding = palette.space12;
  [NSLayoutConstraint activateConstraints:@[
    [_symbol.topAnchor constraintEqualToAnchor:_surface.topAnchor constant:padding],
    [_symbol.centerXAnchor constraintEqualToAnchor:_surface.centerXAnchor],
    [_symbol.widthAnchor constraintEqualToConstant:palette.composerButtonHeight * 1.5],
    [_symbol.heightAnchor constraintEqualToAnchor:_symbol.widthAnchor],
    [_titleLabel.topAnchor constraintEqualToAnchor:_symbol.bottomAnchor constant:palette.space8],
    [_titleLabel.leadingAnchor constraintEqualToAnchor:_surface.leadingAnchor constant:padding],
    [_titleLabel.trailingAnchor constraintEqualToAnchor:_surface.trailingAnchor constant:-padding],
    [_descriptionLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:palette.space4],
    [_descriptionLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
    [_descriptionLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
    [_picker.topAnchor constraintEqualToAnchor:_descriptionLabel.bottomAnchor constant:palette.space8],
    [_picker.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
    [_picker.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
    [_picker.bottomAnchor constraintEqualToAnchor:_footer.topAnchor constant:-palette.space8],
    [_footer.leadingAnchor constraintEqualToAnchor:_surface.leadingAnchor],
    [_footer.trailingAnchor constraintEqualToAnchor:_surface.trailingAnchor],
    [_footer.bottomAnchor constraintEqualToAnchor:_surface.bottomAnchor],
    [_footer.heightAnchor constraintEqualToConstant:palette.settingsActionHeight + palette.space8 * 2],
    [_switchButton.trailingAnchor constraintEqualToAnchor:_footer.trailingAnchor constant:-padding],
    [_switchButton.centerYAnchor constraintEqualToAnchor:_footer.centerYAnchor],
    [_cancelButton.trailingAnchor constraintEqualToAnchor:_switchButton.leadingAnchor constant:-palette.space5],
    [_cancelButton.centerYAnchor constraintEqualToAnchor:_switchButton.centerYAnchor],
    [_reloadButton.leadingAnchor constraintEqualToAnchor:_footer.leadingAnchor constant:padding],
    [_reloadButton.centerYAnchor constraintEqualToAnchor:_switchButton.centerYAnchor],
  ]];
  __weak typeof(self) weakSelf = self;
  _picker.selectionChangeHandler = ^(NSString *selected) { weakSelf.switchButton.enabled = selected.length > 0; };
  [self applyPalette:palette];
  return self;
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [[TLThemedButton alloc] init];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.title = title;
  button.target = self;
  button.action = action;
  button.palette = self.palette;
  return button;
}
- (void)presentForWindow:(NSWindow *)window {
  self.dismissed = NO;
  [window beginSheet:self.window completionHandler:nil];
  [self.picker focusSearch];
  [self loadCatalogue:nil];
}
- (void)loadCatalogue:(id)sender {
  NSUInteger generation = ++self.requestGeneration;
  self.reloadButton.enabled = NO;
  self.switchButton.enabled = NO;
  self.picker.userInteractionEnabled = NO;
  [self.picker setStatusText:@"Loading OpenRouter models…"];
  __weak typeof(self) weakSelf = self;
  [self.orchestrator fetchModelCatalogueWithToken:self.token completion:^(NSArray<TLAgentModel *> *models, NSError *error) {
    typeof(self) controller = weakSelf;
    if (!controller || controller.dismissed || generation != controller.requestGeneration) return;
    controller.reloadButton.enabled = YES;
    if (error) {
      [controller.picker setStatusText:error.localizedDescription ?: @"Could not load models. Try Refresh."];
      return;
    }
    [controller.picker setModels:models];
    controller.picker.userInteractionEnabled = YES;
    controller.switchButton.enabled = controller.picker.hasSelectableModel;
    [controller.picker setStatusText:models.count
      ? [NSString stringWithFormat:@"%lu OpenRouter models", (unsigned long)models.count]
      : @"No OpenRouter models available. Check your provider setup."];
  }];
}
- (void)switchModel:(id)sender {
  if (!self.switchButton.enabled || !self.picker.hasSelectableModel || !self.selectionHandler) return;
  self.switchingModel = YES;
  self.switchButton.enabled = NO;
  self.cancelButton.enabled = NO;
  self.reloadButton.enabled = NO;
  self.picker.userInteractionEnabled = NO;
  [self.picker setStatusText:@"Applying model selection…"];
  __weak typeof(self) weakSelf = self;
  self.selectionHandler(self.picker.selectedModelID, ^(NSError *error) {
    typeof(self) controller = weakSelf;
    if (!controller) return;
    controller.switchingModel = NO;
    controller.cancelButton.enabled = YES;
    controller.reloadButton.enabled = YES;
    controller.picker.userInteractionEnabled = YES;
    controller.switchButton.enabled = controller.picker.hasSelectableModel;
    if (error) {
      [controller.picker setStatusText:error.localizedDescription];
      return;
    }
    [controller cancel:nil];
  });
}
- (void)cancel:(id)sender {
  if (self.switchingModel) return;
  self.dismissed = YES;
  self.requestGeneration += 1;
  [self.window.sheetParent endSheet:self.window];
  [self.window orderOut:nil];
}
- (void)cancelOperation:(id)sender { [self cancel:sender]; }
- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.tabBackground;
  self.surface.fillColor = palette.tabBackground;
  self.footer.fillColor = palette.controlSurface;
  self.footer.borderColor = palette.controlBorder;
  self.footer.borderWidth = palette.borderWidth;
  self.symbol.contentTintColor = palette.primaryActionSurface;
  self.titleLabel.font = palette.titleFont;
  self.titleLabel.textColor = palette.appText;
  self.descriptionLabel.font = palette.bodyFont;
  self.descriptionLabel.textColor = palette.textMuted;
  [self.picker updatePalette:palette];
  for (TLThemedButton *button in @[self.cancelButton, self.switchButton, self.reloadButton]) button.palette = palette;
}
@end
