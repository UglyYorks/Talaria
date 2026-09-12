#import "TLBrowserPreferences.h"
#import "WebKitBrowserController.h"
#import "WebKitBrowserSettings.h"
#import "TLBrowserProfileImporter.h"
NSNotificationName const TLBrowserPreferencesDidChangeNotification = @"TLBrowserPreferencesDidChange";
static id TLStoredPreferenceAtPath(NSDictionary *preferences, NSString *path) {
  id value = preferences;
  for (NSString *component in [path componentsSeparatedByString:@"."]) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    value = value[component];
  }
  return value;
}
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
  NSString *override = NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"];
  if (override.isAbsolutePath) return [NSURL fileURLWithPath:override.stringByStandardizingPath isDirectory:YES];
  return [[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
    URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES] URLByAppendingPathComponent:@"WebKit" isDirectory:YES];
}
- (instancetype)initWithProfileURL:(NSURL *)URL {
  if ((self = [super init])) {
    _fileURL = [URL URLByAppendingPathComponent:@"TalariaSettings.json"];
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    NSURL *legacyRoot = nil;
    if (!data && [URL isEqual:self.class.profileURL] && !NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"]) {
      legacyRoot = [URL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Chromium" isDirectory:YES];
      NSURL *legacy = [legacyRoot URLByAppendingPathComponent:@"TalariaSettings.json"];
      data = [NSData dataWithContentsOfURL:legacy];
    }
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    _local = [NSMutableDictionary dictionary];
    if ([stored isKindOfClass:NSDictionary.class]) for (NSDictionary *setting in self.class.catalogue) {
      id value = stored[setting[@"id"]];
      if ([setting[@"id"] isEqual:@"cookies"] && [value isEqual:@4]) value = @2;
      if (value && [self validateValue:value forSetting:setting error:nil]) _local[setting[@"id"]] = value;
    }
    if (legacyRoot) {
      NSData *engineData = [NSData dataWithContentsOfURL:[legacyRoot URLByAppendingPathComponent:@"Default/Preferences"]];
      NSDictionary *engine = engineData ? [NSJSONSerialization JSONObjectWithData:engineData options:0 error:nil] : nil;
      if ([engine isKindOfClass:NSDictionary.class]) for (NSDictionary *setting in self.class.catalogue) {
        NSString *identifier = setting[@"id"], *scope = setting[@"scope"], *path = setting[@"path"];
        if (_local[identifier] || [scope isEqual:@"app"]) continue;
        if ([scope isEqual:@"content"]) path = [@"profile.default_content_setting_values." stringByAppendingString:path];
        id value = TLStoredPreferenceAtPath(engine, path);
        if ([identifier isEqual:@"thirdPartyCookies"] && [value isEqual:@2]) value = @0;
        // Preserve the privacy intent of the previous cookie-only session mode.
        if ([identifier isEqual:@"cookies"] && [value isEqual:@4]) value = @2;
        if (value && [self validateValue:value forSetting:setting error:nil]) _local[identifier] = value;
      }
    }
  }
  return self;
}
+ (NSArray<NSString *> *)categories {
  NSArray *order = @[@"Default browser", @"Privacy & security", @"Site permissions", @"Search engine", @"Appearance", @"On startup", @"Performance", @"Downloads", @"Accessibility", @"Reset settings", @"Import profiles"];
  NSMutableArray *categories = [NSMutableArray array];
  for (NSString *category in order) {
    BOOL present = [@[@"Default browser", @"Reset settings", @"Import profiles"] containsObject:category];
    for (NSDictionary *setting in self.catalogue) if ([setting[@"category"] isEqual:category]) { present = YES; break; }
    if (present) [categories addObject:category];
  }
  return categories;
}
- (void)importProfile:(NSDictionary *)profile fromBrowser:(NSDictionary *)browser completion:(void (^)(NSString *))completion {
  static dispatch_queue_t queue; static dispatch_once_t once;
  dispatch_once(&once, ^{ queue = dispatch_queue_create("Talaria.BrowserProfileImport", DISPATCH_QUEUE_SERIAL); });
  dispatch_async(queue, ^{
    NSError *error;
    NSDictionary *data = [TLBrowserProfileImporter readProfile:profile browser:browser error:&error];
    NSMutableArray *sessions = [NSMutableArray array];
    if ([data[@"storage"] count]) for (NSDictionary *cookie in data[@"cookies"]) if (![cookie[@"persistent"] boolValue]) [sessions addObject:cookie];
    BOOL staged = data && [TLBrowserProfileImporter stageLocalStorage:data[@"storage"] sessionCookies:sessions profileURL:self.class.profileURL error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!staged) { completion(error.localizedDescription ?: @"The browser profile could not be imported."); return; }
      [[TLWebKitBrowserController sharedController] importCookies:data[@"cookies"] completion:^(NSUInteger imported, NSUInteger failed) {
        NSUInteger storage = [data[@"storage"] count], skipped = [data[@"skipped"] unsignedIntegerValue];
        NSMutableString *message = [NSMutableString stringWithFormat:@"Imported %lu cookies from %@ — %@.", (unsigned long)imported, browser[@"name"], profile[@"name"]];
        if (storage) [message appendFormat:@" Restart Talaria to apply %lu local storage entries.", (unsigned long)storage];
        if (skipped) [message appendFormat:@" Skipped %lu expired or isolated items (partitions, containers, or non-web origins).", (unsigned long)skipped];
        if (failed) [message appendFormat:@" %lu cookies could not be saved; retry the import after restarting Talaria.", (unsigned long)failed];
        completion(message);
      }];
    });
  });
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
    add(@"cookies",privacy,@"Cookies",@"Allow sites to keep you signed in, or block cookies.",@"content",@"cookies",@1,@[@1,@2],@[@"Allow",@"Block"]);
    add(@"thirdPartyCookies",privacy,@"Third-party cookies",@"Control cookies set by content embedded from other sites.",@"profile",@"profile.cookie_controls_mode",@1,@[@1,@0],@[@"Block",@"Allow"]);
    add(@"safeBrowsing",privacy,@"Fraudulent website warnings",@"Show WebKit’s warning when it identifies a potentially fraudulent website.",@"profile",@"safebrowsing.enabled",@YES,nil,nil);
    add(@"httpsOnly",privacy,@"Always use secure connections",@"Upgrade website navigation to HTTPS. Pages without a secure connection fail to load.",@"profile",@"https_only_mode_enabled",@NO,nil,nil);
    NSArray *permissions = @[
      @[@"javascript",@"JavaScript",@"Allow sites to run scripts.",@1], @[@"images",@"Images",@"Allow sites to display images.",@1],
      @[@"popups",@"Pop-ups",@"Allow sites to open additional windows automatically.",@2], @[@"sound",@"Sound",@"Allow sites to play audio.",@1],
      @[@"geolocation",@"Location",@"Control requests for your location.",@3], @[@"media_stream_camera",@"Camera",@"Control camera requests. macOS permission is also required.",@3],
      @[@"media_stream_mic",@"Microphone",@"Control microphone requests. macOS permission is also required.",@3],
      @[@"sensors",@"Motion sensors",@"Allow sites to access motion sensors.",@1]];
    for (NSArray *p in permissions) {
      BOOL asks = [p[3] intValue] == 3;
      add(p[0],@"Site permissions",p[1],p[2],@"content",p[0],p[3],asks ? @[@3,@2] : @[@1,@2], asks ? @[@"Ask first",@"Block"] : @[@"Allow",@"Block"]);
    }
    add(@"searchEngine",@"Search engine",@"Default search engine",@"Used for web searches from the browser address bar.",@"app",@"",@"https://www.google.com/search?q={searchTerms}",
      @[@"https://www.google.com/search?q={searchTerms}",@"https://duckduckgo.com/?q={searchTerms}",@"https://www.bing.com/search?q={searchTerms}",@"https://search.brave.com/search?q={searchTerms}",@"custom"],@[@"Google",@"DuckDuckGo",@"Bing",@"Brave",@"Custom"]);
    add(@"customSearchURL",@"Search engine",@"Custom search URL",@"Use an HTTPS URL with {searchTerms} where the query belongs.",@"app",@"",@"https://duckduckgo.com/?q={searchTerms}",nil,nil);
    add(@"addressBarMode",@"Search engine",@"Address bar text",@"Choose what happens when you enter text instead of a URL. The chat composer always sends messages to Hermes.",@"app",@"",@"search",@[@"search",@"assistant"],@[@"Search the web",@"Ask Hermes"]);
    add(@"zoom",@"Appearance",@"Default page zoom",@"Apply to open browser tabs and new pages.",@"app",@"",@100,@[@50,@67,@75,@90,@100,@110,@125,@150,@175,@200,@250,@300],@[@"50%",@"67%",@"75%",@"90%",@"100%",@"110%",@"125%",@"150%",@"175%",@"200%",@"250%",@"300%"]);
    add(@"fontSize",@"Appearance",@"Font size",@"Default size for text on websites that use the browser’s font settings.",@"profile",@"webkit.webprefs.default_font_size",@16,@[@12,@14,@16,@18,@20,@24],@[@"12",@"14",@"16",@"18",@"20",@"24"]);
    add(@"minimumFont",@"Appearance",@"Minimum font size",@"Keep small text readable on web pages.",@"profile",@"webkit.webprefs.minimum_font_size",@0,@[@0,@9,@12,@14,@16,@18,@24],@[@"None",@"9",@"12",@"14",@"16",@"18",@"24"]);
    for (NSArray *font in @[@[@"standard",@"Standard font",@"Times"],@[@"fixed",@"Fixed-width font",@"Menlo"]]) {
      add([@"font_" stringByAppendingString:font[0]],@"Appearance",font[1],@"Choose a font family installed on your Mac.",@"profile",[@"webkit.webprefs.fonts." stringByAppendingFormat:@"%@.Zyyy",font[0]],font[2],nil,nil);
      items.lastObject[@"type"] = @"font";
    }
    add(@"startup",@"On startup",@"When Talaria starts",@"Choose which browser tabs open. Your chats and other workspace tabs are preserved.",@"app",@"",@"restore",@[@"restore",@"empty",@"pages"],@[@"Restore browser tabs",@"No browser tabs",@"Open specific pages"]);
    add(@"startupPages",@"On startup",@"Startup pages",@"Enter complete HTTP or HTTPS URLs, one per line.",@"app",@"",@"",nil,nil); items.lastObject[@"type"] = @"multiline";
    add(@"pauseBackground",@"Performance",@"Pause background tabs",@"Suspend scripts and media in hidden tabs after the delay below. Tabs resume when you return to them.",@"app",@"",@NO,nil,nil);
    add(@"pauseDelay",@"Performance",@"Pause after",@"Time a tab must stay hidden before it is paused.",@"app",@"",@300,@[@60,@300,@900,@1800],@[@"1 minute",@"5 minutes",@"15 minutes",@"30 minutes"]);
    add(@"downloadDirectory",@"Downloads",@"Download location",@"Save downloaded files in this folder.",@"profile",@"download.default_directory",NSHomeDirectory(),nil,nil); items.lastObject[@"type"] = @"directory";
    add(@"askDownload",@"Downloads",@"Ask where to save each file",@"Show a Save dialog before each download.",@"profile",@"download.prompt_for_download",@YES,nil,nil);
    add(@"pdfDownload",@"Downloads",@"Download PDF files",@"Save PDFs instead of opening them in the built-in viewer.",@"profile",@"plugins.always_open_pdf_externally",@NO,nil,nil);
    add(@"tabLinks",@"Accessibility",@"Tab through links",@"Include links when moving keyboard focus through a web page.",@"profile",@"webkit.webprefs.tabs_to_links",@YES,nil,nil);
    add(@"smoothMouseWheelScrolling",@"Accessibility",@"Smooth mouse-wheel scrolling",@"Ease mouse-wheel steps. Trackpad scrolling stays native. Disabled while Reduce Motion is on.",@"app",@"",@YES,nil,nil);
    // Keep the catalogue limited to controls the embedded engine can honor.
    NSIndexSet *removed = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *setting, NSUInteger index, BOOL *stop) {
      return ![TLWebKitBrowserSettings supportsSettingID:setting[@"id"]];
    }];
    [items removeObjectsAtIndexes:removed];
    catalogue = items.copy;
  }); return catalogue;
}
+ (NSDictionary *)settingWithID:(NSString *)identifier { for (NSDictionary *s in self.catalogue) if ([s[@"id"] isEqual:identifier]) return s; return nil; }
- (id)localValue:(NSString *)identifier { return self.local[identifier] ?: [self.class settingWithID:identifier][@"default"]; }
- (void)prepareInWindow:(NSWindow *)window completion:(void (^)(NSError *))completion {
  [TLWebKitBrowserController.sharedController prepareBrowserSettingsInWindow:window completion:completion];
}
- (NSDictionary *)stateForSetting:(NSDictionary *)setting {
  NSMutableDictionary *state = [[TLWebKitBrowserController.sharedController browserSettingState:setting] mutableCopy];
  state[@"value"] = [self localValue:setting[@"id"]];
  return state;
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
    else if ([type isEqual:@"font"] && ![NSFontManager.sharedFontManager.availableFontFamilies containsObject:value]) message = @"Choose an installed font family.";
    else if ([type isEqual:@"directory"]) { BOOL directory = NO; if (![value isAbsolutePath] || ![NSFileManager.defaultManager fileExistsAtPath:value isDirectory:&directory] || !directory || ![NSFileManager.defaultManager isWritableFileAtPath:value]) message = @"Choose an existing writable folder."; }

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
    NSDictionary *state = [self stateForSetting:setting];
    if (![state[@"available"] boolValue]) { if (error) *error = TLBrowserPreferenceError(state[@"reason"] ?: @"This setting is unavailable."); return NO; }
    if (![self persistValue:value forSetting:setting error:error]) return NO;
  } else if (![TLWebKitBrowserController.sharedController setBrowserSetting:setting value:value error:error]) return NO;
  [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserPreferencesDidChangeNotification object:self userInfo:@{@"id":setting[@"id"]}];
  return YES;
}
- (BOOL)persistValue:(id)value forSetting:(NSDictionary *)setting error:(NSError **)error {
  NSDictionary *canonical = [self.class settingWithID:setting[@"id"]];
  if (!canonical || ![canonical isEqual:setting]) { if (error) *error = TLBrowserPreferenceError(@"Unknown browser setting."); return NO; }
  if (value && ![self validateValue:value forSetting:setting error:error]) return NO;
  NSMutableDictionary *next = self.local.mutableCopy;
  if (value) next[setting[@"id"]] = value; else [next removeObjectForKey:setting[@"id"]];
  if (![self persist:next error:error]) return NO;
  self.local = next;
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
  [TLWebKitBrowserController.sharedController clearBrowserData:kind completion:completion];
}
- (BOOL)resetDefaults:(NSError **)error {
  for (NSDictionary *setting in self.class.catalogue) {
    if (![[self stateForSetting:setting][@"available"] boolValue]) continue;
    if (![TLWebKitBrowserController.sharedController setBrowserSetting:setting value:nil error:error]) return NO;
  }
  if (![self persist:@{} error:error]) return NO;
  [self.local removeAllObjects];
  [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserPreferencesDidChangeNotification object:self];
  return YES;
}
@end
