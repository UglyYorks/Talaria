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

static void CheckSyntaxColor(WKWebView *web, NSString *selector, NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  NSString *expected = [NSString stringWithFormat:@"rgb(%ld, %ld, %ld)",
    (long)lrint(rgb.redComponent * 255), (long)lrint(rgb.greenComponent * 255), (long)lrint(rgb.blueComponent * 255)];
  NSString *script = [NSString stringWithFormat:@"getComputedStyle(document.querySelector('%@')).color", selector];
  Check([Evaluate(web, script) isEqual:expected], [NSString stringWithFormat:@"%@ uses its active syntax palette token", selector]);
}

static void Settle(void) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}

static void Capture(WKWebView *web, TLThemePalette *palette, NSString *name) {
  NSString *directory = NSProcessInfo.processInfo.environment[@"TL_CODE_PREVIEW_DIR"];
  if (!directory.length) return;
  [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  WKSnapshotConfiguration *configuration = [[WKSnapshotConfiguration alloc] init];
  configuration.rect = NSMakeRect(0, 0, NSWidth(web.bounds), MIN(700, NSHeight(web.bounds)));
  __block BOOL done = NO;
  __block NSImage *snapshot;
  [web takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image, NSError *error) {
    snapshot = image; done = YES;
  }];
  Wait(^BOOL { return done; });
  Check(snapshot != nil, @"code preview snapshot succeeds");
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

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSMutableArray *savedItems = [NSMutableArray array];
    for (NSPasteboardItem *item in pasteboard.pasteboardItems) {
      NSPasteboardItem *saved = [[NSPasteboardItem alloc] init];
      for (NSPasteboardType type in item.types) {
        NSData *data = [item dataForType:type];
        if (data) [saved setData:data forType:type];
      }
      [savedItems addObject:saved];
    }
    atexit_b(^{
      [pasteboard clearContents];
      if (savedItems.count) [pasteboard writeObjects:savedItems];
    });
    for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:theme.integerValue];
      TLMarkdownRenderer *renderer = [[TLMarkdownRenderer alloc] initWithPalette:palette];
      NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 700)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
      window.releasedWhenClosed = NO;
      NSString *fixture = @"# Code examples\n\n```python\n# Find the next task\nclass Task: pass\n\ndef next_task(tasks):\n    return sorted(tasks, key=lambda t: t.priority)[0]\n\nprint(\"Hello, world!\")\n```\n\n```javascript\nconst debounce = (fn, ms = 300) => {\n  let timeout;\n  return (...args) => {\n    clearTimeout(timeout);\n    timeout = setTimeout(() => fn(...args), ms);\n  };\n};\n```\n\n```sql\nSELECT name FROM tasks WHERE done = false LIMIT 10;\n```";
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
      Check([Evaluate(web, @"hljs.listLanguages().length") integerValue] == 192, @"all bundled languages are available offline");
      Check([Evaluate(web, @"[...document.querySelectorAll('pre code')].every(e=>e.querySelector('.hljs-keyword'))") boolValue], @"Python, JavaScript and SQL receive highlighting");
      Check([Evaluate(web, @"document.querySelectorAll('.tl-code-copy').length") integerValue] == 3, @"one copy button per block");
      CheckSyntaxColor(web, @"pre .hljs-keyword", palette.markdownSyntaxKeyword);
      CheckSyntaxColor(web, @"pre .hljs-string", palette.markdownSyntaxString);
      CheckSyntaxColor(web, @"pre .hljs-number", palette.markdownSyntaxNumber);
      CheckSyntaxColor(web, @"pre .hljs-title.function_", palette.markdownSyntaxFunction);
      CheckSyntaxColor(web, @"pre .hljs-comment", palette.markdownSyntaxComment);
      CheckSyntaxColor(web, @"pre .hljs-title.class_", palette.markdownSyntaxType);
      NSString *mode = theme.integerValue == TLThemePreferenceDark ? @"dark" : @"light";
      Capture(web, palette, mode);
      for (NSNumber *width in @[@200, @360]) {
        [window setContentSize:NSMakeSize(width.doubleValue, 700)];
        [window.contentView layoutSubtreeIfNeeded];
        Settle();
        Check([Evaluate(web, @"document.getElementById('content').scrollWidth<=innerWidth+1") boolValue], @"code stays inside narrow conversations");
        Check([Evaluate(web, @"[...document.querySelectorAll('.tl-code-copy')].every(b=>b.getBoundingClientRect().right<=innerWidth)") boolValue], @"copy controls stay visible at narrow widths");
        Check([Evaluate(web, @"(()=>{const p=document.querySelector('pre');p.scrollLeft=100;return p.scrollLeft>0;})()") boolValue], @"long lines scroll independently");
        Evaluate(web, @"document.querySelector('pre').scrollLeft=0");
        Capture(web, palette, [NSString stringWithFormat:@"%@-%@", mode, width]);
      }
      Check([Evaluate(web, @"['py','js','jsx','ts','tsx','c','c++','c#','java','go','rust','swift','kotlin','objective-c','php','ruby','sh','bash','powershell','html','xml','css','scss','json','yaml','sql','r','scala','dart','lua','perl','elixir','erlang','haskell','clojure','fsharp','julia','matlab','groovy','dockerfile','makefile','cmake','graphql','protobuf','toml','diff'].every(l=>!!hljs.getLanguage(l))") boolValue], @"popular languages and aliases are registered");
      NSString *literal = @"\tprint(\"<script>alert('x')</script> & café 🚀\")\n\n";
      [renderer updateMarkdown:[NSString stringWithFormat:@"```PY title=example\n%@```\n\n```unknown-language\n<em>literal</em>\n```\n\n```\nunlabelled\n```\n\n    indented\n\nInline `ordinary`.", literal] inView:view];
      Settle();
      Check([Evaluate(web, @"document.querySelector('pre code').textContent") isEqual:literal], @"highlighting preserves tabs, blank lines, Unicode and literal markup");
      Check([Evaluate(web, @"document.querySelectorAll('.tl-code-copy').length") integerValue] == 4, @"fenced and indented blocks have controls; inline code does not");
      Check([Evaluate(web, @"!document.querySelector('pre script, pre em') && document.querySelectorAll('pre')[1].textContent==='<em>literal</em>\\n'") boolValue], @"unknown language code remains escaped");
      Check([Evaluate(web, @"document.querySelector('pre code .hljs-built_in')!==null") boolValue], @"language aliases, uppercase labels and fence metadata work");
      Evaluate(web, @"document.querySelector('.tl-code-copy').click()");
      Wait(^BOOL { return [Evaluate(web, @"document.querySelector('.tl-code-copy').textContent") isEqual:@"Copied!"]; });
      Check([[pasteboard stringForType:NSPasteboardTypeString] isEqual:literal], @"native copy preserves exact source without toolbar or syntax markup");
      Evaluate(web, @"window.documentIdentity='same'");
      [renderer updateMarkdown:@"```js\nconst latest = 'streaming';" inView:view];
      Settle();
      Check([Evaluate(web, @"window.documentIdentity") isEqual:@"same"], @"streaming updates keep the web document");
      Check([Evaluate(web, @"document.querySelectorAll('.tl-code-copy').length") integerValue] == 1, @"streaming does not duplicate copy controls");
      Evaluate(web, @"document.querySelector('.tl-code-copy').click()");
      Wait(^BOOL { return [Evaluate(web, @"document.querySelector('.tl-code-copy').textContent") isEqual:@"Copied!"]; });
      Check([[pasteboard stringForType:NSPasteboardTypeString] isEqual:@"const latest = 'streaming';"], @"copy follows the current incomplete code fence");
      // A rejected native request must not overwrite the clipboard.
      Evaluate(web, @"window.copyRejected=false;webkit.messageHandlers.talariaCopyCode.postMessage({bad:true}).catch(()=>window.copyRejected=true);void 0");
      Wait(^BOOL { return [Evaluate(web, @"window.copyRejected") boolValue]; });
      Check([[pasteboard stringForType:NSPasteboardTypeString] isEqual:@"const latest = 'streaming';"], @"invalid clipboard messages are rejected");
      Evaluate(web, @"webkit.messageHandlers.talariaCopyCode.postMessage=()=>Promise.reject(new Error('clipboard unavailable'));document.querySelector('.tl-code-copy').click()");
      Wait(^BOOL { return [Evaluate(web, @"document.querySelector('.tl-code-copy').textContent") isEqual:@"Retry copy"]; });
      Check([Evaluate(web, @"!document.querySelector('.tl-code-copy').disabled") boolValue], @"failed copies can be retried");
      [window close];
    }
    NSLog(@"MarkdownCodeTests passed");
  }
  return 0;
}
