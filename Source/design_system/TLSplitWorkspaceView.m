#import "TLSplitWorkspaceView.h"
#import "TLButton.h"
#import "TLTabIconView.h"

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

// Draw above pane content without intercepting header, browser, or resize input.
@interface TLSplitPaneBorders : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSValue *> *paneRects;
@end
@implementation TLSplitPaneBorders
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  [p.tabBorder setStroke];
  for (NSValue *value in self.paneRects) {
    NSRect rect = NSInsetRect(value.rectValue, p.borderWidth / 2, p.borderWidth / 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:p.space5 yRadius:p.space5];
    path.lineWidth = p.borderWidth;
    [path stroke];
  }
}
@end

@interface TLSplitDropTarget : NSObject
@property (nonatomic) NSRect rect;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic) TLSplitDropSide side;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbolName;
@end
@implementation TLSplitDropTarget
@end

@interface TLSplitDropPreview : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<TLSplitDropTarget *> *targets;
@property (nonatomic, strong) TLSplitDropTarget *activeTarget;
@end
@implementation TLSplitDropPreview
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  for (TLSplitDropTarget *target in self.targets) {
    BOOL active = target == self.activeTarget;
    NSRect rect = NSInsetRect(target.rect, p.borderWidth, p.borderWidth);
    CGFloat radius = MIN(p.messageInputCornerRadius, MIN(NSWidth(rect),NSHeight(rect))/2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [p.controlSurface setFill]; [path fill];
    if (active) { [p.chromeHoverSurface setFill]; [path fill]; }
    [active ? p.controlFocus : p.controlBorder setStroke];
    path.lineWidth = p.borderWidth;
    [path stroke];
    CGFloat inset = MIN(p.space5, MIN(NSWidth(rect),NSHeight(rect))/4);
    NSRect inner = NSInsetRect(rect,inset,inset);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:MAX(0,radius-inset) yRadius:MAX(0,radius-inset)];
    CGFloat dash[] = {p.space4,p.space3}; [outline setLineDash:dash count:2 phase:0];
    outline.lineWidth = p.borderWidth;
    [outline stroke];

    NSColor *textColor = active ? p.controlText : p.labelText;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = NSTextAlignmentCenter; paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attributes = @{NSFontAttributeName:p.labelFont, NSForegroundColorAttributeName:textColor, NSParagraphStyleAttributeName:paragraph};
    CGFloat iconSize = p.tabIconSize;
    NSRect content = NSInsetRect(inner,p.space4,p.space4);
    CGFloat labelHeight = ceil([target.title boundingRectWithSize:NSMakeSize(MAX(1,NSWidth(content)),CGFLOAT_MAX)
      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attributes].size.height);
    BOOL showLabel = NSWidth(content)>=[@"split" sizeWithAttributes:attributes].width && NSHeight(content)>=labelHeight;
    BOOL showIcon = NSWidth(content)>=iconSize && NSHeight(content)>=iconSize+(showLabel ? p.space6+labelHeight : 0);
    CGFloat groupHeight = (showLabel ? labelHeight : 0)+(showIcon ? iconSize+(showLabel ? p.space6 : 0) : 0);
    CGFloat bottom = NSMidY(rect)-groupHeight/2;
    if (showLabel) [target.title drawInRect:NSMakeRect(NSMinX(content),bottom,NSWidth(content),labelHeight) withAttributes:attributes];
    if (showIcon) {
      NSImage *symbol = [NSImage imageWithSystemSymbolName:target.symbolName accessibilityDescription:target.title];
      NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPaletteColors:@[textColor]];
      symbol = [symbol imageWithSymbolConfiguration:configuration];
      [symbol drawInRect:NSMakeRect(NSMidX(rect)-iconSize/2,bottom+(showLabel ? labelHeight+p.space6 : 0),iconSize,iconSize)];
    }
  }
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

@interface TLSplitPaneHeader : NSView
@property (nonatomic, weak) TLSplitWorkspaceView *owner;
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, strong) TLSplitTitleLabel *label;
@property (nonatomic, strong) TLTabIconView *icon;
@property (nonatomic, strong) TLButton *closeButton;
@property (nonatomic) NSPoint startPoint;
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL cancelled;
@property (nonatomic, strong) id dragEventMonitor;
@property (nonatomic, copy) NSArray *dragCancellationObservers;
@end
@implementation TLSplitPaneHeader
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _label = [TLSplitTitleLabel new]; _icon = [TLTabIconView new]; _closeButton = [TLButton new];
    _icon.centersEmojiVertically = YES;
    _closeButton.translatesAutoresizingMaskIntoConstraints = YES;
    _label.accessibilityElement = YES; _label.accessibilityRole = NSAccessibilityStaticTextRole;
    _closeButton.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close view"];
    _closeButton.target = self; _closeButton.action = @selector(close:);
    [self addSubview:_label]; [self addSubview:_icon]; [self addSubview:_closeButton];
    self.toolTip = @"Drag to the tab bar to separate this view";
  }
  return self;
}
- (NSView *)hitTest:(NSPoint)point {
  NSView *hit = [super hitTest:point];
  return hit == self.closeButton || [hit isDescendantOf:self.closeButton] ? hit : (hit ? self : nil);
}
- (void)layout {
  [super layout]; TLThemePalette *p = self.owner.palette;
  CGFloat size = p.tabIconSize, h = NSHeight(self.bounds), w = NSWidth(self.bounds);
  self.icon.frame = NSMakeRect(p.space6, (h-size)/2, size, size);
  self.closeButton.frame = NSMakeRect(MAX(0,w-h), 0, MIN(w,h), h);
  CGFloat x = NSMaxX(self.icon.frame) + p.space4;
  self.label.frame = NSMakeRect(x, (h-p.smallFont.pointSize-p.space2)/2, MAX(0,w-h-x-p.space4), p.smallFont.pointSize+p.space2);
}
- (void)close:(id)sender { if (self.owner.closeIdentity) self.owner.closeIdentity(self.identity); }
- (void)mouseDown:(NSEvent *)event {
  self.startPoint = event.locationInWindow; self.dragging = NO; self.cancelled = NO;
  if (self.owner.focusIdentity) self.owner.focusIdentity(self.identity);
}
- (void)mouseDragged:(NSEvent *)event {
  if (self.cancelled) return;
  if (!self.dragging && hypot(event.locationInWindow.x-self.startPoint.x,event.locationInWindow.y-self.startPoint.y) < 5) return;
  self.dragging = YES;
  if (!self.dragEventMonitor) {
    __weak typeof(self) weakSelf = self;
    __weak NSWindow *dragWindow = self.window;
    self.dragEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
      NSEventMaskKeyDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDown
      handler:^NSEvent *(NSEvent *event) {
      TLSplitPaneHeader *header = weakSelf;
      if (!header.dragging) return event;
      if (event.type == NSEventTypeKeyDown) {
        if (event.keyCode != 53) return event;
        [header cancelDrag]; return nil;
      }
      if (event.type == NSEventTypeLeftMouseDown || (dragWindow && event.window != dragWindow)) {
        [header cancelDrag]; return event;
      }
      if (event.type == NSEventTypeLeftMouseDragged) [header mouseDragged:event];
      else [header mouseUp:event];
      return nil;
    }];
    NSMutableArray *observers = [NSMutableArray new];
    for (NSNotificationName name in @[NSApplicationDidResignActiveNotification,NSWindowDidResignKeyNotification,NSWindowWillCloseNotification]) {
      id object = [name isEqual:NSApplicationDidResignActiveNotification] ? NSApp : dragWindow;
      if (!object) continue;
      [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:name object:object queue:nil usingBlock:^(NSNotification *note) {
        [weakSelf cancelDrag];
      }]];
    }
    self.dragCancellationObservers = observers;
  }
  if (self.owner.dragPane) self.owner.dragPane(self.identity, event.locationInWindow, NO, NO);
}
- (void)cancelDrag {
  if (!self.dragging) return;
  self.cancelled = YES; self.dragging = NO;
  [self removeDragTracking];
  if (self.owner.dragPane) self.owner.dragPane(self.identity, self.startPoint, YES, YES);
}
- (void)removeDragTracking {
  if (self.dragEventMonitor) [NSEvent removeMonitor:self.dragEventMonitor]; self.dragEventMonitor = nil;
  for (id observer in self.dragCancellationObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
  self.dragCancellationObservers = nil;
}
- (void)mouseUp:(NSEvent *)event {
  [self removeDragTracking]; BOOL dragged = self.dragging; self.dragging = NO;
  if (dragged && self.owner.dragPane) self.owner.dragPane(self.identity, event.locationInWindow, YES, NO);
}
- (void)dealloc {
  if (_dragEventMonitor) [NSEvent removeMonitor:_dragEventMonitor];
  for (id observer in _dragCancellationObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
}
@end

@interface TLSplitDivider : NSView
@property (nonatomic, weak) TLSplitWorkspaceView *owner;
@property (nonatomic) BOOL horizontal;
@property (nonatomic) NSUInteger column;
@property (nonatomic) NSUInteger boundary;
@end
@interface TLSplitWorkspaceView ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *hosts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TLSplitPaneHeader *> *headers;
@property (nonatomic, strong) NSMutableArray<TLSplitDivider *> *dividers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *rowWeights;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *columnWeights;
@property (nonatomic, strong) TLSplitDropPreview *preview;
@property (nonatomic, strong) TLSplitDragBadge *dragBadge;
@property (nonatomic, strong) TLSplitPaneBorders *paneBorders;
@property (nonatomic) BOOL sizeUpdateScheduled;
- (void)resizeDivider:(TLSplitDivider *)divider point:(NSPoint)point balance:(BOOL)balance;
@end
@implementation TLSplitDivider
- (BOOL)acceptsFirstResponder { return YES; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:self.horizontal ? NSCursor.resizeUpDownCursor : NSCursor.resizeLeftRightCursor]; }
- (void)mouseDown:(NSEvent *)event {
  [self.window makeFirstResponder:self];
  if (event.clickCount == 2) [self.owner resizeDivider:self point:NSZeroPoint balance:YES];
}
- (void)mouseDragged:(NSEvent *)event { [self.owner resizeDivider:self point:[self.owner convertPoint:event.locationInWindow fromView:nil] balance:NO]; }
- (void)adjust:(CGFloat)delta {
  NSPoint point = NSMakePoint(NSMidX(self.frame),NSMidY(self.frame));
  if (self.horizontal) point.y += delta * NSHeight(self.owner.bounds); else point.x += delta * NSWidth(self.owner.bounds);
  [self.owner resizeDivider:self point:point balance:NO];
}
- (void)keyDown:(NSEvent *)event {
  if (event.keyCode >= 123 && event.keyCode <= 126) [self adjust:(event.keyCode == 123 || event.keyCode == 125) ? -0.05 : 0.05];
  else [super keyDown:event];
}
- (BOOL)accessibilityPerformIncrement { [self adjust:0.05]; return YES; }
- (BOOL)accessibilityPerformDecrement { [self adjust:-0.05]; return YES; }
@end

@implementation TLSplitWorkspaceView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _hosts = [NSMutableDictionary new]; _headers = [NSMutableDictionary new]; _dividers = [NSMutableArray new];
    _fraction = 0.5; _focusedIdentity = @""; _leftTitle = @""; _rightTitle = @"";
    _paneBorders = [TLSplitPaneBorders new]; [self addSubview:_paneBorders];
    _preview = [TLSplitDropPreview new]; _preview.hidden = YES; [self addSubview:_preview];
    _dragBadge = [TLSplitDragBadge new]; _dragBadge.hidden = YES; [self addSubview:_dragBadge];
    self.columns = @[@[@"single"]]; self.palette = _palette;
  }
  return self;
}
- (NSArray<NSString *> *)identities { NSMutableArray *all = [NSMutableArray new]; for (NSArray *column in self.columns) [all addObjectsFromArray:column]; return all; }
- (NSView *)hostForIdentity:(NSString *)identity {
  NSView *host = self.hosts[identity];
  if (!host) {
    host = [NSView new]; host.wantsLayer = YES; host.layer.masksToBounds = YES;
    host.accessibilityElement = YES; host.accessibilityRole = NSAccessibilityGroupRole;
    self.hosts[identity] = host; [self addSubview:host positioned:NSWindowBelow relativeTo:self.paneBorders];
  }
  return host;
}
- (NSView *)leftHost { return [self hostForIdentity:self.identities.firstObject ?: @"single"]; }
- (NSView *)rightHost { NSView *host = [self hostForIdentity:self.identities.count > 1 ? self.identities[1] : @"unused"]; host.hidden = !self.split; return host; }
- (BOOL)rightFocused { return self.identities.count > 1 && [self.focusedIdentity isEqual:self.identities[1]]; }
- (void)setRightFocused:(BOOL)right { self.focusedIdentity = right && self.identities.count > 1 ? self.identities[1] : self.identities.firstObject; }
- (void)setSplit:(BOOL)split {
  _split = split;
  if (split && self.identities.count < 2) self.columns = @[@[@"left"],@[@"right"]];
  if (!split && self.identities.count > 1) self.columns = @[@[self.identities.firstObject]];
  self.needsLayout = YES;
}
- (void)setColumns:(NSArray<NSArray<NSString *> *> *)columns {
  if ([_columns isEqual:columns]) return;
  _columns = columns.copy; _split = self.identities.count > 1;
  self.rowWeights = [NSMutableDictionary new]; self.columnWeights = [NSMutableArray new];
  for (NSArray *column in columns) {
    NSMutableArray *weights = [NSMutableArray new]; for (NSString *identity in column) { [weights addObject:@(1.0/column.count)]; [self hostForIdentity:identity]; }
    self.rowWeights[@(self.columnWeights.count)] = weights; [self.columnWeights addObject:@(1.0/columns.count)];
  }
  NSSet *live = [NSSet setWithArray:self.identities];
  for (NSString *identity in self.hosts.allKeys) if (![live containsObject:identity]) { [self.hosts[identity] removeFromSuperview]; [self.hosts removeObjectForKey:identity]; }
  for (NSString *identity in self.headers.allKeys) if (![live containsObject:identity]) { [self.headers[identity] removeFromSuperview]; [self.headers removeObjectForKey:identity]; }
  for (TLSplitDivider *divider in self.dividers) [divider removeFromSuperview]; [self.dividers removeAllObjects];
  for (NSUInteger c=0;c<columns.count;c++) {
    for (NSUInteger r=1;r<columns[c].count;r++) [self addDividerForColumn:c boundary:r horizontal:YES];
    if (c>0) [self addDividerForColumn:c boundary:c horizontal:NO];
  }
  self.needsLayout = YES;
}
- (void)addDividerForColumn:(NSUInteger)column boundary:(NSUInteger)boundary horizontal:(BOOL)horizontal {
  TLSplitDivider *divider = [TLSplitDivider new]; divider.owner = self; divider.column = column; divider.boundary = boundary; divider.horizontal = horizontal;
  divider.accessibilityElement = YES; divider.accessibilityRole = NSAccessibilitySplitterRole; divider.accessibilityLabel = @"Resize split panes";
  divider.toolTip = @"Drag to resize · Double-click to balance · Arrow keys to adjust";
  [self.dividers addObject:divider]; [self addSubview:divider positioned:NSWindowBelow relativeTo:self.paneBorders];
}
- (void)setTitle:(NSString *)title image:(NSImage *)image icon:(NSString *)icon systemIcon:(NSString *)symbol forIdentity:(NSString *)identity {
  TLSplitPaneHeader *header = self.headers[identity];
  if (!header) { header = [TLSplitPaneHeader new]; header.owner = self; header.identity = identity; self.headers[identity] = header; [self addSubview:header positioned:NSWindowBelow relativeTo:self.paneBorders]; }
  header.wantsLayer = YES; header.layer.masksToBounds = YES;
  header.layer.backgroundColor = self.palette.tabBackground.CGColor;
  header.label.stringValue = title; header.label.font = self.palette.smallFont;
  header.icon.image = image; header.icon.icon = icon; header.icon.systemIconName = symbol; header.icon.palette = self.palette; [header.icon applyCurrentState];
  header.closeButton.palette = self.palette; header.closeButton.contentTintColor = self.palette.labelText;
  header.closeButton.accessibilityLabel = [@"Close " stringByAppendingString:title]; header.closeButton.toolTip = header.closeButton.accessibilityLabel;
  self.hosts[identity].accessibilityLabel = title;
  [self updateFocus]; self.needsLayout = YES;
}
- (void)setLeftTitle:(NSString *)title { _leftTitle = title.copy; [self setTitle:title image:nil icon:@"" systemIcon:@"rectangle" forIdentity:self.identities.firstObject]; }
- (void)setRightTitle:(NSString *)title { _rightTitle = title.copy; if (self.identities.count>1) [self setTitle:title image:nil icon:@"" systemIcon:@"rectangle" forIdentity:self.identities[1]]; }
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette; self.wantsLayer = YES; self.layer.backgroundColor = palette.tabBackground.CGColor;
  self.preview.palette = palette; self.dragBadge.palette = palette;
  self.paneBorders.palette = palette; self.paneBorders.needsDisplay = YES;
  self.paneBorders.alphaValue = palette.workspaceOutlineOpacity;
  for (TLSplitPaneHeader *header in self.headers.allValues) {
    header.layer.backgroundColor = palette.tabBackground.CGColor;
    header.label.font = palette.smallFont; header.icon.palette = palette; [header.icon applyCurrentState];
    header.closeButton.palette = palette; header.closeButton.contentTintColor = palette.labelText; header.needsLayout = YES;
  }
  for (NSView *divider in self.dividers) divider.needsDisplay = YES;
  [self updateFocus]; self.needsLayout = YES; self.preview.needsDisplay = YES; self.dragBadge.needsDisplay = YES;
}
- (void)setFocusedIdentity:(NSString *)identity { _focusedIdentity = identity.copy; [self updateFocus]; }
- (void)updateFocus { for (TLSplitPaneHeader *header in self.headers.allValues) header.label.textColor = self.palette.labelText; self.needsDisplay = YES; }
- (void)setFraction:(CGFloat)fraction {
  _fraction = isfinite(fraction) ? MAX(0.15,MIN(0.85,fraction)) : 0.5;
  if (self.columns.count == 2) self.columnWeights = [@[@(_fraction),@(1-_fraction)] mutableCopy];
  self.needsLayout = YES;
}
- (void)restoreLayoutWeights:(NSDictionary *)weights {
  if (![weights[@"columns"] isEqual:self.columns]) return;
  self.columnWeights = [weights[@"widths"] mutableCopy];
  self.rowWeights = [NSMutableDictionary new];
  for (NSNumber *column in weights[@"heights"]) self.rowWeights[column] = [weights[@"heights"][column] mutableCopy];
  self.needsLayout = YES;
}
- (void)saveLayoutWeights {
  if (!self.layoutWeightsChanged) return;
  NSMutableDictionary *heights = [NSMutableDictionary new];
  for (NSNumber *column in self.rowWeights) heights[column] = [self.rowWeights[column] copy];
  self.layoutWeightsChanged(@{@"columns":self.columns, @"widths":self.columnWeights.copy, @"heights":heights.copy});
}
- (void)resizeDivider:(TLSplitDivider *)divider point:(NSPoint)point balance:(BOOL)balance {
  NSMutableArray<NSNumber *> *weights = divider.horizontal ? self.rowWeights[@(divider.column)] : self.columnWeights;
  NSUInteger b = divider.boundary; if (b >= weights.count) return;
  CGFloat start = 0; for (NSUInteger i=0;i<b-1;i++) start += weights[i].doubleValue;
  CGFloat sum = weights[b-1].doubleValue + weights[b].doubleValue;
  CGFloat inset = self.split ? self.palette.space5 : 0;
  CGFloat available = MAX(0, (divider.horizontal ? NSHeight(self.bounds) : NSWidth(self.bounds)) - inset*2 - self.palette.space5*(weights.count-1));
  CGFloat position = (divider.horizontal ? NSHeight(self.bounds)-point.y : point.x) - inset;
  CGFloat value = balance ? sum/2 : (position-self.palette.space5*(b-0.5))/MAX(1,available)-start;
  value = MAX(sum*0.15,MIN(sum*0.85,value)); weights[b-1] = @(value); weights[b] = @(sum-value);
  if (!divider.horizontal && weights.count == 2) { _fraction = value; if (self.fractionChanged) self.fractionChanged(value); }
  [self saveLayoutWeights];
  self.needsLayout = YES;
}
- (void)layout {
  [super layout]; CGFloat width=NSWidth(self.bounds), height=NSHeight(self.bounds), gap=self.palette.space5;
  CGFloat inset=self.split ? gap : 0, gridHeight=MAX(0,height-inset*2);
  CGFloat availableWidth=MAX(0,width-inset*2-gap*(self.columns.count-1)), x=inset;
  NSMutableArray<NSValue *> *paneRects = [NSMutableArray new];
  BOOL changed = NO;
  for (NSUInteger c=0;c<self.columns.count;c++) {
    NSArray *column=self.columns[c]; CGFloat w=availableWidth*self.columnWeights[c].doubleValue, top=height-inset;
    CGFloat availableHeight=MAX(0,gridHeight-gap*(column.count-1));
    for (NSUInteger r=0;r<column.count;r++) {
      NSString *identity=column[r]; CGFloat h=availableHeight*self.rowWeights[@(c)][r].doubleValue;
      CGFloat headerHeight=self.split ? MIN(self.palette.tabHeight,h) : 0;
      NSView *host=[self hostForIdentity:identity]; NSRect frame=NSMakeRect(x,top-h,w,MAX(0,h-headerHeight));
      changed |= !NSEqualRects(host.frame,frame); host.frame=frame; host.hidden=NO;
      host.layer.backgroundColor = self.palette.tabBackground.CGColor;
      host.layer.cornerRadius = self.split ? self.palette.space5 : 0;
      TLSplitPaneHeader *header=self.headers[identity]; header.frame=NSMakeRect(x,top-headerHeight,w,headerHeight); header.hidden=!self.split; header.needsLayout=YES;
      header.layer.cornerRadius = self.split ? self.palette.space5 : 0;
      [paneRects addObject:[NSValue valueWithRect:NSMakeRect(x,top-h,w,h)]];
      for (TLSplitDivider *d in self.dividers) if (d.horizontal && d.column==c && d.boundary==r+1) d.frame=NSMakeRect(x,top-h-gap,w,gap);
      top-=h+gap;
    }
    for (TLSplitDivider *d in self.dividers) if (!d.horizontal && d.boundary==c+1) d.frame=NSMakeRect(x+w,inset,gap,gridHeight);
    x+=w+gap;
  }
  self.hosts[@"unused"].hidden = YES;
  self.paneBorders.frame = self.bounds; self.paneBorders.hidden = !self.split;
  self.paneBorders.paneRects = paneRects; self.paneBorders.needsDisplay = YES;
  self.preview.frame=self.bounds;
  if (changed && !self.sizeUpdateScheduled) {
    self.sizeUpdateScheduled=YES; __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.sizeUpdateScheduled=NO; if (weakSelf.contentSizeChanged) weakSelf.contentSizeChanged(); });
  }
}
- (NSRect)paneRectForIdentity:(NSString *)identity {
  if (!identity) return NSZeroRect;
  NSRect frame=self.hosts[identity].frame;
  if (self.split) frame.size.height+=NSHeight(self.headers[identity].frame);
  return frame;
}
- (NSString *)identityAtPoint:(NSPoint)point {
  for (NSString *identity in self.identities) if (NSPointInRect(point,[self paneRectForIdentity:identity])) return identity;
  return nil;
}
// Each insertion boundary is represented once, including the shared gap.
// Neighbor candidates let a dragged pane use the opposite side of a boundary.
- (void)prepareDropTargetsWithValidator:(BOOL (^)(NSString *, TLSplitDropSide))validator {
  [self layoutSubtreeIfNeeded];
  NSMutableArray<TLSplitDropTarget *> *targets = [NSMutableArray new];
  void (^addTarget)(NSRect,NSArray *,NSArray *,NSString *,NSString *) = ^(NSRect rect, NSArray *identities, NSArray *sides, NSString *title, NSString *symbol) {
    if (NSWidth(rect)<=0 || NSHeight(rect)<=0) return;
    for (NSUInteger i=0;i<identities.count;i++) {
      TLSplitDropSide side = [sides[i] integerValue];
      if (validator && !validator(identities[i],side)) continue;
      TLSplitDropTarget *target = [TLSplitDropTarget new];
      target.rect=rect; target.identity=identities[i]; target.side=side;
      target.title=title; target.symbolName=symbol;
      [targets addObject:target]; break;
    }
  };
  CGFloat inset=self.split ? self.palette.space5 : 0;
  CGFloat bottom=inset, height=MAX(0,NSHeight(self.bounds)-inset*2);
  // A band extends into both adjacent panes, keeping the shared gap droppable.
  for (NSUInteger c=0;c<=self.columns.count;c++) {
    NSArray *left=c>0 ? self.columns[c-1] : @[], *right=c<self.columns.count ? self.columns[c] : @[];
    if (!left.count && !right.count) continue;
    NSRect l=[self paneRectForIdentity:left.firstObject], r=[self paneRectForIdentity:right.firstObject];
    CGFloat minX=left.count ? NSMaxX(l)-NSWidth(l)*0.22 : NSMinX(r);
    CGFloat maxX=right.count ? NSMinX(r)+NSWidth(r)*0.22 : NSMaxX(l);
    NSMutableArray *identities=[NSMutableArray new], *sides=[NSMutableArray new];
    for (NSString *identity in left) { [identities addObject:identity]; [sides addObject:@(TLSplitDropSideRight)]; }
    for (NSString *identity in right) { [identities addObject:identity]; [sides addObject:@(TLSplitDropSideLeft)]; }
    NSString *title=c==0 ? @"Add left split" : c==self.columns.count ? @"Add right split" : @"Add middle split";
    NSString *symbol=c==0 ? @"rectangle.lefthalf.filled" : c==self.columns.count ? @"rectangle.righthalf.filled" : @"rectangle.split.2x1";
    addTarget(NSMakeRect(minX,bottom,maxX-minX,height),identities,sides,title,symbol);
  }
  NSArray<TLSplitDropTarget *> *columnTargets=targets.copy;
  for (NSArray *column in self.columns) {
    NSRect columnRect=[self paneRectForIdentity:column.firstObject];
    CGFloat x=NSMinX(columnRect), maxX=NSMaxX(columnRect);
    // Reserve room only for column targets that are actually available.
    // With no column insertion, row targets occupy the entire column width.
    for (TLSplitDropTarget *target in columnTargets) {
      if (NSMinX(target.rect)<=NSMinX(columnRect) && NSMaxX(target.rect)>NSMinX(columnRect)) x=MAX(x,NSMaxX(target.rect)+self.palette.space3);
      if (NSMaxX(target.rect)>=NSMaxX(columnRect) && NSMinX(target.rect)<NSMaxX(columnRect)) maxX=MIN(maxX,NSMinX(target.rect)-self.palette.space3);
    }
    CGFloat width=MAX(0,maxX-x);
    for (NSUInteger r=0;r<=column.count;r++) {
      NSString *above=r>0 ? column[r-1] : nil, *below=r<column.count ? column[r] : nil;
      NSRect a=[self paneRectForIdentity:above], b=[self paneRectForIdentity:below];
      CGFloat minY=below ? NSMaxY(b)-NSHeight(b)*0.22 : NSMinY(a);
      CGFloat maxY=above ? NSMinY(a)+NSHeight(a)*0.22 : NSMaxY(b);
      NSMutableArray *identities=[NSMutableArray new], *sides=[NSMutableArray new];
      if (above) { [identities addObject:above]; [sides addObject:@(TLSplitDropSideBelow)]; }
      if (below) { [identities addObject:below]; [sides addObject:@(TLSplitDropSideAbove)]; }
      NSString *title=r==0 ? @"Add top split" : r==column.count ? @"Add bottom split" : @"Add middle split";
      NSString *symbol=r==0 ? @"rectangle.tophalf.filled" : r==column.count ? @"rectangle.bottomhalf.filled" : @"rectangle.split.1x2";
      addTarget(NSMakeRect(x,minY,width,maxY-minY),identities,sides,title,symbol);
    }
  }
  self.preview.targets=targets; self.preview.activeTarget=nil;
  self.preview.frame=self.bounds; self.preview.hidden=targets.count==0; self.preview.needsDisplay=YES;
}
- (TLSplitDropTarget *)dropTargetAtPoint:(NSPoint)point {
  if (self.preview.hidden || !NSPointInRect(point,self.bounds)) return nil;
  for (TLSplitDropTarget *target in self.preview.targets) if (NSPointInRect(point,target.rect)) return target;
  return nil;
}
- (NSString *)dropIdentityAtPoint:(NSPoint)point { return [self dropTargetAtPoint:point].identity; }
- (TLSplitDropSide)dropSideAtPoint:(NSPoint)point { return [self dropTargetAtPoint:point].side; }
- (void)showDropSide:(TLSplitDropSide)side title:(NSString *)title point:(NSPoint)point {
  self.preview.activeTarget=side==TLSplitDropSideNone ? nil : [self dropTargetAtPoint:point];
  self.dragBadge.title=title;
  self.dragBadge.hidden=!NSPointInRect(point,self.bounds);
  CGFloat w=MIN(self.palette.tabMaxWidth,NSWidth(self.bounds)), h=self.palette.tabHeight;
  self.dragBadge.frame=NSMakeRect(MAX(0,MIN(NSWidth(self.bounds)-w,point.x+self.palette.space6)),MAX(0,MIN(NSHeight(self.bounds)-h,point.y-h-self.palette.space6)),w,h);
  self.dragBadge.needsDisplay=YES; self.preview.needsDisplay=YES; self.needsLayout=YES;
}
- (void)clearDropPreview { self.preview.hidden=YES; self.preview.targets=@[]; self.preview.activeTarget=nil; self.dragBadge.hidden=YES; }
@end
