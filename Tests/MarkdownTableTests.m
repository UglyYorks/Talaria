#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "MarkdownRenderer.h"
#import "Theme.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void Wait(BOOL (^ready)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!ready() && deadline.timeIntervalSinceNow > 0) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  Check(ready(), @"WebKit operation completes");
}

static id Evaluate(WKWebView *web, NSString *script) {
  __block BOOL done = NO;
  __block id value;
  __block NSError *failure;
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    value = result; failure = error; done = YES;
  }];
  Wait(^BOOL { return done; });
  Check(!failure, [NSString stringWithFormat:@"JavaScript succeeds: %@", failure]);
  return value;
}

static void Settle(void) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}

static void Capture(WKWebView *web, TLThemePalette *palette, NSString *name) {
  NSString *directory = NSProcessInfo.processInfo.environment[@"TL_TABLE_PREVIEW_DIR"];
  if (!directory.length) return;
  [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  WKSnapshotConfiguration *configuration = [[WKSnapshotConfiguration alloc] init];
  configuration.rect = NSMakeRect(0, 0, NSWidth(web.bounds), MIN(900, NSHeight(web.bounds)));
  __block BOOL done = NO;
  __block NSImage *snapshot;
  [web takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image, NSError *error) {
    snapshot = image; done = YES;
  }];
  Wait(^BOOL { return done; });
  Check(snapshot != nil, @"table preview snapshot succeeds");
  NSImage *composite = [[NSImage alloc] initWithSize:snapshot.size];
  [composite lockFocus];
  [palette.appContentBackground setFill];
  NSRectFill(NSMakeRect(0, 0, snapshot.size.width, snapshot.size.height));
  [snapshot drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
  [composite unlockFocus];
  NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:composite.TIFFRepresentation];
  Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
    writeToFile:[directory stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES], @"preview saved");
}

static void CheckReadableTable(WKWebView *web) {
  // Inspect actual line boxes: no alphabetic word in a cell should split over lines.
  Check([Evaluate(web,
    @"(()=>{const walker=document.createTreeWalker(document.querySelector('table'),NodeFilter.SHOW_TEXT);"
    @"let node;while(node=walker.nextNode()){for(const match of node.textContent.matchAll(/[A-Za-z]{3,}/g)){"
    @"const range=document.createRange();range.setStart(node,match.index);range.setEnd(node,match.index+match[0].length);"
    @"if(range.getClientRects().length!==1)return false;}}return true;})()") boolValue],
    @"table words remain intact instead of wrapping a few characters per line");
  Check([Evaluate(web, @"document.getElementById('content').scrollWidth<=innerWidth+1 && document.documentElement.scrollWidth<=innerWidth+1") boolValue],
    @"table overflow stays inside the conversation");
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *fixture =
      @"The alternatives I’d look at are:\n\n"
      @"| Alternative | How it compares | Australian availability |\n"
      @"| --- | --- | --- |\n"
      @"| **Toyota Sienta Hybrid** | A compact seven-seat people mover with sliding doors and flexible seating. Worth a look if you want the practicality without a big van. | Available through Japanese-import specialists—not Toyota Australia’s regular new-car range.[13] |\n"
      @"| **Honda Freed Hybrid** | Another compact Japanese people mover worth comparing with the Sienta. | Import route; an Australian importer lists compliance availability for eligible 2024–25 GT5 hybrids. Eligibility depends on the exact variant/build.[9] |\n"
      @"| **Kia PV5 Passenger** | Probably the most interesting upcoming alternative: electric, boxy, sliding doors, and **4,695mm long × 1,895mm wide**. | Reported Australian arrival **October–December 2026**. Seven-seat configuration expected; final local specifications and pricing were not locked in the report. **Not an available-now recommendation**.[7] |\n"
      @"| **VW ID. Buzz** | Similar upright, sliding-door concept, but a wider vehicle: **1,985mm wide**, with lengths of **4,712mm or 4,962mm**. | Officially sold here in five- and seven-seat versions.[6][14] |\n\n"
      @"Text after the table stays in the normal message flow.";
    for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
      NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 900)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
      window.releasedWhenClosed = NO;
      NSView *view = [renderer viewForMarkdown:fixture textColor:palette.assistantMessageText baseFont:palette.messageBodyFont];
      [window.contentView addSubview:view];
      [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
      ]];
      [window.contentView layoutSubtreeIfNeeded];
      WKWebView *web = [view valueForKey:@"webView"];
      Wait(^BOOL { return [[view valueForKey:@"documentReady"] boolValue]; });
      Settle();
      NSString *mode = theme.integerValue == TLThemePreferenceDark ? @"dark" : @"light";
      Capture(web, palette, mode);
      CheckReadableTable(web);
      Check([Evaluate(web, @"document.querySelector('table').getBoundingClientRect().width<=innerWidth+1") boolValue],
        @"comparison fits a regular conversation without scrolling");
      for (NSNumber *width in @[@360, @200]) {
        [window setContentSize:NSMakeSize(width.doubleValue, 900)];
        [window.contentView layoutSubtreeIfNeeded];
        Settle();
        CheckReadableTable(web);
        Check([Evaluate(web,
          @"(()=>{const scroll=document.querySelector('table').parentElement;scroll.scrollLeft=scroll.scrollWidth;"
          @"return (scroll.scrollWidth<=scroll.clientWidth || scroll.scrollLeft>0) && document.querySelector('tr').lastElementChild.getBoundingClientRect().right<=innerWidth+1;})()") boolValue],
          @"the final column remains reachable, scrolling horizontally when the table cannot fit");
        if (width.integerValue == 200) {
          Check([Evaluate(web, @"document.querySelector('table').parentElement.scrollLeft>0") boolValue],
            @"the comparison scrolls instead of crushing columns at the minimum window width");
        }
        Evaluate(web, @"document.querySelector('table').parentElement.scrollLeft=0");
        Capture(web, palette, [NSString stringWithFormat:@"%@-%@", mode, width]);
      }
      // Streaming must apply the same layout without nesting wrappers or reloading WebKit.
      Evaluate(web, @"window.documentIdentity='same'");
      NSString *streaming = @"| Name | Amount |\n| :--- | ---: |\n| Alpha | 42 |\n\n| Item | Note |\n| --- | --- |\n| Beta | Pending";
      [renderer updateMarkdown:streaming inView:view];
      Settle();
      Check([Evaluate(web, @"window.documentIdentity") isEqual:@"same"], @"streaming keeps the existing document");
      Check([Evaluate(web, @"document.querySelectorAll('table').length") integerValue] == 2, @"multiple tables render while streaming");
      Check([Evaluate(web, @"getComputedStyle(document.querySelector('th:last-child')).textAlign==='right'") boolValue], @"Markdown column alignment is preserved");
      Check([Evaluate(web, @"[...document.querySelectorAll('table')].every(t=>t.parentElement.scrollWidth<=t.parentElement.clientWidth+1)") boolValue],
        @"small tables fit without unnecessary scrolling");
      [renderer updateMarkdown:[streaming stringByAppendingString:@" |\n| Gamma | Ready |"] inView:view];
      Settle();
      Check([Evaluate(web, @"document.querySelectorAll('.tl-table-scroll').length===2 && !document.querySelector('.tl-table-scroll .tl-table-scroll')") boolValue],
        @"streaming does not duplicate scroll containers");
      NSString *longToken = [@"identifier" stringByPaddingToLength:240 withString:@"identifier" startingAtIndex:0];
      [renderer updateMarkdown:[NSString stringWithFormat:@"| Name | Value |\n| --- | --- |\n| Link | [Reference](https://example.com) |\n| Code | `%@` |", longToken] inView:view];
      Settle();
      CheckReadableTable(web);
      Check([Evaluate(web, @"document.querySelector('td code').textContent.length") unsignedIntegerValue] == longToken.length, @"long cell values remain complete");
      Check([Evaluate(web, @"document.querySelector('td a').getAttribute('href')") isEqual:@"https://example.com"], @"table links remain intact");
      Check([Evaluate(web, @"(()=>{const scroll=document.querySelector('table').parentElement;scroll.focus();scroll.scrollLeft=100;return document.activeElement===scroll && scroll.scrollLeft>0;})()") boolValue],
        @"overflow remains accessible in a focusable scroll container");
      [window close];
    }
    NSLog(@"MarkdownTableTests passed");
  }
  return 0;
}
