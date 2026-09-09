#import "TLNotificationMessageCardView.h"

@implementation TLNotificationMessageCardView
- (instancetype)initWithNotification:(NSDictionary *)notification palette:(TLThemePalette *)palette {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.fillColor = palette.assistantMessageSurface;
    self.borderColor = [notification[@"urgency"] isEqual:@"high"] ? palette.sidebarUrgentNotificationBadgeSurface :
      ([notification[@"urgency"] isEqual:@"medium"] ? palette.sidebarInboxPrimaryBadgeSurface : palette.assistantMessageBorder);
    self.borderEdges = TLBorderEdgeAll;
    self.borderWidth = palette.borderWidth;
    self.cornerRadius = palette.radiusMedium;
    NSStackView *stack = [NSStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = palette.space3;
    [self addSubview:stack];
    NSString *title = [notification[@"title"] isKindOfClass:NSString.class] ? notification[@"title"] : @"Notification";
    NSString *summary = [notification[@"summary"] isKindOfClass:NSString.class] ? notification[@"summary"] : @"";
    NSUInteger labelIndex = 0;
    for (NSString *text in @[title, summary]) {
      if (!text.length) continue;
      NSTextField *label = [NSTextField wrappingLabelWithString:text];
      label.translatesAutoresizingMaskIntoConstraints = NO;
      label.font = labelIndex++ == 0 ? palette.sidebarInboxUnreadTitleFont : palette.messageBodyFont;
      label.textColor = palette.assistantMessageText;
      label.selectable = YES;
      [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
      [stack addArrangedSubview:label];
      [label.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
      [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space5],
      [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space5],
      [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:palette.space5],
      [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-palette.space5],
    ]];
    self.accessibilityLabel = [NSString stringWithFormat:@"Notification, %@ urgency: %@. %@", notification[@"urgency"] ?: @"low", title, summary];
  }
  return self;
}
@end
