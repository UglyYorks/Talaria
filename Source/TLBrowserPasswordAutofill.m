#import "TLBrowserPasswordAutofill.h"
#import "Theme.h"

static WKContentWorld *TLPasswordWorld(void) { return [WKContentWorld worldWithName:@"talaria-password-autofill"]; }
static BOOL TLSecurePasswordURL(NSURL *URL) {
  return [URL.scheme.lowercaseString isEqual:@"https"] && URL.host.length && !URL.user && !URL.password;
}

@interface TLBrowserPasswordAutofill () <WKScriptMessageHandler, NSTextFieldDelegate>
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic) WKFrameInfo *frame;
@property (nonatomic) NSString *token;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSAlert *alert;
@property (nonatomic) NSTextField *username;
@property (nonatomic) NSSecureTextField *password;
@property (nonatomic) BOOL stopped;
@property (nonatomic) BOOL requiresPassword;
@end

// WKUserContentController retains its message handlers. The owner is a session.
@interface TLPasswordMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) TLBrowserPasswordAutofill *owner;
@end
@implementation TLPasswordMessageHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.owner userContentController:controller didReceiveScriptMessage:message];
}
@end

@implementation TLBrowserPasswordAutofill
- (instancetype)initWithWebView:(WKWebView *)webView {
  if (!(self = [super init])) return nil;
  _webView = webView;
  NSURL *URL = [NSBundle.mainBundle URLForResource:@"BrowserPasswordAutofill" withExtension:@"js"];
  NSString *source = URL ? [NSString stringWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:nil] : nil;
  if (!source.length) return self;
  TLPasswordMessageHandler *handler = [TLPasswordMessageHandler new]; handler.owner = self;
  WKUserContentController *content = webView.configuration.userContentController;
  [content addScriptMessageHandler:handler contentWorld:TLPasswordWorld() name:@"talariaPasswordAutofill"];
  [content addUserScript:[[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO inContentWorld:TLPasswordWorld()]];
  return self;
}
- (BOOL)available {
  WKSecurityOrigin *origin = self.frame.securityOrigin;
  NSURL *URL = self.frame.request.URL;
  return !self.stopped && !self.alert && !self.webView.loading && self.token.length &&
    TLSecurePasswordURL(self.webView.URL) && TLSecurePasswordURL(URL) &&
    [origin.protocol isEqual:@"https"] && [origin.host.lowercaseString isEqual:URL.host.lowercaseString] &&
    (origin.port ?: 443) == (URL.port.integerValue ?: 443);
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  if (self.stopped || message.webView != self.webView || ![message.body isKindOfClass:NSDictionary.class]) return;
  NSDictionary *body = message.body;
  if (![body[@"token"] isKindOfClass:NSString.class]) return;
  if ([body[@"available"] boolValue]) {
    self.frame = message.frameInfo; self.token = body[@"token"];
  } else if (message.frameInfo.isMainFrame || [self.token isEqual:body[@"token"]]) {
    self.frame = nil; self.token = nil;
  }
}
- (void)present {
  if (!self.available || !self.webView.window || self.webView.window.attachedSheet) return;
  WKFrameInfo *frame = self.frame; NSString *token = self.token;
  NSURL *pageURL = self.webView.URL;
  NSUInteger generation = ++self.generation;
  [self.webView callAsyncJavaScript:@"return globalThis.__talariaPasswordAutofill?.prepare(token) ?? null;"
    arguments:@{@"token":token} inFrame:frame inContentWorld:TLPasswordWorld() completionHandler:^(id value, NSError *error) {
    if (error || ![value isKindOfClass:NSDictionary.class] || generation != self.generation ||
        !self.available || ![self.token isEqual:token] || ![self.webView.URL isEqual:pageURL] || self.webView.window.attachedSheet) return;
    [self presentFields:value frame:frame token:token pageURL:pageURL generation:generation];
  }];
}
- (void)presentFields:(NSDictionary *)metadata frame:(WKFrameInfo *)frame token:(NSString *)token pageURL:(NSURL *)pageURL generation:(NSUInteger)generation {
  NSAlert *alert = [NSAlert new]; self.alert = alert;
  alert.messageText = @"AutoFill Password";
  NSURLComponents *origin = [NSURLComponents new]; origin.scheme = frame.securityOrigin.protocol; origin.host = frame.securityOrigin.host;
  if (frame.securityOrigin.port && frame.securityOrigin.port != 443) origin.port = @(frame.securityOrigin.port);
  alert.informativeText = [NSString stringWithFormat:@"Click the Password field and choose Passwords… to select a saved login, then click Fill. You can also right-click the field and choose AutoFill → Passwords….\n\nWebsite: %@", origin.string];
  [alert addButtonWithTitle:@"Fill"]; [alert addButtonWithTitle:@"Cancel"];
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat height = palette.fieldHeight, width = palette.browserPromptWidth, gap = palette.space4;
  NSView *fields = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height * 2 + gap)];
  self.username = [[NSTextField alloc] initWithFrame:NSMakeRect(0, height + gap, width, height)];
  self.username.placeholderString = @"Username"; self.username.contentType = NSTextContentTypeUsername;
  self.username.stringValue = [metadata[@"username"] isKindOfClass:NSString.class] ? metadata[@"username"] : @"";
  self.password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
  self.password.placeholderString = @"Password"; self.password.contentType = NSTextContentTypePassword;
  self.requiresPassword = [metadata[@"hasPassword"] boolValue];
  self.username.delegate = self; self.password.delegate = self;
  [self updateFillButton];
  self.username.nextKeyView = self.password; self.password.nextKeyView = self.username;
  [fields addSubview:self.username]; [fields addSubview:self.password]; alert.accessoryView = fields;
  // AppKit owns the password chooser, provider selection and user authentication.
  // Talaria receives only the credential the user fills into these native fields.
  [self applyPalette:[TLThemePalette paletteForPreference:
    [[self.webView.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua] ? TLThemePreferenceDark : TLThemePreferenceLight]];
  alert.window.initialFirstResponder = self.password;
  [alert beginSheetModalForWindow:self.webView.window completionHandler:^(NSModalResponse response) {
    NSString *user = self.username.stringValue ?: @"", *secret = self.password.stringValue ?: @"";
    self.username.stringValue = @""; self.password.stringValue = @"";
    self.username = nil; self.password = nil; self.alert = nil;
    if (generation == self.generation && !self.stopped && [self.webView.URL isEqual:pageURL])
      [self.webView.window makeFirstResponder:self.webView];
    if (response != NSAlertFirstButtonReturn || generation != self.generation || self.stopped ||
        ![self.webView.URL isEqual:pageURL] || ![self.token isEqual:token]) {
      [self.webView callAsyncJavaScript:@"globalThis.__talariaPasswordAutofill?.cancel(token);" arguments:@{@"token":token} inFrame:frame inContentWorld:TLPasswordWorld() completionHandler:nil];
      return;
    }
    [self.webView callAsyncJavaScript:@"return globalThis.__talariaPasswordAutofill?.fill(token, user, secret) ?? false;"
      arguments:@{@"token":token, @"user":user, @"secret":secret} inFrame:frame inContentWorld:TLPasswordWorld() completionHandler:^(id filled, NSError *error) {
      if (generation != self.generation || self.stopped) return;
      if ((error || ![filled boolValue]) && self.webView.window && !self.webView.window.attachedSheet) {
        NSAlert *notice = [NSAlert new]; notice.messageText = @"The sign-in form changed";
        notice.informativeText = @"Select the username or password field and try AutoFill Password again.";
        [notice beginSheetModalForWindow:self.webView.window completionHandler:^(NSModalResponse response) {
          if (generation == self.generation && !self.stopped) [self.webView.window makeFirstResponder:self.webView];
        }];
      }
    }];
  }];
  [alert.window makeFirstResponder:self.password];
}
- (void)updateFillButton {
  self.alert.buttons.firstObject.enabled = self.requiresPassword ? self.password.stringValue.length > 0 : self.username.stringValue.length > 0;
}
- (void)controlTextDidChange:(NSNotification *)notification { [self updateFillButton]; }
- (void)applyPalette:(TLThemePalette *)palette {
  if (!self.alert) return;
  self.alert.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  for (NSTextField *field in @[self.username, self.password]) {
    field.font = palette.bodyFont; field.textColor = palette.controlText; field.backgroundColor = palette.controlSurface;
  }
}
- (void)reset {
  ++self.generation; self.frame = nil; self.token = nil;
  self.username.stringValue = @""; self.password.stringValue = @"";
  if (self.alert.window.sheetParent) [self.alert.window.sheetParent endSheet:self.alert.window returnCode:NSAlertSecondButtonReturn];
}
- (void)stop {
  [self reset]; self.stopped = YES;
  [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"talariaPasswordAutofill" contentWorld:TLPasswordWorld()];
}
@end
