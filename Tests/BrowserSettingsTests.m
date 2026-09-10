#import <AppKit/AppKit.h>
#import "WebKitBrowserSettings.h"
#import "TLBrowserPreferences.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void Save(NSString *identifier, id value) {
  NSError *error = nil;
  Check([TLWebKitBrowserSettings setValue:value forSetting:[TLBrowserPreferences settingWithID:identifier] error:&error],
    [NSString stringWithFormat:@"Save %@: %@", identifier, error.localizedDescription ?: @"ok"]);
}
int main(void) {
  @autoreleasepool {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"talaria-webkit-settings-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    setenv("TL_WEBKIT_PROFILE_DIR", path.UTF8String, 1);
    for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
      NSDictionary *state = [TLWebKitBrowserSettings stateForSetting:setting];
      Check([state[@"available"] boolValue], [NSString stringWithFormat:@"Visible setting %@ has a supported runtime implementation: %@", setting[@"id"], state[@"reason"]]);
    }
    Check(![TLBrowserPreferences settingWithID:@"passwords"] && ![TLBrowserPreferences settingWithID:@"automatic_downloads"] && ![TLBrowserPreferences settingWithID:@"hardwareAcceleration"], @"Unsupported controls are absent from the catalogue");
    Save(@"fontSize", @24); Save(@"minimumFont", @14); Save(@"javascript", @2); Save(@"images", @2); Save(@"cookies", @2); Save(@"tabLinks", @NO);
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new]; configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    [TLWebKitBrowserSettings applyToConfiguration:configuration];
    Check([[configuration.preferences valueForKey:@"_defaultFontSize"] integerValue] == 24, @"Native WebKit default font preference receives the saved value");
    Check(configuration.preferences.minimumFontSize == 14, @"Minimum font uses the public WebKit preference");
    Check(!configuration.defaultWebpagePreferences.allowsContentJavaScript && !configuration.preferences.tabFocusesLinks, @"JavaScript and keyboard navigation preferences apply");
    Check(![[configuration.preferences valueForKey:@"_loadsImagesAutomatically"] boolValue] && ![[configuration.preferences valueForKey:@"_cookieEnabled"] boolValue], @"Image and cookie blocking affect native WebKit preferences");
    Check([[configuration.preferences valueForKey:@"_storageBlockingPolicy"] integerValue] != 2, @"Cookie blocking does not globally disable local storage");
    if (@available(macOS 14.0, *)) {
      __block BOOL receivedPolicy = NO;
      __block WKCookiePolicy savedPolicy = WKCookiePolicyAllow;
      [configuration.websiteDataStore.httpCookieStore getCookiePolicy:^(WKCookiePolicy policy) { savedPolicy = policy; receivedPolicy = YES; }];
      NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
      while (!receivedPolicy && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
      Check(receivedPolicy && savedPolicy == WKCookiePolicyDisallow, @"The WebKit network cookie store confirms cookies are blocked");
    }
    Save(@"cookies", @1); Save(@"thirdPartyCookies", @1);
    configuration = [WKWebViewConfiguration new]; configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore]; [TLWebKitBrowserSettings applyToConfiguration:configuration];
    Check([[configuration.preferences valueForKey:@"_cookieEnabled"] boolValue] && [[configuration.preferences valueForKey:@"_storageBlockingPolicy"] integerValue] == 1, @"Third-party cookie blocking preserves first-party cookies");
    if (@available(macOS 15.2, *)) {
      Save(@"httpsOnly", @YES);
      [TLWebKitBrowserSettings applyToConfiguration:configuration];
      Check(configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy == WKWebpagePreferencesUpgradeToHTTPSPolicyErrorOnFailure, @"Native HTTPS navigation policy protects form submissions and in-page navigations");
      NSURLRequest *request = [TLWebKitBrowserSettings requestForURL:[NSURL URLWithString:@"http://example.test:80/path?one=two"]];
      Check([request.URL.absoluteString isEqual:@"https://example.test/path?one=two"], @"Secure-navigation settings upgrade actual requests without losing path or query");
      NSMutableURLRequest *submission = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://example.test/submit"]];
      submission.HTTPMethod = @"POST"; submission.HTTPBody = [@"name=a%26b&value=two" dataUsingEncoding:NSUTF8StringEncoding];
      [submission setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
      NSURLRequest *upgraded = [TLWebKitBrowserSettings requestForRequest:submission];
      Check([upgraded.URL.scheme isEqual:@"https"] && [upgraded.HTTPMethod isEqual:@"POST"] && [upgraded.HTTPBody isEqual:submission.HTTPBody] && [[upgraded valueForHTTPHeaderField:@"Content-Type"] isEqual:[submission valueForHTTPHeaderField:@"Content-Type"]], @"HTTPS upgrades preserve form method, encoded body and request headers");
      Check([submission.URL.scheme isEqual:@"http"], @"Upgrading a request does not mutate the original navigation");
    } else Check(![TLBrowserPreferences settingWithID:@"httpsOnly"], @"HTTPS-only control requires WebKit native navigation policy support");
    Check(![TLBrowserPreferences settingWithID:@"acceptLanguages"] && ![TLBrowserPreferences settingWithID:@"spellcheck"] && ![TLBrowserPreferences settingWithID:@"doNotTrack"], @"Partial language, spelling and tracking controls are absent");
    Check(![TLBrowserPreferences settingWithID:@"proxyMode"], @"A removed WebKit proxy override is not advertised as a working setting");
    TLBrowserPreferences *reopened = [[TLBrowserPreferences alloc] initWithProfileURL:[NSURL fileURLWithPath:path isDirectory:YES]];
    Check([[reopened localValue:@"fontSize"] integerValue] == 24 && [[reopened localValue:@"minimumFont"] integerValue] == 14, @"Engine preferences persist across service recreation");
    NSURL *legacySettings = [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"TalariaSettings.json"]];
    [@"{\"cookies\":4}" writeToURL:legacySettings atomically:YES encoding:NSUTF8StringEncoding error:nil];
    reopened = [[TLBrowserPreferences alloc] initWithProfileURL:[NSURL fileURLWithPath:path isDirectory:YES]];
    Check([[reopened localValue:@"cookies"] integerValue] == 2, @"Removed session-cookie mode migrates to blocking without weakening privacy");
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    puts("BrowserSettingsTests passed");
  }
  return 0;
}
