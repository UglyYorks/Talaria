#import "TLBrowserPreferences.h"
#import "ChromiumBrowserController.h"
NSNotificationName const TLBrowserPreferencesDidChangeNotification = @"TLBrowserPreferencesDidChange";
static NSError *TLBrowserPreferenceError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.BrowserPreferences" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface TLBrowserPreferences ()
@property NSURL *fileURL;
@property NSMutableDictionary *local;
@end
@implementation TLBrowserPreferences
+ (instancetype)sharedPreferences {
  static TLBrowserPreferences *preferences; static dispatch_once_t once;
  dispatch_once(&once, ^{ preferences = [[self alloc] initWithProfileURL:self.profileURL]; });
  return preferences;
}
+ (NSURL *)profileURL {
  NSString *override = NSProcessInfo.processInfo.environment[@"TL_CHROMIUM_PROFILE_DIR"];
  if (override.isAbsolutePath) return [NSURL fileURLWithPath:override.stringByStandardizingPath isDirectory:YES];
  return [[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
    URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES] URLByAppendingPathComponent:@"Chromium" isDirectory:YES];
}
- (instancetype)initWithProfileURL:(NSURL *)URL {
  if ((self = [super init])) {
    _fileURL = [URL URLByAppendingPathComponent:@"TalariaSettings.json"];
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    _local = [NSMutableDictionary dictionary];
    if ([stored isKindOfClass:NSDictionary.class]) for (NSDictionary *setting in self.class.catalogue) {
      id value = stored[setting[@"id"]];
      if ([setting[@"scope"] isEqual:@"app"] && value && [self validateValue:value forSetting:setting error:nil]) _local[setting[@"id"]] = value;
    }
  }
  return self;
}
+ (NSArray<NSString *> *)categories {
  return @[@"Privacy & security", @"Site permissions", @"Autofill & passwords", @"Search engine", @"Appearance", @"On startup", @"Performance", @"Languages", @"Downloads", @"Accessibility", @"System", @"Reset settings"];
}
+ (NSArray<NSDictionary *> *)catalogue {
  static NSArray *catalogue; static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSMutableArray *items = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSString *, NSString *, NSString *, NSString *, id, NSArray *, NSArray *) =
    ^(NSString *identifier, NSString *category, NSString *title, NSString *detail, NSString *scope, NSString *path, id defaultValue, NSArray *values, NSArray *labels) {
      NSMutableDictionary *item = [@{@"id":identifier, @"category":category, @"title":title, @"detail":detail, @"scope":scope, @"path":path, @"default":defaultValue,
        @"type":values ? @"choice" : [defaultValue isKindOfClass:NSNumber.class] ? @"bool" : @"text"} mutableCopy];
      if (values) { item[@"values"] = values; item[@"labels"] = labels; }
      [items addObject:item];
    };
    NSString *privacy = @"Privacy & security";
    add(@"cookies",privacy,@"Cookies",@"Allow sites to keep you signed in, block cookies, or keep them for this session only.",@"content",@"cookies",@1,@[@1,@2,@4],@[@"Allow",@"Block",@"Session only"]);
    add(@"thirdPartyCookies",privacy,@"Third-party cookies",@"Control cookies set by content embedded from other sites.",@"profile",@"profile.cookie_controls_mode",@1,@[@1,@0],@[@"Block",@"Allow"]);
    add(@"doNotTrack",privacy,@"Send Do Not Track",@"Ask websites not to track you. Sites decide whether to honor this request.",@"profile",@"enable_do_not_track",@NO,nil,nil);
    add(@"safeBrowsing",privacy,@"Safe Browsing",@"Check pages and downloads for known threats when protection services are available.",@"profile",@"safebrowsing.enabled",@YES,nil,nil);
    add(@"httpsOnly",privacy,@"Always use secure connections",@"Upgrade navigation to HTTPS and warn before opening insecure pages.",@"profile",@"https_only_mode_enabled",@NO,nil,nil);
    add(@"preloading",privacy,@"Preload pages",@"Predict and prepare pages you may visit.",@"profile",@"net.network_prediction_options",@0,@[@2,@0,@3],@[@"Off",@"Standard",@"Extended"]);
    add(@"secureDNS",privacy,@"Secure DNS",@"Use encrypted DNS when your current provider supports it, or use system DNS only.",@"global",@"dns_over_https.mode",@"automatic",@[@"automatic",@"off"],@[@"Automatic",@"Off"]);
    NSArray *permissions = @[
      @[@"javascript",@"JavaScript",@"Allow sites to run scripts.",@1], @[@"images",@"Images",@"Allow sites to display images.",@1],
      @[@"popups",@"Pop-ups and redirects",@"Allow sites to open additional windows.",@2], @[@"sound",@"Sound",@"Allow sites to play audio.",@1],
      @[@"geolocation",@"Location",@"Control requests for your location.",@3], @[@"notifications",@"Notifications",@"Control website notification requests.",@3],
      @[@"media_stream_camera",@"Camera",@"Control camera requests. macOS permission is also required.",@3],
      @[@"media_stream_mic",@"Microphone",@"Control microphone requests. macOS permission is also required.",@3],
      @[@"clipboard",@"Clipboard",@"Control requests to read text and images from your clipboard.",@3],
      @[@"automatic_downloads",@"Multiple downloads",@"Control sites that download several files automatically.",@3],
      @[@"usb_guard",@"USB devices",@"Control requests to connect to USB devices.",@3],
      @[@"serial_guard",@"Serial ports",@"Control requests to connect to serial ports.",@3],
      @[@"hid_guard",@"HID devices",@"Control requests to connect to human interface devices.",@3],
      @[@"local_fonts",@"Local fonts",@"Control access to fonts installed on your Mac.",@3],
      @[@"background_sync",@"Background sync",@"Allow sites to finish sending data after you leave.",@1],
      @[@"sensors",@"Motion sensors",@"Allow sites to access motion sensors.",@1]];
    for (NSArray *p in permissions) {
      BOOL asks = [p[3] intValue] == 3;
      add(p[0],@"Site permissions",p[1],p[2],@"content",p[0],p[3],asks ? @[@3,@2] : @[@1,@2], asks ? @[@"Ask first",@"Block"] : @[@"Allow",@"Block"]);
    }
    add(@"passwords",@"Autofill & passwords",@"Offer to save passwords",@"Offer to remember passwords when you sign in on a website.",@"profile",@"credentials_enable_service",@YES,nil,nil);
    add(@"autoSignIn",@"Autofill & passwords",@"Sign in automatically",@"Use saved credentials when a site supports automatic sign-in.",@"profile",@"credentials_enable_autosignin",@YES,nil,nil);
    add(@"addresses",@"Autofill & passwords",@"Save and fill addresses",@"Remember and fill contact information in web forms.",@"profile",@"autofill.profile_enabled",@YES,nil,nil);
    add(@"payments",@"Autofill & passwords",@"Save and fill payment methods",@"Remember and fill payment methods in web forms.",@"profile",@"autofill.credit_card_enabled",@YES,nil,nil);
    add(@"searchEngine",@"Search engine",@"Default search engine",@"Used for web searches from the browser address bar.",@"app",@"",@"https://www.google.com/search?q={searchTerms}",
      @[@"https://www.google.com/search?q={searchTerms}",@"https://duckduckgo.com/?q={searchTerms}",@"https://www.bing.com/search?q={searchTerms}",@"https://search.brave.com/search?q={searchTerms}",@"custom"],@[@"Google",@"DuckDuckGo",@"Bing",@"Brave",@"Custom"]);
    add(@"customSearchURL",@"Search engine",@"Custom search URL",@"Use an HTTPS URL with {searchTerms} where the query belongs.",@"app",@"",@"https://duckduckgo.com/?q={searchTerms}",nil,nil);
    add(@"addressBarMode",@"Search engine",@"Address bar text",@"Choose what happens when you enter text instead of a URL. The chat composer always sends messages to Hermes.",@"app",@"",@"search",@[@"search",@"assistant"],@[@"Search the web",@"Ask Hermes"]);
    add(@"zoom",@"Appearance",@"Default page zoom",@"Apply to open browser tabs and new pages.",@"app",@"",@100,@[@50,@67,@75,@90,@100,@110,@125,@150,@175,@200,@250,@300],@[@"50%",@"67%",@"75%",@"90%",@"100%",@"110%",@"125%",@"150%",@"175%",@"200%",@"250%",@"300%"]);
    add(@"fontSize",@"Appearance",@"Font size",@"Default size for text on websites that use the browser’s font settings.",@"profile",@"webkit.webprefs.default_font_size",@16,@[@12,@14,@16,@18,@20,@24],@[@"12",@"14",@"16",@"18",@"20",@"24"]);
    add(@"minimumFont",@"Appearance",@"Minimum font size",@"Keep small text readable on web pages.",@"profile",@"webkit.webprefs.minimum_font_size",@0,@[@0,@9,@12,@14,@16,@18,@24],@[@"None",@"9",@"12",@"14",@"16",@"18",@"24"]);
    for (NSArray *font in @[@[@"standard",@"Standard font",@"Times"],@[@"serif",@"Serif font",@"Times"],@[@"sansserif",@"Sans-serif font",@"Helvetica"],@[@"fixed",@"Fixed-width font",@"Menlo"]]) {
      add([@"font_" stringByAppendingString:font[0]],@"Appearance",font[1],@"Choose a font family installed on your Mac.",@"profile",[@"webkit.webprefs.fonts." stringByAppendingFormat:@"%@.Zyyy",font[0]],font[2],nil,nil);
      items.lastObject[@"type"] = @"font";
    }
    add(@"startup",@"On startup",@"When Talaria starts",@"Choose which browser tabs open. Your chats and other workspace tabs are preserved.",@"app",@"",@"restore",@[@"restore",@"empty",@"pages"],@[@"Restore browser tabs",@"No browser tabs",@"Open specific pages"]);
    add(@"startupPages",@"On startup",@"Startup pages",@"Enter complete HTTP or HTTPS URLs, one per line.",@"app",@"",@"",nil,nil); items.lastObject[@"type"] = @"multiline";
    add(@"pauseBackground",@"Performance",@"Pause background tabs",@"Pause scripts and media in hidden tabs after the delay below. Tabs resume when you return to them.",@"app",@"",@NO,nil,nil);
    add(@"pauseDelay",@"Performance",@"Pause after",@"Time a tab must stay hidden before it is paused.",@"app",@"",@300,@[@60,@300,@900,@1800],@[@"1 minute",@"5 minutes",@"15 minutes",@"30 minutes"]);
    add(@"acceptLanguages",@"Languages",@"Preferred languages",@"Send these language codes to websites, in order; for example en-AU,en,fr.",@"profile",@"intl.accept_languages",@"en-US,en",nil,nil);
    add(@"translation",@"Languages",@"Offer page translation",@"Offer to translate pages written in another language.",@"profile",@"translate.enabled",@YES,nil,nil);
    add(@"spellcheck",@"Languages",@"Spell check",@"Underline spelling mistakes in web forms using the macOS spelling service.",@"profile",@"browser.enable_spellchecking",@YES,nil,nil);
    add(@"downloadDirectory",@"Downloads",@"Download location",@"Save downloaded files in this folder.",@"profile",@"download.default_directory",NSHomeDirectory(),nil,nil); items.lastObject[@"type"] = @"directory";
    add(@"askDownload",@"Downloads",@"Ask where to save each file",@"Show a Save dialog before each download.",@"profile",@"download.prompt_for_download",@YES,nil,nil);
    add(@"pdfDownload",@"Downloads",@"Download PDF files",@"Save PDFs instead of opening them in the built-in viewer.",@"profile",@"plugins.always_open_pdf_externally",@NO,nil,nil);
    add(@"caret",@"Accessibility",@"Navigate pages with a text cursor",@"Use the keyboard to move through and select web page text.",@"profile",@"settings.a11y.caretbrowsing.enabled",@NO,nil,nil);
    add(@"tabLinks",@"Accessibility",@"Tab through links",@"Include links when moving keyboard focus through a web page.",@"profile",@"webkit.webprefs.tabs_to_links",@YES,nil,nil);
    add(@"animations",@"Accessibility",@"Animated images",@"Control playback of animated images on web pages.",@"profile",@"settings.a11y.animation_policy",@"allowed",@[@"allowed",@"once",@"none"],@[@"Allow",@"Play once",@"Do not animate"]);
    add(@"screenReader",@"Accessibility",@"Full accessibility tree",@"Expose browser page content to assistive technology. Automatically enabled when required by macOS.",@"app",@"",@NO,nil,nil);
    add(@"hardwareAcceleration",@"System",@"Hardware acceleration",@"Use the GPU when available. Takes effect after restarting Talaria.",@"app",@"",@YES,nil,nil);
    add(@"proxyMode",@"System",@"Proxy",@"Use your Mac’s proxy configuration, connect directly, or set a proxy for Talaria only.",@"proxy",@"proxy",@"system",@[@"system",@"direct",@"fixed_servers",@"pac_script"],@[@"System settings",@"Direct connection",@"Proxy server",@"PAC script"]);
    add(@"proxyServer",@"System",@"Proxy server",@"For example http://localhost:8080 or socks5://localhost:1080. Do not include credentials.",@"proxy",@"proxy",@"",nil,nil);
    add(@"proxyPAC",@"System",@"PAC script URL",@"An HTTPS URL for your proxy auto-configuration script.",@"proxy",@"proxy",@"",nil,nil);
    add(@"proxyBypass",@"System",@"Proxy bypass list",@"Hosts that connect directly, separated by semicolons. For example localhost;*.local.",@"proxy",@"proxy",@"localhost;127.0.0.1;[::1]",nil,nil);
    catalogue = items.copy;
  }); return catalogue;
}
+ (NSDictionary *)settingWithID:(NSString *)identifier { for (NSDictionary *s in self.catalogue) if ([s[@"id"] isEqual:identifier]) return s; return nil; }
- (id)localValue:(NSString *)identifier { return self.local[identifier] ?: [self.class settingWithID:identifier][@"default"]; }
- (void)prepareInWindow:(NSWindow *)window completion:(void (^)(NSError *))completion {
  [TLChromiumBrowserController.sharedController prepareBrowserSettingsInWindow:window completion:completion];
}
- (NSDictionary *)stateForSetting:(NSDictionary *)setting {
  if ([setting[@"scope"] isEqual:@"app"]) return @{@"value":[self localValue:setting[@"id"]],@"available":@YES};
  return [TLChromiumBrowserController.sharedController browserSettingState:setting];
}
- (BOOL)validateValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error {
  NSString *message = nil, *type = setting[@"type"], *identifier = setting[@"id"];
  if (!setting || ![self.class settingWithID:identifier]) message = @"Unknown browser setting.";
  else if ([type isEqual:@"choice"] && ![setting[@"values"] containsObject:value]) message = @"Choose a value from the list.";
  else if ([type isEqual:@"bool"] && (![value isKindOfClass:NSNumber.class] || ![@[@NO,@YES] containsObject:value])) message = @"Expected an on or off value.";
  else if (![@[@"choice",@"bool"] containsObject:type] && ![value isKindOfClass:NSString.class]) message = @"Enter a text value.";
  else if ([value isKindOfClass:NSString.class]) {
    if ([value length] > 16384) message = @"This value is too long.";
    else if ([identifier isEqual:@"customSearchURL"] && (![value containsString:@"{searchTerms}"] || ![self validWebURL:[value stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:@"query"] HTTPSOnly:YES])) message = @"Enter an HTTPS URL containing {searchTerms}.";
    else if ([identifier isEqual:@"startupPages"]) for (NSString *line in [value componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
      if (trimmed.length && ![self validWebURL:trimmed HTTPSOnly:NO]) { message = @"Each startup page must be a complete HTTP or HTTPS URL without credentials."; break; }
    }
    else if ([identifier isEqual:@"acceptLanguages"] && ![[NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*(,[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*)*"] evaluateWithObject:value]) message = @"Use comma-separated language codes, such as en-AU,en,fr.";
    else if ([type isEqual:@"font"] && ![NSFontManager.sharedFontManager.availableFontFamilies containsObject:value]) message = @"Choose an installed font family.";
    else if ([type isEqual:@"directory"]) { BOOL directory = NO; if (![value isAbsolutePath] || ![NSFileManager.defaultManager fileExistsAtPath:value isDirectory:&directory] || !directory || ![NSFileManager.defaultManager isWritableFileAtPath:value]) message = @"Choose an existing writable folder."; }
    else if ([identifier isEqual:@"proxyPAC"] && [value length] && ![self validWebURL:value HTTPSOnly:YES]) message = @"Enter an HTTPS PAC URL without credentials.";
    else if ([identifier isEqual:@"proxyServer"] && [value length]) {
      NSURLComponents *url = [NSURLComponents componentsWithString:value];
      if (![@[@"http",@"https",@"socks4",@"socks5"] containsObject:url.scheme] || !url.host.length || !url.port || url.port.integerValue < 1 || url.port.integerValue > 65535 || url.user || url.password || url.query || url.fragment || (url.path.length && ![url.path isEqual:@"/"])) message = @"Enter a proxy URL with a host and port, without credentials or a path.";
    }
  }
  if (message && error) *error = TLBrowserPreferenceError(message);
  return message == nil;
}
- (BOOL)validWebURL:(NSString *)value HTTPSOnly:(BOOL)HTTPSOnly {
  NSURLComponents *url = [NSURLComponents componentsWithString:value];
  return url.URL && url.host.length && !url.user && !url.password && (HTTPSOnly ? [url.scheme isEqual:@"https"] : [@[@"http",@"https"] containsObject:url.scheme]);
}
- (BOOL)saveValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error {
  if (![self validateValue:value forSetting:setting error:error]) return NO;
  if ([setting[@"scope"] isEqual:@"app"]) {
    NSMutableDictionary *next = self.local.mutableCopy; next[setting[@"id"]] = value;
    if (![self persist:next error:error]) return NO;
    self.local = next;
  } else if (![TLChromiumBrowserController.sharedController setBrowserSetting:setting value:value error:error]) return NO;
  [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserPreferencesDidChangeNotification object:self userInfo:@{@"id":setting[@"id"]}];
  return YES;
}
- (BOOL)persist:(NSDictionary *)values error:(NSError **)error {
  if (![NSFileManager.defaultManager createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
  NSData *data = [NSJSONSerialization dataWithJSONObject:values options:NSJSONWritingPrettyPrinted error:error];
  return data && [data writeToURL:self.fileURL options:NSDataWritingAtomic error:error];
}
- (NSURL *)searchURLForText:(NSString *)text {
  NSString *query = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!query.length) return nil;
  NSString *template = [self localValue:@"searchEngine"];
  if ([template isEqual:@"custom"]) template = [self localValue:@"customSearchURL"];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
  return [NSURL URLWithString:[template stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:[query stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
}
- (NSArray<NSURL *> *)startupURLs {
  if (![[self localValue:@"startup"] isEqual:@"pages"]) return @[];
  NSMutableArray *URLs = [NSMutableArray array];
  for (NSString *line in [[self localValue:@"startupPages"] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([self validWebURL:trimmed HTTPSOnly:NO]) [URLs addObject:[NSURL URLWithString:trimmed]];
  } return URLs;
}
- (void)clearData:(NSString *)kind completion:(void (^)(NSError *))completion {
  [TLChromiumBrowserController.sharedController clearBrowserData:kind completion:completion];
}
- (BOOL)resetDefaults:(NSError **)error {
  for (NSDictionary *setting in self.class.catalogue) {
    if ([setting[@"scope"] isEqual:@"app"]) continue;
    if (![[self stateForSetting:setting][@"available"] boolValue]) continue;
    if (![TLChromiumBrowserController.sharedController setBrowserSetting:setting value:nil error:error]) return NO;
  }
  if (![self persist:@{} error:error]) return NO;
  [self.local removeAllObjects];
  [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserPreferencesDidChangeNotification object:self];
  return YES;
}
@end
