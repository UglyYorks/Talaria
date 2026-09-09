#import "TLBookmarkEditorController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLEmojiPicker.h"
#import "design_system/TLThemedButton.h"

@interface TLBookmarkEditorController () <NSTextFieldDelegate>
@property (nonatomic, strong) TLBookmark *bookmark;
@property (nonatomic, strong) NSStackView *body;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *URLField;
@property (nonatomic, strong) NSTextField *destinationLabel;
@property (nonatomic, strong) NSTextField *heading;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) TLEmojiPicker *emojiPicker;
@property (nonatomic, strong) TLThemedButton *saveButton;
@property (nonatomic, strong) TLThemedButton *cancelButton;
@end

@implementation TLBookmarkEditorController
- (instancetype)initWithBookmark:(TLBookmark *)bookmark palette:(TLThemePalette *)palette {
  if ((self = [super initWithNibName:nil bundle:nil])) { _bookmark = bookmark; _palette = palette; }
  return self;
}

- (void)loadView {
  TLThemePalette *p = self.palette;
  self.view = [[TLTokenView alloc] initWithFrame:NSMakeRect(0, 0, p.settingsSheetWidth / 2, p.fieldHeight * 6)];
  self.heading = [NSTextField labelWithString:@"Add bookmark"];
  self.nameField = [NSTextField textFieldWithString:self.bookmark.name];
  self.nameField.placeholderString = @"Name";
  self.nameField.accessibilityLabel = @"Bookmark name";
  self.nameField.delegate = self;
  NSStackView *identity = [NSStackView new];
  identity.spacing = p.space5;
  if (self.bookmark.chatID != 0) {
    self.emojiPicker = [TLEmojiPicker new];
    self.emojiPicker.emoji = self.bookmark.emoji;
    self.emojiPicker.accessibilityLabel = @"Bookmark emoji";
    [identity addArrangedSubview:self.emojiPicker];
    self.destinationLabel = [NSTextField labelWithString:@"conversation"];
  } else {
    self.URLField = [NSTextField textFieldWithString:self.bookmark.URL.absoluteString ?: @""];
    self.URLField.placeholderString = @"https://example.com";
    self.URLField.accessibilityLabel = @"Bookmark URL";
    self.URLField.delegate = self;
  }
  [identity addArrangedSubview:self.nameField];
  self.errorLabel = [NSTextField wrappingLabelWithString:@""];
  self.errorLabel.hidden = YES;
  self.saveButton = [TLThemedButton buttonWithTitle:@"Add bookmark" target:self action:@selector(save:)];
  self.saveButton.primary = YES;
  self.saveButton.keyEquivalent = @"\r";
  self.cancelButton = [TLThemedButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
  self.cancelButton.keyEquivalent = @"\033";
  NSStackView *actions = [NSStackView stackViewWithViews:@[self.cancelButton, self.saveButton]];
  actions.spacing = p.space5;
  NSStackView *body = [NSStackView stackViewWithViews:@[self.heading, identity,
    self.URLField ?: self.destinationLabel, self.errorLabel, actions]];
  self.body = body;
  body.orientation = NSUserInterfaceLayoutOrientationVertical;
  body.distribution = NSStackViewDistributionFill;
  body.alignment = NSLayoutAttributeLeading;
  body.spacing = p.space6;
  body.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:body];
  for (NSView *view in @[identity, self.URLField ?: self.destinationLabel, self.errorLabel]) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [view.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
  }
  for (NSTextField *field in self.URLField ? @[self.nameField, self.URLField] : @[self.nameField]) {
    field.bezelStyle = NSTextFieldRoundedBezel;
    [field.heightAnchor constraintEqualToConstant:p.fieldHeight].active = YES;
  }
  [NSLayoutConstraint activateConstraints:@[
    [body.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:p.space8],
    [body.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-p.space8],
    [body.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:p.space8],
    [body.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-p.space8],

  ]];
  [self applyPalette:p];
  [self updateValidation];
  [self sizeToFitContent];
}

- (void)sizeToFitContent {
  [self.view layoutSubtreeIfNeeded];
  self.preferredContentSize = NSMakeSize(self.palette.settingsSheetWidth / 2,
    ceil(self.body.fittingSize.height + self.palette.space8 * 2));
  [self.view setFrameSize:self.preferredContentSize];
  if (self.contentSizeChangedHandler) self.contentSizeChangedHandler(self.preferredContentSize);
}

- (void)viewDidAppear {
  [super viewDidAppear];
  [self.view.window makeFirstResponder:self.nameField];
  [self.nameField selectText:nil];
}

- (void)controlTextDidChange:(NSNotification *)notification {
  self.errorLabel.hidden = YES;
  [self updateValidation];
  [self sizeToFitContent];
}

- (void)updateValidation {
  self.saveButton.enabled = [self.nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0 &&
    (!self.URLField || [TLBookmark normalizedURL:self.URLField.stringValue] != nil);
}

- (void)save:(id)sender {
  [self updateValidation];
  if (!self.saveButton.enabled) return;
  self.bookmark.name = self.nameField.stringValue;
  if (self.URLField) {
    NSURL *URL = [TLBookmark normalizedURL:self.URLField.stringValue];
    if (![URL.host.lowercaseString isEqual:self.bookmark.URL.host.lowercaseString]) self.bookmark.faviconData = nil;
    self.bookmark.URL = URL;
  } else self.bookmark.emoji = self.emojiPicker.emoji;
  NSError *error = nil;
  if (self.saveHandler && !self.saveHandler(self.bookmark, &error)) {
    self.errorLabel.stringValue = error.localizedDescription ?: @"Could not save bookmark.";
    self.errorLabel.hidden = NO;
    [self sizeToFitContent];
    return;
  }
  if (self.closeHandler) self.closeHandler();
}

- (void)cancel:(id)sender { if (self.closeHandler) self.closeHandler(); }
- (void)cancelOperation:(id)sender { [self cancel:sender]; }

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  if (!self.isViewLoaded) return;
  ((TLTokenView *)self.view).fillColor = palette.controlSurface;
  self.view.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.heading.font = palette.labelFont;
  self.heading.textColor = palette.controlText;
  self.destinationLabel.font = palette.bodyFont;
  self.destinationLabel.textColor = palette.textMuted;
  self.errorLabel.font = palette.smallFont;
  self.errorLabel.textColor = palette.textMuted;
  for (NSTextField *field in self.URLField ? @[self.nameField, self.URLField] : @[self.nameField]) {
    field.font = palette.bodyFont;
    field.textColor = palette.controlText;
    field.backgroundColor = palette.controlSurface;
  }
  self.emojiPicker.palette = palette;
  self.saveButton.palette = palette;
  self.cancelButton.palette = palette;
}
@end
