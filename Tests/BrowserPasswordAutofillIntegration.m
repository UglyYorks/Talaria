#import <AppKit/AppKit.h>
#import "TLBrowserPasswordAutofill.h"
#import "design_system/TLBrowserWebView.h"
#import "BrowserWebKitTestSupport.h"
#import "Theme.h"

static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr, "%s: %s\n", condition ? "PASS" : "FAIL", message.UTF8String);
  fflush(condition ? stdout : stderr); if (!condition) exit(1);
}
static void Later(dispatch_block_t action) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), action);
}

@interface TLPasswordAutofillProbe : NSObject <NSApplicationDelegate, WKNavigationDelegate>
@property NSWindow *window;
@property TLBrowserWebView *webView;
@property TLBrowserPasswordAutofill *autofill;
@property NSArray<NSDictionary *> *cases;
@property NSUInteger index;
@property BOOL privateMode;
@end
@implementation TLPasswordAutofillProbe
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.cases = @[
    @{@"name":@"paired login", @"html":@"<form><input id=u autocomplete=username><input id=p type=password></form>", @"expected":@YES},
    @{@"name":@"password-only login", @"html":@"<form><p>Previously selected account</p><input id=p type=password autocomplete=current-password></form>", @"expected":@YES},
    @{@"name":@"username-first login", @"html":@"<form><input id=p autocomplete=username></form>", @"expected":@YES},
    @{@"name":@"form isolation", @"html":@"<form><input id=other autocomplete=username></form><form><input id=u autocomplete=username><input id=p type=password></form>", @"expected":@YES},
    @{@"name":@"page-world bridge spoof", @"html":@"<input id=p type=password><script>window.__talariaPasswordAutofill={fill(){throw Error('page bridge called')}};</script>", @"expected":@YES},
    @{@"name":@"cancel", @"html":@"<input id=p type=password>", @"expected":@YES, @"cancel":@YES},
    @{@"name":@"replaced form", @"html":@"<form><input id=p type=password></form>", @"expected":@YES, @"mutate":@"document.querySelector('form').innerHTML='<input id=p type=password>';"},
    @{@"name":@"changed form destination", @"html":@"<form><input id=p type=password></form>", @"expected":@YES, @"mutate":@"document.querySelector('form').action='https://other.test/';"},
    @{@"name":@"username handler replaces password", @"html":@"<form><input id=u autocomplete=username oninput=\"p.outerHTML='<input id=p type=password>'\"><input id=p type=password></form>", @"expected":@YES, @"rejectFill":@YES},
    @{@"name":@"HTTP page", @"html":@"<input id=p type=password>", @"expected":@NO, @"http":@YES},
    @{@"name":@"HTTP form destination", @"html":@"<form action='http://autofill.test/'><input id=p type=password></form>", @"expected":@NO},
    @{@"name":@"cross-origin form destination", @"html":@"<form action='https://other.test/'><input id=p type=password></form>", @"expected":@NO},
    @{@"name":@"new password", @"html":@"<input id=p type=password autocomplete=new-password>", @"expected":@NO},
    @{@"name":@"one-time code", @"html":@"<input id=p autocomplete=one-time-code>", @"expected":@NO},
    @{@"name":@"ambiguous password fields", @"html":@"<form><input id=p type=password><input type=password></form>", @"expected":@NO},
    @{@"name":@"read-only password", @"html":@"<input id=p type=password readonly>", @"expected":@NO},
    @{@"name":@"navigation cancels chooser", @"html":@"<input id=p type=password>", @"expected":@YES, @"navigate":@YES}
  ];
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 850, 620) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed = NO;
  TLTestActivateWindow(self.window, ^{ [self startMode]; });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ Check(NO, @"autofill test deadline"); });
}
- (void)startMode {
  WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
  configuration.websiteDataStore = self.privateMode ? WKWebsiteDataStore.nonPersistentDataStore : WKWebsiteDataStore.defaultDataStore;
  self.webView = [[TLBrowserWebView alloc] initWithFrame:self.window.contentView.bounds configuration:configuration];
  self.webView.navigationDelegate = self;
  self.autofill = [[TLBrowserPasswordAutofill alloc] initWithWebView:self.webView];
  __weak typeof(self) weakSelf = self;
  self.webView.passwordAutofillHandler = ^{ [weakSelf.autofill present]; };
  self.webView.passwordAutofillAvailable = ^{ return weakSelf.autofill.available; };
  self.window.contentView = self.webView;
  [self.window makeFirstResponder:self.webView];
  [self loadCase];
}
- (void)loadCase {
  NSDictionary *test = self.cases[self.index];
  NSString *URL = [test[@"http"] boolValue] ? @"http://autofill.test/login" : @"https://autofill.test/login";
  NSString *html = [NSString stringWithFormat:@"<!doctype html><title>AutoFill Test</title>%@<script>window.events=[];document.addEventListener('input',e=>events.push(e.target.id+':input'));document.addEventListener('change',e=>events.push(e.target.id+':change'));</script>", test[@"html"]];
  [self.webView loadSimulatedRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:URL]] responseHTMLString:html];
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation { [self.autofill reset]; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  [self.window makeFirstResponder:webView];
  TLTestEvaluate(webView, @"document.getElementById('p').focus();true", ^(id value) {
    Later(^{ [self checkCase]; });
  });
}
- (void)checkCase {
  NSDictionary *test = self.cases[self.index];
  NSString *name = [NSString stringWithFormat:@"%@ %@", self.privateMode ? @"private" : @"regular", test[@"name"]];
  Check(self.autofill.available == [test[@"expected"] boolValue], [name stringByAppendingString:@" availability"]);
  NSMenuItem *menu = [[NSMenuItem alloc] initWithTitle:@"AutoFill Password…" action:@selector(autofillPassword:) keyEquivalent:@"\\"];
  Check([self.webView validateMenuItem:menu] == self.autofill.available, @"native command validation");
  if (!self.autofill.available) { [self nextCase]; return; }
  // Check responder routing on the initially activated window. Subsequent cases
  // address the native action directly so using another app during the suite
  // does not turn loss of foreground activation into a false routing failure.
  BOOL initial = self.index == 0 && !self.privateMode;
  Check([NSApp sendAction:@selector(autofillPassword:) to:initial ? nil : self.webView from:nil],
    initial ? @"AutoFill command reaches the focused browser through the responder chain" : @"native AutoFill action is handled");
  [self waitForSheet:0];
}
- (void)waitForSheet:(NSUInteger)attempt {
  if (![self.autofill valueForKey:@"alert"] || !self.window.attachedSheet) {
    Check(attempt < 30, @"native AutoFill sheet opens"); Later(^{ [self waitForSheet:attempt + 1]; }); return;
  }
  NSAlert *alert = [self.autofill valueForKey:@"alert"];
  NSTextField *user = [self.autofill valueForKey:@"username"];
  NSSecureTextField *password = [self.autofill valueForKey:@"password"];
  Check([user.contentType isEqual:NSTextContentTypeUsername] && [password.contentType isEqual:NSTextContentTypePassword], @"native fields offer system credential AutoFill");
  Check(!alert.buttons.firstObject.enabled, @"Fill waits for a selected or entered credential");
  Check([alert.informativeText containsString:@"autofill.test"], @"chooser identifies the target website");
  if (self.index == 0) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:self.privateMode ? TLThemePreferenceDark : TLThemePreferenceLight];
    [self.autofill applyPalette:palette];
    NSView *view = alert.window.contentView;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSString *path = [NSProcessInfo.processInfo.environment[@"TL_AUTOFILL_OUTPUT"] stringByAppendingPathComponent:self.privateMode ? @"autofill-dark.png" : @"autofill-light.png"];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    if ([NSProcessInfo.processInfo.environment[@"TL_AUTOFILL_INTERACTIVE"] boolValue]) return;
  }
  // Synthetic credentials exercise delivery without reading or unlocking a vault.
  user.stringValue = @"fixture-user"; password.stringValue = @"fixture-secret";
  [password.delegate controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:password]];
  Check(alert.buttons.firstObject.enabled, @"Fill becomes available after credential entry");
  NSDictionary *test = self.cases[self.index];
  if ([test[@"navigate"] boolValue]) {
    [self.autofill reset];
    Later(^{ Check(!self.window.attachedSheet && !self.autofill.available, @"navigation invalidates and dismisses the chooser"); [self nextCase]; }); return;
  }
  TLTestEvaluate(self.webView, [test[@"mutate"] ?: @"" stringByAppendingString:@"true"], ^(id value) {
    [[test[@"cancel"] boolValue] ? alert.buttons.lastObject : alert.buttons.firstObject performClick:nil];
    Later(^{ Later(^{
      Check(!user.stringValue.length && !password.stringValue.length, @"native credential fields cleared after dismissal");
      TLTestEvaluate(self.webView, @"({value:document.getElementById('p').value,user:document.getElementById('u')?.value,other:document.getElementById('other')?.value,events})", ^(NSDictionary *result) {
        BOOL reject = [test[@"cancel"] boolValue] || test[@"mutate"] || [test[@"rejectFill"] boolValue];
        NSString *expected = reject ? @"" : [test[@"name"] isEqual:@"username-first login"] ? @"fixture-user" : @"fixture-secret";
        Check([result[@"value"] isEqual:expected], [test[@"name"] stringByAppendingString:@" credential delivery"]);
        if (!reject) Check([result[@"events"] containsObject:@"p:input"] && [result[@"events"] containsObject:@"p:change"], @"website receives input and change events");
        if ([result[@"other"] isKindOfClass:NSString.class]) Check(![result[@"other"] length], @"other forms remain untouched");
        if (self.window.attachedSheet) [self.window endSheet:self.window.attachedSheet];
        [self nextCase];
      });
    }); });
  });
}
- (void)nextCase {
  if (++self.index < self.cases.count) { Later(^{ [self loadCase]; }); return; }
  [self.autofill stop]; self.autofill = nil;
  if (!self.privateMode) { self.privateMode = YES; self.index = 0; [self startMode]; return; }
  printf("TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); [NSApp terminate:nil];
}
@end
int main(void) { @autoreleasepool {
  NSApplication *app = NSApplication.sharedApplication;
  TLPasswordAutofillProbe *delegate = [TLPasswordAutofillProbe new]; app.delegate = delegate; [app run];
} return 0; }
