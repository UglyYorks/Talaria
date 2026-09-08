#import <AppKit/AppKit.h>
#import "ChatAttachmentStore.h"
#import "TLAttachmentViewerWindowController.h"
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLChatPresentation.h"
#import "design_system/TLAttachmentCard.h"
#import "design_system/TLThemedButton.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]]; }
static NSBitmapImageRep *Snapshot(NSView *view, NSString *name) {
  [view layoutSubtreeIfNeeded]; [view displayIfNeeded];
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@"build/" stringByAppendingString:name] atomically:YES];
  return bitmap;
}
static TLAttachmentPreviewItem *Item(NSString *name, NSURL *URL, BOOL directory) {
  TLAttachmentPreviewItem *item = [TLAttachmentPreviewItem new]; item.name = name; item.directory = directory;
  item.URLResolver = ^NSURL *{ return [NSFileManager.defaultManager fileExistsAtPath:URL.path] ? URL : nil; };
  return item;
}
static NSArray<TLAttachmentCard *> *FindCards(NSView *view) {
  NSMutableArray *cards = [NSMutableArray array];
  if ([view isKindOfClass:TLAttachmentCard.class]) [cards addObject:view];
  for (NSView *child in view.subviews) [cards addObjectsFromArray:FindCards(child)];
  return cards;
}

@interface TalariaWindowController (AttachmentViewerTests)
- (NSView *)rowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail;
- (NSString *)rowSignatureForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail;
- (NSString *)displayTextForMessage:(TLChatMessage *)message;
@end

static void TestResolution(NSURL *base) {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSURL *workspace = [base URLByAppendingPathComponent:@"workspace"];
  [manager createDirectoryAtURL:workspace withIntermediateDirectories:YES attributes:nil error:nil];
  NSURL *source = [base URLByAppendingPathComponent:@"résumé report.txt"];
  [@"Retained contents" writeToURL:source atomically:YES encoding:NSUTF8StringEncoding error:nil];
  TLChatAttachmentStore *store = [[TLChatAttachmentStore alloc] initWithWorkspaceURL:workspace];
  NSDictionary *attachment = [store copyURLs:@[source] sessionID:@"conversation_A" error:nil].firstObject;
  NSURL *retained = [store fileURLForAttachment:attachment sessionID:@"conversation_A"];
  Check(retained != nil, @"resolves a retained snapshot with spaces and Unicode");
  Check(![retained isEqual:source], @"previews the retained copy, not the original");
  Check(![store fileURLForAttachment:attachment sessionID:@"conversation_B"], @"cannot read another conversation's attachment");
  Check(![store fileURLForAttachment:@{@"guestPath":@42} sessionID:@"conversation_A"], @"malformed metadata does not crash");
  Check(![store fileURLForAttachment:@{@"guestPath":@"/workspace/attachments/conversation_A/../../outside.txt"} sessionID:@"conversation_A"], @"rejects path traversal");
  Check(![store fileURLForAttachment:@{@"guestPath":@"/etc/passwd"} sessionID:@"conversation_A"], @"rejects arbitrary host paths");
  [manager removeItemAtURL:retained error:nil];
  Check(![store fileURLForAttachment:attachment sessionID:@"conversation_A"], @"missing snapshots resolve to unavailable");
  [manager createSymbolicLinkAtURL:retained withDestinationURL:source error:nil];
  Check(![store fileURLForAttachment:attachment sessionID:@"conversation_A"], @"rejects files replaced with symbolic links");
  [manager removeItemAtURL:retained error:nil];
  [manager copyItemAtURL:source toURL:retained error:nil];
  NSURL *parent = retained.URLByDeletingLastPathComponent;
  NSURL *moved = [base URLByAppendingPathComponent:@"redirected"];
  [manager moveItemAtURL:parent toURL:moved error:nil];
  [manager createSymbolicLinkAtURL:parent withDestinationURL:moved error:nil];
  Check(![store fileURLForAttachment:attachment sessionID:@"conversation_A"], @"rejects a redirected ancestor as well as a linked file");
}

static void TestTranscript(void) {
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(0,0,700,300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; window.releasedWhenClosed = NO;
  window.minSize = NSMakeSize(200,200); window.contentMinSize = NSMakeSize(200,200);
  TalariaWindowController *owner = [[TalariaWindowController alloc] initWithWindow:window];
  TLChatPresentation *origin = [TLChatPresentation new]; origin.chat = [TLChatRecord new]; origin.chat.title = @"Design review"; origin.chat.hermesSessionID = @"conversation_A";
  [owner setValue:origin forKey:@"chatPresentation"];
  TLChatMessage *first = [TLChatMessage messageWithRole:TLRoleUser content:@"Here are the latest files." thinking:nil];
  first.attachments = @[@{@"name":@"Cover design.png", @"directory":@NO}, @{@"name":@"Research notes.md", @"directory":@NO}];
  TLChatMessage *second = [TLChatMessage messageWithRole:TLRoleUser content:@"" thinking:nil];
  second.attachments = @[@{@"name":@"Final report.pdf", @"directory":@NO}];
  origin.messages = [@[first,second] mutableCopy];
  Check([[owner displayTextForMessage:first] isEqual:first.content], @"attachment metadata is never dumped into message text");
  for (NSNumber *theme in @[@1,@2]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue]; [owner setValue:palette forKey:@"palette"];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    for (NSNumber *width in @[@200,@700]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 300)];
      [owner setValue:[NSLayoutConstraint constraintWithItem:[NSView new] attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:width.doubleValue - 40] forKey:@"messageInputWidthConstraint"];
      NSView *root = [NSView new]; window.contentView = root;
      NSView *row = [owner rowForMessage:second showsOutgoingTail:YES]; [root addSubview:row];
      [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [row.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [row.topAnchor constraintEqualToAnchor:root.topAnchor constant:20]]];
      [root layoutSubtreeIfNeeded];
      NSArray<TLAttachmentCard *> *cards = FindCards(row);
      Check(cards.firstObject.isAccessibilityElement && [cards.firstObject.accessibilityRole isEqual:NSAccessibilityButtonRole], @"file cards expose a named accessible preview action");
      Check(cards.count == 1 && NSHeight(row.bounds) >= palette.attachmentCardHeight, @"attachment-only message has a real preview card and nonzero height");
      Snapshot(root, [NSString stringWithFormat:@"attachment-message-%@-%@.png",theme,width]);
      Check(NSWidth(cards[0].bounds) > 0 && NSMaxX([cards[0] convertRect:cards[0].bounds toView:root]) <= width.doubleValue, @"message file card fits a 200px window");
      // Change the active pane before activating an existing card.
      [owner setValue:[TLChatPresentation new] forKey:@"chatPresentation"];
      [cards[0] accessibilityPerformPress];
      TLAttachmentViewerWindowController *viewer = [owner valueForKey:@"attachmentViewer"];
      Check(viewer.selectedIndex == 2 && [[viewer valueForKey:@"items"] count] == 3, @"click preserves the originating conversation and selected attachment across focus changes");
      [viewer close]; [owner setValue:origin forKey:@"chatPresentation"];
    }
  }
  // Long message text must wrap to the card's narrower width without clipping.
  [window setContentSize:NSMakeSize(700,700)];
  [owner setValue:[NSLayoutConstraint constraintWithItem:[NSView new] attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:660] forKey:@"messageInputWidthConstraint"];
  first.content = @"Please review these attachments before our next meeting. The design includes a number of important changes to the navigation and the document viewer. I have included the research notes so that everyone can check the supporting details.";
  NSView *root = [NSView new]; window.contentView = root;
  NSView *row = [owner rowForMessage:first showsOutgoingTail:YES]; [root addSubview:row];
  [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [row.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [row.topAnchor constraintEqualToAnchor:root.topAnchor constant:20]]];
  [root layoutSubtreeIfNeeded];
  NSStackView *stack = (id)FindCards(row).firstObject.superview;
  NSTextField *label = (id)stack.arrangedSubviews.firstObject;
  NSRect required = [first.content boundingRectWithSize:NSMakeSize(NSWidth(label.bounds),CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:label.font}];
  Check(NSHeight(label.bounds) + 2 >= ceil(NSHeight(required)), @"message text wraps to attachment width without clipping");
  Snapshot(root,@"attachment-message-with-text.png");
  [window close];
}

static void TestViewer(NSURL *base) {
  NSURL *textURL = [base URLByAppendingPathComponent:@"Research notes.md"];
  NSString *notes = @"# Attachment viewer\n\nA few notes from our design review.\n\n• Keep the conversation close at hand.\n• Make every attachment easy to browse.\n• Preserve the original file.\n\nNext steps\n──────────\nReview the cover design and share the final report.\n\n<script>This is displayed as text, never executed.</script>\n";
  [notes writeToURL:textURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
  TLAttachmentPreviewItem *savedItem = Item(@"Research notes.md",textURL,NO);
  NSURL *exportURL = [base URLByAppendingPathComponent:@"Exported notes.md"];
  Check([savedItem saveCopyToURL:exportURL error:nil], @"saves a separate copy of the retained file");
  Check([[NSString stringWithContentsOfURL:exportURL encoding:NSUTF8StringEncoding error:nil] isEqual:notes], @"saved copy contains the complete original");
  [@"Old contents" writeToURL:exportURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
  Check([savedItem saveCopyToURL:exportURL error:nil], @"replaces a user-selected existing destination");
  Check([[NSString stringWithContentsOfURL:exportURL encoding:NSUTF8StringEncoding error:nil] isEqual:notes], @"replacement saves the new contents");
  Check(![savedItem saveCopyToURL:textURL error:nil], @"cannot overwrite the retained source");
  Check(![Item(@"Folder",base,YES) saveCopyToURL:[base URLByAppendingPathComponent:@"recursive"] error:nil], @"cannot recursively save a folder into itself");
  Check(![savedItem saveCopyToURL:[base URLByAppendingPathComponent:@"missing-parent/file"] error:nil] && [[NSString stringWithContentsOfURL:textURL encoding:NSUTF8StringEncoding error:nil] isEqual:notes], @"failed exports leave the original intact");
  NSURL *imageURL = [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"assets/sidebar-planet.png"]];
  NSURL *missing = [base URLByAppendingPathComponent:@"Missing.pdf"];
  NSArray *items = @[Item(@"Cover design.png",imageURL,NO), Item(@"Research notes.md",textURL,NO), Item(@"Source files",base,YES), Item(@"Missing.pdf",missing,NO)];
  TLAttachmentViewerWindowController *viewer = [[TLAttachmentViewerWindowController alloc] initWithItems:items conversationTitle:@"Design review" selectedIndex:1 palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  [viewer showWindow:nil];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
  while (![viewer valueForKey:@"textView"] && deadline.timeIntervalSinceNow > 0) Drain();
  Check([[(NSTextView *)[viewer valueForKey:@"textView"] string] isEqual:notes], @"loads selectable text literally");
  for (NSNumber *theme in @[@1,@2]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
    [viewer applyPalette:palette];
    for (NSNumber *width in @[@520,@980]) {
      [viewer.window setContentSize:NSMakeSize(width.doubleValue,680)]; Drain();
      [viewer.window.contentView layoutSubtreeIfNeeded];
      NSView *preview = [viewer valueForKey:@"previewHost"];
      Check(NSWidth(preview.frame) > 450, @"preview remains useful in compact and wide windows");
      Check(((NSView *)[viewer valueForKey:@"sidebar"]).hidden == (width.integerValue == 520), @"compact viewer collapses its file list");
      Snapshot(viewer.window.contentView,[NSString stringWithFormat:@"attachment-viewer-%@-%@.png",theme,width]);
    }
    Check([[viewer valueForKey:@"saveButton"] isKindOfClass:TLThemedButton.class] && [[viewer valueForKey:@"finderButton"] isKindOfClass:TLThemedButton.class], @"viewer actions use the reusable button covered by rendered interaction tests");
  }
  [viewer selectItemAtIndex:0];
  Check([[(QLPreviewView *)[viewer valueForKey:@"preview"] previewItem].previewItemURL isEqual:imageURL], @"images use the native Quick Look preview");
  for (NSUInteger tick = 0; tick < 8; tick++) Drain();
  Snapshot(viewer.window.contentView,@"attachment-viewer-image.png");
  [viewer selectItemAtIndex:1]; [viewer selectItemAtIndex:3]; Drain();
  Check(![viewer valueForKey:@"textView"] && ![viewer valueForKey:@"preview"], @"late text loads cannot overwrite a new selection");
  Check(![(NSButton *)[viewer valueForKey:@"saveButton"] isEnabled], @"missing files cannot be saved");
  Check([[(NSTextField *)[viewer valueForKey:@"emptyTitle"] stringValue] isEqual:@"File unavailable"], @"missing files have a clear fallback");
  [viewer selectItemAtIndex:2];
  Check([[(NSTextField *)[viewer valueForKey:@"emptyTitle"] stringValue] isEqual:@"Folder attachment"], @"folders have deliberate preview guidance");
  [viewer selectItemAtIndex:0];
  Check(![(NSButton *)[viewer valueForKey:@"previousButton"] isEnabled], @"navigation stops at first file");
  [viewer selectItemAtIndex:3]; Check(![(NSButton *)[viewer valueForKey:@"nextButton"] isEnabled], @"navigation stops at last file");
  [viewer close]; Check(![viewer valueForKey:@"keyMonitor"] && ![viewer valueForKey:@"preview"], @"closing releases keyboard and native preview resources");
  NSMutableData *large = [NSMutableData dataWithLength:3 * 1024 * 1024]; memset(large.mutableBytes, 'a', large.length); [large writeToURL:textURL atomically:YES];
  viewer = [[TLAttachmentViewerWindowController alloc] initWithItems:@[items[1]] conversationTitle:@"Large log" selectedIndex:0 palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  deadline = [NSDate dateWithTimeIntervalSinceNow:3]; while (![viewer valueForKey:@"textView"] && deadline.timeIntervalSinceNow > 0) Drain();
  Check([(NSTextView *)[viewer valueForKey:@"textView"] string].length == 2 * 1024 * 1024, @"large text previews are bounded");
  Check([[(NSTextField *)[viewer valueForKey:@"detailLabel"] stringValue] containsString:@"first 2 MB"], @"truncation is visible");
  [viewer close];
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSURL *base = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtURL:base withIntermediateDirectories:YES attributes:nil error:nil];
    TestResolution(base); TestViewer(base); TestTranscript();
    [NSFileManager.defaultManager removeItemAtURL:base error:nil];
    NSLog(@"AttachmentViewerTests passed");
  }
  return 0;
}
