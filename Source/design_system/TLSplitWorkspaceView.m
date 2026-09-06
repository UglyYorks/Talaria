#import "TLSplitWorkspaceView.h"
#import "TLButton.h"

// A clipped title has no intrinsic width, so long tab names cannot impose a
// minimum window size on proportional panes.
@interface TLSplitTitleLabel : NSView
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) NSColor *textColor;
@end
@implementation TLSplitTitleLabel
- (void)setStringValue:(NSString *)value { _stringValue = value.copy; self.accessibilityLabel = value; self.needsDisplay = YES; }
- (void)setFont:(NSFont *)font { _font = font; self.needsDisplay = YES; }
- (void)setTextColor:(NSColor *)color { _textColor = color; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirtyRect {
  if (!self.font || !self.textColor) return;
  NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.stringValue drawInRect:self.bounds withAttributes:@{NSFontAttributeName:self.font,
    NSForegroundColorAttributeName:self.textColor, NSParagraphStyleAttributeName:paragraph}];
}
@end

@interface TLSplitDropPreview : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@end
@implementation TLSplitDropPreview
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
  NSRect frame = NSInsetRect(self.bounds, self.palette.space4, self.palette.space4);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:self.palette.radiusMedium yRadius:self.palette.radiusMedium];
  [self.palette.chromeHoverSurface setFill];
  [path fill];
  [self.palette.controlFocus setStroke];
  path.lineWidth = self.palette.focusRingSize;
  [path stroke];
  NSDictionary *attributes = @{NSFontAttributeName:self.palette.labelFont, NSForegroundColorAttributeName:self.palette.controlText};
  NSSize size = [self.title sizeWithAttributes:attributes];
  CGFloat width = MIN(size.width + self.palette.space8 * 2, MAX(0, NSWidth(frame) - self.palette.space8 * 2));
  NSRect label = NSMakeRect(NSMidX(frame) - width / 2, NSMidY(frame) - size.height / 2 - self.palette.space4,
                           width, size.height + self.palette.space4 * 2);
  [self.palette.controlSurface setFill];
  [[NSBezierPath bezierPathWithRoundedRect:label xRadius:self.palette.radiusMedium yRadius:self.palette.radiusMedium] fill];
  NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
  style.alignment = NSTextAlignmentCenter;
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  NSMutableDictionary *textAttributes = attributes.mutableCopy;
  textAttributes[NSParagraphStyleAttributeName] = style;
  [self.title drawInRect:NSInsetRect(label, self.palette.space4, self.palette.space4) withAttributes:textAttributes];
}
@end

@interface TLSplitDragBadge : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@end
@implementation TLSplitDragBadge
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, p.borderWidth, p.borderWidth)
    xRadius:p.radiusMedium yRadius:p.radiusMedium];
  [p.controlSurface setFill]; [path fill];
  [p.controlBorder setStroke]; path.lineWidth = p.borderWidth; [path stroke];
  NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary *attributes = @{NSFontAttributeName:p.labelFont, NSForegroundColorAttributeName:p.controlText, NSParagraphStyleAttributeName:paragraph};
  [self.title drawInRect:NSInsetRect(self.bounds, p.space6, (NSHeight(self.bounds) - p.labelFont.pointSize - p.space2) / 2) withAttributes:attributes];
}
@end

@interface TLSplitDivider : NSView
@property (nonatomic, weak) TLSplitWorkspaceView *owner;
@end
@implementation TLSplitDivider
- (BOOL)acceptsFirstResponder { return YES; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeLeftRightCursor]; }
- (void)mouseDown:(NSEvent *)event {
  [self.window makeFirstResponder:self];
  if (event.clickCount == 2) { self.owner.fraction = 0.5; if (self.owner.fractionChanged) self.owner.fractionChanged(0.5); }
}
- (void)mouseDragged:(NSEvent *)event {
  CGFloat x = [self.owner convertPoint:event.locationInWindow fromView:nil].x;
  self.owner.fraction = x / MAX(1, NSWidth(self.owner.bounds));
  if (self.owner.fractionChanged) self.owner.fractionChanged(self.owner.fraction);
}
- (void)keyDown:(NSEvent *)event {
  if (event.keyCode == 123 || event.keyCode == 124) {
    self.owner.fraction += event.keyCode == 123 ? -0.05 : 0.05;
    if (self.owner.fractionChanged) self.owner.fractionChanged(self.owner.fraction);
  } else [super keyDown:event];
}
- (BOOL)accessibilityPerformIncrement {
  self.owner.fraction += 0.05;
  if (self.owner.fractionChanged) self.owner.fractionChanged(self.owner.fraction);
  return YES;
}
- (BOOL)accessibilityPerformDecrement {
  self.owner.fraction -= 0.05;
  if (self.owner.fractionChanged) self.owner.fractionChanged(self.owner.fraction);
  return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.owner.palette;
  [p.tabBackground setFill]; NSRectFill(self.bounds);
  [self.window.firstResponder == self ? p.controlFocus : p.tabBorder setFill];
  NSRectFill(NSMakeRect(floor(NSMidX(self.bounds)), 0, p.borderWidth, NSHeight(self.bounds)));
}
@end

@interface TLSplitWorkspaceView ()
@property (nonatomic, strong, readwrite) NSView *leftHost;
@property (nonatomic, strong, readwrite) NSView *rightHost;
@property (nonatomic, strong) TLSplitDivider *divider;
@property (nonatomic, strong) TLSplitTitleLabel *leftLabel;
@property (nonatomic, strong) TLSplitTitleLabel *rightLabel;
@property (nonatomic, strong) TLButton *leftExpand;
@property (nonatomic, strong) TLButton *rightExpand;
@property (nonatomic, strong) TLButton *swapButton;
@property (nonatomic, strong) TLSplitDropPreview *preview;
@property (nonatomic, strong) TLSplitDragBadge *dragBadge;
@property (nonatomic) TLSplitDropSide previewSide;
@property (nonatomic) BOOL sizeUpdateScheduled;
@property (nonatomic) NSSize previousContentSize;
@property (nonatomic, strong) NSLayoutConstraint *leftWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *rightLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *leftTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *rightTopConstraint;
@property (nonatomic) CGFloat effectiveFraction;
@end
@implementation TLSplitWorkspaceView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _fraction = 0.5;
    _leftTitle = @""; _rightTitle = @"";
    _leftHost = [NSView new]; _rightHost = [NSView new];
    for (NSView *host in @[_leftHost, _rightHost]) {
      // Pane widths are proportional constraints, never fixed window minima.
      host.translatesAutoresizingMaskIntoConstraints = NO;
      host.wantsLayer = YES; host.layer.masksToBounds = YES; [self addSubview:host];
      host.accessibilityElement = YES; host.accessibilityRole = NSAccessibilityGroupRole;
    }
    _divider = [TLSplitDivider new]; _divider.owner = self;
    _divider.accessibilityElement = YES;
    _divider.accessibilityRole = NSAccessibilitySplitterRole;
    _divider.accessibilityLabel = @"Resize split panes";
    _divider.toolTip = @"Drag to resize · Double-click to balance · Arrow keys to adjust";
    [self addSubview:_divider];
    _leftLabel = [TLSplitTitleLabel new]; _rightLabel = [TLSplitTitleLabel new];
    for (TLSplitTitleLabel *label in @[_leftLabel, _rightLabel]) {
      label.accessibilityElement = YES; label.accessibilityRole = NSAccessibilityStaticTextRole; [self addSubview:label];
    }
    _leftExpand = [self buttonWithSymbol:@"arrow.up.left.and.arrow.down.right" label:@"Expand left pane" action:@selector(expandLeft:)];
    _rightExpand = [self buttonWithSymbol:@"arrow.up.left.and.arrow.down.right" label:@"Expand right pane" action:@selector(expandRight:)];
    _swapButton = [self buttonWithSymbol:@"arrow.left.arrow.right" label:@"Swap split panes" action:@selector(swap:)];
    _preview = [TLSplitDropPreview new]; _preview.hidden = YES;
    [self addSubview:_preview];
    _dragBadge = [TLSplitDragBadge new]; _dragBadge.hidden = YES; [self addSubview:_dragBadge];
    for (NSView *view in self.subviews) view.translatesAutoresizingMaskIntoConstraints = NO;
    for (TLSplitTitleLabel *label in @[_leftLabel, _rightLabel])
      [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    CGFloat inset = self.palette.space6;
    NSLayoutConstraint *leftTitleWidth = [_leftLabel.trailingAnchor constraintEqualToAnchor:_leftExpand.leadingAnchor constant:-inset];
    NSLayoutConstraint *rightTitleWidth = [_rightLabel.trailingAnchor constraintEqualToAnchor:_swapButton.leadingAnchor constant:-inset];
    leftTitleWidth.priority = NSLayoutPriorityFittingSizeCompression; rightTitleWidth.priority = NSLayoutPriorityFittingSizeCompression;
    [NSLayoutConstraint activateConstraints:@[
      [_divider.leadingAnchor constraintEqualToAnchor:_leftHost.trailingAnchor],
      [_divider.widthAnchor constraintEqualToConstant:self.palette.space5],
      [_divider.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_divider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_leftExpand.trailingAnchor constraintEqualToAnchor:_leftHost.trailingAnchor],
      [_rightExpand.trailingAnchor constraintEqualToAnchor:_rightHost.trailingAnchor],
      [_swapButton.trailingAnchor constraintEqualToAnchor:_rightExpand.leadingAnchor],
      [_leftLabel.leadingAnchor constraintEqualToAnchor:_leftHost.leadingAnchor constant:inset],
      [_rightLabel.leadingAnchor constraintEqualToAnchor:_rightHost.leadingAnchor constant:inset],
      [_leftLabel.heightAnchor constraintEqualToConstant:self.palette.smallFont.pointSize + self.palette.space2],
      [_rightLabel.heightAnchor constraintEqualToConstant:self.palette.smallFont.pointSize + self.palette.space2],
      [_leftLabel.centerYAnchor constraintEqualToAnchor:_leftExpand.centerYAnchor],
      [_rightLabel.centerYAnchor constraintEqualToAnchor:_rightExpand.centerYAnchor],
      leftTitleWidth, rightTitleWidth,
    ]];
    for (TLButton *button in @[_leftExpand, _rightExpand, _swapButton]) {
      [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [button.widthAnchor constraintEqualToConstant:self.palette.tabHeight],
        [button.heightAnchor constraintEqualToConstant:self.palette.tabHeight],
      ]];
    }
    _rightLeadingConstraint = [_rightHost.leadingAnchor constraintEqualToAnchor:_leftHost.trailingAnchor];
    _leftTopConstraint = [_leftHost.topAnchor constraintEqualToAnchor:self.topAnchor];
    _rightTopConstraint = [_rightHost.topAnchor constraintEqualToAnchor:self.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
      [_leftHost.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_leftHost.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [_rightHost.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_rightHost.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      _rightLeadingConstraint, _leftTopConstraint, _rightTopConstraint,
    ]];
    [self updatePaneConstraints];
    self.palette = _palette;
  }
  return self;
}
- (TLButton *)buttonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  TLButton *button = [TLButton new]; button.translatesAutoresizingMaskIntoConstraints = YES;
  button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  button.toolTip = label; button.accessibilityLabel = label; button.target = self; button.action = action;
  [self addSubview:button]; return button;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.wantsLayer = YES; self.layer.backgroundColor = palette.tabBackground.CGColor;
  for (TLButton *button in @[self.leftExpand, self.rightExpand, self.swapButton]) {
    button.palette = palette; button.contentTintColor = palette.labelText;
  }
  for (TLSplitTitleLabel *label in @[self.leftLabel, self.rightLabel]) label.font = palette.smallFont;
  self.preview.palette = palette;
  self.dragBadge.palette = palette; self.dragBadge.needsDisplay = YES;
  [self updateFocus]; self.needsLayout = YES; self.preview.needsDisplay = YES; self.divider.needsDisplay = YES;
}
- (void)setSplit:(BOOL)split { if (_split == split) return; _split = split; [self updatePaneConstraints]; self.needsLayout = YES; }
- (void)setFraction:(CGFloat)fraction {
  _fraction = isfinite(fraction) ? MAX(0.15, MIN(0.85, fraction)) : 0.5;
  self.divider.accessibilityValue = @(_fraction);
  [self updatePaneConstraints]; self.needsLayout = YES;
}
- (void)setRightFocused:(BOOL)rightFocused { _rightFocused = rightFocused; [self updateFocus]; }
- (void)updateFocus {
  self.leftLabel.textColor = self.rightFocused ? self.palette.textMuted : self.palette.controlText;
  self.rightLabel.textColor = self.rightFocused ? self.palette.controlText : self.palette.textMuted;
  self.leftHost.accessibilityLabel = [NSString stringWithFormat:@"Left pane: %@", self.leftTitle];
  self.rightHost.accessibilityLabel = [NSString stringWithFormat:@"Right pane: %@", self.rightTitle];
  self.needsDisplay = YES;
}
- (void)setLeftTitle:(NSString *)leftTitle { _leftTitle = leftTitle.copy; self.leftLabel.stringValue = leftTitle; self.leftLabel.toolTip = leftTitle; [self updateFocus]; }
- (void)setRightTitle:(NSString *)rightTitle { _rightTitle = rightTitle.copy; self.rightLabel.stringValue = rightTitle; self.rightLabel.toolTip = rightTitle; [self updateFocus]; }
- (void)updatePaneConstraints {
  CGFloat divider = self.split ? self.palette.space5 : 0;
  CGFloat available = MAX(1, NSWidth(self.bounds) - divider);
  CGFloat minimumFraction = MIN(0.35, self.palette.windowMinimumWidth / available);
  CGFloat fraction = self.split ? MAX(minimumFraction, MIN(1 - minimumFraction, self.fraction)) : 1;
  CGFloat header = self.split ? self.palette.tabHeight : 0;
  self.leftTopConstraint.constant = header;
  self.rightTopConstraint.constant = header;
  self.rightLeadingConstraint.constant = divider;
  if (!self.leftWidthConstraint || fabs(self.effectiveFraction - fraction) > 0.0001) {
    self.leftWidthConstraint.active = NO;
    self.leftWidthConstraint = [self.leftHost.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:fraction constant:-divider * fraction];
    self.leftWidthConstraint.active = YES;
    self.effectiveFraction = fraction;
  } else self.leftWidthConstraint.constant = -divider * fraction;
}
- (void)layout {
  [self updatePaneConstraints];
  [super layout];
  CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
  CGFloat dividerWidth = self.palette.space5;
  CGFloat available = MAX(0, width - dividerWidth);
  // Preserve the preferred ratio while allowing the window itself to shrink to 200px.
  CGFloat minimum = MIN(self.palette.windowMinimumWidth, available * 0.35);
  CGFloat leftWidth = self.split ? MAX(minimum, MIN(available - minimum, available * self.fraction)) : width;
  self.rightHost.hidden = !self.split;
  for (NSView *view in @[self.divider, self.leftLabel, self.rightLabel, self.leftExpand, self.rightExpand, self.swapButton]) view.hidden = !self.split;
  if (!self.preview.hidden) self.preview.frame = NSMakeRect(self.previewSide == TLSplitDropSideRight ? width / 2 : 0, 0, width / 2, height);
  NSSize contentSize = NSMakeSize(leftWidth, height);
  if (!NSEqualSizes(contentSize, self.previousContentSize)) {
    self.previousContentSize = contentSize;
    if (!self.sizeUpdateScheduled) {
      self.sizeUpdateScheduled = YES;
      __weak typeof(self) weakSelf = self;
      dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.sizeUpdateScheduled = NO; if (weakSelf.contentSizeChanged) weakSelf.contentSizeChanged(); });
    }
  }
}
- (void)drawRect:(NSRect)dirtyRect {
  if (!self.split) return;
  [self.palette.controlFocus setFill];
  NSRect host = self.rightFocused ? self.rightHost.frame : self.leftHost.frame;
  NSRectFill(NSMakeRect(NSMinX(host), NSHeight(self.bounds) - self.palette.borderWidth, NSWidth(host), self.palette.borderWidth));
}
- (void)mouseDown:(NSEvent *)event {
  if (self.split && self.focusPane) self.focusPane([self convertPoint:event.locationInWindow fromView:nil].x > NSMaxX(self.leftHost.frame));
}
- (TLSplitDropSide)dropSideAtPoint:(NSPoint)point {
  if (!NSPointInRect(point, self.bounds)) return TLSplitDropSideNone;
  if (point.x < NSWidth(self.bounds) * 0.35) return TLSplitDropSideLeft;
  if (point.x > NSWidth(self.bounds) * 0.65) return TLSplitDropSideRight;
  return TLSplitDropSideNone;
}
- (void)showDropSide:(TLSplitDropSide)side title:(NSString *)title point:(NSPoint)point {
  self.previewSide = side;
  self.preview.hidden = side == TLSplitDropSideNone;
  self.preview.title = side == TLSplitDropSideLeft ? @"Release to split left" : @"Release to split right";
  self.dragBadge.title = title;
  self.dragBadge.hidden = !NSPointInRect(point, self.bounds);
  CGFloat width = MIN(self.palette.tabMaxWidth, NSWidth(self.bounds));
  CGFloat height = self.palette.tabHeight;
  self.dragBadge.frame = NSMakeRect(MAX(0, MIN(NSWidth(self.bounds) - width, point.x + self.palette.space6)),
    MAX(0, MIN(NSHeight(self.bounds) - height, point.y - height - self.palette.space6)), width, height);
  self.dragBadge.needsDisplay = YES;
  self.preview.needsDisplay = YES; self.needsLayout = YES;
}
- (void)clearDropPreview { self.dragBadge.hidden = YES; self.preview.hidden = YES; self.previewSide = TLSplitDropSideNone; }
- (void)expandLeft:(id)sender { if (self.expandPane) self.expandPane(NO); }
- (void)expandRight:(id)sender { if (self.expandPane) self.expandPane(YES); }
- (void)swap:(id)sender { if (self.swapPanes) self.swapPanes(); }
@end
