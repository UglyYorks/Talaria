#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserTabController.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
@interface TLChromiumBrowserController (ExtensionTests)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(NSView *)view;
- (void)browserClosed:(CefRefPtr<CefBrowser>)browser;
@end
static CefRefPtr<CefBrowser> fixtureBrowser;
// Install via the normal unpacked-extension flow, answering only the test's
// folder chooser. CDP's debug installer marks extensions as session-only.
class TLFixtureInstallerClient : public CefClient, public CefLifeSpanHandler, public CefDialogHandler {
 public:
  explicit TLFixtureInstallerClient(TLChromiumBrowserController *runtime) : runtime_(runtime) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    fixtureBrowser = browser; [runtime_ browserCreated:browser parentView:nil];
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    fixtureBrowser = nullptr; [runtime_ browserClosed:browser];
  }
  bool OnFileDialog(CefRefPtr<CefBrowser> browser, FileDialogMode mode,
                    const CefString &title, const CefString &default_path,
                    const std::vector<CefString> &filters, const std::vector<CefString> &extensions,
                    const std::vector<CefString> &descriptions, CefRefPtr<CefFileDialogCallback> callback) override {
    NSString *record=[NSString stringWithFormat:@"mode=%d path=%@", mode, NSProcessInfo.processInfo.arguments[4]];
    [record writeToFile:[NSProcessInfo.processInfo.arguments[3] stringByAppendingString:@".dialog"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // CEF reports Chromium's extension folder picker as OPEN in this release.
    if (mode == FILE_DIALOG_OPEN || mode == FILE_DIALOG_OPEN_FOLDER)
      callback->Continue({[NSProcessInfo.processInfo.arguments[4] UTF8String]});
    else callback->Cancel();
    return true;
  }
 private:
  __unsafe_unretained TLChromiumBrowserController *runtime_;
  IMPLEMENT_REFCOUNTING(TLFixtureInstallerClient);
};
@interface TLExtensionTestApp : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation TLExtensionTestApp
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
@end
@interface TLExtensionTestRuntime : TLChromiumBrowserController
@end
@implementation TLExtensionTestRuntime
- (NSString *)chromiumCachePath { return NSProcessInfo.processInfo.arguments[2]; }
@end
@interface TLExtensionTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLExtensionTestRuntime *runtime;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) TLBrowserTabController *tab;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation TLExtensionTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
 [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
 NSArray *args=NSProcessInfo.processInfo.arguments;
 [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSMenu *menu=[NSMenu new]; NSMenuItem *item=[NSMenuItem new]; NSMenu *appMenu=[NSMenu new];
 [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"].target=NSApp;item.submenu=appMenu;[menu addItem:item];NSApp.mainMenu=menu;
 self.runtime=[TLExtensionTestRuntime new];
 self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(70,120,1000,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
 self.window.releasedWhenClosed=NO;self.window.title=@"Talaria embedded extension test";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
 self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:args[1]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:360 browserService:self.runtime];
#pragma clang diagnostic pop
 NSView *content=self.window.contentView;[content addSubview:self.tab.view];
 [NSLayoutConstraint activateConstraints:@[[self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[self.tab.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor],[self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
 [self.window makeKeyAndOrderFront:nil];[content layoutSubtreeIfNeeded];[self.tab startInWindow:self.window]; [NSApp activateIgnoringOtherApps:YES];
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){
   NSString *command=[NSString stringWithContentsOfFile:args[3] encoding:NSUTF8StringEncoding error:nil];
   if (!command.length) return;
   [NSFileManager.defaultManager removeItemAtPath:args[3] error:nil];
   if ([command isEqualToString:@"quit"]) [NSApp terminate:nil];
   else if ([command isEqualToString:@"manager"]) [self.runtime showExtensionsFromWindow:self.window];
   else if ([command isEqualToString:@"fixture-installer"]) {
     CefWindowInfo info; info.runtime_style=CEF_RUNTIME_STYLE_CHROME;
     CefBrowserSettings settings;
     CefBrowserHost::CreateBrowser(info,new TLFixtureInstallerClient(self.runtime),
       "chrome://extensions/?talaria-fixture",settings,nullptr,nullptr);
   }
   else if ([command isEqualToString:@"close-fixture-installer"]) {
     if (fixtureBrowser) fixtureBrowser->GetHost()->CloseBrowser(true);
   }
   else if ([command isEqualToString:@"close-manager"]) {
     NSInteger identifier=[[self.runtime valueForKey:@"extensionBrowserIdentifier"] integerValue];
     auto browser=[self.runtime browserWithIdentifier:(int)identifier];
     if (browser) browser->GetHost()->CloseBrowser(true);
   }
   else if ([command isEqualToString:@"snapshot"]) {
     TLChromiumBrowserSession *session=[self.tab valueForKey:@"browserSession"];
     auto browser=[self.runtime browserWithIdentifier:(int)session.browserIdentifier];
     NSView *view=browser ? (__bridge NSView *)browser->GetHost()->GetWindowHandle() : nil;
     NSDictionary *snapshot=@{@"embedded":@(view.superview==session.containerView),
       @"visible":@(!view.isHiddenOrHasHiddenAncestor && view.window.isVisible),
       @"width":@(NSWidth(view.bounds)),@"height":@(NSHeight(view.bounds)),
       @"alloy":@(browser && browser->GetHost()->GetRuntimeStyle()==CEF_RUNTIME_STYLE_ALLOY)};
     [[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:nil]
       writeToFile:[args[3] stringByAppendingString:@".snapshot"] atomically:YES];
   }
   else [self.runtime openExtensionURL:[NSURL URLWithString:command] fromWindow:self.window];
 }];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
 [self.timer invalidate];[self.tab close];return [self.runtime prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater;
}
@end
int main(int argc,char **argv) { @autoreleasepool {
 TLChromiumBrowserControllerConfigureMainArgs(argc,argv);TLExtensionTestApp *app=[TLExtensionTestApp sharedApplication];TLExtensionTestDelegate *delegate=[TLExtensionTestDelegate new];app.delegate=delegate;[app run];
}return 0;}
