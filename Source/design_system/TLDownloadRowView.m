#import "TLDownloadRowView.h"
#import "TLThemedButton.h"
#import "TLWrappingActionView.h"

@interface TLDownloadRowView ()
@property NSTextField *nameLabel, *sourceLabel, *statusLabel;
@property NSImageView *iconView;
@property TLWrappingActionView *actions;
@property TLTokenView *progressTrack, *progressFill;
@property TLBrowserDownload *download;
@property TLThemePalette *palette;
@property NSArray<NSString *> *actionNames;
@end
@implementation TLDownloadRowView
- (instancetype)init {
  if ((self = [super init])) {
    TLThemePalette *p = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _nameLabel = [NSTextField labelWithString:@""];
    _sourceLabel = [NSTextField labelWithString:@""];
    _statusLabel = [NSTextField labelWithString:@""];
    _iconView = [[NSImageView alloc] init];
    _iconView.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:@"Downloaded file"];
    _actions = [[TLWrappingActionView alloc] initWithViews:@[] palette:p];
    _progressTrack = [[TLTokenView alloc] init];
    _progressFill = [[TLTokenView alloc] init];
    [_progressTrack addSubview:_progressFill];
    for (NSTextField *label in @[_nameLabel, _sourceLabel, _statusLabel]) {
      label.lineBreakMode = NSLineBreakByTruncatingTail;
      [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    for (NSView *view in @[_nameLabel, _sourceLabel, _statusLabel, _iconView, _actions, _progressTrack]) {
      view.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
      [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:p.space5],
      [_iconView.topAnchor constraintEqualToAnchor:self.topAnchor constant:p.space5],
      [_iconView.widthAnchor constraintEqualToConstant:p.fieldHeight],
      [_iconView.heightAnchor constraintEqualToConstant:p.fieldHeight],
      [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:p.space8],
      [_nameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-p.space5],
      [_nameLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:p.space8],
      [_sourceLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:p.space5],
      [_sourceLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
      [_sourceLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:p.space2],
      [_statusLabel.leadingAnchor constraintEqualToAnchor:_sourceLabel.leadingAnchor],
      [_statusLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
      [_statusLabel.topAnchor constraintEqualToAnchor:_sourceLabel.bottomAnchor constant:p.space4],
      [_progressTrack.leadingAnchor constraintEqualToAnchor:_sourceLabel.leadingAnchor],
      [_progressTrack.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
      [_progressTrack.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:p.space5],
      [_progressTrack.heightAnchor constraintEqualToConstant:p.space2],
      [_actions.leadingAnchor constraintEqualToAnchor:_sourceLabel.leadingAnchor],
      [_actions.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
      [_actions.topAnchor constraintEqualToAnchor:_progressTrack.bottomAnchor constant:p.space5],
      [_actions.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-p.space8],
    ]];
  }
  return self;
}
- (void)configureWithDownload:(TLBrowserDownload *)download palette:(TLThemePalette *)p {
  self.download = download; self.palette = p;
  self.fillColor = p.controlSurface; self.cornerRadius = p.radiusMedium;
  self.nameLabel.stringValue = download.fileName;
  self.nameLabel.font = p.labelFont; self.nameLabel.textColor = p.appText;
  NSString *source = [NSURL URLWithString:download.URLString].host ?: @"Browser download";
  NSString *date = [NSDateFormatter localizedStringFromDate:download.startedAt dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
  self.sourceLabel.stringValue = [NSString stringWithFormat:@"%@ · %@", source, date];
  self.sourceLabel.font = p.smallFont; self.sourceLabel.textColor = p.textMuted;
  self.statusLabel.stringValue = download.statusText; self.statusLabel.toolTip = download.statusText;
  self.statusLabel.font = p.smallFont; self.statusLabel.textColor = p.textMuted;
  self.nameLabel.toolTip = download.path.length ? download.path : download.fileName;
  self.iconView.contentTintColor = p.textMuted;
  self.progressTrack.fillColor = p.controlBorder; self.progressFill.fillColor = p.controlText;
  self.progressTrack.cornerRadius = p.space2 * 0.5; self.progressFill.cornerRadius = p.space2 * 0.5;
  self.progressTrack.hidden = !download.active;
  NSArray *names = download.active ? @[(download.state == TLBrowserDownloadStatePaused ? @"Resume" : @"Pause"), @"Cancel"] :
    download.state == TLBrowserDownloadStateComplete ? @[@"Open", @"Show in Finder", @"Remove"] :
    download.canRetry ? @[@"Retry", @"Remove"] : @[@"Remove"];
  if (![names isEqual:self.actionNames]) {
    self.actionNames = names;
    for (NSView *view in self.actions.subviews.copy) [view removeFromSuperview];
    for (NSString *name in names) {
      TLThemedButton *button = [TLThemedButton buttonWithTitle:name target:self action:@selector(performAction:)];
      button.identifier = name;
      button.translatesAutoresizingMaskIntoConstraints = YES;
      [self.actions addSubview:button];
    }
  }
  for (TLThemedButton *button in self.actions.subviews) {
    button.palette = p;
    button.enabled = download.active ? download.controllable :
      [@[@"Open", @"Show in Finder"] containsObject:button.title] ? download.fileAvailable : YES;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", button.title, download.fileName];
    button.toolTip = [button.title isEqual:@"Remove"] ? @"Remove from this list. The file stays on disk." : nil;
  }
  self.actions.palette = p;
  [self.actions invalidateIntrinsicContentSize];
  self.actions.needsLayout = YES;
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  double fraction = self.download.totalBytes > 0 ? (double)self.download.receivedBytes / self.download.totalBytes : 0;
  NSRect bounds = self.progressTrack.bounds;
  self.progressFill.frame = NSMakeRect(0, 0, NSWidth(bounds) * MAX(0, MIN(1, fraction)), NSHeight(bounds));
}
- (void)performAction:(NSButton *)sender { if (self.actionHandler) self.actionHandler(sender.identifier); }
@end
