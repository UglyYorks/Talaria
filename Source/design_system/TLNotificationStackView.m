#import "TLNotificationStackView.h"
#import "TLThemedButton.h"

static NSString *TLNotificationText(id value) {
  return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSInteger TLNotificationUrgency(NSDictionary *item) {
  NSString *urgency = TLNotificationText(item[@"urgency"]);
  return [urgency isEqualToString:@"high"] ? 2 : ([urgency isEqualToString:@"medium"] ? 1 : 0);
}

static NSTimeInterval TLNotificationDate(id value) {
  if ([value isKindOfClass:NSNumber.class]) return [value doubleValue];
  if ([value isKindOfClass:NSDate.class]) return [value timeIntervalSince1970];
  if (![value isKindOfClass:NSString.class]) return 0;
  static NSISO8601DateFormatter *formatter;
  static NSISO8601DateFormatter *fractional;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    formatter = [[NSISO8601DateFormatter alloc] init];
    fractional = [[NSISO8601DateFormatter alloc] init];
    fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
  });
  return ([fractional dateFromString:value] ?: [formatter dateFromString:value]).timeIntervalSince1970;
}

@interface TLNotificationItemView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSDictionary *notification;
@property (nonatomic) NSUInteger unreadCount;
@property (nonatomic) BOOL unread;
@property (nonatomic) BOOL collapsedGroup;
@property (nonatomic) NSUInteger groupCount;
@property (nonatomic, copy) void (^activate)(void);
@property (nonatomic, copy) void (^markRead)(BOOL read);
@property (nonatomic, copy) void (^expand)(BOOL expanded);
@property (nonatomic, strong) NSTrackingArea *tracking;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation TLNotificationItemView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (NSFont *)titleFont {
  return self.unread ? self.palette.sidebarInboxUnreadTitleFont : self.palette.sidebarInboxReadTitleFont;
}
- (CGFloat)titleHeightForWidth:(CGFloat)width {
  NSRect measured = [TLNotificationText(self.notification[@"title"])
    boundingRectWithSize:NSMakeSize(MAX(1, width - self.palette.sidebarInboxItemHorizontalInset * 2), CGFLOAT_MAX)
    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
    attributes:@{NSFontAttributeName:self.titleFont}];
  return ceil(MAX(self.titleFont.ascender - self.titleFont.descender, measured.size.height));
}
- (CGFloat)heightForWidth:(CGFloat)width {
  return ceil(self.palette.space4 * 3 + [self titleHeightForWidth:width] +
    MAX(self.palette.space9, self.palette.smallFont.ascender - self.palette.smallFont.descender));
}
- (NSColor *)badgeSurface {
  NSInteger urgency = TLNotificationUrgency(self.notification);
  return urgency == 2 ? self.palette.sidebarUrgentNotificationBadgeSurface :
    (urgency == 1 ? self.palette.sidebarInboxPrimaryBadgeSurface : self.palette.sidebarInboxBadgeSurface);
}
- (NSColor *)badgeTextColor {
  NSInteger urgency = TLNotificationUrgency(self.notification);
  return urgency == 2 ? self.palette.sidebarUrgentNotificationBadgeText :
    (urgency == 1 ? self.palette.sidebarInboxPrimaryBadgeText : self.palette.sidebarInboxBadgeText);
}
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, p.borderWidth, p.borderWidth)
    xRadius:p.radiusMedium yRadius:p.radiusMedium];
  [(self.pressed ? p.sidebarActiveSurface : (self.hovered ? p.sidebarHoverSurface :
    (self.collapsedGroup ? p.appBackground : p.transparentSurface))) setFill];
  [card fill];
  if (self.collapsedGroup) {
    [p.sidebarBorder setStroke]; card.lineWidth = p.borderWidth; [card stroke];
  }
  if (self.window.firstResponder == self) {
    [p.controlFocus setStroke]; card.lineWidth = p.focusRingSize; [card stroke];
  }
  CGFloat inset = p.sidebarInboxItemHorizontalInset;
  CGFloat titleHeight = [self titleHeightForWidth:NSWidth(self.bounds)];
  NSMutableParagraphStyle *titleStyle = [[NSMutableParagraphStyle alloc] init];
  titleStyle.lineBreakMode = NSLineBreakByWordWrapping;
  [TLNotificationText(self.notification[@"title"]) drawInRect:NSMakeRect(inset, p.space4,
    MAX(1, NSWidth(self.bounds) - inset * 2), titleHeight)
    withAttributes:@{NSFontAttributeName:self.titleFont, NSForegroundColorAttributeName:p.appText,
      NSParagraphStyleAttributeName:titleStyle}];

  CGFloat metadataY = p.space4 * 2 + titleHeight;
  NSString *count = self.unreadCount ? [NSString stringWithFormat:@"%lu", (unsigned long)self.unreadCount] : @"";
  NSSize countSize = [count sizeWithAttributes:@{NSFontAttributeName:p.sidebarInboxBadgeFont}];
  CGFloat badgeHeight = self.unreadCount ? p.space9 : p.space3;
  CGFloat badgeWidth = self.unreadCount ? MAX(p.sidebarInboxBadgeMinimumWidth,
    ceil(countSize.width + p.sidebarInboxBadgeHorizontalPadding * 2)) : badgeHeight;
  CGFloat metadataHeight = MAX(p.space9, p.smallFont.ascender - p.smallFont.descender);
  NSRect badge = NSMakeRect(MAX(inset, NSWidth(self.bounds) - inset - badgeWidth),
    metadataY + (metadataHeight - badgeHeight) * 0.5, badgeWidth, badgeHeight);
  [[self badgeSurface] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:badge xRadius:badgeHeight * 0.5 yRadius:badgeHeight * 0.5] fill];
  [count drawAtPoint:NSMakePoint(NSMidX(badge) - countSize.width * 0.5, NSMidY(badge) - countSize.height * 0.5)
    withAttributes:@{NSFontAttributeName:p.sidebarInboxBadgeFont, NSForegroundColorAttributeName:self.badgeTextColor}];

  NSString *kind = TLNotificationText(self.notification[@"source_kind"]);
  NSString *symbol = [kind isEqualToString:@"cron"] || [kind isEqualToString:@"schedule"] ||
    [kind isEqualToString:@"scheduled"] ? @"clock.arrow.circlepath" : @"bolt.circle";
  NSImage *icon = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
  icon = [icon imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[p.textMuted]]];
  [icon drawInRect:NSMakeRect(inset, metadataY + (metadataHeight - p.sidebarInboxIconSize) * 0.5,
    p.sidebarInboxIconSize, p.sidebarInboxIconSize)];
  CGFloat textX = inset + p.sidebarInboxIconSize + p.space3;
  NSMutableParagraphStyle *metadataStyle = [[NSMutableParagraphStyle alloc] init];
  metadataStyle.lineBreakMode = NSLineBreakByTruncatingTail;
  NSString *task = TLNotificationText(self.notification[@"task_name"]);
  if (!task.length) task = @"Automation";
  [task drawInRect:NSMakeRect(textX, metadataY, MAX(1, NSMinX(badge) - p.space3 - textX), metadataHeight)
    withAttributes:@{NSFontAttributeName:p.smallFont, NSForegroundColorAttributeName:p.textMuted,
      NSParagraphStyleAttributeName:metadataStyle}];
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.tracking) [self removeTrackingArea:self.tracking];
  self.tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
  [self addTrackingArea:self.tracking];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.pressed = NO; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)event {
  if (event.modifierFlags & NSEventModifierFlagControl) { [super rightMouseDown:event]; return; }
  [self.window makeFirstResponder:self]; self.pressed = YES; self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event {
  BOOL activate = self.pressed && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
  self.pressed = NO; self.needsDisplay = YES;
  if (activate && self.activate) self.activate();
}
- (void)keyDown:(NSEvent *)event {
  NSString *key = event.charactersIgnoringModifiers;
  if ([key isEqualToString:@"\r"] || [key isEqualToString:@" "]) {
    if (self.activate) self.activate();
  } else if (event.keyCode == 124 && self.expand) self.expand(YES);
  else if ((event.keyCode == 123 || event.keyCode == 53) && self.expand) self.expand(NO);
  else if (event.keyCode == 48 || event.keyCode == 125 || event.keyCode == 126) {
    BOOL previous = event.keyCode == 126 || (event.modifierFlags & NSEventModifierFlagShift);
    if (previous) [self.window selectPreviousKeyView:self]; else [self.window selectNextKeyView:self];
  }
  else [super keyDown:event];
}
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; [self scrollRectToVisible:self.bounds]; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }
- (NSMenu *)menuForEvent:(NSEvent *)event {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Notifications"];
  NSString *title = self.collapsedGroup ? (self.unread ? @"Mark all as read" : @"Mark all as unread") :
    (self.unread ? @"Mark as read" : @"Mark as unread");
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(toggleRead:) keyEquivalent:@""];
  item.target = self; [menu addItem:item]; return menu;
}
- (void)toggleRead:(id)sender { if (self.markRead) self.markRead(self.unread); }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel {
  NSString *state = self.unread ? @"Unread" : @"Read";
  NSString *group = self.collapsedGroup ? [NSString stringWithFormat:@", %lu notifications, %lu unread. Expand stack",
    (unsigned long)self.groupCount, (unsigned long)self.unreadCount] : @"";
  return [NSString stringWithFormat:@"%@, %@. %@, %@ urgency%@", TLNotificationText(self.notification[@"title"]),
    TLNotificationText(self.notification[@"task_name"]), state, TLNotificationText(self.notification[@"urgency"]), group];
}
- (BOOL)accessibilityPerformPress { if (self.activate) { self.activate(); return YES; } return NO; }
@end

@interface TLNotificationStackView ()
@property (nonatomic, copy) NSArray<TLNotificationItemView *> *itemViews;
@property (nonatomic, strong) TLThemedButton *collapseButton;
@end

@implementation TLNotificationStackView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _notifications = @[]; _itemViews = @[];
    self.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
+ (NSArray<NSDictionary *> *)orderedNotifications:(NSArray<NSDictionary *> *)notifications {
  return [notifications sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    BOOL ar = [a[@"is_read"] boolValue], br = [b[@"is_read"] boolValue];
    if (ar != br) return ar ? NSOrderedDescending : NSOrderedAscending;
    if (!ar && TLNotificationUrgency(a) != TLNotificationUrgency(b))
      return TLNotificationUrgency(a) > TLNotificationUrgency(b) ? NSOrderedAscending : NSOrderedDescending;
    NSTimeInterval ad = TLNotificationDate(a[@"updated_at"] ?: a[@"created_at"]);
    NSTimeInterval bd = TLNotificationDate(b[@"updated_at"] ?: b[@"created_at"]);
    if (ad != bd) return ad > bd ? NSOrderedAscending : NSOrderedDescending;
    return [[a[@"id"] description] compare:[b[@"id"] description]];
  }];
}
- (NSUInteger)unreadCount {
  NSUInteger count = 0;
  for (NSDictionary *item in self.notifications) if (![item[@"is_read"] boolValue]) count++;
  return count;
}
- (void)setNotifications:(NSArray<NSDictionary *> *)notifications {
  NSArray *ordered = [self.class orderedNotifications:notifications ?: @[]];
  if ([_notifications isEqual:ordered]) return;
  _notifications = [ordered copy];
  if (_notifications.count < 2) _expanded = NO;
  [self rebuild];
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.collapseButton.palette = palette;
  for (TLNotificationItemView *row in self.itemViews) { row.palette = palette; row.needsDisplay = YES; }
  [self invalidateIntrinsicContentSize]; self.needsLayout = YES; self.needsDisplay = YES;
}
- (void)setExpanded:(BOOL)expanded {
  expanded = expanded && self.notifications.count > 1;
  if (_expanded == expanded) return;
  BOOL restoreFocus = [self.window.firstResponder isKindOfClass:NSView.class] &&
    [(NSView *)self.window.firstResponder isDescendantOf:self];
  _expanded = expanded; [self rebuild];
  if (self.expansionChanged) self.expansionChanged(expanded);
  if (restoreFocus) [self.window makeFirstResponder:self.itemViews.firstObject];
}
- (void)collapse:(id)sender { self.expanded = NO; }
- (void)rebuild {
  for (NSView *view in self.subviews.copy) [view removeFromSuperview];
  NSMutableArray *rows = [NSMutableArray array];
  BOOL grouped = !self.expanded && self.notifications.count > 1;
  NSArray *visible = grouped ? @[self.notifications.firstObject] : self.notifications;
  __weak typeof(self) weakSelf = self;
  for (NSDictionary *notification in visible) {
    TLNotificationItemView *row = [[TLNotificationItemView alloc] initWithFrame:NSZeroRect];
    row.palette = self.palette; row.notification = notification; row.collapsedGroup = grouped;
    row.groupCount = self.notifications.count;
    row.unreadCount = grouped ? self.unreadCount : (![notification[@"is_read"] boolValue] ? 1 : 0);
    row.unread = grouped ? self.unreadCount > 0 : ![notification[@"is_read"] boolValue];
    row.toolTip = TLNotificationText(notification[@"summary"]);
    row.activate = ^{
      if (grouped) weakSelf.expanded = YES;
      else if (weakSelf.openHandler) weakSelf.openHandler(notification);
    };
    row.markRead = ^(BOOL read) {
      NSArray *items = grouped ? weakSelf.notifications : @[notification];
      for (NSDictionary *item in items)
        if ([item[@"is_read"] boolValue] != read && weakSelf.readHandler) weakSelf.readHandler(item, read);
    };
    row.expand = ^(BOOL expanded) { weakSelf.expanded = expanded; };
    [rows addObject:row]; [self addSubview:row];
  }
  self.itemViews = rows;
  self.collapseButton = nil;
  if (self.expanded) {
    self.collapseButton = [TLThemedButton buttonWithTitle:@"Collapse" target:self action:@selector(collapse:)];
    self.collapseButton.palette = self.palette;
    [self addSubview:self.collapseButton];
  }
  [self invalidateIntrinsicContentSize]; self.needsLayout = YES; self.needsDisplay = YES;
}
- (CGFloat)stackDepth {
  return !self.expanded && self.notifications.count > 1 ? MIN((NSUInteger)2, self.notifications.count - 1) * self.palette.space3 : 0;
}
- (CGFloat)contentHeightForWidth:(CGFloat)width {
  CGFloat height = self.stackDepth;
  for (TLNotificationItemView *row in self.itemViews) height += [row heightForWidth:width];
  if (self.collapseButton) height += self.palette.space3 + self.collapseButton.intrinsicContentSize.height;
  return ceil(height);
}
- (NSSize)intrinsicContentSize {
  CGFloat width = NSWidth(self.bounds) > 0 ? NSWidth(self.bounds) : self.palette.sidebarWidth;
  return NSMakeSize(NSViewNoIntrinsicMetric, [self contentHeightForWidth:width]);
}
- (void)setFrameSize:(NSSize)size {
  BOOL changed = size.width != NSWidth(self.frame);
  [super setFrameSize:size];
  if (changed) { [self invalidateIntrinsicContentSize]; self.needsLayout = YES; }
}
- (void)layout {
  [super layout];
  CGFloat y = 0, width = NSWidth(self.bounds);
  for (TLNotificationItemView *row in self.itemViews) {
    CGFloat height = [row heightForWidth:width];
    row.frame = NSMakeRect(0, y, width, height); y += height;
  }
  if (self.collapseButton) {
    NSSize size = self.collapseButton.intrinsicContentSize;
    self.collapseButton.frame = NSMakeRect(self.palette.sidebarInboxItemHorizontalInset, y + self.palette.space3,
      MIN(size.width, MAX(1, width - self.palette.sidebarInboxItemHorizontalInset * 2)), size.height);
  }
}
- (void)drawRect:(NSRect)dirtyRect {
  CGFloat depth = self.stackDepth;
  if (depth <= 0) return;
  TLThemePalette *p = self.palette;
  CGFloat frontHeight = [self.itemViews.firstObject heightForWidth:NSWidth(self.bounds)];
  for (CGFloat offset = depth; offset > 0; offset -= p.space3) {
    NSRect rect = NSMakeRect(offset, offset, MAX(1, NSWidth(self.bounds) - offset * 2), frontHeight);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:p.radiusMedium yRadius:p.radiusMedium];
    [p.sidebarActiveSurface setFill]; [path fill];
    [p.sidebarBorder setStroke]; path.lineWidth = p.borderWidth; [path stroke];
  }
}
@end
