#import "TLToolStatusPill.h"
#import <QuartzCore/QuartzCore.h>

@interface TLToolStatusPill ()
@property NSTextField *avatarLabel;
@property NSTextField *activityLabel;
@property NSTextField *shimmerLabel;
@property CAGradientLayer *shimmerMask;
@property NSTimer *shimmerTimer;
@property CFTimeInterval shimmerStart;
@end
@implementation TLToolStatusPill
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    _avatarLabel = [NSTextField labelWithString:@""];
    _activityLabel = [NSTextField labelWithString:@""];
    for (NSTextField *label in @[_avatarLabel, _activityLabel]) {
      label.translatesAutoresizingMaskIntoConstraints = NO;
      [self addSubview:label];
    }
    _activityLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_activityLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _shimmerLabel = [NSTextField labelWithString:@""];
    _shimmerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _shimmerLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _shimmerLabel.accessibilityElement = NO;
    _shimmerLabel.wantsLayer = YES;
    [self addSubview:_shimmerLabel];
    _shimmerMask = [CAGradientLayer layer];
    _shimmerMask.startPoint = CGPointMake(0, 0.5);
    _shimmerMask.endPoint = CGPointMake(1, 0.5);
    _shimmerLabel.layer.mask = _shimmerMask;
    [NSLayoutConstraint activateConstraints:@[
      [_shimmerLabel.leadingAnchor constraintEqualToAnchor:_activityLabel.leadingAnchor],
      [_shimmerLabel.trailingAnchor constraintEqualToAnchor:_activityLabel.trailingAnchor],
      [_shimmerLabel.topAnchor constraintEqualToAnchor:_activityLabel.topAnchor],
      [_shimmerLabel.bottomAnchor constraintEqualToAnchor:_activityLabel.bottomAnchor],
    ]];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(displayOptionsChanged:)
      name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    CGFloat pad = self.palette.space5;
    [NSLayoutConstraint activateConstraints:@[
      [_avatarLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
      [_avatarLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_activityLabel.leadingAnchor constraintEqualToAnchor:_avatarLabel.trailingAnchor constant:pad],
      [_activityLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-pad * 2],
      [_activityLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [self.heightAnchor constraintEqualToConstant:self.palette.space9 * 2],
    ]];
    self.hidden = YES;
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.layer.backgroundColor = palette.secondaryActionSurface.CGColor;
  self.layer.cornerRadius = palette.space9;
  self.avatarLabel.font = palette.bodyFont;
  self.avatarLabel.textColor = palette.secondaryActionText;
  self.activityLabel.font = palette.smallFont;
  self.shimmerLabel.font = palette.smallFont;
  self.shimmerLabel.textColor = palette.secondaryActionText;
  self.shimmerMask.colors = @[(id)palette.transparentSurface.CGColor,
    (id)palette.secondaryActionText.CGColor, (id)palette.transparentSurface.CGColor];
  [self updateShimmer];
}
- (void)displayOptionsChanged:(NSNotification *)notification { [self updateShimmer]; }
- (void)dealloc { [_shimmerTimer invalidate]; [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self]; }
- (void)layout {
  [super layout];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.shimmerMask.frame = self.shimmerLabel.bounds;
  [CATransaction commit];
  [self updateShimmer];
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateShimmer]; }
- (void)setHidden:(BOOL)hidden { [super setHidden:hidden]; [self updateShimmer]; }
- (void)updateShimmer {
  BOOL animate = self.window && !self.hidden && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  self.shimmerLabel.hidden = !animate;
  self.activityLabel.textColor = animate ? self.palette.textMuted : self.palette.secondaryActionText;
  if (!animate) {
    [self.shimmerTimer invalidate];
    self.shimmerTimer = nil;
    return;
  }
  if (self.shimmerTimer) return;
  self.shimmerStart = CACurrentMediaTime();
  __weak typeof(self) weakSelf = self;
  self.shimmerTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *timer) {
    TLToolStatusPill *pill = weakSelf;
    if (!pill) { [timer invalidate]; return; }
    if (pill.isHiddenOrHasHiddenAncestor) return;
    CGFloat phase = fmod(CACurrentMediaTime() - pill.shimmerStart, 2.0) / 2.0;
    CGFloat center = -0.3 + phase * 1.6;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    pill.shimmerMask.locations = @[@(center - 0.3), @(center), @(center + 0.3)];
    [CATransaction commit];
  }];
  [NSRunLoop.mainRunLoop addTimer:self.shimmerTimer forMode:NSRunLoopCommonModes];
}
+ (NSString *)labelForToolName:(NSString *)name {
  NSString *key = name.lowercaseString;
  if ([key hasPrefix:@"web_"] || [key hasPrefix:@"browser"]) return @"Browsing web";
  if ([key containsString:@"search"]) return @"Searching";
  if ([key containsString:@"fetch"] || [key containsString:@"query"]) return @"Fetching data";
  if ([key isEqual:@"run_host_command"]) return @"Running command on your Mac";
  if ([key containsString:@"terminal"] || [key containsString:@"shell"]) return @"Running command";
  if ([key containsString:@"read"] && [key containsString:@"file"]) return @"Reading file";
  if ([key containsString:@"write"] || [key containsString:@"patch"] || [key containsString:@"edit"]) return @"Editing file";
  if ([key containsString:@"image"]) return @"Working with images";
  NSString *readable = [[name stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  return readable.length ? [@"Using " stringByAppendingString:readable] : @"Working";
}
- (void)setAvatar:(NSString *)avatar activity:(NSDictionary *)activity {
  self.avatarLabel.stringValue = avatar.length ? avatar : @"🤖";
  self.activityLabel.stringValue = [self.class labelForToolName:activity[@"name"] ?: @""];
  self.shimmerLabel.stringValue = self.activityLabel.stringValue;
  self.accessibilityElement = YES;
  self.accessibilityLabel = self.activityLabel.stringValue;
  self.toolTip = self.activityLabel.stringValue;
  [self updateShimmer];
}
@end
