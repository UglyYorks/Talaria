// Actual desktop WebKit integration for document scrolling and native-footer exclusivity.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserTabController.h"
@interface TLBrowserTabController (DocumentFooterTests)
- (void)toggleBrowserHeightMode:(id)sender;
- (CGFloat)footerHeight;
- (void)configureDocumentFooter;
@end
@interface TLFooterTestApplication : NSApplication
@end
@implementation TLFooterTestApplication
- (void)sendEvent:(NSEvent *)event {
  // User trackpad input must not enter the foreground automation window. Programmatic
  // input goes directly to the web view; phase tests use the explicitly routed event.
  if(event.type==NSEventTypeScrollWheel) return;
  [super sendEvent:event];
}
@end
@interface TLFooterTestBrowser : TLWebKitBrowserController
@property(nonatomic,strong) NSDictionary *lastProbe;
@end
@implementation TLFooterTestBrowser
- (void)probeOverlayInSession:(TLWebKitBrowserSession *)session overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion {
  [super probeOverlayInSession:session overlayRect:rect viewportSize:viewport quick:quick completion:^(NSDictionary *result){self.lastProbe=result;completion(result);}];
}
@end
@interface TLFooterTestDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic,strong) TLFooterTestBrowser *browser;
@property(nonatomic,strong) TLBrowserTabController *tab;
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) NSMutableArray *results;
@property(nonatomic) double initialHeight, appVisibleAt;
@property(nonatomic) BOOL appReplacesRaisedFooter;
@property(nonatomic,strong) NSNumber *liveRaisedTotal;
@end
@implementation TLFooterTestDelegate
- (void)after:(double)seconds run:(dispatch_block_t)block { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block); }
- (TLWebKitBrowserSession *)session { return [self.tab valueForKey:@"browserSession"]; }
- (BOOL)raised { return [[self.tab valueForKey:@"browserUsesReducedHeight"] boolValue]; }
- (WKWebView *)webView { return self.session.webView; }
- (void)check:(BOOL)passed name:(NSString *)name { NSLog(@"%@: %@",passed ? @"PASS" : @"FAIL",name); [self.results addObject:@{@"name":name,@"passed":@(passed)}]; }
- (void)eval:(NSString *)code then:(void (^)(id))completion {
  [self.session.webView callAsyncJavaScript:code arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id value,NSError *error){
    if(error){[self check:NO name:[@"JavaScript fixture: " stringByAppendingString:error.localizedDescription]];[self finish];}
    else completion(value);
  }];
}
- (void)wheel:(double)delta {
  if (!NSApp.isActive) { [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES]; }
  TLTestScroll(self.session.webView, delta);
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  self.results=[NSMutableArray array];
  [[NSString stringWithFormat:@"%d",NSProcessInfo.processInfo.processIdentifier] writeToFile:[args[3] stringByAppendingString:@".pid"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.browser=[TLFooterTestBrowser new];
  self.window=[[NSWindow alloc] initWithContentRect:args.count>4 ? NSMakeRect(0,0,1460,1000) : NSMakeRect(0,0,1000,700) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];self.window.releasedWhenClosed=NO;
  // Keep renderer visibility stable while the test runner and editor update.
  self.window.level=NSFloatingWindowLevel;
  self.window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
  self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
  self.window.titlebarAppearsTransparent=YES;self.window.titleVisibility=NSWindowTitleHidden;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  self.tab=[[TLBrowserTabController alloc] initWithURL:[NSURL URLWithString:[args[1] stringByAppendingString:@"/document-footer"]] palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight] database:nil orchestrator:nil inputWidth:800 browserService:self.browser];
#pragma clang diagnostic pop
  __weak TLFooterTestDelegate * weakSelf=self;
  self.tab.metadataChangedHandler=^(NSString *title,NSURL *URL){
    if([title hasPrefix:@"viewport-app-visible:"])weakSelf.appVisibleAt=NSProcessInfo.processInfo.systemUptime;
  };
  NSView *content=self.window.contentView;[content addSubview:self.tab.view];
  [NSLayoutConstraint activateConstraints:@[[self.tab.view.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[self.tab.view.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[self.tab.view.topAnchor constraintEqualToAnchor:content.topAnchor],[self.tab.view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
  [self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];[content layoutSubtreeIfNeeded];[self.tab startInWindow:self.window];
  TLTestActivateWindow(self.window,^{[self waitForBridge:0 then:^{[self testDocument];}];});
  [self after:90 run:^{if(self.tab){[self check:NO name:@"Integration deadline"];[self finish];}}];
}

- (void)waitForBridge:(NSUInteger)attempt then:(dispatch_block_t)next {
  BOOL ready=[[[self.session valueForKey:@"pageBridge"] valueForKey:@"ready"] boolValue];
  if(!ready && attempt<70){[self after:0.1 run:^{[self waitForBridge:attempt+1 then:next];}];return;}
  [self check:ready name:@"Isolated document-footer bridge installed"];
  if(!ready){dispatch_async(dispatch_get_main_queue(),^{[self finish];});return;}
  id bridge=[self.session valueForKey:@"pageBridge"];
  NSLog(@"Footer view geometry: frame=%@ bounds=%@ visibleRect=%@",NSStringFromRect(self.session.webView.frame),NSStringFromRect(self.session.webView.bounds),NSStringFromRect(self.session.webView.visibleRect));
  NSLog(@"Footer placement: frame=%@ screen=%@ active=%d hidden=%d paused=%@ generation=%@",NSStringFromRect(self.window.frame),NSStringFromRect(self.window.screen.frame),NSApp.active,self.session.webView.hiddenOrHasHiddenAncestor,[self.session valueForKey:@"paused"],[self.session valueForKey:@"transitionGeneration"]);
  NSLog(@"Footer native state: visible=%d occlusion=%lu viewWindow=%@ cover=%@ frames=%@",self.window.visible,(unsigned long)self.window.occlusionState,self.session.webView.window,[self.session valueForKey:@"navigationCover"],[[bridge valueForKey:@"frames"] allKeys]);
  [self.session.webView evaluateJavaScript:@"({visibility:document.visibilityState,hidden:document.hidden})" completionHandler:^(id state,NSError *error){NSLog(@"Footer document state: %@ error=%@",state,error);}];
  [self after:0.6 run:next];
}
- (void)state:(void (^)(NSDictionary *))completion {
  [self eval:@"let f=document.querySelector('[data-talaria-document-footer]');return {height:innerHeight,scroll:scrollY,total:document.scrollingElement.scrollHeight,spacer:f?f.getBoundingClientRect().height:0,color:f?getComputedStyle(f).backgroundColor:'',resizes:window.resizes||0}" then:completion];
}
- (void)testDocument {
  [self state:^(NSDictionary *page){
    self.initialHeight=[page[@"height"] doubleValue];
    double size=[self.tab footerHeight];
    [self check:fabs([page[@"spacer"] doubleValue]-size)<1 && fabs([page[@"total"] doubleValue]-3000-size)<1 name:@"Document scrollbar includes exactly one native-footer-height spacer"];
    [self eval:@"window.resizes=0;addEventListener('resize',()=>resizes++);scrollTo(0,document.scrollingElement.scrollHeight);return true" then:^(id value){
      [self after:0.2 run:^{[self state:^(NSDictionary *bottom){
        [self check:!self.raised && fabs([bottom[@"height"] doubleValue]-self.initialHeight)<1 && [bottom[@"resizes"] intValue]==0 name:@"Reaching document end exposes spacer without resizing or opening native footer"];
        [self check:fabs([bottom[@"scroll"] doubleValue]-([bottom[@"total"] doubleValue]-self.initialHeight))<1 name:@"Native scroll position reaches the entire extension"];
        double scroll=[bottom[@"scroll"] doubleValue];
        [self wheel:-40];[self after:0.3 run:^{[self state:^(NSDictionary *up){
          [self check:[up[@"scroll"] doubleValue]<scroll && !self.raised && [up[@"resizes"] intValue]==0 name:@"Upward wheel input scrolls natively through the spacer without viewport changes"];
          [self testViewportAnimation:0];
        }];}];
      }];}];
    }];
  }];
}
- (void)testViewportAnimation:(NSUInteger)cycle {
  if(cycle==2){[self eval:@"document.querySelector('#animationProbe').remove();return true" then:^(id value){[self testToggle:0];}];return;}
  [self eval:@"if(!document.querySelector('#animationProbe'))document.body.insertAdjacentHTML('beforeend','<div id=animationProbe style=\"position:fixed;left:0;bottom:0;width:10px;height:12px;pointer-events:none\"><span>Layout</span></div>');window.animationSamples=[];window.recordAnimation=true;const sample=()=>{let p=document.querySelector('#animationProbe');animationSamples.push({height:innerHeight,bottom:p.getBoundingClientRect().bottom,glyph:p.firstElementChild.getBoundingClientRect().height});if(recordAnimation)requestAnimationFrame(sample)};sample();return true" then:^(id value){
    [self.tab toggleBrowserHeightMode:nil];
    [self after:0.5 run:^{[self eval:@"recordAnimation=false;return animationSamples" then:^(NSArray *samples){
      NSMutableSet *heights=[NSMutableSet set];BOOL aligned=YES,monotonic=YES,unscaled=YES;
      double previous=[samples.firstObject[@"height"] doubleValue],glyph=[samples.firstObject[@"glyph"] doubleValue];
      for(NSDictionary *sample in samples){
        double height=[sample[@"height"] doubleValue];[heights addObject:sample[@"height"]];
        aligned &= fabs([sample[@"bottom"] doubleValue]-height)<1;
        unscaled &= fabs([sample[@"glyph"] doubleValue]-glyph)<0.1;
        monotonic &= cycle==0 ? height<=previous : height>=previous;previous=height;
      }
      BOOL motion=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
      [self check:motion || heights.count>=3 name:cycle==0 ? @"Opening animates real WebKit viewport sizes" : @"Closing animates real WebKit viewport sizes"];
      [self check:aligned && monotonic && unscaled name:@"Fixed bottom content follows every viewport layout without squishing or overshoot"];
      NSView *host=[self.tab valueForKey:@"browserHostView"];
      NSView *clip=[host valueForKey:@"contentView"];
      [self check:cycle==0 ? (clip.layer.cornerRadius>0 && host.layer.shadowOpacity>0 && clip.layer.masksToBounds && !host.layer.masksToBounds) : (clip.layer.cornerRadius==0 && host.layer.shadowOpacity==0)
        name:cycle==0 ? @"Raised viewport clips rounded corners while its shadow remains outside" : @"Lowered viewport removes corner and shadow decoration"];
      if(cycle==0) {
        NSBitmapImageRep *image=[self.window.contentView bitmapImageRepForCachingDisplayInRect:self.window.contentView.bounds];
        [self.window.contentView cacheDisplayInRect:self.window.contentView.bounds toBitmapImageRep:image];
        [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"/tmp/talaria-rounded-viewport.png" atomically:YES];
      }

      [self testViewportAnimation:cycle+1];
    }];}];
  }];
}
// Verify WebKit's actual rendered surface as well as its native view geometry.
- (void)checkCompositor:(NSString *)name { [self checkCompositor:name then:^{}]; }
- (void)checkCompositor:(NSString *)name then:(dispatch_block_t)completion {
  WKWebView *view=self.session.webView;
  NSSize expected=view.bounds.size;
  CGFloat backingScale=view.window.backingScaleFactor;
  CALayer *surface=view.layer;
  double error=surface ? MAX(fabs(NSWidth(surface.bounds)-expected.width),fabs(NSHeight(surface.bounds)-expected.height)) : 0;
  BOOL aligned=NSEqualRects(view.frame,view.superview.bounds);
  WKSnapshotConfiguration *configuration=[WKSnapshotConfiguration new];configuration.afterScreenUpdates=NO;
  [view takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image,NSError *snapshotError){
    NSBitmapImageRep *bitmap=image ? [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation] : nil;
    BOOL rendered=bitmap && fabs(image.size.width-expected.width)<1 && fabs(image.size.height-expected.height)<1 &&
      fabs(bitmap.pixelsWide-expected.width*backingScale)<2 && fabs(bitmap.pixelsHigh-expected.height*backingScale)<2;
    [self.results addObject:@{@"name":name,@"passed":@(rendered && aligned && error<1),@"surfaces":@(bitmap ? 1 : 0),@"maxError":@(error),
      @"viewport":NSStringFromSize(expected),@"imageSize":NSStringFromSize(image.size),@"pixels":@[@(bitmap.pixelsWide),@(bitmap.pixelsHigh)],@"error":snapshotError.localizedDescription ?: @""}];
    completion();
  }];
}
- (void)testToggle:(NSUInteger)cycle {
  if(cycle==24){[self testGrowth];return;}
  [self.tab toggleBrowserHeightMode:nil];
  if(cycle%3==0){[self after:0.03 run:^{[self.tab toggleBrowserHeightMode:nil];}];[self after:0.06 run:^{[self.tab toggleBrowserHeightMode:nil];}];}
  [self after:0.65 run:^{[self state:^(NSDictionary *page){
    double size=[self.tab footerHeight];
    double expected=self.initialHeight-(self.raised?size:0);
    BOOL good=fabs([page[@"height"] doubleValue]-expected)<1 &&
      fabs([page[@"total"] doubleValue]-(3000+(self.raised?0:size)))<1 &&
      fabs([page[@"spacer"] doubleValue]-(self.raised?0:size))<1;
    [self check:good name:[NSString stringWithFormat:@"Toggle %lu: exclusive equal-height space, no accumulated blank area",(unsigned long)cycle]];
    [self checkCompositor:[NSString stringWithFormat:@"Toggle %lu compositor stays aligned",(unsigned long)cycle] then:^{ [self testToggle:cycle+1]; }];
  }];}];
}
- (void)testGrowth {
  [self eval:@"document.body.style.height='3500px';return true" then:^(id value){
    [self after:0.35 run:^{[self state:^(NSDictionary *page){
      [self check:fabs([page[@"total"] doubleValue]-3500-[self.tab footerHeight])<1 name:@"Document growth moves the spacer without polling or cumulative padding"];
      [self eval:@"document.body.style.height='3000px';document.documentElement.style.background='rgb(40,50,60)';document.body.style.background='rgb(40,50,60)';scrollTo(0,document.scrollingElement.scrollHeight);return true" then:^(id result){
        [self after:0.8 run:^{[self state:^(NSDictionary *colored){
          [self check:[colored[@"color"] isEqual:@"rgb(40, 50, 60)"] name:@"Spacer matches the content above it instead of sampling its own fill"];
          [self testPreparedExtension];
        }];}];
      }];
    }];}];
  }];
}
- (void)testPreparedExtension {
  [self eval:@"document.body.innerHTML='<main style=\"height:2800px;background:rgb(240,20,30)\"></main><footer style=\"height:200px;background:rgb(20,40,60)\"></footer>';scrollTo(0,0);return true" then:^(id value){
    [self after:0.5 run:^{[self state:^(NSDictionary *top){
      NSColor *native=[[self.tab valueForKey:@"footerContentColor"] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      [self check:[top[@"color"] isEqual:@"rgb(20, 40, 60)"] && fabs(native.redComponent*255-240)<3 && fabs(native.greenComponent*255-20)<3 name:@"Offscreen extension uses document bottom while native footer samples a different visible edge"];
      [self eval:@"scrollTo(0,document.scrollingElement.scrollHeight);let f=document.querySelector('[data-talaria-document-footer]');return {color:getComputedStyle(f).backgroundColor,animations:f.getAnimations().length}" then:^(NSDictionary *first){
        [self check:[first[@"color"] isEqual:@"rgb(20, 40, 60)"] && [first[@"animations"] intValue]==0 name:@"Fast jump exposes the prepared extension color immediately with no correction fade"];
        [self eval:@"document.body.innerHTML='';return true" then:^(id cleared){[self testPixelColor];}];
      }];
    }];}];
  }];
}
- (void)testPixelColor {
  [self.tab setValue:@1e100 forKey:@"footerCaptureNext"];
  [self eval:@"document.body.style.background='linear-gradient(rgb(200,30,40),rgb(10,40,90) 90%)';return true" then:^(id value){
    [self after:0.4 run:^{
      NSView *root=self.session.webView;
      NSMutableArray<NSView *> *views=[NSMutableArray arrayWithObject:root];
      for(NSUInteger i=0;i<views.count;i++)[views addObjectsFromArray:views[i].subviews];
      NSMutableArray *flags=[NSMutableArray array];
      for(NSView *view in views){[flags addObject:@(view.postsFrameChangedNotifications)];view.postsFrameChangedNotifications=YES;}
      __block NSUInteger changes=0;
      id observer=[NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note){if([views containsObject:note.object])changes++;}];
      [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *result){
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        for(NSUInteger i=0;i<views.count;i++)views[i].postsFrameChangedNotifications=[flags[i] boolValue];
        NSArray *rgb=result[@"rgb"];
        // Color-managed screenshot conversion may round a channel by 1–2 levels.
        BOOL matches=rgb.count==3 && fabs([rgb[0] doubleValue]-10)<=3 && fabs([rgb[1] doubleValue]-40)<=3 && fabs([rgb[2] doubleValue]-90)<=3;
        [self check:matches && [result[@"mode"] isEqual:@"pixels"]
          name:@"Gradient readback crops above the spacer instead of sampling the extension"];
        [self.results addObject:@{@"name":@"Rendered color diagnostics",@"passed":@YES,@"sample":result ?: @{}}];
        [self check:changes==0 name:@"Content color capture never resizes the live WebKit views"];
        [self testBanner];
      }];
    }];
  }];
}
- (void)testCanvasExtension {
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/canvas-extension"]]];
  [self after:0.5 run:^{[self waitForBridge:0 then:^{
    [self.tab setValue:@1e100 forKey:@"footerCaptureNext"];
    [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *offscreen){
      [self check:[offscreen[@"busy"] boolValue] && !offscreen[@"captureMS"] name:@"Offscreen canvas does not read unrelated viewport pixels"];
      dispatch_async(dispatch_get_main_queue(),^{[self eval:@"scrollTo(0,document.scrollingElement.scrollHeight);return canvasReady" then:^(id ready){
        [self check:[ready boolValue] name:@"WebGL backdrop renders with a non-preserved drawing buffer"];
        [self after:0.4 run:^{
          NSView *root=self.session.webView;
          NSMutableArray<NSView *> *views=[NSMutableArray arrayWithObject:root];
          for(NSUInteger i=0;i<views.count;i++)[views addObjectsFromArray:views[i].subviews];
          NSMutableArray *flags=[NSMutableArray array];
          for(NSView *view in views){[flags addObject:@(view.postsFrameChangedNotifications)];view.postsFrameChangedNotifications=YES;}
          __block NSUInteger changes=0;
          id observer=[NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note){if([views containsObject:note.object])changes++;}];
          [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *sample){
            [NSNotificationCenter.defaultCenter removeObserver:observer];
            for(NSUInteger i=0;i<views.count;i++)views[i].postsFrameChangedNotifications=[flags[i] boolValue];
            [self check:[sample[@"applied"] boolValue] && !self.raised name:@"Native screenshot supplies the canvas extension without opening native footer"];
            [self check:changes==0 name:@"Canvas capture never resizes WebKit views or introduces viewport blink"];
            [self.results addObject:@{@"name":@"Canvas strip capture diagnostics",@"passed":@YES,@"sample":sample ?: @{}}];
            dispatch_async(dispatch_get_main_queue(),^{[self eval:@"let n=document.querySelector('[data-talaria-document-footer]'),s=getComputedStyle(n).backgroundImage,c=[...s.matchAll(/rgb\\((\\d+), (\\d+), (\\d+)\\)/g)].map(m=>m.slice(1).map(Number));return {colors:c,height:n.getBoundingClientRect().height,total:document.scrollingElement.scrollHeight}" then:^(NSDictionary *page){
              NSArray *colors=page[@"colors"];
              [self check:colors.count==32 && [colors.firstObject[0] intValue]>220 && [colors.lastObject[2] intValue]>210 name:@"Canvas extension retains different left and right edge colors"];
              [self check:fabs([page[@"height"] doubleValue]-[self.tab footerHeight])<1 && fabs([page[@"total"] doubleValue]-1900-[self.tab footerHeight])<1 name:@"Gradient fill does not change document extension geometry"];
              [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *cached){
                [self check:[cached[@"busy"] boolValue] && !cached[@"captureMS"] name:@"Unchanged canvas strip needs no further capture"];
                dispatch_async(dispatch_get_main_queue(),^{[self testEdgeColors];});
              }];
            }];});
          }];
        }];
      }];});
    }];
  }];}];
}
- (void)testBanner {
  // A new document clears manual override, then a real fixed banner takes over.
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/document-footer?banner-test"]]];
  [self after:0.5 run:^{[self waitForBridge:0 then:^{
    [self eval:@"document.body.insertAdjacentHTML('beforeend','<div id=consent style=\"position:fixed;bottom:12px;left:0;right:0;height:90px;background:rgb(20,10,180)\">Cookies</div>');return true" then:^(id value){
      [self after:1.2 run:^{[self state:^(NSDictionary *page){
        [self check:self.raised && [page[@"spacer"] doubleValue]==0 && fabs([page[@"height"] doubleValue]-(self.initialHeight-[self.tab footerHeight]))<1 name:@"Fixed banner opens native footer and removes document spacer"];
        NSColor *blue=[[self.tab valueForKey:@"footerContentColor"] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        [self check:fabs(blue.redComponent*255-20)<3 && fabs(blue.blueComponent*255-180)<3 name:@"Native footer continues the blue banner despite a white page gap"];
        [self eval:@"document.querySelector('#consent').remove();return true" then:^(id removed){
          [self after:1.5 run:^{[self state:^(NSDictionary *clear){
            [self check:!self.raised && fabs([clear[@"spacer"] doubleValue]-[self.tab footerHeight])<1 name:@"Banner dismissal restores only the document spacer"];
            dispatch_async(dispatch_get_main_queue(),^{[self testFramedBanner];});
          }];}];
        }];
      }];}];
    }];
  }];}];
}
- (void)testFramedBanner {
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/banner-color-frame"]]];
  [self after:2 run:^{
    NSColor *color=[[self.tab valueForKey:@"footerContentColor"] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    [self check:self.raised && fabs(color.redComponent*255-20)<3 && fabs(color.blueComponent*255-180)<3 name:@"Cross-origin closed-shadow banner supplies its blue background"];
    [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/banner-gradient-frame"]]];
    [self after:2.5 run:^{
      NSColor *gradient=[[self.tab valueForKey:@"footerContentColor"] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      [self check:self.raised && fabs(gradient.redComponent*255-30)<3 && fabs(gradient.greenComponent*255-80)<3 && fabs(gradient.blueComponent*255-140)<3 name:@"Complex framed banner captures inside its edge instead of the white gap"];
      [self testViewportApp:0];
    }];
  }];
}
- (void)testViewportApp:(NSUInteger)index {
  if(index==2){[self testLayoutApp];return;}
  self.appVisibleAt=0;self.browser.lastProbe=nil;self.appReplacesRaisedFooter=self.raised;
  NSString *path=index==0 ? @"/viewport-app" : @"/flutter-app";
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:path]]];
  [self awaitViewportApp:index attempt:0];
}
- (void)awaitViewportApp:(NSUInteger)index attempt:(NSUInteger)attempt {
  BOOL detected=self.appVisibleAt>0 && self.raised && [self.browser.lastProbe[@"reason"] isEqual:@"viewport-app"];
  if(!detected && attempt<60){[self after:0.05 run:^{[self awaitViewportApp:index attempt:attempt+1];}];return;}
  double latency=(NSProcessInfo.processInfo.systemUptime-self.appVisibleAt)*1000;
  // Navigation from a raised banner first completes the existing close/settle.
  double budget=self.appReplacesRaisedFooter ? 1000 : 600;
  [self.results addObject:@{@"name":index==0 ? @"Map application automatically raises native footer" : @"Flutter application automatically raises native footer",@"passed":@(detected && latency<budget),@"latencyMS":@(latency),@"probe":self.browser.lastProbe ?: @{}}];
  if(!detected){[self testViewportApp:index+1];return;}
  [self after:0.4 run:^{[self state:^(NSDictionary *page){
    [self check:[page[@"spacer"] doubleValue]==0 && fabs([page[@"height"] doubleValue]-(self.initialHeight-[self.tab footerHeight]))<1 name:@"Canvas application uses native footer without document spacer"];
    [self checkCompositor:@"Application opening compositor stays aligned"];
    [self eval:@"document.querySelector('#app').insertAdjacentHTML('beforeend','<button style=\"position:absolute;inset:0;width:100%;height:100%\">Controls</button>');return true" then:^(id result){
      [self after:0.8 run:^{
        [self check:self.raised name:@"Transient canvas controls preserve raised footer"];
        [self eval:@"document.querySelector('#map').remove();return true" then:^(id removed){
          [self after:1.5 run:^{
            [self check:!self.raised name:@"Removing canvas application restores overlay"];
            [self testViewportApp:index+1];
          }];
        }];
      }];
    }];
  }];}];
}
- (void)testLayoutApp {
  self.appVisibleAt=0;self.browser.lastProbe=nil;
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/layout-app"]]];
  [self awaitLayoutApp:0];
}
- (void)awaitLayoutApp:(NSUInteger)attempt {
  BOOL detected=self.appVisibleAt>0 && self.raised && [self.browser.lastProbe[@"reason"] isEqual:@"viewport-layout"];
  if(!detected && attempt<60){[self after:0.05 run:^{[self awaitLayoutApp:attempt+1];}];return;}
  double latency=(NSProcessInfo.processInfo.systemUptime-self.appVisibleAt)*1000;
  [self.results addObject:@{@"name":@"Flex application automatically raises native footer",@"passed":@(detected && latency<1000),@"latencyMS":@(latency),@"probe":self.browser.lastProbe ?: @{}}];
  [self after:0.8 run:^{[self state:^(NSDictionary *page){
    [self check:self.raised && [page[@"spacer"] doubleValue]==0 && fabs([page[@"height"] doubleValue]-(self.initialHeight-[self.tab footerHeight]))<1 name:@"Flex application stays docked after viewport resize without a document spacer"];
    [self checkCompositor:@"Flex application opening compositor stays aligned"];
    [self eval:@"document.querySelector('section').scrollTop=600;return true" then:^(id result){
      [self after:0.5 run:^{
        [self check:self.raised name:@"Scrolling conversation leaves stationary bottom text protected"];
        [self eval:@"document.querySelector('#bottom').remove();return true" then:^(id removed){
          [self after:1.5 run:^{
            [self check:!self.raised name:@"Removing flex bottom text restores overlay"];
            [self testCanvasExtension];
          }];
        }];
      }];
    }];
  }];}];
}
- (void)testEdgeColors {
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/edge-colors"]]];
  [self after:0.5 run:^{[self waitForBridge:0 then:^{
    [self.tab setValue:@1e100 forKey:@"footerCaptureNext"];
    [self.tab setValue:@1e100 forKey:@"footerColorNext"];
    [self eval:@"document.body.style.background='linear-gradient(rgb(180,30,20) 21%,rgb(20,30,150) 79%)';return true" then:^(id changed){
    [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *sample){
      NSArray *top=sample[@"top"][@"rgb"], *bottom=sample[@"rgb"];
      [self check:top.count==3 && bottom.count==3 && [top[0] intValue]==180 && [top[2] intValue]==20 && [bottom[0] intValue]==20 && [bottom[2] intValue]==150 name:@"One viewport sample preserves distinct top and bottom colors"];
      [self check:[sample[@"mode"] isEqual:@"pixels"] && [sample[@"top"][@"mode"] isEqual:@"pixels"] && [sample[@"captureMS"] doubleValue]>0 name:@"Complex top and bottom edges share one screenshot capture"];
      [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *cached){
        [self check:!cached[@"captureMS"] && [cached[@"top"][@"mode"] isEqual:@"cachedPixels"] && [cached[@"mode"] isEqual:@"cachedPixels"] name:@"Both unchanged edges reuse their pixel caches"];
        [self.tab setValue:@0 forKey:@"footerColorNext"];
        [self after:0.5 run:^{
          NSColor *header=[self.tab.headerContentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
          [self check:header && fabs(header.redComponent*255-180)<2 name:@"Browser tab receives the visible top color through the shared polling path"];
          [self testHighResolutionEdgeColors];
        }];
      }];
    }];
    }];
  }];}];
}
- (void)testHighResolutionEdgeColors {
  NSRect previousFrame=self.window.frame;
  [self.window setContentSize:NSMakeSize(3008,1698)];
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:@"/x-like-edge-colors"]]];
  [self after:0.5 run:^{[self waitForBridge:0 then:^{
    // Use real backing geometry; WebKit has no public device-scale override.
    // Enlarge the fixture on 1x displays to retain the >16 Mi pixel assertion.
    CGFloat backingScale = self.window.backingScaleFactor;
    CGFloat factor = 2.0 / MAX(1, backingScale);
    [self.window setContentSize:NSMakeSize(3008 * factor, 1698 * factor)];
    [self after:0.3 run:^{
      [self.tab setValue:nil forKey:@"headerContentColor"];
      [self.tab setValue:@1e100 forKey:@"footerColorNext"];
      [self.tab setValue:@1e100 forKey:@"footerCaptureNext"];
      [self sampleHighResolutionEdge:0 previousFrame:previousFrame];
    }];
  }];}];
}
- (void)sampleHighResolutionEdge:(NSUInteger)attempt previousFrame:(NSRect)previousFrame {
  [self.browser sampleFooterColorInSession:self.session allowCapture:YES completion:^(NSDictionary *sample){
    NSDictionary *top=sample[@"top"];
    if(!top[@"rgb"] && attempt<7){[self after:0.25 run:^{[self sampleHighResolutionEdge:attempt+1 previousFrame:previousFrame];}];return;}
    NSArray *view=top[@"viewState"];
    double scale=[top[@"deviceScale"] doubleValue];
    double pixels=view.count==4 ? [view[0] doubleValue]*[view[1] doubleValue]*scale*scale : 0;
    [self check:pixels>16*1024*1024 && pixels<=32*1024*1024 name:@"X-like fixture exercises a 6K viewport above the former capture limit"];
    [self check:[top[@"rgb"] isEqual:@[@0,@0,@0]] && [top[@"mode"] isEqual:@"pixels"] && [sample[@"captureMS"] doubleValue]>0 name:@"Transparent relative wrappers receive their rendered black top color at 6K"];
    [self.results addObject:@{@"name":@"6K edge capture diagnostics",@"passed":@YES,@"sample":sample ?: @{}}];
    [self.tab setValue:@0 forKey:@"footerColorNext"];
    [self.tab setValue:@0 forKey:@"footerCaptureNext"];
    [self awaitHighResolutionHeader:0 previousFrame:previousFrame];
  }];
}
- (void)awaitHighResolutionHeader:(NSUInteger)attempt previousFrame:(NSRect)previousFrame {
  NSColor *header=[self.tab.headerContentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  BOOL black=header && header.redComponent==0 && header.greenComponent==0 && header.blueComponent==0;
  if(!black && attempt<30){[self after:0.1 run:^{[self awaitHighResolutionHeader:attempt+1 previousFrame:previousFrame];}];return;}
  [self check:black name:@"A cleared browser tab acquires the black X-like page color at 6K"];
  [self.window setFrame:previousFrame display:YES];
  [self after:0.3 run:^{[self testLivePage];}];
}
- (void)testLivePage {
  NSArray *args=NSProcessInfo.processInfo.arguments;
  if(args.count<=4){[self finish];return;}
  [self.window setContentSize:NSMakeSize(1336,1320.75)];
  // Fractional workspace geometry exercises AppKit/WebKit rounding as well as
  // the integer-sized standalone fixture.
  for(NSLayoutConstraint *constraint in self.tab.view.superview.constraints){
    if(constraint.firstItem==self.tab.view && constraint.firstAttribute==NSLayoutAttributeTop)constraint.constant=37.5;
    if(constraint.firstItem==self.tab.view && constraint.firstAttribute==NSLayoutAttributeBottom)constraint.constant=-5.25;
  }
  [self.tab.view.superview layoutSubtreeIfNeeded];
  [self.browser navigateSession:self.session toURL:[NSURL URLWithString:args[4]]];
  [self after:2 run:^{[self waitForBridge:0 then:^{
    [self.tab setValue:@0 forKey:@"footerCaptureNext"];
    [self eval:@"scrollTo(0,Math.min(250,document.scrollingElement.scrollHeight));return {url:location.href,mode:document.compatMode}" then:^(NSDictionary *info){
      [self check:[info[@"url"] isEqual:args[4]] name:@"Requested live page loaded"];
      [self.browser configureDocumentFooter:@{@"enabled":@NO} inSession:self.session completion:^(BOOL applied){
        [self state:^(NSDictionary *base){
          [self.tab configureDocumentFooter];
          [self after:0.3 run:^{[self state:^(NSDictionary *shown){
            [self check:applied && fabs([shown[@"total"] doubleValue]-[base[@"total"] doubleValue]-[self.tab footerHeight])<1 && [shown[@"spacer"] doubleValue]>0 name:@"Live page gets exactly one footer-height document extension"];
            [self liveCycle:0 baseline:[base[@"total"] doubleValue]];
          }];}];
        }];
      }];
    }];
  }];}];
}
- (void)liveCycle:(NSUInteger)cycle baseline:(double)baseline {
  if(cycle==24){dispatch_async(dispatch_get_main_queue(),^{[self finish];});return;}
  [self.tab setValue:@0 forKey:@"footerCaptureNext"];
  [self.tab setValue:@0 forKey:@"footerColorNext"];
  [self.tab toggleBrowserHeightMode:nil];
  [self after:0.6 run:^{[self state:^(NSDictionary *page){
    double spacer=self.raised?0:[self.tab footerHeight];
    if(self.raised && !self.liveRaisedTotal)self.liveRaisedTotal=page[@"total"];
    double expected=self.raised ? self.liveRaisedTotal.doubleValue : baseline+spacer;
    [self check:fabs([page[@"total"] doubleValue]-expected)<1 && fabs([page[@"spacer"] doubleValue]-spacer)<1 name:[NSString stringWithFormat:@"Live toggle %lu preserves exclusive spaces and original document height",(unsigned long)cycle]];
    [self checkCompositor:[NSString stringWithFormat:@"Live toggle %lu compositor stays aligned",(unsigned long)cycle]];
    [self liveCycle:cycle+1 baseline:baseline];
  }];}];
}
- (void)finish {
  [self.tab close];self.tab=nil;
  NSData *data=[NSJSONSerialization dataWithJSONObject:self.results options:NSJSONWritingPrettyPrinted error:nil];[data writeToFile:NSProcessInfo.processInfo.arguments[3] atomically:YES];[NSApp terminate:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app { return [self.browser prepareForApplicationTermination]?NSTerminateNow:NSTerminateLater; }
@end
int main(int argc,char **argv){@autoreleasepool{if(argc>2)setenv("TL_WEBKIT_PROFILE_DIR",argv[2],1);TLFooterTestApplication *app=[TLFooterTestApplication sharedApplication];TLFooterTestDelegate *delegate=[TLFooterTestDelegate new];app.delegate=delegate;[app run];}return 0;}
