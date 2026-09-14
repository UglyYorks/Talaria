#import "TLMarkdownEditorView.h"
#import "TLThemedButton.h"
#import <WebKit/WebKit.h>

@interface TLMarkdownMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> target;
@end
@implementation TLMarkdownMessageHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface TLMarkdownEditorView () <WKScriptMessageHandler, WKNavigationDelegate, NSTextViewDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSScrollView *toolbarScroll, *sourceScroll;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSTextView *sourceView;
@property (nonatomic, strong) NSTextField *notice;
@property (nonatomic, strong) TLThemedButton *modeButton;
@property (nonatomic, copy) NSArray<TLThemedButton *> *formatButtons;
@property (nonatomic) NSUInteger epoch, sequence;
@property (nonatomic, copy) NSString *selectedLink;
@property (nonatomic) BOOL pageReady, ready, sourceMode, sourceRequired, closed, syncing;
@end

static NSString *TLEditorCSSColor(NSColor *color) {
  NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  return [NSString stringWithFormat:@"rgba(%ld,%ld,%ld,%.3f)", (long)lround(rgb.redComponent * 255),
    (long)lround(rgb.greenComponent * 255), (long)lround(rgb.blueComponent * 255), rgb.alphaComponent];
}

@implementation TLMarkdownEditorView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _string = @""; self.wantsLayer = YES;
    self.toolbar = [NSView new];
    self.toolbarScroll = [NSScrollView new]; self.toolbarScroll.drawsBackground = NO;
    self.toolbarScroll.hasHorizontalScroller = YES; self.toolbarScroll.autohidesScrollers = YES;
    self.toolbarScroll.documentView = self.toolbar; [self addSubview:self.toolbarScroll];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSArray *item in @[@[@"Bold",@"bold"], @[@"Italic",@"italic"], @[@"H1",@"title"], @[@"H2",@"heading"],
      @[@"List",@"bullet"], @[@"1. List",@"ordered"], @[@"Tasks",@"task"], @[@"Quote",@"quote"],
      @[@"Code",@"code"], @[@"Link",@"link"], @[@"Table",@"table"], @[@"Undo",@"undo"], @[@"Redo",@"redo"]]) {
      TLThemedButton *button = [TLThemedButton buttonWithTitle:item[0] target:self action:@selector(format:)];
      button.identifier = item[1]; button.toolTip = item[0]; [self.toolbar addSubview:button]; [buttons addObject:button];
    }
    self.formatButtons = buttons;
    self.modeButton = [TLThemedButton buttonWithTitle:@"Markdown" target:self action:@selector(toggleSource:)];
    self.modeButton.toolTip = @"Switch between formatted editing and Markdown source";
    [self addSubview:self.modeButton];
    self.notice = [NSTextField labelWithString:@""]; self.notice.hidden = YES; [self addSubview:self.notice];
    self.sourceView = [NSTextView new]; self.sourceView.richText = NO; self.sourceView.allowsUndo = YES;
    self.sourceView.delegate = self; self.sourceView.autoresizingMask = NSViewWidthSizable;
    self.sourceView.verticallyResizable = YES; self.sourceView.horizontallyResizable = NO;
    self.sourceView.textContainer.widthTracksTextView = YES;
    self.sourceView.automaticQuoteSubstitutionEnabled = NO; self.sourceView.automaticDashSubstitutionEnabled = NO;
    self.sourceView.accessibilityLabel = @"Markdown source";
    self.sourceScroll = [NSScrollView new]; self.sourceScroll.hasVerticalScroller = YES;
    self.sourceScroll.autohidesScrollers = YES; self.sourceScroll.documentView = self.sourceView;
    [self addSubview:self.sourceScroll];
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    TLMarkdownMessageHandler *handler = [TLMarkdownMessageHandler new]; handler.target = self;
    [config.userContentController addScriptMessageHandler:handler name:@"notesEditor"];
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    self.webView.navigationDelegate = self; [self addSubview:self.webView];
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    [self loadPage]; [self updateControls];
  }
  return self;
}
- (NSString *)resource:(NSString *)name {
  NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:nil];
  if (!url) {
    NSURL *directory = NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent;
    // Native test executables receive resources next to the executable.
    NSURL *candidate = [directory URLByAppendingPathComponent:name];
    if ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) url = candidate;
  }
  return url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
}
- (void)loadPage {
  NSString *dependencies = [self resource:@"notes-editor.min.js"], *script = [self resource:@"NotesEditor.js"], *css = [self resource:@"NotesEditor.css"];
  if (!dependencies || !script || !css) { [self showSourceError:@"The formatted editor could not load. Your Markdown is available below."]; return; }
  dependencies = [dependencies stringByReplacingOccurrencesOfString:@"</script" withString:@"<\\/script"];
  script = [script stringByReplacingOccurrencesOfString:@"</script" withString:@"<\\/script"];
  NSString *html = [NSString stringWithFormat:@"<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src https: http: data:;\"><style>%@</style></head><body><div id='editor'></div><script>%@</script><script>%@</script></body></html>", css, dependencies, script];
  [self.webView loadHTMLString:html baseURL:nil];
}
- (void)evaluate:(NSString *)body arguments:(NSDictionary *)arguments completion:(void (^)(id, NSError *))completion {
  [self.webView callAsyncJavaScript:body arguments:arguments inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:completion];
}
- (void)setString:(NSString *)string {
  _string = [string copy] ?: @""; self.epoch++; self.sequence = 0; self.ready = NO;
  self.sourceRequired = NO; self.sourceView.string = _string; [self.sourceView.undoManager removeAllActions];
  if (self.pageReady) { self.sourceMode = NO; [self loadDocument]; }
  [self updateControls];
}
- (void)loadDocument {
  NSUInteger epoch = self.epoch;
  __weak typeof(self) weakSelf = self;
  [self evaluate:@"return TalariaNotes.load(markdown, epoch, editable)" arguments:@{@"markdown":self.string,@"epoch":@(epoch),@"editable":@(self.editable)}
    completion:^(id result, NSError *error) {
      typeof(self) self = weakSelf;
      if (!self || self.closed || epoch != self.epoch) return;
      if (error || ![result isKindOfClass:NSDictionary.class]) { [self showSourceError:@"The formatted editor could not load. Your Markdown is available below."]; return; }
      self.ready = YES; self.sourceRequired = [result[@"sourceRequired"] boolValue];
      if (self.sourceRequired) self.sourceMode = YES;
      self.notice.stringValue = self.sourceRequired ? @"Embedded HTML, reference definitions or metadata is preserved in Markdown view." : @"";
      self.notice.toolTip = self.notice.stringValue;
      [self updateControls]; [self applyWebTheme];
    }];
}
- (void)receiveSnapshot:(NSDictionary *)snapshot {
  if (self.closed || [snapshot[@"epoch"] unsignedIntegerValue] != self.epoch || [snapshot[@"composing"] boolValue] ||
      [snapshot[@"sequence"] unsignedIntegerValue] <= self.sequence || ![snapshot[@"markdown"] isKindOfClass:NSString.class]) return;
  self.sequence = [snapshot[@"sequence"] unsignedIntegerValue];
  NSString *markdown = snapshot[@"markdown"];
  if (![self.string isEqual:markdown]) {
    _string = [markdown copy]; self.sourceView.string = markdown;
    if (self.changeHandler) self.changeHandler();
  }
  self.selectedLink = [snapshot[@"href"] isKindOfClass:NSString.class] ? snapshot[@"href"] : @"";
  [self applySelection:snapshot[@"state"]];
}
- (BOOL)finishEditing {
  if (self.sourceMode || !self.ready || self.closed) return YES;
  if (self.syncing) return NO;
  self.syncing = YES;
  __block BOOL finished = NO, success = NO;
  NSUInteger epoch = self.epoch;
  __weak typeof(self) weakSelf = self;
  [self evaluate:@"return TalariaNotes.snapshot()" arguments:@{} completion:^(id result, NSError *error) {
    typeof(self) self = weakSelf;
    success = self && !error && epoch == self.epoch && [result isKindOfClass:NSDictionary.class] && ![result[@"composing"] boolValue];
    if (success) [self receiveSnapshot:result];
    finished = YES;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
  while (!finished && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
  self.syncing = NO;
  return finished && success;
}
- (void)setEditable:(BOOL)editable { _editable = editable; [self updateControls]; }
- (void)updateControls {
  self.sourceScroll.hidden = !self.sourceMode; self.webView.hidden = self.sourceMode || !self.ready;
  self.sourceView.editable = self.editable && !self.closed;
  self.modeButton.title = self.sourceMode ? @"Formatted" : @"Markdown";
  self.modeButton.enabled = !self.closed && self.ready && !self.sourceRequired;
  self.notice.hidden = !self.notice.stringValue.length;
  for (TLThemedButton *button in self.formatButtons) button.enabled = self.editable && self.ready && !self.sourceMode && !self.closed;
  if (self.ready) [self evaluate:@"TalariaNotes.setEditable(editable)" arguments:@{@"editable":@(self.editable && !self.sourceMode && !self.closed)} completion:nil];
  self.needsLayout = YES;
}
- (void)toggleSource:(id)sender {
  if (![self finishEditing]) return;
  self.sourceMode = !self.sourceMode;
  if (!self.sourceMode) { self.epoch++; self.sequence = 0; [self loadDocument]; }
  [self updateControls]; [self focusEditor];
}
- (void)format:(TLThemedButton *)button {
  if (!self.ready || !self.editable || self.sourceMode) return;
  NSString *value = @"";
  if ([button.identifier isEqual:@"link"]) {
    if (![self finishEditing]) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"Edit link";
    alert.informativeText = @"Enter a web or email address for the selected text. Leave it empty to remove the link.";
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,self.palette.settingsCompactWidth,self.palette.settingsActionHeight)];
    field.placeholderString = @"https://example.com"; field.stringValue = self.selectedLink ?: @""; alert.accessoryView = field;
    [alert addButtonWithTitle:@"Apply"]; [alert addButtonWithTitle:@"Cancel"];
    while (YES) {
      if ([alert runModal] != NSAlertFirstButtonReturn) return;
      value = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (!value.length || [@[@"https",@"http",@"mailto"] containsObject:[NSURL URLWithString:value].scheme.lowercaseString]) break;
      alert.informativeText = @"Use an address beginning with https://, http:// or mailto:. Leave it empty to remove the link.";
    }
  }
  [self evaluate:@"TalariaNotes.command(command, value)" arguments:@{@"command":button.identifier,@"value":value} completion:nil];
}
- (void)applySelection:(NSDictionary *)selection {
  if (![selection isKindOfClass:NSDictionary.class]) return;
  for (TLThemedButton *button in self.formatButtons) button.primary = [selection[button.identifier] boolValue];
}
- (void)textDidChange:(NSNotification *)notification {
  if (self.closed || !self.sourceMode) return;
  _string = [self.sourceView.string copy]; if (self.changeHandler) self.changeHandler();
}
- (void)focusEditor {
  if (self.sourceMode) [self.window makeFirstResponder:self.sourceView];
  else if (self.ready) { [self.window makeFirstResponder:self.webView]; [self evaluate:@"TalariaNotes.focus()" arguments:@{} completion:nil]; }
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [self focusEditor]; return YES; }
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  if (self.closed || !message.frameInfo.isMainFrame || ![message.body isKindOfClass:NSDictionary.class]) return;
  NSDictionary *body = message.body;
  if ([body[@"type"] isEqual:@"ready"]) { self.pageReady = YES; [self loadDocument]; }
  else if ([body[@"type"] isEqual:@"change"] && !self.sourceMode) [self receiveSnapshot:body];
  else if ([body[@"type"] isEqual:@"selection"] && [body[@"epoch"] unsignedIntegerValue] == self.epoch) [self applySelection:body[@"state"]];
}
- (void)showSourceError:(NSString *)message {
  self.ready = NO; self.sourceMode = YES; self.notice.stringValue = message; self.notice.toolTip = message; [self updateControls];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
  self.pageReady = NO; [self showSourceError:@"The formatted editor stopped. Your latest available draft is available in Markdown view."];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  decisionHandler([action.request.URL.absoluteString isEqual:@"about:blank"] && action.navigationType == WKNavigationTypeOther ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.layer.backgroundColor = palette.controlSurface.CGColor;
  for (TLThemedButton *button in self.formatButtons) button.palette = palette;
  self.modeButton.palette = palette; self.notice.font = palette.smallFont; self.notice.textColor = palette.textMuted;
  self.sourceView.font = palette.markdownCodeFont; self.sourceView.textColor = palette.controlText;
  self.sourceView.backgroundColor = palette.controlSurface; self.sourceScroll.backgroundColor = palette.controlSurface;
  self.sourceView.insertionPointColor = palette.controlText;
  self.sourceView.selectedTextAttributes = @{NSBackgroundColorAttributeName:palette.itemHighlightSurface, NSForegroundColorAttributeName:palette.controlText};
  self.sourceView.textContainerInset = NSMakeSize(palette.space12, palette.space12);
  [self applyWebTheme]; self.needsLayout = YES;
}
- (void)applyWebTheme {
  if (!self.pageReady) return;
  TLThemePalette *p = self.palette;
  NSMutableDictionary *tokens = [@{@"surface":TLEditorCSSColor(p.controlSurface),@"text":TLEditorCSSColor(p.controlText),
    @"link":TLEditorCSSColor(p.markdownLinkText),@"border":TLEditorCSSColor(p.controlBorder),@"focus":TLEditorCSSColor(p.controlFocus),
    @"selection":TLEditorCSSColor(p.itemHighlightSurface),@"selection-text":TLEditorCSSColor(p.controlText),
    @"quote-border":TLEditorCSSColor(p.markdownQuoteBorder),@"quote-text":TLEditorCSSColor(p.markdownQuoteText),
    @"code-surface":TLEditorCSSColor(p.markdownCodeSurface),@"code-text":TLEditorCSSColor(p.markdownCodeText),@"code-border":TLEditorCSSColor(p.markdownCodeBorder),
    @"table-border":TLEditorCSSColor(p.markdownTableBorder),@"table-header":TLEditorCSSColor(p.markdownTableHeaderSurface)} mutableCopy];
  NSDictionary *sizes = @{@"font":@(p.bodyFont.pointSize),@"code-font":@(p.markdownCodeFont.pointSize),@"h1":@(p.markdownHeading1Font.pointSize),
    @"h2":@(p.markdownHeading2Font.pointSize),@"h3":@(p.markdownHeading3Font.pointSize),@"inset":@(p.space12),@"gap":@(p.space8),
    @"small-gap":@(p.space2),@"indent":@(p.space16 * 2),@"radius":@(p.radiusMedium)};
  for (NSString *key in sizes) tokens[key] = [NSString stringWithFormat:@"%@px",sizes[key]];
  [self evaluate:@"TalariaNotes.theme(tokens)" arguments:@{@"tokens":tokens} completion:nil];
}
- (void)layout {
  [super layout]; TLThemePalette *p = self.palette;
  CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds), bar = p.settingsActionHeight + p.space12;
  CGFloat modeWidth = MIN(width, self.modeButton.intrinsicContentSize.width);
  self.modeButton.frame = NSMakeRect(MAX(0,width-modeWidth),MAX(0,height-p.settingsActionHeight),modeWidth,p.settingsActionHeight);
  self.toolbarScroll.frame = NSMakeRect(0,MAX(0,height-bar),MAX(0,width-modeWidth-p.space4),bar);
  CGFloat x = 0;
  for (TLThemedButton *button in self.formatButtons) {
    CGFloat w = button.intrinsicContentSize.width;
    button.frame = NSMakeRect(x,0,w,p.settingsActionHeight); x += w+p.space4;
  }
  self.toolbar.frame = NSMakeRect(0,0,MAX(x,NSWidth(self.toolbarScroll.bounds)),p.settingsActionHeight);
  CGFloat noticeHeight = self.notice.hidden ? 0 : p.settingsActionHeight;
  self.notice.frame = NSMakeRect(0,MAX(0,height-bar-noticeHeight),width,noticeHeight);
  NSRect content = NSMakeRect(0,0,width,MAX(0,height-bar-noticeHeight));
  self.webView.frame = self.sourceScroll.frame = content;
  self.sourceView.minSize = NSMakeSize(0,self.sourceScroll.contentSize.height);
  self.sourceView.maxSize = NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
  self.sourceView.frame = NSMakeRect(0,0,width,MAX(self.sourceView.frame.size.height,self.sourceScroll.contentSize.height));
  self.sourceView.textContainer.containerSize = NSMakeSize(width,CGFLOAT_MAX);
}
- (void)close {
  self.closed = YES; self.changeHandler = nil; [self.webView stopLoading];
  [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"notesEditor"];
  self.webView.navigationDelegate = nil;
}
@end
