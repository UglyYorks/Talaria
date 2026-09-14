#import <AppKit/AppKit.h>
#import "TLChatTabController.h"
#import "TLQuestionRequest.h"
#import "design_system/TLRuntimeActivityView.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLToolStatusPill.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Pump(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]]; }
static NSArray *Activities(void) {
  return @[
    @{@"id":@"process:1", @"kind":@"process", @"name":@"codex exec — repair the failing tests", @"state":@"running",
      @"detail":@"/workspace/talaria", @"output":@"Inspecting the test failures…\nUpdated the session event handler.\nRunning regression tests…\n12 tests passed.\n"},
    @{@"id":@"agent:review", @"kind":@"agent", @"name":@"Review the event lifecycle", @"state":@"running",
      @"detail":@"Checking background updates after the parent reply ends", @"model":@"Review agent"},
    @{@"id":@"notice:1", @"kind":@"notice", @"name":@"Process update", @"state":@"completed", @"detail":@"Build completed successfully"}
  ];
}
static NSScrollView *Output(TLRuntimeActivityView *view) { return [[view valueForKey:@"outputViews"] objectForKey:@"process:1"]; }
static NSUInteger PixelsNear(NSBitmapImageRep *rep, NSColor *target) {
  target = [target colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  NSUInteger count = 0;
  for (NSInteger y = 0; y < rep.pixelsHigh; y++) for (NSInteger x = 0; x < rep.pixelsWide; x++) {
    NSColor *pixel = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (pixel.alphaComponent > 0.9 && fabs(pixel.redComponent-target.redComponent) < 0.04 &&
        fabs(pixel.greenComponent-target.greenComponent) < 0.04 && fabs(pixel.blueComponent-target.blueComponent) < 0.04) count++;
  }
  return count;
}
// A one-point diagonal symbol has no fully opaque pixels at 1x. Check its
// rendered coverage toward the expected foreground, excluding reference swatches.
static NSUInteger SymbolInk(NSBitmapImageRep *rep, NSColor *foreground, NSColor *surface) {
  foreground = [foreground colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  surface = [surface colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  CGFloat fr = foreground.redComponent - surface.redComponent;
  CGFloat fg = foreground.greenComponent - surface.greenComponent;
  CGFloat fb = foreground.blueComponent - surface.blueComponent;
  CGFloat scale = fr*fr + fg*fg + fb*fb;
  if (scale < 0.001) return 0;
  NSUInteger count = 0;
  for (NSInteger y = 0; y < rep.pixelsHigh; y++) for (NSInteger x = 0; x < rep.pixelsWide - 8; x++) {
    NSColor *pixel = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat coverage = ((pixel.redComponent-surface.redComponent)*fr + (pixel.greenComponent-surface.greenComponent)*fg +
      (pixel.blueComponent-surface.blueComponent)*fb) / scale;
    if (coverage > 0.5 && coverage <= 1.05) count++;
  }
  return count;
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,680)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    TLTokenView *background = [[TLTokenView alloc] initWithFrame:window.contentView.bounds];
    window.contentView = background;
    TLRuntimeActivityView *view = [TLRuntimeActivityView new];
    [window.contentView addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
      [view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:12],
      [view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-12],
      [view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:12],
    ]];
    view.activities = Activities();
    TLThemedButton *button = [view valueForKey:@"disclosure"];
    Check([button.title containsString:@"2 running"] && !view.expanded, @"collapsed activity reports live work");
    Check([[(NSTextField *)[view valueForKey:@"preview"] stringValue] containsString:@"Checking"], @"latest agent update is visible without expanding");
    [button performClick:nil];
    Check(view.expanded, @"disclosure opens activity details");
    Check(Output(view) == nil, @"opening activity does not dump every task's output");
    NSStackView *rows = [view valueForKey:@"details"];
    NSStackView *firstHeader = [(NSStackView *)rows.arrangedSubviews.firstObject arrangedSubviews].firstObject;
    TLThemedButton *rowToggle = (id)firstHeader.arrangedSubviews.lastObject;
    [rowToggle performClick:nil];
    Check(Output(view) != nil, @"a row disclosure reveals its selectable details");
    for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      view.palette = [TLThemePalette paletteForPreference:theme.integerValue];
      window.appearance = [NSAppearance appearanceNamed:view.palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
      window.backgroundColor = view.palette.tabBackground;
      background.fillColor = view.palette.tabBackground;
      for (NSNumber *width in @[@200, @640]) {
        [window setContentSize:NSMakeSize(width.doubleValue, 680)];
        [window.contentView layoutSubtreeIfNeeded]; Pump();
        Check(NSWidth(view.frame) <= width.doubleValue && NSHeight(view.frame) > 100, @"activity fits narrow and wide windows");
        NSScrollView *scroll = Output(view);
        Check(NSWidth(scroll.frame) <= NSWidth(view.frame) + 1, @"terminal output remains inside the panel");
        NSTextView *output = (id)scroll.documentView;
        Check(!output.editable && output.selectable && !output.automaticLinkDetectionEnabled, @"terminal output is selectable plain text");
        Check([output.textColor isEqual:view.palette.markdownCodeText] && [output.backgroundColor isEqual:view.palette.markdownCodeSurface], @"terminal uses semantic theme colors");
        NSBitmapImageRep *rep = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
        [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
          writeToFile:[NSString stringWithFormat:@"build/activity-%@-%@.png", view.palette.dark ? @"dark" : @"light", width] atomically:YES];
      }
      NSStackView *renderedRows = [view valueForKey:@"details"];
      NSStackView *renderedHeader = [(NSStackView *)renderedRows.arrangedSubviews.firstObject arrangedSubviews].firstObject;
      for (TLThemedButton *button in @[[view valueForKey:@"disclosure"], renderedHeader.arrangedSubviews.lastObject])
      for (NSNumber *highlighted in @[@NO, @YES]) {
        button.cell.highlighted = highlighted.boolValue;
        NSSize size = NSMakeSize(NSWidth(button.bounds) + 8, NSHeight(button.bounds));
        NSImage *rendered = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect bounds) {
          [view.palette.tabBackground setFill]; NSRectFill(bounds);
          [button.cell drawWithFrame:button.bounds inView:button];
          // Reference swatches go through the same macOS color conversion as the cell.
          [view.palette.secondaryActionText setFill]; NSRectFillUsingOperation(NSMakeRect(size.width-8,0,4,size.height), NSCompositingOperationSourceOver);
          [view.palette.secondaryActionSurface setFill]; NSRectFillUsingOperation(NSMakeRect(size.width-4,0,4,size.height), NSCompositingOperationSourceOver);
          return YES;
        }];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:rendered.TIFFRepresentation];
        if (!button.title.length) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
          writeToFile:[NSString stringWithFormat:@"build/activity-row-control-%@-%@.png", theme, highlighted] atomically:YES];
        NSColor *foreground = [rep colorAtX:rep.pixelsWide-6 y:rep.pixelsHigh/2];
        NSColor *surface = [rep colorAtX:rep.pixelsWide-2 y:rep.pixelsHigh/2];
        if (button.title.length) Check(PixelsNear(rep, foreground) > (NSUInteger)rep.pixelsHigh * 4 + 5,
          @"rendered disclosure text keeps its foreground in normal and pressed states");
        else Check(SymbolInk(rep, foreground, surface) > 3,
          @"rendered row disclosure remains readable against its paired surface in both themes");
        if (!highlighted.boolValue) Check(PixelsNear(rep, surface) > (NSUInteger)rep.pixelsHigh * 4 + 40,
          @"rendered disclosure uses its paired surface in both themes");
      }
      button.cell.highlighted = NO;
    }
    NSScrollView *scroll = Output(view);
    NSTextView *output = (id)scroll.documentView;
    output.selectedRange = NSMakeRange(0, 10);
    NSMutableArray *updated = [Activities() mutableCopy];
    NSMutableDictionary *process = [updated[0] mutableCopy];
    process[@"output"] = [process[@"output"] stringByAppendingString:@"All checks passed.\n"];
    process[@"state"] = @"completed"; updated[0] = process;
    view.activities = updated;
    Check(Output(view) == scroll && NSEqualRanges(output.selectedRange, NSMakeRange(0,10)), @"new output keeps the existing selectable log view");
    Check([button.title containsString:@"1 running"], @"process completion updates the running count");
    view.statusText = @"Activity disconnected. Send a message to reconnect.";
    Check([[(NSTextField *)[view valueForKey:@"preview"] stringValue] containsString:@"disconnected"], @"transport errors remain visible");

    TLChatTabController *chat = [TLChatTabController new];
    TLChatRecord *record = [TLChatRecord new]; record.chatID = 1; record.hermesSessionID = @"one";
    chat.chat = record;
    chat.messages = [@[[TLChatMessage messageWithRole:TLRoleAssistant content:@"Started a background task." thinking:nil]] mutableCopy];
    NSWindow *chatWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,600)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    chatWindow.releasedWhenClosed = NO;
    chatWindow.contentView = [chat buildChatWorkspace];
    chat.messageInputWidthConstraint.constant = 560;
    [chatWindow orderFront:nil];
    TLToolStatusPill *pill = [chat valueForKey:@"toolStatusPill"];
    __block void (^pending)(NSDictionary *, NSError *);
    __block NSUInteger calls = 0;
    chat.activityProvider = ^(void (^completion)(NSDictionary *, NSError *)) { calls++; pending = [completion copy]; };
    [chat refreshRuntimeActivity]; [chat refreshRuntimeActivity];
    Check(calls == 1, @"only one activity request may be in flight");
    pending(@{@"available":@YES, @"activities":Activities()}, nil); Pump();
    Check(chat.runtimeActivities.count == 3, @"activity arrives after the parent reply with no active turn runner");
    [chat renderMessagesScrollingToBottom:NO]; [chatWindow.contentView layoutSubtreeIfNeeded];
    Check(!pill.hidden && [pill.accessibilityLabel containsString:@"2 running"], @"background work stays in the composer pill after the parent reply");
    Check([[chat valueForKey:@"runtimeActivityView"] superview] == nil, @"background activity does not add a transcript panel");
    Check([pill accessibilityPerformPress], @"activity details are accessible from the pill"); Pump();
    NSPopover *popover = [chat valueForKey:@"activityPopover"];
    Check(popover.shown && !Output([chat valueForKey:@"runtimeActivityView"]), @"pill opens compact activity rows without expanding terminal logs");
    popover.animates = NO;
    [popover close];
    for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      [chat applyPalette:[TLThemePalette paletteForPreference:theme.integerValue]];
      chatWindow.appearance = [NSAppearance appearanceNamed:chat.palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
      for (NSNumber *width in @[@200, @640]) {
        [chatWindow setContentSize:NSMakeSize(width.doubleValue,600)];
        chat.messageInputWidthConstraint.constant = width.doubleValue - 40;
        [chat renderMessagesScrollingToBottom:NO]; [chatWindow.contentView layoutSubtreeIfNeeded]; Pump();
        NSRect frame = [pill convertRect:pill.bounds toView:chatWindow.contentView];
        Check(!NSIsEmptyRect(frame) && NSContainsRect(chatWindow.contentView.bounds, frame), [NSString stringWithFormat:@"activity is visible inside narrow and wide chat windows: pill %@, workspace %@", NSStringFromRect(frame), NSStringFromRect(chatWindow.contentView.bounds)]);
        NSBitmapImageRep *rep = [chatWindow.contentView bitmapImageRepForCachingDisplayInRect:chatWindow.contentView.bounds];
        [chatWindow.contentView cacheDisplayInRect:chatWindow.contentView.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
          writeToFile:[NSString stringWithFormat:@"build/activity-pill-%@-%@.png", chat.palette.dark ? @"dark" : @"light", width] atomically:YES];
        [pill accessibilityPerformPress]; Pump();
        NSView *popoverView = [(NSPopover *)[chat valueForKey:@"activityPopover"] contentViewController].view;
        [popoverView layoutSubtreeIfNeeded];
        Check(NSWidth(popoverView.bounds) <= MAX(160, width.doubleValue - 40), [NSString stringWithFormat:@"activity popover respects the requested width: %@ for %@", NSStringFromRect(popoverView.bounds), width]);
        TLRuntimeActivityView *activityPanel = [chat valueForKey:@"runtimeActivityView"];
        if (!Output(activityPanel)) {
          for (NSStackView *card in [(NSStackView *)[activityPanel valueForKey:@"details"] arrangedSubviews]) {
            NSStackView *header = card.arrangedSubviews.firstObject;
            NSButton *toggle = (id)header.arrangedSubviews.lastObject;
            if ([toggle.identifier isEqual:@"process:1"]) { [toggle performClick:nil]; break; }
          }
          [popoverView layoutSubtreeIfNeeded];
        }
        NSScrollView *terminal = Output([chat valueForKey:@"runtimeActivityView"]);
        Check(NSWidth(terminal.frame) > 0 && NSWidth(terminal.frame) <= NSWidth(popoverView.bounds), @"terminal details fit the activity popover");
        rep = [popoverView bitmapImageRepForCachingDisplayInRect:popoverView.bounds];
        [popoverView cacheDisplayInRect:popoverView.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
          writeToFile:[NSString stringWithFormat:@"build/activity-details-%@-%@.png", chat.palette.dark ? @"dark" : @"light", width] atomically:YES];
        ((NSPopover *)[chat valueForKey:@"activityPopover"]).animates = NO;
        [[chat valueForKey:@"activityPopover"] close];
      }
    }
    [chat setValue:@0 forKey:@"nextActivityPoll"]; [chat refreshRuntimeActivity];
    pending(@{@"available":@NO, @"activities":@[]}, nil); Pump();
    Check([chat.runtimeActivities[0][@"state"] isEqual:@"interrupted"], @"a disconnected runtime cannot look like it is still running");
    Check(![pill valueForKey:@"shimmerTimer"] && [pill.accessibilityLabel hasPrefix:@"Activity unavailable"], @"disconnection replaces running text and stops animation");
    [chat setValue:@0 forKey:@"nextActivityPoll"]; [chat refreshRuntimeActivity];
    pending(@{@"available":@YES, @"activities":@[]}, nil); Pump();
    Check(chat.runtimeActivities.count == 0 && [[chat valueForKey:@"runtimeActivityView"] isHidden], @"an empty fresh snapshot clears stale activity");
    Check(pill.hidden, @"empty background state hides the idle pill");
    [chat setValue:@0 forKey:@"nextActivityPoll"]; [chat refreshRuntimeActivity];
    void (^stale)(NSDictionary *, NSError *) = [pending copy];
    TLChatRecord *other = [TLChatRecord new]; other.chatID = 2; other.hermesSessionID = @"two";
    chat.chat = other;
    stale(@{@"available":@YES, @"activities":Activities()}, nil); Pump();
    Check(chat.runtimeActivities.count == 0, @"late results cannot cross into another session");
    __block NSString *answer = nil;
    TLQuestionRequest *question = [[TLQuestionRequest alloc] initWithPresentation:@{@"title":@"Allow background command?", @"options":@[@{@"id":@"deny", @"title":@"Deny"}]} response:^(NSString *choice) { answer = choice; }];
    [chat presentBackgroundQuestion:question];
    Check([chat.messages.lastObject.questions containsObject:question] && question.pending, @"background Mac approval is attached to the owning transcript");
    [chat refreshRuntimeActivity]; [chat close];
    Check([answer isEqual:@"deny"] && !question.pending, @"closing the chat resolves pending background consent");
    pending(@{@"available":@YES, @"activities":Activities()}, nil); Pump();
    Check(chat.runtimeActivities.count == 0 && ![chat valueForKey:@"activityTimer"], @"closing stops polling and ignores in-flight results");
    [chatWindow close];
    [window close];
    NSLog(@"Runtime activity tests passed");
  }
  return 0;
}
