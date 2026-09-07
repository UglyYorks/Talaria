// Real CEF DevTools lifecycle and native footer layout, using an isolated profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserTabController.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_menu_model_delegate.h"
#include "include/cef_string_visitor.h"
class TLContextMenuTextVisitor : public CefStringVisitor {
 public:
  explicit TLContextMenuTextVisitor(void (^reply)(NSString *)) : reply_([reply copy]) {}
  void Visit(const CefString &value) override { reply_([NSString stringWithUTF8String:value.ToString().c_str()]); }
 private:
  void (^__strong reply_)(NSString *);
  IMPLEMENT_REFCOUNTING(TLContextMenuTextVisitor);
};
class TLDevToolsTestMenuDelegate : public CefMenuModelDelegate {
 public:
  void ExecuteCommand(CefRefPtr<CefMenuModel>, int, cef_event_flags_t) override {}
 private:
  IMPLEMENT_REFCOUNTING(TLDevToolsTestMenuDelegate);
};
@interface TLChromiumBrowserController (DevToolsTests)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(NSView *)parent;
- (NSSavePanel *)pageSavePanel;
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion;
- (void)createBrowserWithURLString:(NSString *)URLString parentView:(NSView *)parent;
@end
@interface TLBrowserTabController (DevToolsTests)
- (void)toggleBrowserHeightMode:(id)sender;
@end
@interface TLDevToolsTestApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation TLDevToolsTestApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scoped; [super sendEvent:event]; }
@end
@interface TLDevToolsTestBrowser : TLChromiumBrowserController
@property(nonatomic,copy) NSString *testCache;
@property(nonatomic) NSInteger inspectorIdentifier;
@property(nonatomic) NSUInteger inspectorCount;
@property(nonatomic,strong) NSSavePanel *savePanel;
@property(nonatomic,strong) NSURL *archiveDestination;
@end
@implementation TLDevToolsTestBrowser
- (NSString *)chromiumCachePath { return self.testCache; }
- (NSSavePanel *)pageSavePanel { self.savePanel=[super pageSavePanel];return self.savePanel; }
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion {
  // Exercise the real sheet's cancellation separately from the user's chosen URL.
  if(self.archiveDestination)completion(self.archiveDestination);
  else [super choosePageArchiveURL:name fromWindow:window completion:completion];
}
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(NSView *)parent {
  [super browserCreated:browser parentView:parent];
  if (!parent) { self.inspectorIdentifier=browser->GetIdentifier();self.inspectorCount++; }
}
@end
@interface TLDevToolsTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLDevToolsTestBrowser *browser;
@property(nonatomic,strong) TLBrowserTabController *tab, *otherTab;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,strong) id menuObserver;
@property(nonatomic,copy) NSString *windowText;
@end
@implementation TLDevToolsTestDelegate
- (void)after:(double)seconds run:(dispatch_block_t)block {
  // System printing runs a modal loop that does not drain the main GCD queue.
  NSTimer *timer=[NSTimer timerWithTimeInterval:seconds repeats:NO block:^(NSTimer *){block();}];
  for(NSString *mode in @[NSRunLoopCommonModes,NSModalPanelRunLoopMode,NSEventTrackingRunLoopMode])
    [NSRunLoop.mainRunLoop addTimer:timer forMode:mode];
}
- (TLChromiumBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (CefRefPtr<CefBrowser>)cef { return [self.browser browserWithIdentifier:(int)self.session.browserIdentifier]; }
- (CGFloat)inset:(TLBrowserTabController *)tab { return [[tab valueForKey:@"browserHostBottomConstraint"] constant]; }
- (void)check:(BOOL)passed name:(NSString *)name { NSLog(@"%@: %@",passed ? @"PASS" : @"FAIL",name);[self.results addObject:@{@"name":name,@"passed":@(passed)}]; }
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)completion attempt:(NSUInteger)attempt {
  if (!self.tab) return;
  if (condition()) { completion();return; }
  if (attempt>=100) { [self check:NO name:@"DevTools lifecycle deadline"];[self finish];return; }
  [self after:0.1 run:^{[self waitFor:condition then:completion attempt:attempt+1];}];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  self.results=[NSMutableArray array];
  [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.browser=[TLDevToolsTestBrowser new];self.browser.testCache=args[2];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(80,80,1100,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];self.window.releasedWhenClosed=NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/clear"]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:360 browserService:self.browser];
  self.otherTab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/clear"]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark] database:nil orchestrator:nil inputWidth:360 browserService:self.browser];
#pragma clang diagnostic pop
  NSView *content=self.window.contentView;
  [content addSubview:self.tab.view];[content addSubview:self.otherTab.view];
  [NSLayoutConstraint activateConstraints:@[
    [self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [self.tab.view.widthAnchor constraintEqualToAnchor:content.widthAnchor multiplier:0.5],
    [self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor],
    [self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    [self.otherTab.view.leadingAnchor constraintEqualToAnchor:self.tab.view.trailingAnchor],
    [self.otherTab.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [self.otherTab.view.topAnchor constraintEqualToAnchor:content.topAnchor],
    [self.otherTab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
  [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[content layoutSubtreeIfNeeded];
  [self.tab startInWindow:self.window];[self.otherTab startInWindow:self.window];
  [self waitFor:^BOOL{return self.session.browserIdentifier>=0 && [[[self.session valueForKey:@"documentFooter"] valueForKey:@"ready"] boolValue];}
    then:^{[self after:0.5 run:^{[self begin];}];} attempt:0];
  [self after:60 run:^{if(self.tab){[self check:NO name:@"Integration deadline"];[self finish];}}];
}
- (void)showInspector {
  CefWindowInfo info;CefBrowserSettings settings;
  [self cef]->GetHost()->ShowDevTools(info,nullptr,settings,CefPoint(40,20));
}
- (void)selectContextItem:(NSString *)title then:(dispatch_block_t)completion {
  if(self.menuObserver)[NSNotificationCenter.defaultCenter removeObserver:self.menuObserver];
  __weak TLDevToolsTestDelegate *weakSelf=self;
  self.menuObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note){
    NSMenu *menu=note.object;
    NSInteger index=[menu indexOfItemWithTitle:title];
    if(index<0)return;
    [weakSelf after:0.1 run:^{
      NSArray *expected=@[@"Reload Page",@"",@"Show Page Source",@"Save Page As…",@"",@"Print Page…",@"",@"Inspect Element"];
      NSMutableArray *actual=[NSMutableArray array];
      for(NSMenuItem *item in menu.itemArray)[actual addObject:item.separatorItem ? @"" : item.title];
      [weakSelf check:[actual isEqual:expected] name:@"Plain-page native menu matches the reference order and separators"];
      [weakSelf check:[menu itemWithTitle:@"Print Page…"].image!=nil name:@"Print Page has its native printer icon"];
      [NSNotificationCenter.defaultCenter removeObserver:weakSelf.menuObserver];weakSelf.menuObserver=nil;
      [menu performActionForItemAtIndex:index];[menu cancelTracking];
      [weakSelf after:0.1 run:completion];
    }];
  }];
  auto page=[self cef];
  NSView *view=(__bridge NSView *)page->GetHost()->GetWindowHandle();
  [self.window makeKeyAndOrderFront:nil];
  NSPoint point=[view convertPoint:NSMakePoint(200,view.isFlipped ? 160 : NSHeight(view.bounds)-160) toView:nil];
  NSEvent *event=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  [NSApp sendEvent:event];
  NSEvent *release=[NSEvent mouseEventWithType:NSEventTypeRightMouseUp location:point modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
  [NSApp sendEvent:release];
}
- (void)begin {
  auto page=[self cef];auto handler=page->GetHost()->GetClient()->GetContextMenuHandler();
  [self check:handler!=nullptr name:@"Browser provides a context menu handler"];
  if(!handler){[self finish];return;}
  auto menu=CefMenuModel::CreateMenuModel(new TLDevToolsTestMenuDelegate);
  menu->AddItem(MENU_ID_BACK,"Back");menu->AddSeparator();menu->AddItem(MENU_ID_COPY,"Copy");
  handler->OnBeforeContextMenu(page,page->GetMainFrame(),nullptr,menu);
  [self check:menu->GetCount()==10 && menu->GetCommandIdAt(0)==MENU_ID_COPY && menu->GetTypeAt(1)==MENUITEMTYPE_SEPARATOR name:@"Page menu preserves contextual editing commands"];
  [self check:!handler->OnContextMenuCommand(page,page->GetMainFrame(),nullptr,MENU_ID_COPY,EVENTFLAG_NONE) name:@"Standard editing commands retain Chromium handling"];
  NSUInteger generation=self.session.documentGeneration;
  [self selectContextItem:@"Reload Page" then:^{
    [self waitFor:^BOOL{return self.session.documentGeneration>generation && ![self cef]->IsLoading();} then:^{
      [self check:YES name:@"Reload Page reloads the inspected page"];
      [self testSource];
    } attempt:0];
  }];
}
- (void)testSource {
  [self selectContextItem:@"Show Page Source" then:^{
    [self waitFor:^BOOL{auto popup=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];return self.browser.inspectorCount>0 && popup && !popup->IsLoading();} then:^{
      auto popup=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];
      self.windowText=nil;popup->GetMainFrame()->GetText(new TLContextMenuTextVisitor(^(NSString *text){self.windowText=text;}));
      [self waitFor:^BOOL{return self.windowText!=nil;} then:^{
        [self check:[self.windowText containsString:@"<p>"] && [self.windowText containsString:@"Normal page"] name:@"Show Page Source displays actual HTML in a separate browser window"];
        [self check:!self.session.devToolsVisible && [self inset:self.tab]==0 name:@"Source window does not change the page or footer mode"];
        popup->GetHost()->CloseBrowser(true);
        [self testSave];
      } attempt:0];
    } attempt:0];
  }];
}
- (void)sendKey:(NSString *)characters code:(unsigned short)code toWindow:(NSWindow *)window {
  [window makeKeyWindow];
  for(NSNumber *kind in @[@(NSEventTypeKeyDown),@(NSEventTypeKeyUp)]) {
    NSEvent *event=[NSEvent keyEventWithType:(NSEventType)kind.unsignedIntegerValue location:NSZeroPoint modifierFlags:0
      timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
      characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
    [NSApp sendEvent:event];
  }
}
- (void)testSave {
  [self selectContextItem:@"Save Page As…" then:^{
    [self waitFor:^BOOL{return self.browser.savePanel!=nil && self.window.attachedSheet!=nil;} then:^{
      [self check:self.window.attachedSheet!=nil name:@"Save Page As opens a native save sheet"];
      [self.browser.savePanel cancel:nil];
      [self waitFor:^BOOL{return self.window.attachedSheet==nil;} then:^{
        [self check:YES name:@"The native save sheet can be cancelled"];
        [self saveToTestDestination];
      } attempt:0];
    } attempt:0];
  }];
}
- (void)saveToTestDestination {
  NSString *directory=[NSProcessInfo.processInfo.arguments[3] stringByDeletingLastPathComponent];
  NSString *path=[directory stringByAppendingPathComponent:@"Saved page.mhtml"];
  self.browser.archiveDestination=[NSURL fileURLWithPath:path];
  [self check:![NSFileManager.defaultManager fileExistsAtPath:path] name:@"Cancelling Save creates no file"];
  [self selectContextItem:@"Save Page As…" then:^{
    [self waitFor:^BOOL{return [NSFileManager.defaultManager fileExistsAtPath:path];} then:^{
      NSString *archive=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
      [self check:[archive containsString:@"multipart/related"] && [archive containsString:@"Normal page"] name:@"Saving writes a self-contained MHTML page archive to the chosen URL"];
      [self.browser createBrowserWithURLString:[NSURL fileURLWithPath:path].absoluteString parentView:nil];
      [self waitFor:^BOOL{auto popup=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];return popup && !popup->IsLoading() && popup->GetMainFrame()->GetURL().ToString().find("file:")==0;} then:^{
        auto popup=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];
        self.windowText=nil;popup->GetMainFrame()->GetText(new TLContextMenuTextVisitor(^(NSString *text){self.windowText=text;}));
        [self waitFor:^BOOL{return self.windowText!=nil;} then:^{
          [self check:[self.windowText containsString:@"Normal page"] name:@"The saved archive reopens as a working page"];
          popup->GetHost()->CloseBrowser(true);[self testPrint];
        } attempt:0];
      } attempt:0];
    } attempt:0];
  }];
}
- (void)testPrint {
  [self selectContextItem:@"Print Page…" then:^{
    [self waitFor:^BOOL{return self.window.attachedSheet!=nil || NSApp.modalWindow!=nil;} then:^{
      NSWindow *panel=self.window.attachedSheet ?: NSApp.modalWindow;
      [self check:panel!=nil name:@"Print Page opens a native print dialog"];
      [self after:0.3 run:^{[self sendKey:@"\033" code:53 toWindow:panel];}];
      [self waitFor:^BOOL{return self.window.attachedSheet==nil && NSApp.modalWindow==nil;} then:^{
        [self check:YES name:@"Print dialog cancels without printing"];
        self.browser.inspectorCount=0;
        [self selectContextItem:@"Inspect Element" then:^{
          [self waitFor:^BOOL{return self.session.devToolsVisible && [self inset:self.tab]<0;}
            then:^{[self after:0.5 run:^{[self verifyOpen];}];} attempt:0];
        }];
      } attempt:0];
    } attempt:0];
  }];
}
- (void)verifyOpen {
  auto page=[self cef];
  auto inspector=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];
  [self check:page->GetHost()->HasDevTools() && inspector!=nullptr name:@"DevTools opens and reports visibility on its source session"];
  if(!inspector){[self finish];return;}
  NSView *pageView=(__bridge NSView *)page->GetHost()->GetWindowHandle();
  NSView *inspectorView=(__bridge NSView *)inspector->GetHost()->GetWindowHandle();
  [self check:pageView.window==self.window && inspectorView.window!=self.window name:@"DevTools uses its own window without replacing the page"];
  [self check:[self inset:self.tab]<0 && [self inset:self.otherTab]==0 name:@"Only the inspected tab raises its footer"];
  NSDictionary *configuration=[self.session valueForKey:@"documentFooterConfiguration"];
  [self check:![configuration[@"enabled"] boolValue] name:@"DevTools disables the document spacer while the native footer is raised"];
  [self.tab toggleBrowserHeightMode:nil];
  [self check:[[self.tab valueForKey:@"browserUsesReducedHeight"] boolValue] name:@"Manual toggle cannot lower the footer while inspecting"];
  NSInteger identifier=self.browser.inspectorIdentifier;
  [self showInspector];
  [self after:0.5 run:^{
    [self check:self.browser.inspectorCount==1 && self.browser.inspectorIdentifier==identifier name:@"Repeated Inspect reuses the existing DevTools window"];
    NSUInteger generation=self.session.documentGeneration;
    [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/clear?next"]]];
    [self waitFor:^BOOL{return self.session.documentGeneration>generation && [[[self.session valueForKey:@"documentFooter"] valueForKey:@"ready"] boolValue];}
      then:^{[self after:0.5 run:^{[self verifyNavigationAndClose];}];} attempt:0];
  }];
}
- (void)verifyNavigationAndClose {
  [self check:self.session.devToolsVisible && [self inset:self.tab]<0 name:@"Navigation preserves the raised footer while DevTools stays open"];
  auto inspector=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier];
  NSView *inspectorView=(__bridge NSView *)inspector->GetHost()->GetWindowHandle();
  [inspectorView.window performClose:nil];
  [self waitFor:^BOOL{return !self.session.devToolsVisible && [self inset:self.tab]==0;}
    then:^{
      [self check:![self cef]->GetHost()->HasDevTools() name:@"Closing the native DevTools window clears visibility"];
      [self check:[self inset:self.tab]==0 && [self inset:self.otherTab]==0 name:@"Closing DevTools restores automatic footer placement"];
      [self showInspector];
      [self waitFor:^BOOL{return self.session.devToolsVisible && self.browser.inspectorCount==2;}
        then:^{
          NSInteger identifier=self.browser.inspectorIdentifier;
          [self.tab close];
          [self waitFor:^BOOL{return [self.browser browserWithIdentifier:(int)identifier]==nullptr;}
            then:^{[self check:YES name:@"Closing the inspected tab also closes DevTools"];[self finish];} attempt:0];
        } attempt:0];
    } attempt:0];
}
- (void)finish {
  dispatch_async(dispatch_get_main_queue(),^{[self finishAfterCallbacks];});
}
- (void)finishAfterCallbacks {
  if(!self.tab)return;
  if(self.menuObserver)[NSNotificationCenter.defaultCenter removeObserver:self.menuObserver];self.menuObserver=nil;
  [self.tab close];[self.otherTab close];self.tab=nil;self.otherTab=nil;
  if(auto popup=[self.browser browserWithIdentifier:(int)self.browser.inspectorIdentifier])popup->GetHost()->CloseBrowser(true);
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{TLChromiumBrowserControllerConfigureMainArgs(argc,argv);TLDevToolsTestApplication *app=[TLDevToolsTestApplication sharedApplication];TLDevToolsTestDelegate *delegate=[TLDevToolsTestDelegate new];app.delegate=delegate;[app run];}return 0;}
