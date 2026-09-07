#import <AppKit/AppKit.h>
#import "TLAutomationsTabController.h"
#import "design_system/TLThemedButton.h"

@interface TLAutomationsTabController (Testing)
- (void)newAutomation:(id)sender;
- (void)save:(id)sender;
- (void)runNow:(id)sender;
- (void)toggleAdvanced:(id)sender;
- (void)fieldChanged:(id)sender;
@end

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Drain(void) {
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:0.05];
  while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
}
static NSDictionary *Fixture(void) {
  return @{@"jobs": @[@{@"job_id": @"job-1", @"name": @"Morning briefing", @"enabled": @YES,
    @"schedule": @"Every weekday at 9am", @"state": @"scheduled", @"next_run_at": @"2026-09-08T09:00:00+10:00",
    @"last_run_at": @"2026-09-07T09:00:00+10:00", @"last_status": @"success",
    @"values": @{@"name": @"Morning briefing", @"schedule": @"0 9 * * 1-5", @"prompt": @"Review my project updates and prepare a concise morning briefing. Highlight anything that needs my attention.",
                 @"deliver": @"local", @"skills": @[@"research"], @"continuity": @NO}}],
    @"fields": @[@{@"key": @"name", @"type": @"string"}, @{@"key": @"prompt", @"type": @"string"},
      @{@"key": @"schedule", @"type": @"string"}, @{@"key": @"deliver", @"type": @"string"},
      @{@"key": @"repeat", @"type": @"integer"}, @{@"key": @"skills", @"type": @"array"},
      @{@"key": @"continuity", @"type": @"boolean"}, @{@"key": @"model", @"type": @"string"},
      @{@"key": @"no_agent", @"type": @"boolean"}],
    @"scheduler": @{@"running": @NO, @"owned": @NO, @"provider": @"builtin", @"external": @NO}};
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  Check(NSApp != nil, @"native tests need WindowServer access");
  TLAgentRecord *agent = [[TLAgentRecord alloc] init]; agent.agentID = 17; agent.name = @"Personal Hermes";
  __block NSMutableArray *requests = [NSMutableArray array];
  __block TLAutomationReply pending;
  __block BOOL defer = NO;
  TLAutomationsTabController *controller = [[TLAutomationsTabController alloc]
    initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] agents:@[agent] agentID:17
    request:^(NSInteger agentID, NSDictionary *parameters, TLAutomationReply reply) {
      Check(agentID == 17, @"requests stay scoped to displayed agent");
      [requests addObject:parameters];
      if (defer) { pending = reply; return; }
      reply([parameters[@"action"] isEqual:@"list"] ? Fixture() : @{@"success": @YES}, nil);
    }];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 1000)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = controller.view;
  [controller refresh:nil]; Drain();
  NSTableView *table = [controller valueForKey:@"table"];
  Check(table.numberOfRows == 1, @"jobs load from Hermes");
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO]; Drain();
  NSMutableDictionary *editors = [controller valueForKey:@"editors"];
  Check([[(NSTextField *)editors[@"schedule"] stringValue] isEqual:@"0 9 * * 1-5"], @"editing uses round-trippable schedule, not display text");
  NSUInteger before = requests.count;
  [controller save:nil]; Drain();
  Check(requests.count == before, @"opening then saving does not rewrite optional defaults");
  ((NSTextField *)editors[@"name"]).stringValue = @"Renamed briefing";
  [controller fieldChanged:nil];
  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:palette]; Drain();
    Check([[(NSTextField *)editors[@"name"] stringValue] isEqual:@"Renamed briefing"], @"theme keeps unsaved draft");
    Check([[(NSTextField *)editors[@"name"] textColor] isEqual:palette.controlText], @"field foreground follows theme");
    [controller.view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [controller.view bitmapImageRepForCachingDisplayInRect:controller.view.bounds];
    [controller.view cacheDisplayInRect:controller.view.bounds toBitmapImageRep:bitmap];
    NSString *path = [NSString stringWithFormat:@"/tmp/talaria-automations-%@.png", theme.integerValue == TLThemePreferenceDark ? @"dark" : @"light"];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
  }
  [controller save:nil]; Drain();
  NSDictionary *update = requests[requests.count - 2];
  Check([update[@"action"] isEqual:@"update"], @"save updates selected job");
  Check([update[@"values"] isEqual:@{@"name": @"Renamed briefing"}], @"save sends only changed fields");
  [controller newAutomation:nil]; Drain();
  editors = [controller valueForKey:@"editors"];
  ((NSTextField *)editors[@"schedule"]).stringValue = @"in 30m";
  ((NSTextView *)editors[@"prompt"]).string = @"Remind me to check the build";
  ((NSTextField *)editors[@"repeat"]).stringValue = @"3.5";
  before = requests.count; [controller save:nil]; Drain();
  Check(requests.count == before, @"invalid repeat never reaches Hermes");
  ((NSTextField *)editors[@"repeat"]).stringValue = @"";
  [controller save:nil]; Drain();
  NSDictionary *create = requests[requests.count - 2];
  Check([create[@"action"] isEqual:@"create"] && [create[@"values"][@"deliver"] isEqual:@"local"], @"new jobs default to local output");
  Check(create[@"values"][@"repeat"] == nil, @"one-shot default repeat is preserved");
  defer = YES;
  [controller newAutomation:nil]; Drain();
  [window setContentSize:NSMakeSize(200, 720)];
  [controller.view layoutSubtreeIfNeeded];
  Check(NSWidth(window.contentView.bounds) == 200, @"automation content does not raise the minimum window width");
  [controller refresh:nil]; [controller refresh:nil];
  before = requests.count;
  Check(pending != nil, @"async request is pending");
  editors = [controller valueForKey:@"editors"];
  Check(![(NSTextField *)editors[@"name"] isEnabled] && ![(NSTextView *)editors[@"prompt"] isEditable],
    @"pending saves and refreshes cannot discard newly typed edits");
  [controller close]; pending(Fixture(), nil); Drain();
  [controller refresh:nil];
  Check(requests.count == before && controller.closed, @"close ignores pending callbacks and cancels refresh");
  [window close];
  NSLog(@"Automations tests passed");
} return 0; }
