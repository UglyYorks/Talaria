// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserPreferences.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
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
@interface TLProbeDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLChromiumBrowserSession *session;
@property NSInteger stage;
@property NSString *baseURL;
@end
@implementation TLProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSString *profile = NSProcessInfo.processInfo.environment[@"TL_CHROMIUM_PROFILE_DIR"];
  Check([profile hasPrefix:@"/tmp/talaria-native-browser-test-"], @"test uses an isolated temporary profile");
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([self.baseURL hasPrefix:@"http://127.0.0.1:"], @"test fixture uses loopback only");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  [TLBrowserPreferences.sharedPreferences prepareInWindow:self.window completion:^(NSError *error) {
    Check(!error, @"embedded browser starts"); [self testPreferences];
  }];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"integration timeout"); });
}
- (void)set:(NSString *)identifier value:(id)value {
  NSError *error = nil;
  Check([TLBrowserPreferences.sharedPreferences saveValue:value forSetting:[TLBrowserPreferences settingWithID:identifier] error:&error], [NSString stringWithFormat:@"save %@ (%@)",identifier,error.localizedDescription ?: @"ok"]);
}
- (void)testPreferences {
  for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
    NSDictionary *state = [TLBrowserPreferences.sharedPreferences stateForSetting:setting];
    Check([state[@"available"] boolValue], [NSString stringWithFormat:@"native %@ is supported by this Chromium runtime",setting[@"id"]]);
  }
  BOOL secondRun = [NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_REOPEN"] boolValue];
  if (secondRun) {
    Check([[[TLBrowserPreferences.sharedPreferences stateForSetting:[TLBrowserPreferences settingWithID:@"doNotTrack"]] objectForKey:@"value"] boolValue], @"Chromium preference persists across desktop launches");
    Check([[TLBrowserPreferences.sharedPreferences localValue:@"zoom"] intValue] == 150, @"Talaria preference persists across desktop launches");
    [NSApp terminate:nil]; return;
  }
  [self set:@"doNotTrack" value:@YES];
  [self set:@"fontSize" value:@24];
  [self set:@"zoom" value:@150];
  [self set:@"javascript" value:@2];
  [self set:@"askDownload" value:@NO];
  NSString *downloadDirectory = [TLBrowserPreferences.profileURL.path stringByAppendingPathComponent:@"TestDownloads"];
  [NSFileManager.defaultManager createDirectoryAtPath:downloadDirectory withIntermediateDirectories:YES attributes:nil error:nil];
  [self set:@"downloadDirectory" value:downloadDirectory];
  self.stage = 0;
  self.session = [TLChromiumBrowserController.sharedController loadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/page"]] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) { [self title:title]; } linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
}
- (void)title:(NSString *)title {
  if (self.stage == 0 && [title isEqual:@"scripts off"]) {
    self.stage = 1;
    Check(YES,@"blocking JavaScript changes embedded page execution");
    Check(self.session.documentGeneration > 0,@"navigation advances browser document state alongside saved zoom");
    auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
    Check(browser && fabs(browser->GetHost()->GetZoomLevel() - log(1.5)/log(1.2)) < 0.001,@"new embedded tabs use saved page zoom");
    [self set:@"javascript" value:@1];
    [TLChromiumBrowserController.sharedController reloadSession:self.session];
  } else if (self.stage == 1 && [title hasPrefix:@"scripts on"]) {
    self.stage = 2;
    Check([title isEqual:@"scripts on:24px:1"],@"font size and Do Not Track apply to real web content");
    [self testUnchangedZoom];
  }
}
- (void)evaluate:(const char *)expression completion:(void (^)(id))completion {
  auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
  CefRefPtr<TLProbeEvaluation> evaluation = new TLProbeEvaluation(completion); evaluation->Start(browser,expression);
}
- (void)testUnchangedZoom {
  [self set:@"zoom" value:@100];
  auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
  auto parameters = CefDictionaryValue::Create();
  parameters->SetDouble("pageScaleFactor", 2);
  browser->GetHost()->ExecuteDevToolsMethod(0, "Emulation.setPageScaleFactor", parameters);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
    [self evaluate:"visualViewport.scale" completion:^(NSNumber *before) {
      Check(fabs(before.doubleValue-2)<0.01,@"fixture has a visible page-scale change");
      [self set:@"pauseDelay" value:@60];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
        [self evaluate:"visualViewport.scale" completion:^(NSNumber *after) {
          Check(fabs(after.doubleValue-before.doubleValue)<0.01,@"unchanged zoom does not reset the rendered page when preferences are applied");
          auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
          // Exercise the real main-document callback independently of the
          // renderer's own page-scale reset when it replaces a document.
          browser->GetHost()->GetClient()->GetLoadHandler()->OnLoadStart(browser, browser->GetMainFrame(), TT_LINK);
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            [self evaluate:"visualViewport.scale" completion:^(NSNumber *afterLoadStart) {
              Check(fabs(afterLoadStart.doubleValue-before.doubleValue)<0.01,@"main-document navigation callback does not issue a redundant visual reset");
              [self set:@"zoom" value:@150];
              auto browser = [TLChromiumBrowserController.sharedController browserWithIdentifier:(int)self.session.browserIdentifier];
              Check(fabs(browser->GetHost()->GetZoomLevel()-log(1.5)/log(1.2))<0.001,@"an actual zoom change still updates the browser");
              [self testBackgroundTabs];
            }];
          });
        }];
      });
    }];
  });
}
- (void)testBackgroundTabs {
  [self set:@"pauseBackground" value:@YES];
  [self set:@"pauseDelay" value:@60];
  self.window.contentView.hidden = YES;
  NSMutableDictionary *dates = [TLChromiumBrowserController.sharedController valueForKey:@"backgroundSince"];
  dates[@(self.session.browserIdentifier)] = [NSDate dateWithTimeIntervalSinceNow:-61];
  [TLChromiumBrowserController.sharedController checkBackgroundBrowsers];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
    [self evaluate:"window.talariaTicks" completion:^(NSNumber *first) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
        [self evaluate:"window.talariaTicks" completion:^(NSNumber *second) {
          Check([first isEqual:second],@"background tab scripts pause after the chosen delay");
          self.window.contentView.hidden = NO;
          [TLChromiumBrowserController.sharedController checkBackgroundBrowsers];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            [self evaluate:"window.talariaTicks" completion:^(NSNumber *third) {
              Check(third.integerValue > second.integerValue,@"paused tabs resume when shown");
              [self clearAndDownload];
            }];
          });
        }];
      });
    }];
  });
}
- (void)clearAndDownload {
    [TLBrowserPreferences.sharedPreferences clearData:@"cache" completion:^(NSError *error) {
      Check(!error,@"cache deletion reports completion");
      [TLBrowserPreferences.sharedPreferences clearData:@"cookies" completion:^(NSError *error) {
        Check(!error,@"cookie deletion reports completion");
        [TLChromiumBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/download"]]];
        [self checkDownload:0];
      }];
    }];
}
- (void)checkDownload:(NSUInteger)attempt {
  NSString *path = [[TLBrowserPreferences.profileURL.path stringByAppendingPathComponent:@"TestDownloads"] stringByAppendingPathComponent:@"fixture.txt"];
  NSString *data = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if ([data isEqual:@"talaria download fixture"]) {
    Check(YES,@"embedded browser downloads to the configured folder");
    [NSApp terminate:nil]; return;
  }
  if (attempt >= 100) Check(NO,@"download finishes");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self checkDownload:attempt+1]; });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLChromiumBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [TLChromiumBrowserController.sharedController shutdown]; }
@end
int main(int argc,char **argv) { @autoreleasepool {
  TLChromiumBrowserControllerConfigureMainArgs(argc,argv);
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLProbeDelegate *delegate; delegate = [[TLProbeDelegate alloc] init]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
  [app finishLaunching];
  [app run]; return 0;
}}
