#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "TLNotesTabController.h"
#import "design_system/TLMarkdownEditorView.h"
#import "design_system/TLCollectionEditorView.h"
#import "design_system/TLThemedButton.h"
#import "TLChatControllerTestSupport.h"
#import "WorkspaceTabRuntime.h"

@interface TLNotesTabController (Testing)
- (void)selectNotes:(id)sender;
- (void)selectMemory:(id)sender;
- (void)openNoteID:(NSString *)identity;
- (void)newNote:(id)sender;
- (void)save:(id)sender;
- (void)saveCopy:(id)sender;
- (void)textDidChange:(NSNotification *)notification;
- (void)searchChanged:(id)sender;
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
- (BOOL)activateAgentWithID:(NSInteger)agentID;
@end
@interface TLNotesTestDatabase : NSObject
@property (nonatomic) NSInteger currentAgentID;
@end
@implementation TLNotesTestDatabase
- (BOOL)setCurrentAgentID:(NSInteger)agentID error:(NSError **)error { self.currentAgentID = agentID; return YES; }
- (id)appSettings:(NSError **)error { return nil; }
@end
@interface TLNotesTestOrchestrator : NSObject
@property (nonatomic, copy) TLNotesRequest request;
@end
@implementation TLNotesTestOrchestrator
- (id)listAgents:(NSError **)error { return nil; }
- (void)hermesNotesWithParameters:(NSDictionary *)parameters agentID:(NSInteger)agentID token:(NSString *)token
                           model:(NSString *)model completion:(TLNotesReply)completion {
  self.request(agentID, parameters, completion);
}
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

  TLNotesTestDatabase *database = [TLNotesTestDatabase new];
  TLNotesTestOrchestrator *orchestrator = [TLNotesTestOrchestrator new];
  [owner setValue:database forKey:@"database"]; [owner setValue:orchestrator forKey:@"agentOrchestrator"];
  NSMutableDictionary *storage = [NSMutableDictionary dictionary];
  __block TLNotesReply pending;
  __block NSDictionary *pendingParameters;
  __block NSInteger pendingAgent = 0;
  __block BOOL deferSave = YES;
  orchestrator.request = ^(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply) {
    NSMutableDictionary *notebook = storage[@(agentID)];
    if (!notebook) { notebook = [NSMutableDictionary dictionary]; storage[@(agentID)] = notebook; }
    NSString *action = parameters[@"action"], *identity = parameters[@"id"];
    if (deferSave && [action isEqual:@"save"]) {
      pending = reply; pendingParameters = parameters; pendingAgent = agentID; return;
    }
    if ([action isEqual:@"list"]) reply(@{@"notes":notebook.allValues}, nil);
    else if ([action isEqual:@"create"] || [action isEqual:@"save"]) {
      notebook[identity] = Note(identity, parameters[@"content"], NSUUID.UUID.UUIDString);
      reply(@{@"note":notebook[identity]}, nil);
    } else if ([action isEqual:@"read"]) reply(@{@"note":notebook[identity]}, nil);
  };
  NSButton *agentControl = [NSButton new]; agentControl.tag = 17;
  [owner activateAgentWithID:agentControl.tag]; Drain(0.05);
  TLNotesTabController *first = (id)runtime.featureController;
  Check([[first valueForKey:@"agentID"] integerValue] == 17, @"Notes follows the app's selected agent");
  for (NSView *view in [(TLCollectionEditorView *)first.view header].subviews)
    Check(![view isKindOfClass:NSPopUpButton.class], @"Notes does not offer a separate agent picker");
  [first newNote:nil]; Drain(0.05);
  TLMarkdownEditorView *firstEditor = [first valueForKey:@"textView"];
  firstEditor.string = @"# First agent's draft"; [first textDidChange:nil]; [first save:nil]; Drain(0.05);
  Check(pending && pendingAgent == 17 && [pendingParameters[@"content"] isEqual:firstEditor.string], @"pending saves target the original agent");
  agentControl.tag = 23; [owner activateAgentWithID:agentControl.tag]; Drain(0.05);
  TLNotesTabController *second = (id)runtime.featureController;
  Check(second != first && [[second valueForKey:@"agentID"] integerValue] == 23 && !first.closed &&
    [owner runtimeForTab:tab] == runtime && state.snapshot.workspaceTabs.count == 2,
    @"app agent switching changes the notebook immediately while reusing the Notes tab");
  [second newNote:nil]; Drain(0.05);
  TLMarkdownEditorView *secondEditor = [second valueForKey:@"textView"];
  NSString *secondContent = [secondEditor.string copy];
  pending(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"VM disconnected"}]);
  pending = nil; Drain(0.05);
  Check([[first valueForKey:@"dirty"] boolValue] && [secondEditor.string isEqual:secondContent], @"a late failure preserves its original draft without touching the new notebook");
  agentControl.tag = 17; [owner activateAgentWithID:agentControl.tag]; Drain(0.05);
  Check(runtime.featureController == first && [firstEditor.string isEqual:@"# First agent's draft"], @"switching back restores an unsaved draft");
  [first save:nil]; Drain(0.05);
  agentControl.tag = 23; [owner activateAgentWithID:agentControl.tag]; Drain(0.05);
  NSString *identity = pendingParameters[@"id"];
  storage[@17][identity] = Note(identity, pendingParameters[@"content"], @"saved-revision");
  deferSave = NO; pending(@{@"note":storage[@17][identity]}, nil); pending = nil; Drain(0.05);
  Check(![[first valueForKey:@"dirty"] boolValue] && [secondEditor.string isEqual:secondContent] &&
    [storage[@17] count] == 1 && [storage[@23] count] == 1, @"a late save completes in its original VM after the app agent changes");
  [owner closeNotesTab:nil];
  Check(first.closed && second.closed, @"closing Notes closes every cached notebook");
  Check(runtime.featureController.closed && ![state hasWorkspaceTabWithKind:TLWorkspaceTabKindNotes tabID:0], @"closing Notes cancels its controller and removes the tab");
  [owner performTabCommand:TLTabCommandReopen];
  TLWorkspaceTab *reopened = [state workspaceTabWithKind:TLWorkspaceTabKindNotes tabID:0];
  Check(reopened && [owner runtimeForTab:reopened] != runtime, @"reopen restores a fresh Notes tab");
  [owner closeNotesTab:nil];
}


static NSDictionary *MemoryNote(NSString *identity, NSString *content, NSString *revision) {
  NSMutableDictionary *note = [Note(identity, content, revision) mutableCopy];
  note[@"title"] = [identity isEqual:@"MEMORY.md"] ? @"Learned facts" : @"About you";
  note[@"preview"] = content;
  note[@"path"] = [@"/workspace/.hermes/memories/" stringByAppendingString:identity];
  return note;
}
static id EditorJS(TLMarkdownEditorView *editor, NSString *script) {
  __block BOOL finished = NO; __block id value = nil; __block NSError *failure = nil;
  WKWebView *web = [editor valueForKey:@"webView"];
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) { value = result; failure = error; finished = YES; }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (!finished && deadline.timeIntervalSinceNow > 0) Drain(0.01);
  Check(finished && !failure, [NSString stringWithFormat:@"editor JavaScript completes: %@; script: %@", failure, script]); return value;
}
static void WaitForEditor(TLMarkdownEditorView *editor) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!editor.ready && deadline.timeIntervalSinceNow > 0) Drain(0.01);
  Check(editor.ready, @"bundled formatted editor loads in WebKit");
}
static void TestWYSIWYGEditor(void) {
  TLMarkdownEditorView *editor = [TLMarkdownEditorView new];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,560)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO; window.contentView = editor;
  editor.editable = YES;
  __block NSUInteger changes = 0; editor.changeHandler = ^{ changes++; };
  NSString *original = @"# A heading\n\nA **bold** word and *italic* word.\n\n- First\n- Second\n";
  editor.string = original; WaitForEditor(editor);
  Check([EditorJS(editor,@"document.querySelector('h1').textContent") isEqual:@"A heading"], @"headings are rendered in the editable surface");
  Check([EditorJS(editor,@"document.querySelector('strong').textContent") isEqual:@"bold"], @"Markdown emphasis renders as formatted text");
  Check([editor finishEditing] && [editor.string isEqual:original] && changes == 0, @"opening and flushing do not normalize or autosave untouched Markdown");
  EditorJS(editor,@"document.querySelector('.tiptap').focus(); document.execCommand('selectAll'); document.execCommand('insertText', false, 'Typed in the formatted editor');");
  Check([editor finishEditing] && [editor.string containsString:@"Typed in the formatted editor"] && changes > 0, @"actual WebKit typing reaches the native Markdown draft before saving");
  EditorJS(editor,@"document.execCommand('selectAll');"); Drain(0.05);
  EditorJS(editor,@"TalariaNotes.command('bold');");
  Check([editor finishEditing] && [editor.string containsString:@"**Typed in the formatted editor**"], [NSString stringWithFormat:@"formatting commands serialize to Markdown: %@",editor.string]);
  NSString *draft = [editor.string copy];
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:preference.integerValue];
    editor.palette = palette; Drain(0.2);
    Check([editor finishEditing] && [editor.string isEqual:draft], @"theme changes preserve editor content and history");
    NSString *surface = EditorJS(editor,@"getComputedStyle(document.body).backgroundColor");
    NSColor *rgb = [palette.controlSurface colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    NSArray *channels = EditorJS(editor,@"getComputedStyle(document.body).backgroundColor.match(/[0-9.]+/g).map(Number)");
    Check(channels.count >= 3 && fabs([channels[0] doubleValue]-lround(rgb.redComponent*255)) < 1 &&
      fabs([channels[1] doubleValue]-lround(rgb.greenComponent*255)) < 1 && fabs([channels[2] doubleValue]-lround(rgb.blueComponent*255)) < 1 &&
      fabs((channels.count == 4 ? [channels[3] doubleValue] : 1)-rgb.alphaComponent) < 0.01,
      [NSString stringWithFormat:@"WebKit receives the active theme surface: %@ vs %@", surface,rgb]);
    TLThemedButton *button = [[editor valueForKey:@"formatButtons"] firstObject];
    for (NSNumber *state in @[@0,@1,@2,@3]) {
      button.enabled = state.integerValue != 3; button.cell.highlighted = state.integerValue == 2;
      [button setValue:@(state.integerValue == 1) forKey:@"hovered"];
      NSColor *background = button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface;
      NSColor *foreground = button.primary ? palette.primaryActionText : palette.secondaryActionText;
      if (state.integerValue == 1 || state.integerValue == 2) background = Blend(background,palette.chromeHoverSurface,1);
      if (!button.enabled) { background = Blend(palette.tabBackground,background,palette.disabledOpacity); foreground = Blend(background,foreground,palette.disabledOpacity); }
      NSBitmapImageRep *bitmap = RenderButton(button);
      Check(ContainsColor(bitmap,background) && ContainsColor(bitmap,foreground), @"formatting buttons render matching semantic colors in every state");
    }
    button.cell.highlighted = NO; button.enabled = YES; [button setValue:@NO forKey:@"hovered"];
    __block BOOL captured = NO;
    [(WKWebView *)[editor valueForKey:@"webView"] takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
      Check(image && !error, @"WebKit renders the formatted editor snapshot");
      NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:
        [NSString stringWithFormat:@"/tmp/talaria-formatted-note-%@.png",palette.dark ? @"dark" : @"light"] atomically:YES]; captured = YES;
    }];
    NSDate *captureDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!captured && captureDeadline.timeIntervalSinceNow > 0) Drain(0.01);
    Check(captured, @"formatted editor snapshot finishes");
  }
  editor.string = @"<!-- keep this -->\n\nText"; WaitForEditor(editor);
  Check([[editor valueForKey:@"sourceMode"] boolValue] && [editor.string hasPrefix:@"<!-- keep this -->"], @"unsupported embedded markup stays intact in source view");
  editor.string = @"# New document"; WaitForEditor(editor);
  Check(![[editor valueForKey:@"sourceMode"] boolValue], @"ordinary notes open in formatted mode after a source-only document");
  // A stale message from another note cannot replace this document.
  NSUInteger epoch = [[editor valueForKey:@"epoch"] unsignedIntegerValue];
  EditorJS(editor,[NSString stringWithFormat:@"webkit.messageHandlers.notesEditor.postMessage({type:'change',epoch:%lu,sequence:999,markdown:'old draft'}); null",(unsigned long)(epoch-1)]);
  Drain(0.05); Check([editor.string isEqual:@"# New document"], @"late editor events cannot cross note boundaries");
  [window setContentSize:NSMakeSize(200,560)]; [editor layoutSubtreeIfNeeded];
  NSView *toolbar = [editor valueForKey:@"toolbarScroll"], *mode = [editor valueForKey:@"modeButton"];
  Check(!NSIntersectsRect(toolbar.frame,mode.frame) && NSMaxX(mode.frame) <= 200, @"formatting toolbar scrolls inside narrow windows");
  NSScrollView *scroll = (id)toolbar;
  Check(scroll.contentSize.height >= editor.palette.settingsActionHeight, @"scrollbar space cannot clip formatting buttons");
  [editor close]; [window close];
}
static void TestMemoryEditor(void) {
  NSMutableDictionary *notes = [NSMutableDictionary dictionary];
  NSMutableDictionary *memories = [@{@"MEMORY.md":MemoryNote(@"MEMORY.md", @"Uses Python.", @"memory-v1"),
    @"USER.md":MemoryNote(@"USER.md", @"Lives in Brisbane.", @"user-v1")} mutableCopy];
  __block TLNotesReply pending;
  __block NSDictionary *pendingParameters;
  __block BOOL deferSave = NO, conflict = NO;
  __block NSMutableArray *requests = [NSMutableArray array];
  TLNotesTabController *controller = [[TLNotesTabController alloc] initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]
    agentID:17 request:^(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply) {
      [requests addObject:parameters];
      NSMutableDictionary *store = [parameters[@"collection"] isEqual:@"memory"] ? memories : notes;
      NSString *action = parameters[@"action"], *identity = parameters[@"id"];
      if ([action isEqual:@"list"]) {
        NSArray *items = store == memories ? @[memories[@"MEMORY.md"], memories[@"USER.md"]] : notes.allValues;
        reply(@{@"notes":items}, nil);
      } else if ([action isEqual:@"read"]) reply(@{@"note":store[identity]}, nil);
      else if ([action isEqual:@"save"] || [action isEqual:@"create"]) {
        if (deferSave) { pending = reply; pendingParameters = parameters; return; }
        if (conflict && store == memories) { reply(@{@"conflict":@YES, @"message":@"Memory changed outside this editor."}, nil); return; }
        store[identity] = store == memories ? MemoryNote(identity, parameters[@"content"], NSUUID.UUID.UUIDString) : Note(identity, parameters[@"content"], NSUUID.UUID.UUIDString);
        reply(@{@"note":store[identity]}, nil);
      }
    }];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO; window.contentView = controller.view;
  [controller.view layoutSubtreeIfNeeded];
  [controller selectMemory:nil]; Drain(0.05);
  TLMarkdownEditorView *editor = [controller valueForKey:@"textView"];
  Check([[controller valueForKey:@"memoryCollection"] boolValue] && [editor.string isEqual:@"Uses Python."], @"Memory opens the real learned facts collection");
  Check([(NSView *)[controller valueForKey:@"createButton"] isHidden] &&
    [[(NSButton *)[controller valueForKey:@"deleteButton"] title] isEqual:@"Clear"], @"fixed memory files offer clearing rather than creating or deleting files");
  [controller openNoteID:@"USER.md"]; Drain(0.05);
  editor.string = @"Prefers concise answers."; [controller textDidChange:nil]; Drain(0.75);
  Check([memories[@"USER.md"][@"content"] isEqual:editor.string] && notes.count == 0, @"profile autosaves to Hermes memory, not ordinary notes");
  Check([[(NSTextField *)[controller valueForKey:@"status"] stringValue] containsString:@"New chats"], @"memory explains when edited facts take effect");
  deferSave = YES; editor.string = @"Profile draft before switching"; [controller textDidChange:nil];
  [controller selectNotes:nil]; Drain(0.05);
  Check(pending && [[controller valueForKey:@"memoryCollection"] boolValue] && [pendingParameters[@"collection"] isEqual:@"memory"], @"switching tabs waits for the memory draft to save");
  memories[@"USER.md"] = MemoryNote(@"USER.md", pendingParameters[@"content"], @"user-v2");
  deferSave = NO; pending(@{@"note":memories[@"USER.md"]}, nil); pending = nil; Drain(0.05);
  Check(![[controller valueForKey:@"memoryCollection"] boolValue] && ![[controller valueForKey:@"dirty"] boolValue], @"successful save completes the tab switch");
  [controller newNote:nil]; Drain(0.05);
  Check(notes.count == 1 && memories.count == 2, @"ordinary notes remain separate");
  [controller selectMemory:nil]; Drain(0.05);
  conflict = YES; editor.string = @"Keep my memory draft"; [controller textDidChange:nil]; [controller selectNotes:nil]; Drain(0.05);
  Check([[controller valueForKey:@"memoryCollection"] boolValue] && [[controller valueForKey:@"dirty"] boolValue] &&
    [editor.string isEqual:@"Keep my memory draft"], @"a conflicting memory save prevents switching and preserves the draft");
  [controller saveCopy:nil]; Drain(0.05);
  Check(notes.count == 2 && ![[controller valueForKey:@"memoryCollection"] boolValue] &&
    [editor.string isEqual:@"Keep my memory draft"] && [memories[@"MEMORY.md"][@"content"] isEqual:@"Uses Python."],
    @"Save copy preserves a conflicted memory draft as a regular note without overwriting the agent");
  conflict = NO; [controller selectMemory:nil]; Drain(0.05);
  editor.string = @""; [controller textDidChange:nil]; [controller save:nil]; Drain(0.05);
  Check([memories[@"MEMORY.md"][@"content"] isEqual:@""], @"removing all text saves an empty memory");
  memories[@"MEMORY.md"] = MemoryNote(@"MEMORY.md", @"New fact learned by the agent.", @"memory-v3");
  [controller refresh:nil]; Drain(0.05);
  Check([editor.string isEqual:@"New fact learned by the agent."], @"memory refresh discovers new learning");
  memories[@"USER.md"] = MemoryNote(@"USER.md", [@"A long profile detail. " stringByPaddingToLength:200 withString:@"More saved preferences. " startingAtIndex:0], @"user-v4");
  [controller refresh:nil]; Drain(0.05);
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:preference.integerValue];
    [controller applyPalette:palette]; WaitForEditor(editor); Drain(0.2);
    for (NSNumber *width in @[@200, @960]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 720)]; [controller.view layoutSubtreeIfNeeded]; Drain(0.2);
      TLThemedButton *notesTab = [controller valueForKey:@"notesTabButton"], *memoryTab = [controller valueForKey:@"memoryTabButton"];
      Check(NSMaxX(memoryTab.frame) <= width.doubleValue && !NSIntersectsRect(notesTab.frame, memoryTab.frame), @"internal tabs fit at the minimum window width");
      NSTableView *memoryTable = [controller valueForKey:@"table"];
      if (![(TLCollectionEditorView *)controller.view collection].hidden) {
        NSTableCellView *profileCell = [memoryTable viewAtColumn:0 row:1 makeIfNecessary:YES];
        [profileCell layoutSubtreeIfNeeded];
        Check(NSHeight(profileCell.textField.frame) <= memoryTable.rowHeight && NSMinY(profileCell.textField.frame) >= 0,
          @"long memory previews remain inside their rows");
      }
      NSView *back = [controller valueForKey:@"backButton"], *clear = [controller valueForKey:@"deleteButton"];
      Check(back.hidden || !NSIntersectsRect(back.frame, clear.frame), @"memory navigation and clear actions do not overlap in narrow windows");
      for (TLThemedButton *button in @[notesTab, memoryTab]) {
        for (NSNumber *state in @[@0, @1, @2, @3]) {
          button.enabled = state.integerValue != 3; button.cell.highlighted = state.integerValue == 2;
          [button setValue:@(state.integerValue == 1) forKey:@"hovered"];
          NSColor *surface = button.primary ? palette.primaryActionSurface : palette.secondaryActionSurface;
          NSColor *text = button.primary ? palette.primaryActionText : palette.secondaryActionText;
          if (state.integerValue == 1 || state.integerValue == 2) surface = Blend(surface, palette.chromeHoverSurface, 1);
          if (!button.enabled) { surface = Blend(palette.tabBackground, surface, palette.disabledOpacity); text = Blend(surface, text, palette.disabledOpacity); }
          NSBitmapImageRep *bitmap = RenderButton(button);
          Check(ContainsColor(bitmap, surface) && ContainsColor(bitmap, text), @"memory tabs render paired theme colors in every interaction state");
        }
        button.enabled = YES; button.cell.highlighted = NO; [button setValue:@NO forKey:@"hovered"];
      }
      WaitForEditor(editor); Drain(0.2);
    NSBitmapImageRep *bitmap = [controller.view bitmapImageRepForCachingDisplayInRect:controller.view.bounds];
      [controller.view cacheDisplayInRect:controller.view.bounds toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:
        [NSString stringWithFormat:@"/tmp/talaria-memory-%@-%@.png", palette.dark ? @"dark" : @"light", width] atomically:YES];
    }
  }
  [controller close]; [window close];
}

int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  TestWYSIWYGEditor();
  TestWorkspaceNotes();
  TestMemoryEditor();
  __block NSMutableDictionary *storage = [NSMutableDictionary dictionary];
  __block NSMutableArray *requests = [NSMutableArray array];
  __block TLNotesReply pending;
  __block NSDictionary *pendingParameters;
  __block BOOL deferSave = NO, failSave = NO, conflict = NO, deferList = NO;
  __block NSInteger displayedAgent = 17, revision = 0;
  TLNotesTabController *controller = [[TLNotesTabController alloc] initWithPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]
    agentID:17 request:^(NSInteger agentID, NSDictionary *parameters, TLNotesReply reply) {
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
  TLMarkdownEditorView *editor = [controller valueForKey:@"textView"];
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
    [controller applyPalette:palette]; Drain(0.2); [controller.view layoutSubtreeIfNeeded];
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
    WaitForEditor(editor); Drain(0.2);
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
  NSView *createAction = [controller valueForKey:@"createButton"], *refreshAction = [controller valueForKey:@"refreshButton"];
  Check(!NSIntersectsRect(createAction.frame, refreshAction.frame), @"New and Refresh remain separate in narrow Notes windows");
  [window setContentSize:NSMakeSize(960,720)]; [controller.view layoutSubtreeIfNeeded];
  Check(!surface.collection.hidden && !surface.editor.hidden, @"wide windows restore both panes");

  deferList = YES; [controller refresh:nil]; NSUInteger count = requests.count;
  Check(pending != nil, @"refresh can remain pending");
  [controller close]; pending(@{@"notes":@[]}, nil); Drain(0.05); [controller refresh:nil];
  Check(requests.count == count && controller.closed, @"closed tabs ignore late replies and stop refreshes");
  [window close];
  NSLog(@"Notes tests passed");
} return 0; }
