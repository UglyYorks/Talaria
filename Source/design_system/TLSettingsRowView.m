#import "TLSettingsRowView.h"
@interface TLSettingsRowView ()
@property TLThemePalette *palette;
@property NSStackView *columns;
@property NSArray<NSLayoutConstraint *> *stackedConstraints;
@property NSLayoutConstraint *equalColumns;
@property BOOL stacked;
@end
@implementation TLSettingsRowView
- (instancetype)initWithSummary:(NSView *)summary controls:(NSView *)controls palette:(TLThemePalette *)palette {
  self = [super init];
  if (!self) return nil;
  _palette = palette;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  _columns = [NSStackView stackViewWithViews:@[summary, controls]];
  _columns.translatesAutoresizingMaskIntoConstraints = NO;
  _columns.spacing = palette.space12;
  _columns.alignment = NSLayoutAttributeNotAnAttribute;
  _columns.orientation = NSUserInterfaceLayoutOrientationVertical;
  _columns.alignment = NSLayoutAttributeLeading;
  _stacked = YES;
  [self addSubview:_columns];
  _equalColumns = [summary.widthAnchor constraintEqualToAnchor:controls.widthAnchor];
  _stackedConstraints = @[[summary.widthAnchor constraintEqualToAnchor:_columns.widthAnchor],
                         [controls.widthAnchor constraintEqualToAnchor:_columns.widthAnchor]];
  [NSLayoutConstraint activateConstraints:_stackedConstraints];
  [NSLayoutConstraint activateConstraints:@[
    [_columns.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space8],
    [_columns.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space8],
    [_columns.topAnchor constraintEqualToAnchor:self.topAnchor constant:palette.space8],
    [_columns.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-palette.space8],
  ]];
  return self;
}
- (void)layout {
  BOOL stacked = NSWidth(self.bounds) < self.palette.settingsCompactWidth;
  if (self.stacked != stacked) {
    self.stacked = stacked;
    self.equalColumns.active = !stacked;
    if (stacked) [NSLayoutConstraint activateConstraints:self.stackedConstraints];
    else [NSLayoutConstraint deactivateConstraints:self.stackedConstraints];
    self.columns.alignment = NSLayoutAttributeNotAnAttribute;
    self.columns.distribution = stacked ? NSStackViewDistributionFill : NSStackViewDistributionFillEqually;
    self.columns.orientation = stacked ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    self.columns.alignment = stacked ? NSLayoutAttributeLeading : NSLayoutAttributeTop;
  }
  [super layout];
}
@end
