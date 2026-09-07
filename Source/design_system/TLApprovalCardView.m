#import "TLApprovalCardView.h"
#import "TLThemedButton.h"

NSArray<NSString *> *TLApprovalChoices(NSDictionary *request) {
  NSArray *choices = [request[@"choices"] isKindOfClass:NSArray.class] ? request[@"choices"] : @[@"once", @"deny"];
  NSMutableOrderedSet *allowed = [NSMutableOrderedSet orderedSet];
  for (id choice in choices) {
    if ([@[@"once", @"session", @"always", @"deny"] containsObject:choice]) [allowed addObject:choice];
  }
  return allowed.array;
}

NSString *TLApprovalChoiceTitle(NSString *choice) {
  return @{@"once":@"Allow once", @"session":@"Allow this session", @"always":@"Always allow", @"deny":@"Deny"}[choice] ?: @"";
}

@interface TLApprovalCardView ()
@property NSDictionary *request;
@property NSStackView *stack;
@property NSStackView *actions;
@property NSTextField *heading;
@property NSTextField *reason;
@property NSTextView *code;
@property NSScrollView *codeScroll;
@property TLThemedButton *expandButton;
@property NSLayoutConstraint *codeHeight;
@property BOOL expanded;
@property BOOL submitted;
@end

@implementation TLApprovalCardView
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  _request = [request copy];
  _submitted = [request[@"submitted"] boolValue];
  _stack = [NSStackView new];
  _stack.translatesAutoresizingMaskIntoConstraints = NO;
  _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  _stack.alignment = NSLayoutAttributeLeading;
  _stack.spacing = palette.space5;
  [self addSubview:_stack];
  [NSLayoutConstraint activateConstraints:@[
    [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:palette.space6],
    [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-palette.space6],
    [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:palette.space6],
    [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-palette.space6]]];
  _heading = [self label:_submitted ? @"Approval response sent" : @"Approval required"];
  _reason = [self label:[request[@"description"] isKindOfClass:NSString.class] && [request[@"description"] length]
    ? request[@"description"] : @"Hermes needs your permission to run this command."];
  [_stack addArrangedSubview:_heading];
  [_stack addArrangedSubview:_reason];
  [_heading.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;
  [_reason.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;

  _codeScroll = [NSScrollView new];
  _codeScroll.translatesAutoresizingMaskIntoConstraints = NO;
  _codeScroll.hasVerticalScroller = YES;
  _code = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
  _code.editable = NO;
  _code.selectable = YES;
  _code.richText = NO;
  _code.verticallyResizable = YES;
  _code.horizontallyResizable = NO;
  _code.autoresizingMask = NSViewWidthSizable;
  _code.textContainer.widthTracksTextView = YES;
  _code.textContainer.containerSize = NSMakeSize(0, CGFLOAT_MAX);
  _code.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
  _code.string = [request[@"command"] isKindOfClass:NSString.class] ? request[@"command"] : @"";
  _codeScroll.documentView = _code;
  [_stack addArrangedSubview:_codeScroll];
  [_codeScroll.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;
  _codeHeight = [_codeScroll.heightAnchor constraintEqualToConstant:0];
  _codeHeight.active = YES;
  _expandButton = [TLThemedButton buttonWithTitle:@"Expand code" target:self action:@selector(toggleCode:)];
  [_stack addArrangedSubview:_expandButton];
  [_expandButton setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [_expandButton.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor].active = YES;

  _actions = [NSStackView new];
  _actions.orientation = NSUserInterfaceLayoutOrientationVertical;
  _actions.alignment = NSLayoutAttributeLeading;
  _actions.spacing = palette.space4;
  [_stack addArrangedSubview:_actions];
  [_actions.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor].active = YES;
  for (NSString *choice in TLApprovalChoices(request)) {
    TLThemedButton *button = [TLThemedButton buttonWithTitle:TLApprovalChoiceTitle(choice) target:self action:@selector(choose:)];
    button.identifier = choice;
    button.primary = [choice isEqual:@"once"];
    button.enabled = !_submitted;
    [button setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_actions addArrangedSubview:button];
  }
  self.palette = palette;
  return self;
}

- (NSTextField *)label:(NSString *)text {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.selectable = YES;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.fillColor = palette.controlSurface;
  self.borderColor = palette.controlBorder;
  self.borderEdges = TLBorderEdgeAll;
  self.borderWidth = palette.borderWidth;
  self.cornerRadius = palette.chipRadius;
  self.heading.font = palette.roleFont;
  self.heading.textColor = palette.assistantMessageText;
  self.reason.font = palette.smallFont;
  self.reason.textColor = palette.assistantMessageText;
  self.code.font = palette.markdownCodeFont;
  self.code.textColor = palette.markdownCodeText;
  self.code.backgroundColor = palette.markdownCodeSurface;
  self.codeScroll.backgroundColor = palette.markdownCodeSurface;
  self.code.textContainerInset = NSMakeSize(palette.space4, palette.space4);
  self.expandButton.palette = palette;
  for (TLThemedButton *button in self.actions.arrangedSubviews) button.palette = palette;
  [self updateCodeHeight];
}

- (void)updateCodeHeight {
  CGFloat lineHeight = ceil(self.palette.markdownCodeFont.ascender - self.palette.markdownCodeFont.descender + self.palette.markdownCodeFont.leading);
  self.codeHeight.constant = lineHeight * (self.expanded ? 18 : 6) + self.palette.space4 * 2;
}

- (void)toggleCode:(id)sender {
  self.expanded = !self.expanded;
  self.expandButton.title = self.expanded ? @"Collapse code" : @"Expand code";
  [self updateCodeHeight];
}

- (void)layout {
  CGFloat required = self.actions.spacing * MAX(0, (NSInteger)self.actions.arrangedSubviews.count - 1);
  for (NSView *button in self.actions.arrangedSubviews) required += button.intrinsicContentSize.width;
  NSUserInterfaceLayoutOrientation orientation = required <= NSWidth(self.bounds) - self.palette.space6 * 2
    ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
  if (self.actions.orientation != orientation) {
    self.actions.orientation = orientation;
    self.actions.alignment = orientation == NSUserInterfaceLayoutOrientationHorizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeLeading;
  }
  [super layout];
}

- (void)choose:(TLThemedButton *)button {
  if (self.submitted || ![TLApprovalChoices(self.request) containsObject:button.identifier] || !self.choiceHandler) return;
  // The continuation can synchronously replace this row. Keep the card alive
  // across that callback and reject reentrant clicks before dispatching it.
  TLApprovalCardView * __attribute__((objc_precise_lifetime)) card = self;
  card.submitted = YES;
  for (NSButton *action in card.actions.arrangedSubviews) action.enabled = NO;
  if (!card.choiceHandler(button.identifier)) {
    card.submitted = NO;
    for (NSButton *action in card.actions.arrangedSubviews) action.enabled = YES;
  }
}
@end
