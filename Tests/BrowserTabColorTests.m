#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "design_system/TLTransitionCoordinator.h"
#import "TalariaWindowController.h"
#import "TLBrowserTabController.h"
#import "TLMainWindow.h"
#import "TLWorkspaceTabsController.h"
#import "design_system/TLChromeTabView.h"
#import "design_system/UIComponents.h"

@interface TalariaWindowController (TabColorTests)
- (void)buildInterface;
- (void)installAppStateBindings;
- (void)updateBrowserTabColorSample;
- (TLBrowserTabController *)activeBrowserController;
- (void)applyTheme;
- (TLWorkspaceTab *)activeWorkspaceTab;
- (void)splitTab:(TLWorkspaceTab *)tab besideTab:(TLWorkspaceTab *)other onLeft:(BOOL)left;
- (void)startNewChatWithModel:(NSString *)model focus:(BOOL)focus;
- (void)focusSplitPane:(BOOL)right;
@end
@interface TLTabColorTestController : TalariaWindowController
@end
@implementation TLTabColorTestController
- (void)refreshHermesHistory {}
- (void)generateChatIconIfNeededForChatID:(NSInteger)chatID messages:(NSArray *)messages {}
@end
static void Check(BOOL condition, NSString *message) {
  NSLog(@"%@: %@", condition ? @"PASS" : @"FAIL", message);
  if (!condition) exit(1);
}
static void Later(double seconds, dispatch_block_t block) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds*NSEC_PER_SEC), dispatch_get_main_queue(), block);
}
@interface TLTabColorTestDelegate : NSObject <NSApplicationDelegate>
@property TLTabColorTestController *owner;
@property TLBrowserTabController *browser;
@end
@implementation TLTabColorTestDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
  NSArray *args = NSProcessInfo.processInfo.arguments;
  NSWindow *window = [[TLMainWindow alloc] initWithContentRect:NSMakeRect(100,100,1100,700)
    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
    backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.titleVisibility = NSWindowTitleHidden; window.titlebarAppearsTransparent = YES;
  self.owner = [[TLTabColorTestController alloc] initWithWindow:window];
  TLDatabase *database = [[TLDatabase alloc] initWithURL:[NSURL fileURLWithPath:args[2]] error:nil];
  [self.owner setValue:database forKey:@"database"];
  [self.owner setValue:[TLAppStateManager new] forKey:@"appStateManager"];
  [self.owner setValue:[NSMutableArray array] forKey:@"appStateSubscriptions"];
  [self.owner setValue:[NSMutableDictionary dictionary] forKey:@"workspaceTabRuntimes"];
  [self.owner setValue:[TLAppSettings defaultSettings] forKey:@"settings"];
  [self.owner setValue:[TLThemePalette paletteForPreference:TLThemePreferenceLight] forKey:@"palette"];
  [self.owner setValue:[NSMutableArray array] forKey:@"agents"];
  [self.owner setValue:[NSMutableArray array] forKey:@"chats"];
  [self.owner setValue:@(-1) forKey:@"nextDraftChatID"];
  [self.owner setValue:@1 forKey:@"nextBrowserTabID"];
  [self.owner buildInterface]; [self.owner installAppStateBindings];
  [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  [self.owner startNewChatWithModel:@"test" focus:NO];
  [self.owner openBrowserTabWithURL:[NSURL URLWithString:args[1]]];
  Later(3, ^{ [self checkPage]; });
  Later(40, ^{ Check(NO, @"Desktop tab color test deadline"); });
}
- (void)checkPage {
  self.browser=[self.owner activeBrowserController];
  TLWebKitBrowserSession *session=[self.browser valueForKey:@"browserSession"];
  if(@available(macOS 26.0,*))Check(session.webView.obscuredContentInsets.top==0,@"Tabs do not extend the native page viewport");
  for(NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    TLThemePalette *palette=[TLThemePalette paletteForPreference:theme.integerValue];
    Check([[palette textColorForContentBackground:TLColorFromHex(0x0D78E8)] isEqual:palette.white],@"Medium blue uses white tab labels in both themes");
    Check([[palette textColorForContentBackground:TLColorFromHex(0xEDF0F1)] isEqual:palette.black],@"Light page backgrounds retain dark labels");
  }
  TLBrowserViewportView *viewport=[self.browser valueForKey:@"browserHostView"];
  Check(viewport.contentView.layer.filters.count==0,@"Page content has no tab blur filter");
  TLChromeTabSelectionView *selection=[[self.owner valueForKey:@"workspaceTabsController"] selectionView];
  Check([selection.displayedBackgroundColor isEqual:self.browser.headerContentColor],@"Initial page color is applied without a transition");
  Check(self.browser.headerColorChangesAnimated,@"Loaded page enables subsequent color transitions");
  [self checkAdaptiveTiming];
  [self checkSolidColor:0];
}
- (void)checkAdaptiveTiming {
  TLChromeTabSelectionView *selection=[[TLChromeTabSelectionView alloc] initWithFrame:NSMakeRect(0,0,300,40)];
  __block NSTimeInterval now=0;
  TLTransitionCoordinator *clock=[[TLTransitionCoordinator alloc] initWithClock:^{return now;} automaticallyAdvances:NO];
  [selection setValue:clock forKey:@"colorTransition"];
  TLThemePalette *palette=selection.palette;
  [selection setSelectionFrame:NSMakeRect(0,0,300,40) leadingFlareOutset:0 animated:NO fromFrame:NSZeroRect duration:0];
  [selection setContentBackgroundColor:palette.black animated:NO];
  [selection setContentBackgroundColor:palette.white animated:YES];
  NSArray *darkLightLocations=[[(CAGradientLayer *)[selection valueForKey:@"waveMask"] locations] copy];
  now=1.2;[clock advance];
  CGFloat early=[[selection valueForKey:@"waveProgress"] doubleValue];
  now=1.8;[clock advance];
  CGFloat late=[[selection valueForKey:@"waveProgress"] doubleValue];
  Check(early<.2 && late>.8,@"High-contrast sweep crosses most of the tab in the middle 0.6 seconds");
  [selection setContentBackgroundColor:palette.black animated:YES];
  Check([[selection valueForKey:@"waveProgress"] doubleValue]==0,@"New color starts immediately instead of waiting for the old wave");
  CALayer *frozen=[selection valueForKey:@"frozenBackground"];
  Check(!frozen.hidden && frozen.contents!=nil,@"Interrupted native background is preserved beneath the new wave");
  now=2.4;[clock advance];
  CGFloat restarted=[[selection valueForKey:@"waveProgress"] doubleValue];
  [selection setContentBackgroundColor:palette.black animated:YES];
  Check([[selection valueForKey:@"waveProgress"] doubleValue]==restarted,@"Unchanged samples do not restart an active wave");
  now=3.01;[clock advance];
  Check(![[selection valueForKey:@"waveActive"] boolValue] && frozen.hidden && !frozen.contents,@"Latest color keeps the original deadline without a queue or retained snapshot");
  [selection setContentBackgroundColor:palette.white animated:NO];
  Check(!clock.hasTransitions && ![[selection valueForKey:@"waveActive"] boolValue],@"Immediate updates cancel the pending wave");
  [selection setContentBackgroundColor:TLColorFromHex(0xEEEEEE) animated:YES];
  Check([darkLightLocations isEqual:[(CAGradientLayer *)[selection valueForKey:@"waveMask"] locations]],@"Similar and contrasting colors use identical gradient bands");
  [clock finishAllTransitions];
}
- (void)checkSolidColor:(NSUInteger)step {
  BOOL dark=step==1;
  __block NSTimeInterval waveTime=0;
  TLChromeTabSelectionView *selection=[[self.owner valueForKey:@"workspaceTabsController"] selectionView];
  TLTransitionCoordinator *controlled=dark ? [[TLTransitionCoordinator alloc] initWithClock:^{return waveTime;} automaticallyAdvances:NO] : nil;
  if(controlled)[selection setValue:controlled forKey:@"colorTransition"];
  TLWebKitBrowserSession *session=[self.browser valueForKey:@"browserSession"];
  NSString *script=[NSString stringWithFormat:@"document.body.style.background='rgb(%d,%d,%d)';scrollTo(0,%lu);true",dark?10:245,dark?10:245,dark?10:245,(unsigned long)(500+step*20)];
  [session.webView evaluateJavaScript:script completionHandler:^(id value,NSError *error){
    Check(!error,@"Scroll across a changed page edge");
    if(dark) Later(1.5,^{
      waveTime=1.5;[controlled advance];
      TLWorkspaceTabsController *tabs=[self.owner valueForKey:@"workspaceTabsController"];
      CAShapeLayer *base=[tabs.selectionView valueForKey:@"backgroundLayer"];
      CAShapeLayer *wave=[tabs.selectionView valueForKey:@"waveLayer"];
      CAGradientLayer *mask=[tabs.selectionView valueForKey:@"waveMask"];
      CGRect rect=CGPathGetBoundingBox(base.path);
      CGFloat opaqueEnd=CGRectGetMinY(mask.frame)+CGRectGetHeight(mask.frame)*[mask.locations[1] doubleValue];
      CGFloat transparentStart=CGRectGetMinY(mask.frame)+CGRectGetHeight(mask.frame)*[mask.locations[2] doubleValue];
      Check(!wave.hidden && opaqueEnd<CGRectGetMidY(rect) && transparentStart>CGRectGetMidY(rect),@"Halfway through three seconds, the tall gradient spans the tab center");
      Check(fabs(transparentStart-opaqueEnd-CGRectGetHeight(rect))<.01,@"Black-to-white uses the same full-height gradient");
      TLChromeTabView *tab=[tabs valueForKey:@"activeTabView"];
      NSTextField *overlay=[tab valueForKey:@"waveTitleLabel"];
      CAGradientLayer *textMask=[tab valueForKey:@"textWaveMask"];
      NSRect textFrame=[tabs.selectionView convertRect:textMask.frame fromView:overlay];
      Check(!overlay.hidden && NSEqualRects(textFrame,mask.frame) && [textMask.locations isEqual:mask.locations],@"Label reveal uses the same gradient position and feather as the background");
      NSColor *old=[NSColor colorWithCGColor:base.fillColor];
      NSColor *next=[NSColor colorWithCGColor:wave.fillColor];
      Check(old.redComponent>.9 && next.redComponent<.1,@"Wave preserves both original colors instead of morphing them");
    });
    Later(3.2,^{
      if(controlled){waveTime=3;[controlled advance];[selection setValue:[TLTransitionCoordinator new] forKey:@"colorTransition"];}
      NSColor *color=[self.browser.headerContentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      Check(color && (dark ? color.redComponent<.1 : color.redComponent>.9),@"Page inference updates to the scrolled content");
      TLWorkspaceTabsController *tabs=[self.owner valueForKey:@"workspaceTabsController"];
      TLChromeTabView *active=[tabs valueForKey:@"activeTabView"];
      NSTextField *label=[active valueForKey:@"titleLabel"];
      NSColor *text=[label.textColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      Check(dark ? text.redComponent>.9 : text.redComponent<.1,@"Tab label reaches the contrasting color after three seconds");
      NSView *title=[active valueForKey:@"titleClipView"];
      Check(title.layer.compositingFilter==nil,@"Label uses ordinary solid text rendering");
      if(step==0)[self checkSolidColor:1];else [self preparePixelColor];
    });
  }];
}
- (void)preparePixelColor {
  TLWebKitBrowserSession *session=[self.browser valueForKey:@"browserSession"];
  NSRect range=self.browser.tabColorSampleRect;
  Check(NSWidth(range)>0 && NSWidth(range)<.5,@"Top-edge inference is local to the tab's horizontal position");
  NSString *script=[NSString stringWithFormat:@"const edge=document.createElement('div');edge.style.cssText='position:fixed;top:0;height:16px;width:100%%;background:rgb(150,30,70)';const local=document.createElement('div');local.style.cssText='height:16px;position:absolute;background:linear-gradient(rgb(36,104,66),rgb(36,104,66));left:%f%%;width:%f%%';edge.append(local);document.body.append(edge);scrollBy(0,20);true",NSMinX(range)*100,NSWidth(range)*100];
  [session.webView evaluateJavaScript:script completionHandler:^(id value,NSError *error){Check(!error,@"Scroll a gradient into the sampled edge");[self checkPixelColor:0];}];
}
- (void)checkPixelColor:(NSUInteger)attempt {
  NSColor *color=[self.browser.headerContentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  BOOL matches=color && fabs(color.redComponent*255-36)<3 && fabs(color.greenComponent*255-104)<3 && fabs(color.blueComponent*255-66)<3;
  if(!matches && attempt<15){Later(.1,^{[self checkPixelColor:attempt+1];});return;}
  Check(matches,@"Scroll end refreshes complex page pixels beneath the tab promptly");
  Later(3.2,^{ [self checkThemes]; });
}
- (void)checkThemes {
  for(NSNumber *theme in @[@(TLThemePreferenceLight),@(TLThemePreferenceDark)]) {
    TLAppSettings *settings=[self.owner valueForKey:@"settings"];settings.theme=theme.integerValue;[self.owner applyTheme];
    TLChromeTabSelectionView *selection=[[self.owner valueForKey:@"workspaceTabsController"] selectionView];
    Check([selection.displayedBackgroundColor isEqual:self.browser.headerContentColor],@"Both themes preserve the inferred solid tab background");
  }
  [self.owner.window setContentSize:NSMakeSize(2600,1300)];
  TLWebKitBrowserSession *session=[self.browser valueForKey:@"browserSession"];
  NSURL *URL=[NSURL URLWithString:@"/large-canvas" relativeToURL:session.webView.URL];
  [TLWebKitBrowserController.sharedController navigateSession:session toURL:URL.absoluteURL];
  Later(1,^{[self checkLargeCanvas:0];});
}
- (void)checkLargeCanvas:(NSUInteger)attempt {
  TLWebKitBrowserSession *session=[self.browser valueForKey:@"browserSession"];
  NSColor *color=[self.browser.headerContentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  BOOL matches=color && fabs(color.redComponent*255-14)<3 && fabs(color.greenComponent*255-47)<3 && fabs(color.blueComponent*255-126)<3;
  if((!matches || session.webView.loading) && attempt<30){Later(.2,^{[self checkLargeCanvas:attempt+1];});return;}
  Check(matches,@"Large canvas initial load infers its blue edge without scrolling");
  [session.webView evaluateJavaScript:@"scrollY" completionHandler:^(id value,NSError *error){
    Check(!error && [value doubleValue]==0,@"Color inference did not require a scroll");
  TLWorkspaceTab *browserTab = [self.owner activeWorkspaceTab];
  [self.owner startNewChatWithModel:@"test" focus:NO];
  [self.owner splitTab:browserTab besideTab:[self.owner activeWorkspaceTab] onLeft:YES];
  TLWorkspaceTabsController *tabs = [self.owner valueForKey:@"workspaceTabsController"];
  Later(.2, ^{
    [tabs refreshContentColorsAnimated:NO];
    TLThemePalette *palette = [self.owner valueForKey:@"palette"];
    Check([tabs.selectionView.displayedBackgroundColor isEqual:palette.tabBackground], @"Split view uses the chat background even with a colored browser focused");
    [self.browser setValue:palette.controlFocus forKey:@"headerContentColor"];
    if (self.browser.headerColorChangedHandler) self.browser.headerColorChangedHandler();
    Check([tabs.selectionView.displayedBackgroundColor isEqual:palette.tabBackground] && ![[tabs.selectionView valueForKey:@"waveActive"] boolValue], @"Page color changes never recolor the split tab");
    [self.owner focusSplitPane:YES];
    [tabs refreshContentColorsAnimated:NO];
    Check([tabs.selectionView.displayedBackgroundColor isEqual:palette.tabBackground], @"Changing focused panes keeps the split background constant");
  Later([NSProcessInfo.processInfo.arguments containsObject:@"--inspect"] ? 25 : 0,^{
    NSLog(@"BrowserTabColorTests passed");[NSApp terminate:nil];
  });
  });
  }];
}
@end
int main(void) { @autoreleasepool {
  NSApplication *app=NSApplication.sharedApplication;
  TLTabColorTestDelegate *delegate=[TLTabColorTestDelegate new];app.delegate=delegate;[app run];
}return 0;}
