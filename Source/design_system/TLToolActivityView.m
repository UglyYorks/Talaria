#import "TLToolActivityView.h"
#import "TLThemedButton.h"

@interface TLToolActivityView ()
@property (nonatomic, strong) TLThemedButton *disclosureButton;
@end

@implementation TLToolActivityView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.distribution = NSStackViewDistributionFill;
    _activities = @[];
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _disclosureButton = [[TLThemedButton alloc] init];
    _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureButton.title = @"Tool activity";
    _disclosureButton.imagePosition = NSImageLeft;
    _disclosureButton.target = self;
    _disclosureButton.action = @selector(toggleExpanded:);
    [self addArrangedSubview:_disclosureButton];
    [_disclosureButton.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor].active = YES;
    [self rebuild];
    self.hidden = YES;
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  [self rebuild];
}
- (void)setActivities:(NSArray<NSDictionary<NSString *,NSString *> *> *)activities {
  if ([_activities isEqual:activities]) return;
  _activities = [activities copy] ?: @[];
  if (!_activities.count) _expanded = NO;
  [self rebuild];
}
- (void)setExpanded:(BOOL)expanded {
  if (_expanded == expanded) return;
  _expanded = expanded;
  [self rebuild];
}
- (void)toggleExpanded:(id)sender {
  self.expanded = !self.expanded;
}
- (NSTextField *)label:(NSString *)text title:(BOOL)title {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = title ? self.palette.roleFont : self.palette.smallFont;
  label.textColor = title ? self.palette.labelText : self.palette.textMuted;
  label.selectable = YES;
  label.maximumNumberOfLines = title ? 2 : 4;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  label.toolTip = text;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self addArrangedSubview:label];
  [label.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
  return label;
}
- (void)rebuild {
  for (NSView *view in [self.arrangedSubviews copy]) {
    if (view == self.disclosureButton) continue;
    [self removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.hidden = self.activities.count == 0;
  self.spacing = self.palette.space4;
  self.disclosureButton.palette = self.palette;
  self.disclosureButton.image = [NSImage imageWithSystemSymbolName:self.expanded ? @"chevron.down" : @"chevron.right"
    accessibilityDescription:nil];
  self.disclosureButton.toolTip = self.expanded ? @"Hide tool activity" : @"Show tool activity";
  self.disclosureButton.accessibilityLabel = self.disclosureButton.toolTip;
  self.disclosureButton.accessibilityValue = self.expanded ? @"Expanded" : @"Collapsed";
  if (!self.expanded) return;
  NSDictionary *states = @{@"preparing":@"Preparing", @"running":@"Running", @"completed":@"Completed",
    @"failed":@"Failed", @"stopped":@"Stopped", @"interrupted":@"Interrupted", @"paused":@"Paused", @"ended":@"Ended"};
  for (NSDictionary *activity in self.activities) {
    NSString *title = [NSString stringWithFormat:@"%@ · %@", states[activity[@"state"]] ?: @"Ended", activity[@"name"]];
    [self label:title title:YES];
    for (NSString *key in @[@"detail", @"summary"]) {
      if ([activity[key] length]) [self label:activity[key] title:NO];
    }
  }
}
@end
