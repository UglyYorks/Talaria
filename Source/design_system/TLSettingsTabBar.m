#import "TLSettingsTabBar.h"

@interface TLSettingsTabBar ()
@property NSScrollView *scroll;
@property NSView *document;
@property TLThemedButton *previous;
@property TLThemedButton *next;
@property (nonatomic, copy, readwrite) NSArray<TLThemedButton *> *tabButtons;
@property BOOL revealSelection;
- (void)selectTab:(NSButton *)sender;
- (void)moveSelectionWithEvent:(NSEvent *)event;
@end

@interface TLSettingsTabButton : TLThemedButton
@end
@implementation TLSettingsTabButton
- (BOOL)acceptsFirstResponder { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityRadioButtonRole; }
- (id)accessibilityValue { return @(self.state == NSControlStateValueOn); }
- (void)keyDown:(NSEvent *)event {
  if (event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 115 || event.keyCode == 119)
    [(TLSettingsTabBar *)self.target moveSelectionWithEvent:event];
  else [super keyDown:event];
}
@end

@implementation TLSettingsTabBar
- (instancetype)initWithFrame:(NSRect)frame {
  if (!(self = [super initWithFrame:frame])) return nil;
  _selectedIndex = -1;
  _titles = @[]; _tabButtons = @[];
  _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  _scroll = [[NSScrollView alloc] init];
  _scroll.drawsBackground = NO; _scroll.borderType = NSNoBorder;
  _scroll.horizontalScrollElasticity = NSScrollElasticityNone;
  _scroll.verticalScrollElasticity = NSScrollElasticityNone;
  _document = [[NSView alloc] init]; _scroll.documentView = _document;
  [self addSubview:_scroll];
  _previous = [self arrow:@"chevron.left" label:@"Scroll categories left" action:@selector(scrollTabs:)];
  _next = [self arrow:@"chevron.right" label:@"Scroll categories right" action:@selector(scrollTabs:)];
  _previous.tag = -1; _next.tag = 1;
  self.accessibilityRole = NSAccessibilityTabGroupRole;
  self.accessibilityLabel = @"Browser settings categories";
  _scroll.contentView.postsBoundsChangedNotifications = YES;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateScrollButtons:)
    name:NSViewBoundsDidChangeNotification object:_scroll.contentView];
  return self;
}
- (TLThemedButton *)arrow:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  TLThemedButton *button = [[TLThemedButton alloc] init];
  button.title = @""; button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  button.imagePosition = NSImageOnly; button.accessibilityLabel = label; button.toolTip = label;
  button.target = self; button.action = action; button.palette = self.palette;
  [self addSubview:button]; return button;
}
- (void)setTitles:(NSArray<NSString *> *)titles {
  for (NSView *view in self.tabButtons) [view removeFromSuperview];
  _titles = [titles copy];
  NSMutableArray *buttons = [NSMutableArray array];
  for (NSString *title in titles) {
    TLSettingsTabButton *button = [[TLSettingsTabButton alloc] init];
    button.title = title; button.toolTip = title; button.accessibilityLabel = title;
    button.palette = self.palette; button.tag = buttons.count;
    [button setButtonType:NSButtonTypePushOnPushOff];
    button.target = self; button.action = @selector(selectTab:);
    button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.document addSubview:button]; [buttons addObject:button];
  }
  self.tabButtons = buttons;
  self.selectedIndex = titles.count ? MAX(0, MIN(self.selectedIndex, (NSInteger)titles.count - 1)) : -1;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  for (TLThemedButton *button in self.tabButtons) button.palette = palette;
  self.previous.palette = palette; self.next.palette = palette;
  [self invalidateIntrinsicContentSize]; self.needsLayout = YES;
}
- (void)setSelectedIndex:(NSInteger)selectedIndex {
  if (selectedIndex < -1 || selectedIndex >= (NSInteger)self.tabButtons.count) return;
  _selectedIndex = selectedIndex;
  for (TLThemedButton *button in self.tabButtons) {
    button.state = button.tag == selectedIndex ? NSControlStateValueOn : NSControlStateValueOff;
    button.primary = button.tag == selectedIndex;
  }
  self.revealSelection = YES; self.needsLayout = YES;
}
- (void)selectTab:(NSButton *)sender {
  self.selectedIndex = sender.tag;
  [self layoutSubtreeIfNeeded];
  [self sendAction:self.action to:self.target];
}
- (void)moveSelectionWithEvent:(NSEvent *)event {
  if (!self.tabButtons.count) return;
  NSInteger index = self.selectedIndex;
  if (event.keyCode == 115) index = 0;
  else if (event.keyCode == 119) index = self.tabButtons.count - 1;
  else index += event.keyCode == 123 ? -1 : 1;
  index = MAX(0, MIN(index, (NSInteger)self.tabButtons.count - 1));
  [self selectTab:self.tabButtons[index]];
  [self.window makeFirstResponder:self.tabButtons[index]];
}
- (void)scrollTabs:(NSButton *)sender {
  NSClipView *clip = self.scroll.contentView;
  CGFloat maximum = MAX(0, NSWidth(self.document.bounds) - NSWidth(clip.bounds));
  CGFloat x = MAX(0, MIN(maximum, NSMinX(clip.bounds) + sender.tag * NSWidth(clip.bounds)));
  [clip scrollToPoint:NSMakePoint(x, 0)]; [self.scroll reflectScrolledClipView:clip];
}
- (void)updateScrollButtons:(NSNotification *)notification {
  NSRect visible = self.scroll.contentView.bounds;
  self.previous.enabled = NSMinX(visible) > 0;
  self.next.enabled = NSMaxX(visible) < NSWidth(self.document.bounds);
}
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, self.palette.settingsActionHeight); }
- (void)setFrameSize:(NSSize)size {
  BOOL changed = size.width != NSWidth(self.frame);
  [super setFrameSize:size];
  if (changed) { self.revealSelection = YES; self.needsLayout = YES; }
}
- (void)layout {
  [super layout];
  CGFloat gap = self.palette.space4, height = self.palette.settingsActionHeight;
  CGFloat total = 0;
  for (NSView *button in self.tabButtons) total += button.intrinsicContentSize.width + gap;
  total = MAX(0, total - gap);
  BOOL overflow = total > NSWidth(self.bounds);
  self.previous.hidden = !overflow; self.next.hidden = !overflow;
  CGFloat inset = overflow ? height + gap : 0;
  CGFloat width = MAX(0, NSWidth(self.bounds) - inset * 2);
  self.previous.frame = NSMakeRect(0, 0, height, height);
  self.next.frame = NSMakeRect(MAX(0, NSWidth(self.bounds) - height), 0, height, height);
  self.scroll.frame = NSMakeRect(inset, 0, width, height);
  CGFloat x = 0;
  for (NSView *button in self.tabButtons) {
    CGFloat itemWidth = MIN(width, button.intrinsicContentSize.width);
    button.frame = NSMakeRect(x, 0, itemWidth, height); x += itemWidth + gap;
  }
  self.document.frame = NSMakeRect(0, 0, MAX(width, x - gap), height);
  if (self.revealSelection && self.selectedIndex >= 0 && width > 0) {
    [self.document scrollRectToVisible:self.tabButtons[self.selectedIndex].frame];
    self.revealSelection = NO;
  }
  [self updateScrollButtons:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
