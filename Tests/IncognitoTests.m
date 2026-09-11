#import <AppKit/AppKit.h>
#import "Database.h"
#import "TalariaWindowController.h"
#import "AgentOrchestrator.h"
#import "TLSettingsTabController.h"
#import "design_system/TLIncognitoPill.h"
#import "design_system/TLWorkspaceOutlineView.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface TLIncognitoTestCredentials : NSObject <TLCredentialStore>
@property(nonatomic) NSUInteger writes;
@end
@implementation TLIncognitoTestCredentials
- (NSString *)credentialForAccount:(NSString *)account error:(NSError **)error { return @"fixture-token"; }
- (BOOL)setCredential:(NSString *)credential forAccount:(NSString *)account error:(NSError **)error { self.writes++; return YES; }
- (BOOL)removeCredentialForAccount:(NSString *)account error:(NSError **)error { self.writes++; return YES; }
@end
@interface TalariaWindowController (IncognitoTests)
- (BOOL)windowShouldClose:(NSWindow *)window;
- (void)toggleSidebar:(id)sender;
@end
@interface TLIncognitoTestWindow : TalariaWindowController
@end
@implementation TLIncognitoTestWindow
- (void)prepareHermesCommands {}
- (void)refreshNotifications {}
- (void)showOnboardingDemoWindow:(id)sender {}
@end

@interface TLSettingsTabController (IncognitoTests)
- (NSView *)buildPluginsPage;
- (void)renderPlugins;
- (void)togglePlugin:(NSSwitch *)sender;
@end
@interface TLIncognitoPluginSettings : TLSettingsTabController
@property NSUInteger requests;
@end
@implementation TLIncognitoPluginSettings
- (void)buildSettingsTabContent {}
- (void)requestPlugins:(NSDictionary *)parameters { self.requests++; }
@end
static NSArray<NSView *> *Descendants(NSView *view) {
  NSMutableArray *result = [NSMutableArray arrayWithObject:view];
  for (NSView *child in view.subviews) [result addObjectsFromArray:Descendants(child)];
  return result;
}
static void CheckVisiblePlugin(TLDatabase *database) {
  for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:preference.integerValue];
    TLIncognitoPluginSettings *controller = [[TLIncognitoPluginSettings alloc]
      initWithSettings:TLAppSettings.defaultSettings database:database orchestrator:(id)[NSObject new] palette:palette];
    NSView *page = [controller buildPluginsPage];
    [controller setValue:@[
      @{@"id": @"ordinary", @"name": @"Ordinary plugin", @"description": @"Configurable", @"source": @"user",
        @"version": @"1", @"enabled": @YES, @"restart_required": @NO, @"error": @""},
      @{@"id": @"talaria-incognito", @"name": @"Talaria Incognito", @"description": @"Read-only memory",
        @"source": @"talaria", @"scope": @"incognito", @"version": @"1.0", @"read_only": @YES,
        @"enabled": @YES, @"restart_required": @NO, @"error": @""}] forKey:@"plugins"];
    [controller renderPlugins];
    NSStackView *rows = [controller valueForKey:@"pluginRows"];
    Check(rows.arrangedSubviews.count == 2, @"Incognito is visible beside installed plugins");
    NSUInteger switches = 0;
    BOOL scoped = NO;
    for (NSView *view in Descendants(rows)) {
      if ([view isKindOfClass:NSSwitch.class]) {
        switches++;
        Check([view.identifier isEqual:@"ordinary"] && [(NSSwitch *)view isEnabled], @"Ordinary plugins remain configurable");
      }
      if ([view isKindOfClass:NSTextField.class] &&
          [[(NSTextField *)view stringValue] containsString:@"Automatic in Incognito windows"]) scoped = YES;
    }
    Check(switches == 1 && scoped, @"Incognito explains its scope and offers no unsafe toggle in either theme");
    NSSwitch *forged = [NSSwitch new]; forged.identifier = @"talaria-incognito";
    [controller togglePlugin:forged];
    Check(controller.requests == 0, @"Stale or injected actions cannot toggle the Incognito policy");
    NSSearchField *search = [controller valueForKey:@"pluginSearch"];
    search.stringValue = @"incognito";
    [controller renderPlugins];
    Check(rows.arrangedSubviews.count == 1, @"Incognito can be found using plugin search");
    Check(page != nil, @"Plugins page is composed successfully");
  }
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSURL *folder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *error = nil;
    TLIncognitoTestCredentials *credentials = [TLIncognitoTestCredentials new];
    TLDatabase *normal = [[TLDatabase alloc] initWithURL:[folder URLByAppendingPathComponent:@"normal.sqlite3"] credentialStore:credentials error:&error];
    Check(normal != nil, error.localizedDescription);
    TLBundledAgentClient *closedClient = [[TLBundledAgentClient alloc] initWithVMService:(id)[NSObject new]];
    closedClient.incognitoID = @"closed-test-window";
    [closedClient closeIncognito];
    __block BOOL completed = NO;
    [closedClient hermesHistoryWithAgent:[TLAgentRecord new] action:@"list" sessionID:@"" token:@"" model:@""
      completion:^(NSDictionary *result, NSError *failure) {
        Check(result == nil && [failure.localizedDescription containsString:@"closed"], @"Closed private clients complete structured requests with an error");
        completed = YES;
      }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!completed && deadline.timeIntervalSinceNow > 0)
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(completed, @"Closing a private window cannot leave a structured request waiting");
    CheckVisiblePlugin(normal);
    TLAppSettings *settings = [normal appSettings:&error];
    settings.rememberOpenRouterToken = YES;
    settings.openRouterToken = @"fixture-token";
    [normal saveAppSettings:settings error:&error];
    NSUInteger writes = credentials.writes;
    TLChatRecord *chat = [normal createChatWithModel:settings.selectedModel error:&error];
    [normal saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:@"normal history" thinking:nil] chatID:chat.chatID error:&error];
    TLDatabase *private = [normal incognitoDatabase:&error];
    Check(private.incognito && !normal.incognito, @"Only the private database is Incognito");
    Check([private listChats:&error].count == 0, @"Private windows start without saved chats");
    Check([[private appSettings:&error].openRouterToken isEqual:@"fixture-token"], @"Private settings read existing credentials");
    TLChatRecord *privateChat = [private createChatWithModel:settings.selectedModel error:&error];
    [private saveMessage:[TLChatMessage messageWithRole:TLRoleUser content:@"private secret" thinking:nil] chatID:privateChat.chatID error:&error];
    Check([normal listChats:&error].count == 1, @"Private chats never enter the persistent database");
    Check([private recordBrowserVisitToURL:[NSURL URLWithString:@"https://private.invalid"] title:@"private" error:&error] == 0, @"Incognito never records browser visits");
    Check([normal listBrowserHistory:&error].count == 0, @"Normal browser history stays untouched");
    settings.openRouterToken = @"private-token";
    [private saveAppSettings:settings error:&error];
    Check(credentials.writes == writes, @"Private settings cannot mutate Keychain");
    TLAgentOrchestrator *orchestrator = [[TLAgentOrchestrator alloc] initWithDatabase:private agentClient:(id)[NSObject new] vmService:(id)[NSObject new]];
    TLIncognitoTestWindow *window = [[TLIncognitoTestWindow alloc] initWithDatabase:private agentOrchestrator:orchestrator appStateManager:[TLAppStateManager new]];
    Check(window.incognito, @"Window inherits private mode before building UI");
    TLIncognitoPill *pill = [window valueForKey:@"incognitoPill"];
    Check(pill != nil && !pill.hidden && [[window valueForKey:@"sidebarToggleButton"] isHidden], @"Incognito pill replaces sidebar icon");
    Check([[window valueForKey:@"workspaceOutline"] incognito], @"Content and active tab use the Incognito perimeter");
    for (NSNumber *preference in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
      TLThemePalette *palette = [TLThemePalette paletteForPreference:preference.integerValue];
      Check(palette.incognitoBorderWidth == 2.0, @"Incognito perimeter is two points in both themes");
      pill.palette = palette;
      pill.frame = NSMakeRect(0, 0, pill.intrinsicContentSize.width, pill.intrinsicContentSize.height);
      NSBitmapImageRep *bitmap = [pill bitmapImageRepForCachingDisplayInRect:pill.bounds];
      [pill cacheDisplayInRect:pill.bounds toBitmapImageRep:bitmap];
      Check(bitmap != nil && bitmap.pixelsWide > 0, @"Privacy pill renders in both themes");
    }
    Check(![[window valueForKey:@"sidebarVisible"] boolValue], @"Private sidebar starts hidden");
    [window toggleSidebar:nil];
    Check(![[window valueForKey:@"sidebarVisible"] boolValue], @"Private sidebar cannot be opened");
    __block BOOL closed = NO;
    window.incognitoDidClose = ^{ closed = YES; };
    Check([window windowShouldClose:window.window] && closed, @"Private close disposes of the window instead of hiding it");
    [window.window close];
    [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
    NSLog(@"Incognito database, window, and cleanup tests passed");
  }
  return 0;
}
