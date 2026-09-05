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
  __block id value = nil;
  __block NSError *failure = nil;
  [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    value = result; failure = error; done = YES;
  }];
  Wait(^BOOL { return done; });
  Check(!failure, [NSString stringWithFormat:@"JavaScript succeeds: %@", failure]);
  return value;
}

static void Settle(WKWebView *web) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  Wait(^BOOL { return [Evaluate(web, @"document.fonts.status === 'loaded'") boolValue]; });
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
}

static void Capture(WKWebView *web, NSString *name, TLThemePalette *palette) {
  NSString *directory = NSProcessInfo.processInfo.environment[@"TL_MATH_PREVIEW_DIR"];
  if (!directory.length) return;
  [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  CGFloat height = [Evaluate(web, @"document.getElementById('content').getBoundingClientRect().height") doubleValue];
  for (CGFloat y = 0; y < height; y += 750) {
    WKSnapshotConfiguration *configuration = [[WKSnapshotConfiguration alloc] init];
    configuration.rect = NSMakeRect(0, y, NSWidth(web.bounds), MIN(850, height - y));
    __block NSImage *snapshot = nil;
    __block BOOL done = NO;
    [web takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image, NSError *error) {
      snapshot = image; done = YES;
    }];
    Wait(^BOOL { return done; });
    Check(snapshot != nil, @"formula preview snapshot succeeds");
    NSImage *composite = [[NSImage alloc] initWithSize:snapshot.size];
    [composite lockFocus];
    [palette.messagesSurface setFill];
    NSRectFill(NSMakeRect(0, 0, snapshot.size.width, snapshot.size.height));
    [snapshot drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [composite unlockFocus];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:composite.TIFFRepresentation];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%02ld.png", name, (long)(y / 750 + 1)]];
    Check([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"preview is saved");
  }
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *fixture = [NSString stringWithContentsOfFile:@"Tests/Fixtures/latex-formulas.md" encoding:NSUTF8StringEncoding error:nil];
    Check(fixture.length > 0, @"all screenshot formulas are available");
    for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
      NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 920, 700)
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
      Settle(web);
      Check([Evaluate(web, @"document.querySelectorAll('.katex').length") integerValue] == 24, @"all 24 screenshot formulas typeset");
      Check([Evaluate(web, @"document.querySelectorAll('.katex-error').length") integerValue] == 0, @"no formula has a rendering error");
      Check([Evaluate(web, @"document.querySelectorAll('math').length") integerValue] == 24, @"every formula includes accessible MathML");
      Check([Evaluate(web, @"document.fonts.check('16px KaTeX_Main') && document.fonts.check('16px KaTeX_Math')") boolValue], @"bundled math fonts load");
      Check([Evaluate(web, @"[...document.fonts].some(f=>f.family==='KaTeX_Main' && f.status==='loaded')") boolValue], @"typesetting uses a loaded KaTeX font rather than a fallback");
      Check([Evaluate(web, @"document.querySelectorAll('code').length") integerValue] == 1, @"only the literal equation-environment example remains code");
      NSString *mode = theme.integerValue == TLThemePreferenceDark ? @"dark" : @"light";
      Check([Evaluate(web, @"[...document.querySelectorAll('.tl-math')].every(e=>e.scrollWidth<=e.clientWidth)") boolValue],
            @"fitting equations have no horizontal overflow or spurious scrollbars from glyph overhang");
      Capture(web, [mode stringByAppendingString:@"-wide"], palette);
      for (NSNumber *width in @[@360, @200]) {
        [window setContentSize:NSMakeSize(width.doubleValue, 700)];
        [window.contentView layoutSubtreeIfNeeded];
        Settle(web);
        Check([Evaluate(web, @"document.getElementById('content').scrollWidth <= innerWidth + 1") boolValue],
              [NSString stringWithFormat:@"formulas do not overflow the conversation at %@ points", width]);
        Capture(web, [NSString stringWithFormat:@"%@-%@", mode, width], palette);
      }
      [window setContentSize:NSMakeSize(920, 700)];
      NSString *delimiters = @"Inline $x^2$ and \\(\\frac{a}{b}\\).\n\n$$\n\\sum_{n=1}^{\\infty} n^{-2} = \\frac{\\pi^2}{6}\n$$\n\n\\[\n\\begin{pmatrix}a & b\\\\c & d\\end{pmatrix}\n\\]\n\n```latex\n\\begin{aligned}a &= b+c\\\\d &= e+f\\end{aligned}\n```\n\n`const x = 2;` and `foo_bar` and $5 and $10.\n\n```js\nconst formula = '$x^2$';\n```";
      [renderer updateMarkdown:delimiters inView:view];
      Settle(web);
      Check([Evaluate(web, @"document.querySelectorAll('.katex').length") integerValue] == 5, @"inline, block, bracket, and fenced math all render");
      Check([Evaluate(web, @"document.querySelectorAll('code').length") integerValue] == 3, @"ordinary code and fenced code remain literal");
      Check([Evaluate(web, @"document.body.innerText.includes('$5 and $10')") boolValue], @"currency is not parsed as math");
      Capture(web, [mode stringByAppendingString:@"-delimiters"], palette);
      [window setContentSize:NSMakeSize(200, 700)];
      [window.contentView layoutSubtreeIfNeeded];
      [renderer updateMarkdown:@"$$\\underbrace{a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p}_{\\text{a deliberately wide equation}}$$" inView:view];
      Settle(web);
      Check([Evaluate(web, @"(()=>{const e=document.querySelector('.tl-math-display');e.scrollLeft=100;return e.scrollWidth>e.clientWidth && e.scrollLeft>0;})()") boolValue],
            @"genuinely wide equations remain horizontally scrollable");
      Check([Evaluate(web, @"document.getElementById('content').scrollWidth<=innerWidth+1") boolValue],
            @"wide equation scrolling stays inside the conversation");
      [window setContentSize:NSMakeSize(920, 700)];
      [renderer updateMarkdown:@"> $$\n> \\frac{1}{2}\n> $$\n\nEscaped \\$x^2\\$.\n\n$\\href{javascript:alert(1)}{click}$\n\n$\\includegraphics{https://example.com/image.png}$" inView:view];
      Settle(web);
      Check([Evaluate(web, @"document.querySelectorAll('blockquote .katex').length") integerValue] == 1, @"block math respects Markdown quote boundaries");
      Check([Evaluate(web, @"document.querySelectorAll('a, img').length") integerValue] == 0, @"math cannot create active links or remote images");
      Check([Evaluate(web, @"document.body.innerText.includes('$x^2$')") boolValue], @"escaped math delimiters stay literal");
      Evaluate(web, @"window.documentIdentity = 'same'");
      for (NSString *source in @[@"Streaming $\\frac{1}{", @"Streaming $\\frac{1}{2}$", @"Unknown $\\notACommand{x}$"] ) {
        [renderer updateMarkdown:source inView:view];
        Settle(web);
        Check([Evaluate(web, @"window.documentIdentity") isEqual:@"same"], @"math updates preserve the streaming document");
        Check([Evaluate(web, @"document.querySelectorAll('.katex-error').length") integerValue] == 0, @"incomplete and invalid math stays readable without error markup");
        if ([source hasSuffix:@"2}$"]) Check([Evaluate(web, @"document.querySelectorAll('.katex').length") integerValue] == 1, @"completed streaming expression typesets");
      }
      [window close];
    }
    NSLog(@"MarkdownMathTests passed");
  }
  return 0;
}
