#import "WebKitBrowserSettings.h"
#import "TLBrowserPreferences.h"
#import "design_system/TLBrowserWebView.h"

@interface WKHTTPCookieStore (TLBrowserCookiePolicy)
- (void)_setCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)policy completionHandler:(void (^)(void))completionHandler;
@end

static id Value(NSString *identifier) { return [TLBrowserPreferences.sharedPreferences localValue:identifier]; }
static NSError *SettingError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.BrowserSettings" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
// WebKit exposes these native preferences in its upstream Cocoa SPI. Keep their
// use in one place, check the setter on this OS, and report absent controls in UI.
static BOOL SetNative(id object, NSString *key, id value) {
  NSString *stem = [key hasPrefix:@"_"] ? [key substringFromIndex:1] : key;
  NSString *setter = [NSString stringWithFormat:@"%@set%@%@:", [key hasPrefix:@"_"] ? @"_" : @"", [stem substringToIndex:1].uppercaseString, [stem substringFromIndex:1]];
  if (![object respondsToSelector:NSSelectorFromString(setter)]) return NO;
  @try { [object setValue:value forKey:stem]; return YES; }
  @catch (NSException *exception) { return NO; }
}
static NSString *PreferenceKey(NSString *identifier) {
  return @{@"fontSize":@"_defaultFontSize", @"font_standard":@"_standardFontFamily", @"font_fixed":@"_fixedPitchFontFamily",
    @"images":@"_loadsImagesAutomatically", @"cookies":@"_cookieEnabled", @"thirdPartyCookies":@"_storageBlockingPolicy",
    @"sensors":@"_deviceOrientationEventEnabled"}[identifier];
}

@implementation TLWebKitBrowserSettings
+ (BOOL)supportsSettingID:(NSString *)identifier {
  // This query runs while the catalogue is built; do not read saved preferences
  // here or initialization would recursively request the unfinished catalogue.
  if ([identifier isEqual:@"geolocation"]) { if (@available(macOS 27.0, *)) return YES; else return NO; }
  if ([identifier isEqual:@"httpsOnly"]) { if (@available(macOS 15.2, *)) return YES; else return NO; }
  if ([@[@"pauseBackground", @"pauseDelay"] containsObject:identifier]) { if (@available(macOS 14.0, *)) return YES; else return NO; }
  if ([identifier isEqual:@"sound"])
    return [WKWebView instancesRespondToSelector:NSSelectorFromString(@"_setPageMuted:")] && [WKWebView instancesRespondToSelector:NSSelectorFromString(@"_mediaMutedState")];
  NSString *key = PreferenceKey(identifier);
  if (!key) return YES;
  id probe = [identifier hasPrefix:@"font_"] ? @"Helvetica" : [identifier isEqual:@"fontSize"] ? @24 : @0;
  WKPreferences *preferences = [WKPreferences new];
  if (!SetNative(preferences, key, probe)) return NO;
  @try { if (![[preferences valueForKey:key] isEqual:probe]) return NO; } @catch (NSException *exception) { return NO; }
  if ([identifier isEqual:@"cookies"]) {
    if (@available(macOS 14.0, *)) return YES;
    return [WKHTTPCookieStore instancesRespondToSelector:@selector(_setCookieAcceptPolicy:completionHandler:)];
  }
  if ([identifier isEqual:@"thirdPartyCookies"])
    return [WKWebsiteDataStore instancesRespondToSelector:NSSelectorFromString(@"_setResourceLoadStatisticsEnabled:")];
  return YES;
}
+ (NSDictionary *)stateForSetting:(NSDictionary *)setting {
  NSDictionary *canonical = [TLBrowserPreferences settingWithID:setting[@"id"]];
  if (!canonical || ![canonical isEqual:setting]) return @{@"available":@NO, @"reason":@"Unknown browser setting."};
  NSString *reason = [self supportsSettingID:setting[@"id"]] ? nil : @"This setting is not available in the installed WebKit version.";
  NSMutableDictionary *state = [@{@"value":Value(setting[@"id"]), @"available":@(reason == nil)} mutableCopy];
  if (reason) state[@"reason"] = reason;
  return state;
}
+ (BOOL)setValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error {
  NSDictionary *state = [self stateForSetting:setting];
  if (![state[@"available"] boolValue]) { if (error) *error = SettingError(state[@"reason"]); return NO; }
  if (value && ![TLBrowserPreferences.sharedPreferences validateValue:value forSetting:setting error:error]) return NO;
  return [TLBrowserPreferences.sharedPreferences persistValue:value forSetting:setting error:error];
}
+ (void)applyNativePreferences:(WKWebViewConfiguration *)configuration {
  WKPreferences *preferences = configuration.preferences;
  preferences.minimumFontSize = [Value(@"minimumFont") doubleValue];
  preferences.javaScriptCanOpenWindowsAutomatically = [Value(@"popups") integerValue] == 1;
  preferences.fraudulentWebsiteWarningEnabled = [Value(@"safeBrowsing") boolValue];
  preferences.tabFocusesLinks = [Value(@"tabLinks") boolValue];
  preferences.elementFullscreenEnabled = YES;
  configuration.defaultWebpagePreferences.allowsContentJavaScript = [Value(@"javascript") integerValue] != 2;
  if (@available(macOS 15.2, *))
    configuration.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = [Value(@"httpsOnly") boolValue]
      ? WKWebpagePreferencesUpgradeToHTTPSPolicyErrorOnFailure : WKWebpagePreferencesUpgradeToHTTPSPolicyKeepAsRequested;
  configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
  configuration.upgradeKnownHostsToHTTPS = YES;
  SetNative(preferences, @"_developerExtrasEnabled", @YES);
  SetNative(preferences, @"_defaultFontSize", Value(@"fontSize"));
  SetNative(preferences, @"_standardFontFamily", Value(@"font_standard"));
  SetNative(preferences, @"_fixedPitchFontFamily", Value(@"font_fixed"));
  SetNative(preferences, @"_loadsImagesAutomatically", @([Value(@"images") integerValue] != 2));
  SetNative(preferences, @"_cookieEnabled", @([Value(@"cookies") integerValue] != 2));
  SetNative(preferences, @"_storageBlockingPolicy", @([Value(@"thirdPartyCookies") integerValue] == 1 ? 1 : 0));
  WKHTTPCookieStore *cookies = configuration.websiteDataStore.httpCookieStore;
  BOOL blockCookies = [Value(@"cookies") integerValue] == 2;
  if (@available(macOS 14.0, *)) [cookies setCookiePolicy:blockCookies ? WKCookiePolicyDisallow : WKCookiePolicyAllow completionHandler:nil];
  else if ([cookies respondsToSelector:@selector(_setCookieAcceptPolicy:completionHandler:)])
    [cookies _setCookieAcceptPolicy:blockCookies ? NSHTTPCookieAcceptPolicyNever : NSHTTPCookieAcceptPolicyAlways completionHandler:^{}];
  SetNative(preferences, @"_deviceOrientationEventEnabled", @([Value(@"sensors") integerValue] != 2));
  SetNative(preferences, @"_notificationsEnabled", @NO);
  SetNative(configuration.websiteDataStore, @"_resourceLoadStatisticsEnabled", @([Value(@"thirdPartyCookies") integerValue] == 1));
}
+ (void)applyToConfiguration:(WKWebViewConfiguration *)configuration {
  [self applyNativePreferences:configuration];
}
+ (void)applyToWebView:(WKWebView *)webView {
  if([webView isKindOfClass:TLBrowserWebView.class])((TLBrowserWebView *)webView).smoothMouseWheelScrolling=[Value(@"smoothMouseWheelScrolling") boolValue];
  [self applyNativePreferences:webView.configuration];
  if ([webView respondsToSelector:NSSelectorFromString(@"_setPageMuted:")]) {
    @try {
      NSUInteger muted = [[webView valueForKey:@"_mediaMutedState"] unsignedIntegerValue];
      muted = [Value(@"sound") integerValue] == 2 ? muted | 1 : muted & ~((NSUInteger)1);
      SetNative(webView, @"_pageMuted", @(muted));
    } @catch (NSException *exception) {}
  }
  CGFloat zoom = [Value(@"zoom") doubleValue] / 100.;
  if (fabs(webView.pageZoom - zoom) > 0.0001) webView.pageZoom = zoom;
}
+ (NSURLRequest *)requestForURL:(NSURL *)URL {
  return [self requestForRequest:[NSURLRequest requestWithURL:URL]];
}
+ (NSURLRequest *)requestForRequest:(NSURLRequest *)original {
  NSMutableURLRequest *request = original.mutableCopy;
  NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
  if ([Value(@"httpsOnly") boolValue] && [components.scheme.lowercaseString isEqual:@"http"]) {
    components.scheme = @"https";
    if (components.port.integerValue == 80) components.port = nil;
    if (components.URL) request.URL = components.URL;
  }
  return request;
}

@end
