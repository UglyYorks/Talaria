#import <AppKit/AppKit.h>
#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"

@interface TLChromeTabView (TabLayoutTesting)
- (NSRect)activeTabRectInRect:(NSRect)rect;
- (NSRect)inactiveHoverPillRectInRect:(NSRect)rect;
@end

static void AssertOffset(TLChromeTabView *tab, CGFloat expected, NSString *context) {
  NSLayoutConstraint *constraint = [tab valueForKey:@"iconCenterYConstraint"];
  if (fabs(constraint.constant - expected) > 0.001) {
    NSLog(@"FAIL %@: expected %g, got %g", context, expected, constraint.constant);
    exit(1);
  }
}

static void AssertClose(CGFloat actual, CGFloat expected, NSString *context) {
  if (fabs(actual - expected) > 0.001) {
    NSLog(@"FAIL %@: expected %g, got %g", context, expected, actual);
    exit(1);
  }
}

static void TestSharedFlareSpace(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *left = [[TLChromeTabView alloc] init];
  TLChromeTabView *right = [[TLChromeTabView alloc] init];
  NSLayoutConstraint *leftWidth = [left.widthAnchor constraintEqualToConstant:palette.tabMaxWidth];
  NSLayoutConstraint *rightWidth = [right.widthAnchor constraintEqualToConstant:palette.tabMaxWidth];
  [controller setValue:[NSMutableArray arrayWithObjects:leftWidth, rightWidth, nil] forKey:@"tabWidthConstraints"];

  [controller updateTabWidthsForAvailableWidth:300.0];
  AssertClose(leftWidth.constant, 156.0, @"two tabs reclaim their tightened shared boundary");
  AssertClose(rightWidth.constant, 156.0, @"tightened flare layout keeps tab widths equal");
  AssertClose(stack.spacing, -(palette.tabFlareRadius + palette.space2), @"neighboring tab bodies sit closer together");
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 300.0, @"tightened tabs leave no unused strip width");

  [controller updateTabWidthsForAvailableWidth:20.0];
  AssertClose(leftWidth.constant + rightWidth.constant + stack.spacing, 20.0, @"narrow tabs continue sharing their reduced flares");
}

static void TestHoveredTabSeparators(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *left = [[TLChromeTabView alloc] init];
  TLChromeTabView *middle = [[TLChromeTabView alloc] init];
  TLChromeTabView *right = [[TLChromeTabView alloc] init];
  middle.dragDelegate = (id<TLChromeTabViewDelegate>)controller;
  [controller setValue:[NSMutableArray arrayWithObjects:left, middle, right, nil] forKey:@"tabViews"];
  NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];

  [middle mouseEntered:event];
  if (middle.showsLeadingSeparator || right.showsLeadingSeparator) {
    NSLog(@"FAIL hovered tab keeps an adjacent separator visible");
    exit(1);
  }

  [middle mouseExited:event];
  if (!middle.showsLeadingSeparator || !right.showsLeadingSeparator) {
    NSLog(@"FAIL leaving a tab does not restore its adjacent separators");
    exit(1);
  }

  [controller setNewTabButtonHovered:YES];
  if (right.showsTrailingSeparator) {
    NSLog(@"FAIL new-tab hover keeps the final separator visible");
    exit(1);
  }
  [controller setNewTabButtonHovered:NO];
  if (!right.showsTrailingSeparator) {
    NSLog(@"FAIL leaving the new-tab button does not restore the final separator");
    exit(1);
  }
}

static void TestInactiveFirstTabPadding(TLThemePalette *palette) {
  NSStackView *stack = [[NSStackView alloc] init];
  TLWorkspaceTabsController *controller = [[TLWorkspaceTabsController alloc] initWithTabStack:stack
                                                                                       target:nil
                                                                                     delegate:nil
                                                                                      palette:palette];
  TLChromeTabView *first = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  first.palette = palette;
  first.active = NO;
  TLChromeTabView *second = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, palette.tabHeight)];
  [controller setValue:[NSMutableArray arrayWithObjects:first, second, nil] forKey:@"tabViews"];

  [controller updateEdgeAttachmentState];
  NSLayoutConstraint *leading = [first valueForKey:@"iconLeadingConstraint"];
  AssertClose(first.leadingFlareOutset, palette.space0, @"first inactive tab does not reserve an impossible leading flare");
  AssertClose(leading.constant,
              palette.tabIconLeadingInset - palette.tabFlareRadius,
              @"first inactive tab uses the same left content padding as the selected state");

  NSRect hoverRect = [first inactiveHoverPillRectInRect:first.bounds];
  AssertClose(NSMinX(hoverRect), palette.tabFlareRadius, @"inactive hover excludes the leading flare width");
  AssertClose(NSMaxX(hoverRect), NSWidth(first.bounds) - palette.tabFlareRadius,
              @"inactive hover excludes the trailing flare width");
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    for (NSNumber *themeValue in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      TLThemePreference theme = themeValue.integerValue;
      TLChromeTabView *tab = [[TLChromeTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 36)];
      tab.palette = [TLThemePalette paletteForPreference:theme];
      tab.icon = @"\U0001F310";
      AssertOffset(tab, tab.palette.space2, @"Emoji fallback keeps its offset");

      tab.image = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
      AssertOffset(tab, tab.palette.space0, @"Loaded favicon is vertically centered");
      tab.active = YES;
      AssertOffset(tab, tab.palette.space0, @"Active favicon stays centered");
      tab.palette = [TLThemePalette paletteForPreference:theme];
      AssertOffset(tab, tab.palette.space0, @"Theme refresh preserves favicon alignment");

      tab.image = nil;
      AssertOffset(tab, tab.palette.space2, @"Removing favicon restores emoji positioning");
      tab.systemIconName = @"clock";
      AssertOffset(tab, tab.palette.space0, @"System icon positioning is unchanged");
      NSRect activeRect = [tab activeTabRectInRect:tab.bounds];
      AssertClose(NSMinY(activeRect), NSMinY(tab.bounds), @"shorter active tab stays attached to content");
      AssertClose(NSHeight(activeRect),
                  NSHeight(tab.bounds) - tab.palette.tabActiveHeightReduction,
                  @"active tab height uses the theme reduction");
      TestSharedFlareSpace(tab.palette);
      TestHoveredTabSeparators(tab.palette);
      TestInactiveFirstTabPadding(tab.palette);

      NSLayoutConstraint *leading = [tab valueForKey:@"iconLeadingConstraint"];
      tab.leadingFlareOutset = tab.palette.space0;
      [tab layoutSubtreeIfNeeded];
      AssertClose(leading.constant,
                  tab.palette.tabIconLeadingInset - tab.palette.tabFlareRadius,
                  @"edge-connected first tab keeps the standard body-to-content padding");

      TLChromeTabView *neighbor = [[TLChromeTabView alloc] init];
      neighbor.active = YES;
      AssertClose(neighbor.layer.zPosition, 1.0, @"selected tab draws above overlapping neighbors");
      neighbor.active = NO;
      AssertClose(neighbor.layer.zPosition, 0.0, @"inactive tab returns to the strip plane");
    }
    NSLog(@"TabLayoutTests passed");
  }
  return 0;
}
