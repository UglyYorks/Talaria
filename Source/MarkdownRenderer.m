#import "MarkdownRenderer.h"
#import "Theme.h"
#import <WebKit/WebKit.h>

@interface TLMarkdownContentWebView : WKWebView
@end

@interface TLMarkdownWebView : NSView <WKNavigationDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic, strong) NSFont *baseFont;
@property (nonatomic, copy, nullable) TLMarkdownLinkHandler linkHandler;
@property (nonatomic) BOOL rendersMarkdown;
@property (nonatomic) BOOL heightUpdateScheduled;
@property (nonatomic) BOOL documentReady;
@property (nonatomic) BOOL contentUpdateScheduled;
@property (nonatomic, copy) void (^heightChangeHandler)(void);
- (void)updateText:(NSString *)text;

- (instancetype)initWithText:(NSString *)text
                     palette:(TLThemePalette *)palette
                   textColor:(NSColor *)textColor
                    baseFont:(NSFont *)baseFont
                  linkHandler:(nullable TLMarkdownLinkHandler)linkHandler
             rendersMarkdown:(BOOL)rendersMarkdown;

@end

@interface TLMarkdownRenderer ()
@property (nonatomic, strong) TLThemePalette *palette;
@end

static NSString *TLCSSColor(NSColor *color);
static NSString *TLJSONString(NSString *string);
static NSString *TLMarkdownItScript(void);
static NSString *TLMarkdownHTML(NSString *text, TLThemePalette *palette, NSColor *textColor, NSFont *baseFont, BOOL rendersMarkdown);

@implementation TLMarkdownRenderer

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super init];
  if (self) {
    _palette = palette;
  }
  return self;
}

- (NSView *)viewForMarkdown:(NSString *)markdown textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont {
  TLMarkdownWebView *view = [[TLMarkdownWebView alloc] initWithText:markdown ?: @""
                                         palette:self.palette
                                       textColor:textColor
                                        baseFont:baseFont
                                     linkHandler:self.linkHandler
                                 rendersMarkdown:YES];
  view.heightChangeHandler = self.heightChangeHandler;
  return view;
}

- (NSView *)viewForPlainText:(NSString *)text textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont {
  return [[TLMarkdownWebView alloc] initWithText:text ?: @""
                                         palette:self.palette
                                       textColor:textColor
                                        baseFont:baseFont
                                     linkHandler:self.linkHandler
                                 rendersMarkdown:NO];
}

- (void)updateMarkdown:(NSString *)markdown inView:(NSView *)view {
  if ([view isKindOfClass:TLMarkdownWebView.class]) { [(TLMarkdownWebView *)view updateText:markdown]; }
}

@end

@implementation TLMarkdownContentWebView

- (void)scrollWheel:(NSEvent *)event {
  if (fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)) {
    NSScrollView *parentScrollView = [self parentScrollView];
    if (parentScrollView) {
      [parentScrollView scrollWheel:event];
      return;
    }
  }

  [super scrollWheel:event];
}

- (NSScrollView *)parentScrollView {
  NSView *view = self.superview;
  while (view) {
    if ([view isKindOfClass:NSScrollView.class]) {
      return (NSScrollView *)view;
    }
    view = view.superview;
  }

  return nil;
}

@end

@implementation TLMarkdownWebView

- (instancetype)initWithText:(NSString *)text
                     palette:(TLThemePalette *)palette
                   textColor:(NSColor *)textColor
                    baseFont:(NSFont *)baseFont
                  linkHandler:(nullable TLMarkdownLinkHandler)linkHandler
             rendersMarkdown:(BOOL)rendersMarkdown {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _text = [text copy];
    _palette = palette;
    _textColor = textColor;
    _baseFont = baseFont;
    _linkHandler = [linkHandler copy];
    _rendersMarkdown = rendersMarkdown;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.suppressesIncrementalRendering = NO;

    _webView = [[TLMarkdownContentWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _webView.translatesAutoresizingMaskIntoConstraints = NO;
    [_webView setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_webView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _webView.navigationDelegate = self;
    _webView.allowsBackForwardNavigationGestures = NO;
    if (@available(macOS 11.0, *)) {
      _webView.underPageBackgroundColor = palette.transparentSurface;
    }
    @try {
      [_webView setValue:@NO forKey:@"drawsBackground"];
    } @catch (NSException *exception) {
    }

    [self addSubview:_webView];
    _heightConstraint = [self.heightAnchor constraintEqualToConstant:24.0];
    _heightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
      [_webView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_webView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_webView.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_webView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    [self loadHTML];
  }
  return self;
}

- (void)setFrameSize:(NSSize)newSize {
  BOOL widthChanged = fabs(newSize.width - self.frame.size.width) > 0.5;
  [super setFrameSize:newSize];
  if (widthChanged) {
    [self scheduleHeightUpdate];
  }
}

- (void)loadHTML {
  self.documentReady = NO;
  NSString *html = TLMarkdownHTML(self.text, self.palette, self.textColor, self.baseFont, self.rendersMarkdown);
  [self.webView loadHTMLString:html baseURL:NSBundle.mainBundle.resourceURL];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  self.documentReady = YES;
  [self updateText:self.text];
  [self scheduleHeightUpdate];
}

- (void)updateText:(NSString *)text {
  self.text = text ?: @"";
  if (!self.documentReady || self.contentUpdateScheduled) { return; }
  self.contentUpdateScheduled = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    TLMarkdownWebView *view = weakSelf;
    if (!view) return;
    view.contentUpdateScheduled = NO;
    NSString *script = [NSString stringWithFormat:@"window.talariaRender(%@)", TLJSONString(view.text)];
    [view.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
      [weakSelf scheduleHeightUpdate];
    }];
  });
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *URL = navigationAction.request.URL;
  if (navigationAction.navigationType == WKNavigationTypeLinkActivated && URL) {
    TLMarkdownLinkHandler linkHandler = [self.linkHandler copy];
    NSEventModifierFlags modifierFlags = navigationAction.modifierFlags;
    decisionHandler(WKNavigationActionPolicyCancel);
    if (linkHandler) {
      dispatch_async(dispatch_get_main_queue(), ^{
        linkHandler(URL, modifierFlags);
      });
    }
    return;
  }

  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)scheduleHeightUpdate {
  if (self.heightUpdateScheduled) {
    return;
  }

  self.heightUpdateScheduled = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.heightUpdateScheduled = NO;
    [self updateHeight];
  });
}

- (void)updateHeight {
  NSString *script =
    @"Math.ceil(Math.max("
    @"document.body.scrollHeight,"
    @"document.documentElement.scrollHeight,"
    @"document.body.offsetHeight,"
    @"document.documentElement.offsetHeight"
    @"));";

  [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    if (error || ![result respondsToSelector:@selector(doubleValue)]) {
      return;
    }

    CGFloat height = MAX(1.0, ceil([result doubleValue]));
    if (fabs(self.heightConstraint.constant - height) < 0.5) {
      return;
    }

    self.heightConstraint.constant = height;
    [self invalidateIntrinsicContentSize];
    [self.superview layoutSubtreeIfNeeded];
    if (self.heightChangeHandler) self.heightChangeHandler();
  }];
}

@end

static NSString *TLCSSColor(NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
  NSInteger red = (NSInteger)lrint(rgb.redComponent * 255.0);
  NSInteger green = (NSInteger)lrint(rgb.greenComponent * 255.0);
  NSInteger blue = (NSInteger)lrint(rgb.blueComponent * 255.0);
  CGFloat alpha = rgb.alphaComponent;
  return [NSString stringWithFormat:@"rgba(%ld, %ld, %ld, %.3f)", (long)red, (long)green, (long)blue, alpha];
}

static NSString *TLJSONString(NSString *string) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:string ?: @""
                                                 options:NSJSONWritingFragmentsAllowed
                                                   error:nil];
  if (!data) {
    return @"\"\"";
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"\"\"";
  return [json stringByReplacingOccurrencesOfString:@"</" withString:@"<\\/"];
}

static NSString *TLMarkdownItScript(void) {
  static NSString *script = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"markdown-it" withExtension:@"min.js"];
    NSString *loadedScript = scriptURL ? [NSString stringWithContentsOfURL:scriptURL
                                                                  encoding:NSUTF8StringEncoding
                                                                     error:nil] : nil;
    loadedScript = loadedScript ?: @"";
    script = [loadedScript stringByReplacingOccurrencesOfString:@"</script" withString:@"<\\/script"];
  });

  return script;
}

static NSString *TLMarkdownHTML(NSString *text, TLThemePalette *palette, NSColor *textColor, NSFont *baseFont, BOOL rendersMarkdown) {
  return [NSString stringWithFormat:
    @"<!doctype html>"
    @"<html>"
    @"<head>"
    @"<meta charset=\"utf-8\">"
    @"<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    @"<style>"
    @"html,body{margin:0;padding:0;background:%@;color:%@;font:%.1fpx -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.48;overflow:hidden;word-break:normal;overflow-wrap:anywhere;}"
    @"body{-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;}"
    @"#content{box-sizing:border-box;width:100%%;max-width:100%%;}"
    @"#content>:first-child{margin-top:0!important;}"
    @"#content>:last-child{margin-bottom:0!important;}"
    @"p{margin:0 0 %.1fpx 0;}"
    @"h1,h2,h3,h4,h5,h6{margin:%.1fpx 0 %.1fpx 0;line-height:1.2;color:%@;font-weight:700;letter-spacing:0;}"
    @"h1{font-size:%.1fpx;}h2{font-size:%.1fpx;}h3{font-size:%.1fpx;}h4,h5,h6{font-size:%.1fpx;}"
    @"strong{font-weight:700;}em{font-style:italic;}s{text-decoration:line-through;}"
    @"a{color:%@;text-decoration:underline;text-underline-offset:2px;}"
    @"ul,ol{margin:0 0 %.1fpx 1.35em;padding-left:1.1em;}"
    @"li{margin:%.1fpx 0;padding-left:.15em;}"
    @"li>p{margin:0;}"
    @"blockquote{margin:0 0 %.1fpx 0;padding:0 0 0 %.1fpx;border-left:%.1fpx solid %@;color:%@;}"
    @"pre{box-sizing:border-box;margin:0 0 %.1fpx 0;padding:%.1fpx %.1fpx;background:%@;border:%.1fpx solid %@;border-radius:%.1fpx;overflow-x:auto;white-space:pre;}"
    @"code{font:%.1fpx ui-monospace,SFMono-Regular,SF Mono,Menlo,Consolas,monospace;color:%@;background:%@;border-radius:4px;padding:1px 4px;}"
    @"pre code{display:block;padding:0;background:%@;color:%@;white-space:pre;overflow-wrap:normal;}"
    @"table{box-sizing:border-box;width:100%%;border-collapse:collapse;margin:0 0 %.1fpx 0;table-layout:auto;}"
    @"th,td{border:%.1fpx solid %@;padding:%.1fpx %.1fpx;text-align:left;vertical-align:top;}"
    @"th{background:%@;font-weight:700;}"
    @"tr:nth-child(even) td{background:%@;}"
    @"hr{border:0;border-top:%.1fpx solid %@;margin:%.1fpx 0;}"
    @"img{max-width:100%%;height:auto;border-radius:%.1fpx;}"
    @".plain{white-space:pre-wrap;}"
    @".task-list-item{list-style:none;margin-left:-1.2em;}"
    @".task-list-item input{margin-right:.45em;vertical-align:-1px;}"
    @"</style>"
    @"</head>"
    @"<body>"
    @"<div id=\"content\"></div>"
    @"<script>%@</script>"
    @"<script>"
    @"const initialSource=%@;"
    @"window.talariaRender=function(source){"
    @"const content=document.getElementById('content');"
    @"if(%@&&window.markdownit){"
    @"const md=window.markdownit({html:false,linkify:true,typographer:false,breaks:false});"
    @"content.innerHTML=md.render(source);"
    @"document.querySelectorAll('li').forEach((li)=>{"
    @"const walker=document.createTreeWalker(li,NodeFilter.SHOW_TEXT);"
    @"const node=walker.nextNode();"
    @"if(!node)return;"
    @"const match=node.nodeValue.match(/^\\s*\\[([ xX])\\]\\s+/);"
    @"if(!match)return;"
    @"node.nodeValue=node.nodeValue.slice(match[0].length);"
    @"const box=document.createElement('input');box.type='checkbox';box.disabled=true;box.checked=match[1].toLowerCase()==='x';"
    @"li.classList.add('task-list-item');li.insertBefore(box,li.firstChild);"
    @"});"
    @"document.querySelectorAll('a').forEach((a)=>{a.target='_blank';a.rel='noopener noreferrer';});"
    @"}else{content.className='plain';content.textContent=source;}"
    @"};window.talariaRender(initialSource);"
    @"</script>"
    @"</body>"
    @"</html>",
    TLCSSColor(palette.transparentSurface),
    TLCSSColor(textColor),
    baseFont.pointSize,
    palette.space5,
    palette.space6,
    palette.space4,
    TLCSSColor(textColor),
    palette.markdownHeading1Font.pointSize,
    palette.markdownHeading2Font.pointSize,
    palette.markdownHeading3Font.pointSize,
    palette.bodyFont.pointSize,
    TLCSSColor(palette.markdownLinkText),
    palette.space5,
    palette.space2,
    palette.space5,
    palette.space6,
    palette.borderWidth * 3.0,
    TLCSSColor(palette.markdownQuoteBorder),
    TLCSSColor(palette.markdownQuoteText),
    palette.space5,
    palette.space5,
    palette.space6,
    TLCSSColor(palette.markdownCodeSurface),
    palette.borderWidth,
    TLCSSColor(palette.markdownCodeBorder),
    palette.radiusMedium,
    palette.markdownCodeFont.pointSize,
    TLCSSColor(palette.markdownCodeText),
    TLCSSColor(palette.markdownCodeSurface),
    TLCSSColor(palette.transparentSurface),
    TLCSSColor(palette.markdownCodeText),
    palette.space5,
    palette.borderWidth,
    TLCSSColor(palette.markdownTableBorder),
    palette.space4,
    palette.space5,
    TLCSSColor(palette.markdownTableHeaderSurface),
    TLCSSColor(palette.markdownTableAlternateRowSurface),
    palette.borderWidth,
    TLCSSColor(palette.markdownTableBorder),
    palette.space6,
    palette.radiusMedium,
    TLMarkdownItScript(),
    TLJSONString(text),
    rendersMarkdown ? @"true" : @"false"];
}
