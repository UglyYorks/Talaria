// Real Chromium Fullscreen API and AppKit view restoration; isolated profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserTabController.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
@interface TLChromiumBrowserController (FullscreenTests)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
@end
@interface TLBrowserTabController (FullscreenTests)
- (BOOL)canSampleOverlay;
- (void)toggleBrowserHeightMode:(id)sender;
@end
@interface TLFullscreenTestApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation TLFullscreenTestApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scoped; [super sendEvent:event]; }
@end
@interface TLFullscreenTestBrowser : TLChromiumBrowserController
@property(nonatomic,copy) NSString *testCache;
@end
@implementation TLFullscreenTestBrowser
- (NSString *)chromiumCachePath { return self.testCache; }
@end
@interface TLFullscreenTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLFullscreenTestBrowser *browser;
@property(nonatomic,strong) TLBrowserTabController *tab;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSView *originalHost;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,copy) void (^reply)(id);
@property(nonatomic) NSUInteger scriptID;
@property(nonatomic) NSRect originalWindow;
@property(nonatomic) CGFloat originalInset;
@end
@implementation TLFullscreenTestDelegate
- (void)after:(double)seconds run:(dispatch_block_t)block { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block); }
- (TLChromiumBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (CefRefPtr<CefBrowser>)cef { return [self.browser browserWithIdentifier:(int)self.session.browserIdentifier]; }
- (NSView *)nativeView { return (__bridge NSView *)[self cef]->GetHost()->GetWindowHandle(); }
- (void)check:(BOOL)passed name:(NSString *)name { [self.results addObject:@{@"name":name,@"passed":@(passed)}]; }
- (void)eval:(NSString *)code then:(void (^)(id))completion {
  self.reply=completion; self.scriptID++;
  NSString *script=[NSString stringWithFormat:@"Promise.resolve((()=>{%@})()).then(value=>{document.title=JSON.stringify({test:%lu,value})}).catch(error=>{document.title=JSON.stringify({test:%lu,value:{error:String(error)}})})",code,(unsigned long)self.scriptID,(unsigned long)self.scriptID];
  CefRefPtr<CefDictionaryValue> params=CefDictionaryValue::Create();
  params->SetString("expression",script.UTF8String); params->SetBool("userGesture",true);
  [self cef]->GetHost()->ExecuteDevToolsMethod(0,"Runtime.evaluate",params);
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  self.results=[NSMutableArray array];
  [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.browser=[TLFullscreenTestBrowser new];self.browser.testCache=args[2];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,1000,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO]; self.window.releasedWhenClosed=NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/fullscreen"]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:360 browserService:self.browser];
#pragma clang diagnostic pop
  __weak TLFullscreenTestDelegate *weakSelf=self;
  self.tab.metadataChangedHandler=^(NSString *title,NSURL *URL){
    id value=[NSJSONSerialization JSONObjectWithData:[title dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if([value isKindOfClass:NSDictionary.class] && [value[@"test"] unsignedIntegerValue]==weakSelf.scriptID && weakSelf.reply){
      void (^callback)(id)=weakSelf.reply;weakSelf.reply=nil;dispatch_async(dispatch_get_main_queue(),^{callback(value[@"value"]);});
    }
  };
  NSView *content=self.window.contentView;[content addSubview:self.tab.view];
  // A tab occupies only part of the window, like a split pane; fullscreen must
  // escape these constraints and restore them unchanged afterwards.
  [NSLayoutConstraint activateConstraints:@[[self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[self.tab.view.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.6],[self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor constant:40],[self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
  [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[content layoutSubtreeIfNeeded];
  self.originalWindow=self.window.frame;[self.tab startInWindow:self.window];
  [self waitForPage:0];
  [self after:35 run:^{if(self.tab){[self check:NO name:@"Fullscreen integration deadline"];[self finish];}}];
}
- (void)waitForPage:(NSUInteger)attempt {
  if(self.session.browserIdentifier<0 || ![[[self.session valueForKey:@"documentFooter"] valueForKey:@"ready"] boolValue]) {
    if(attempt<80){[self after:0.1 run:^{[self waitForPage:attempt+1];}];return;}
    [self check:NO name:@"Page ready"];[self finish];return;
  }
  [self after:0.5 run:^{[self cycle:0];}];
}
- (void)cycle:(NSUInteger)index {
  if(index==4){[self finish];return;}
  if(index==1)[self.tab toggleBrowserHeightMode:nil];
  [self after:0.6 run:^{
    self.originalHost=[self nativeView].superview;
    self.originalInset=[[self.tab valueForKey:@"browserHostBottomConstraint"] constant];
    NSString *target=index==1?@"document.querySelector('video')":@"document.querySelector('#target')";
    if(index==2)target=@"document.querySelector('iframe')";
    NSString *script=[NSString stringWithFormat:@"return %@.requestFullscreen().then(()=>true)",target];
    [self eval:script then:^(id entered){
      [self check:[entered isEqual:@YES] name:@"Renderer accepts user-initiated fullscreen"];
      [self after:0.4 run:^{[self verifyEntry:index];}];
    }];
  }];
}
- (void)verifyEntry:(NSUInteger)index {
  NSView *view=[self nativeView];
  NSView *host=self.originalHost;
  [self check:self.session.fullscreen && view.inFullScreenMode && view.window!=self.window name:@"Browser content enters native fullscreen"];
  [self check:NSEqualSizes(view.bounds.size,view.window.screen.frame.size) name:@"Browser fills the selected display"];
  [self check:!NSEqualSizes(host.bounds.size,view.bounds.size) && NSEqualRects(self.originalWindow,self.window.frame) name:@"Original split layout and window stay unchanged"];
  [self check:![self.tab canSampleOverlay] name:@"Footer probes pause in fullscreen"];
  [self eval:@"let f=document.querySelector('[data-talaria-document-footer]');return {fullscreen:!!document.fullscreenElement,spacer:f?f.getBoundingClientRect().height:0,width:innerWidth,height:innerHeight}" then:^(NSDictionary *state){
    [self check:[state[@"fullscreen"] boolValue] && [state[@"spacer"] doubleValue]==0 name:@"Fullscreen has no document extension"];
    [self check:fabs([state[@"width"] doubleValue]-NSWidth(view.bounds))<1 && fabs([state[@"height"] doubleValue]-NSHeight(view.bounds))<1 name:@"Renderer viewport matches native fullscreen size"];
    if(index==3){
      [self.tab close];
      [self check:!view.inFullScreenMode name:@"Closing fullscreen tab restores native presentation"];
      [self after:0.2 run:^{[self finish];}];return;
    }
    if(index==1){
      NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil
        characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
      [NSApp sendEvent:escape];
    }else if(index==2){
      [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/fullscreen?again"]]];
    }else{
      [self eval:@"return document.exitFullscreen().then(()=>true)" then:^(id result){}];
    }
    [self after:0.7 run:^{
      [self check:!self.session.fullscreen && !view.inFullScreenMode && view.superview==host name:@"Exit restores the browser to its original host"];
      [self check:NSEqualRects(view.frame,host.bounds) && NSEqualRects(self.window.frame,self.originalWindow) name:@"Exit restores exact browser and window geometry"];
      if(index!=2)[self check:self.originalInset==[[self.tab valueForKey:@"browserHostBottomConstraint"] constant] name:@"Exit preserves manual footer mode"];
      [self eval:@"return !document.fullscreenElement" then:^(id cleared){
        [self check:[cleared isEqual:@YES] name:@"Exit also clears renderer fullscreen"];
        [self cycle:index+1];
      }];
    }];
  }];
}
- (void)finish {
  [self.tab close];self.tab=nil;
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{TLChromiumBrowserControllerConfigureMainArgs(argc,argv);TLFullscreenTestApplication *app=[TLFullscreenTestApplication sharedApplication];TLFullscreenTestDelegate *delegate=[TLFullscreenTestDelegate new];app.delegate=delegate;[app run];}return 0;}
