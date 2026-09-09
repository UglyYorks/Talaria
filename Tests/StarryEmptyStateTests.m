#import <AppKit/AppKit.h>
#import "TalariaWindowController.h"
#import "TLChatTabController.h"
#import "TLEmptyStateTips.h"

static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@", message); exit(1); } }
@interface TalariaWindowController (EmptyStateTests)
- (NSView *)buildChatWorkspace;
- (void)renderMessagesScrollingToBottom:(BOOL)scroll;
@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSArray *tips = TLEmptyStateTips();
    Check(tips.count == 20 && [NSSet setWithArray:tips].count == 20, @"twenty distinct tips");
    for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      TLStarryEmptyStateView *sky = [[TLStarryEmptyStateView alloc] initWithFrame:NSMakeRect(0,0,760,500)];
      sky.palette = palette;
      sky.avatar = @"🦉";
      for (NSNumber *width in @[@140, @200, @420, @760, @1600]) {
        sky.frame = NSMakeRect(0,0,width.doubleValue,500);
        for (NSString *tip in tips) {
          sky.tip = tip;
          [sky layoutSubtreeIfNeeded];
          NSTextField *label = [sky valueForKey:@"tipLabel"];
          Check(NSContainsRect(sky.bounds, label.frame), @"tips fit narrow and wide views without clipping");
          CGFloat requiredHeight = label.intrinsicContentSize.height;
          Check(NSHeight(label.frame) >= ceil(requiredHeight), @"wrapped labels display every line");
          Check(![sky hitTest:NSMakePoint(10,10)], @"sky does not intercept input");
        }
      }
      sky.frame = NSMakeRect(0,0,200,500);
      sky.tip = tips.firstObject;
      [sky layoutSubtreeIfNeeded];
      NSBitmapImageRep *narrow = [sky bitmapImageRepForCachingDisplayInRect:sky.bounds];
      [sky cacheDisplayInRect:sky.bounds toBitmapImageRep:narrow];
      [[narrow representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[NSString stringWithFormat:@"build/starry-narrow-%@.png", palette.dark ? @"dark" : @"light"] atomically:YES];
      sky.frame = NSMakeRect(0,0,760,500);
      sky.tip = tips[16];
      [sky layoutSubtreeIfNeeded];
      NSBitmapImageRep *rep = [sky bitmapImageRepForCachingDisplayInRect:sky.bounds];
      [sky cacheDisplayInRect:sky.bounds toBitmapImageRep:rep];
      NSString *path = [NSString stringWithFormat:@"build/starry-%@.png", palette.dark ? @"dark" : @"light"];
      [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
      NSRect quietRect = [[sky valueForKey:@"quietRect"] rectValue];
      NSColor *background = [palette.tabBackground colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      NSColor *ink = [palette.emptyText colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      CGFloat peakContrast = 0;
      for (NSInteger y = 0; y < rep.pixelsHigh; y += 3) {
        for (NSInteger x = 0; x < rep.pixelsWide; x += 3) {
          if (NSPointInRect(NSMakePoint(x * NSWidth(sky.bounds) / rep.pixelsWide,
            y * NSHeight(sky.bounds) / rep.pixelsHigh), quietRect)) continue;
          NSColor *pixel = [[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
          peakContrast = MAX(peakContrast, fabs(pixel.redComponent - background.redComponent));
        }
      }
      Check(peakContrast > 0.01, @"sparkles remain visible in both themes");
      // AppKit composites in its working color space; compare perceived contrast
      // instead of assuming that sRGB channel values blend linearly.
      Check(peakContrast < fabs(ink.redComponent - background.redComponent) * 0.5,
        @"rendered sparkles have less than half the contrast of the old opaque stars");
      NSData *first = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      [sky setValue:@30 forKey:@"frameIndex"];
      [sky cacheDisplayInRect:sky.bounds toBitmapImageRep:rep];
      Check(![first isEqual:[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]], @"sparkles change size between frames");
      sky.hidden = YES;
      Check([sky valueForKey:@"animationTimer"] == nil, @"hidden skies stop animation");

      NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
      window.releasedWhenClosed = NO;
      TalariaWindowController *owner = [[TalariaWindowController alloc] initWithWindow:window];
      [owner setValue:palette forKey:@"palette"];
      TLChatTabController *chat = [TLChatTabController new];
      chat.chat = [TLChatRecord new];
      [owner setValue:chat forKey:@"chatPresentation"];
      chat.chatWorkspace = [owner buildChatWorkspace];
      window.contentView = chat.chatWorkspace;
      [owner renderMessagesScrollingToBottom:NO];
      [window.contentView layoutSubtreeIfNeeded];
      Check(!chat.emptyStateView.hidden, @"empty chat shows the sky");
      NSString *selectedTip = chat.emptyStateView.tip;
      chat.isLoading = YES;
      [owner renderMessagesScrollingToBottom:NO];
      Check(chat.emptyStateView.hidden && chat.messageStack.arrangedSubviews.count == 1, @"loading keeps its status");
      chat.isLoading = NO; chat.errorMessage = @"Connection failed";
      [owner renderMessagesScrollingToBottom:NO];
      Check(chat.emptyStateView.hidden && chat.messageStack.arrangedSubviews.count == 1, @"errors keep their status");
      chat.errorMessage = @"";
      [chat.messages addObject:[TLChatMessage messageWithRole:TLRoleUser content:@"Hello" thinking:nil]];
      [owner renderMessagesScrollingToBottom:NO];
      Check(chat.emptyStateView.hidden, @"first message removes the sky");
      for (NSString *content in [@[@"Hi"] arrayByAddingObjectsFromArray:tips]) {
        [chat.messages removeAllObjects];
        TLChatMessage *message = [TLChatMessage messageWithRole:TLRoleUser content:content thinking:nil];
        [chat.messages addObject:message];
        [owner renderMessagesScrollingToBottom:NO];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *row = [chat.messageRowViews objectForKey:message];
        TLMessageBubbleView *userBubble = nil;
        for (NSView *view in row.subviews) if ([view isKindOfClass:TLMessageBubbleView.class]) userBubble = (id)view;
        sky.frame = NSMakeRect(0,0,700,500);
        sky.availableMessageWidth = chat.messageInputWidthConstraint.constant;
        sky.tip = content;
        [sky layoutSubtreeIfNeeded];
        NSRect tipBubble = [[sky valueForKey:@"bubbleRect"] rectValue];
        Check(userBubble != nil, @"comparison uses a real rendered user bubble");
        Check(fabs(NSWidth(tipBubble) - NSWidth(userBubble.frame)) <= 1,
          [NSString stringWithFormat:@"tip width matches user message: %.1f vs %.1f", NSWidth(tipBubble), NSWidth(userBubble.frame)]);
        Check(fabs(NSHeight(tipBubble) - NSHeight(userBubble.frame)) <= 1,
          [NSString stringWithFormat:@"tip height matches user message: %.1f vs %.1f", NSHeight(tipBubble), NSHeight(userBubble.frame)]);
        NSTextField *tipLabel = [sky valueForKey:@"tipLabel"];
        NSTextField *userLabel = (id)[chat.messageMarkdownViews objectForKey:message];
        Check(fabs(NSWidth(tipLabel.frame) - NSWidth(userLabel.frame)) <= 1,
          @"tip preserves the user label's cell insets so the final word is not clipped");
        NSTextField *avatar = [sky valueForKey:@"avatarLabel"];
        Check(NSMidY(avatar.frame) >= NSMaxY(tipBubble) - 1, @"emoji sits down beside the tail");
        Check(NSMinX(tipBubble) - NSMaxX(avatar.frame) <= palette.space2, @"emoji sits close to the bubble");
      }

      [chat.messages removeAllObjects];
      [owner renderMessagesScrollingToBottom:NO];
      Check(!chat.emptyStateView.hidden && [chat.emptyStateView.tip isEqual:selectedTip], @"renders preserve the selected tip");
      [window close];
    }
    NSLog(@"Starry empty state tests passed.");
  }
  return 0;
}
