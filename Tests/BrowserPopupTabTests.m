#import <AppKit/AppKit.h>
#import "TalariaWindowController.h"
#import "TLBrowserTabController.h"
#import "TLMainWindow.h"
#import "TLBrowserPreferences.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"
#import "design_system/UIComponents.h"

@interface TalariaWindowController (PopupTabTests)
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)updateBrowserTabColorSample;
- (TLBrowserTabController *)activeBrowserController;
- (void)applyTheme;
- (TLWorkspaceTab *)activeWorkspaceTab;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)left;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
@end
@interface TLPopupTabTestController : TalariaWindowController
@end
@implementation TLPopupTabTestController
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
@end
static void Check(BOOL condition, NSString *message) {
  NSLog(@"%@: %@", condition ? @"PASS" : @"FAIL", message);
  if (!condition) exit(1);
}
static void Later(double seconds, dispatch_block_t block) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds*NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
@interface TLPopupTabTestDelegate : NSObject <NSApplicationDelegate>
@property TLPopupTabTestController *owner;
@property TLBrowserTabController *browser;
@end
@implementation TLPopupTabTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  NSArray *args = NSProcessInfo.processInfo.arguments;
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(100,100,1100,700)
    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
    backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.titleVisibility = NSWindowTitleHidden; window.titlebarAppearsTransparent = YES;
  self.owner = [[TLPopupTabTestController alloc] initWithWindow:window];
  TLDatabase *database = [[TLDatabase alloc] initWithURL:[NSURL fileURLWithPath:args[2]] error:nil];
  [self.owner setValue:database forKey:@"database"];
  [self.owner setValue:[TLAppStateManager new] forKey:@"appStateManager"];
  [self.owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [self.owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [self.owner setValue:[TLAppSettings defaultSettings] forKey:@"settings"];
  [self.owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  [self.owner setValue:[NSMutableArray array] forKey:@"agents"];
  [self.owner setValue:[NSMutableArray array] forKey:@"chats"];
  [self.owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [self.owner setValue:@1 forKey:@"nextBrowserTabID"];
  [self.owner buildInterface]; [self.owner installAppStateBindings];
  [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  [self.owner startNewChatWithModel:@"test" focus:NO];
  [self.owner openBrowserTabWithURL:[NSURL URLWithString:args[1]]];
  Later(3, ^{ [self checkPage]; });
  Later(40, ^{ Check(NO, @"Desktop popup-tab test deadline"); });
}
- (void)checkPage {
  self.browser=[self.owner activeBrowserController];
  NSError *error=nil;
  [TLBrowserPreferences.sharedPreferences saveValue:@1 forSetting:[TLBrowserPreferences settingWithID:@"popups"] error:&error];
  Check(!error,@"Enable script popups in disposable profile");
  [self openPopup:0];
}
- (void)openPopup:(NSUInteger)step {
  TLWebKitBrowserSession *opener=[self.browser valueForKey:@"browserSession"];
  NSUInteger windows=NSApp.windows.count;
  NSString *script=step==0 ? @"window.child=window.open('','fixture');child.document.write('<title>Child</title><p>Opener survives</p>');child.opener===window" : step==1 ? @"window.child=window.open(location.href,'_blank');!!child" : @"const a=document.createElement('a');a.href=location.href;a.target='_blank';document.body.append(a);a.click();true";
  [opener.webView evaluateJavaScript:script completionHandler:^(id value,NSError *error){
    Check(!error && [value boolValue],@"Script-created tab preserves window.open return value and opener");
    Later(.5,^{
      TLBrowserTabController *child=[self.owner activeBrowserController];
      TLWebKitBrowserSession *session=[child valueForKey:@"browserSession"];
      Check(child!=self.browser && session.webView.window==self.owner.window,@"Script destination opens as a tab in the original window");
      Check(NSApp.windows.count==windows,@"No additional native window created");
      Check(session.webView.configuration.websiteDataStore==opener.webView.configuration.websiteDataStore,@"Child preserves opener storage session");
      [session.webView evaluateJavaScript:step==0 ? @"document.body.innerText==='Opener survives' && opener!==null" : @"document.title==='Popup destination'" completionHandler:^(id result,NSError *error){
        Check(!error && [result boolValue],@"Blank document access and destination navigation survive tab routing");
        [session.webView evaluateJavaScript:@"window.close();true" completionHandler:^(id result,NSError *error){
          Later(.3,^{
            Check(child.isClosed && self.owner.window.visible && !self.browser.isClosed,@"window.close closes only the child tab");
            if(step<2)[self openPopup:step+1];else {NSLog(@"BrowserPopupTabTests passed");[NSApp terminate:nil];}
          });
        }];
      }];
    });
  }];
}
@end
int main(void) { @autoreleasepool {
  NSApplication *app=NSApplication.sharedApplication;
  TLPopupTabTestDelegate *delegate=[TLPopupTabTestDelegate new];app.delegate=delegate;[app run];
}return 0;}
