#import <AppKit/AppKit.h>
#import "TLNotesTabController.h"
#import "design_system/TLCollectionEditorView.h"
#import "design_system/TLThemedButton.h"
#import "TLChatControllerTestSupport.h"
#import "WorkspaceTabRuntime.h"

@interface TLNotesTabController (Testing)
- (void)newNote:(id)sender;
- (void)save:(id)sender;
- (void)saveCopy:(id)sender;
- (void)textDidChange:(NSNotification *)notification;
- (void)searchChanged:(id)sender;
- (void)changeAgent:(id)sender;
- (void)showList:(id)sender;
- (void)revealSelectedNote:(id)sender;
@end

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(NSTimeInterval seconds) {
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  NSUInteger cycles = 0;
  while (end.timeIntervalSinceNow > 0 || cycles++ < 10) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static NSDictionary *Note(NSString *identity, NSString *content, NSString *revision) {
  return @{@"id":identity, @"content":[content copy], @"revision":revision, @"title":@"Project ideas", @"preview":@"An idea worth keeping.",
    @"path":[@"/workspace/notes/" stringByAppendingString:identity], @"modified_at":@100};
}
static NSBitmapImageRep *RenderButton(TLThemedButton *button) {
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:ceil(NSWidth(button.bounds))
    pixelsHigh:ceil(NSHeight(button.bounds)) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  [button.palette.tabBackground setFill]; NSRectFill(button.bounds);
  [button.cell drawWithFrame:button.bounds inView:button];
  [NSGraphicsContext restoreGraphicsState]; return bitmap;
}
static NSColor *Blend(NSColor *base, NSColor *overlay, CGFloat fraction) {
  base = [base colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  overlay = [overlay colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  CGFloat alpha = overlay.alphaComponent * fraction;
  return [NSColor colorWithDeviceRed:base.redComponent * (1-alpha) + overlay.redComponent * alpha
    green:base.greenComponent * (1-alpha) + overlay.greenComponent * alpha blue:base.blueComponent * (1-alpha) + overlay.blueComponent * alpha alpha:1];
}
static BOOL ContainsColor(NSBitmapImageRep *image, NSColor *color) {
  NSColor *expected = [color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  NSUInteger count = 0;
  for (NSInteger y = 0; y < image.pixelsHigh; y++) for (NSInteger x = 0; x < image.pixelsWide; x++) {
    NSColor *actual = [[image colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    if (fabs(actual.redComponent - expected.redComponent) < 0.045 && fabs(actual.greenComponent - expected.greenComponent) < 0.045 &&
        fabs(actual.blueComponent - expected.blueComponent) < 0.045 && ++count > 5) return YES;
  }
  return NO;
}

@interface TalariaWindowController (NotesTests)
- (void)showNotes:(id)sender;
- (void)closeNotesTab:(id)sender;
- (NSStackView *)buildSidebarActionStack;
- (TLWorkspaceTabRuntime *)runtimeForTab:(TLWorkspaceTab *)tab;
- (void)hydrateWorkspaceTabsFromAppState;
@end
@interface TLNotesTestOwner : TalariaWindowController
@end
@implementation TLNotesTestOwner
- (void)reloadWorkspaceTabs {}
- (void)renderWorkspaceTabs {}
- (void)updateWorkspaceMode {}
- (void)updateControlStatesForChat:(TLChatTabController *)chatContext {}
@end
static void TestWorkspaceNotes(void) {
  TLAppStateManager *state = [TLAppStateManager new];
  [state addWorkspaceTab:[TLWorkspaceTab tabWithKind:TLWorkspaceTabKindHistory tabID:0 title:@"History" toolTip:nil URL:nil closeable:YES] activate:YES];
  TLNotesTestOwner *owner = [[TLNotesTestOwner alloc] initWithWindow:nil];
  [owner setValue:state forKey:@"appStateManager"];
  [owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  NSStackView *actions = [owner buildSidebarActionStack];
  Check(actions.arrangedSubviews.count == 3 && [[(id)actions.arrangedSubviews[0] title] isEqual:@"Notes"] &&
    [[(id)actions.arrangedSubviews[1] title] isEqual:@"Automations"], @"Notes appears immediately above Automations");
  NSUInteger windowCount = NSApp.windows.count;
  [owner showNotes:nil];
  TLWorkspaceTab *tab = [state workspaceTabWithKind:TLWorkspaceTabKindNotes tabID:0];
  TLWorkspaceTabRuntime *runtime = [owner runtimeForTab:tab];
  Check(tab && state.snapshot.activeTabKind == TLWorkspaceTabKindNotes && [runtime.featureController isKindOfClass:TLNotesTabController.class],
    @"Notes opens as a feature tab");
  Check(NSApp.windows.count == windowCount, @"Notes uses the existing desktop window");
  [owner showNotes:nil]; [owner hydrateWorkspaceTabsFromAppState];
  Check(state.snapshot.workspaceTabs.count == 2 && [owner runtimeForTab:tab] == runtime, @"opening Notes again reuses its tab and controller");
  [owner closeNotesTab:nil];
  Check(runtime.featureController.closed && ![state hasWorkspaceTabWithKind:TLWorkspaceTabKindNotes tabID:0], @"closing Notes cancels its controller and removes the tab");
  [owner performTabCommand:TLTabCommandReopen];
  TLWorkspaceTab *reopened = [state workspaceTabWithKind:TLWorkspaceTabKindNotes tabID:0];
  Check(reopened && [owner runtimeForTab:reopened] != runtime, @"reopen restores a fresh Notes tab");
  [owner closeNotesTab:nil];
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TestWorkspaceNotes();
  TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 17; agent.name = @"Personal agent";
  TLAgentRecord *other = [TLAgentRecord new]; other.agentID = 23; other.name = @"Work agent";
  __block NSMutableDictionary *storage = [NSMutableDictionary dictionary];
  __block NSMutableArray *requests = [NSMutableArray array];
  __block TLNotesReply pending;
  __block NSDictionary *pendingParameters;
  __block BOOL deferSave = NO, failSave = NO, conflict = NO, deferList = NO;
  __block NSInteger displayedAgent = 17, revision = 0;
  TLNotesTabController *controller = [[TLNotesTabController alloc] initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]
    agents:@[agent,other] agentID:17 request:^(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply) {
      Check(agentID == displayedAgent, @"each operation uses the displayed VM");
      [requests addObject:parameters];
      NSString *action = parameters[@"action"], *identity = parameters[@"id"];
      if ((deferSave && [action isEqual:@"save"]) || (deferList && [action isEqual:@"list"])) {
        pending = reply; pendingParameters = parameters; return;
      }
      if (failSave && [action isEqual:@"save"]) { reply(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"VM disconnected"}]); return; }
      if (conflict && [action isEqual:@"save"]) { reply(@{@"conflict":@YES, @"message":@"The agent changed this note."}, nil); return; }
      if ([action isEqual:@"create"] || [action isEqual:@"save"]) {
        storage[identity] = Note(identity, parameters[@"content"], [NSString stringWithFormat:@"%064ld", (long)++revision]);
        reply(@{@"note":storage[identity]}, nil);
      } else if ([action isEqual:@"list"]) reply(@{@"notes":storage.allValues, @"skipped":@[]}, nil);
      else if ([action isEqual:@"read"]) reply(@{@"note":storage[identity]}, nil);
    }];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO; window.contentView = controller.view;
  [controller refresh:nil]; Drain(0.05);
  Check([[controller valueForKey:@"notes"] count] == 0, @"empty VM has an empty collection");
  [controller newNote:nil]; Drain(0.05);
  NSTextView *editor = [controller valueForKey:@"textView"];
  NSTableView *table = [controller valueForKey:@"table"];
  NSDictionary *note = [controller valueForKey:@"note"];
  NSString *identity = note[@"id"];
  Check(storage.count == 1 && [identity hasSuffix:@".md"] && [editor.string isEqual:@"# Untitled note\n\n"], @"new note is saved to the VM before editing");
  Check(table.numberOfRows == 1, [NSString stringWithFormat:@"new note appears in the collection (rows=%ld, notes=%@, requests=%@)", (long)table.numberOfRows, [controller valueForKey:@"notes"], requests]);

  editor.string = @"# Project ideas\n\nAn idea worth keeping.\n\n- Sketch a small prototype\n- Share it with the agent\n";
  [controller textDidChange:nil]; Drain(0.75);
  Check([storage[identity][@"content"] isEqual:editor.string] && ![[controller valueForKey:@"dirty"] boolValue], @"typing autosaves Markdown");
  Check([controller prepareToClose], @"saved notes can close without prompting");
  deferSave = YES;
  editor.string = @"# Draft one"; [controller textDidChange:nil]; [controller save:nil]; Drain(0.05);
  Check(pending != nil && editor.editable, [NSString stringWithFormat:@"editor remains writable during a save (pending=%d editable=%d busy=%@ saving=%@ dirty=%@)", pending != nil, editor.editable, [controller valueForKey:@"busy"], [controller valueForKey:@"saving"], [controller valueForKey:@"dirty"]]);
  editor.string = @"# Draft two"; [controller textDidChange:nil];
  storage[identity] = Note(identity, pendingParameters[@"content"], @"revision-two");
  TLNotesReply finish = pending; pending = nil; deferSave = NO;
  finish(@{@"note":storage[identity]}, nil); Drain(0.75);
  Check([storage[identity][@"content"] isEqual:@"# Draft two"] && ![[controller valueForKey:@"dirty"] boolValue], @"late save responses cannot replace newer typing");

  conflict = YES;
  editor.string = @"# User draft"; [controller textDidChange:nil]; [controller save:nil]; Drain(0.05);
  Check([[controller valueForKey:@"dirty"] boolValue] && [editor.string isEqual:@"# User draft"], @"agent conflicts retain the local draft");
  Check(![(NSView *)[controller valueForKey:@"duplicateButton"] isHidden], @"conflicts offer Save copy");
  conflict = NO; [controller saveCopy:nil]; Drain(0.05);
  Check(storage.count == 2 && [editor.string isEqual:@"# User draft"] && ![[controller valueForKey:@"dirty"] boolValue], @"Save copy keeps both versions");
  identity = [controller valueForKey:@"note"][@"id"];

  failSave = YES;
  editor.string = @"# Offline draft"; [controller textDidChange:nil]; [controller save:nil]; Drain(0.05);
  Check([[controller valueForKey:@"dirty"] boolValue] && [editor.string isEqual:@"# Offline draft"], @"VM failures preserve unsaved text");
  failSave = NO; [controller save:nil]; Drain(0.05);
  Check([storage[identity][@"content"] isEqual:editor.string], @"failed saves can be retried");

  storage[identity] = Note(identity, @"# Agent update\n\nWritten directly to Markdown.", @"agent-revision");
  [controller refresh:nil]; Drain(0.05);
  Check([editor.string hasPrefix:@"# Agent update"], @"refresh incorporates the agent's edits when the draft is clean");
  NSSearchField *search = [controller valueForKey:@"search"];
  search.stringValue = @"search entire body"; [controller searchChanged:nil]; Drain(0.05);
  Check([requests.lastObject[@"query"] isEqual:search.stringValue], @"search is executed against full files in the VM");
  search.stringValue = @"";

  for (NSNumber *preference in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:preference.integerValue];
    editor.string = @"# Project ideas\n\nAn idea worth keeping.\n\n- Sketch a small prototype\n- Share it with the agent\n";
    editor.string = [editor.string stringByAppendingFormat:@"\nTheme draft %@", preference];
    [controller textDidChange:nil];
    [controller applyPalette:palette]; [controller.view layoutSubtreeIfNeeded];
    Check([editor.string hasPrefix:@"# Project ideas"] && [[controller valueForKey:@"dirty"] boolValue], @"changing themes preserves drafts");
    TLThemedButton *button = [controller valueForKey:@"createButton"];
    for (NSNumber *primary in @[@YES, @NO]) for (NSNumber *state in @[@0,@1,@2,@3]) {
      button.primary = primary.boolValue; button.enabled = state.integerValue != 3;
      [button setValue:@(state.integerValue == 1) forKey:@"hovered"];
      button.cell.highlighted = state.integerValue == 2;
      NSColor *surface = button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface;
      NSColor *text = button.primary ? palette.primaryActionText : palette.secondaryActionText;
      if (state.integerValue == 1 || state.integerValue == 2) surface = Blend(surface, palette.chromeHoverSurface, 1);
      if (!button.enabled) { surface = Blend(palette.tabBackground, surface, palette.disabledOpacity); text = Blend(surface, text, palette.disabledOpacity); }
      NSBitmapImageRep *bitmap = RenderButton(button);
      Check(ContainsColor(bitmap, surface) && ContainsColor(bitmap, text), @"notes buttons render paired theme colors in normal, hover, pressed and disabled states");
    }
    button.primary = YES; button.enabled = YES; button.cell.highlighted = NO; [button setValue:@NO forKey:@"hovered"];
    NSBitmapImageRep *bitmap = [controller.view bitmapImageRepForCachingDisplayInRect:controller.view.bounds];
    [controller.view cacheDisplayInRect:controller.view.bounds toBitmapImageRep:bitmap];
    NSString *path = [NSString stringWithFormat:@"/tmp/talaria-notes-%@.png", preference.integerValue == TLThemePreferenceDark ? @"dark" : @"light"];
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    [controller save:nil]; Drain(0.05);
  }
  [window setContentSize:NSMakeSize(200,720)]; [controller.view layoutSubtreeIfNeeded];
  TLCollectionEditorView *surface = (id)controller.view;
  Check(NSWidth(controller.view.bounds) == 200 && surface.compact && surface.collection.hidden && !surface.editor.hidden,
    @"narrow windows show a full-width editor without raising the minimum width");
  [controller showList:nil]; [controller.view layoutSubtreeIfNeeded];
  Check(!surface.collection.hidden && surface.editor.hidden, @"All notes returns to the collection at narrow widths");
  [controller revealSelectedNote:nil]; [controller.view layoutSubtreeIfNeeded];
  Check(surface.collection.hidden && !surface.editor.hidden, @"the already-selected note can reopen after going back to the list");
  [window setContentSize:NSMakeSize(960,720)]; [controller.view layoutSubtreeIfNeeded];
  Check(!surface.collection.hidden && !surface.editor.hidden, @"wide windows restore both panes");

  NSPopUpButton *picker = [controller valueForKey:@"agentPicker"];
  [picker selectItemWithTag:23]; displayedAgent = 23;
  [controller changeAgent:nil]; Drain(0.05);
  Check([[controller valueForKey:@"agentID"] integerValue] == 23 && [controller valueForKey:@"note"] == nil,
    @"switching agents clears the previous VM's editor");
  deferList = YES; [controller refresh:nil]; NSUInteger count = requests.count;
  Check(pending != nil, @"refresh can remain pending");
  [controller close]; pending(@{@"notes":@[]}, nil); Drain(0.05); [controller refresh:nil];
  Check(requests.count == count && controller.closed, @"closed tabs ignore late replies and stop refreshes");
  [window close];
  NSLog(@"Notes tests passed");
} return 0; }
