#import <AppKit/AppKit.h>
#import "TLChatControllerTestSupport.h"
#import "ChatAttachmentStore.h"
#import "TLAttachmentViewerWindowController.h"
#import "TalariaWindowController.h"
#import "TLMainWindow.h"
#import "TLChatTabController.h"
#import "design_system/TLAttachmentChipView.h"
#import "design_system/TLGlassButton.h"
#import "design_system/TLAttachmentPreviewPanel.h"
#import "design_system/UIComponents.h"

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
static NSArray<TLAttachmentChipView *> *FindChips(NSView *view) {
  NSMutableArray *cards = [NSMutableArray array];
  if ([view isKindOfClass:TLAttachmentChipView.class]) [cards addObject:view];
  for (NSView *child in view.subviews) [cards addObjectsFromArray:FindChips(child)];
  return cards;
}
static TLMessageBubbleView *FindBubble(NSView *row) {
  for (NSView *view in row.subviews) if ([view isKindOfClass:TLMessageBubbleView.class]) return (id)view;
  return nil;
}

@interface TLChatTabController (AttachmentViewerTests)
- (NSView *)rowForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail;
- (NSString *)rowSignatureForMessage:(TLChatMessage *)message showsOutgoingTail:(BOOL)tail;
- (NSString *)displayTextForMessage:(TLChatMessage *)message;
@end

static NSUInteger PixelsMatching(NSBitmapImageRep *bitmap, CGFloat expected[3]) {
  NSUInteger count = 0;
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
    NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    if (fabs(pixel.redComponent - expected[0]) < 0.04 && fabs(pixel.greenComponent - expected[1]) < 0.04 && fabs(pixel.blueComponent - expected[2]) < 0.04) count++;
  }
  return count;
}
static CGFloat Luminance(NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  CGFloat channels[3] = {rgb.redComponent,rgb.greenComponent,rgb.blueComponent};
  for (NSUInteger i = 0; i < 3; i++) channels[i] = channels[i] <= 0.04045 ? channels[i] / 12.92 : pow((channels[i] + 0.055) / 1.055,2.4);
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}
static NSRect RenderedSymbolBounds(NSBitmapImageRep *bitmap) {
  CGFloat peak = 0;
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
    NSColor *color = [bitmap colorAtX:x y:y]; peak = MAX(peak,Luminance(color) * color.alphaComponent);
  }
  NSInteger left = bitmap.pixelsWide, top = bitmap.pixelsHigh, right = -1, bottom = -1;
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
    NSColor *color = [bitmap colorAtX:x y:y];
    if (Luminance(color) * color.alphaComponent < peak * 0.6) continue;
    left = MIN(left,x); top = MIN(top,y); right = MAX(right,x); bottom = MAX(bottom,y);
  }
  return NSMakeRect(left,top,right - left + 1,bottom - top + 1);
}
static void ClickPreview(NSWindow *window, NSPoint point) {
  NSPoint location = [window.contentView convertPoint:point toView:nil];
  NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:location modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
  NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:location modifierFlags:0 timestamp:down.timestamp + 0.01 windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
  [NSApp postEvent:up atStart:YES]; [NSApp sendEvent:down]; Drain();
}
static void TestViewerControlAppearance(TLAttachmentViewerWindowController *viewer, NSNumber *theme) {
  TLThemePalette *palette = [viewer valueForKey:@"palette"];
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:viewer.window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
  for (NSString *key in @[@"finderButton",@"saveButton",@"closeButton"]) {
    TLHoverIconButton *button = [viewer valueForKey:key];
    NSWindow *referenceWindow = [[NSWindow alloc] initWithContentRect:button.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]; referenceWindow.releasedWhenClosed = NO;
    referenceWindow.appearance = viewer.window.appearance;
    NSButton *native = [[NSButton alloc] initWithFrame:button.bounds]; native.bordered = NO; native.imagePosition = NSImageOnly;
    native.image = button.image; native.contentTintColor = palette.labelText; referenceWindow.contentView = native;
    NSRect nativeGlyph = RenderedSymbolBounds(Snapshot(native,[NSString stringWithFormat:@"attachment-%@-native.png",key]));
    CGFloat idleBrightness = 0;
    for (NSString *state in @[@"normal",@"hovered",@"pressed",@"focused",@"inactive",@"disabled"]) {
      [button mouseExited:event]; [button setValue:@NO forKey:@"pressed"]; button.enabled = YES;
      [viewer.window makeFirstResponder:nil];
      if ([state isEqual:@"hovered"]) [button mouseEntered:event];
      if ([state isEqual:@"pressed"]) [button setValue:@YES forKey:@"pressed"];
      if ([state isEqual:@"focused"]) [viewer.window makeFirstResponder:button];
      if ([state isEqual:@"inactive"]) [viewer.window resignKeyWindow];
      if ([state isEqual:@"disabled"]) button.enabled = NO;
      [button layout];
      NSBitmapImageRep *bitmap = Snapshot(button,[NSString stringWithFormat:@"attachment-%@-%@-%@.png",key,theme,state]);
      BOOL highlighted = [state isEqual:@"hovered"] || [state isEqual:@"pressed"];
      NSColor *ink = [(highlighted ? palette.statusItemIcon : palette.labelText) colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      CGFloat foreground[3] = {ink.redComponent,ink.greenComponent,ink.blueComponent};
      if (button.enabled) Check(PixelsMatching(bitmap,foreground) > 10,@"preview icons render their explicit light tint, including white on hover and press, in both themes and inactive windows");
      if (button.enabled) {
        NSRect actualGlyph = RenderedSymbolBounds(bitmap);
        Check(fabs(NSWidth(actualGlyph) - NSWidth(nativeGlyph)) <= 2 && fabs(NSHeight(actualGlyph) - NSHeight(nativeGlyph)) <= 2,
          @"tinted preview symbols preserve the native glyph width and height without squashing");
        Check(fabs(NSMidX(actualGlyph) - NSMidX(nativeGlyph)) <= 1 && fabs(NSMidY(actualGlyph) - NSMidY(nativeGlyph)) <= 1,
          @"tinted preview symbols preserve native alignment");
      }
      CGFloat scale = bitmap.pixelsWide / NSWidth(button.bounds);
      NSColor *surface = [bitmap colorAtX:(NSInteger)(7 * scale) y:bitmap.pixelsHigh / 2];
      if ([state isEqual:@"normal"]) idleBrightness = Luminance(surface);
      if (highlighted) Check(Luminance(surface) > idleBrightness,@"hovered and pressed preview button backgrounds render lighter than idle");
      if (button.enabled) Check((Luminance(ink) + 0.05) / (Luminance(surface) + 0.05) >= 4.5,@"preview icon and surface retain readable rendered contrast");
    }
    button.enabled = YES; [button mouseExited:event]; [button setValue:@NO forKey:@"pressed"];
    [referenceWindow close];
  }
  [viewer.window makeKeyWindow];
}
static void TestSharedChipAppearance(void) {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,220,52) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]; window.releasedWhenClosed = NO;
  TLTokenView *root = [TLTokenView new]; window.contentView = root;
  TLAttachmentChipView *chip = [[TLAttachmentChipView alloc] initWithFrame:NSMakeRect(10,10,200,32)];
  chip.title = @"Research notes.md"; chip.showsRemoveButton = NO; chip.activationHandler = ^{}; [root addSubview:chip];
  NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(30,25) modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  for (NSNumber *theme in @[@1,@2]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue]; root.fillColor = palette.tabBackground; chip.palette = palette;
    for (NSString *state in @[@"normal",@"hovered",@"pressed",@"focused"]) {
      [chip mouseExited:event]; [chip mouseUp:event]; [window makeFirstResponder:nil];
      if ([state isEqual:@"hovered"]) [chip mouseEntered:event];
      if ([state isEqual:@"pressed"]) [chip mouseDown:event];
      if ([state isEqual:@"focused"]) [window makeFirstResponder:chip];
      NSBitmapImageRep *bitmap = Snapshot(root,[NSString stringWithFormat:@"attachment-chip-%@-%@.png",theme,state]);
      NSColor *ink = [palette.controlText colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
      CGFloat foreground[3] = {ink.redComponent,ink.greenComponent,ink.blueComponent};
      Check(PixelsMatching(bitmap,foreground) > 10,@"shared chips render readable theme text in normal, hover, pressed and focus states");
      // Measure the rendered surface, rather than predicting Core Animation's color-space compositing.
      CGFloat scale = bitmap.pixelsWide / NSWidth(root.bounds);
      NSColor *surface = [bitmap colorAtX:bitmap.pixelsWide / 2 y:bitmap.pixelsHigh - (NSInteger)(15 * scale)];
      CGFloat foregroundLuminance = Luminance(ink), backgroundLuminance = Luminance(surface);
      CGFloat contrast = (MAX(foregroundLuminance,backgroundLuminance) + 0.05) / (MIN(foregroundLuminance,backgroundLuminance) + 0.05);
      Check(contrast >= 4.5,@"rendered chip text and surface maintain readable contrast in both themes and interaction states");
    }
  }
  chip.showsRemoveButton = YES;
  Check([chip.accessibilityChildren containsObject:chip.closeButton],@"composer chip removal remains accessible after sharing the component");
  [window close];
}

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
  TLChatTabController *origin = [owner newChatTabController]; origin.chat = [TLChatRecord new]; origin.chat.title = @"Design review"; origin.chat.hermesSessionID = @"conversation_A";
  [owner setValue:origin forKey:@"chatPresentation"];
  TLChatMessage *first = [TLChatMessage messageWithRole:TLRoleUser content:@"Here are the latest files." thinking:nil];
  first.attachments = @[@{@"name":@"Cover design.png", @"directory":@NO}, @{@"name":@"Research notes.md", @"directory":@NO}];
  TLChatMessage *second = [TLChatMessage messageWithRole:TLRoleUser content:@"" thinking:nil];
  second.attachments = @[@{@"name":@"Final report.pdf", @"directory":@NO}];
  origin.messages = [@[first,second] mutableCopy];
  Check([[origin displayTextForMessage:first] isEqual:first.content], @"attachment metadata is never dumped into message text");
  for (NSNumber *theme in @[@1,@2]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue]; [owner setValue:palette forKey:@"palette"]; [origin applyPalette:palette];
    window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    for (NSNumber *width in @[@200,@700]) {
      [window setContentSize:NSMakeSize(width.doubleValue, 300)];
      [owner setValue:[NSLayoutConstraint constraintWithItem:[NSView new] attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:width.doubleValue - 40] forKey:@"messageInputWidthConstraint"];
      NSView *root = [NSView new]; window.contentView = root;
      NSView *row = [origin rowForMessage:second showsOutgoingTail:YES]; [root addSubview:row];
      [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [row.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [row.topAnchor constraintEqualToAnchor:root.topAnchor constant:20]]];
      [root layoutSubtreeIfNeeded];
      NSArray<TLAttachmentChipView *> *cards = FindChips(row);
      Check(!FindBubble(row),@"attachment-only messages show standalone chips without an empty bubble");
      Check(cards.firstObject.isAccessibilityElement && [cards.firstObject.accessibilityRole isEqual:NSAccessibilityButtonRole], @"file cards expose a named accessible preview action");
      Check(cards.firstObject.showsRemoveButton == NO && [cards.firstObject.label.font isEqual:palette.smallFont], @"message chips use composer typography and hide draft-only removal controls");
      Check(cards.count == 1 && NSHeight(row.bounds) >= palette.fieldHeight, @"attachment-only message has a real preview card and nonzero height");
      Snapshot(root, [NSString stringWithFormat:@"attachment-message-%@-%@.png",theme,width]);
      Check(NSWidth(cards[0].bounds) > 0 && NSMaxX([cards[0] convertRect:cards[0].bounds toView:root]) <= width.doubleValue,
        [NSString stringWithFormat:@"message chips fit the requested %@px window (content %@, row %@, chip %@)",width,NSStringFromRect(root.bounds),NSStringFromRect(row.frame),NSStringFromRect([cards[0] convertRect:cards[0].bounds toView:root])]);
      // Change the active pane before activating an existing card.
      [owner setValue:[TLChatTabController new] forKey:@"chatPresentation"];
      [cards[0] accessibilityPerformPress];
      TLAttachmentViewerWindowController *viewer = [owner valueForKey:@"attachmentViewer"];
      Check(viewer.selectedIndex == 2 && [[viewer valueForKey:@"items"] count] == 3, @"click preserves the originating conversation and selected attachment across focus changes");
      [viewer close]; [owner setValue:origin forKey:@"chatPresentation"];
      [row removeFromSuperview];
      row = [origin rowForMessage:first showsOutgoingTail:YES]; [root addSubview:row];
      [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [row.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [row.topAnchor constraintEqualToAnchor:root.topAnchor constant:20]]];
      [root layoutSubtreeIfNeeded];
      TLMessageBubbleView *bubble = FindBubble(row);
      NSArray<TLAttachmentChipView *> *chips = FindChips(row);
      Check(bubble && FindChips(bubble).count == 0,@"message attachments are outside the text bubble");
      for (TLAttachmentChipView *chip in chips) {
        NSRect chipFrame = [chip convertRect:chip.bounds toView:row];
        Check(NSMaxY(chipFrame) + palette.space5 <= NSMinY(bubble.frame) + 0.5,@"attachments sit below the text bubble with theme spacing");
        Check(NSMinX(chipFrame) >= 0 && NSMaxX(chipFrame) <= NSWidth(row.bounds) + 0.5,@"attachment chips fit narrow conversation rows");
      }
      NSRect lastChipFrame = [chips.lastObject convertRect:chips.lastObject.bounds toView:row];
      Check(fabs(NSMaxX(lastChipFrame) - NSWidth(row.bounds)) < 0.5,@"wrapped outgoing attachments align to the message's trailing edge");
      Snapshot(root,[NSString stringWithFormat:@"attachment-below-bubble-%@-%@.png",theme,width]);
    }
  }
  // Long text wraps independently of the attachment row below it.
  [window setContentSize:NSMakeSize(700,700)];
  [owner setValue:[NSLayoutConstraint constraintWithItem:[NSView new] attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:660] forKey:@"messageInputWidthConstraint"];
  first.content = @"Please review these attachments before our next meeting. The design includes a number of important changes to the navigation and the document viewer. I have included the research notes so that everyone can check the supporting details.";
  NSView *root = [NSView new]; window.contentView = root;
  NSView *row = [origin rowForMessage:first showsOutgoingTail:YES]; [root addSubview:row];
  [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20], [row.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20], [row.topAnchor constraintEqualToAnchor:root.topAnchor constant:20]]];
  [root layoutSubtreeIfNeeded];
  NSStackView *stack = (id)FindBubble(row).subviews.firstObject;
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
    Check(!viewer.window.opaque && viewer.window.styleMask == (NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel), @"viewer is a transparent borderless fullscreen panel");
    Check(NSEqualRects(viewer.window.frame, viewer.window.screen.frame), @"viewer covers the full screen, including menu bar and dock areas");
    TLTokenView *root = (id)viewer.window.contentView;
    Check(root.fillColor.alphaComponent >= 0.8 && root.fillColor.alphaComponent < 1 && [[viewer valueForKey:@"palette"] dark], @"both app themes use a darker semitransparent backdrop");
    Check(FindChips(root).count == 0, @"carousel has no attachment list or sidebar");
    NSView *preview = [viewer valueForKey:@"previewHost"];
    Check(fabs(NSMidX(preview.frame) - NSMidX(root.bounds)) < 1, @"the file is centered across the full screen");
    Snapshot(root,[NSString stringWithFormat:@"attachment-carousel-%@.png",theme]);
    Check([[viewer valueForKey:@"closeButton"] isKindOfClass:TLHoverIconButton.class], @"fullscreen carousel has an accessible close control");
    TestViewerControlAppearance(viewer,theme);
  }
  TLAttachmentPreviewPanel *panel = (id)viewer.window;
  NSView *textContent = [viewer valueForKey:@"textScroll"];
  Check(!panel.isBackdropPoint([textContent convertPoint:NSMakePoint(30,30) toView:panel.contentView]),@"text selection does not dismiss the preview");
  for (NSString *key in @[@"previousButton",@"nextButton",@"closeButton",@"saveButton",@"finderButton"]) {
    NSView *button = [viewer valueForKey:key];
    Check(!panel.isBackdropPoint([button convertPoint:NSMakePoint(NSMidX(button.bounds),NSMidY(button.bounds)) toView:panel.contentView]),@"preview controls are excluded from backdrop dismissal");
  }
  // Plain arrow keys work even while the native text preview owns focus.
  [viewer.window makeFirstResponder:[viewer valueForKey:@"textView"]];
  NSEvent *right = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:viewer.window.windowNumber context:nil characters:@"\uF703" charactersIgnoringModifiers:@"\uF703" isARepeat:NO keyCode:124];
  [NSApp sendEvent:right]; Check(viewer.selectedIndex == 2, @"right arrow advances the carousel");
  NSEvent *left = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:viewer.window.windowNumber context:nil characters:@"\uF702" charactersIgnoringModifiers:@"\uF702" isARepeat:NO keyCode:123];
  [NSApp sendEvent:left]; Check(viewer.selectedIndex == 1, @"left arrow returns to the previous file");
  [viewer selectItemAtIndex:0];
  deadline = [NSDate dateWithTimeIntervalSinceNow:3];
  while (![viewer valueForKey:@"imageView"] && deadline.timeIntervalSinceNow > 0) Drain();
  Check([(NSImageView *)[viewer valueForKey:@"imageView"] image] != nil, @"images fill the transparent stage without an opaque Quick Look canvas");
  Snapshot(viewer.window.contentView,@"attachment-carousel-image.png");
  NSImageView *imageView = [viewer valueForKey:@"imageView"];
  NSPoint imageCenter = [imageView convertPoint:NSMakePoint(NSMidX(imageView.bounds),NSMidY(imageView.bounds)) toView:panel.contentView];
  ClickPreview(panel,imageCenter); Check(panel.visible,@"clicking the displayed image keeps the preview open");
  NSImage *originalImage = imageView.image;
  for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(300,1600)],[NSValue valueWithSize:NSMakeSize(1600,300)]]) {
    imageView.image = [[NSImage alloc] initWithSize:size.sizeValue];
    NSPoint margin = size.sizeValue.width < size.sizeValue.height ? NSMakePoint(1,NSMidY(imageView.bounds)) : NSMakePoint(NSMidX(imageView.bounds),1);
    Check(panel.isBackdropPoint([imageView convertPoint:margin toView:panel.contentView]),@"portrait and landscape letterboxing dismisses, even inside the full-size image view");
    Check(!panel.isBackdropPoint(imageCenter),@"the displayed image stays interactive at either aspect ratio");
  }
  imageView.image = originalImage;
  NSView *nextButton = [viewer valueForKey:@"nextButton"];
  ClickPreview(panel,[nextButton convertPoint:NSMakePoint(NSMidX(nextButton.bounds),NSMidY(nextButton.bounds)) toView:panel.contentView]);
  Check(panel.visible && viewer.selectedIndex == 1,@"clicking a carousel button navigates without dismissing");
  [viewer selectItemAtIndex:1]; [viewer selectItemAtIndex:3]; Drain();
  Check(![viewer valueForKey:@"textView"] && ![viewer valueForKey:@"preview"], @"late text loads cannot overwrite a new selection");
  Check(![(NSButton *)[viewer valueForKey:@"saveButton"] isEnabled], @"missing files cannot be saved");
  Check([[(NSTextField *)[viewer valueForKey:@"emptyTitle"] stringValue] isEqual:@"File unavailable"], @"missing files have a clear fallback");
  [viewer selectItemAtIndex:2];
  Check([[(NSTextField *)[viewer valueForKey:@"emptyTitle"] stringValue] isEqual:@"Folder attachment"], @"folders have deliberate preview guidance");
  [viewer selectItemAtIndex:0];
  Check(![(NSButton *)[viewer valueForKey:@"previousButton"] isEnabled], @"navigation stops at first file");
  [viewer selectItemAtIndex:3]; Check(![(NSButton *)[viewer valueForKey:@"nextButton"] isEnabled], @"navigation stops at last file");
  [(NSButton *)[viewer valueForKey:@"closeButton"] performClick:nil]; Check(!viewer.window.visible, @"close button dismisses the fullscreen viewer");
  Check(![viewer valueForKey:@"keyMonitor"] && ![viewer valueForKey:@"preview"], @"closing releases keyboard and native preview resources");
  [viewer selectItemAtIndex:0]; [viewer showWindow:nil];
  deadline = [NSDate dateWithTimeIntervalSinceNow:3]; while (![viewer valueForKey:@"imageView"] && deadline.timeIntervalSinceNow > 0) Drain();
  imageView = [viewer valueForKey:@"imageView"];
  NSPoint margin = [imageView convertPoint:NSMakePoint(1,1) toView:panel.contentView];
  ClickPreview(panel,margin);
  Check(!panel.visible && ![viewer valueForKey:@"keyMonitor"] && ![viewer valueForKey:@"imageView"],@"clicking a letterboxed margin closes the panel and releases preview resources");
  [viewer selectItemAtIndex:2]; [viewer showWindow:nil];
  ClickPreview(panel,NSMakePoint(5,5)); Check(!panel.visible,@"clicking the outer backdrop also dismisses empty and folder previews");
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
    TestResolution(base); TestViewer(base); TestTranscript(); TestSharedChipAppearance();
    [NSFileManager.defaultManager removeItemAtURL:base error:nil];
    NSLog(@"AttachmentViewerTests passed");
  }
  return 0;
}
