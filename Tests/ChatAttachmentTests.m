#import <AppKit/AppKit.h>
#import "ChatAttachmentStore.h"
#import "Database.h"
#import "PromptMessages.h"
#import "design_system/TLMessageInput.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSURL *HostURL(NSURL *workspace, NSDictionary *attachment) {
  return [workspace URLByAppendingPathComponent:[attachment[@"guestPath"] substringFromIndex:@"/workspace/".length]];
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
  input.attachmentsEditable = YES;
  NSStackView *stack = [input valueForKey:@"attachmentStack"];
  NSButton *remove = (NSButton *)stack.arrangedSubviews.firstObject;
  [NSApp sendAction:remove.action to:remove.target from:remove];
  Check(input.attachmentURLs.count == 3, @"remove action updates the draft");
  input.attachmentURLs = @[];
  [root layoutSubtreeIfNeeded];
  Check(NSHeight(input.bounds) == input.palette.composerButtonHeight, @"empty composer returns to its normal height");
  [pasteboard releaseGlobally];
}

int main(void) {
  @autoreleasepool { TestStorageAndPersistence(); TestComposer(); NSLog(@"ChatAttachmentTests passed"); }
  return 0;
}
