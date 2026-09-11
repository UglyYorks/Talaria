// Explicit desktop integration test with a disposable profile and loopback pages.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
#import "TLBrowserPreferences.h"
#import "design_system/UIComponents.h"

@interface TLNavigationTestApplication : NSApplication
@end
@implementation TLNavigationTestApplication
@end


static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr,"%s: %s\n",condition ? "PASS" : "FAIL",message.UTF8String);
  fflush(condition ? stdout : stderr);
  if (!condition) exit(1);
}
static void Later(double seconds, void (^action)(void)) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}

@interface TLNavigationTestDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property NSString *baseURL;
@property NSUInteger phase;
@property NSUInteger initialGeneration;
@property BOOL checkedCover;
@property BOOL checkedProgressiveRendering;
@property TLBrowserTabController *tab;
@end

@implementation TLNavigationTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSString *profile = NSProcessInfo.processInfo.environment[@"TL_WEBKIT_PROFILE_DIR"];
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([profile hasPrefix:@"/tmp/talaria-native-navigation-test-"],@"disposable browser profile");
  Check([self.baseURL hasPrefix:@"http://127.0.0.1:"],@"loopback fixture");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80,80,900,650)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  self.session = [TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/start"]]
    inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil
    navigationHandler:^(BOOL back, BOOL forward, BOOL loading) { if (!loading) [self loaded]; }];
  Later(50,^{ Check(NO,@"navigation test timeout"); });
}
- (NSImageView *)cover {
  for (NSView *view in self.window.contentView.subviews)
    if ([view isKindOfClass:NSImageView.class]) return (NSImageView *)view;
  return nil;
}
- (void)loaded {
  if (!self.session.documentGeneration) return;
  if (self.phase == 0) {
    self.phase = 1;
    Later(.25,^{ [self clickLink]; });
  } else if (self.phase == 1) {
    self.phase = 2;
    Later(.25,^{
      Check(self.checkedCover,@"old frame was checked while destination CSS was pending");
      Check(self.checkedProgressiveRendering,@"destination was revealed before all resources finished");
      Check(!self.cover,@"destination paint removes the old frame");
      [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/blank"]]];
    });
  } else if (self.phase == 2) {
    self.phase = 3;
    Later(.25,^{
      Check(!self.cover,@"blank destination also releases the old frame");
      [self checkResizeAndClose];
    });
  }
}
- (void)clickLink {
  self.initialGeneration = self.session.documentGeneration;
  NSView *view = self.session.webView;
  NSPoint point = [view convertPoint:NSMakePoint(40,view.isFlipped ? 40 : NSHeight(view.bounds)-40) toView:nil];
  for (NSNumber *type in @[@(NSEventTypeLeftMouseDown),@(NSEventTypeLeftMouseUp)]) {
    NSEvent *event = [NSEvent mouseEventWithType:(NSEventType)type.integerValue location:point modifierFlags:0
      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSView *target = [self.window.contentView hitTest:point];
    if (event.type == NSEventTypeLeftMouseDown) [target mouseDown:event]; else [target mouseUp:event];
  }
  Later(.8,^{
    Check(self.session.documentGeneration == self.initialGeneration + 1,[NSString stringWithFormat:@"link commits exactly one new document (before=%lu after=%lu URL=%@ loading=%d)",(unsigned long)self.initialGeneration,(unsigned long)self.session.documentGeneration,self.session.webView.URL,self.session.webView.loading]);
    NSImageView *cover = self.cover;
    Check(cover.image != nil,@"last rendered frame remains visible during cross-origin navigation");
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:cover.image.TIFFRepresentation];
    NSColor *pixel = [[bitmap colorAtX:10 y:10] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    Check(pixel.blueComponent > pixel.redComponent + .2,@"held image contains the blue source page, not a blank frame");
    self.checkedCover = YES;
    Later(1.2,^{ [self checkProgressiveRendering]; });
  });
}
- (void)checkProgressiveRendering {
  WKWebView *view=self.session.webView;
  Check(view.loading,@"slow image is still loading when the destination is revealed");
  Check(!self.cover,@"first visible content releases the old frame before load completion");
  Check(!view.configuration.suppressesIncrementalRendering,@"browser allows progressive rendering");
  TLTestEvaluate(view,@"({imagePending:!document.getElementById('slow-image').complete,title:document.querySelector('h1').textContent})",^(id value){
    Check([value[@"imagePending"] boolValue] && [value[@"title"] isEqual:@"Destination page"],@"destination content exists while its image remains pending");
    WKSnapshotConfiguration *configuration=[WKSnapshotConfiguration new];configuration.afterScreenUpdates=NO;
    [view takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image,NSError *error){
      Check(!error && image != nil && view.loading,@"rendered destination can be captured before loading finishes");
      NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
      NSColor *pixel=[[bitmap colorAtX:10 y:100] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      Check(pixel.greenComponent>pixel.blueComponent+.05 && pixel.greenComponent>pixel.redComponent+.1,
        @"visible pixels contain the green destination, not the blue source or a blank frame");
      self.checkedProgressiveRendering=YES;
    }];
  });
}
- (void)checkResizeAndClose {
  [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/slow"]]];
  Later(.4,^{
    Check(self.cover.image != nil,@"next navigation can capture a fresh frame");
    [self.window setContentSize:NSMakeSize(800,600)];
    Check(!self.cover,@"resizing removes a snapshot with obsolete geometry");
    [TLWebKitBrowserController.sharedController closeSession:self.session];
    Later(.3,^{
      Check(!self.cover,@"closing a tab prevents delayed captures from reappearing");
      [self checkInsetNavigation];
    });
  });
}
- (void)checkInsetNavigation {
  self.session=[TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/inset-source"]]
    inView:self.window.contentView fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  [self waitForPath:@"/inset-source" attempt:0 then:^{
    if (@available(macOS 26.0, *)) self.session.webView.obscuredContentInsets=NSEdgeInsetsMake(0,0,70,0);
    else { [TLWebKitBrowserController.sharedController closeSession:self.session];[self checkHistory];return; }
    [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/slow"]]];
    Later(.4,^{
      Check(self.session.webView.loading,@"inset regression examines the pending address navigation");
      Check(![self.session valueForKey:@"navigationCover"],@"overlay input keeps the live page instead of a snapshot with a blank inset band");
      Later(.3,^{
        Check(![self.session valueForKey:@"navigationCover"],@"delayed snapshot cannot introduce an inset band during loading");
        [TLWebKitBrowserController.sharedController closeSession:self.session];[self checkHistory];
      });
    });
  }];
}
- (TLBrowserAddressInput *)address { return [self.tab valueForKey:@"browserAddressInput"]; }
- (void)waitForPath:(NSString *)path attempt:(NSUInteger)attempt then:(dispatch_block_t)next {
  WKWebView *view=self.session.webView;
  if(!view.loading && [[view.URL.path stringByAppendingString:view.URL.fragment.length ? [@"#" stringByAppendingString:view.URL.fragment] : @""] isEqual:path]) {
    Later(.3,next);return;
  }
  if(attempt>=80)Check(NO,[NSString stringWithFormat:@"navigation reaches %@ (actual %@)",path,view.URL]);
  Later(.05,^{[self waitForPath:path attempt:attempt+1 then:next];});
}
- (void)checkHistory {
  // Exercise the production tab and toolbar, not only the engine's methods.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/history"]]
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:600];
#pragma clang diagnostic pop
  self.window.contentView=self.tab.view;[self.window.contentView layoutSubtreeIfNeeded];
  [self.tab startInWindow:self.window];self.session=[self.tab valueForKey:@"browserSession"];
  [self waitForPath:@"/history" attempt:0 then:^{
    Check(!self.address.backButton.enabled && !self.address.forwardButton.enabled,@"new tab disables both history buttons");
    TLTestEvaluate(self.session.webView,@"history.pushState({page:1}, '', '/history/one');document.querySelector('h1').textContent='One';",^(id value){
      [self waitForPath:@"/history/one" attempt:0 then:^{
        Check(self.address.backButton.enabled,@"pushState enables the real Back button");
        [self.address.backButton performClick:nil];
        [self waitForPath:@"/history" attempt:0 then:^{
          Check(![self.session valueForKey:@"navigationCover"],@"Back to same-document history reveals the restored page immediately");
          Check(!self.address.backButton.enabled && self.address.forwardButton.enabled,@"Back updates both toolbar buttons");
          TLTestEvaluate(self.session.webView,@"document.querySelector('h1').textContent",^(id value){
            Check([value isEqual:@"Start"],@"Back runs the site's popstate handler");
            [self.address.forwardButton performClick:nil];
            [self waitForPath:@"/history/one" attempt:0 then:^{
              Check(![self.session valueForKey:@"navigationCover"],@"Forward to same-document history reveals the restored page immediately");
              Check(self.address.backButton.enabled && !self.address.forwardButton.enabled,@"Forward updates both toolbar buttons");
              [self checkRepeatedURLHistory];
            }];
          });
        }];
      }];
    });
  }];
}
- (void)checkRepeatedURLHistory {
  TLTestEvaluate(self.session.webView,@"history.pushState({page:2}, '', location.href);",^(id value){
    [self.address.backButton performClick:nil];
    Later(.4,^{TLTestEvaluate(self.session.webView,@"history.state.page",^(id value){
      Check([value isEqual:@1] && ![self.session valueForKey:@"navigationCover"],@"Back reveals a history entry even when the URL is unchanged");
      [self.address.forwardButton performClick:nil];
      Later(.4,^{TLTestEvaluate(self.session.webView,@"history.state.page",^(id value){
        Check([value isEqual:@2] && ![self.session valueForKey:@"navigationCover"],@"Forward reveals a history entry even when the URL is unchanged");
        [self checkFragmentHistory];
      });});
    });});
  });
}
- (void)checkFragmentHistory {
  TLTestEvaluate(self.session.webView,@"document.querySelector('a').click();",^(id value){
    [self waitForPath:@"/history/one#section" attempt:0 then:^{
      Check(![self.session valueForKey:@"navigationCover"],@"fragment link releases the old page image");
      [self.address.backButton performClick:nil];
      [self waitForPath:@"/history/one" attempt:0 then:^{
        Check(![self.session valueForKey:@"navigationCover"],@"Back through fragment history reveals the page");
        [self.address.forwardButton performClick:nil];
        [self waitForPath:@"/history/one#section" attempt:0 then:^{
          Check(![self.session valueForKey:@"navigationCover"],@"Forward through fragment history reveals the page");
          [self checkCrossDocumentHistory];
        }];
      }];
    }];
  });
}
- (void)checkCrossDocumentHistory {
  [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/history/second"]]];
  [self waitForPath:@"/history/second" attempt:0 then:^{
    [self.address.backButton performClick:nil];
    [self waitForPath:@"/history/one#section" attempt:0 then:^{
      Check(![self.session valueForKey:@"navigationCover"],@"cross-document Back reveals the restored page");
      Check([self.address.textView.toolTip hasSuffix:@"/history/one#section"],@"Back restores the address bar URL");
      [self.address.forwardButton performClick:nil];
      [self waitForPath:@"/history/second" attempt:0 then:^{
        Check(![self.session valueForKey:@"navigationCover"],@"cross-document Forward reveals the restored page");
        Check(!self.address.forwardButton.enabled,@"Forward disables itself at the end of history");
        [self checkHistoryWithoutPageScripts];
      }];
    }];
  }];
}
- (void)checkHistoryWithoutPageScripts {
  TLBrowserPreferences *preferences=TLBrowserPreferences.sharedPreferences;
  Check([preferences persistValue:@2 forSetting:[TLBrowserPreferences settingWithID:@"javascript"] error:nil],@"disable site JavaScript in the disposable profile");
  [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/history/noscript"]]];
  [self waitForPath:@"/history/noscript" attempt:0 then:^{
    TLTestEvaluate(self.session.webView,@"window.fixtureScriptRan === true",^(id value){
      Check([value isEqual:@NO],@"fixture's page script is disabled");
      [TLWebKitBrowserController.sharedController navigateSession:self.session toURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/history/noscript#section"]]];
      [self waitForPath:@"/history/noscript#section" attempt:0 then:^{
        Check(![self.session valueForKey:@"navigationCover"],@"address-bar fragment navigation releases the old image without page scripts");
        [self.address.backButton performClick:nil];
        [self waitForPath:@"/history/noscript" attempt:0 then:^{
          Check(![self.session valueForKey:@"navigationCover"],@"Back works with site JavaScript disabled");
          [self.address.forwardButton performClick:nil];
          [self waitForPath:@"/history/noscript#section" attempt:0 then:^{
            Check(![self.session valueForKey:@"navigationCover"],@"Forward works with site JavaScript disabled");
            [self.tab close];[NSApp terminate:nil];
          }];
        }];
      }];
    });
  }];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [TLWebKitBrowserController.sharedController shutdown]; fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); }
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    TLNavigationTestApplication *application = [TLNavigationTestApplication sharedApplication];
    TLNavigationTestDelegate *delegate = [TLNavigationTestDelegate new];
    application.delegate = delegate;
    [application run];
  }
  return 0;
}
