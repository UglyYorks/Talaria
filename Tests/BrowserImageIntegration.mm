// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
#import "ChromiumImageActions.h"
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
class TLImageTestMenuDelegate : public CefMenuModelDelegate {
 public: void ExecuteCommand(CefRefPtr<CefMenuModel>, int, cef_event_flags_t) override {}
 private: IMPLEMENT_REFCOUNTING(TLImageTestMenuDelegate);
};
@interface TLChromiumBrowserController (ImageTests)
- (void)openImageURL:(NSURL *)URL fromBrowser:(CefRefPtr<CefBrowser>)browser inNewWindow:(BOOL)newWindow;
@end
@interface TLImageProbeDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLChromiumBrowserSession *session;
@property NSString *baseURL;
@property BOOL started;
@property NSURL *openedURL;
@end
@implementation TLImageProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([TLBrowserPreferences.profileURL.path hasPrefix:@"/tmp/talaria-image-test-"], @"isolated profile");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  self.session = [TLChromiumBrowserController.sharedController loadURL:[NSURL URLWithString:self.baseURL] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) {
      if (![title isEqual:@"images ready"] || self.started) return;
      self.started = YES;
      dispatch_async(dispatch_get_main_queue(), ^{ [self testMenu]; [self readImage:0]; });
    } linkHandler:^(NSURL *URL, NSEventModifierFlags modifiers) { self.openedURL = URL; Check(modifiers == 0, @"image tab ignores menu modifiers"); }
    URLHandler:nil faviconHandler:nil navigationHandler:nil];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,40*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"image integration timeout"); });
}
- (CefRefPtr<CefBrowser>)browser { return [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier]; }
- (void)testMenu {
  auto model = CefMenuModel::CreateMenuModel(new TLImageTestMenuDelegate());
  TLChromiumPopulateImageMenu(model, [self.baseURL stringByAppendingString:@"/image.png"], YES);
  Check(model->GetCount() == 16, @"image menu has all twelve actions and four separators");
  NSArray *expected = @[@"Open Image in New Tab", @"Open Image in New Window", @"", @"Save Image to “Downloads”", @"Save Image As…", @"Add Image to Photos", @"Use Image as Desktop Wallpaper", @"", @"Copy Image Address", @"Copy Image", @"Copy Subject", @"Look Up", @"", @"Share…", @"", @"Inspect Element"];
  for (NSUInteger i=0; i<expected.count; i++) {
    NSString *title = [NSString stringWithUTF8String:model->GetLabelAt(i).ToString().c_str()];
    Check([title isEqual:expected[i]], [NSString stringWithFormat:@"image menu row %lu: %@",(unsigned long)i,title]);
  }
  Check(!model->IsEnabled(TLChromiumImageCommandFirst + TLBrowserImageLookUp), @"Look Up matches disabled reference state");
  TLChromiumPopulateImageMenu(model, [self.baseURL stringByAppendingString:@"/missing.png"], NO);
  Check(!model->IsEnabled(TLChromiumImageCommandFirst + TLBrowserImageCopy) && model->IsEnabled(TLChromiumImageCommandFirst + TLBrowserImageCopyAddress), @"broken image permits address actions without pretending content is available");
  for (NSString *URL in @[@"javascript:alert(1)",@"data:text/html,hello",@"file:///etc/passwd",@"https:"]) Check(!TLBrowserImageURLIsSupported([NSURL URLWithString:URL]), @"unsafe image navigation rejected");
  model->Clear(); model->AddItem(MENU_ID_COPY,"Copy");
  [self browser]->GetHost()->GetClient()->GetContextMenuHandler()->OnBeforeContextMenu([self browser], [self browser]->GetMainFrame(), nullptr, model);
  Check(model->GetCount() == 10 && model->GetCommandIdAt(0) == MENU_ID_COPY && model->GetIndexOf(TLChromiumImageCommandFirst) < 0, @"page/editing context menu remains unchanged");
  NSURL *URL = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"/image.png"]];
  [TLChromiumBrowserController.sharedController openImageURL:URL fromBrowser:[self browser] inNewWindow:NO];
  Check([self.openedURL isEqual:URL], @"Open Image in New Tab uses workspace tab handler");
}
- (void)readImage:(NSUInteger)index {
  NSArray *paths = @[@"/image.png", @"/animation.gif", @"/vector.svg"];
  if (index == paths.count) { [self testBlob]; return; }
  NSURL *URL = [NSURL URLWithString:[self.baseURL stringByAppendingString:paths[index]]];
  TLChromiumReadImage([self browser], URL, self.baseURL, ^(TLBrowserImageResource *resource, NSError *error) {
    NSData *expected = [NSData dataWithContentsOfURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:[paths[index] lastPathComponent]]];
    Check(!error && [resource.data isEqual:expected], [NSString stringWithFormat:@"cached %@ preserves exact original bytes and format",paths[index]]);
    Check(resource.image != nil, @"image formats expose pixels for native image actions");
    Check([resource.fileName isEqual:[paths[index] lastPathComponent]], @"image filename retains matching extension");
    if (index == 0) [self testSave:resource URL:URL completion:^{ [self readImage:index+1]; }]; else [self readImage:index+1];
  });
}
- (void)testSave:(TLBrowserImageResource *)resource URL:(NSURL *)URL completion:(dispatch_block_t)completion {
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
  Check([TLBrowserImageActions copyImage:resource.image toPasteboard:pasteboard] && [NSImage canInitWithPasteboard:pasteboard], @"Copy Image writes actual image data");
  [pasteboard releaseGlobally];
  TLBrowserDownloadManager *manager = [[TLBrowserDownloadManager alloc] initWithHistoryURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"image-history.json"]];
  NSURL *destination = [TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"Saved/image.png"];
  [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:NO manager:manager completion:^(NSError *error) {
    Check(!error && manager.downloads.firstObject.fileAvailable, @"quick save is recorded as a completed download");
    [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:NO manager:manager completion:^(NSError *error) {
      Check(!error && manager.downloads.count == 2 && ![manager.downloads[0].path isEqual:manager.downloads[1].path], @"quick save never overwrites an existing image");
      Check([[NSData dataWithContentsOfURL:destination] isEqual:resource.data], @"saved image matches original content");
      [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:YES manager:manager completion:^(NSError *error) {
        Check(!error && [manager.downloads.firstObject.path isEqual:destination.path], @"Save As honors the explicitly chosen destination");
        [TLBrowserImageActions saveResource:resource URL:URL destination:[destination URLByAppendingPathComponent:@"impossible.png"] overwrite:NO manager:manager completion:^(NSError *error) {
          Check(error && manager.downloads.firstObject.state == TLBrowserDownloadStateFailed, @"write errors produce a failed download instead of phantom activity");
          for (NSSharingServiceName name in @[NSSharingServiceNameAddToIPhoto, NSSharingServiceNameUseAsDesktopPicture]) {
            Check([[NSSharingService sharingServiceNamed:name] canPerformWithItems:@[resource.image]], @"native Photos/wallpaper service accepts image content");
          }
          [TLBrowserImageActions copySubjectOfImage:resource.image completion:^(NSImage *subject, NSError *error) {
            Check(subject != nil || error.localizedDescription.length > 0, @"subject extraction returns pixels or an actionable no-subject error");
            completion();
          }];
        }];
      }];
    }];
  }];
}
- (void)testBlob {
  CefRefPtr<TLProbeEvaluation> evaluation = new TLProbeEvaluation(^(NSString *URLString) {
    NSURL *URL = [NSURL URLWithString:URLString];
    Check(TLBrowserImageURLIsSupported(URL), @"blob image URL can open in a browser tab");
    TLChromiumReadImage([self browser], URL, self.baseURL, ^(TLBrowserImageResource *resource, NSError *error) {
      Check(!error && resource.image && resource.data.length, @"blob image can be read using the owning browser");
      [TLChromiumBrowserController.sharedController closeSession:self.session];
      [NSApp terminate:nil];
    });
  });
  evaluation->Start([self browser], "document.getElementById('blob').src");
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [TLChromiumBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [TLChromiumBrowserController.sharedController shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  TLChromiumBrowserControllerConfigureMainArgs(argc,argv);
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLImageProbeDelegate *delegate; delegate = [TLImageProbeDelegate new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app finishLaunching]; [app run]; return 0;
}}
