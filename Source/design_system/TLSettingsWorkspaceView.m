#import "TLSettingsWorkspaceView.h"

@implementation TLSettingsWorkspaceView
- (instancetype)init {
  self = [super init];
  if (!self) return nil;
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
- (void)layout {
  [super layout];
  TLThemePalette *p = self.palette;
  BOOL compact = NSWidth(self.bounds) < p.settingsCompactWidth;
  CGFloat side = compact ? 0 : p.settingsSidebarWidth;
  CGFloat width = MAX(0, NSWidth(self.bounds) - side);
  CGFloat inset = compact ? p.space8 : p.space12;
  CGFloat headerHeight = p.settingsActionHeight + p.space12 * (compact ? 4 : 2);
  CGFloat footerHeight = p.settingsActionHeight + p.space8 * 2;
  CGFloat height = NSHeight(self.bounds);
  self.sidebar.hidden = compact;
  self.sidebar.frame = NSMakeRect(0, 0, side, height);
  self.header.frame = NSMakeRect(side, MAX(0, height - headerHeight), width, headerHeight);
  self.footer.frame = NSMakeRect(side, 0, width, footerHeight);
  CGFloat pageBottom = self.footer.hidden ? 0 : footerHeight;
  self.pageHost.frame = NSMakeRect(side, pageBottom, width, MAX(0, height - headerHeight - pageBottom));
  self.pageMenu.hidden = !compact;
  self.pageTitle.hidden = compact;
  CGFloat titleY = headerHeight - p.space12 - p.settingsActionHeight;
  self.pageMenu.frame = NSMakeRect(inset, titleY, MAX(0, width - inset * 2), p.settingsActionHeight);
  self.pageTitle.frame = NSMakeRect(inset, titleY, MAX(0, width - inset * 2), p.settingsActionHeight);
  self.pageDescription.frame = NSMakeRect(inset, p.space8, MAX(0, width - inset * 2), compact ? p.space12 * 2 : p.space12);
}
@end
