// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
@interface TLProbeApplication : NSApplication
@end
@implementation TLProbeApplication
@end
@interface TLWebKitBrowserController (Integration)
- (void)checkBackgroundBrowsers;
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
static void CheckSlowDownload(TLBrowserDownload *download, NSString *message) {
  NSData *data = [NSData dataWithContentsOfFile:download.path];
  Check(data.length == 64 * 65536, [message stringByAppendingString:@" has the exact expected size"]);
  const uint8_t *bytes = (const uint8_t *)data.bytes;
  BOOL intact = YES;
  for (NSUInteger index = 0; index < data.length; index++) {
    if (bytes[index] != (uint8_t)((index * 37 + index / 251) % 256)) { intact = NO; break; }
  }
  Check(intact, [message stringByAppendingString:@" preserves every payload byte"]);
}
@interface TLProbeDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property NSInteger stage;
@property NSString *baseURL;
@property NSInteger downloadStage;
@property TLBrowserDownload *firstDownload;
@property TLBrowserDownload *secondDownload;
@property TLBrowserDownload *restartDownload;
@end
@implementation TLProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSString *profile = NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"];
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
    Check([state[@"available"] boolValue], [NSString stringWithFormat:@"native %@ is supported by this WebKit runtime",setting[@"id"]]);
  }
  BOOL secondRun = [NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_REOPEN"] boolValue];
  if (secondRun) {
    Check([[[TLBrowserPreferences.sharedPreferences stateForSetting:[TLBrowserPreferences settingWithID:@"fontSize"]] objectForKey:@"value"] integerValue] == 24, @"WebKit font preference persists across desktop launches");
    Check([[TLBrowserPreferences.sharedPreferences localValue:@"zoom"] intValue] == 150, @"Talaria preference persists across desktop launches");
    NSArray *downloads = TLBrowserDownloadManager.sharedManager.downloads;
    Check(downloads.count == 5, @"download history persists across desktop launches");
    for (TLBrowserDownload *download in downloads) Check(!download.active, @"restored history contains no phantom active transfers");
    [NSApp terminate:nil]; return;
  }
  [self set:@"fontSize" value:@24];
  [self set:@"zoom" value:@150];
  [self set:@"javascript" value:@2];
  [self set:@"askDownload" value:@NO];
  NSString *downloadDirectory = [TLBrowserPreferences.profileURL.path stringByAppendingPathComponent:@"TestDownloads"];
  [NSFileManager.defaultManager createDirectoryAtPath:downloadDirectory withIntermediateDirectories:YES attributes:nil error:nil];
  [self set:@"downloadDirectory" value:downloadDirectory];
  self.stage = 0;
  self.session = [TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/page"]] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) { [self title:title]; } linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
}
- (void)title:(NSString *)title {
  if (self.stage == 0 && [title isEqual:@"scripts off"]) {
    self.stage = 1;
    Check(YES,@"blocking JavaScript changes embedded page execution");
    Check(self.session.documentGeneration > 0,@"navigation advances browser document state alongside saved zoom");
    Check(self.session.webView && fabs(self.session.webView.pageZoom - 1.5) < 0.001,@"new embedded tabs use saved page zoom");
    [self set:@"javascript" value:@1];
    [TLWebKitBrowserController.sharedController reloadSession:self.session];
  } else if (self.stage == 1 && [title hasPrefix:@"scripts on"]) {
    self.stage = 2;
    Check([title isEqual:@"scripts on:24px"],@"font size applies to real web content");
    [self testUnchangedZoom];
  }
}
- (void)evaluate:(const char *)expression completion:(void (^)(id))completion {
  TLTestEvaluate(self.session.webView, [NSString stringWithUTF8String:expression], completion);
}
- (void)testUnchangedZoom {
  [self set:@"zoom" value:@100];
  self.session.webView.allowsMagnification = YES;
  self.session.webView.magnification = 2;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
    [self evaluate:"visualViewport.scale" completion:^(NSNumber *before) {
      Check(fabs(before.doubleValue-2)<0.01,@"fixture has a visible page-scale change");
      [self set:@"pauseDelay" value:@60];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
        [self evaluate:"visualViewport.scale" completion:^(NSNumber *after) {
          Check(fabs(after.doubleValue-before.doubleValue)<0.01,@"unchanged zoom does not reset the rendered page when preferences are applied");
          // Invoke the navigation delegate without replacing the loaded page.
          id<WKNavigationDelegate> delegate = self.session.webView.navigationDelegate;
          [delegate webView:self.session.webView didStartProvisionalNavigation:nil];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            [self evaluate:"visualViewport.scale" completion:^(NSNumber *afterLoadStart) {
              Check(fabs(afterLoadStart.doubleValue-before.doubleValue)<0.01,@"main-document navigation callback does not issue a redundant visual reset");
              [self set:@"zoom" value:@150];
              Check(fabs(self.session.webView.pageZoom-1.5)<0.001,@"an actual zoom change still updates the browser");
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
  [self.session setValue:[NSDate dateWithTimeIntervalSinceNow:-61] forKey:@"backgroundSince"];
  [TLWebKitBrowserController.sharedController checkBackgroundBrowsers];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
    [self evaluate:"window.talariaTicks" completion:^(NSNumber *first) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
        [self evaluate:"window.talariaTicks" completion:^(NSNumber *second) {
          Check([first isEqual:second],@"background tab scripts pause after the chosen delay");
          self.window.contentView.hidden = NO;
          [TLWebKitBrowserController.sharedController checkBackgroundBrowsers];
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self verifyResumeAfter:second attempt:0]; });
        }];
      });
    }];
  });
}
- (void)verifyResumeAfter:(NSNumber *)previous attempt:(NSUInteger)attempt {
  [self evaluate:"window.talariaTicks" completion:^(NSNumber *current) {
    if(attempt==0)fprintf(stdout,"Resume observation: before=%ld after=%ld paused=%d attached=%d visible=%d\n",previous.longValue,current.longValue,[[self.session valueForKey:@"paused"] boolValue],self.session.webView.superview!=nil,self.window.visible);
    if(current.integerValue<=previous.integerValue && attempt<10) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self verifyResumeAfter:previous attempt:attempt+1]; });
      return;
    }
    Check(current.integerValue>previous.integerValue,@"paused tabs resume when shown");
    [self clearAndDownload];
  }];
}
- (void)clearAndDownload {
    [TLBrowserPreferences.sharedPreferences clearData:@"cache" completion:^(NSError *error) {
      Check(!error,@"cache deletion reports completion");
      [TLBrowserPreferences.sharedPreferences clearData:@"cookies" completion:^(NSError *error) {
        Check(!error,@"cookie deletion reports completion");
        [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/download"]]];
        [self checkDownload:0];
      }];
    }];
}
- (void)checkDownload:(NSUInteger)attempt {
  NSString *path = [[TLBrowserPreferences.profileURL.path stringByAppendingPathComponent:@"TestDownloads"] stringByAppendingPathComponent:@"fixture.txt"];
  NSString *data = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  if ([data isEqual:@"talaria download fixture"]) {
    Check(YES,@"embedded browser downloads to the configured folder");
    TLBrowserDownload *download = TLBrowserDownloadManager.sharedManager.downloads.firstObject;
    if (download.state != TLBrowserDownloadStateComplete) {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self checkDownload:attempt+1]; });
      return;
    }
    Check(download.fileAvailable && [download.path isEqual:path], @"manager receives the completed WebKit download and its actual destination");
    [TLWebKitBrowserController.sharedController startDownloadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/slow?one"]] fromWindow:self.window];
    [TLWebKitBrowserController.sharedController startDownloadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/slow?two"]] fromWindow:self.window];
    self.downloadStage = 0;
    [self checkDownloadControls:0];
    return;
  }
  if (attempt >= 100) Check(NO,@"download finishes");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self checkDownload:attempt+1]; });
}
- (void)checkDownloadControls:(NSUInteger)attempt {
  TLBrowserDownloadManager *manager = TLBrowserDownloadManager.sharedManager;
  if (self.downloadStage == 0) {
    for (TLBrowserDownload *download in manager.downloads) {
      if ([download.URLString hasSuffix:@"/slow?one"]) self.firstDownload = download;
      if ([download.URLString hasSuffix:@"/slow?two"]) self.secondDownload = download;
    }
    if (self.firstDownload.receivedBytes > 0 && self.secondDownload.receivedBytes > 0) {
      Check(![self.firstDownload.path isEqual:self.secondDownload.path], @"concurrent same-name downloads have separate destinations");
      [manager performAction:TLBrowserDownloadActionPause forDownload:self.firstDownload];
      self.downloadStage = 1;
    }
  } else if (self.downloadStage == 1 && self.firstDownload.state == TLBrowserDownloadStatePaused) {
    Check(YES, @"WebKit confirms pause in the download manager");
    [manager performAction:TLBrowserDownloadActionCancel forDownload:self.secondDownload];
    [manager performAction:TLBrowserDownloadActionResume forDownload:self.firstDownload];
    [TLWebKitBrowserController.sharedController closeSession:self.session];
    self.downloadStage = 2;
  } else if (self.downloadStage == 2 && self.firstDownload.state == TLBrowserDownloadStateComplete && self.secondDownload.state == TLBrowserDownloadStateCancelled) {
    Check(self.firstDownload.fileAvailable, @"resumed download finishes after its browser tab closes");
    CheckSlowDownload(self.firstDownload, @"Byte-resumed download");
    Check(self.secondDownload.canRetry, @"cancelled WebKit download offers retry");
    [TLWebKitBrowserController.sharedController startDownloadURL:[NSURL URLWithString:self.secondDownload.URLString] fromWindow:self.window];
    self.downloadStage = 3;
  } else if (self.downloadStage == 3) {
    TLBrowserDownload *retry = manager.downloads.firstObject;
    if (retry != self.secondDownload && [retry.URLString isEqual:self.secondDownload.URLString] && retry.state == TLBrowserDownloadStateComplete) {
      Check(retry.fileAvailable && manager.downloads.count == 4, @"retry finishes through WebKit with the original browser tab closed");
      CheckSlowDownload(retry, @"Retried download");
      [TLWebKitBrowserController.sharedController startDownloadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/slow-no-range?restart"]] fromWindow:self.window];
      self.downloadStage = 4;
    }
  } else if (self.downloadStage == 4) {
    for (TLBrowserDownload *download in manager.downloads)
      if ([download.URLString hasSuffix:@"/slow-no-range?restart"]) self.restartDownload = download;
    if (self.restartDownload.receivedBytes > 0) {
      [manager performAction:TLBrowserDownloadActionPause forDownload:self.restartDownload];
      self.downloadStage = 5;
    }
  } else if (self.downloadStage == 5 && self.restartDownload.state == TLBrowserDownloadStatePaused &&
      [self.restartDownload.statusText containsString:@"restarts from the beginning"]) {
    Check([self.restartDownload.statusText containsString:@"restarts from the beginning"], @"nonresumable GET pause explains that Resume will restart from zero");
    [manager performAction:TLBrowserDownloadActionResume forDownload:self.restartDownload];
    self.downloadStage = 6;
  } else if (self.downloadStage == 6 && self.restartDownload.state == TLBrowserDownloadStateComplete) {
    Check(self.restartDownload.fileAvailable && manager.downloads.count == 5, @"nonresumable GET restart completes with one download history entry");
    CheckSlowDownload(self.restartDownload, @"Restarted nonresumable download");
    [NSApp terminate:nil]; return;
  }
  if (attempt >= 200) Check(NO, [NSString stringWithFormat:@"download controls finish (stage %ld, states %ld/%ld)", (long)self.downloadStage, (long)self.firstDownload.state, (long)self.secondDownload.state]);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self checkDownloadControls:attempt+1]; });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [TLWebKitBrowserController.sharedController shutdown]; fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); }
@end
int main(int argc,char **argv) { @autoreleasepool {
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLProbeDelegate *delegate; delegate = [[TLProbeDelegate alloc] init]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
  [app finishLaunching];
  [app run]; return 0;
}}
