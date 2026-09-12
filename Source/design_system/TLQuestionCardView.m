#import "TLQuestionCardView.h"
#import "TLThemedButton.h"

@interface TLQuestionCardView ()
@property NSDictionary *request;
@property NSStackView *stack;
@property NSStackView *actions;
@property NSTextField *heading;
@property NSTextField *reason;
@property NSTextField *status;
@property NSTextView *code;
@property NSScrollView *codeScroll;
@property TLThemedButton *expandButton;
@property NSLayoutConstraint *codeHeight;
@property BOOL expanded;
@property BOOL submitted;
@property NSTextField *answerField;
@property TLTokenView *answerSurface;
@property TLThemedButton *sendAnswer;
@property NSMutableOrderedSet<NSString *> *selectedOptions;
@property NSMutableArray<NSLayoutConstraint *> *optionHeights;
@end

@implementation TLQuestionCardView
- (instancetype)initWithRequest:(NSDictionary *)request palette:(TLThemePalette *)palette {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.translatesAutoresizingMaskIntoConstraints = NO;
  _request = [request copy];
  _selectedOptions = [NSMutableOrderedSet orderedSet];
  _optionHeights = [NSMutableArray array];
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
  _heading = [self label:request[@"title"] ?: @"Question"];
  _reason = [self label:[request[@"description"] isKindOfClass:NSString.class] && [request[@"description"] length]
    ? request[@"description"] : @""];
  _reason.hidden = !_reason.stringValue.length;
  [_stack addArrangedSubview:_heading];
  [_stack addArrangedSubview:_reason];
  [_heading.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;
  [_reason.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;

  _codeScroll = [NSScrollView new];
  _codeScroll.translatesAutoresizingMaskIntoConstraints = NO;
  _codeScroll.hasVerticalScroller = YES;
  _codeScroll.autohidesScrollers = YES;
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
  for (NSDictionary *option in request[@"options"]) {
    TLThemedButton *button = [TLThemedButton buttonWithTitle:option[@"title"] target:self action:@selector(choose:)];
    button.identifier = option[@"id"];
    button.primary = [option[@"primary"] boolValue];
    button.enabled = !_submitted;
    button.cell.wraps = YES;
    button.cell.lineBreakMode = NSLineBreakByWordWrapping;
    NSLayoutConstraint *height = [button.heightAnchor constraintEqualToConstant:palette.settingsActionHeight];
    height.active = YES; [_optionHeights addObject:height];
    [button setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_actions addArrangedSubview:button];
    [button.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor].active = YES;
  }
  if ([request[@"allows_text"] boolValue]) {
    _answerField = [[NSTextField alloc] init];
    _answerField.translatesAutoresizingMaskIntoConstraints = NO;
    _answerField.bezeled = NO;
    _answerField.bordered = NO;
    _answerField.drawsBackground = NO;
    _answerSurface = [[TLTokenView alloc] init];
    _answerSurface.translatesAutoresizingMaskIntoConstraints = NO;
    [_answerSurface addSubview:_answerField];
    _answerField.placeholderString = @"Type your answer…";
    _answerField.enabled = !_submitted;
    _answerField.target = self;
    _answerField.action = @selector(sendAnswer:);
    [_stack addArrangedSubview:_answerSurface];
    [NSLayoutConstraint activateConstraints:@[
      [_answerSurface.heightAnchor constraintEqualToConstant:palette.fieldHeight],
      [_answerSurface.widthAnchor constraintEqualToAnchor:_stack.widthAnchor],
      [_answerField.leadingAnchor constraintEqualToAnchor:_answerSurface.leadingAnchor constant:palette.space4],
      [_answerField.trailingAnchor constraintEqualToAnchor:_answerSurface.trailingAnchor constant:-palette.space4],
      [_answerField.centerYAnchor constraintEqualToAnchor:_answerSurface.centerYAnchor]]];
    _sendAnswer = [TLThemedButton buttonWithTitle:@"Send answer" target:self action:@selector(sendAnswer:)];
    _sendAnswer.enabled = !_submitted;
    _sendAnswer.primary = YES;
    [_stack addArrangedSubview:_sendAnswer];
    [_sendAnswer.widthAnchor constraintLessThanOrEqualToAnchor:_stack.widthAnchor].active = YES;
  }
  _status = [self label:request[@"status"] ?: @""];
  _status.hidden = !_status.stringValue.length;
  [_stack addArrangedSubview:_status];
  [_status.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;
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
  self.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.fillColor = palette.controlSurface;
  self.borderColor = palette.controlBorder;
  self.borderEdges = TLBorderEdgeAll;
  self.borderWidth = palette.borderWidth;
  self.cornerRadius = palette.chipRadius;
  self.heading.font = palette.roleFont;
  self.heading.textColor = palette.assistantMessageText;
  self.answerField.font = palette.smallFont;
  self.answerField.textColor = palette.controlText;
  self.answerField.backgroundColor = palette.markdownCodeSurface;
  NSTextView *editor = (id)self.answerField.currentEditor;
  editor.textColor = palette.controlText;
  editor.insertionPointColor = palette.controlText;
  editor.backgroundColor = palette.markdownCodeSurface;
  self.answerSurface.fillColor = palette.markdownCodeSurface;
  self.answerSurface.borderEdges = TLBorderEdgeAll;
  self.answerSurface.borderWidth = palette.borderWidth;
  self.answerSurface.borderColor = palette.controlBorder;
  self.answerSurface.cornerRadius = palette.chipRadius;
  self.answerField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Type your answer…"
    attributes:@{NSForegroundColorAttributeName:palette.controlText, NSFontAttributeName:palette.smallFont}];
  self.sendAnswer.palette = palette;
  self.status.font = palette.smallFont;
  self.status.textColor = palette.assistantMessageText;
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
  [self.code.layoutManager ensureLayoutForTextContainer:self.code.textContainer];
  CGFloat textHeight = ceil([self.code.layoutManager usedRectForTextContainer:self.code.textContainer].size.height);
  self.codeScroll.hidden = !self.code.string.length;
  self.expandButton.hidden = !self.code.string.length || textHeight <= lineHeight * 6;
  self.codeHeight.constant = self.code.string.length ? MIN(lineHeight * (self.expanded ? 18 : 6), MAX(lineHeight, textHeight)) + self.palette.space4 * 2 : 0;
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
  [self.actions.arrangedSubviews enumerateObjectsUsingBlock:^(TLThemedButton *button, NSUInteger index, BOOL *stop) {
    CGFloat available = MAX(1, NSWidth(self.bounds) - self.palette.space6 * 2 - self.palette.space8 * 2);
    CGFloat textHeight = [button.title boundingRectWithSize:NSMakeSize(available, CGFLOAT_MAX)
      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
      attributes:@{NSFontAttributeName:self.palette.labelFont}].size.height;
    self.optionHeights[index].constant = MAX(self.palette.settingsActionHeight, ceil(textHeight) + self.palette.space4 * 2);
  }];
  [super layout];
  [self updateCodeHeight];
}

- (void)setActionsEnabled:(BOOL)enabled {
  for (NSButton *action in self.actions.arrangedSubviews) action.enabled = enabled;
  self.answerField.enabled = enabled;
  self.sendAnswer.enabled = enabled;
}
- (void)submit:(NSString *)answer {
  if (self.submitted || !answer.length || !self.choiceHandler) return;
  TLQuestionCardView * __attribute__((objc_precise_lifetime)) card = self;
  card.submitted = YES;
  [card setActionsEnabled:NO];
  if (!card.choiceHandler(answer)) {
    card.submitted = NO;
    [card setActionsEnabled:YES];
  }
}
- (void)choose:(TLThemedButton *)button {
  if (self.submitted || ![self.actions.arrangedSubviews containsObject:button]) return;
  if ([self.request[@"multi_select"] boolValue]) {
    if ([self.selectedOptions containsObject:button.identifier]) [self.selectedOptions removeObject:button.identifier];
    else [self.selectedOptions addObject:button.identifier];
    button.primary = [self.selectedOptions containsObject:button.identifier];
    button.state = button.primary ? NSControlStateValueOn : NSControlStateValueOff;
    return;
  }
  [self submit:[self.request[@"allows_text"] boolValue] ? button.title : button.identifier];
}
- (void)sendAnswer:(id)sender {
  NSMutableArray *answers = [NSMutableArray array];
  for (NSDictionary *option in self.request[@"options"])
    if ([self.selectedOptions containsObject:option[@"id"]]) [answers addObject:option[@"title"]];
  NSString *typed = [self.answerField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (typed.length) [answers addObject:typed];
  [self submit:[answers componentsJoinedByString:@", "]];
}
@end
