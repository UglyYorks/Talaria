#import "TLRuntimeActivityView.h"
#import "TLThemedButton.h"

@interface TLRuntimeActivityView ()
@property (nonatomic, strong) TLThemedButton *disclosure;
@property (nonatomic, strong) NSTextField *preview;
@property (nonatomic, strong) NSMutableSet<NSString *> *expandedRows;
@property (nonatomic, strong) NSStackView *details;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSScrollView *> *outputViews;
@end

@implementation TLRuntimeActivityView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    _activities = @[]; _statusText = @""; _expandedRows = [NSMutableSet set];
    _outputViews = [NSMutableDictionary dictionary];
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _disclosure = [TLThemedButton new];
    _disclosure.imagePosition = NSImageLeft;
    _disclosure.target = self; _disclosure.action = @selector(toggle:);
    [self addArrangedSubview:_disclosure];
    [_disclosure.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor].active = YES;
    _preview = [NSTextField wrappingLabelWithString:@""];
    _preview.maximumNumberOfLines = 2;
    _preview.lineBreakMode = NSLineBreakByWordWrapping;
    _preview.selectable = YES;
    [self addArrangedSubview:_preview];
    [_preview.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    _details = [NSStackView new];
    _details.orientation = NSUserInterfaceLayoutOrientationVertical;
    _details.alignment = NSLayoutAttributeLeading;
    [self addArrangedSubview:_details];
    [_details.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
    [self rebuild];
  }
  return self;
}
+ (NSString *)summaryForActivity:(NSDictionary *)activity {
  NSString *value = [activity[@"kind"] isEqual:@"agent"] ? activity[@"name"] :
    [activity[@"summary"] length] ? activity[@"summary"] : [activity[@"detail"] length] ? activity[@"detail"] : activity[@"name"];
  NSString *line = [[value ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] firstObject];
  line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return line.length > 100 ? [[line substringToIndex:99] stringByAppendingString:@"…"] : line;
}
- (void)toggleRow:(NSButton *)sender {
  NSString *identity = sender.identifier;
  if ([self.expandedRows containsObject:identity]) [self.expandedRows removeObject:identity];
  else [self.expandedRows addObject:identity];
  [self rebuild];
}
- (void)toggle:(id)sender { self.expanded = !self.expanded; }
- (void)layout {
  CGFloat width = NSWidth(self.bounds);
  self.preview.preferredMaxLayoutWidth = width;
  for (NSStackView *card in self.details.arrangedSubviews) {
    for (NSView *view in card.arrangedSubviews) if ([view isKindOfClass:NSTextField.class]) {
      ((NSTextField *)view).preferredMaxLayoutWidth = width;
    }
  }
  [super layout];
}
- (void)setExpanded:(BOOL)expanded { if (_expanded == expanded) return; _expanded = expanded; [self rebuild]; }
- (void)setPalette:(TLThemePalette *)palette { if (_palette == palette) return; _palette = palette; [self rebuild]; }
- (void)setStatusText:(NSString *)text { if ([_statusText isEqual:text]) return; _statusText = [text copy] ?: @""; [self rebuild]; }
- (void)setActivities:(NSArray<NSDictionary *> *)activities {
  if ([_activities isEqual:activities]) return;
  _activities = [activities copy] ?: @[];
  NSSet *identities = [NSSet setWithArray:[_activities valueForKey:@"id"]];
  for (NSString *identity in self.outputViews.allKeys) if (![identities containsObject:identity]) [self.outputViews removeObjectForKey:identity];
  [self.expandedRows intersectSet:identities];
  [self rebuild];
}
- (NSTextField *)label:(NSString *)text inStack:(NSStackView *)stack title:(BOOL)title {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.font = title ? self.palette.roleFont : self.palette.smallFont;
  label.textColor = title ? self.palette.labelText : self.palette.textMuted;
  label.selectable = YES;
  label.maximumNumberOfLines = title ? 2 : 4;
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.toolTip = text;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  [stack addArrangedSubview:label];
  [label.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  return label;
}
- (void)rebuild {
  self.hidden = !self.activities.count && !self.statusText.length;
  self.spacing = self.palette.space4;
  self.details.spacing = self.palette.space8;
  self.disclosure.palette = self.palette;
  NSUInteger active = 0;
  NSDictionary *latest = self.activities.lastObject;
  for (NSDictionary *row in self.activities) {
    if ([@[@"preparing", @"running"] containsObject:row[@"state"]]) {
      if (!active || [row[@"updated"] integerValue] >= [latest[@"updated"] integerValue]) latest = row;
      active++;
    }
  }
  self.disclosure.title = active ? [NSString stringWithFormat:@"Activity · %lu running", active] : @"Activity";
  self.disclosure.image = [NSImage imageWithSystemSymbolName:self.expanded ? @"chevron.down" : @"chevron.right" accessibilityDescription:nil];
  self.disclosure.accessibilityLabel = self.disclosure.title;
  self.disclosure.accessibilityValue = self.expanded ? @"Expanded" : @"Collapsed";
  NSString *preview = [latest[@"summary"] length] ? latest[@"summary"] : [latest[@"detail"] length] ? latest[@"detail"] : latest[@"name"] ?: @"";
  if ([latest[@"output"] length]) {
    NSArray *lines = [latest[@"output"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines.reverseObjectEnumerator) if (line.length) { preview = line; break; }
  }
  self.preview.stringValue = self.statusText.length ? self.statusText : preview;
  self.preview.font = self.palette.smallFont;
  self.preview.textColor = self.palette.textMuted;
  self.preview.hidden = self.expanded || !self.preview.stringValue.length;
  for (NSView *view in self.details.arrangedSubviews.copy) { [self.details removeArrangedSubview:view]; [view removeFromSuperview]; }
  self.details.hidden = !self.expanded;
  if (!self.expanded) return;
  NSDictionary *states = @{@"preparing":@"Starting", @"running":@"Running", @"completed":@"Done", @"failed":@"Failed",
    @"stopped":@"Stopped", @"interrupted":@"Disconnected", @"ended":@"Ended"};
  // Newest entries are closest to the disclosure; the cache has a fixed row budget.
  NSArray *ordered = [self.activities sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    BOOL aRunning = [@[@"running", @"preparing"] containsObject:a[@"state"]];
    BOOL bRunning = [@[@"running", @"preparing"] containsObject:b[@"state"]];
    if (aRunning != bRunning) return aRunning ? NSOrderedAscending : NSOrderedDescending;
    return [@([b[@"updated"] integerValue]) compare:@([a[@"updated"] integerValue])];
  }];
  for (NSDictionary *row in ordered) {
    NSStackView *card = [NSStackView new];
    card.orientation = NSUserInterfaceLayoutOrientationVertical;
    card.alignment = NSLayoutAttributeLeading;
    card.spacing = self.palette.space3;
    [self.details addArrangedSubview:card];
    [card.widthAnchor constraintEqualToAnchor:self.details.widthAnchor].active = YES;
    NSString *state = [row[@"kind"] isEqual:@"notice"] ? @"Update" : states[row[@"state"]] ?: @"Update";
    NSStackView *header = [NSStackView new];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.distribution = NSStackViewDistributionFill;
    header.spacing = self.palette.space4;
    [card addArrangedSubview:header];
    [header.widthAnchor constraintEqualToAnchor:card.widthAnchor].active = YES;
    NSString *name = [self.class summaryForActivity:@{@"name":row[@"name"] ?: @"Activity"}];
    NSTextField *title = [NSTextField labelWithString:[NSString stringWithFormat:@"%@ · %@", state, name]];
    title.font = self.palette.roleFont; title.textColor = self.palette.labelText;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:title];
    BOOL open = [self.expandedRows containsObject:row[@"id"]];
    TLThemedButton *toggle = [TLThemedButton new];
    toggle.palette = self.palette; toggle.identifier = row[@"id"];
    [toggle setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [toggle setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [title setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    toggle.title = @""; toggle.imagePosition = NSImageOnly;
    toggle.image = [NSImage imageWithSystemSymbolName:open ? @"chevron.up" : @"chevron.down" accessibilityDescription:nil];
    toggle.image.template = YES;
    toggle.target = self; toggle.action = @selector(toggleRow:);
    toggle.accessibilityLabel = [NSString stringWithFormat:@"%@ details for %@", open ? @"Hide" : @"Show", name];
    [header addArrangedSubview:toggle];
    if (!open) {
      NSString *summary = [self.class summaryForActivity:row];
      if (summary.length && ![summary isEqual:name]) {
        NSTextField *line = [self label:summary inStack:card title:NO];
        line.maximumNumberOfLines = 1; line.lineBreakMode = NSLineBreakByTruncatingTail;
      }
      continue;
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"model", @"goal", @"detail", @"summary", @"output"]) {
      NSString *part = row[key];
      if (part.length && ![parts containsObject:part]) [parts addObject:part];
    }
    NSString *fullText = [parts componentsJoinedByString:@"\n\n"];
    if (!fullText.length) fullText = name;
    NSScrollView *scroll = self.outputViews[row[@"id"]];
    BOOL created = scroll == nil;
    if (!scroll) { scroll = [NSScrollView new]; self.outputViews[row[@"id"]] = scroll; }
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = self.palette.markdownCodeSurface;
    scroll.wantsLayer = YES;
    scroll.layer.cornerRadius = self.palette.radiusMedium;
    NSTextView *output = (id)scroll.documentView;
    if (!output) output = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 160, 120)];
    NSRange selection = output.selectedRange;
    NSPoint origin = scroll.contentView.bounds.origin;
    BOOL followsTail = created || NSMaxY(scroll.documentVisibleRect) >= NSHeight(output.bounds) - 2;
    output.editable = NO; output.selectable = YES;
    output.richText = NO; output.automaticLinkDetectionEnabled = NO;
    output.font = self.palette.markdownCodeFont;
    output.textColor = self.palette.markdownCodeText;
    output.backgroundColor = self.palette.markdownCodeSurface;
    output.textContainerInset = NSMakeSize(self.palette.space4, self.palette.space4);
    output.autoresizingMask = NSViewWidthSizable;
    output.textContainer.widthTracksTextView = YES;
    output.verticallyResizable = YES; output.horizontallyResizable = NO;
    if (![output.string isEqual:fullText]) {
      output.string = fullText;
      selection.location = MIN(selection.location, output.string.length);
      selection.length = MIN(selection.length, output.string.length - selection.location);
      output.selectedRange = selection;
    }
    output.accessibilityLabel = [row[@"kind"] isEqual:@"process"] ? @"Terminal output" : @"Activity details";
    scroll.documentView = output;
    [card addArrangedSubview:scroll];
    [scroll.widthAnchor constraintEqualToAnchor:card.widthAnchor].active = YES;
    if (created) [scroll.heightAnchor constraintEqualToConstant:self.palette.space10 * 8].active = YES;
    if (followsTail && !selection.length) [output scrollRangeToVisible:NSMakeRange(output.string.length, 0)];
    else [scroll.contentView scrollToPoint:origin];
  }
}
@end
