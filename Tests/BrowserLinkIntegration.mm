// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserImageActions.h"
#import "TLBrowserLinkActions.h"
#import "design_system/TLActionMenuItem.h"
#import "design_system/TLLinkServicesView.h"
@interface TLProbeApplication : NSApplication
@end
@implementation TLProbeApplication
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
@interface TLWebKitBrowserController (LinkTests)
- (void)openImageURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session inNewWindow:(BOOL)newWindow;
@end
@interface TLLinkProbeDelegate : NSObject <NSApplicationDelegate>
@property TLWebKitBrowserController *browser;
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property NSString *baseURL;
@property BOOL started;
@property NSInteger menuDestination;
@property NSURL *openedURL;
@property id trackingObserver;
@end
@implementation TLLinkProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([TLBrowserPreferences.profileURL.path hasPrefix:@"/tmp/talaria-link-test-"], @"isolated profile");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  self.browser = [TLWebKitBrowserController new];
  self.session = [self.browser loadURL:[NSURL URLWithString:self.baseURL] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) {
      if (![title isEqual:@"Link menu fixture"] || self.started) return;
      self.started = YES;
      if (NSProcessInfo.processInfo.environment[@"TL_CONTEXT_MENU_INTERACTIVE"]) return;
      dispatch_async(dispatch_get_main_queue(), ^{ TLTestActivateWindow(self.window,^{[self waitFor:^BOOL{return !self.session.webView.loading;} then:^{[self testTrustedContext:0];} attempt:0];}); });
    } linkHandler:^(NSURL *URL, NSEventModifierFlags flags) { self.openedURL = URL; } URLHandler:nil faviconHandler:nil navigationHandler:nil];
  if (NSProcessInfo.processInfo.environment[@"TL_CONTEXT_MENU_INTERACTIVE"]) return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,45*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"link integration timeout"); });
}
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)then attempt:(NSUInteger)attempt {
  if (condition()) { then(); return; }
  if (attempt >= 200) Check(NO, @"asynchronous link action completes");
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{ [self waitFor:condition then:then attempt:attempt+1]; });
}
- (NSURL *)URL:(NSString *)path { return [NSURL URLWithString:[self.baseURL stringByAppendingString:path]]; }
- (void)testTrustedContext:(NSUInteger)index {
  if(index==2){[self testMenu];return;}
  NSString *selector=index==0 ? @"a img" : @"#editor";
  NSString *script=[NSString stringWithFormat:@"(()=>{const e=document.querySelector('%@');e.scrollIntoView({block:'center'});if(e.select)e.select();const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()",selector];
  TLTestEvaluate(self.session.webView,script,^(NSDictionary *location){
    self.trackingObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note){
      NSMenu *menu=note.object;
      [NSNotificationCenter.defaultCenter removeObserver:self.trackingObserver];self.trackingObserver=nil;
      NSArray *titles=[menu.itemArray valueForKey:@"title"];
      BOOL matches=index==0 ? ([titles containsObject:@"Open Link in New Tab"] && [titles containsObject:@"Open Image in New Tab"] && [titles containsObject:@"Save Image As…"]) :
        ([titles containsObject:@"Copy"] && [titles containsObject:@"Paste"] && ![titles containsObject:@"Show Page Source"] && ![titles containsObject:@"Open Link in New Tab"]);
      [NSRunLoop.mainRunLoop performInModes:@[NSRunLoopCommonModes,NSEventTrackingRunLoopMode] block:^{
        [menu cancelTracking];
        Check(matches,index==0 ? @"Trusted right-click on a linked image builds the real combined menu" : @"Trusted right-click in a text field preserves native editing actions");
        dispatch_async(dispatch_get_main_queue(),^{[self testTrustedContext:index+1];});
      }];
    }];
    WKWebView *view=self.session.webView;[self.window makeKeyAndOrderFront:nil];
    NSPoint local=NSMakePoint([location[@"x"] doubleValue],view.isFlipped ? [location[@"y"] doubleValue] : NSHeight(view.bounds)-[location[@"y"] doubleValue]);
    NSPoint point=[view convertPoint:local toView:nil];
    NSEvent *event=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [NSApp postEvent:event atStart:NO];
    NSEvent *release=[NSEvent mouseEventWithType:NSEventTypeRightMouseUp location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
    [NSApp postEvent:release atStart:NO];
  });
}
- (void)testCombinedMenu {
  NSMenu *images = [NSMenu new]; images.autoenablesItems = NO;
  __block NSInteger selectedImage = -1;
  NSArray *imageTitles = TLBrowserImageMenuTitles();
  for (NSUInteger i=0; i<imageTitles.count; i++) {
    if (i == TLBrowserImageSaveDownloads || i == TLBrowserImageCopyAddress || i == TLBrowserImageShare) [images addItem:NSMenuItem.separatorItem];
    NSMenuItem *item = [TLActionMenuItem itemWithTitle:imageTitles[i] action:^{ selectedImage = i; }];
    item.tag = 10000 + i; item.enabled = i != TLBrowserImageLookUp;
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
  Check(selectedImage == TLBrowserImageOpenTab && imageOpen.tag == 10000, @"image selection still routes to its original image command");
}
- (void)testMenu {
  [self testCombinedMenu];
  NSURL *URL = [self URL:@"/one"];
  NSMenu *menu = [TLBrowserLinkActions menuForURL:URL canSplit:YES view:self.window.contentView point:NSZeroPoint
    open:^(NSURL *URL, TLBrowserLinkDestination destination) { self.menuDestination = destination; self.openedURL = URL; }
    inspect:^{} imageMenu:nil];
  NSArray *expected = @[@"Open Link in New Tab",@"Open Link in New Window",@"Open Link in Split View",@"",@"Copy Link",@"",@"Share…",@"",@"Inspect Element"];
  Check(menu.numberOfItems == expected.count, @"link menu has all requested options, excluding bookmarks and reading list");
  for (NSUInteger i=0; i<expected.count; i++) Check([[menu itemAtIndex:i].title isEqual:expected[i]], [NSString stringWithFormat:@"link menu row %lu",(unsigned long)i]);
  Check([menu itemAtIndex:2].enabled && ![menu itemAtIndex:2].submenu, @"split opens directly without a submenu");
  Check([menu itemAtIndex:4].image && [menu itemAtIndex:6].image, @"copy and share have native icons");
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
        __weak TLLinkProbeDelegate *weakSelf = self;
        self.session.contextLinkHandler = ^(NSURL *link, TLBrowserLinkDestination destination) {
          weakSelf.openedURL = link;
          if (destination == TLBrowserLinkNewWindow) [weakSelf.browser openURL:link fromWindow:weakSelf.window modifierFlags:0];
        };
        TLBrowserLinkOpenHandler split = self.session.contextLinkHandler;
        Check(split != nil, @"WebKit resolves the source session's split handler");
        split([self URL:@"/two"], TLBrowserLinkSplitView);
        Check([self.openedURL isEqual:[self URL:@"/two"]], @"split request reaches the originating tab");
        [self testNewWindow];
      });
    });
  });
}
- (void)testNewWindow {
  [self.browser openImageURL:[self URL:@"/one"] inSession:self.session inNewWindow:YES];
  [self waitFor:^BOOL {
    for (NSWindow *window in NSApp.windows) {
      if (window != self.window && window.isVisible && [window.title isEqual:@"Link menu fixture"]) return YES;
    }
    return NO;
  } then:^{
    Check(YES, @"new-window links still open and receive page titles");
    [self testScriptPopup];
  } attempt:0];
}
- (void)testScriptPopup {
  NSError *error=nil;
  Check([TLBrowserPreferences.sharedPreferences saveValue:@1 forSetting:[TLBrowserPreferences settingWithID:@"popups"] error:&error], @"Enable script popups for the isolated fixture");
  TLTestEvaluate(self.session.webView, @"(()=>{const popup=window.open('','talaria-popup-test');if(!popup)return false;window.__testPopup=popup;popup.document.open();popup.document.write('<title>Script popup fixture</title><p>Opener survives</p>');popup.document.close();return popup.opener===window && popup.document.body.innerText==='Opener survives'})()", ^(NSNumber *opened) {
    Check(opened.boolValue, @"Script popups preserve opener and inherited about:blank document access");
    [self waitFor:^BOOL {
      for(NSWindow *window in NSApp.windows)if(window.isVisible && [window.title isEqual:@"Script popup fixture"])return YES;
      return NO;
    } then:^{
      Check(YES, @"Script popup renders its document in a native window");
      TLTestEvaluate(self.session.webView, @"window.__testPopup.close();true", ^(id value) {
        [self waitFor:^BOOL {
          for(NSWindow *window in NSApp.windows)if(window.isVisible && [window.title isEqual:@"Script popup fixture"])return NO;
          return YES;
        } then:^{ Check(YES,@"window.close dismisses its script-created native window");[self testClosingTitle]; } attempt:0];
      });
    } attempt:0];
  });
}
- (void)testClosingTitle {
  WKWebView *closing = self.session.webView;
  id<WKNavigationDelegate> lateDelegate = closing.navigationDelegate;
  self.window.title = @"Host window";
  [self.browser closeSession:self.session];
  Check(self.session.contextLinkHandler == nil, @"closed tabs cannot receive split requests");
  Check(closing != nil, @"exercise title event during asynchronous tab closure");
  [closing evaluateJavaScript:@"document.title='Late page title'" completionHandler:^(id value, NSError *error) {
    Check([self.window.title isEqual:@"Host window"], @"late embedded title cannot rename the host window");
    Check(self.session.webView == nil && closing.superview == nil, @"closed browser detaches its page view");
    if ([lateDelegate respondsToSelector:@selector(webView:didFinishNavigation:)]) [lateDelegate webView:closing didFinishNavigation:nil];
    Check([self.window.title isEqual:@"Host window"], @"title after browser destruction is safely ignored");
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
  }];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [self.browser prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [self.browser shutdown]; fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); }
@end
int main(int argc,char **argv) { @autoreleasepool {
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLLinkProbeDelegate *delegate; delegate = [TLLinkProbeDelegate new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app finishLaunching]; [app run]; return 0;
}}
