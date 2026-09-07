#import "TLSettingsWorkspaceView.h"

@interface TLSettingsWorkspaceView ()
@property TLTokenView *topBar;
@end

@implementation TLSettingsWorkspaceView
- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  _showsSidebar = YES;
  _topBar = [[TLTokenView alloc] init];
  _sectionTabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Agent", @"Browser", @"Application"]
    trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
  _sectionTabs.segmentStyle = NSSegmentStyleRounded;
  _sectionTabs.segmentDistribution = NSSegmentDistributionFillEqually;
  _sectionTabs.selectedSegment = 0;
  _sectionTabs.accessibilityLabel = @"Settings sections";
  [_topBar addSubview:_sectionTabs];
  [self addSubview:_topBar];
  _sidebar = [[TLTokenView alloc] init];
  _header = [[NSView alloc] init];
  _pageHost = [[NSView alloc] init];
  _footer = [[TLTokenView alloc] init];
  _pageMenu = [[NSPopUpButton alloc] init];
  _pageTitle = [NSTextField labelWithString:@""];
  _pageDescription = [NSTextField wrappingLabelWithString:@""];
  for (NSView *view in @[_sidebar, _header, _pageHost, _footer]) [self addSubview:view];
  for (NSView *view in @[_pageMenu, _pageTitle, _pageDescription]) [_header addSubview:view];
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.fillColor = palette.tabBackground;
  self.topBar.fillColor = palette.tabBackground;
  self.topBar.borderColor = palette.controlBorder;
  self.topBar.borderEdges = TLBorderEdgeBottom;
  self.topBar.borderWidth = palette.borderWidth;
  self.sidebar.fillColor = palette.sidebarSurface;
  self.sidebar.borderColor = palette.sidebarBorder;
  self.sidebar.borderEdges = TLBorderEdgeRight;
  self.sidebar.borderWidth = palette.borderWidth;
  self.footer.fillColor = palette.tabBackground;
  self.footer.borderColor = palette.controlBorder;
  self.footer.borderEdges = TLBorderEdgeTop;
  self.footer.borderWidth = palette.borderWidth;
  self.pageTitle.font = palette.titleFont;
  self.pageTitle.textColor = palette.appText;
  self.pageDescription.font = palette.bodyFont;
  self.pageDescription.textColor = palette.textMuted;
  self.pageMenu.font = palette.bodyFont;
  self.needsLayout = YES;
}
- (void)setShowsSidebar:(BOOL)showsSidebar {
  _showsSidebar = showsSidebar;
  self.needsLayout = YES;
}
- (void)layout {
  [super layout];
  TLThemePalette *p = self.palette;
  BOOL compact = NSWidth(self.bounds) < p.settingsCompactWidth;
  CGFloat side = compact || !self.showsSidebar ? 0 : p.settingsSidebarWidth;
  CGFloat width = MAX(0, NSWidth(self.bounds) - side);
  CGFloat inset = compact ? p.space8 : p.space12;
  CGFloat headerHeight = p.settingsActionHeight + p.space12 * (compact ? 4 : 2);
  CGFloat footerHeight = p.settingsActionHeight + p.space8 * 2;
  CGFloat topHeight = p.settingsActionHeight + p.space8 * 2;
  CGFloat height = MAX(0, NSHeight(self.bounds) - topHeight);
  self.topBar.frame = NSMakeRect(0, height, NSWidth(self.bounds), topHeight);
  CGFloat tabWidth = MIN(p.settingsSidebarWidth * 2, MAX(0, NSWidth(self.bounds) - p.space8 * 2));
  self.sectionTabs.controlSize = compact ? NSControlSizeSmall : NSControlSizeRegular;
  self.sectionTabs.segmentDistribution = compact ? NSSegmentDistributionFillProportionally : NSSegmentDistributionFillEqually;
  self.sectionTabs.font = compact ? p.smallFont : p.labelFont;
  self.sectionTabs.frame = NSMakeRect((NSWidth(self.bounds) - tabWidth) / 2, p.space8, tabWidth, p.settingsActionHeight);
  self.sidebar.hidden = compact || !self.showsSidebar;
  self.sidebar.frame = NSMakeRect(0, 0, side, height);
  self.header.frame = NSMakeRect(side, MAX(0, height - headerHeight), width, headerHeight);
  self.footer.frame = NSMakeRect(side, 0, width, footerHeight);
  CGFloat pageBottom = self.footer.hidden ? 0 : footerHeight;
  self.pageHost.frame = NSMakeRect(side, pageBottom, width, MAX(0, height - headerHeight - pageBottom));
  self.pageMenu.hidden = !compact || !self.showsSidebar;
  self.pageTitle.hidden = compact && self.showsSidebar;
  inset = MAX(inset, (width - p.settingsContentMaxWidth) / 2);
  CGFloat titleY = headerHeight - p.space12 - p.settingsActionHeight;
  self.pageMenu.frame = NSMakeRect(inset, titleY, MAX(0, width - inset * 2), p.settingsActionHeight);
  self.pageTitle.frame = NSMakeRect(inset, titleY, MAX(0, width - inset * 2), p.settingsActionHeight);
  self.pageDescription.frame = NSMakeRect(inset, p.space8, MAX(0, width - inset * 2), compact ? p.space12 * 2 : p.space12);
}
@end
