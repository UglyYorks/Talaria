#import "TLSystemSidebarController.h"
#import "TLNotificationsController.h"
#import "design_system/TLSidebarSelectionButton.h"
#import "design_system/UIComponents.h"

@interface TLProjectsListView : NSStackView
@end
@implementation TLProjectsListView
- (BOOL)isFlipped { return YES; }
@end

@interface TLSystemSidebarController ()
@property (nonatomic, strong) TLNotificationsController *notificationsController;
@property (nonatomic, strong) TLSidebarSelectionButton *projectsTab;
@property (nonatomic, strong) TLSidebarSelectionButton *notificationsTab;
@property (nonatomic, strong) NSScrollView *projectsScroll;
@property (nonatomic, strong) NSStackView *projectsList;
@property (nonatomic) BOOL showingProjects;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *sessionRows;
@end

@implementation TLSystemSidebarController

- (instancetype)initWithPalette:(TLThemePalette *)palette notifications:(TLNotificationsController *)notifications {
  if ((self = [super initWithNibName:nil bundle:nil])) {
    _palette = palette;
    _notificationsController = notifications;
    _projects = @[];
    _sessionRows = [NSMutableArray array];
    _showingProjects = YES;
    notifications.showsTitle = NO;
    [self buildView];
    [self applyPalette];
    [self rebuildProjects];
  }
  return self;
}

- (void)buildView {
  TLThemePalette *p = self.palette;
  self.view = [[TLTokenView alloc] initWithFrame:NSMakeRect(0, 0, p.sidebarWidth, p.space16)];
  self.view.translatesAutoresizingMaskIntoConstraints = NO;
  NSStackView *tabs = [[NSStackView alloc] init];
  tabs.translatesAutoresizingMaskIntoConstraints = NO;
  tabs.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  tabs.distribution = NSStackViewDistributionFillEqually;
  tabs.spacing = p.space3;
  self.projectsTab = [TLSidebarSelectionButton buttonWithTitle:@"Projects" target:self action:@selector(showProjects:)];
  self.notificationsTab = [TLSidebarSelectionButton buttonWithTitle:@"Notifications" target:self action:@selector(showNotifications:)];
  self.projectsTab.compact = YES;
  self.notificationsTab.compact = YES;
  self.projectsTab.accessibilityLabel = @"Projects";
  self.notificationsTab.accessibilityLabel = @"Notifications";
  [tabs addArrangedSubview:self.projectsTab];
  [tabs addArrangedSubview:self.notificationsTab];
  [self.view addSubview:tabs];

  self.projectsList = [[TLProjectsListView alloc] init];
  self.projectsList.translatesAutoresizingMaskIntoConstraints = NO;
  self.projectsList.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.projectsList.alignment = NSLayoutAttributeWidth;
  self.projectsList.spacing = p.space3;
  self.projectsScroll = [[NSScrollView alloc] init];
  self.projectsScroll.translatesAutoresizingMaskIntoConstraints = NO;
  self.projectsScroll.drawsBackground = NO;
  self.projectsScroll.hasVerticalScroller = YES;
  self.projectsScroll.autohidesScrollers = YES;
  self.projectsScroll.documentView = self.projectsList;
  [self.view addSubview:self.projectsScroll];
  NSView *notifications = self.notificationsController.view;
  notifications.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:notifications];
  CGFloat inset = p.sidebarInboxItemHorizontalInset;
  [NSLayoutConstraint activateConstraints:@[
    [tabs.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:inset],
    [tabs.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-inset],
    [tabs.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:p.space4],
    [self.projectsScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.projectsScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.projectsScroll.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:p.space5],
    [self.projectsScroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.projectsList.leadingAnchor constraintEqualToAnchor:self.projectsScroll.contentView.leadingAnchor],
    [self.projectsList.topAnchor constraintEqualToAnchor:self.projectsScroll.contentView.topAnchor],
    [self.projectsList.widthAnchor constraintEqualToAnchor:self.projectsScroll.contentView.widthAnchor],
    [notifications.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [notifications.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [notifications.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:p.space5],
    [notifications.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  ]];
  [self selectProjects:YES];
}

- (void)showProjects:(id)sender { [self selectProjects:YES]; }
- (void)showNotifications:(id)sender { [self selectProjects:NO]; }
- (void)selectProjects:(BOOL)projects {
  self.showingProjects = projects;
  self.projectsScroll.hidden = !projects;
  self.notificationsController.view.hidden = projects;
  self.projectsTab.selected = projects;
  self.notificationsTab.selected = !projects;
  self.projectsTab.accessibilityValue = projects ? @"Selected" : @"Not selected";
  self.notificationsTab.accessibilityValue = projects ? @"Not selected" : @"Selected";
}

- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self applyPalette]; }
- (void)applyPalette {
  TLThemePalette *p = self.palette;
  ((TLTokenView *)self.view).fillColor = p.transparentSurface;
  self.projectsTab.palette = p;
  self.notificationsTab.palette = p;
  self.projectsList.spacing = p.space3;
  [self rebuildProjects];
}
- (void)setProjects:(NSArray<NSDictionary *> *)projects {
  if ([_projects isEqual:projects]) return;
  _projects = [projects copy] ?: @[];
  [self rebuildProjects];
}
- (void)setSelectedProject:(NSDictionary *)selectedProject {
  if ([_selectedProject isEqual:selectedProject]) return;
  _selectedProject = [selectedProject copy];
  [self rebuildProjects];
}
- (void)setErrorMessage:(NSString *)errorMessage {
  if ([_errorMessage isEqual:errorMessage]) return;
  _errorMessage = [errorMessage copy];
  [self rebuildProjects];
}
- (void)setLoading:(BOOL)loading {
  if (_loading == loading) return;
  _loading = loading;
  [self rebuildProjects];
}

- (void)addStatus:(NSString *)message {
  NSTextField *label = [NSTextField wrappingLabelWithString:message];
  label.font = self.palette.smallFont;
  label.textColor = self.palette.textMuted;
  [self.projectsList addArrangedSubview:label];
  [label.widthAnchor constraintEqualToAnchor:self.projectsList.widthAnchor
                                    constant:-self.palette.sidebarInboxItemHorizontalInset * 2].active = YES;
}

- (void)rebuildProjects {
  if (!self.projectsList) return;
  for (NSView *view in self.projectsList.arrangedSubviews.copy) {
    [self.projectsList removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  [self.sessionRows removeAllObjects];
  if (self.errorMessage.length) [self addStatus:self.errorMessage];
  else if (self.loading && !self.projects.count) [self addStatus:@"Loading projects…"];
  else if (!self.projects.count) [self addStatus:@"No Hermes projects yet."];

  NSString *selectedID = [self.selectedProject[@"id"] isKindOfClass:NSString.class] ? self.selectedProject[@"id"] : nil;
  for (NSDictionary *project in self.projects) {
    NSString *projectID = [project[@"id"] isKindOfClass:NSString.class] ? project[@"id"] : nil;
    if (!projectID.length) continue;
    NSString *label = [project[@"label"] isKindOfClass:NSString.class] ? project[@"label"] : projectID;
    NSInteger count = [project[@"sessionCount"] respondsToSelector:@selector(integerValue)] ? [project[@"sessionCount"] integerValue] : 0;
    NSString *title = [NSString stringWithFormat:@"%@  (%ld)", label, (long)count];
    TLSidebarSelectionButton *button = [TLSidebarSelectionButton buttonWithTitle:title target:self action:@selector(openProject:)];
    button.palette = self.palette;
    button.selected = [projectID isEqualToString:selectedID];
    button.identifier = projectID;
    button.alignment = NSTextAlignmentLeft;
    button.lineBreakMode = NSLineBreakByTruncatingTail;
    button.toolTip = [project[@"path"] isKindOfClass:NSString.class] ? project[@"path"] : label;
    [self.projectsList addArrangedSubview:button];
    [button.widthAnchor constraintEqualToAnchor:self.projectsList.widthAnchor].active = YES;
    if (![projectID isEqualToString:selectedID]) continue;
    if (self.loading) [self addStatus:@"Loading sessions…"];
    NSArray *repos = [self.selectedProject[@"repos"] isKindOfClass:NSArray.class] ? self.selectedProject[@"repos"] : @[];
    BOOL hasSessions = NO;
    for (NSDictionary *repo in repos) {
      if (![repo isKindOfClass:NSDictionary.class]) continue;
      for (NSDictionary *group in repo[@"groups"] ?: @[]) {
        if (![group isKindOfClass:NSDictionary.class]) continue;
        for (NSDictionary *session in group[@"sessions"] ?: @[]) {
          if (![session isKindOfClass:NSDictionary.class] || ![session[@"id"] isKindOfClass:NSString.class]) continue;
          hasSessions = YES;
          NSString *name = [session[@"title"] isKindOfClass:NSString.class] && [session[@"title"] length] ? session[@"title"] : @"Untitled session";
          TLSidebarSelectionButton *row = [TLSidebarSelectionButton buttonWithTitle:[@"    " stringByAppendingString:name]
            target:self action:@selector(openSession:)];
          row.palette = self.palette;
          row.alignment = NSTextAlignmentLeft;
          row.lineBreakMode = NSLineBreakByTruncatingTail;
          row.tag = self.sessionRows.count;
          [self.sessionRows addObject:session];
          row.toolTip = name;
          [self.projectsList addArrangedSubview:row];
          [row.widthAnchor constraintEqualToAnchor:self.projectsList.widthAnchor].active = YES;
        }
      }
    }
    if (!self.loading && !hasSessions) [self addStatus:@"No sessions in this project."];
  }
}

- (void)openProject:(TLSidebarSelectionButton *)sender {
  NSString *projectID = sender.identifier;
  if (self.projectHandler && projectID.length) self.projectHandler(projectID);
}
- (void)openSession:(TLSidebarSelectionButton *)sender {
  NSDictionary *session = sender.tag >= 0 && (NSUInteger)sender.tag < self.sessionRows.count ? self.sessionRows[sender.tag] : nil;
  if (self.sessionHandler && session) self.sessionHandler(session);
}
@end
