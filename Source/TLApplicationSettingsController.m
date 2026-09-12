#import "TLApplicationSettingsController.h"
#import "UIComponents.h"
#import "design_system/TLSettingsRowView.h"
#import "design_system/TLWrappingActionView.h"
#import "design_system/TLShortcutRecorder.h"

@interface TLApplicationSettingsController ()
@property TLApplicationPreferences *preferences;
@property NSSwitch *loginToggle;
@property NSSwitch *notchToggle;
@property NSTextField *loginStatus;
@property NSTextField *shortcutStatus;
@property TLThemedButton *reviewLoginButton;
@property TLThemedButton *clearShortcutButton;
@property TLShortcutRecorder *shortcutRecorder;
@end
@implementation TLApplicationSettingsController
- (instancetype)initWithPalette:(TLThemePalette *)palette preferences:(TLApplicationPreferences *)preferences {
  if (!(self = [super initWithPalette:palette])) return nil;
  _preferences = preferences;
  [self buildContent];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesDidChange:) name:NSApplicationDidBecomeActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesDidChange:) name:TLApplicationPreferencesDidChangeNotification object:preferences];
  [self refresh];
  return self;
}
- (NSStackView *)stack:(NSArray *)views {
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.translatesAutoresizingMaskIntoConstraints = NO; stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading; stack.spacing = self.palette.space8;
  return stack;
}
- (NSView *)row:(NSString *)title detail:(NSString *)detail controls:(NSArray *)controls {
  NSTextField *label = [self wrappingLabelWithString:title font:self.palette.labelFont colorToken:@"appText"];
  NSTextField *description = [self wrappingLabelWithString:detail font:self.palette.bodyFont colorToken:@"textMuted"];
  NSStackView *summary = [self stack:@[label, description]], *fields = [self stack:controls];
  for (NSView *view in summary.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:summary.widthAnchor].active = YES;
  for (NSView *view in controls) if ([view isKindOfClass:NSTextField.class] || [view isKindOfClass:TLWrappingActionView.class])
    [view.widthAnchor constraintEqualToAnchor:fields.widthAnchor].active = YES;
  TLSettingsRowView *row = [[TLSettingsRowView alloc] initWithSummary:summary controls:fields palette:self.palette];
  row.cornerRadius = self.palette.radiusMedium; row.borderWidth = self.palette.borderWidth;
  [self bindColorForObject:row keyPath:@"fillColor" token:@"controlSurface"];
  [self bindColorForObject:row keyPath:@"borderColor" token:@"controlBorder"];
  return row;
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action {
  TLThemedButton *button = [[TLThemedButton alloc] init]; button.title = title; button.palette = self.palette;
  button.target = self; button.action = action; button.translatesAutoresizingMaskIntoConstraints = NO; return button;
}
- (void)buildContent {
  TLTokenView *root = [[TLTokenView alloc] init]; self.view = root;
  [self bindColorForObject:root keyPath:@"fillColor" token:@"tabBackground"];
  self.loginToggle = [[NSSwitch alloc] init]; self.loginToggle.target = self; self.loginToggle.action = @selector(changeLogin:);
  self.loginToggle.accessibilityLabel = @"Launch on system start";
  self.loginStatus = [self wrappingLabelWithString:@"" font:self.palette.smallFont colorToken:@"textMuted"];
  self.reviewLoginButton = [self button:@"Review login item…" action:@selector(reviewLogin:)];
  NSView *login = [self row:@"Launch on system start" detail:@"Open Talaria automatically when you log in to your Mac."
    controls:@[self.loginToggle, self.loginStatus, self.reviewLoginButton]];
  self.notchToggle = [[NSSwitch alloc] init]; self.notchToggle.target = self; self.notchToggle.action = @selector(changeNotch:);
  self.notchToggle.accessibilityLabel = @"Enable notch";
  NSView *notch = [self row:@"Enable notch" detail:@"Show quick input at the top of your screen. Shake the cursor while dragging files to reveal the drop area."
    controls:@[self.notchToggle]];
  self.shortcutRecorder = [[TLShortcutRecorder alloc] init]; self.shortcutRecorder.palette = self.palette;
  self.shortcutRecorder.translatesAutoresizingMaskIntoConstraints = NO;
  __weak typeof(self) weakSelf = self;
  self.shortcutRecorder.recordingHandler = ^(BOOL recording) { weakSelf.preferences.shortcutRecording = recording; };
  self.shortcutRecorder.changeHandler = ^(NSDictionary *shortcut) {
    typeof(self) owner = weakSelf; if (!owner || owner.isClosed) return;
    NSError *error = nil;
    BOOL saved = [owner.preferences setQuickInputShortcut:shortcut error:&error];
    [owner refresh];
    owner.shortcutStatus.stringValue = saved ? (shortcut ? @"Shortcut saved." : @"Shortcut cleared.") : error.localizedDescription;
  };
  self.clearShortcutButton = [self button:@"Clear" action:@selector(clearShortcut:)];
  TLWrappingActionView *actions = [[TLWrappingActionView alloc] initWithViews:@[self.shortcutRecorder, self.clearShortcutButton] palette:self.palette];
  self.shortcutStatus = [self wrappingLabelWithString:@"" font:self.palette.smallFont colorToken:@"textMuted"];
  NSView *shortcut = [self row:@"Notch / main window shortcut" detail:@"Open the notch from any app, or the main window when the notch is off. Click to record a combination; Escape cancels."
    controls:@[actions, self.shortcutStatus]];
  NSStackView *content = [self stack:@[login, notch, shortcut]];
  NSScrollView *scroll = [[NSScrollView alloc] init]; scroll.drawsBackground = NO;
  scroll.translatesAutoresizingMaskIntoConstraints = NO; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES;
  [root addSubview:scroll];
  [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor], [scroll.topAnchor constraintEqualToAnchor:root.topAnchor],
    [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
  TLFlippedView *document = [[TLFlippedView alloc] init]; document.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.documentView = document; [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
  [document addSubview:content];
  NSLayoutConstraint *width = [content.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-self.palette.space12 * 2];
  width.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[[content.centerXAnchor constraintEqualToAnchor:document.centerXAnchor], width,
    [content.widthAnchor constraintLessThanOrEqualToConstant:self.palette.settingsContentMaxWidth],
    [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:document.leadingAnchor constant:self.palette.space8],
    [content.trailingAnchor constraintLessThanOrEqualToAnchor:document.trailingAnchor constant:-self.palette.space8],
    [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:self.palette.space8],
    [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-self.palette.space8]]];
  for (NSView *view in content.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:content.widthAnchor].active = YES;
}
- (void)preferencesDidChange:(NSNotification *)notification { [self refresh]; }
- (void)refresh {
  if (self.isClosed) return;
  SMAppServiceStatus status = self.preferences.loginItemStatus;
  self.loginToggle.state = status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval ? NSControlStateValueOn : NSControlStateValueOff;
  self.reviewLoginButton.hidden = status != SMAppServiceStatusRequiresApproval;
  // NotFound can mean macOS has never seen this login item. Report an error
  // only if the user actually tries to register it and registration fails.
  self.loginStatus.stringValue = status == SMAppServiceStatusRequiresApproval ? @"Allow Talaria in System Settings → Login Items to finish enabling this." : @"";
  self.loginStatus.hidden = !self.loginStatus.stringValue.length;
  self.notchToggle.state = self.preferences.notchEnabled ? NSControlStateValueOn : NSControlStateValueOff;
  self.shortcutRecorder.shortcut = self.preferences.quickInputShortcut;
  self.clearShortcutButton.enabled = self.preferences.quickInputShortcut != nil;
  self.shortcutStatus.stringValue = self.preferences.shortcutError ?: (self.preferences.quickInputShortcut ? @"Available while Talaria is running." : @"No shortcut assigned.");
}
- (void)changeLogin:(NSSwitch *)sender {
  NSError *error = nil; BOOL saved = [self.preferences setLaunchAtLogin:sender.state == NSControlStateValueOn error:&error];
  [self refresh];
  if (!saved) { self.loginStatus.hidden = NO; self.loginStatus.stringValue = error.localizedDescription ?: @"Could not update the login item. Try again."; }
}
- (void)reviewLogin:(id)sender { [SMAppService openSystemSettingsLoginItems]; }
- (void)changeNotch:(NSSwitch *)sender { self.preferences.notchEnabled = sender.state == NSControlStateValueOn; }
- (void)clearShortcut:(id)sender { [self.shortcutRecorder cancelRecording]; self.shortcutRecorder.changeHandler(nil); }
- (void)cancelShortcutRecording { [self.shortcutRecorder cancelRecording]; }
- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.reviewLoginButton.palette = palette; self.clearShortcutButton.palette = palette; self.shortcutRecorder.palette = palette;
}
- (void)close {
  [self cancelShortcutRecording]; [super close];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  self.shortcutRecorder.changeHandler = nil; self.shortcutRecorder.recordingHandler = nil;
  self.loginToggle.target = nil; self.notchToggle.target = nil;
  self.reviewLoginButton.target = nil; self.clearShortcutButton.target = nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
