// Explicit desktop integration test with a disposable profile and loopback pages.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"

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
  Later(20,^{ Check(NO,@"navigation test timeout"); });
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
      [NSApp terminate:nil];
    });
  });
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
