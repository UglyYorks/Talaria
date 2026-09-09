#import <AppKit/AppKit.h>
#import "TLNotificationsController.h"
#import "design_system/TLNotificationStackView.h"
#import "design_system/TLThemedButton.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

static NSDictionary *Item(NSString *identifier, NSString *task, NSString *kind, NSString *title,
                          NSString *urgency, BOOL read, NSInteger updated) {
  return @{@"id": identifier, @"task_id": task, @"source_kind": kind, @"task_name": task,
    @"title": title, @"summary": @"Details from the automation's original message.", @"urgency": urgency,
    @"is_read": @(read), @"created_at": @(updated), @"updated_at": @(updated), @"version": @3,
    @"session_id": @"run-session", @"tool_call_id": [@"tool-" stringByAppendingString:identifier],
    @"message_id": @"message", @"run_id": @"run"};
}

static NSArray<TLNotificationStackView *> *Groups(TLNotificationsController *controller) {
  return [controller valueForKey:@"groupViews"];
}
static NSArray<NSControl *> *Rows(TLNotificationStackView *group) { return [group valueForKey:@"itemViews"]; }

static void Layout(TLNotificationsController *controller) {
  [controller.view.window.contentView layoutSubtreeIfNeeded];
  [controller.view layoutSubtreeIfNeeded];
  for (TLNotificationStackView *group in Groups(controller)) [group layoutSubtreeIfNeeded];
}

static BOOL BitmapContainsLayers(NSBitmapImageRep *bitmap, NSArray<NSColor *> *layers) {
  CGFloat expected[3] = {0, 0, 0};
  for (NSColor *layer in layers) {
    NSColor *rgb = [layer colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    CGFloat alpha = rgb.alphaComponent;
    expected[0] = rgb.redComponent * alpha + expected[0] * (1 - alpha);
    expected[1] = rgb.greenComponent * alpha + expected[1] * (1 - alpha);
    expected[2] = rgb.blueComponent * alpha + expected[2] * (1 - alpha);
  }
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
    for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
      NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      if (fabs(pixel.redComponent - expected[0]) < 0.035 &&
          fabs(pixel.greenComponent - expected[1]) < 0.035 &&
          fabs(pixel.blueComponent - expected[2]) < 0.035 && pixel.alphaComponent > 0.9) return YES;
    }
  }
  return NO;
}
static BOOL BitmapContains(NSBitmapImageRep *bitmap, NSColor *expected) {
  return BitmapContainsLayers(bitmap, @[expected]);
}

// Use a known device color space for pixel assertions; cached window bitmaps can
// carry a display profile and otherwise introduce a second color conversion.
static NSBitmapImageRep *RenderControl(NSControl *control) {
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:ceil(NSWidth(control.bounds)) pixelsHigh:ceil(NSHeight(control.bounds)) bitsPerSample:8
    samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  TLThemePalette *palette = [control valueForKey:@"palette"];
  [palette.tabBackground setFill]; NSRectFill(control.bounds);
  if ([control isKindOfClass:NSButton.class]) [control.cell drawWithFrame:control.bounds inView:control];
  else [control drawRect:control.bounds];
  [NSGraphicsContext restoreGraphicsState];
  return bitmap;
}

static NSBitmapImageRep *Render(NSView *view) {
  [view layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  return bitmap;
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TLThemePalette *dark = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  TLNotificationsController *controller = [[TLNotificationsController alloc] initWithPalette:dark];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 280, 680)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window.contentView addSubview:controller.view];
  [NSLayoutConstraint activateConstraints:@[
    [controller.view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
    [controller.view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [controller.view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
    [controller.view.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]]];
  Check(Groups(controller).count == 0, @"starts with no demo notifications");

  NSDictionary *high = Item(@"high", @"Daily Email Summary", @"cron", @"Payment pending", @"high", NO, 10);
  NSDictionary *medium = Item(@"medium", @"Daily Email Summary", @"cron", @"Project deadline question", @"medium", NO, 30);
  NSDictionary *read = Item(@"read", @"Daily Email Summary", @"cron", @"Earlier report", @"low", YES, 40);
  NSDictionary *low = Item(@"low", @"Review Downloads", @"cron", @"14 downloads need review", @"low", NO, 20);
  NSDictionary *sameTaskOtherTrigger = Item(@"event", @"Daily Email Summary", @"webhook", @"New email arrived", @"medium", NO, 50);
  NSDictionary *old = Item(@"old", @"Security Checkup", @"cron", @"Password security issues", @"high", YES, 100);
  NSArray *feed = @[old, low, read, medium, high, sameTaskOtherTrigger];
  controller.notifications = feed; Layout(controller);
  Check(Groups(controller).count == 4, @"one group per source kind and stable task ID");
  TLNotificationStackView *email = Groups(controller).firstObject;
  Check([email.notifications.firstObject[@"id"] isEqual:@"high"], @"unread urgent group comes first despite older timestamp");
  Check([Groups(controller)[1].notifications.firstObject[@"id"] isEqual:@"event"], @"medium unread precedes newer read groups");
  Check([Groups(controller).lastObject.notifications.firstObject[@"id"] isEqual:@"old"], @"read high urgency remains after unread groups");
  Check(email.unreadCount == 2 && Rows(email).count == 1, @"collapsed stack counts unread notifications, not all items");

  __block NSDictionary *opened;
  __block NSMutableArray *readActions = [NSMutableArray array];
  controller.openHandler = ^(NSDictionary *notification) { opened = notification; };
  controller.readHandler = ^(NSDictionary *notification, BOOL readState) {
    [readActions addObject:@{@"notification": notification, @"read": @(readState)}];
  };
  Check([Rows(email).firstObject accessibilityPerformPress], @"stack exposes VoiceOver activation");
  Layout(controller);
  Check(email.expanded && Rows(email).count == 3 && opened == nil && readActions.count == 0,
    @"expansion reveals individual notifications without opening or marking anything read");
  [Rows(email)[1] accessibilityPerformPress];
  Check([opened[@"id"] isEqual:@"medium"] && [opened[@"tool_call_id"] isEqual:@"tool-medium"] &&
    [opened[@"version"] isEqual:@3], @"item activation preserves the exact navigation anchor and version");
  Check(readActions.count == 0, @"only the owner marks read after navigation succeeds");
  NSControl *readRow = Rows(email).lastObject;
  NSEvent *contextEvent = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint
    modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  NSMenuItem *markUnread = [[readRow menuForEvent:contextEvent] itemAtIndex:0];
  Check([markUnread.title isEqualToString:@"Mark as unread"], @"read notification offers mark unread");
  [NSApp sendAction:markUnread.action to:markUnread.target from:markUnread];
  Check(![readActions.lastObject[@"read"] boolValue] &&
    [readActions.lastObject[@"notification"][@"id"] isEqual:@"read"], @"context action preserves individual read state");

  controller.loading = YES; controller.errorMessage = @"Unable to refresh. Saved notifications are available.";
  Check(Groups(controller).count == 4 && email.expanded, @"refresh failures preserve cached notifications and expansion");
  controller.notifications = [feed copy];
  Check(Groups(controller).firstObject == email && email.expanded, @"unchanged feed preserves native interaction state");
  controller.loading = NO; controller.errorMessage = nil;

  for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    controller.palette = palette; Layout(controller);
    Check(BitmapContains(RenderControl(Rows(email)[0]), palette.sidebarUrgentNotificationBadgeSurface), @"high urgency renders the red semantic badge");
    Check(BitmapContains(RenderControl(Rows(email)[1]), palette.sidebarInboxPrimaryBadgeSurface), @"medium urgency renders the blue semantic badge");
    Check(BitmapContainsLayers(RenderControl(Rows(email)[2]), @[palette.tabBackground, palette.sidebarSurface,
      palette.sidebarInboxBadgeSurface]), @"read low urgency retains its grey dot");
    Check(BitmapContains(RenderControl(Rows(email)[0]), palette.appText), @"title foreground follows the active theme");
    TLThemedButton *collapse = [email valueForKey:@"collapseButton"];
    NSBitmapImageRep *buttonBitmap = RenderControl(collapse);
    Check(BitmapContainsLayers(buttonBitmap, @[palette.tabBackground, palette.secondaryActionSurface]) && BitmapContains(buttonBitmap, palette.secondaryActionText),
      @"collapse button renders matching themed foreground/background");
    NSString *path = [NSString stringWithFormat:@"/tmp/talaria-notifications-%@.png", palette.dark ? @"dark" : @"light"];
    [[Render(controller.view) representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
  }

  NSEvent *left = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
    windowNumber:window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:123];
  [Rows(email).firstObject keyDown:left]; Layout(controller);
  Check(!email.expanded && Rows(email).count == 1, @"left arrow collapses the stack");
  NSMenuItem *markAll = [[Rows(email).firstObject menuForEvent:contextEvent] itemAtIndex:0];
  Check([markAll.title isEqualToString:@"Mark all as read"], @"collapsed group offers explicit bulk read action");
  NSUInteger actionCount = readActions.count;
  [NSApp sendAction:markAll.action to:markAll.target from:markAll];
  Check(readActions.count == actionCount + 2, @"bulk read updates only unread items in the selected group");

  [window setContentSize:NSMakeSize(200, 680)]; Layout(controller);
  NSScrollView *scroll = [controller valueForKey:@"scrollView"];
  for (TLNotificationStackView *group in Groups(controller)) {
    Check(NSMaxX(group.frame) <= NSWidth(scroll.contentView.bounds) + 0.5, @"stacks fit narrow sidebar width");
    for (NSView *row in Rows(group)) Check(NSHeight(row.frame) > 0 && NSWidth(row.frame) > 0, @"narrow rows retain readable layout");
  }
  [[Render(controller.view) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:@"/tmp/talaria-notifications-narrow.png" atomically:YES];

  controller.notifications = @[]; Layout(controller);
  Check(Groups(controller).count == 0 &&
    [[(NSTextField *)[controller valueForKey:@"statusLabel"] stringValue] containsString:@"caught up"],
    @"empty feed clears prior agent's groups and shows a calm empty state");
  [window close];
  NSLog(@"NotificationSidebarTests passed");
  return 0;
} }
