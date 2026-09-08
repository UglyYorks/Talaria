// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
#import "ChromiumImageActions.h"
#import "TLBrowserLinkActions.h"
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
- (void)chooseLinkedDownloadPath:(NSString *)path fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion;
- (void)openImageURL:(NSURL *)URL fromBrowser:(CefRefPtr<CefBrowser>)browser inNewWindow:(BOOL)newWindow;
@end
@interface TLLinkTestBrowser : TLChromiumBrowserController
@property NSURL *destination;
@property NSWindow *sourceWindow;
@property NSUInteger promptCount;
@property BOOL cancelNext;
@end
@implementation TLLinkTestBrowser
- (void)chooseLinkedDownloadPath:(NSString *)path fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion {
  self.promptCount++;
  Check(window == self.sourceWindow && window.isVisible, @"Save As belongs to the visible originating window");
  Check([path.lastPathComponent hasPrefix:@"linked-file"] && [path.pathExtension isEqual:@"txt"], @"Save As uses the server's suggested filename");
  completion(self.cancelNext ? nil : self.destination);
}
@end
@interface TLLinkProbeDelegate : NSObject <NSApplicationDelegate>
@property TLLinkTestBrowser *browser;
@property NSWindow *window;
@property TLChromiumBrowserSession *session;
@property NSString *baseURL;
@property NSString *groupID;
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
  self.browser = [TLLinkTestBrowser new]; self.browser.sourceWindow = self.window;
  self.browser.destination = [TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"chosen.txt"];
  self.session = [self.browser loadURL:[NSURL URLWithString:self.baseURL] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) {
      if (![title isEqual:@"Link menu fixture"] || self.started) return;
      self.started = YES; dispatch_async(dispatch_get_main_queue(), ^{ [self testStore]; [self testMenu]; });
    } linkHandler:^(NSURL *URL, NSEventModifierFlags flags) { self.openedURL = URL; } URLHandler:nil faviconHandler:nil navigationHandler:nil];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"link integration timeout"); });
}
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)then attempt:(NSUInteger)attempt {
  if (condition()) { then(); return; }
  if (attempt >= 200) Check(NO, @"asynchronous link action completes");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self waitFor:condition then:then attempt:attempt+1]; });
}
- (NSURL *)URL:(NSString *)path { return [NSURL URLWithString:[self.baseURL stringByAppendingString:path]]; }
- (void)testStore {
  NSError *error = nil;
  NSURL *file = [TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"TestGroups.json"];
  TLBrowserLinkStore *store = [[TLBrowserLinkStore alloc] initWithURL:file];
  NSString *group = [store createGroupNamed:@"Research" error:&error];
  Check(group.length && !error, @"named tab group is created");
  Check([store addURL:[self URL:@"/one"] title:@"First" collection:group error:&error], @"link saved in tab group");
  [store addURL:[self URL:@"/one"] title:@"Updated" collection:group error:&error];
  store = [[TLBrowserLinkStore alloc] initWithURL:file];
  Check(store.groups.count == 1 && [store linksInCollection:group].count == 1 && [[[store linksInCollection:group] firstObject][@"title"] isEqual:@"Updated"], @"groups persist and duplicate links update their existing entry");
  Check(![store addURL:[NSURL URLWithString:@"javascript:alert(1)"] title:@"Unsafe" collection:group error:&error], @"executable link is not persisted as a browser tab");
  Check([store removeGroup:group error:&error] && !store.groups.count, @"saved tab group can be removed");
  self.groupID = [TLBrowserLinkStore.sharedStore createGroupNamed:@"Link Test Group" error:&error];
}
- (void)testMenu {
  NSURL *URL = [self URL:@"/one"];
  __block BOOL downloaded = NO, saveAs = NO;
  NSMenu *menu = [TLBrowserLinkActions menuForURL:URL title:@"A link" view:self.window.contentView point:NSZeroPoint
    open:^(NSURL *URL, TLBrowserLinkDestination destination, NSString *groupID) { self.menuDestination = destination; self.openedURL = URL; }
    download:^(BOOL ask) { downloaded = YES; saveAs = ask; } inspect:^{}];
  NSArray *expected = @[@"Open Link in New Tab",@"Open Link in New Window",@"Open Link in Tab Group",@"",@"Download Linked File",@"Download Linked File As…",@"",@"Copy Link",@"",@"Share…",@"",@"Inspect Element",@"",@"Services"];
  Check(menu.numberOfItems == expected.count, @"link menu has all requested options, excluding bookmarks and reading list");
  for (NSUInteger i=0; i<expected.count; i++) Check([[menu itemAtIndex:i].title isEqual:expected[i]], [NSString stringWithFormat:@"link menu row %lu",(unsigned long)i]);
  Check([menu itemAtIndex:2].submenu.numberOfItems == 3, @"tab-group submenu offers new and existing groups");
  Check([menu itemAtIndex:7].image && [menu itemAtIndex:9].image && [menu itemAtIndex:13].image, @"copy, share and Services have native icons");
  TLLinkServicesView *requestor = [TLLinkServicesView new]; requestor.URL = URL;
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
  Check([requestor validRequestorForSendType:NSPasteboardTypeString returnType:nil] == requestor &&
        [requestor writeSelectionToPasteboard:pasteboard types:@[NSPasteboardTypeString, NSPasteboardTypeURL]] &&
        [[pasteboard stringForType:NSPasteboardTypeString] isEqual:URL.absoluteString], @"Services receives the clicked URL rather than unrelated page selection");
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
      [menu performActionForItemAtIndex:4];
      dispatch_async(dispatch_get_main_queue(), ^{
        Check(downloaded && !saveAs, @"Download Linked File requests direct saving");
        [menu performActionForItemAtIndex:5];
        dispatch_async(dispatch_get_main_queue(), ^{
          Check(saveAs, @"Download Linked File As requests a dialog");
          [[menu itemAtIndex:2].submenu performActionForItemAtIndex:2];
          dispatch_async(dispatch_get_main_queue(), ^{
            Check(self.menuDestination == TLBrowserLinkTabGroup && [TLBrowserLinkStore.sharedStore linksInCollection:self.groupID].count == 1, @"existing-group action saves the link in the selected group");
            [self testDownload];
          });
        });
      });
    });
  });
}
- (void)testDownload {
  NSError *error = nil;
  NSString *directory = [TLBrowserPreferences.profileURL.path stringByAppendingPathComponent:@"Downloads"];
  [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
  Check([self.browser setBrowserSetting:[TLBrowserPreferences settingWithID:@"downloadDirectory"] value:directory error:&error], @"configure temporary download directory");
  Check([self.browser setBrowserSetting:[TLBrowserPreferences settingWithID:@"askDownload"] value:@YES error:&error], @"enable ordinary download prompts");
  [self.browser downloadLinkedURL:[self URL:@"/download?quick"] fromWindow:self.window askForDestination:NO];
  [self waitFor:^BOOL { return TLBrowserDownloadManager.sharedManager.downloads.firstObject.state == TLBrowserDownloadStateComplete; } then:^{
    Check(self.browser.promptCount == 0 && TLBrowserDownloadManager.sharedManager.downloads.firstObject.fileAvailable, @"direct linked download bypasses prompt preference and enters Downloads");
    NSError *error = nil;
    [self.browser setBrowserSetting:[TLBrowserPreferences settingWithID:@"askDownload"] value:@NO error:&error];
    [self.browser downloadLinkedURL:[self URL:@"/download?as"] fromWindow:self.window askForDestination:YES];
    [self waitFor:^BOOL { return self.browser.promptCount == 1 && TLBrowserDownloadManager.sharedManager.downloads.firstObject.state == TLBrowserDownloadStateComplete; } then:^{
      Check([[NSData dataWithContentsOfURL:self.browser.destination] isEqual:[@"linked file fixture" dataUsingEncoding:NSUTF8StringEncoding]], @"Save As ignores prompt preference and writes the selected path");
      self.browser.cancelNext = YES;
      [self.browser downloadLinkedURL:[self URL:@"/download?cancel"] fromWindow:self.window askForDestination:YES];
      [self waitFor:^BOOL { return self.browser.promptCount == 2 && TLBrowserDownloadManager.sharedManager.downloads.firstObject.state == TLBrowserDownloadStateCancelled; } then:^{
        Check(!TLBrowserDownloadManager.sharedManager.downloads.firstObject.active, @"cancelling Save As leaves no active transfer"); [self testGroups];
      } attempt:0];
    } attempt:0];
  } attempt:0];
}
- (NSArray<NSWindow *> *)groupWindows {
  NSString *identifier = [@"Talaria.BrowserGroup." stringByAppendingString:self.groupID];
  return [NSApp.windows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSWindow *window, NSDictionary *bindings) { return [window.tabbingIdentifier isEqual:identifier]; }]];
}
- (void)testGroups {
  [self.browser openURL:[self URL:@"/one"] inTabGroup:self.groupID fromWindow:self.window];
  [self waitFor:^BOOL { return self.groupWindows.count == 1; } then:^{
    [self.browser openURL:[self URL:@"/two"] inTabGroup:self.groupID fromWindow:self.window];
    [self waitFor:^BOOL { return self.groupWindows.count == 2; } then:^{
      NSArray<NSWindow *> *windows = self.groupWindows;
      Check(windows[0].tabGroup == windows[1].tabGroup && windows[0].tabGroup.windows.count == 2, @"links open as real native tabs in the selected group");
      Check([windows[0].subtitle isEqual:@"Link Test Group"], @"grouped windows display the group name");
      [self.browser closeSession:self.session];
      dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
    } attempt:0];
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
