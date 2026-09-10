// Real WebKit DevTools lifecycle and native footer layout, using an isolated profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
@interface TLWebKitBrowserController (DevToolsTests)
- (NSSavePanel *)pageSavePanel;
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion;
- (void)inspectSession:(TLWebKitBrowserSession *)session atPoint:(NSPoint)point;
- (void)closeInspectorInSession:(TLWebKitBrowserSession *)session;
- (NSMenu *)pageMenuForSession:(TLWebKitBrowserSession *)session contextMenu:(NSMenu *)menu point:(NSPoint)point;
@end
@interface TLBrowserTabController (DevToolsTests)
- (void)toggleBrowserHeightMode:(id)sender;
@end
@interface TLDevToolsTestApplication : NSApplication
@end
@implementation TLDevToolsTestApplication
@end
@interface TLDevToolsTestBrowser : TLWebKitBrowserController
@property(nonatomic) NSInteger inspectorIdentifier;
@property(nonatomic) NSUInteger inspectorCount;
@property(nonatomic,strong) NSSavePanel *savePanel;
@property(nonatomic,strong) NSURL *archiveDestination;
@end
@implementation TLDevToolsTestBrowser
- (NSSavePanel *)pageSavePanel { self.savePanel=[super pageSavePanel];return self.savePanel; }
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion {
  // Exercise the real sheet's cancellation separately from the user's chosen URL.
  if(self.archiveDestination)completion(self.archiveDestination);
  else [super choosePageArchiveURL:name fromWindow:window completion:completion];
}
@end
static WKWebView *TLFindTestWebView(NSView *view) {
  if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
  for (NSView *child in view.subviews) { WKWebView *found=TLFindTestWebView(child); if(found)return found; }
  return nil;
}
static NSTextView *TLFindTestTextView(NSView *view) {
  if ([view isKindOfClass:NSTextView.class]) return (NSTextView *)view;
  for (NSView *child in view.subviews) { NSTextView *found=TLFindTestTextView(child); if(found)return found; }
  return nil;
}
@interface TLDevToolsTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLDevToolsTestBrowser *browser;
@property(nonatomic,strong) TLBrowserTabController *tab, *otherTab;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic,strong) id menuObserver;
@property(nonatomic,copy) NSString *windowText;
@property(nonatomic,weak) NSWindow *inspectorWindow;
@property(nonatomic,strong) NSHashTable<NSWindow *> *seenInspectorWindows;
@end
@implementation TLDevToolsTestDelegate
- (void)after:(double)seconds run:(dispatch_block_t)block {
  // System printing runs a modal loop that does not drain the main GCD queue.
  NSTimer *timer=[NSTimer timerWithTimeInterval:seconds repeats:NO block:^(NSTimer *){block();}];
  for(NSString *mode in @[NSRunLoopCommonModes,NSModalPanelRunLoopMode,NSEventTrackingRunLoopMode])
    [NSRunLoop.mainRunLoop addTimer:timer forMode:mode];
}
- (TLWebKitBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (WKWebView *)webView { return self.session.webView; }
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
  self.browser=[TLDevToolsTestBrowser new];
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
  TLTestActivateWindow(self.window,^{[self waitFor:^BOOL{return self.session.browserIdentifier>=0 && [[[self.session valueForKey:@"pageBridge"] valueForKey:@"ready"] boolValue];}
    then:^{[self after:0.5 run:^{[self begin];}];} attempt:0];});
  [self after:60 run:^{if(self.tab){[self check:NO name:@"Integration deadline"];[self finish];}}];
}
- (void)showInspector { [self.browser inspectSession:self.session atPoint:NSMakePoint(40,20)]; }
- (WKWebView *)popup {
  for(NSWindow *window in NSApp.windows) {
    if(window != self.window && window.isVisible && ![window isKindOfClass:NSPanel.class]) {
      WKWebView *view=TLFindTestWebView(window.contentView); if(view)return view;
    }
  }
  return nil;
}
- (NSWindow *)visibleInspector {
  if(self.inspectorWindow.isVisible)return self.inspectorWindow;
  for(NSWindow *window in NSApp.windows) {
    if(window != self.window && window.isVisible && ![window isKindOfClass:NSPanel.class]) {
      self.inspectorWindow=window;
      if(!self.seenInspectorWindows)self.seenInspectorWindows=[NSHashTable weakObjectsHashTable];
      if(![self.seenInspectorWindows containsObject:window]) { [self.seenInspectorWindows addObject:window];self.browser.inspectorCount++; }
      return window;
    }
  }
  return nil;
}
- (void)selectContextItem:(NSString *)title then:(dispatch_block_t)completion {
  if(self.menuObserver)[NSNotificationCenter.defaultCenter removeObserver:self.menuObserver];
  __weak TLDevToolsTestDelegate *weakSelf=self;
  self.menuObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidBeginTrackingNotification object:nil queue:nil usingBlock:^(NSNotification *note){
    NSMenu *menu=note.object;
    NSLog(@"Native context tracking items: %@",[menu.itemArray valueForKey:@"title"]);
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
  NSView *view=self.session.webView;
  [self.window makeKeyAndOrderFront:nil];
  NSPoint point=[view convertPoint:NSMakePoint(200,view.isFlipped ? 160 : NSHeight(view.bounds)-160) toView:nil];
  NSEvent *event=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
  NSView *target=[self.window.contentView hitTest:point];
  NSLog(@"Sending native context click to %@ at %@; view %@",target,NSStringFromPoint(point),NSStringFromRect(view.frame));
  [NSApp postEvent:event atStart:NO];
  NSEvent *release=[NSEvent mouseEventWithType:NSEventTypeRightMouseUp location:point modifierFlags:0
    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:view.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
  [NSApp postEvent:release atStart:NO];
}
- (void)begin {
  NSMenu *original=[NSMenu new];
  [original addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
  NSMenuItem *copy=original.itemArray.firstObject;
  NSMenu *menu=[self.browser pageMenuForSession:self.session contextMenu:original point:NSZeroPoint];
  [self check:menu!=nil name:@"Browser provides a context menu handler"];
  [self check:menu.numberOfItems==10 && [menu.itemArray.firstObject.title isEqual:copy.title] && menu.itemArray.firstObject.action==copy.action && menu.itemArray.firstObject.target==copy.target && [menu itemAtIndex:1].separatorItem name:@"Page menu preserves contextual editing commands"];
  [self check:copy.action==@selector(copy:) name:@"Standard editing commands retain WebKit handling"];
  NSUInteger generation=self.session.documentGeneration;
  [self selectContextItem:@"Reload Page" then:^{
    [self waitFor:^BOOL{return self.session.documentGeneration>generation && !self.session.webView.loading;} then:^{
      [self check:YES name:@"Reload Page reloads the inspected page"];
      [self testSource];
    } attempt:0];
  }];
}
- (NSWindow *)sourceWindow {
  for(NSWindow *candidate in NSApp.windows) if(candidate!=self.window && candidate.isVisible && [candidate.title hasPrefix:@"Source:"])return candidate;
  return nil;
}
- (void)testSource {
  [self selectContextItem:@"Show Page Source" then:^{
    [self waitFor:^BOOL{return self.sourceWindow!=nil;} then:^{
      NSTextView *source=TLFindTestTextView(self.sourceWindow.contentView);
      [self check:[source.string containsString:@"<p>"] && [source.string containsString:@"Normal page"] name:@"Show Page Source displays actual HTML in a separate window"];
      [self check:source.selectable && !source.editable name:@"Page source is selectable and read-only"];
      [self check:!self.session.devToolsVisible && [self inset:self.tab]==0 name:@"Source window does not change the page or footer mode"];
      [self.sourceWindow performClose:nil];
      [self testSave];
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
  NSString *path=[directory stringByAppendingPathComponent:@"Saved page.webarchive"];
  self.browser.archiveDestination=[NSURL fileURLWithPath:path];
  [self check:![NSFileManager.defaultManager fileExistsAtPath:path] name:@"Cancelling Save creates no file"];
  [self selectContextItem:@"Save Page As…" then:^{
    [self waitFor:^BOOL{return [NSFileManager.defaultManager fileExistsAtPath:path];} then:^{
      NSDictionary *archive=[NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:path] options:NSPropertyListImmutable format:nil error:nil];
      NSString *HTML=[[NSString alloc] initWithData:archive[@"WebMainResource"][@"WebResourceData"] encoding:NSUTF8StringEncoding];
      [self check:archive[@"WebMainResource"] && [HTML containsString:@"Normal page"] name:@"Saving writes a self-contained WebArchive to the chosen URL"];
      [self.browser openURL:[NSURL fileURLWithPath:path] fromWindow:nil];
      [self waitFor:^BOOL{return self.popup && !self.popup.loading && self.popup.URL.isFileURL;} then:^{
        WKWebView *popup=self.popup;
        self.windowText=nil; TLTestEvaluate(popup,@"document.body.innerText",^(NSString *text){self.windowText=text;});
        [self waitFor:^BOOL{return self.windowText!=nil;} then:^{
          [self check:[self.windowText containsString:@"Normal page"] name:@"The saved archive reopens as a working page"];
          [popup.window performClose:nil];[self testPrint];
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
  NSWindow *inspector=[self visibleInspector];
  [self check:self.session.devToolsVisible && inspector!=nil name:@"DevTools opens and reports visibility on its source session"];
  if(!inspector){[self finish];return;}
  NSView *pageView=self.session.webView;
  NSView *inspectorView=inspector.contentView;
  [self check:pageView.window==self.window && inspectorView.window!=self.window name:@"DevTools uses its own window without replacing the page"];
  [self check:[self inset:self.tab]<0 && [self inset:self.otherTab]==0 name:@"Only the inspected tab raises its footer"];
  NSDictionary *configuration=[self.session valueForKey:@"documentFooterConfiguration"];
  [self check:![configuration[@"enabled"] boolValue] name:@"DevTools disables the document spacer while the native footer is raised"];
  [self.tab toggleBrowserHeightMode:nil];
  [self check:[[self.tab valueForKey:@"browserUsesReducedHeight"] boolValue] name:@"Manual toggle cannot lower the footer while inspecting"];
  NSWindow *originalInspector=self.inspectorWindow;
  [self showInspector];
  [self after:0.5 run:^{
    [self check:self.browser.inspectorCount==1 && [self visibleInspector]==originalInspector name:@"Repeated Inspect reuses the existing DevTools window"];
    NSUInteger generation=self.session.documentGeneration;
    [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/clear?next"]]];
    [self waitFor:^BOOL{return self.session.documentGeneration>generation && [[[self.session valueForKey:@"pageBridge"] valueForKey:@"ready"] boolValue];}
      then:^{[self after:0.5 run:^{[self verifyNavigationAndClose];}];} attempt:0];
  }];
}
- (void)verifyNavigationAndClose {
  [self check:self.session.devToolsVisible && [self inset:self.tab]<0 name:@"Navigation preserves the raised footer while DevTools stays open"];
  [[self visibleInspector] performClose:nil];
  [self waitFor:^BOOL{return !self.session.devToolsVisible && [self inset:self.tab]==0;}
    then:^{
      [self check:!self.session.devToolsVisible name:@"Closing the native DevTools window clears visibility"];
      [self check:[self inset:self.tab]==0 && [self inset:self.otherTab]==0 name:@"Closing DevTools restores automatic footer placement"];
      [self showInspector];
      [self waitFor:^BOOL{return self.session.devToolsVisible && [self visibleInspector] && self.browser.inspectorCount==2;}
        then:^{
          NSWindow *closingInspector=self.inspectorWindow;
          [self.tab close];
          [self waitFor:^BOOL{return !closingInspector.isVisible;}
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
  if(self.popup)[self.popup.window performClose:nil];
  [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil] writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{if(argc>2)setenv("TL_WEBKIT_PROFILE_DIR",argv[2],1);TLDevToolsTestApplication *app=[TLDevToolsTestApplication sharedApplication];TLDevToolsTestDelegate *delegate=[TLDevToolsTestDelegate new];app.delegate=delegate;[app run];}return 0;}
