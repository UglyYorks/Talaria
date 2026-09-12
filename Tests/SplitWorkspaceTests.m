#import <AppKit/AppKit.h>
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLChatTabController.h"
#import "TLWorkspaceSplitState.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLSplitWorkspaceView.h"
#import "design_system/TLChromeTabView.h"
#import "WorkspaceTabRuntime.h"
#import "AppStateManager.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLButton.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]]; }
static void DispatchDragEvent(NSEvent *event) {
  // Exercise AppKit's event delivery and local monitors, including when the
  // original tab has been detached. Direct mouseUp calls cannot catch this bug.
  [NSApp postEvent:event atStart:YES];
  NSEvent *next=[NSApp nextEventMatchingMask:((NSEventMask)1 << event.type)
    untilDate:NSDate.date inMode:NSDefaultRunLoopMode dequeue:YES];
  if (next) [NSApp sendEvent:next];
}
static TLWorkspaceTab *Tab(NSInteger n) {
  return [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindChat tabID:n title:@"Chat" toolTip:nil URL:nil closeable:YES];
}

@interface TalariaWindowController (SplitTests)
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)size;
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)installEffectiveAppearanceObserver;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)left;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other placement:(TLSplitPlacement)placement;
- (void)focusSplitPane:(BOOL)right;
- (NSArray<TLWorkspaceTab *> *)workspaceTabsForTabsController:(TLWorkspaceTabsController *)controller;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller moveTab:(TLWorkspaceTab *)tab toIndex:(NSUInteger)index;
- (void)loadChatWithID:(NSInteger)chatID;
- (void)updateWorkspaceMode;
- (void)updateControlStates;
- (void)applyTheme;
- (void)closeChatTabWithID:(NSInteger)chatID;
- (void)closeActiveTabOrWindow:(id)sender;
- (BOOL)persistActiveDraftChatWithModel:(NSString *)model;
- (void)scheduleStreamingMessageRender;
- (void)renderMessagesScrollingToBottom:(BOOL)scrollToBottom;
- (void)updateMessageScrollInsets;
- (void)restoreAttachmentDraft:(NSArray<NSURL *> *)URLs prompt:(NSString *)prompt chatID:(NSInteger)chatID;
- (void)openBrowserTab:(id)sender;
- (void)openBrowserTabWithURL:(NSURL *)URL;
- (void)sendMessage:(id)sender allowAutomaticRouting:(BOOL)allowAutomaticRouting;
- (BOOL)performInputSuggestionAtIndex:(NSUInteger)index;
- (void)updateSlashCommandList;
- (void)flushSlashCommandUpdate;
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab;
- (void)openLinkURL:(NSURL *)URL inSplitBesideBrowserTabID:(NSInteger)tabID;
- (void)handleContextLinkURL:(NSURL *)URL destination:(TLBrowserLinkDestination)destination sourceIdentity:(NSString *)identity;
- (void)closeBrowserTab:(id)sender;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller willSelectTab:(TLWorkspaceTab *)tab;
- (BOOL)workspaceTabsController:(TLWorkspaceTabsController *)controller dragTab:(TLWorkspaceTab *)tab atWindowPoint:(NSPoint)point;
- (void)workspaceTabsController:(TLWorkspaceTabsController *)controller endDraggingTab:(TLWorkspaceTab *)tab cancelled:(BOOL)cancelled;
@end

// Real native workspace and action routing, with no VM, network, credentials or user data.
@interface TLSplitTestController : TalariaWindowController
@property (nonatomic, strong) TLChatTabController *lastScrollPresentation;
@end
@implementation TLSplitTestController
- (void)ensureBrowserRuntimeForTab:(TLWorkspaceTab *)tab {
  NSMutableDictionary *runtimes = [self valueForKey:@"workspaceTabRuntimes"];
  NSString *key = TLWorkspaceTabRuntimeKey(tab.kind, tab.tabID);
  if (!runtimes[key]) runtimes[key] = [TLWorkspaceTabRuntime runtimeWithContentView:[NSView new]
    openAction:@selector(openBrowserTab:) closeAction:@selector(closeBrowserTab:)];
}
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
- (void)updateMessageScrollInsets {
  self.lastScrollPresentation = [self valueForKey:@"chatPresentation"];
  [super updateMessageScrollInsets];
}
@end
@interface TLSplitTestDatabase : NSObject
@end
@implementation TLSplitTestDatabase
- (NSArray *)listBookmarks:(NSError **)error { return @[]; }
- (NSArray *)listBrowserHistory:(NSError **)error { return @[]; }
- (NSInteger)currentAgentID { return 0; }
- (TLChatRecord *)createChatWithModel:(NSString *)model supportingModel:(NSString *)supporting error:(NSError **)error {
  TLChatRecord *chat = [TLChatRecord new]; chat.chatID = 123; chat.model = model; chat.title = @"Saved chat"; chat.messages = @[]; return chat;
}
@end

static void TestGrouping(void) {
  TLWorkspaceSplitState *state = [TLWorkspaceSplitState new];
  TLWorkspaceTab *a = Tab(-1), *b = Tab(-2), *c = Tab(-3), *d = Tab(-4);
  [state splitTab:a besideTab:a onLeft:YES]; Check(state.groups.count == 0, @"cannot split a tab with itself");
  [state splitTab:a besideTab:b onLeft:YES];
  TLWorkspaceSplitGroup *group = [state groupForTab:a];
  Check(group == [state groupForTab:b] && [group.leftIdentity isEqual:TLWorkspaceTabIdentity(a)], @"both tabs resolve to the ordered pair");
  group.fraction = 0.7;
  [state splitTab:a besideTab:b onLeft:NO];
  Check([state groupForTab:a].fraction == 0.7 && [[state groupForTab:a].rightIdentity isEqual:TLWorkspaceTabIdentity(a)], @"moving a member preserves the divider preference");
  [state splitTab:c besideTab:d onLeft:YES];
  [state splitTab:a besideTab:c onLeft:YES];
  Check(state.groups.count == 1 && ![state groupForTab:b] && [state groupForTab:d] == [state groupForTab:a], @"adding a third pane preserves the destination companions");
  TLWorkspaceTab *saved = Tab(123); saved.presentationIdentity = TLWorkspaceTabIdentity(a);
  [state reconcileTabs:@[saved,b,c,d]];
  Check([state groupForTab:saved] != nil, @"saving a draft keeps its split");
  [state reconcileTabs:@[saved,b,d]];
  Check([state groupForTab:saved] == [state groupForTab:d], @"closing a member preserves the other two panes");
}
static void TestGrid(void) {
  TLWorkspaceSplitState *state = [TLWorkspaceSplitState new];
  NSMutableArray<TLWorkspaceTab *> *tabs = [NSMutableArray new];
  for (NSInteger i=1;i<=10;i++) [tabs addObject:Tab(-i)];
  [state splitTab:tabs[1] besideTab:tabs[0] placement:TLSplitPlacementBelow];
  [state splitTab:tabs[2] besideTab:tabs[1] placement:TLSplitPlacementBelow];
  Check(![state splitTab:tabs[9] besideTab:tabs[2] placement:TLSplitPlacementBelow], @"a fourth row is rejected without changing the group");
  for (NSUInteger r=1;r<3;r++) {
    Check([state splitTab:tabs[r*3] besideTab:tabs[(r-1)*3] placement:TLSplitPlacementRight], @"a column can be added beside an existing pane");
    [state splitTab:tabs[r*3+1] besideTab:tabs[r*3] placement:TLSplitPlacementBelow];
    [state splitTab:tabs[r*3+2] besideTab:tabs[r*3+1] placement:TLSplitPlacementBelow];
  }
  TLWorkspaceSplitGroup *group = [state groupForTab:tabs[0]];
  Check(group.columns.count == 3 && group.identities.count == 9, @"three columns of three views remain in one group");
  Check(![state splitTab:tabs[9] besideTab:tabs[8] placement:TLSplitPlacementRight] && ![state groupForTab:tabs[9]], @"a fourth column leaves the source tab standalone");
  Check([state splitTab:tabs[0] besideTab:tabs[2] placement:TLSplitPlacementBelow] && [group.columns[0].lastObject isEqual:TLWorkspaceTabIdentity(tabs[0])], @"dragging within a full column reorders without exceeding its limit");
  TLSplitWorkspaceView *view = [[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
  view.columns = group.columns; view.focusedIdentity = group.identities.firstObject;
  for (NSString *identity in group.identities) [view setTitle:[@"View " stringByAppendingString:identity] image:nil icon:@"" systemIcon:@"globe" forIdentity:identity];
  for (NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    view.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *width in @[@200,@480,@1000]) {
      view.frame = NSMakeRect(0,0,width.doubleValue,600); [view layoutSubtreeIfNeeded];
      NSMutableArray *frames = [NSMutableArray new];
      for (NSString *identity in group.identities) {
        NSView *host = [view hostForIdentity:identity];
        NSRect frame = host.frame;
        Check(host.layer.masksToBounds && host.layer.cornerRadius == view.palette.space5, @"each pane clips all its corners, including interior panes");
        Check(NSWidth(frame)>0 && NSHeight(frame)>0 && NSContainsRect(view.bounds,frame), @"all nine panes fit even in a 200px window");
        NSView *header = [view valueForKey:@"headers"][identity];
        NSRect pane = NSUnionRect(frame,header.frame);
        Check(NSContainsRect(NSInsetRect(view.bounds,view.palette.space5-0.01,view.palette.space5-0.01),pane), @"every split pane leaves padding at the workspace edges");
        Check([[view identityAtPoint:NSMakePoint(NSMidX(frame),NSMidY(frame))] isEqual:identity], @"focus hit testing identifies every grid cell");
        for (NSValue *other in frames) Check(!NSIntersectsRect(NSInsetRect(pane,-view.palette.space5/2+0.01,-view.palette.space5/2+0.01),NSInsetRect(other.rectValue,-view.palette.space5/2+0.01,-view.palette.space5/2+0.01)), @"grid panes retain spacing between their borders");
        [frames addObject:[NSValue valueWithRect:pane]];
      }
    }
    NSDictionary *headers = [view valueForKey:@"headers"];
    for (NSView *header in headers.allValues) {
      [header layoutSubtreeIfNeeded];
      NSButton *close = [header valueForKey:@"closeButton"];
      Check(NSContainsRect(header.bounds,close.frame), @"close buttons remain inside their pane headers after resizing");
      Check([close.image.accessibilityDescription isEqual:@"Close view"], @"every pane uses a close icon");
      NSBitmapImageRep *rep = [header bitmapImageRepForCachingDisplayInRect:header.bounds];
      [header cacheDisplayInRect:header.bounds toBitmapImageRep:rep];
      Check(rep.pixelsWide > 0 && rep.pixelsHigh > 0, @"pane chrome renders in both themes");
    }
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData *beforeFocus = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    view.focusedIdentity = group.identities.lastObject;
    NSBitmapImageRep *afterFocus = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:afterFocus];
    Check([beforeFocus isEqual:[afterFocus representationUsingType:NSBitmapImageFileTypePNG properties:@{}]], @"changing the focused pane does not highlight or recolor split chrome");
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-grid-light.png" : @"/tmp/talaria-grid-dark.png" atomically:YES];
  }
  __block NSDictionary *savedWeights = nil;
  view.layoutWeightsChanged = ^(NSDictionary *weights) { savedWeights = weights; };
  NSView *rowDivider = nil;
  for (NSView *divider in [view valueForKey:@"dividers"]) if ([[divider valueForKey:@"horizontal"] boolValue]) { rowDivider = divider; break; }
  CGFloat before = NSHeight([view hostForIdentity:group.columns[0][0]].frame);
  [(id)rowDivider accessibilityPerformIncrement]; [view layoutSubtreeIfNeeded];
  CGFloat resized = NSHeight([view hostForIdentity:group.columns[0][0]].frame);
  Check(savedWeights && fabs(before-resized)>1, @"horizontal dividers resize row heights through accessibility controls");
  for (NSView *divider in [view valueForKey:@"dividers"]) {
    NSRect beforeFrame = [view hostForIdentity:group.columns[0][0]].frame;
    NSEvent *drag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged
      location:NSMakePoint(NSMidX(divider.frame),NSMidY(divider.frame)) modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
    [divider mouseDragged:drag]; [view layoutSubtreeIfNeeded];
    NSRect afterFrame = [view hostForIdentity:group.columns[0][0]].frame;
    Check(fabs(NSWidth(beforeFrame)-NSWidth(afterFrame))<0.01 && fabs(NSHeight(beforeFrame)-NSHeight(afterFrame))<0.01, @"grabbing a resize gap does not jump after adding outer padding");
  }
  view.columns = @[@[@"temporary"]]; view.columns = group.columns;
  for (NSString *identity in group.identities) [view setTitle:identity image:nil icon:@"" systemIcon:@"globe" forIdentity:identity];
  [view restoreLayoutWeights:savedWeights]; [view layoutSubtreeIfNeeded];
  Check(fabs(NSHeight([view hostForIdentity:group.columns[0][0]].frame)-resized)<0.01, @"saved divider sizes restore when returning to a group");
  NSView *first = [view hostForIdentity:group.columns[0][0]];
  NSPoint topEdge=NSMakePoint(NSMidX(first.frame),NSMaxY(first.frame)+view.palette.tabHeight-2);
  [view prepareDropTargetsWithValidator:nil];
  Check([view dropSideAtPoint:topEdge] == TLSplitDropSideAbove, @"top edge offers vertical splitting");
  [state detachTab:tabs[4]];
  Check(group.identities.count == 8 && ![state groupForTab:tabs[4]], @"detaching one pane preserves eight other panes");
  [state reconcileTabs:@[tabs[0],tabs[1],tabs[2]]];
  Check(group.columns.count == 1 && group.identities.count == 3, @"closing whole columns removes empty columns");
}

static void TestColumnLayout(void) {
  TLWorkspaceSplitState *state = [TLWorkspaceSplitState new];
  TLWorkspaceTab *a=Tab(-1), *b=Tab(-2), *c=Tab(-3), *d=Tab(-4);
  [state splitTab:b besideTab:a placement:TLSplitPlacementRight];
  [state splitTab:c besideTab:a placement:TLSplitPlacementBelow];
  TLWorkspaceSplitGroup *group = [state groupForTab:a];
  Check([group.columns isEqual:@[@[TLWorkspaceTabIdentity(a),TLWorkspaceTabIdentity(c)],@[TLWorkspaceTabIdentity(b)]]], @"dropping below stacks inside the target column and leaves the adjacent column intact");
  TLSplitWorkspaceView *view = [[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
  view.columns = group.columns;
  for (NSString *identity in group.identities) [view setTitle:identity image:nil icon:@"" systemIcon:@"globe" forIdentity:identity];
  [view layoutSubtreeIfNeeded];
  NSView *top=[view hostForIdentity:TLWorkspaceTabIdentity(a)], *bottom=[view hostForIdentity:TLWorkspaceTabIdentity(c)], *right=[view hostForIdentity:TLWorkspaceTabIdentity(b)];
  Check(NSMinX(top.frame)==NSMinX(bottom.frame) && NSWidth(top.frame)==NSWidth(bottom.frame) && NSMaxY(bottom.frame)<NSMinY(top.frame), @"stacked panes share a column width");
  Check(NSHeight(right.frame)>NSHeight(top.frame)*2, @"the neighboring column spans the full workspace height");
  [view prepareDropTargetsWithValidator:nil];
  NSPoint point=NSMakePoint(NSMaxX(bottom.frame)-1,NSMidY(bottom.frame));
  [view showDropSide:[view dropSideAtPoint:point] title:@"New column" point:point];
  NSView *preview=[view valueForKey:@"preview"];
  NSRect targetRect=[[[preview valueForKey:@"activeTarget"] valueForKey:@"rect"] rectValue];
  Check(fabs(NSHeight(targetRect)-(NSHeight(view.bounds)-2*view.palette.space5))<0.01, @"left and right drag targets span the full height even from a lower pane");
  point=NSMakePoint(NSMidX(bottom.frame),NSMaxY(bottom.frame)+view.palette.tabHeight);
  [view showDropSide:[view dropSideAtPoint:point] title:@"Stack view" point:point];
  targetRect=[[[preview valueForKey:@"activeTarget"] valueForKey:@"rect"] rectValue];
  Check(NSMinX(targetRect)>NSMinX(bottom.frame) && NSMaxX(targetRect)<NSMaxX(bottom.frame) && NSMinY(targetRect)<point.y && NSMaxY(targetRect)>point.y, @"the shared row target covers the gap inside its column");
  [view clearDropPreview];
  NSRect rightBefore=right.frame;
  CGFloat topHeight=NSHeight(top.frame);
  for (NSView *divider in [view valueForKey:@"dividers"]) if ([[divider valueForKey:@"horizontal"] boolValue]) {
    [(id)divider accessibilityPerformIncrement]; break;
  }
  [view layoutSubtreeIfNeeded];
  Check(fabs(NSHeight(top.frame)-topHeight)>1 && NSEqualRects(rightBefore,right.frame), @"resizing a row affects only its own column");
  CGFloat topWidth=NSWidth(top.frame);
  for (NSView *divider in [view valueForKey:@"dividers"]) if (![[divider valueForKey:@"horizontal"] boolValue]) {
    [(id)divider accessibilityPerformIncrement]; break;
  }
  [view layoutSubtreeIfNeeded];
  Check(fabs(NSWidth(top.frame)-topWidth)>1 && NSWidth(top.frame)==NSWidth(bottom.frame), @"resizing a column changes the width of every pane in its stack");
  for (NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    view.palette=[TLThemePalette paletteForPreference:theme.integerValue]; [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue==TLThemePreferenceLight ? @"/tmp/talaria-columns-light.png" : @"/tmp/talaria-columns-dark.png" atomically:YES];
  }
  [state splitTab:c besideTab:b placement:TLSplitPlacementAbove];
  Check([group.columns isEqual:@[@[TLWorkspaceTabIdentity(a)],@[TLWorkspaceTabIdentity(c),TLWorkspaceTabIdentity(b)]]], @"dragging above a view in another column transfers only the dragged pane");
  [state splitTab:d besideTab:b placement:TLSplitPlacementLeft];
  Check([group.columns isEqual:@[@[TLWorkspaceTabIdentity(a)],@[TLWorkspaceTabIdentity(d)],@[TLWorkspaceTabIdentity(c),TLWorkspaceTabIdentity(b)]]], @"a left drop beside a lower pane inserts a whole column");
  [state detachTab:c];
  Check(group.columns.count==3 && group.identities.count==3 && ![state groupForTab:c], @"unsplitting removes only the dragged view from its column");
}

static void TestDropTargets(void) {
  TLSplitWorkspaceView *view=[[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
  view.columns=@[@[@"left"],@[@"right"]];
  [view setTitle:@"Left" image:nil icon:@"" systemIcon:@"globe" forIdentity:@"left"];
  [view setTitle:@"Right" image:nil icon:@"" systemIcon:@"globe" forIdentity:@"right"];
  [view prepareDropTargetsWithValidator:nil];
  NSView *preview=[view valueForKey:@"preview"];
  Check(!preview.hidden && [[preview valueForKey:@"targets"] count]==7 && ![preview valueForKey:@"activeTarget"], @"two columns expose three column boundaries and four row boundaries before any hover");
  NSRect left=[view hostForIdentity:@"left"].frame, right=[view hostForIdentity:@"right"].frame;
  for (NSNumber *x in @[@(NSMaxX(left)-1),@(NSMidX(view.bounds)),@(NSMinX(right)+1)]) {
    NSPoint point=NSMakePoint(x.doubleValue,300);
    Check([view dropSideAtPoint:point]==TLSplitDropSideRight && [[view dropIdentityAtPoint:point] isEqual:@"left"], @"both neighboring edges and the gap resolve to the same center insertion");
    [view showDropSide:[view dropSideAtPoint:point] title:@"Third view" point:point];
    Check([[preview valueForKey:@"targets"] count]==7, @"hovering highlights a destination without hiding other targets");
  }
  for (NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    view.palette=[TLThemePalette paletteForPreference:theme.integerValue]; [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue==TLThemePreferenceLight ? @"/tmp/talaria-drop-targets-light.png" : @"/tmp/talaria-drop-targets-dark.png" atomically:YES];
  }
  [view prepareDropTargetsWithValidator:^BOOL(NSString *identity, TLSplitDropSide side) { return [identity isEqual:@"right"]; }];
  Check([[view dropIdentityAtPoint:NSMakePoint(500,300)] isEqual:@"right"] && [view dropSideAtPoint:NSMakePoint(500,300)]==TLSplitDropSideLeft, @"a shared target can use the other neighbor when dragging its first neighbor");
  [view clearDropPreview];
  Check(preview.hidden && [view dropSideAtPoint:NSMakePoint(500,300)]==TLSplitDropSideNone, @"ending a drag removes all targets and hit areas");

  view.columns=@[@[@"left"],@[@"middle"],@[@"right"]];
  [view setTitle:@"Middle" image:nil icon:@"" systemIcon:@"globe" forIdentity:@"middle"];
  [view prepareDropTargetsWithValidator:^BOOL(NSString *identity, TLSplitDropSide side) {
    return side==TLSplitDropSideAbove || side==TLSplitDropSideBelow;
  }];
  Check([[preview valueForKey:@"targets"] count]==6, @"three columns with room to stack expose only their six row targets");
  for (id target in [preview valueForKey:@"targets"]) {
    NSString *identity=[target valueForKey:@"identity"];
    NSRect rect=[[target valueForKey:@"rect"] rectValue];
    NSRect host=[view hostForIdentity:identity].frame;
    Check(NSMinX(rect)==NSMinX(host) && NSWidth(rect)==NSWidth(host), @"row targets span the full column when no new column can be inserted");
    Check([[view dropIdentityAtPoint:NSMakePoint(NSMinX(rect)+1,NSMidY(rect))] isEqual:identity] &&
      [[view dropIdentityAtPoint:NSMakePoint(NSMaxX(rect)-1,NSMidY(rect))] isEqual:identity], @"the full-width target accepts drops at both column edges");
  }
  NSPoint rowHover=NSMakePoint(NSMidX([view hostForIdentity:@"middle"].frame),NSHeight(view.bounds)-view.palette.space5-1);
  [view showDropSide:[view dropSideAtPoint:rowHover] title:@"New view" point:rowHover];
  for (NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    view.palette=[TLThemePalette paletteForPreference:theme.integerValue]; [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue==TLThemePreferenceLight ? @"/tmp/talaria-full-column-targets-light.png" : @"/tmp/talaria-full-column-targets-dark.png" atomically:YES];
  }

  TLWorkspaceSplitState *state=[TLWorkspaceSplitState new];
  NSMutableArray<TLWorkspaceTab *> *tabs=[NSMutableArray new];
  for (NSInteger i=1;i<=10;i++) [tabs addObject:Tab(-i)];
  for (NSUInteger c=0;c<3;c++) {
    if (c) [state splitTab:tabs[c*3] besideTab:tabs[(c-1)*3] placement:TLSplitPlacementRight];
    for (NSUInteger r=1;r<3;r++) [state splitTab:tabs[c*3+r] besideTab:tabs[c*3+r-1] placement:TLSplitPlacementBelow];
  }
  view.columns=[state groupForTab:tabs[0]].columns;
  [view prepareDropTargetsWithValidator:^BOOL(NSString *identity, TLSplitDropSide side) {
    TLWorkspaceTab *other=nil;
    for (TLWorkspaceTab *tab in tabs) if ([TLWorkspaceTabIdentity(tab) isEqual:identity]) other=tab;
    TLSplitPlacement placement=side==TLSplitDropSideLeft ? TLSplitPlacementLeft : side==TLSplitDropSideRight ? TLSplitPlacementRight : side==TLSplitDropSideAbove ? TLSplitPlacementAbove : TLSplitPlacementBelow;
    return [state canSplitTab:tabs[9] besideTab:other placement:placement];
  }];
  Check(preview.hidden && [[preview valueForKey:@"targets"] count]==0, @"a full nine-pane grid offers no invalid drop areas");
}

static void TestUnchangedDropTargets(void) {
  TLWorkspaceSplitState *state=[TLWorkspaceSplitState new];
  TLWorkspaceTab *chat=Tab(-1), *browser=[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:1 title:@"Browser" toolTip:nil URL:nil closeable:YES];
  for (NSNumber *stacked in @[@NO,@YES]) {
    [state removeGroupForTab:chat];
    [state splitTab:browser besideTab:chat placement:stacked.boolValue ? TLSplitPlacementBelow : TLSplitPlacementRight];
    TLWorkspaceSplitGroup *group=[state groupForTab:chat];
    group.fraction=0.3;
    NSArray *original=group.columns.copy;
    for (TLWorkspaceTab *dragged in @[chat,browser]) {
      TLSplitWorkspaceView *view=[[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
      view.columns=group.columns; view.fraction=group.fraction;
      for (NSString *identity in group.identities) [view setTitle:identity image:nil icon:@"" systemIcon:@"globe" forIdentity:identity];
      [view prepareDropTargetsWithValidator:^BOOL(NSString *identity, TLSplitDropSide side) {
        TLWorkspaceTab *other=[identity isEqual:TLWorkspaceTabIdentity(chat)] ? chat : browser;
        TLSplitPlacement placement=side==TLSplitDropSideLeft ? TLSplitPlacementLeft : side==TLSplitDropSideRight ? TLSplitPlacementRight : side==TLSplitDropSideAbove ? TLSplitPlacementAbove : TLSplitPlacementBelow;
        return [state canSplitTab:dragged besideTab:other placement:placement];
      }];
      NSArray *targets=[[view valueForKey:@"preview"] valueForKey:@"targets"];
      Check(targets.count>0, @"moves that rearrange or restack the pair remain available");
      for (id target in targets) Check(![[target valueForKey:@"title"] isEqual:@"Add middle split"], @"dragging either member of a pair omits its unchanged middle destination");
    }
    TLSplitPlacement unchanged=stacked.boolValue ? TLSplitPlacementBelow : TLSplitPlacementRight;
    Check(![state splitTab:browser besideTab:chat placement:unchanged] && [group.columns isEqual:original] && group.fraction==0.3 && state.groups.firstObject==group, @"rejecting an unchanged drop preserves the group and its widths");
  }
}

static void TestPointerCancellation(void) {
  TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0,0,180,36)];
  NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(20,20)
    modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
  NSEvent *drag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:NSMakePoint(80,200)
    modifierFlags:0 timestamp:1 windowNumber:0 context:nil eventNumber:2 clickCount:1 pressure:1];
  [tab mouseDown:down]; [tab mouseDragged:drag];
  Check([[tab valueForKey:@"didDrag"] boolValue], @"pointer movement begins the drag");
  [tab cancelPointerDrag]; [tab mouseDragged:drag];
  Check(![[tab valueForKey:@"didDrag"] boolValue], @"Escape prevents held-pointer movement from restarting a cancelled drag");
  [tab mouseDown:down]; [tab mouseDragged:drag];
  Check([[tab valueForKey:@"didDrag"] boolValue], @"a fresh pointer press can drag after cancellation");
  [tab finishPointerDrag];
}
static void TestPaneGeometry(void) {
  TLSplitWorkspaceView *view = [[TLSplitWorkspaceView alloc] initWithFrame:NSMakeRect(0,0,1000,600)];
  NSLayoutConstraint *widthConstraint = [view.widthAnchor constraintEqualToConstant:1000];
  widthConstraint.active = YES;
  [view.heightAnchor constraintEqualToConstant:600].active = YES;
  view.split = YES; view.leftTitle = @"Research"; view.rightTitle = @"Notes";
  [view setTitle:@"Research" image:nil icon:@"💬" systemIcon:@"" forIdentity:@"left"];
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    view.palette = [TLThemePalette paletteForPreference:theme.integerValue];
    for (NSNumber *width in @[@200,@480,@1000,@1800]) {
      widthConstraint.constant = width.doubleValue;
      view.frame = NSMakeRect(0,0,width.doubleValue,600); view.fraction = 0.95; [view layoutSubtreeIfNeeded];
      Check(NSWidth(view.leftHost.frame) > 0 && NSWidth(view.rightHost.frame) > 0, @"both panes survive narrow widths");
      Check(NSMaxX(view.rightHost.frame) <= width.doubleValue + 0.01, @"pane stays inside the window at all widths");
      Check(NSMaxX(view.leftHost.frame) < NSMinX(view.rightHost.frame), @"divider separates nonoverlapping panes");
      Check(NSMaxY(view.leftHost.frame) <= NSHeight(view.bounds) - view.palette.tabHeight + 0.01,
        @"pane content stays below its header");
    }
    widthConstraint.constant = 1000;
    view.frame = NSMakeRect(0,0,1000,600); view.fraction = 0.5; [view layoutSubtreeIfNeeded];
    NSView *header=[view valueForKey:@"headers"][@"left"];
    NSView *icon=[header valueForKey:@"icon"];
    NSBitmapImageRep *iconRep=[icon bitmapImageRepForCachingDisplayInRect:icon.bounds];
    [icon cacheDisplayInRect:icon.bounds toBitmapImageRep:iconRep];
    NSInteger firstPixel=iconRep.pixelsHigh, lastPixel=-1;
    for (NSInteger y=0;y<iconRep.pixelsHigh;y++) for (NSInteger x=0;x<iconRep.pixelsWide;x++) {
      if ([iconRep colorAtX:x y:y].alphaComponent>0.5) { firstPixel=MIN(firstPixel,y); lastPixel=MAX(lastPixel,y); }
    }
    Check(lastPixel>=firstPixel && fabs((firstPixel+lastPixel+1)/2.0-iconRep.pixelsHigh/2.0)<=2,
      @"the rendered chat emoji is vertically centered in its icon box in both themes");
    Check(fabs(NSMidY(icon.frame)-NSMidY(header.bounds))<0.01, @"the icon box is centered in the split header");
    NSBitmapImageRep *headerRep=[header bitmapImageRepForCachingDisplayInRect:header.bounds];
    [header cacheDisplayInRect:header.bounds toBitmapImageRep:headerRep];
    [[headerRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue==TLThemePreferenceLight ? @"/tmp/talaria-pane-header-light.png" : @"/tmp/talaria-pane-header-dark.png" atomically:YES];
    [view prepareDropTargetsWithValidator:nil];
    Check([view dropSideAtPoint:NSMakePoint(100,300)] == TLSplitDropSideLeft, @"left edge selects left split");
    Check([view dropSideAtPoint:NSMakePoint(900,300)] == TLSplitDropSideRight, @"right edge selects right split");
    Check([view dropSideAtPoint:NSMakePoint(250,300)] == TLSplitDropSideNone && [view dropSideAtPoint:NSMakePoint(-1,300)] == TLSplitDropSideNone, @"pane centers and outside remain safe cancellation areas");
    [view showDropSide:TLSplitDropSideLeft title:@"Notes" point:NSMakePoint(100,300)];
    [view layoutSubtreeIfNeeded];
    NSView *preview = [view valueForKey:@"preview"];
    Check(!preview.hidden && [preview hitTest:NSMakePoint(100,300)] == nil, @"preview does not intercept the drag");
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:theme.integerValue == TLThemePreferenceLight ? @"/tmp/talaria-split-light.png" : @"/tmp/talaria-split-dark.png" atomically:YES];
    Check(CGColorEqualToColor(view.layer.backgroundColor, view.palette.tabBackground.CGColor), @"split surface follows the current theme");
    [view clearDropPreview]; Check(preview.hidden, @"cancellation removes the preview");
  }
  view.split = NO; [view layoutSubtreeIfNeeded];
  Check(NSWidth(view.leftHost.frame) == 1000 && view.rightHost.hidden, @"unsplit restores full content width");
}

static void TestChatInputNavigation(TLSplitTestController *owner, TLAppStateManager *state) {
  [owner setValue:@1000 forKey:@"nextBrowserTabID"];
  NSURL *URL = [NSURL URLWithString:@"https://www.example.com/page?q=hello#section"];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *neighbor = state.snapshot.workspaceTabs.lastObject;
  TLChatTabController *neighborPresentation = [owner valueForKey:@"chatPresentation"];
  neighborPresentation.promptTextView.string = @"Keep this draft";
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *empty = state.snapshot.workspaceTabs.lastObject;
  TLChatTabController *retired = [owner valueForKey:@"chatPresentation"];
  [state moveWorkspaceTabWithKind:empty.kind tabID:empty.tabID toIndex:1];
  [owner splitTab:empty besideTab:neighbor onLeft:YES];
  [owner focusSplitPane:NO];
  TLWorkspaceSplitState *splits = [owner valueForKey:@"splitState"];
  [splits groupForTab:empty].fraction = 0.6;
  NSUInteger count = state.snapshot.workspaceTabs.count;
  retired.promptTextView.string = URL.absoluteString;
  [owner sendMessage:nil allowAutomaticRouting:YES]; Drain();
  TLWorkspaceTab *browser = state.snapshot.workspaceTabs[1];
  Check(state.snapshot.workspaceTabs.count == count && browser.kind == TLWorkspaceTabKindBrowser &&
    [browser.URL isEqual:URL] && state.snapshot.activeTabID == browser.tabID,
    @"Enter replaces the empty chat at the same index and preserves the full URL");
  Check([TLWorkspaceTabIdentity(browser) isEqual:TLWorkspaceTabIdentity(empty)] &&
    [[splits groupForTab:browser].leftIdentity isEqual:TLWorkspaceTabIdentity(browser)] &&
    [[splits groupForTab:browser].rightIdentity isEqual:TLWorkspaceTabIdentity(neighbor)] &&
    [splits groupForTab:browser].fraction == 0.6, @"conversion preserves split identity, side and divider");
  TLSplitWorkspaceView *workspace = [owner valueForKey:@"splitWorkspace"];
  TLWorkspaceTabRuntime *runtime = [owner valueForKey:@"workspaceTabRuntimes"][TLWorkspaceTabRuntimeKey(browser.kind,browser.tabID)];
  Check(runtime.contentView.superview == workspace.leftHost &&
    neighborPresentation.chatWorkspace.superview == workspace.rightHost &&
    [neighborPresentation.promptTextView.string isEqual:@"Keep this draft"],
    @"the browser replaces only its pane and retains the neighboring draft");
  Check(![state workspaceTabWithKind:empty.kind tabID:empty.tabID] && !retired.chatWorkspace.superview &&
    ![owner valueForKey:@"workspaceTabRuntimes"][TLWorkspaceTabRuntimeKey(empty.kind,empty.tabID)] &&
    ![owner valueForKey:@"modelDraftChats"][@(empty.tabID)], @"conversion retires the empty draft and runtime");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  Check(![owner valueForKey:@"modelDraftChats"][@(empty.tabID)], @"opening another chat does not resurrect the converted draft");
  empty = state.snapshot.workspaceTabs.lastObject;
  TLChatTabController *presentation = [owner valueForKey:@"chatPresentation"];
  [owner.window.contentView layoutSubtreeIfNeeded];
  Check(!presentation.closed && presentation.emptyStateView && !presentation.emptyStateView.hidden &&
    !presentation.emptyStateView.isHiddenOrHasHiddenAncestor && NSWidth(presentation.emptyStateView.bounds)>0 &&
    NSHeight(presentation.emptyStateView.bounds)>0,
    @"new tab after converting a chat to a browser displays its empty-state UI");
  presentation.promptTextView.string = URL.absoluteString;
  [owner updateSlashCommandList]; [owner flushSlashCommandUpdate];
  count = state.snapshot.workspaceTabs.count;
  Check([owner performInputSuggestionAtIndex:0], @"Open suggestion accepts the URL"); Drain();
  browser = state.snapshot.workspaceTabs.lastObject;
  Check(state.snapshot.workspaceTabs.count == count && browser.kind == TLWorkspaceTabKindBrowser &&
    [browser.URL isEqual:URL] && [TLWorkspaceTabIdentity(browser) isEqual:TLWorkspaceTabIdentity(empty)],
    @"Open suggestion also converts an empty chat without adding a tab");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *nonempty = state.snapshot.workspaceTabs.lastObject;
  presentation = [owner valueForKey:@"chatPresentation"];
  [presentation.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Keep this conversation" thinking:nil]];
  presentation.promptTextView.string = URL.absoluteString;
  count = state.snapshot.workspaceTabs.count;
  [owner sendMessage:nil allowAutomaticRouting:YES]; Drain();
  Check(state.snapshot.workspaceTabs.count == count + 1 &&
    [state workspaceTabWithKind:nonempty.kind tabID:nonempty.tabID] && presentation.messages.count == 1,
    @"URL submission preserves chats that already contain messages");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *queued = state.snapshot.workspaceTabs.lastObject;
  presentation = [owner valueForKey:@"chatPresentation"];
  [presentation.queuedPrompts addObject:[TLQueuedPrompt promptWithText:@"Keep this follow-up" attachmentURLs:@[]]];
  presentation.queuePaused = YES;
  presentation.promptTextView.string = URL.absoluteString;
  count = state.snapshot.workspaceTabs.count;
  [owner sendMessage:nil allowAutomaticRouting:YES]; Drain();
  Check(state.snapshot.workspaceTabs.count == count + 1 &&
    [state workspaceTabWithKind:queued.kind tabID:queued.tabID] && presentation.queuedPrompts.count == 1,
    @"URL submission retains an otherwise empty chat with queued follow-ups");

  [owner startNewChatWithModel:@"test-model" focus:NO];
  empty = state.snapshot.workspaceTabs.lastObject;
  count = state.snapshot.workspaceTabs.count;
  [owner openBrowserTabWithURL:URL]; Drain();
  Check(state.snapshot.workspaceTabs.count == count + 1 && [state workspaceTabWithKind:empty.kind tabID:empty.tabID],
    @"explicit new-tab actions still retain an empty chat");
  TLChatTabController *closedPresentation = [owner valueForKey:@"chatPresentation"];
  [closedPresentation.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Previous conversation" thinking:nil]];
  [closedPresentation renderMessagesScrollingToBottom:NO];
  Check(closedPresentation.emptyStateView.hidden, @"the previous conversation has no empty-state UI");
  [owner closeChatTabWithID:empty.tabID]; Drain();
  [owner startNewChatWithModel:@"test-model" focus:NO]; Drain();
  presentation = [owner valueForKey:@"chatPresentation"];
  [owner.window.contentView layoutSubtreeIfNeeded];
  Check(presentation != closedPresentation && !presentation.closed && presentation.emptyStateView && !presentation.emptyStateView.isHiddenOrHasHiddenAncestor &&
    NSWidth(presentation.emptyStateView.bounds)>0 && NSHeight(presentation.emptyStateView.bounds)>0,
    @"new tab from a browser after closing the previous chat displays its empty-state UI");
}

static void TestDraftPromotionAcrossEvents(void) {
  TLSplitTestController *owner;
  TLChatTabController *chat;
  // AppKit drains autoreleased runtime snapshots between creating a draft and
  // submitting its first prompt. Keep that boundary in this lifecycle test.
  @autoreleasepool {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,550)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    owner = [[TLSplitTestController alloc] initWithWindow:window];
    [owner setValue:[TLAppStateManager new] forKey:@"appStateManager"];
    [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
    [owner setValue:[TLSplitTestDatabase new] forKey:@"database"];
    [owner setValue:[TLAppSettings defaultSettings] forKey:@"settings"];
    [owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceDark] forKey:@"palette"];
    [owner setValue:window.contentView forKey:@"contentHost"];
    [owner setValue:@(-1) forKey:@"nextDraftChatID"];
    [owner startNewChatWithModel:@"test-model" focus:NO];
    chat = [owner valueForKey:@"chatPresentation"];
    Check(!chat.emptyStateView.hidden, @"draft starts with the empty state visible");
  }
  @autoreleasepool {
    Check([owner persistActiveDraftChatWithModel:@"test-model"], @"first submission saves the draft");
  }
  Check(!chat.closed, @"retiring the draft identity keeps its chat controller alive across events");
  TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleUser content:@"First prompt" thinking:nil];
  [chat.messages addObject:message];
  [chat markMessageDirty:message];
  [chat scheduleStreamingMessageRender];
  Drain();
  Check(chat.emptyStateView.hidden && [chat.messageRowViews objectForKey:message].superview == chat.messageStack,
    @"first submission renders its message and removes the empty state");
  [owner startNewChatWithModel:@"test-model" focus:NO];
  [owner closeChatTabWithID:123];
  Check(chat.closed, @"explicit tab closure still disposes the saved controller");
  [owner.window close];
}

static void TestNewTabContextMenu(TLSplitTestController *owner, TLAppStateManager *state) {
  TLButton *plus = [owner valueForKey:@"createChatButton"];
  NSButton *control = [plus valueForKey:@"button"];
  NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:owner.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
  NSMenu *menu = [control menuForEvent:rightClick];
  Check([[menu.itemArray valueForKey:@"title"] isEqual:@[@"Open new tab", @"Open new tab in a sideview"]], @"right-clicking the plus control exposes exactly the two requested actions");
  NSUInteger count = state.snapshot.workspaceTabs.count;
  NSMenuItem *ordinary = menu.itemArray[0];
  [NSApp sendAction:ordinary.action to:ordinary.target from:ordinary]; Drain();
  TLWorkspaceTab *first = [state workspaceTabWithKind:state.snapshot.activeTabKind tabID:state.snapshot.activeTabID];
  TLWorkspaceSplitState *splits = [owner valueForKey:@"splitState"];
  Check(state.snapshot.workspaceTabs.count == count+1 && ![splits groupForTab:first], @"Open new tab creates an ordinary standalone tab");
  count = state.snapshot.workspaceTabs.count;
  NSMenuItem *lastEnabled = nil;
  for (NSUInteger size=2;size<=9;size++) {
    menu = [control menuForEvent:rightClick];
    lastEnabled = menu.itemArray[1];
    Check(lastEnabled.enabled, @"sideview action stays enabled while a slot is free");
    [NSApp sendAction:lastEnabled.action to:lastEnabled.target from:lastEnabled]; Drain();
    TLWorkspaceSplitGroup *group = [splits groupForTab:first];
    Check(group.identities.count == size && state.snapshot.workspaceTabs.count == count+size-1, @"sideview action creates exactly one new tab in the existing group");
  }
  TLWorkspaceSplitGroup *full = [splits groupForTab:first];
  Check(full.columns.count == 3 && full.columns[0].count == 3 && full.columns[1].count == 3 && full.columns[2].count == 3, @"automatic placement fills all nine slots");
  menu = [control menuForEvent:rightClick];
  Check(menu.itemArray[0].enabled && !menu.itemArray[1].enabled, @"only the sideview action is disabled at nine panes");
  count = state.snapshot.workspaceTabs.count;
  [NSApp sendAction:lastEnabled.action to:lastEnabled.target from:lastEnabled]; Drain();
  Check(state.snapshot.workspaceTabs.count == count && full.identities.count == 9, @"a stale enabled action cannot create an extra tab when the grid is full");
  NSString *closedIdentity = full.columns[0][1];
  TLSplitWorkspaceView *workspace = [owner valueForKey:@"splitWorkspace"];
  workspace.closeIdentity(closedIdentity); Drain();
  menu = [control menuForEvent:rightClick];
  Check(menu.itemArray[1].enabled, @"closing any pane re-enables the sideview action");
  NSMenuItem *refill = menu.itemArray[1];
  [NSApp sendAction:refill.action to:refill.target from:refill]; Drain();
  Check(full.columns[0].count == 3 && full.identities.count == 9 && ![full.identities containsObject:closedIdentity], @"new sideviews reuse free slots outside the focused column");
}

static void TestBrowserChatDefaultWidths(TLSplitTestController *owner, TLAppStateManager *state) {
  TLSplitWorkspaceView *workspace=[owner valueForKey:@"splitWorkspace"];
  TLWorkspaceSplitState *splits=[owner valueForKey:@"splitState"];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *chat=state.snapshot.workspaceTabs.lastObject;
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *secondChat=state.snapshot.workspaceTabs.lastObject;
  TLWorkspaceTab *browser=[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:90001 title:@"Browser" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
  TLWorkspaceTab *secondBrowser=[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:90002 title:@"Browser 2" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
  [state addWorkspaceTab:browser activate:YES]; [state addWorkspaceTab:secondBrowser activate:NO]; Drain();
  for (NSNumber *width in @[@1199,@1200,@1201,@1600]) {
    NSSize size=owner.window.contentView.bounds.size;
    size.width+=width.doubleValue-NSWidth(workspace.bounds);
    [owner.window setContentSize:size]; [owner.window.contentView layoutSubtreeIfNeeded];
    Check(fabs(NSWidth(workspace.bounds)-width.doubleValue)<0.01, @"width threshold is measured against the workspace, excluding the sidebar");
    for (NSNumber *browserOnLeft in @[@YES,@NO]) {
      [splits detachTab:browser]; [owner updateWorkspaceMode];
      [owner splitTab:browser besideTab:chat onLeft:browserOnLeft.boolValue]; Drain();
      CGFloat browserWidth=NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(browser)].frame);
      CGFloat chatWidth=NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(chat)].frame);
      CGFloat expected=width.doubleValue>1200 ? 0.7 : 0.5;
      Check(fabs(browserWidth/(browserWidth+chatWidth)-expected)<0.001, @"a wide browser-chat pair gives the browser 70 percent on either side; 1200px and below stays equal");
    }
  }
  [splits detachTab:browser]; [owner updateWorkspaceMode];
  [owner splitTab:browser besideTab:chat placement:TLSplitPlacementBelow]; Drain();
  Check([splits groupForTab:browser].columns.count==1 &&
    fabs(NSHeight([workspace hostForIdentity:TLWorkspaceTabIdentity(browser)].frame)-NSHeight([workspace hostForIdentity:TLWorkspaceTabIdentity(chat)].frame))<0.01, @"vertically stacked browser and chat views remain equal");
  [splits detachTab:browser]; [owner updateWorkspaceMode];
  [owner splitTab:browser besideTab:secondBrowser onLeft:YES]; Drain();
  Check(fabs(NSWidth(workspace.leftHost.frame)-NSWidth(workspace.rightHost.frame))<0.01, @"two browsers keep equal widths on a wide workspace");
  [splits detachTab:browser]; [owner updateWorkspaceMode];
  [owner splitTab:chat besideTab:secondChat onLeft:YES]; Drain();
  Check(fabs(NSWidth(workspace.leftHost.frame)-NSWidth(workspace.rightHost.frame))<0.01, @"two chats keep equal widths on a wide workspace");
  [owner splitTab:browser besideTab:chat onLeft:YES]; Drain();
  Check([splits groupForTab:browser].columns.count==3 &&
    fabs(NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(browser)].frame)-NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(chat)].frame))<0.01, @"adding a browser to a larger group does not apply the pair-only default");
  [splits removeGroupForTab:browser]; [owner updateWorkspaceMode];
  [owner splitTab:browser besideTab:chat onLeft:YES]; Drain();
  for (NSView *divider in [workspace valueForKey:@"dividers"]) if (![[divider valueForKey:@"horizontal"] boolValue]) {
    [(id)divider accessibilityPerformIncrement]; break;
  }
  [workspace layoutSubtreeIfNeeded];
  CGFloat customFraction=[splits groupForTab:browser].fraction;
  [owner loadChatWithID:chat.tabID]; [owner updateWorkspaceMode]; [workspace layoutSubtreeIfNeeded];
  Check(customFraction>0.7 && fabs(NSWidth(workspace.leftHost.frame)/(NSWidth(workspace.leftHost.frame)+NSWidth(workspace.rightHost.frame))-customFraction)<0.001, @"manual resizing overrides the initial 70/30 split and survives focus changes");
  [owner splitTab:browser besideTab:chat onLeft:NO]; Drain();
  CGFloat browserWidth=NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(browser)].frame);
  CGFloat chatWidth=NSWidth([workspace hostForIdentity:TLWorkspaceTabIdentity(chat)].frame);
  Check(fabs(browserWidth/(browserWidth+chatWidth)-customFraction)<0.001, @"swapping the browser and chat keeps their respective width shares");
}

static void TestRealWorkspace(void) {
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,700)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLSplitTestController *owner = [[TLSplitTestController alloc] initWithWindow:window];
  window.delegate = (id<NSWindowDelegate>)owner;
  window.minSize = NSMakeSize(200,400); window.contentMinSize = NSMakeSize(200,400);
  window.maxSize = NSMakeSize(100000,100000); window.contentMaxSize = NSMakeSize(100000,100000);
  TLAppStateManager *state = [TLAppStateManager new];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:[TLSplitTestDatabase new] forKey:@"database"];
  TLAppSettings *settings = [TLAppSettings defaultSettings]; settings.theme = TLThemePreferenceLight;
  [owner setValue:settings forKey:@"settings"];
  [owner setValue:[TLThemePalette paletteForPreference:settings.theme] forKey:@"palette"];
  [owner setValue:[NSMutableArray array] forKey:@"agents"];
  [owner setValue:[NSMutableArray array] forKey:@"chats"];
  [owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [owner buildInterface]; [owner installAppStateBindings];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *a = state.snapshot.workspaceTabs.lastObject;
  TLChatTabController *pa = [owner valueForKey:@"chatPresentation"];
  pa.promptTextView.string = @"Unsent left draft";
  pa.messageInput.attachmentURLs = @[[NSURL fileURLWithPath:@"/tmp/left.txt"]];
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *b = state.snapshot.workspaceTabs.lastObject;
  TLChatTabController *pb = [owner valueForKey:@"chatPresentation"];
  pb.promptTextView.string = @"Unsent right draft";
  Check(pa != pb && pa.chatWorkspace != pb.chatWorkspace && pa.promptTextView != pb.promptTextView, @"chats own independent live views and composers");
  [owner splitTab:a besideTab:b onLeft:YES]; Drain();
  TLSplitWorkspaceView *workspace = [owner valueForKey:@"splitWorkspace"];
  TLWorkspaceSplitState *splits = [owner valueForKey:@"splitState"];
  Check(workspace.split && pa.chatWorkspace.superview == workspace.leftHost && pb.chatWorkspace.superview == workspace.rightHost, @"chat pair mounts both real workspaces");
  Check(!pa.chatWorkspace.hidden && !pb.chatWorkspace.hidden, @"both chats remain visible");
  NSView *paneHeader=[workspace valueForKey:@"headers"][TLWorkspaceTabIdentity(a)];
  NSPoint panePress=[paneHeader convertPoint:NSMakePoint(NSMidX(paneHeader.bounds),NSMidY(paneHeader.bounds)) toView:nil];
  NSPoint paneDrag=[workspace.leftHost convertPoint:NSMakePoint(NSMidX(workspace.leftHost.bounds),NSMidY(workspace.leftHost.bounds)) toView:nil];
  NSEvent *(^paneEvent)(NSEventType,NSPoint)=^NSEvent *(NSEventType type,NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
  };
  [paneHeader mouseDown:paneEvent(NSEventTypeLeftMouseDown,panePress)];
  [paneHeader mouseDragged:paneEvent(NSEventTypeLeftMouseDragged,paneDrag)];
  Check(![[workspace valueForKey:@"preview"] isHidden], @"pane-header dragging starts the drop-target session");
  [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
  Check([[workspace valueForKey:@"preview"] isHidden] && ![paneHeader valueForKey:@"dragEventMonitor"], @"losing application focus clears pane-header drag targets and tracking");
  [paneHeader mouseDown:paneEvent(NSEventTypeLeftMouseDown,panePress)];
  [paneHeader mouseDragged:paneEvent(NSEventTypeLeftMouseDragged,paneDrag)];
  DispatchDragEvent(paneEvent(NSEventTypeLeftMouseUp,paneDrag));
  Check([[workspace valueForKey:@"preview"] isHidden] && ![paneHeader valueForKey:@"dragEventMonitor"] && workspace.split, @"a fresh pane-header drag can finish through AppKit after cancellation");
  TLWorkspaceTabsController *strip = [owner valueForKey:@"workspaceTabsController"];
  NSArray<TLChromeTabView *> *stripViews = [strip valueForKey:@"tabViews"];
  Check(stripViews.count == 1 && [stripViews[0].title isEqual:@"Split view"] && [stripViews[0].systemIconName isEqual:@"rectangle.3.group"], @"a split has exactly one tab with its group icon and name");
  Check(fabs(NSWidth(pa.chatWorkspace.frame) - NSWidth(workspace.leftHost.bounds)) < 1 &&
    fabs(NSWidth(pb.chatWorkspace.frame) - NSWidth(workspace.rightHost.bounds)) < 1, @"each transcript fills its pane");
  Check(fabs(NSMidX(pa.messageInput.frame) - NSMidX(pa.chatWorkspace.bounds)) < 1, @"composer stays centered inside its pane");
  Check(pa.promptTextView.editable, @"visible chat composer is editable");
  [window makeFirstResponder:pa.promptTextView];
  [owner updateWorkspaceMode];
  Check(window.firstResponder == pa.promptTextView, @"metadata refresh keeps the focused editor attached");
  [owner focusSplitPane:YES];
  Check(state.snapshot.activeTabID == b.tabID && [owner valueForKey:@"chatPresentation"] == pb, @"pane click routes shortcuts and composer actions to its chat");
  Check([pa.promptTextView.string isEqual:@"Unsent left draft"] && [pb.promptTextView.string isEqual:@"Unsent right draft"] && pa.messageInput.attachmentURLs.count == 1, @"focus changes preserve both drafts and attachments");
  pa.messages = [NSMutableArray arrayWithObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Background transcript" thinking:nil]];
  [pa scheduleStreamingMessageRender]; Drain();
  Check([owner valueForKey:@"chatPresentation"] == pb && state.snapshot.activeTabID == b.tabID && pa.renderedMessages.count == 1, @"background render targets the originating pane without changing focus");
  pa.messageStackBottomConstraint.constant = 0;
  CGFloat rightInset = pb.messageStackBottomConstraint.constant;
  [pa renderMessagesScrollingToBottom:NO];
  Drain();
  Check(pa.messageStackBottomConstraint.constant < 0 && pb.messageStackBottomConstraint.constant == rightInset && [owner valueForKey:@"chatPresentation"] == pb,
    @"deferred scroll layout belongs to the rendered chat after focus changes");
  [owner restoreAttachmentDraft:@[] prompt:@"Restored left draft" chatID:a.tabID];
  Check([pa.promptTextView.string isEqual:@"Restored left draft"] && [pb.promptTextView.string isEqual:@"Unsent right draft"],
    @"failed background attachment preparation restores its own visible composer");
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *c = state.snapshot.workspaceTabs.lastObject;
  Check(!workspace.split, @"unrelated tab uses full width");
  [owner workspaceTabsController:strip moveTab:a toIndex:1];
  NSArray *visibleTabs = [owner workspaceTabsForTabsController:strip];
  Check(visibleTabs.count == 2 && [TLWorkspaceTabIdentity(visibleTabs[0]) isEqual:TLWorkspaceTabIdentity(c)], @"dragging the group reorders it as one tab");
  [owner workspaceTabsController:strip moveTab:a toIndex:0];
  [pa.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Update while hidden" thinking:nil]];
  [owner loadChatWithID:a.tabID]; Check(workspace.split && [splits groupForTab:b], @"selecting either member restores its pair");
  Check(pa.renderedMessages.count == 2, @"returning to a cached chat displays updates received while hidden");
  [owner splitTab:a besideTab:b onLeft:NO];
  Check(pa.chatWorkspace.superview == workspace.rightHost, @"swap moves existing views without recreating content");
  [owner focusSplitPane:YES];
  [pa.messages removeAllObjects];
  [pa renderMessagesScrollingToBottom:NO];
  Check(!pa.emptyStateView.hidden, @"new draft shows its empty state before the first message");
  @autoreleasepool {
    Check([owner persistActiveDraftChatWithModel:@"test-model"], @"draft can be saved while split");
  }
  Drain();
  TLWorkspaceTab *saved = [state workspaceTabWithKind:TLWorkspaceTabKindChat tabID:123];
  Check([splits groupForTab:saved] && [owner valueForKey:@"chatPresentation"] == pa, @"saving preserves pair and live chat presentation");
  Check(!pa.closed, @"saving a draft does not dispose its retained chat controller");
  TLChatMessage *firstMessage = [TLChatMessage messageWithRole:TLRoleUser content:@"Hello after saving" thinking:nil];
  [pa.messages addObject:firstMessage];
  [pa markMessageDirty:firstMessage];
  [pa scheduleStreamingMessageRender];
  Drain();
  Check(pa.emptyStateView.hidden && pa.messageStack.arrangedSubviews.count == 1 &&
    [pa.messageRowViews objectForKey:firstMessage].superview == pa.messageStack,
    @"the first message replaces the empty state after draft promotion");
  [owner loadChatWithID:c.tabID];
  [owner closeChatTabWithID:b.tabID]; Drain();
  Check(state.snapshot.activeTabID == c.tabID && !workspace.split, @"closing a background pair does not steal focus");
  [owner splitTab:saved besideTab:c onLeft:YES];
  [owner closeChatTabWithID:123]; Drain();
  Check(pa.closed, @"closing the saved tab still disposes its controller");
  Check(state.snapshot.activeTabID == c.tabID && !workspace.split, @"closing the focused half expands and focuses its companion");
  // A cancelled drag never changes tab order or commits a split.
  [owner startNewChatWithModel:@"test-model" focus:NO];
  TLWorkspaceTab *d = state.snapshot.workspaceTabs.lastObject;
  [owner loadChatWithID:c.tabID];
  Drain();
  [strip.transitionCoordinator finishAllTransitions]; [window.contentView layoutSubtreeIfNeeded];
  NSArray<TLChromeTabView *> *dragViews=[[strip valueForKey:@"tabViews"] copy];
  TLChromeTabView *fallback=dragViews[0], *source=dragViews[1];
  NSView *tabStack=[strip valueForKey:@"tabStack"];
  CGFloat originalStripWidth=NSWidth(tabStack.frame);
  NSPoint press=[source convertPoint:NSMakePoint(NSMidX(source.bounds),NSMidY(source.bounds)) toView:nil];
  NSEvent *(^pointer)(NSEventType,NSPoint)=^NSEvent *(NSEventType type,NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
  };
  [source mouseDown:pointer(NSEventTypeLeftMouseDown,press)];
  [source mouseDragged:pointer(NSEventTypeLeftMouseDragged,NSMakePoint(press.x+10,press.y))];
  NSPoint outside=[workspace convertPoint:NSMakePoint(NSMidX(workspace.bounds),NSMidY(workspace.bounds)) toView:nil];
  [source mouseDragged:pointer(NSEventTypeLeftMouseDragged,outside)];
  [strip.transitionCoordinator finishAllTransitions]; [window.contentView layoutSubtreeIfNeeded];
  NSTextField *fallbackLabel=[fallback valueForKey:@"titleLabel"];
  Check(fallback.active && !fallback.hidden && !fallbackLabel.isHiddenOrHasHiddenAncestor && fallbackLabel.stringValue.length>0 && strip.selectionView.layer.zPosition<fallback.layer.zPosition, @"dragging the second tab outside leaves the first tab selected with its label above the selection background");
  Check(source.hidden && NSWidth(tabStack.frame)<originalStripWidth, @"the floating tab disappears from the strip and its slot collapses");
  Check(![[workspace valueForKey:@"dragBadge"] isHidden], @"the dragged title remains beside the pointer");
  NSView *dragChrome=[owner valueForKey:@"topbar"];
  NSBitmapImageRep *dragRep=[dragChrome bitmapImageRepForCachingDisplayInRect:dragChrome.bounds];
  [dragChrome cacheDisplayInRect:dragChrome.bounds toBitmapImageRep:dragRep];
  [[dragRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-external-tab-drag.png" atomically:YES];
  DispatchDragEvent(pointer(NSEventTypeLeftMouseDragged,press));
  [window.contentView layoutSubtreeIfNeeded];
  Check(!source.hidden && [[strip valueForKey:@"tabViews"] containsObject:source] && fabs(NSWidth(tabStack.frame)-originalStripWidth)<0.01, @"returning to the tab bar restores the same tab and its slot");
  DispatchDragEvent(pointer(NSEventTypeLeftMouseDragged,outside));
  DispatchDragEvent([NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
    windowNumber:window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53]);
  [strip.transitionCoordinator finishAllTransitions]; [window.contentView layoutSubtreeIfNeeded];
  Check(!source.hidden && [[strip valueForKey:@"tabViews"] count]==2 && state.snapshot.activeTabID==c.tabID, @"cancelling an external drag restores both tabs and the original selection");
  Check(![strip valueForKey:@"draggedTab"] && ![strip valueForKey:@"dragEventMonitor"] && [[workspace valueForKey:@"preview"] isHidden], @"Escape tears down tracking and the drop overlay through AppKit event delivery");
  [source mouseDown:pointer(NSEventTypeLeftMouseDown,press)];
  [source mouseDragged:pointer(NSEventTypeLeftMouseDragged,outside)];
  [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
  Check(!source.hidden && ![strip valueForKey:@"draggedTab"] && [[workspace valueForKey:@"preview"] isHidden], @"switching apps cancels and restores a detached tab drag");
  [owner workspaceTabsController:nil willSelectTab:d]; [owner loadChatWithID:d.tabID];
  NSView *dragTopbar=[owner valueForKey:@"topbar"];
  NSPoint startDrag=[dragTopbar convertPoint:NSMakePoint(NSMidX(dragTopbar.bounds),NSMidY(dragTopbar.bounds)) toView:nil];
  Check(![owner workspaceTabsController:nil dragTab:d atWindowPoint:startDrag] && ![[workspace valueForKey:@"preview"] isHidden], @"drop areas appear while the pointer is still dragging over the tab strip");
  [owner workspaceTabsController:nil endDraggingTab:d cancelled:YES];
  Check([[workspace valueForKey:@"preview"] isHidden] && state.snapshot.activeTabID==c.tabID, @"cancelling a strip drag clears targets and restores the original tab");
  [owner workspaceTabsController:nil willSelectTab:d]; [owner loadChatWithID:d.tabID];
  NSPoint drop = [workspace convertPoint:NSMakePoint(50,200) toView:nil];
  [owner workspaceTabsController:nil dragTab:d atWindowPoint:drop];
  Check(![[workspace valueForKey:@"preview"] isHidden], @"dragging from tabs shows a split preview");
  [owner workspaceTabsController:nil endDraggingTab:d cancelled:YES];
  Check(!workspace.split && state.snapshot.activeTabID == c.tabID, @"cancel restores the prior tab without grouping");
  [source mouseDown:pointer(NSEventTypeLeftMouseDown,press)];
  [source mouseDragged:pointer(NSEventTypeLeftMouseDragged,drop)];
  DispatchDragEvent(pointer(NSEventTypeLeftMouseUp,drop));
  Drain();
  [strip.transitionCoordinator finishAllTransitions];
  Check(workspace.split && [[splits groupForTab:d].leftIdentity isEqual:TLWorkspaceTabIdentity(d)], @"dropping commits the previewed left split");
  Check(![strip valueForKey:@"draggedTab"] && ![strip valueForKey:@"dragEventMonitor"] && [[workspace valueForKey:@"preview"] isHidden], @"releasing a detached tab via AppKit finishes the drag and removes every drop target");
  NSArray<TLChromeTabView *> *groupTabs=[strip valueForKey:@"tabViews"];
  Check(groupTabs.count==1 && [groupTabs.firstObject.title isEqual:@"Split view"] &&
    (source.hidden || !source.superview || source==groupTabs.firstObject), [NSString stringWithFormat:@"a successful split shows only its group tab without resurrecting the standalone tab (%@, source hidden %d, attached %d)",[groupTabs valueForKey:@"title"],source.hidden,source.superview!=nil]);
  for (NSNumber *fromLeft in @[@YES,@NO]) {
    [owner startNewChatWithModel:@"test-model" focus:NO];
    TLWorkspaceTab *third=state.snapshot.workspaceTabs.lastObject;
    [owner loadChatWithID:c.tabID];
    [workspace layoutSubtreeIfNeeded];
    NSRect left=[workspace hostForIdentity:TLWorkspaceTabIdentity(d)].frame;
    NSRect right=[workspace hostForIdentity:TLWorkspaceTabIdentity(c)].frame;
    NSPoint centerDrop=[workspace convertPoint:NSMakePoint(fromLeft.boolValue ? NSMaxX(left)-1 : NSMinX(right)+1,NSMidY(left)) toView:nil];
    [owner workspaceTabsController:nil willSelectTab:third]; [owner loadChatWithID:third.tabID];
    [owner workspaceTabsController:nil dragTab:third atWindowPoint:centerDrop];
    [owner workspaceTabsController:nil endDraggingTab:third cancelled:NO];
    Check([[splits groupForTab:c].columns isEqual:@[@[TLWorkspaceTabIdentity(d)],@[TLWorkspaceTabIdentity(third)],@[TLWorkspaceTabIdentity(c)]]], @"approaching either edge of the shared middle target inserts the third view between the same two columns");
    [owner closeChatTabWithID:third.tabID]; [owner loadChatWithID:c.tabID]; Drain();
  }
  NSAppearance *originalAppearance = NSApp.appearance;
  [owner installEffectiveAppearanceObserver];
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    NSApp.appearance = [NSAppearance appearanceNamed:theme.integerValue == TLThemePreferenceDark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    Drain();
    Check(window.appearance == nil, @"the app window inherits the system color scheme without a manual override");
    Check(workspace.palette.dark == (theme.integerValue == TLThemePreferenceDark), @"system appearance changes reach existing split chrome despite a legacy theme preference");
    for (TLChatTabController *presentation in [[owner valueForKey:@"chatPresentations"] allValues])
      Check(presentation.messageInput.palette.dark == workspace.palette.dark, @"theme reaches every cached composer");
  }
  NSApp.appearance = originalAppearance; Drain();
  [[[owner valueForKey:@"workspaceTabsController"] transitionCoordinator] finishAllTransitions];
  Drain();
  for (NSNumber *width in @[@200,@500,@1100]) {
    [owner windowWillResize:window toSize:NSMakeSize(width.doubleValue,700)];
    [window setContentSize:NSMakeSize(width.doubleValue,700)]; [window.contentView layoutSubtreeIfNeeded]; Drain();
    Check(NSWidth(window.contentView.bounds) == width.doubleValue, [NSString stringWithFormat:@"split preserves window width %@ (actual %g)", width, NSWidth(window.contentView.bounds)]);
  }
  NSView *topbar = [owner valueForKey:@"topbar"];
  NSPoint stripDrop = [topbar convertPoint:NSMakePoint(NSWidth(topbar.bounds)-10,NSMidY(topbar.bounds)) toView:nil];
  workspace.dragPane(TLWorkspaceTabIdentity(c), stripDrop, YES, YES);
  Check(workspace.split, @"cancelling a pane drag keeps its group intact");
  workspace.dragPane(TLWorkspaceTabIdentity(c), stripDrop, YES, NO);
  Check(!workspace.split && state.snapshot.workspaceTabs.count == 2, @"dragging a pane into the tab strip retains both tabs");
  TLWorkspaceTab *browser = [TLWorkspaceTab tabWithKind:TLWorkspaceTabKindBrowser tabID:99 title:@"Browser" toolTip:nil URL:[NSURL URLWithString:@"https://example.com"] closeable:YES];
  TLWorkspaceTabRuntime *runtime = [TLWorkspaceTabRuntime runtimeWithContentView:[NSView new] openAction:@selector(openBrowserTab:) closeAction:@selector(closeBrowserTab:)];
  [[owner valueForKey:@"workspaceTabRuntimes"] setObject:runtime forKey:TLWorkspaceTabRuntimeKey(browser.kind,browser.tabID)];
  [state addWorkspaceTab:browser activate:YES]; Drain();
  [owner splitTab:browser besideTab:c onLeft:YES]; Drain();
  [owner focusSplitPane:YES]; Drain();
  TLChatTabController *chat = [owner valueForKey:@"chatPresentation"];
  Check(chat.promptTextView.editable && [window makeFirstResponder:chat.promptTextView], @"chat beside browser accepts keyboard focus");
  NSPoint editorPoint = [chat.promptTextView convertPoint:NSMakePoint(NSMidX(chat.promptTextView.bounds),NSMidY(chat.promptTextView.bounds)) toView:window.contentView.superview];
  NSView *hit = [window.contentView hitTest:editorPoint];
  Check(hit == chat.promptTextView || [hit isDescendantOf:chat.promptTextView], [NSString stringWithFormat:@"pane editor receives pointer hit (got %@)",hit.class]);
  NSUInteger beforeSplitLink = state.snapshot.workspaceTabs.count;
  NSURL *linkedURL = [NSURL URLWithString:@"https://example.com/linked-page"];
  [owner openLinkURL:linkedURL inSplitBesideBrowserTabID:browser.tabID]; Drain();
  TLWorkspaceTab *linked = [state workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:state.snapshot.activeTabID];
  TLWorkspaceSplitGroup *linkedGroup = [splits groupForTab:browser];
  Check(state.snapshot.workspaceTabs.count == beforeSplitLink + 1 && [linked.URL isEqual:linkedURL], @"split link creates a browser tab for the clicked URL");
  Check([linkedGroup.leftIdentity isEqual:TLWorkspaceTabIdentity(browser)] &&
    [linkedGroup.rightIdentity isEqual:TLWorkspaceTabIdentity(linked)], @"split link uses its source browser even when the other pane was focused");
  Check(state.snapshot.activeTabID == linked.tabID && workspace.rightFocused, @"split link focuses the new right pane");
  Check([splits groupForTab:c] == linkedGroup && linkedGroup.identities.count == 3, @"adding a split link keeps the existing third pane visible");
  [owner openLinkURL:linkedURL inSplitBesideBrowserTabID:99999];
  [owner openLinkURL:[NSURL URLWithString:@"javascript:alert(1)"] inSplitBesideBrowserTabID:browser.tabID];
  Check(state.snapshot.workspaceTabs.count == beforeSplitLink + 1, @"closed sources and unsupported URLs cannot create split tabs");
  [owner handleContextLinkURL:linkedURL destination:TLBrowserLinkSplitView sourceIdentity:TLWorkspaceTabIdentity(c)]; Drain();
  TLWorkspaceTab *chatLink = [state workspaceTabWithKind:TLWorkspaceTabKindBrowser tabID:state.snapshot.activeTabID];
  Check(![splits groupForTab:chatLink] && [splits groupForTab:c].identities.count == 3, @"three columns leave a newly opened link as a standalone tab");
  [owner loadChatWithID:c.tabID];
  NSUInteger countBeforeClose = state.snapshot.workspaceTabs.count;
  workspace.closeIdentity(TLWorkspaceTabIdentity(linked)); Drain();
  Check(state.snapshot.workspaceTabs.count == countBeforeClose-1 && [splits groupForTab:c].identities.count == 2 && workspace.split,
    @"closing a pane removes only that tab and preserves its two companions");
  [owner closeActiveTabOrWindow:owner]; Drain();
  Check(![state workspaceTabWithKind:c.kind tabID:c.tabID] && ![state workspaceTabWithKind:browser.kind tabID:browser.tabID] &&
    [state workspaceTabWithKind:chatLink.kind tabID:chatLink.tabID], @"closing a grouped tab closes its remaining panes and preserves unrelated tabs");
  TestChatInputNavigation(owner, state);
  TestNewTabContextMenu(owner, state);
  TestBrowserChatDefaultWidths(owner, state);
  [window close];
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TestGrouping(); TestGrid(); TestColumnLayout(); TestDropTargets(); TestUnchangedDropTargets(); TestPointerCancellation(); TestPaneGeometry(); TestDraftPromotionAcrossEvents(); TestRealWorkspace();
  NSLog(@"SplitWorkspaceTests passed");
} return 0; }
