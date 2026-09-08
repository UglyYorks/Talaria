// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserPreferences.h"
#import "ChromiumImageActions.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLActionMenuItem.h"
#import "design_system/TLLinkServicesView.h"
#include "include/cef_client.h"
#include "include/cef_menu_model_delegate.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_request_context.h"
#include "include/cef_devtools_message_observer.h"
@interface TLProbeApplication : NSApplication <CefAppProtocol>
@property BOOL handlingSendEvent;
@end
@implementation TLProbeApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
@end
@interface TLChromiumBrowserController (Integration)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (void)checkBackgroundBrowsers;
- (void (^)(NSURL *))splitLinkHandlerForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)browserTitleChanged:(CefRefPtr<CefBrowser>)browser title:(NSString *)title;
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
class TLProbeEvaluation : public CefDevToolsMessageObserver {
 public:
 explicit TLProbeEvaluation(void (^completion)(id)) : completion_([completion copy]) {}
 void Start(CefRefPtr<CefBrowser> browser, const char *expression) {
   registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
   auto parameters = CefDictionaryValue::Create(); parameters->SetString("expression",expression); parameters->SetBool("returnByValue",true);
   identifier_ = browser->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",parameters);
 }
 void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,int identifier,bool success,const void *result,size_t size) override {
   if (identifier != identifier_) return;
   CefRefPtr<TLProbeEvaluation> keepAlive = this;
   NSDictionary *response = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
   auto completion = completion_; completion_ = nil; registration_ = nullptr;
   Check(success && !response[@"exceptionDetails"],@"read browser fixture state");
   completion(response[@"result"][@"value"]);
 }
 private:
 int identifier_ = 0;
 CefRefPtr<CefRegistration> registration_;
 void (^completion_)(id);
 IMPLEMENT_REFCOUNTING(TLProbeEvaluation);
};
@interface TLChromiumBrowserController (LinkTests)
- (void)openImageURL:(NSURL *)URL fromBrowser:(CefRefPtr<CefBrowser>)browser inNewWindow:(BOOL)newWindow;
@end
@interface TLLinkProbeDelegate : NSObject <NSApplicationDelegate>
@property TLChromiumBrowserController *browser;
@property NSWindow *window;
@property TLChromiumBrowserSession *session;
@property NSString *baseURL;
@property BOOL started;
@property NSInteger menuDestination;
@property NSURL *openedURL;
@end
@implementation TLLinkProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([TLBrowserPreferences.profileURL.path hasPrefix:@"/tmp/talaria-link-test-"], @"isolated profile");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  self.browser = [TLChromiumBrowserController new];
  self.session = [self.browser loadURL:[NSURL URLWithString:self.baseURL] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) {
      if (![title isEqual:@"Link menu fixture"] || self.started) return;
      self.started = YES; dispatch_async(dispatch_get_main_queue(), ^{ [self testMenu]; });
    } linkHandler:^(NSURL *URL, NSEventModifierFlags flags) { self.openedURL = URL; } URLHandler:nil faviconHandler:nil navigationHandler:nil];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"link integration timeout"); });
}
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)then attempt:(NSUInteger)attempt {
  if (condition()) { then(); return; }
  if (attempt >= 200) Check(NO, @"asynchronous link action completes");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self waitFor:condition then:then attempt:attempt+1]; });
}
- (NSURL *)URL:(NSString *)path { return [NSURL URLWithString:[self.baseURL stringByAppendingString:path]]; }
- (void)testCombinedMenu {
  NSMenu *images = [NSMenu new]; images.autoenablesItems = NO;
  __block NSInteger selectedImage = -1;
  NSArray *imageTitles = TLBrowserImageMenuTitles();
  for (NSUInteger i=0; i<imageTitles.count; i++) {
    if (i == TLBrowserImageSaveDownloads || i == TLBrowserImageCopyAddress || i == TLBrowserImageShare) [images addItem:NSMenuItem.separatorItem];
    NSMenuItem *item = [TLActionMenuItem itemWithTitle:imageTitles[i] action:^{ selectedImage = i; }];
    item.tag = TLChromiumImageCommandFirst + i; item.enabled = i != TLBrowserImageLookUp;
    [images addItem:item];
  }
  [images addItem:NSMenuItem.separatorItem];
  [images addItem:[TLActionMenuItem itemWithTitle:@"Inspect Element" action:^{}]];
  NSMenuItem *imageOpen = images.itemArray.firstObject;
  NSMenu *combined = [TLBrowserLinkActions menuForURL:[self URL:@"/one"] canSplit:YES view:self.window.contentView point:NSZeroPoint
    open:^(NSURL *, TLBrowserLinkDestination) {} inspect:^{} imageMenu:images];
  NSArray *expected = @[@"Open Link in New Tab",@"Open Link in New Window",@"Open Link in Split View",@"",
    @"Copy Link",@"",
    @"Open Image in New Tab",@"Open Image in New Window",@"",@"Save Image to “Downloads”",@"Save Image As…",
    @"Add Image to Photos",@"Use Image as Desktop Wallpaper",@"",@"Copy Image Address",@"Copy Image",@"Copy Subject",@"Look Up",@"",@"Share…",@"",@"Inspect Element"];
  Check([[combined.itemArray valueForKey:@"title"] isEqual:expected], @"linked-image menu matches the flat reference order with one Share and Inspect");
  Check([combined itemAtIndex:6] == imageOpen && ![combined itemWithTitle:@"Image"], @"image actions retain their targets and are directly accessible");
  Check(![combined itemWithTitle:@"Look Up"].enabled, @"combined menu preserves unavailable image-action states");
  [combined performActionForItemAtIndex:6];
  Check(selectedImage == TLBrowserImageOpenTab && imageOpen.tag == TLChromiumImageCommandFirst, @"image selection still routes to its original image command");
}
- (void)testMenu {
  [self testCombinedMenu];
  NSURL *URL = [self URL:@"/one"];
  NSMenu *menu = [TLBrowserLinkActions menuForURL:URL canSplit:YES view:self.window.contentView point:NSZeroPoint
    open:^(NSURL *URL, TLBrowserLinkDestination destination) { self.menuDestination = destination; self.openedURL = URL; }
    inspect:^{} imageMenu:nil];
  NSArray *expected = @[@"Open Link in New Tab",@"Open Link in New Window",@"Open Link in Split View",@"",@"Copy Link",@"",@"Share…",@"",@"Inspect Element",@"",@"Services"];
  Check(menu.numberOfItems == expected.count, @"link menu has all requested options, excluding bookmarks and reading list");
  for (NSUInteger i=0; i<expected.count; i++) Check([[menu itemAtIndex:i].title isEqual:expected[i]], [NSString stringWithFormat:@"link menu row %lu",(unsigned long)i]);
  Check([menu itemAtIndex:2].enabled && ![menu itemAtIndex:2].submenu, @"split opens directly without a submenu");
  Check([menu itemAtIndex:4].image && [menu itemAtIndex:6].image && [menu itemAtIndex:10].image, @"copy, share and Services have native icons");
  TLLinkServicesView *requestor = [TLLinkServicesView new]; requestor.URL = URL;
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
  Check([requestor validRequestorForSendType:NSPasteboardTypeString returnType:nil] == requestor &&
        [requestor writeSelectionToPasteboard:pasteboard types:@[NSPasteboardTypeString, NSPasteboardTypeURL]] &&
        [[pasteboard stringForType:NSPasteboardTypeString] isEqual:URL.absoluteString], @"Services receives the clicked URL rather than unrelated page selection");
  Check(NSEqualRanges(requestor.selectedRange, NSMakeRange(0, URL.absoluteString.length)), @"Services gets a real native selection for context filtering");
  Check([requestor validRequestorForSendType:@"public.plain-text" returnType:nil] == requestor &&
    [requestor writeSelectionToPasteboard:pasteboard types:@[@"public.plain-text"]] &&
    [[pasteboard stringForType:@"public.plain-text"] isEqual:URL.absoluteString], @"Terminal Services can request the clicked link as plain text");
  Check([requestor validRequestorForSendType:NSPasteboardTypeString returnType:NSPasteboardTypeString] != requestor,
    @"read-only link services do not advertise replacement of page text");
  Check([requestor writeSelectionToPasteboard:pasteboard types:@[@"NSStringPboardType"]] &&
    [[pasteboard stringForType:@"NSStringPboardType"] isEqual:URL.absoluteString], @"legacy AppKit Services can read the same link selection");
  [TLBrowserLinkActions copyURL:URL toPasteboard:pasteboard];
  Check(pasteboard.pasteboardItems.count == 1 && [[pasteboard stringForType:NSPasteboardTypeString] isEqual:URL.absoluteString] &&
    [[pasteboard stringForType:NSPasteboardTypeURL] isEqual:URL.absoluteString], @"Copy Link puts one URL on the clipboard in text and URL formats");
  [pasteboard releaseGlobally];
  [menu performActionForItemAtIndex:0];
  dispatch_async(dispatch_get_main_queue(), ^{
    Check(self.menuDestination == TLBrowserLinkNewTab && [self.openedURL isEqual:URL], @"new-tab menu action opens the clicked link");
    [menu performActionForItemAtIndex:1];
    dispatch_async(dispatch_get_main_queue(), ^{
      Check(self.menuDestination == TLBrowserLinkNewWindow, @"new-window action has a separate destination");
      [menu performActionForItemAtIndex:2];
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(self.menuDestination == TLBrowserLinkSplitView && [self.openedURL isEqual:URL], @"split menu action preserves the clicked link and its destination");
        CefRefPtr<CefBrowser> browser = [self.browser browserWithIdentifier:(int)self.session.browserIdentifier];
        __weak TLLinkProbeDelegate *weakSelf = self;
        self.session.splitLinkHandler = ^(NSURL *link) { weakSelf.openedURL = link; };
        void (^split)(NSURL *) = [self.browser splitLinkHandlerForBrowser:browser];
        Check(split != nil, @"CEF resolves the source session's split handler");
        split([self URL:@"/two"]);
        Check([self.openedURL isEqual:[self URL:@"/two"]], @"split request reaches the originating tab");
        [self testNewWindow];
      });
    });
  });
}
- (void)testNewWindow {
  CefRefPtr<CefBrowser> browser = [self.browser browserWithIdentifier:(int)self.session.browserIdentifier];
  [self.browser openImageURL:[self URL:@"/one"] fromBrowser:browser inNewWindow:YES];
  [self waitFor:^BOOL {
    for (NSWindow *window in NSApp.windows) {
      if (window != self.window && window.isVisible && [window.title isEqual:@"Link menu fixture"]) return YES;
    }
    return NO;
  } then:^{
    Check(YES, @"new-window links still open and receive page titles");
    [self testClosingTitle];
  } attempt:0];
}
- (void)testClosingTitle {
  CefRefPtr<CefBrowser> closing = [self.browser browserWithIdentifier:(int)self.session.browserIdentifier];
  self.window.title = @"Host window";
  [self.browser closeSession:self.session];
  Check([self.browser splitLinkHandlerForBrowser:closing] == nil, @"closed tabs cannot receive split requests");
  // Deliver the callback before deferred native teardown, when CEF is still
  // valid but the workspace tab and its title handler are already gone.
  Check(closing && closing->IsValid(), @"exercise title event during asynchronous tab closure");
  [self.browser browserTitleChanged:closing title:@"Late page title"];
  Check([self.window.title isEqual:@"Host window"], @"late embedded title cannot rename the host window");
  [self waitFor:^BOOL { return !closing->IsValid(); } then:^{
    [self.browser browserTitleChanged:closing title:@"After view destruction"];
    Check([self.window.title isEqual:@"Host window"], @"title after browser destruction is safely ignored");
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
  } attempt:0];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [self.browser prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [self.browser shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  TLChromiumBrowserControllerConfigureMainArgs(argc,argv);
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLLinkProbeDelegate *delegate; delegate = [TLLinkProbeDelegate new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app finishLaunching]; [app run]; return 0;
}}
