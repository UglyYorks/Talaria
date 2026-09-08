// Desktop CEF integration against a local fixture and disposable browser profile.
#import <AppKit/AppKit.h>
#import "ChromiumBrowserController.h"
#import "TLBrowserTabController.h"
#import "design_system/TLFindBar.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
@interface TLChromiumBrowserController (FindIntegration)
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (void)browserFindResult:(CefRefPtr<CefBrowser>)browser identifier:(int)identifier count:(int)count activeMatch:(int)activeMatch finalUpdate:(BOOL)finalUpdate;
@end
@interface TLFindCEFApplication : NSApplication <CefAppProtocol>
@property (nonatomic) BOOL handlingSendEvent;
@end
@implementation TLFindCEFApplication
- (BOOL)isHandlingSendEvent { return self.handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event { CefScopedSendingEvent scoped; [super sendEvent:event]; }
@end
@interface TLFindCEFBrowser : TLChromiumBrowserController
@end
@implementation TLFindCEFBrowser
- (void)browserFindResult:(CefRefPtr<CefBrowser>)browser identifier:(int)identifier count:(int)count activeMatch:(int)activeMatch finalUpdate:(BOOL)finalUpdate {
  NSLog(@"Find callback id=%d count=%d active=%d final=%d",identifier,count,activeMatch,finalUpdate);
  [super browserFindResult:browser identifier:identifier count:count activeMatch:activeMatch finalUpdate:finalUpdate];
}
- (NSString *)chromiumCachePath { return NSProcessInfo.processInfo.arguments[2]; }
@end
@interface TLFindCEFDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) TLFindCEFBrowser *browser;
@property (nonatomic, strong) TLBrowserTabController *tab;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSMutableArray *results;
@end
@implementation TLFindCEFDelegate
- (TLFindBar *)bar { return [self.tab valueForKey:@"findBar"]; }
- (TLChromiumBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (void)check:(BOOL)passed name:(NSString *)name {
  NSLog(@"%@: %@", passed ? @"PASS" : @"FAIL", name);
  [self.results addObject:@{@"name":name, @"passed":@(passed)}];
}
- (void)waitFor:(BOOL (^)(void))condition then:(dispatch_block_t)completion attempt:(NSUInteger)attempt {
  if (!self.tab) return;
  if (condition()) { completion(); return; }
  if (attempt >= 100) { [self check:NO name:[NSString stringWithFormat:@"Find result deadline: browser=%ld generation=%lu label=%@", (long)self.session.browserIdentifier, (unsigned long)self.session.documentGeneration, self.bar.resultLabel.stringValue]]; [self finish]; return; }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    [self waitFor:condition then:completion attempt:attempt + 1];
  });
}
- (void)expect:(NSString *)label then:(dispatch_block_t)completion {
  [self waitFor:^BOOL { return [self.bar.resultLabel.stringValue isEqual:label]; }
    then:^{ [self check:YES name:[@"Native find result: " stringByAppendingString:label]]; completion(); } attempt:0];
}
- (void)query:(NSString *)query {
  self.bar.searchField.stringValue = query;
  [self.bar controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:self.bar.searchField]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.results = [NSMutableArray array]; self.browser = [TLFindCEFBrowser new];
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 800, 600)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  self.window.releasedWhenClosed = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab = [[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:NSProcessInfo.processInfo.arguments[1]]
    palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:360 browserService:self.browser];
#pragma clang diagnostic pop
  NSView *content = self.window.contentView;
  [content addSubview:self.tab.view];
  [NSLayoutConstraint activateConstraints:@[
    [self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [self.tab.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor],
    [self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
  ]];
  [content layoutSubtreeIfNeeded];
  [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  [self.tab startInWindow:self.window];
  [self waitFor:^BOOL {
    auto cef = [self.browser browserWithIdentifier:(int)self.session.browserIdentifier];
    return cef && !cef->IsLoading() && self.session.documentGeneration > 0;
  } then:^{ [self begin]; } attempt:0];
}
- (void)begin {
  [self check:YES name:@"Browser fixture loaded"];
  [self.tab showFindBar]; [self query:@"needle"];
  [self expect:@"1/3" then:^{
    [self check:self.window.firstResponder == self.bar.searchField.currentEditor name:@"Native search keeps query focus"];
    [self.tab findNext:YES];
    [self expect:@"2/3" then:^{
      [self.tab findNext:NO];
      [self expect:@"1/3" then:^{
        [self.tab findNext:NO];
        [self expect:@"3/3" then:^{
          [self.tab findNext:YES];
          [self expect:@"1/3" then:^{ [self rapidQueries]; }];
        }];
      }];
    }];
  }];
}
- (void)rapidQueries {
  [self query:@"absent"]; [self query:@"needle"]; [self query:@"unique"];
  [self expect:@"1/1" then:^{
    [self query:@"absent"];
    [self expect:@"0 matches" then:^{
      [self check:!self.bar.nextButton.enabled name:@"No matches disables navigation"];
      [self query:@""];
      [self check:!self.bar.resultLabel.stringValue.length && ![[self.session valueForKey:@"finding"] boolValue] name:@"Clear cancels Chromium search"];
      [self query:@"needle"];
      [self expect:@"1/3" then:^{ [self closeAndReopen]; }];
    }];
  }];
}
- (void)closeAndReopen {
  [self.tab hideFindBar];
  [self check:!self.tab.findBarVisible && ![[self.session valueForKey:@"finding"] boolValue] name:@"Close removes find and native highlights"];
  [self check:self.window.firstResponder != self.bar.searchField.currentEditor name:@"Close releases query editor"];
  [self.tab showFindBar];
  [self expect:@"1/3" then:^{
    [self.tab applyPalette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
    [self check:[self.bar.resultLabel.stringValue isEqual:@"1/3"] name:@"Theme switching preserves results"];
    NSUInteger generation = self.session.documentGeneration;
    [self.browser reloadSession:self.session];
    [self waitFor:^BOOL { return self.session.documentGeneration > generation; }
      then:^{
        [self check:!self.tab.findBarVisible && ![[self.session valueForKey:@"finding"] boolValue] name:@"Reload clears document search"];
        [self finish];
      } attempt:0];
  }];
}
- (void)finish {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.tab close]; self.tab = nil;
    [[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil]
      writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];
    [NSApp terminate:nil];
  });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
  return [self.browser prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater;
}
@end
int main(int argc, char **argv) {
  @autoreleasepool {
    TLChromiumBrowserControllerConfigureMainArgs(argc, argv);
    TLFindCEFApplication *app = [TLFindCEFApplication sharedApplication];
    TLFindCEFDelegate *delegate = [TLFindCEFDelegate new]; app.delegate = delegate; [app run];
  }
  return 0;
}
