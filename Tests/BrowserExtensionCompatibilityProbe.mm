// Diagnostic for the macOS native-parent limitation, not an extension loader.
// Both browsers request Chrome style; one uses Talaria's native embedding model.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "ChromiumRunLoop.h"
#include "include/cef_application_mac.h"
#include "include/cef_client.h"
#include "include/cef_browser.h"
#include <vector>

@interface TLChromiumBrowserController (Probe)
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(NSView *)view;
- (void)browserClosed:(CefRefPtr<CefBrowser>)browser;
@end
@interface ProbeApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation ProbeApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scope; [super sendEvent:event]; }
@end
@interface ProbeRuntime : TLChromiumBrowserController
@end
@implementation ProbeRuntime
- (NSString *)chromiumCachePath { return NSProcessInfo.processInfo.arguments[2]; }
@end
static NSMutableArray *results;
static ProbeRuntime *runtime;
static std::vector<CefRefPtr<CefBrowser>> browsers;
class ProbeClient : public CefClient, public CefLifeSpanHandler, public CefDisplayHandler {
public:
  explicit ProbeClient(bool embedded): embedded_(embedded) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browsers.push_back(browser);
    [runtime browserCreated:browser parentView:nil];
    [results addObject:@{@"kind":@"creation", @"embedded":@(embedded_), @"id":@(browser->GetIdentifier()),
      @"requestedStyle":@"chrome", @"actualStyle":browser->GetHost()->GetRuntimeStyle()==CEF_RUNTIME_STYLE_CHROME?@"chrome":@"alloy"}];
  }
  void OnTitleChange(CefRefPtr<CefBrowser> browser,const CefString &title) override {
    NSString *value=[NSString stringWithUTF8String:title.ToString().c_str()];
    if (![value hasPrefix:@"PROBE:"]) return;
    id state=[NSJSONSerialization JSONObjectWithData:[[value substringFromIndex:6] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (state) [results addObject:@{@"kind":@"extension",@"embedded":@(embedded_),@"id":@(browser->GetIdentifier()),@"state":state}];
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (!embedded_) return false;
    // Match the app's embedded-view teardown; closing its host NSWindow alone
    // leaves CEF waiting for destruction of the child view.
    TLChromiumDeferToMainRunLoop(^{
      if (browser->IsValid()) {
        NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
        [view removeFromSuperview];
      }
    });
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { [runtime browserClosed:browser]; }
private:
  bool embedded_;
  IMPLEMENT_REFCOUNTING(ProbeClient);
};
@interface ProbeDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) NSWindow *window;
@end
@implementation ProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  results=[NSMutableArray array]; runtime=[ProbeRuntime new];
  NSArray *args=NSProcessInfo.processInfo.arguments;
  [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,700,450) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed=NO; self.window.title=@"Talaria embedded extension compatibility probe";
  [self.window makeKeyAndOrderFront:nil];
  if (![runtime initializeRuntimeFromWindow:self.window]) { [NSApp terminate:nil]; return; }
  for (bool embedded : {true,false}) {
    CefWindowInfo info;
    if (embedded) info.SetAsChild((__bridge void *)self.window.contentView,CefRect(0,0,700,450));
    else info.bounds=CefRect(850,100,700,450);
    info.runtime_style=CEF_RUNTIME_STYLE_CHROME;
    CefBrowserSettings settings;
    CefBrowserHost::CreateBrowser(info,new ProbeClient(embedded),[args[1] UTF8String],settings,nullptr,nullptr);
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    for (auto browser : browsers) {
      auto params=CefDictionaryValue::Create();
      params->SetString("expression","document.title='PROBE:'+JSON.stringify({url:location.href,extension:document.documentElement.dataset.extensionProbe||null})");
      browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
      [[NSJSONSerialization dataWithJSONObject:results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:args[3] atomically:YES];
      browsers.clear(); [NSApp terminate:nil];
    });
  });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [runtime prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv) {
  @autoreleasepool { TLChromiumBrowserControllerConfigureMainArgs(argc,argv); ProbeApplication *app=[ProbeApplication sharedApplication]; ProbeDelegate *delegate=[ProbeDelegate new]; app.delegate=delegate; [app run]; }
  return 0;
}
