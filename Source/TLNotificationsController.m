#import "TLNotificationsController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLNotificationStackView.h"

@interface TLNotificationsController ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) TLFlippedView *documentView;
@property (nonatomic, copy) NSArray<TLNotificationStackView *> *groupViews;
@property (nonatomic, strong) NSMutableDictionary<NSArray *, TLNotificationStackView *> *groupsByKey;
@property (nonatomic, strong) NSLayoutConstraint *titleLeading;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailing;
@property (nonatomic, strong) NSLayoutConstraint *titleTop;
@property (nonatomic, strong) NSLayoutConstraint *scrollTop;
@property (nonatomic) BOOL layingOut;
@end

@implementation TLNotificationsController
- (instancetype)initWithPalette:(TLThemePalette *)palette {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _palette = palette; _notifications = @[]; _groupViews = @[];
    _groupsByKey = [NSMutableDictionary dictionary];
    [self buildView]; [self applyPalette]; [self updateStatus];
  }
  return self;
}
- (void)buildView {
  self.view = [[TLTokenView alloc] initWithFrame:NSMakeRect(0, 0, self.palette.sidebarWidth, self.palette.space16)];
  self.view.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel = [NSTextField labelWithString:@"Notifications"];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
    forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.view addSubview:self.titleLabel];

  self.documentView = [[TLFlippedView alloc] initWithFrame:NSZeroRect];
  self.scrollView = [[NSScrollView alloc] init];
  self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scrollView.hasVerticalScroller = YES;
  self.scrollView.hasHorizontalScroller = NO;
  self.scrollView.autohidesScrollers = YES;
  self.scrollView.drawsBackground = NO;
  self.scrollView.documentView = self.documentView;
  self.scrollView.contentView.postsFrameChangedNotifications = YES;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(viewportResized:)
    name:NSViewFrameDidChangeNotification object:self.scrollView.contentView];
  [self.view addSubview:self.scrollView];
  self.statusLabel = [NSTextField wrappingLabelWithString:@""];
  self.statusLabel.maximumNumberOfLines = 0;
  [self.documentView addSubview:self.statusLabel];
  self.titleLeading = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor];
  self.titleTrailing = [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor];
  self.titleTop = [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor];
  self.scrollTop = [self.scrollView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor];
  [NSLayoutConstraint activateConstraints:@[self.titleLeading, self.titleTrailing, self.titleTop, self.scrollTop,
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
}
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyPalette]; }
- (void)applyPalette {
  TLThemePalette *p = self.palette;
  ((TLTokenView *)self.view).fillColor = p.transparentSurface;
  self.titleLabel.font = p.smallFont; self.titleLabel.textColor = p.textMuted;
  self.statusLabel.font = p.smallFont; self.statusLabel.textColor = p.textMuted;
  self.titleLeading.constant = p.sidebarInboxItemHorizontalInset + p.sidebarInboxItemLeadingOffset;
  self.titleTrailing.constant = -p.sidebarInboxItemHorizontalInset;
  self.titleTop.constant = p.space5;
  self.scrollTop.constant = p.sidebarInboxHeaderItemGap;
  for (TLNotificationStackView *group in self.groupViews) group.palette = p;
  [self layoutDocument];
}
- (void)setNotifications:(NSArray<NSDictionary *> *)notifications {
  if ([_notifications isEqual:notifications]) return;
  _notifications = [notifications copy] ?: @[];
  NSMutableDictionary<NSArray *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
  for (id value in _notifications) {
    if (![value isKindOfClass:NSDictionary.class]) continue;
    NSDictionary *notification = value;
    id source = notification[@"source_kind"], task = notification[@"task_id"];
    if (![source isKindOfClass:NSString.class] || !task || task == NSNull.null) continue;
    NSArray *key = @[source, [task description]];
    if (!groups[key]) groups[key] = [NSMutableArray array];
    [groups[key] addObject:notification];
  }
  NSMutableArray *sortRecords = [NSMutableArray array];
  for (NSArray *key in groups) {
    NSArray<NSDictionary *> *ordered = [TLNotificationStackView orderedNotifications:groups[key]];
    NSMutableDictionary *record = [ordered.firstObject mutableCopy];
    record[@"group_key"] = key;
    // Group recency follows the latest item, even if its highest-urgency item is older.
    NSMutableArray *recencyCandidates = [NSMutableArray array];
    for (NSDictionary *item in ordered) {
      NSMutableDictionary *candidate = [item mutableCopy]; candidate[@"is_read"] = @YES;
      [recencyCandidates addObject:candidate];
    }
    NSDictionary *newest = [TLNotificationStackView orderedNotifications:recencyCandidates].firstObject;
    if (newest[@"updated_at"]) record[@"updated_at"] = newest[@"updated_at"];
    if (newest[@"created_at"]) record[@"created_at"] = newest[@"created_at"];
    [sortRecords addObject:record];
  }
  NSMutableArray *views = [NSMutableArray array];
  NSMutableDictionary *retained = [NSMutableDictionary dictionary];
  __weak typeof(self) weakSelf = self;
  for (NSDictionary *record in [TLNotificationStackView orderedNotifications:sortRecords]) {
    NSArray *key = record[@"group_key"];
    TLNotificationStackView *group = self.groupsByKey[key];
    if (!group) {
      group = [[TLNotificationStackView alloc] initWithFrame:NSZeroRect];
      group.translatesAutoresizingMaskIntoConstraints = YES;
      group.openHandler = ^(NSDictionary *item) { if (weakSelf.openHandler) weakSelf.openHandler(item); };
      group.readHandler = ^(NSDictionary *item, BOOL read) { if (weakSelf.readHandler) weakSelf.readHandler(item, read); };
      group.expansionChanged = ^(BOOL expanded) { [weakSelf layoutDocument]; };
      [self.documentView addSubview:group];
    }
    group.palette = self.palette; group.notifications = groups[key];
    [views addObject:group]; retained[key] = group;
  }
  for (NSArray *key in self.groupsByKey) if (!retained[key]) [self.groupsByKey[key] removeFromSuperview];
  self.groupsByKey = retained; self.groupViews = views;
  [self updateStatus];
}
- (void)setErrorMessage:(NSString *)errorMessage { _errorMessage = [errorMessage copy]; [self updateStatus]; }
- (void)setLoading:(BOOL)loading { _loading = loading; [self updateStatus]; }
- (void)updateStatus {
  NSString *status = self.errorMessage.length ? self.errorMessage :
    (self.loading ? @"Checking notifications…" : (self.groupViews.count ? @"" : @"You're all caught up."));
  self.statusLabel.stringValue = status;
  self.statusLabel.hidden = status.length == 0;
  [self layoutDocument];
}
- (void)viewDidLayout { [super viewDidLayout]; [self layoutDocument]; }
- (void)viewportResized:(NSNotification *)notification { [self layoutDocument]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutDocument {
  if (self.layingOut || !self.scrollView) return;
  self.layingOut = YES;
  TLThemePalette *p = self.palette;
  CGFloat width = MAX(1, NSWidth(self.scrollView.contentView.bounds));
  CGFloat y = 0;
  if (!self.statusLabel.hidden) {
    CGFloat labelWidth = MAX(1, width - p.sidebarInboxItemHorizontalInset * 2);
    self.statusLabel.preferredMaxLayoutWidth = labelWidth;
    NSRect text = [self.statusLabel.stringValue boundingRectWithSize:NSMakeSize(labelWidth, CGFLOAT_MAX)
      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
      attributes:@{NSFontAttributeName:p.smallFont}];
    CGFloat height = ceil(MAX(self.statusLabel.intrinsicContentSize.height, NSHeight(text)));
    self.statusLabel.frame = NSMakeRect(p.sidebarInboxItemHorizontalInset, p.space4, labelWidth, height);
    y += height + p.space4 * 2;
  }
  for (TLNotificationStackView *group in self.groupViews) {
    CGFloat groupWidth = MAX(1, width - p.sidebarInboxItemLeadingOffset);
    [group setFrameSize:NSMakeSize(groupWidth, NSHeight(group.frame))];
    CGFloat height = group.intrinsicContentSize.height;
    group.frame = NSMakeRect(p.sidebarInboxItemLeadingOffset, y, groupWidth, height);
    [group layoutSubtreeIfNeeded];
    y += height + p.space4;
  }
  self.documentView.frame = NSMakeRect(0, 0, width, MAX(y, NSHeight(self.scrollView.contentView.bounds)));
  self.layingOut = NO;
}
@end
