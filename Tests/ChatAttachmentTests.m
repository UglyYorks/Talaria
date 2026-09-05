#import <AppKit/AppKit.h>
#import "ChatAttachmentStore.h"
#import "Database.h"
#import "SQLiteConnection.h"
#import "PromptMessages.h"
#import "design_system/TLMessageInput.h"
#import "design_system/TLTransitionCoordinator.h"

@interface TLMessageInput (AttachmentPickerTesting)
- (void)completeAttachmentSelection:(NSOpenPanel *)panel response:(NSModalResponse)response;
@end
@interface TLAttachmentTestPanel : NSObject
@property (nonatomic, copy) NSArray<NSURL *> *URLs;
@property (nonatomic) BOOL orderedOut;
@end
@implementation TLAttachmentTestPanel
- (void)orderOut:(id)sender { self.orderedOut = YES; }
@end

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSURL *HostURL(NSURL *workspace, NSDictionary *attachment) {
  return [workspace URLByAppendingPathComponent:[attachment[@"guestPath"] substringFromIndex:@"/workspace/".length]];
}

static void TestAttachmentMigrationCollision(void) {
  NSURL *base = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSURL *URL = [base URLByAppendingPathComponent:@"migration.sqlite"];
  NSError *error = nil;
  TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
  TLChatRecord *chat = [database createChatWithModel:@"test" error:&error];
  [database saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:@"Existing conversation" thinking:nil]
                chatID:chat.chatID error:&error];
  database = nil;
  TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
  // Another worktree used version 5 for agent metadata, without adding message attachments.
  Check([fixture executeSQL:
    "ALTER TABLE messages DROP COLUMN attachments;"
    "DROP INDEX agents_vm_directory;"
    "ALTER TABLE agents DROP COLUMN avatar;"
    "ALTER TABLE agents DROP COLUMN soul;"
    "ALTER TABLE agents DROP COLUMN folder_paths;"
    "ALTER TABLE agents ADD COLUMN avatar TEXT NOT NULL DEFAULT '🤖';"
    "ALTER TABLE agents ADD COLUMN soul TEXT NOT NULL DEFAULT '';"
    "ALTER TABLE agents ADD COLUMN folder_paths TEXT NOT NULL DEFAULT '[]';"
    "INSERT INTO agents(name,guest_kind,runtime,status,vm_directory,soul) VALUES('Existing agent','linux','python','stopped','/tmp/test-agent','Keep this');"
    "PRAGMA user_version = 5;" error:&error], @"creates the conflicting version-5 fixture");
  fixture = nil;
  database = [[TLDatabase alloc] initWithURL:URL error:&error];
  TLChatRecord *loaded = [database chatWithID:chat.chatID error:&error];
  Check(loaded && [loaded.messages.firstObject.content isEqual:@"Existing conversation"],
        [NSString stringWithFormat:@"version-5 collision repairs attachment schema without losing messages: %@", error]);
  Check(loaded.messages.firstObject.attachments.count == 0, @"existing messages default to no attachments");
  TLChatMessage *newMessage = [TLChatMessage messageWithRole:TLRoleUser content:@"New attachment" thinking:nil];
  newMessage.attachments = @[@{@"name":@"report.txt", @"guestPath":@"/workspace/attachments/report.txt", @"directory":@NO}];
  Check([database saveMessage:newMessage chatID:chat.chatID error:&error].attachments.count == 1,
        @"attachment messages can be saved after repairing the schema");
  database = nil;
  fixture = [TLSQLiteConnection openURL:URL error:&error];
  TLSQLiteStatement *soul = [fixture prepareSQL:"SELECT soul FROM agents" error:&error];
  Check([soul step] == SQLITE_ROW && [[soul stringAtColumn:0] isEqual:@"Keep this"], @"unrelated agent metadata stays intact");
  soul = nil;
  Check([fixture executeSQL:"PRAGMA user_version = 4" error:&error], @"prepares a database whose attachment column already exists");
  fixture = nil;
  database = [[TLDatabase alloc] initWithURL:URL error:&error];
  Check(database != nil, @"version-4 upgrade tolerates an existing attachment column");
  database = nil;
  database = [[TLDatabase alloc] initWithURL:URL error:&error];
  Check([database chatWithID:chat.chatID error:&error].messages.lastObject.attachments.count == 1,
        @"repeated migration preserves saved attachment metadata");
  [NSFileManager.defaultManager removeItemAtURL:base error:nil];
}

static void TestProfileSchemaCompatibility(void) {
  NSURL *base = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSURL *URL = [base URLByAppendingPathComponent:@"profiles.sqlite"];
  NSError *error = nil;
  TLDatabase *database = [[TLDatabase alloc] initWithURL:URL error:&error];
  TLChatRecord *chat = [database createChatWithModel:@"test" error:&error];
  [database saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:@"Keep this conversation" thinking:nil]
                chatID:chat.chatID error:&error];
  database = nil;
  TLSQLiteConnection *fixture = [TLSQLiteConnection openURL:URL error:&error];
  Check([fixture executeSQL:
    "DROP INDEX agents_vm_directory;"
    "ALTER TABLE agents DROP COLUMN avatar;"
    "ALTER TABLE agents DROP COLUMN soul;"
    "ALTER TABLE agents DROP COLUMN folder_paths;"
    "ALTER TABLE agents ADD COLUMN avatar TEXT NOT NULL DEFAULT '🤖';"
    "ALTER TABLE agents ADD COLUMN soul TEXT NOT NULL DEFAULT '';"
    "ALTER TABLE agents ADD COLUMN folder_paths TEXT NOT NULL DEFAULT '[]';"
    "CREATE UNIQUE INDEX agents_vm_directory ON agents(vm_directory);"
    "INSERT INTO agents(name,guest_kind,runtime,status,vm_directory,soul) VALUES('Existing agent','linux','python','stopped','/tmp/test-agent','Keep profile');"
    "PRAGMA user_version = 6;" error:&error], @"creates the version-6 agent profile fixture");
  fixture = nil;
  for (NSNumber *withoutAttachments in @[@NO, @YES]) {
    if (withoutAttachments.boolValue) {
      fixture = [TLSQLiteConnection openURL:URL error:&error];
      Check([fixture executeSQL:"ALTER TABLE messages DROP COLUMN attachments; PRAGMA user_version = 6" error:&error], @"prepares profile-only schema");
      fixture = nil;
    }
    database = [[TLDatabase alloc] initWithURL:URL error:&error];
    Check(database != nil, [NSString stringWithFormat:@"opens known version-6 schema: %@", error]);
    TLChatRecord *loaded = [database chatWithID:chat.chatID error:&error];
    Check([loaded.messages.firstObject.content isEqual:@"Keep this conversation"], @"preserves existing version-6 chat history");
    TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleUser content:@"File" thinking:nil];
    message.attachments = @[@{@"name":@"report.txt", @"guestPath":@"/workspace/attachments/report.txt", @"directory":@NO}];
    Check([database saveMessage:message chatID:chat.chatID error:&error].attachments.count == 1, @"saves attachments alongside agent profiles");
    database = nil;
    fixture = [TLSQLiteConnection openURL:URL error:&error];
    TLSQLiteStatement *version = [fixture prepareSQL:"PRAGMA user_version" error:&error];
    Check([version step] == SQLITE_ROW && sqlite3_column_int(version.handle, 0) == 8, @"upgrades profile schema without downgrading its data");
    version = nil;
    TLSQLiteStatement *profile = [fixture prepareSQL:"SELECT soul FROM agents" error:&error];
    Check([profile step] == SQLITE_ROW && [[profile stringAtColumn:0] isEqual:@"Keep profile"], @"preserves agent profile data");
    profile = nil;
    fixture = nil;
  }
  fixture = [TLSQLiteConnection openURL:URL error:&error];
  Check([fixture executeSQL:"PRAGMA user_version = 9" error:&error], @"prepares unknown future schema");
  fixture = nil;
  error = nil;
  Check([[TLDatabase alloc] initWithURL:URL error:&error] == nil && error != nil, @"still rejects unknown future schema versions");
  fixture = [TLSQLiteConnection openURL:URL error:nil];
  Check([fixture executeSQL:"PRAGMA user_version = 6; ALTER TABLE agents ADD COLUMN unsupported TEXT" error:nil], @"prepares unrecognized version-6 shape");
  fixture = nil;
  error = nil;
  Check([[TLDatabase alloc] initWithURL:URL error:&error] == nil && error != nil, @"rejects unrecognized version-6 columns");
  [NSFileManager.defaultManager removeItemAtURL:base error:nil];
}

static void TestStorageAndPersistence(void) {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSURL *base = [[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString] URLByResolvingSymlinksInPath];
  NSURL *workspace = [base URLByAppendingPathComponent:@"workspace"];
  NSURL *folder = [base URLByAppendingPathComponent:@"Project files"];
  [manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
  NSURL *file = [folder URLByAppendingPathComponent:@"résumé \"draft\".txt"];
  [@"original" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
  NSURL *hidden = [folder URLByAppendingPathComponent:@".hidden"];
  [@"hidden content" writeToURL:hidden atomically:YES encoding:NSUTF8StringEncoding error:nil];
  TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
  NSError *error = nil;
  NSArray *attachments = [store copyURLs:@[file, file, folder] sessionID:@"talaria_test" error:&error];
  Check(attachments.count == 3 && !error, [NSString stringWithFormat:@"copies files and folders: %@", error]);
  Check(![attachments[0][@"guestPath"] isEqual:attachments[1][@"guestPath"]], @"duplicate filenames never overwrite each other");
  Check([attachments[2][@"directory"] boolValue], @"folder metadata survives copying");
  Check([manager fileExistsAtPath:[[HostURL(workspace, attachments[2]) URLByAppendingPathComponent:@".hidden"] path]], @"copies hidden folder contents");
  [@"changed" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
  Check([[NSString stringWithContentsOfURL:HostURL(workspace, attachments[0]) encoding:NSUTF8StringEncoding error:nil] isEqual:@"original"], @"original edits cannot change an attachment snapshot");
  NSURL *session = [workspace URLByAppendingPathComponent:@"attachments/talaria_test"];
  NSUInteger batchCount = [manager contentsOfDirectoryAtURL:session includingPropertiesForKeys:nil options:0 error:nil].count;
  error = nil;
  Check(![store copyURLs:@[file, [base URLByAppendingPathComponent:@"missing"]] sessionID:@"talaria_test" error:&error] && error,
        @"a failed batch reports an error");
  Check([manager contentsOfDirectoryAtURL:session includingPropertiesForKeys:nil options:0 error:nil].count == batchCount,
        @"a failed batch leaves no partial copy behind");
  NSURL *link = [folder URLByAppendingPathComponent:@"external-link"];
  [manager createSymbolicLinkAtURL:link withDestinationURL:base error:nil];
  Check(![store copyURLs:@[folder] sessionID:@"talaria_test" error:nil], @"folder symlinks cannot escape the selected tree");
  Check(![store copyURLs:@[base] sessionID:@"talaria_test" error:nil], @"rejects recursive copies of the attachment store");
  Check(![store copyURLs:@[file] sessionID:@"../escape" error:nil], @"rejects session path traversal");
  NSURL *dbURL = [base URLByAppendingPathComponent:@"test.sqlite"];
  TLDatabase *database = [[TLDatabase alloc] initWithURL:dbURL error:&error];
  TLChatRecord *chat = [database createChatWithModel:@"test-model" error:nil];
  TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleUser content:@"Review these" thinking:nil];
  message.attachments = attachments;
  TLStoredChatMessage *saved = [database saveMessage:message chatID:chat.chatID error:nil];
  Check([saved.attachments isEqual:attachments], @"saving a message preserves its attachment metadata");
  database = nil;
  database = [[TLDatabase alloc] initWithURL:dbURL error:nil];
  Check([[[database chatWithID:chat.chatID error:nil].messages.firstObject copy] attachments].count == 3,
        @"attachments survive database reopen and message copies");
  NSString *context = TLBuildAttachmentContext(attachments);
  Check([context containsString:@"reference material"] && [context containsString:@"guestPath"], @"prompt contains reference boundaries and usable VM paths");
  Check([store removeAttachmentsForSessionID:@"talaria_test" error:nil] && ![manager fileExistsAtPath:session.path], @"conversation deletion removes its retained copies");
  Check([manager fileExistsAtPath:file.path], @"cleanup never deletes originals");
  [manager removeItemAtURL:base error:nil];
}

static void TestComposer(void) {
  [NSApplication sharedApplication];
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 200)];
  TLMessageInput *input = [[TLMessageInput alloc] init];
  [root addSubview:input];
  NSLayoutConstraint *width = [input.widthAnchor constraintEqualToConstant:600];
  [NSLayoutConstraint activateConstraints:@[width,
    [input.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
    [input.topAnchor constraintEqualToAnchor:root.topAnchor]]];
  input.attachmentsEnabled = YES;
  input.attachmentURLs = @[[NSURL fileURLWithPath:@"/tmp/Report.pdf"], [NSURL fileURLWithPath:@"/tmp/Source folder with a long name/"]];
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    input.palette = [TLThemePalette paletteForPreference:preference.integerValue];
    for (NSNumber *size in @[@600, @200]) {
      width.constant = size.doubleValue;
      [root layoutSubtreeIfNeeded];
      [input recalculateHeight];
      [root layoutSubtreeIfNeeded];
      NSScrollView *scroll = [input valueForKey:@"attachmentScrollView"];
      NSStackView *stack = [input valueForKey:@"attachmentStack"];
      Check(!scroll.hidden && stack.arrangedSubviews.count == 2, @"both attachment chips are present");
      Check(NSWidth(input.bounds) == size.doubleValue && NSHeight(input.bounds) > input.palette.composerButtonHeight,
            @"attachment input expands vertically and respects narrow widths");
      Check(NSWidth(scroll.bounds) > 0 && NSHeight(scroll.bounds) > 0 && NSWidth(stack.bounds) > 0, @"attachment row has visible geometry");
      NSScrollView *text = [input valueForKey:@"textScrollView"];
      Check(!NSIntersectsRect(scroll.frame, text.frame), @"attachment row does not overlap the editor");
      NSBitmapImageRep *image = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
      [input cacheDisplayInRect:input.bounds toBitmapImageRep:image];
      NSString *path = [NSString stringWithFormat:@"/tmp/talaria-attachments-%@-%@.png", preference, size];
      [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
  }
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
  [pasteboard writeObjects:@[[NSURL fileURLWithPath:@"/tmp/Pasted file.txt"]]];
  // The same handler serves editor paste and file drops; use a private pasteboard, never the user's clipboard.
  BOOL (^pasteHandler)(NSPasteboard *) = [input.textView valueForKey:@"filePasteHandler"];
  Check(pasteHandler(pasteboard) && input.attachmentURLs.count == 3, @"pasted file URLs become attachments");
  NSString *originalText = input.textView.string;
  [pasteboard clearContents];
  NSData *PNG = [NSData dataWithContentsOfFile:@"/tmp/talaria-attachments-2-200.png"];
  [pasteboard setData:PNG forType:NSPasteboardTypePNG];
  Check(pasteHandler(pasteboard) && input.attachmentURLs.count == 4 &&
        [NSFileManager.defaultManager fileExistsAtPath:input.attachmentURLs.lastObject.path], @"pasted images become readable file attachments");
  Check([input.textView.string isEqual:originalText], @"pasting attachments leaves prompt text unchanged");
  input.attachmentsEditable = NO;
  [input addAttachmentURLs:@[[NSURL fileURLWithPath:@"/tmp/ignored.txt"]]];
  Check(input.attachmentURLs.count == 4, @"cannot mutate attachment selection during send");
  NSStackView *disabledStack = [input valueForKey:@"attachmentStack"];
  NSButton *disabledRemove = [disabledStack.arrangedSubviews.firstObject valueForKey:@"closeButton"];
  Check(!disabledRemove.enabled, @"remove control is disabled during send");
  input.attachmentsEditable = YES;
  Check(disabledRemove.enabled, @"remove control is enabled after send");
  NSStackView *stack = [input valueForKey:@"attachmentStack"];
  NSButton *remove = [stack.arrangedSubviews.firstObject valueForKey:@"closeButton"];
  [NSApp sendAction:remove.action to:remove.target from:remove];
  Check(input.attachmentURLs.count == 3, @"remove action updates the draft");
  input.attachmentURLs = @[];
  [root layoutSubtreeIfNeeded];
  Check(NSHeight(input.bounds) == input.palette.composerButtonHeight, @"empty composer returns to its normal height");
  [pasteboard releaseGlobally];
}

static void TestAttachmentReconciliationAndAnimation(void) {
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 200)];
  TLMessageInput *input = [[TLMessageInput alloc] init];
  [root addSubview:input];
  [NSLayoutConstraint activateConstraints:@[[input.widthAnchor constraintEqualToConstant:600],
    [input.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [input.topAnchor constraintEqualToAnchor:root.topAnchor]]];
  input.palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  input.attachmentsEnabled = YES;
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *transitions = [[TLTransitionCoordinator alloc] initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  [input setValue:transitions forKey:@"attachmentTransitions"];
  NSURL *a = [NSURL fileURLWithPath:@"/tmp/First attachment.pdf"];
  NSURL *b = [NSURL fileURLWithPath:@"/tmp/Second attachment.mov"];
  NSURL *c = [NSURL fileURLWithPath:@"/tmp/New attachment.txt"];
  [input setAttachmentURLs:@[a, b] animated:NO];
  [root layoutSubtreeIfNeeded];
  NSStackView *stack = [input valueForKey:@"attachmentStack"];
  NSView *first = stack.arrangedSubviews[0];
  NSView *second = stack.arrangedSubviews[1];
  id request = [first valueForKey:@"thumbnailRequest"];
  id image = [first valueForKey:@"image"];
  [input setAttachmentURLs:@[a, b, c] animated:YES];
  Check(stack.arrangedSubviews[0] == first && stack.arrangedSubviews[1] == second, @"adding a file retains existing pill views");
  Check([first valueForKey:@"thumbnailRequest"] == request && [first valueForKey:@"image"] == image,
        @"adding a file retains preview image and in-flight request");
  NSView *added = stack.arrangedSubviews[2];
  NSView *content = [added valueForKey:@"chipContentView"];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    Check(NSWidth(added.frame) == 0 && content.alphaValue == 0, @"new pill starts collapsed with invisible content");
    now += input.palette.tabLifecycleTransitionDuration / 2;
    [transitions advance];
    [root layoutSubtreeIfNeeded];
    Check(NSWidth(added.frame) > 0 && NSWidth(added.frame) < NSWidth(content.frame), @"pill grows while its content keeps full width");
    Check(added.layer.masksToBounds && content.alphaValue > 0 && content.alphaValue < 1, @"pill masks content while fading it in");
    NSBitmapImageRep *render = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
    [input cacheDisplayInRect:input.bounds toBitmapImageRep:render];
    [[render representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-attachment-mid-animation.png" atomically:YES];
  }
  [transitions finishAllTransitions];
  [input setAttachmentURLs:@[a, c] animated:YES];
  NSButton *removedButton = [second valueForKey:@"closeButton"];
  Check(!removedButton.enabled && removedButton.tag == -1, @"exiting pill cannot remove a different attachment");
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    now += input.palette.tabClosingTransitionDuration / 2;
    [transitions advance];
    CGFloat partial = [[second valueForKey:@"revealProgress"] doubleValue];
    Check(partial > 0 && partial < 1, @"removed pill shrinks before leaving the row");
    [input setAttachmentURLs:@[a, b, c] animated:YES];
    Check(stack.arrangedSubviews[1] == second && [[second valueForKey:@"revealProgress"] doubleValue] == partial,
          @"re-adding a closing pill reuses it and reverses smoothly");
  }
  [transitions finishAllTransitions];
  [input setAttachmentURLs:@[c, a] animated:NO];
  Check(stack.arrangedSubviews.count == 2 && stack.arrangedSubviews[0] == added && stack.arrangedSubviews[1] == first,
        @"reordering and removing retain the correct pill identities");
  Check([first valueForKey:@"image"] == image && [first valueForKey:@"thumbnailRequest"] == request, @"removal does not reload retained previews");
  NSButton *firstButton = [first valueForKey:@"closeButton"];
  [NSApp sendAction:firstButton.action to:firstButton.target from:firstButton];
  Check([input.attachmentURLs isEqualToArray:@[c]], @"close action uses the updated index after reordering");
  [input setAttachmentURLs:@[] animated:YES];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion)
    Check(!((NSScrollView *)[input valueForKey:@"attachmentScrollView"]).hidden, @"last pill stays visible through its exit");
  [transitions finishAllTransitions];
  [root layoutSubtreeIfNeeded];
  Check(stack.arrangedSubviews.count == 0 && NSHeight(input.bounds) == input.palette.composerButtonHeight, @"last exit cleans up the row and restores composer height");
  [input setAttachmentURLs:@[a] animated:YES];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    now += input.palette.tabLifecycleTransitionDuration / 2;
    [transitions advance];
    NSView *interrupted = stack.arrangedSubviews.firstObject;
    [input setAttachmentURLs:@[] animated:YES];
    now += input.palette.tabClosingTransitionDuration / 2;
    [transitions advance];
    CGFloat closingProgress = [[interrupted valueForKey:@"revealProgress"] doubleValue];
    [input setAttachmentURLs:@[b] animated:YES];
    Check([[interrupted valueForKey:@"revealProgress"] doubleValue] == closingProgress,
          @"adding a sibling does not restart an existing exit");
    now += input.palette.tabClosingTransitionDuration / 2 + 0.001;
    [transitions advance];
    Check(![stack.arrangedSubviews containsObject:interrupted], @"removing during entry completes on the original exit schedule");
  }
  [transitions finishAllTransitions];
  [input setAttachmentURLs:@[a, a] animated:NO];
  NSArray *duplicates = stack.arrangedSubviews.copy;
  [input setAttachmentURLs:@[a, a, b] animated:YES];
  Check(stack.arrangedSubviews[0] == duplicates[0] && stack.arrangedSubviews[1] == duplicates[1], @"duplicate URL occurrences retain distinct pills");
  [input setAttachmentURLs:@[c] animated:NO];
  [transitions finishAllTransitions];
  Check(stack.arrangedSubviews.count == 1 && [input.attachmentURLs isEqualToArray:@[c]], @"draft replacement cancels old lifecycle work without stale pills");
}

static void TestAttachmentPickerAppearance(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 200)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  TLMessageInput *input = [[TLMessageInput alloc] init];
  [window.contentView addSubview:input];
  [NSLayoutConstraint activateConstraints:@[[input.widthAnchor constraintEqualToConstant:600],
    [input.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
    [input.topAnchor constraintEqualToAnchor:window.contentView.topAnchor]]];
  input.attachmentsEnabled = YES;
  __block NSTimeInterval now = 0;
  TLTransitionCoordinator *transitions = [[TLTransitionCoordinator alloc] initWithClock:^NSTimeInterval { return now; } automaticallyAdvances:NO];
  [input setValue:transitions forKey:@"attachmentTransitions"];
  // Simulate controller work that takes longer than the entire entry animation.
  input.attachmentsChangeHandler = ^{ now += 1; };
  TLAttachmentTestPanel *panel = [[TLAttachmentTestPanel alloc] init];
  panel.URLs = @[[NSURL fileURLWithPath:@"/tmp/Selected from picker.pdf"]];
  [input completeAttachmentSelection:(NSOpenPanel *)panel response:NSModalResponseOK];
  Check(panel.orderedOut && input.attachmentURLs.count == 0, @"picker is hidden before files are added on the next main-loop turn");
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  while (!input.attachmentURLs.count && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  Check(input.attachmentURLs.count == 1, @"picker selection reaches the composer");
  NSStackView *stack = [input valueForKey:@"attachmentStack"];
  NSView *chip = stack.arrangedSubviews.firstObject;
  [transitions advance];
  if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
    Check([[chip valueForKey:@"revealProgress"] doubleValue] == 0, @"controller work does not consume the appearance animation");
    now += input.palette.tabLifecycleTransitionDuration / 2;
    [transitions advance];
    CGFloat progress = [[chip valueForKey:@"revealProgress"] doubleValue];
    Check(progress > 0 && progress < 1, @"picker addition has a visible intermediate reveal frame");
  }
  [transitions finishAllTransitions];
  TLHoverIconButton *close = [chip valueForKey:@"closeButton"];
  Check(close.idleSurfaceColor == nil && close.hoverSurfaceOnly, @"remove button has a transparent idle state and retains hover feedback");
  [window close];
}

static void TestSystemAttachmentThumbnails(void) {
  NSURL *base = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
  NSURL *imageURL = [base URLByAppendingPathComponent:@"Image.png"];
  NSURL *pdfURL = [base URLByAppendingPathComponent:@"Document.pdf"];
  NSURL *videoURL = [base URLByAppendingPathComponent:@"Video.mov"];
  NSURL *textURL = [base URLByAppendingPathComponent:@"Notes.txt"];
  NSURL *unknownURL = [base URLByAppendingPathComponent:@"Unknown.talariafixture"];
  // Synthetic one-second H.264 fixture, generated with:
  // ffmpeg -f lavfi -i testsrc2=size=64x48:rate=5 -t 1 -c:v libx264 -pix_fmt yuv420p -movflags +faststart attachment-preview.mov
  NSURL *videoFixture = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath
    stringByAppendingPathComponent:@"Tests/fixtures/attachment-preview.mov"]];
  Check([NSFileManager.defaultManager copyItemAtURL:videoFixture toURL:videoURL error:nil], @"creates video preview fixture");
  Check([@"Quick Look document preview" writeToURL:textURL atomically:YES encoding:NSUTF8StringEncoding error:nil], @"creates text preview fixture");
  Check([[NSData dataWithBytes:"\0\1\2\3" length:4] writeToURL:unknownURL atomically:YES], @"creates unsupported file fixture");
  NSURL *asset = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"assets/Talaria-icon.png"]];
  Check([NSFileManager.defaultManager copyItemAtURL:asset toURL:imageURL error:nil], @"creates image preview fixture");
  NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 96, 128)];
  NSTextField *label = [NSTextField labelWithString:@"Preview"];
  label.frame = NSMakeRect(8, 80, 80, 24);
  [page addSubview:label];
  Check([[page dataWithPDFInsideRect:page.bounds] writeToURL:pdfURL atomically:YES], @"creates PDF preview fixture");
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 200)];
  TLMessageInput *input = [[TLMessageInput alloc] init];
  [root addSubview:input];
  [NSLayoutConstraint activateConstraints:@[[input.widthAnchor constraintEqualToConstant:600],
    [input.leadingAnchor constraintEqualToAnchor:root.leadingAnchor], [input.topAnchor constraintEqualToAnchor:root.topAnchor]]];
  input.palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  input.attachmentsEnabled = YES;
  input.attachmentURLs = @[imageURL, pdfURL, videoURL, textURL, unknownURL];
  NSStackView *stack = [input valueForKey:@"attachmentStack"];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while (deadline.timeIntervalSinceNow > 0) {
    BOOL pending = NO;
    for (NSView *button in stack.arrangedSubviews) pending |= [button valueForKey:@"thumbnailRequest"] != nil;
    if (!pending) break;
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  NSUInteger index = 0;
  for (NSView *button in stack.arrangedSubviews) {
    NSImage *image = [button valueForKey:@"image"];
    Check(image != nil, @"every file keeps a preview or fallback icon");
    if (index < 4) Check([[button valueForKey:@"hasContentPreview"] boolValue],
      [NSString stringWithFormat:@"Quick Look supplies a content thumbnail for %@", input.attachmentURLs[index].lastPathComponent]);
    else Check(![[button valueForKey:@"hasContentPreview"] boolValue], @"unsupported files keep a system icon without thumbnail clipping");
    index++;
    Check([button valueForKey:@"thumbnailRequest"] == nil, @"completed thumbnail requests are released");
  }
  NSArray *loadedPills = stack.arrangedSubviews.copy;
  NSArray *loadedImages = [loadedPills valueForKey:@"image"];
  NSArray *originalURLs = input.attachmentURLs;
  [input addAttachmentURLs:@[base]];
  for (NSUInteger i = 0; i < loadedPills.count; i++) {
    Check(stack.arrangedSubviews[i] == loadedPills[i] && [loadedPills[i] valueForKey:@"image"] == loadedImages[i] &&
          [loadedPills[i] valueForKey:@"thumbnailRequest"] == nil, @"completed previews stay cached when another file is added");
  }
  input.attachmentURLs = originalURLs;
  [root layoutSubtreeIfNeeded];
  [input recalculateHeight];
  [root layoutSubtreeIfNeeded];
  NSBitmapImageRep *render = [input bitmapImageRepForCachingDisplayInRect:input.bounds];
  [input cacheDisplayInRect:input.bounds toBitmapImageRep:render];
  [[render representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-system-previews.png" atomically:YES];
  input.attachmentURLs = @[];
  [NSFileManager.defaultManager removeItemAtURL:base error:nil];
}

int main(void) {
  @autoreleasepool { TestAttachmentMigrationCollision(); TestProfileSchemaCompatibility(); TestStorageAndPersistence(); TestComposer(); TestAttachmentReconciliationAndAnimation(); TestAttachmentPickerAppearance(); TestSystemAttachmentThumbnails(); NSLog(@"ChatAttachmentTests passed"); }
  return 0;
}
