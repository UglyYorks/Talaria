#import "TLToolActivityView.h"

@implementation TLToolActivityView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.distribution = NSStackViewDistributionFill;
    _activities = @[];
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
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
  [self rebuild];
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
    [self removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.hidden = self.activities.count == 0;
  self.spacing = self.palette.space4;
  NSDictionary *states = @{@"preparing":@"Preparing", @"running":@"Running", @"completed":@"Completed",
    @"failed":@"Failed", @"stopped":@"Stopped", @"interrupted":@"Interrupted", @"paused":@"Paused", @"ended":@"Ended"};
  [self label:@"Tool activity" title:YES];
  for (NSDictionary *activity in self.activities) {
    NSString *title = [NSString stringWithFormat:@"%@ · %@", states[activity[@"state"]] ?: @"Ended", activity[@"name"]];
    [self label:title title:YES];
    for (NSString *key in @[@"detail", @"summary"]) {
      if ([activity[key] length]) [self label:activity[key] title:NO];
    }
  }
}
@end
