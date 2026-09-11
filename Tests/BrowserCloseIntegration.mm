#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <signal.h>
#import "WebKitBrowserController.h"
#import "TLBrowserTabController.h"
#import "BrowserWebKitTestSupport.h"

static void Check(BOOL condition, NSString *message) {
  fprintf(condition ? stdout : stderr,"%s: %s\n",condition ? "PASS" : "FAIL",message.UTF8String);
  fflush(condition ? stdout : stderr); if(!condition)exit(1);
}
static void Later(double seconds, dispatch_block_t block) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,seconds*NSEC_PER_SEC),dispatch_get_main_queue(),block);
}
@interface TLCloseTestDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLBrowserTabController *tab;
@property TLWebKitBrowserSession *session;
@property WKWebView *retainedView;
@property NSUInteger phase;
@property pid_t renderer;
@property BOOL pendingScriptReturned;
@property NSView *survivorHost;
@property TLWebKitBrowserSession *survivor;
@property pid_t survivorRenderer;
@end
@implementation TLCloseTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,850,600)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
  self.survivorHost=[[NSView alloc] initWithFrame:NSMakeRect(0,0,400,300)];
  self.survivor=[TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:[NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"] stringByAppendingString:@"survivor"]]
    inView:self.survivorHost fromWindow:self.window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  [self waitForSurvivor:0];
  Later(45,^{Check(NO,@"close regression deadline");});
}
- (void)waitForSurvivor:(NSUInteger)attempt {
  if(attempt>80)Check(NO,@"other browser tab loads");
  [self.survivor.webView evaluateJavaScript:@"document.title==='Survivor' && (window.survivor=42)" completionHandler:^(id result,NSError *error){
    if(![result isEqual:@42]){Later(.1,^{[self waitForSurvivor:attempt+1];});return;}
    Check(!error,@"another browser tab is open");
    self.survivorRenderer=[[self.survivor.webView valueForKey:@"_webProcessIdentifier"] intValue];
    [self startPage];
  }];
}
- (void)startPage {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"]]
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:600];
#pragma clang diagnostic pop
  self.window.contentView=self.tab.view;[self.window.contentView layoutSubtreeIfNeeded];
  [self.tab startInWindow:self.window];self.session=[self.tab valueForKey:@"browserSession"];
  [self waitForAudio:0];
}
- (void)waitForAudio:(NSUInteger)attempt {
  if(attempt>80)Check(NO,@"fixture starts HTML audio and Web Audio");
  [self.session.webView evaluateJavaScript:@"window.audioReady===true" completionHandler:^(id ready,NSError *error){
    if(![ready isEqual:@YES]){Later(.1,^{[self waitForAudio:attempt+1];});return;}
    [self.session.webView requestMediaPlaybackStateWithCompletionHandler:^(WKMediaPlaybackState state){
      Check(state==WKMediaPlaybackStatePlaying,@"real media is playing before tab closure");
      self.retainedView=self.session.webView;
      self.renderer=[[self.retainedView valueForKey:@"_webProcessIdentifier"] intValue];
      if(self.phase==0){[self closePage];return;}
      // Keep an asynchronous call pending, then block the page's main thread.
      // A native close must not wait for this page script to cooperate.
      [self.retainedView evaluateJavaScript:@"setTimeout(()=>{const end=Date.now()+20000;while(Date.now()<end){}},0);true" completionHandler:^(id value,NSError *scriptError){
        Check(!scriptError,@"schedule a controlled renderer hang");
        Later(.15,^{
          self.pendingScriptReturned=NO;
          [self.retainedView evaluateJavaScript:@"1" completionHandler:^(id value,NSError *error){self.pendingScriptReturned=YES;}];
          Later(.15,^{Check(!self.pendingScriptReturned,@"page is genuinely unresponsive before close");[self closePage];});
        });
      }];
    }];
  }];
}
- (void)closePage {
  NSTimeInterval started=NSProcessInfo.processInfo.systemUptime;
  [self.tab close];[self.tab close];
  Check(NSProcessInfo.processInfo.systemUptime-started<.5,@"closing is immediate and idempotent");
  SEL closed=NSSelectorFromString(@"_isClosed");
  Check([self.retainedView respondsToSelector:closed] && ((BOOL(*)(id,SEL))objc_msgSend)(self.retainedView,closed),
    @"native page is closed even while a callback retains its web view");
  Check(self.retainedView.navigationDelegate==nil && self.retainedView.UIDelegate==nil,@"closed page cannot call browser delegates");
  [self.retainedView requestMediaPlaybackStateWithCompletionHandler:^(WKMediaPlaybackState state){
    Check(state!=WKMediaPlaybackStatePlaying,@"closed page reports no active playback");
    Later(2,^{
      if(self.phase==0){self.phase=1;self.retainedView=nil;[self startPage];}
      else {
        Check(kill(self.renderer,0)!=0,@"hung renderer exits after its last tab closes");
        Check(self.pendingScriptReturned,@"closing aborts the pending call to the hung renderer");
        Check([[self.survivor.webView valueForKey:@"_webProcessIdentifier"] intValue]==self.survivorRenderer,
          @"closing a hung tab preserves the other tab's renderer");
        [self.survivor.webView evaluateJavaScript:@"window.survivor" completionHandler:^(id result,NSError *error){
          Check(!error && [result isEqual:@42],@"other open tab remains responsive with its state intact");
          [NSApp terminate:nil];
        }];
      }
    });
  }];
}
- (void)applicationWillTerminate:(NSNotification *)note {
  [TLWebKitBrowserController.sharedController shutdown];
  fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n");fflush(stdout);
}
@end
int main(void){@autoreleasepool{
  NSApplication *app=NSApplication.sharedApplication;
  TLCloseTestDelegate *delegate=[TLCloseTestDelegate new];app.delegate=delegate;[app run];
}return 0;}
