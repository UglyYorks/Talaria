#import "TLFindBar.h"

@interface TLFindBar ()
@property (nonatomic, strong) NSView *searchSurface;
@property (nonatomic) BOOL noMatches;
@end

@implementation TLFindBar
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;
  self.wantsLayer = YES;
  _searchSurface = [NSView new];
  _searchSurface.wantsLayer = YES;
  [self addSubview:_searchSurface];
  _searchField = [NSTextField new];
  _searchField.drawsBackground = NO;
  _searchField.bordered = NO;
  _searchField.focusRingType = NSFocusRingTypeNone;
  _searchField.usesSingleLineMode = YES;
  _searchField.cell.scrollable = YES;
  _searchField.delegate = self;
  _searchField.wantsLayer = YES;
  _searchLabel = @"Find";
  [_searchField setAccessibilityLabel:_searchLabel];
  [_searchSurface addSubview:_searchField];
  _resultLabel = [NSTextField labelWithString:@""];
  _resultLabel.alignment = NSTextAlignmentRight;
  _resultLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self addSubview:_resultLabel];
  _previousButton = [self buttonWithSymbol:@"chevron.up" label:@"Previous match (⇧↩)" action:@selector(previous:)];
  _nextButton = [self buttonWithSymbol:@"chevron.down" label:@"Next match (↩)" action:@selector(next:)];
  _closeButton = [self buttonWithSymbol:@"xmark" label:@"Close find (Esc)" action:@selector(close:)];
  self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self setMatchCount:0 activeMatch:0 searching:NO];
  return self;
}
- (TLThemedButton *)buttonWithSymbol:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  TLThemedButton *button = [TLThemedButton new];
  button.title = @"";
  button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  button.imagePosition = NSImageOnly;
  button.target = self;
  button.action = action;
  button.toolTip = label;
  [button setAccessibilityLabel:label];
  [self addSubview:button];
  return button;
}
- (void)setSearchLabel:(NSString *)searchLabel {
  _searchLabel = [searchLabel copy];
  [self.searchField setAccessibilityLabel:searchLabel];
  if (self.palette) self.palette = self.palette;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.layer.backgroundColor = palette.tabBackground.CGColor;
  self.searchField.font = palette.bodyFont;
  self.searchField.textColor = palette.controlText;
  self.searchField.backgroundColor = palette.controlSurface;
  self.searchSurface.layer.backgroundColor = palette.controlSurface.CGColor;
  self.searchSurface.layer.cornerRadius = palette.radiusMedium;
  self.searchSurface.layer.borderWidth = palette.borderWidth;
  self.searchSurface.layer.borderColor = palette.controlBorder.CGColor;
  self.searchField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:self.searchLabel
    attributes:@{NSForegroundColorAttributeName:palette.textMuted, NSFontAttributeName:palette.bodyFont}];
  self.resultLabel.font = palette.smallFont;
  self.resultLabel.textColor = palette.textMuted;
  for (TLThemedButton *button in @[self.previousButton, self.nextButton, self.closeButton]) {
    button.palette = palette;
    button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:palette.browserToolbarIconSize weight:NSFontWeightRegular];
  }
  [self updateFieldEditor];
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  CGFloat padding = self.palette.space4, gap = self.palette.space2;
  if (self.noMatches) self.resultLabel.stringValue = NSWidth(self.bounds) < self.palette.fieldHeight * 10 ? @"0/0" : @"0 matches";
  CGFloat height = self.palette.fieldHeight;
  CGFloat buttonWidth = self.palette.browserToolbarButtonSize;
  CGFloat y = (NSHeight(self.bounds) - height) * 0.5;
  CGFloat right = NSWidth(self.bounds) - padding;
  for (NSView *button in @[self.closeButton, self.nextButton, self.previousButton]) {
    button.frame = NSMakeRect(right - buttonWidth, y, buttonWidth, height);
    right -= buttonWidth + gap;
  }
  CGFloat labelWidth = MIN(ceil(self.resultLabel.intrinsicContentSize.width) + gap, MAX(0, NSWidth(self.bounds) * 0.25));
  self.resultLabel.frame = NSMakeRect(right - labelWidth, (NSHeight(self.bounds) - self.resultLabel.intrinsicContentSize.height) * 0.5,
    labelWidth, self.resultLabel.intrinsicContentSize.height);
  right -= labelWidth + padding;
  self.searchSurface.frame = NSMakeRect(padding, y, MAX(0, right - padding), height);
  CGFloat textHeight = ceil(self.searchField.font.ascender - self.searchField.font.descender) + gap;
  self.searchField.frame = NSMakeRect(gap, (height - textHeight) * 0.5,
    MAX(0, NSWidth(self.searchSurface.bounds) - gap * 2), textHeight);
}
- (void)updateFieldEditor {
  NSTextView *editor = (NSTextView *)self.searchField.currentEditor;
  if (!editor) return;
  editor.textColor = self.palette.controlText;
  editor.insertionPointColor = self.palette.controlText;
  editor.backgroundColor = self.palette.controlSurface;
  editor.selectedTextAttributes = @{NSBackgroundColorAttributeName:self.palette.controlFocus,
                                    NSForegroundColorAttributeName:self.palette.controlText};
  self.searchSurface.layer.borderColor = self.palette.controlFocus.CGColor;
}
- (void)controlTextDidBeginEditing:(NSNotification *)notification { [self updateFieldEditor]; }
- (void)controlTextDidEndEditing:(NSNotification *)notification {
  self.searchSurface.layer.borderColor = self.palette.controlBorder.CGColor;
}
- (void)controlTextDidChange:(NSNotification *)notification {
  if (self.queryChangedHandler) self.queryChangedHandler();
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
  if (command == @selector(cancelOperation:)) { [self close:nil]; return YES; }
  if (command == @selector(insertNewline:) || command == @selector(insertNewlineIgnoringFieldEditor:)) {
    BOOL forward = !(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift);
    if (self.navigateHandler) self.navigateHandler(forward);
    return YES;
  }
  return NO;
}
- (void)focusSearchField { [self.searchField selectText:nil]; [self updateFieldEditor]; }
- (void)setMatchCount:(NSInteger)count activeMatch:(NSInteger)activeMatch searching:(BOOL)searching {
  BOOL hasQuery = self.searchField.stringValue.length > 0;
  self.noMatches = hasQuery && !searching && count == 0;
  self.resultLabel.stringValue = !hasQuery ? @"" : searching ? @"…" : count == 0 ? @"0 matches" :
    [NSString stringWithFormat:@"%ld/%ld", (long)MAX(0, activeMatch), (long)count];
  [self.resultLabel setAccessibilityLabel:hasQuery ? (searching ? @"Searching" :
    [NSString stringWithFormat:@"Match %ld of %ld", (long)MAX(0, activeMatch), (long)count]) : @"Match count"];
  self.previousButton.enabled = self.nextButton.enabled = hasQuery && count > 0;
  self.needsLayout = YES;
}
- (void)previous:(id)sender { if (self.navigateHandler) self.navigateHandler(NO); }
- (void)next:(id)sender { if (self.navigateHandler) self.navigateHandler(YES); }
- (void)close:(id)sender { if (self.closeHandler) self.closeHandler(); }
@end
