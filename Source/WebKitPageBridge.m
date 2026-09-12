#import "WebKitPageBridge.h"
#import "BrowserPageContext.h"
#import "TLBrowserContentColor.h"
#import <math.h>

static NSString *TLPageResource(NSString *name) {
  NSURL *URL = [NSBundle.mainBundle URLForResource:name withExtension:@"js"];
  return URL ? [NSString stringWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:nil] : nil;
}
static NSString *TLPageJSON(id value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value ?: NSNull.null options:NSJSONWritingFragmentsAllowed error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"null";
}
static NSError *TLPageError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.PageReader" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}

@interface TLWebKitPageMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) TLWebKitPageBridge *owner;
@end
@interface TLWebKitPageBridge ()
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, readwrite) WKContentWorld *contentWorld;
@property(nonatomic, readwrite) BOOL ready;
@property(nonatomic) NSUInteger generation, findGeneration, overlayCursor;
@property(nonatomic) BOOL scriptsInstalled, stopped;
@property(nonatomic, copy) NSString *handlerName, *installationSource, *overlaySource, *footerSource, *colorSource, *findQuery;
@property(nonatomic) NSInteger activeMatch;
@property(nonatomic, strong) NSMutableDictionary<NSString *, WKFrameInfo *> *frames;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *pending;
@property(nonatomic, copy) NSDictionary *configuration, *pixelSample, *overlayHint;
@property(nonatomic, copy) NSString *footerDocumentIdentifier;
- (void)receiveMessage:(WKScriptMessage *)message;
- (void)evaluateBody:(NSString *)body arguments:(NSDictionary *)arguments frame:(WKFrameInfo *)frame completion:(void (^)(id, NSError *))completion;
@end
@implementation TLWebKitPageMessageHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.owner receiveMessage:message];
}
@end

@interface TLWebKitOverlayRequest : NSObject
@property(nonatomic, weak) TLWebKitPageBridge *bridge;
@property(nonatomic, copy) NSDictionary *scan;
@property(nonatomic, copy) NSArray *points;
@property(nonatomic, copy) NSDictionary *rootPoint;
@property(nonatomic) NSUInteger pointIndex, hitTests;
@property(nonatomic) double cpuMS, maxSliceMS;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
- (void)start;
@end
@implementation TLWebKitOverlayRequest
- (void)start { self.cpuMS = [self.scan[@"cpuMS"] doubleValue]; self.maxSliceMS = [self.scan[@"maxSliceMS"] doubleValue]; [self nextPoint]; }
- (void)finish:(NSDictionary *)value frameID:(NSString *)frameID scale:(double)scale coverage:(double)coverage {
  if (!self.completion) return;
  NSMutableDictionary *result = [@{@"obstructed":value[@"obstructed"] ?: NSNull.null,
    @"cpuMS":@(self.cpuMS), @"costMS":@(self.cpuMS), @"maxSliceMS":@(self.maxSliceMS),
    @"hitTests":@(self.hitTests), @"scanComplete":@([self.scan[@"obstructed"] isKindOfClass:NSNumber.class]),
    @"samples":self.scan[@"samples"] ?: @0, @"cursor":self.scan[@"cursor"] ?: @0} mutableCopy];
  if ([value[@"obstructed"] isEqual:@YES]) {
    NSDictionary *point = self.rootPoint ?: self.scan[@"point"];
    double height = [self.scan[@"viewState"][1] doubleValue];
    if (point) result[@"hint"] = @{@"x":point[@"x"], @"bottom":@(height - [point[@"y"] doubleValue])};
    if (value[@"reason"]) result[@"reason"] = value[@"reason"];
    NSDictionary *sourceBanner = value[@"banner"];
    if ([sourceBanner isKindOfClass:NSDictionary.class] && [sourceBanner[@"coverage"] doubleValue]*coverage >= 0.65 && point) {
      NSMutableDictionary *banner = [sourceBanner mutableCopy];
      banner[@"bottom"] = @(MAX(1, height - [point[@"y"] doubleValue] - [banner[@"edgeDelta"] doubleValue]*scale));
      banner[@"id"] = [NSString stringWithFormat:@"%@:%@",frameID ?: @"main",banner[@"id"]];
      [banner removeObjectForKey:@"edgeDelta"]; [banner removeObjectForKey:@"coverage"];
      result[@"banner"] = banner;
    }
  }
  void (^callback)(NSDictionary *) = self.completion; self.completion = nil;
  // Snapshot/readback and asynchronous frame inspection must not apply geometry
  // from an earlier scroll position or viewport size.
  [self.bridge evaluateBody:@"return JSON.stringify([innerWidth,innerHeight,scrollX,scrollY]) === JSON.stringify(state);"
    arguments:@{@"state":self.scan[@"viewState"] ?: @[]} frame:nil completion:^(id valid, NSError *error) {
      if (error || ![valid isEqual:@YES]) result[@"obstructed"] = NSNull.null;
      callback(result);
    }];
}
- (void)nextPoint {
  if ([self.scan[@"obstructed"] isEqual:@YES]) { [self finish:self.scan frameID:nil scale:1 coverage:1]; return; }
  if (![self.scan[@"obstructed"] isEqual:@NO]) { [self finish:@{} frameID:nil scale:1 coverage:1]; return; }
  if (self.pointIndex >= self.points.count) { [self finish:@{@"obstructed":@NO} frameID:nil scale:1 coverage:1]; return; }
  self.rootPoint = self.points[self.pointIndex++];
  [self inspectPoint:self.rootPoint frameID:nil depth:0 scale:1 coverage:1];
}
- (void)inspectPoint:(NSDictionary *)point frameID:(NSString *)frameID depth:(NSUInteger)depth scale:(double)scale coverage:(double)coverage {
  TLWebKitPageBridge *bridge = self.bridge;
  WKFrameInfo *frame = frameID ? bridge.frames[frameID] : nil;
  if (!bridge || (frameID && !frame) || depth > 6) { [self finish:@{} frameID:frameID scale:scale coverage:coverage]; return; }
  self.hitTests++;
  NSDictionary *config = @{@"x":point[@"x"] ?: @0, @"y":point[@"y"] ?: @0,
    @"allowFrame":@(depth > 0), @"viewportPinned":point[@"viewportPinned"] ?: @NO};
  [bridge evaluateBody:@"return await globalThis.__talariaWebKitBridge?.candidate(config);" arguments:@{@"config":config} frame:frame completion:^(id value, NSError *error) {
    NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : @{};
    self.cpuMS += [result[@"cpuMS"] doubleValue]; self.maxSliceMS = MAX(self.maxSliceMS,[result[@"maxSliceMS"] doubleValue]);
    if (error || !result.count) { [self finish:@{} frameID:frameID scale:scale coverage:coverage]; return; }
    if ([result[@"obstructed"] isEqual:@YES]) { [self finish:result frameID:frameID scale:scale coverage:coverage]; return; }
    NSDictionary *child = result[@"frame"];
    if ([child isKindOfClass:NSDictionary.class]) {
      NSString *childID = [child[@"id"] isKindOfClass:NSString.class] ? child[@"id"] : nil;
      if (!childID) { [self finish:@{} frameID:frameID scale:scale coverage:coverage]; return; }
      [self inspectPoint:child frameID:childID depth:depth+1 scale:scale*[child[@"scaleY"] doubleValue] coverage:coverage*[child[@"coverage"] doubleValue]];
      return;
    }
    if (![result[@"obstructed"] isEqual:@NO]) { [self finish:@{} frameID:frameID scale:scale coverage:coverage]; return; }
    [bridge evaluateBody:@"return await globalThis.__talariaWebKitBridge?.pointerCandidate(config);" arguments:@{@"config":config} frame:frame completion:^(id fallback, NSError *fallbackError) {
      NSDictionary *extra = [fallback isKindOfClass:NSDictionary.class] ? fallback : @{};
      self.cpuMS += [extra[@"cpuMS"] doubleValue]; self.maxSliceMS = MAX(self.maxSliceMS,[extra[@"maxSliceMS"] doubleValue]);
      if (fallbackError) [self finish:@{} frameID:frameID scale:scale coverage:coverage];
      else if ([extra[@"obstructed"] isEqual:@YES]) [self finish:extra frameID:frameID scale:scale coverage:coverage];
      else [self nextPoint];
    }];
  }];
}
@end

@implementation TLWebKitPageBridge
- (instancetype)initWithWebView:(WKWebView *)webView {
  if ((self = [super init])) {
    _webView = webView; _frames = [NSMutableDictionary dictionary]; _pending = [NSMutableDictionary dictionary];
    if (@available(macOS 27.0, *)) {
      WKContentWorldConfiguration *configuration = [WKContentWorldConfiguration new];
      configuration.allowAccessingClosedShadowRoots = YES;
      _contentWorld = [WKContentWorld worldWithConfiguration:configuration];
    } else _contentWorld = [WKContentWorld worldWithName:@"Talaria page integration"];
    _handlerName = [@"talariaPage" stringByAppendingString:[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    _overlaySource = TLPageResource(@"BrowserOverlayProbe");
    _footerSource = TLPageResource(@"BrowserDocumentFooter");
    _colorSource = TLPageResource(@"BrowserFooterColor");
    NSString *bridgeSource = TLPageResource(@"BrowserWebKitBridge");
    if (bridgeSource.length && _overlaySource.length)
      _installationSource = [NSString stringWithFormat:@"(%@)(%@,%@,(%@),(%@));",bridgeSource,TLPageJSON(_handlerName),TLPageJSON(NSUUID.UUID.UUIDString),_overlaySource,_colorSource.length ? _colorSource : @"null"];
  }
  return self;
}
- (void)install {
  if (self.stopped || !self.webView || !self.installationSource.length) return;
  if (!self.scriptsInstalled) {
    self.scriptsInstalled = YES;
    TLWebKitPageMessageHandler *handler = [TLWebKitPageMessageHandler new]; handler.owner = self;
    WKUserContentController *controller = self.webView.configuration.userContentController;
    [controller addScriptMessageHandler:handler contentWorld:self.contentWorld name:self.handlerName];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:self.installationSource injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO inContentWorld:self.contentWorld]];
  }
  NSString *footer = self.footerSource.length ? [NSString stringWithFormat:@"if (!globalThis.__talariaDocumentFooter) (%@)();",self.footerSource] : @"";
  NSString *body = [NSString stringWithFormat:@"%@ globalThis.__talariaWebKitBridge?.announce(); %@ return !!globalThis.__talariaDocumentFooter;",self.installationSource,footer];
  [self evaluateBody:body arguments:@{} frame:nil completion:^(id installed, NSError *error) {
    if (error || ![installed isEqual:@YES]) return;
    self.ready = YES;
    if (self.configuration) [self configureDocumentFooter:self.configuration completion:nil];
  }];
}
- (void)receiveMessage:(WKScriptMessage *)message {
  if (self.stopped || message.webView != self.webView || ![message.body isKindOfClass:NSDictionary.class]) return;
  NSString *identifier = message.body[@"id"];
  if (![identifier isKindOfClass:NSString.class] || identifier.length > 64) return;
  if(message.frameInfo.mainFrame && [message.body[@"scrollEnded"] isEqual:@YES] && self.topScrollEnded)self.topScrollEnded();
  if(message.frameInfo.mainFrame && [message.body[@"topRGB"] isKindOfClass:NSArray.class] && self.topColorChanged)
    self.topColorChanged(message.body[@"topRGB"]);
  if ([message.body[@"footerFill"] isKindOfClass:NSDictionary.class]) {
    if (message.frameInfo.mainFrame && [identifier isEqual:self.footerDocumentIdentifier])
      [self applyFooterFill:message.body[@"footerFill"]];
    return;
  }
  if ([message.body[@"remove"] isEqual:@YES]) [self.frames removeObjectForKey:identifier];
  else if (self.frames.count < 128 || self.frames[identifier]) self.frames[identifier] = message.frameInfo;
}
- (void)evaluateBody:(NSString *)body arguments:(NSDictionary *)arguments frame:(WKFrameInfo *)frame completion:(void (^)(id, NSError *))completion {
  if (self.stopped || !self.webView || !body.length) { if (completion) completion(nil,TLPageError(@"The browser page reader is not ready. Please try again.")); return; }
  NSString *identifier = NSUUID.UUID.UUIDString;
  NSUInteger generation = self.generation;
  __weak TLWebKitPageBridge *weakSelf = self;
  void (^finish)(id,NSError *) = ^(id value, NSError *error) {
    TLWebKitPageBridge *owner = weakSelf;
    void (^callback)(id,NSError *) = owner.pending[identifier];
    [owner.pending removeObjectForKey:identifier];
    if (callback) callback(value, owner.generation == generation ? error : TLPageError(@"The page changed. Please try again."));
  };
  if (completion) self.pending[identifier] = [completion copy];
  [self.webView callAsyncJavaScript:body arguments:arguments inFrame:frame inContentWorld:self.contentWorld completionHandler:finish];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{ finish(nil,TLPageError(@"The browser page did not respond. Please try again.")); });
}
- (void)applyFooterFill:(NSDictionary *)state {
  NSColor *color = [state[@"exposed"] isEqual:@YES] && [self.configuration[@"enabled"] boolValue]
    ? [TLBrowserContentColor colorForRGB:state[@"rgb"]] : nil;
  self.webView.underPageBackgroundColor = color;
}
- (void)resetForNavigation {
  self.footerDocumentIdentifier = nil;
  self.webView.underPageBackgroundColor = nil;
  [self stopFinding]; self.generation++; self.ready = NO;
  self.configuration = nil; self.pixelSample = nil; self.overlayHint = nil; self.overlayCursor = 0;
  [self.frames removeAllObjects];
  NSArray *callbacks = self.pending.allValues; [self.pending removeAllObjects];
  for (void (^callback)(id,NSError *) in callbacks) callback(nil,TLPageError(@"The page changed. Please try again."));
}
- (void)stop {
  if (self.stopped) return;
  self.stopped = YES;
  if (@available(macOS 26.0, *)) self.webView.obscuredContentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
  [self.webView evaluateJavaScript:@"globalThis.__talariaDocumentFooter?.dispose(); globalThis.__talariaWebKitBridge?.clearSelection();"
    inFrame:nil inContentWorld:self.contentWorld completionHandler:nil];
  [self resetForNavigation];
  [self.webView.configuration.userContentController removeScriptMessageHandlerForName:self.handlerName contentWorld:self.contentWorld];
}
- (void)dealloc {
  // WKUserContentController retains a weak forwarding handler, never the bridge.
  [self.webView.configuration.userContentController removeScriptMessageHandlerForName:self.handlerName contentWorld:self.contentWorld];
}
- (void)readPageExpectedURL:(NSURL *)URL completion:(void (^)(NSDictionary *, NSError *))completion {
  NSString *source = TLPageResource(@"Readability");
  if (!source.length) { completion(nil,TLPageError(@"The browser page reader is not ready. Please try again.")); return; }
  NSString *body = [@"return " stringByAppendingString:TLBrowserReadabilityScript(source,URL.absoluteString)];
  [self evaluateBody:body arguments:@{} frame:nil completion:^(id value, NSError *error) {
    if (error || ![value isKindOfClass:NSDictionary.class]) completion(nil,error ?: TLPageError(@"The page text was unavailable. Please try again."));
    else completion(value,nil);
  }];
}
- (void)probeOverlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion {
  if (@available(macOS 26.0, *)) {
    CGFloat bottom = self.webView.obscuredContentInsets.bottom;
    if (bottom > 0 && NSMaxY(rect) <= bottom) {
      // WebKit already keeps interactive page layout above this entire band.
      completion(@{@"obstructed":@NO, @"scanComplete":@YES}); return;
    }
    rect.origin.y -= bottom;
    viewport.height -= bottom;
  }
  if (!self.overlaySource.length || NSIsEmptyRect(rect) || viewport.width <= 0 || viewport.height <= 0) { completion(@{@"obstructed":NSNull.null}); return; }
  NSMutableDictionary *geometry = [@{@"left":@(NSMinX(rect)), @"bottom":@(NSMinY(rect)), @"width":@(NSWidth(rect)), @"height":@(NSHeight(rect)),
    @"currentWidth":@(viewport.width), @"currentHeight":@(viewport.height), @"cursor":@(self.overlayCursor), @"quick":@(quick)} mutableCopy];
  if (self.overlayHint) geometry[@"hint"] = self.overlayHint;
  NSUInteger generation = self.generation;
  NSString *body = [NSString stringWithFormat:@"return await (%@)(geometry);",self.overlaySource];
  [self evaluateBody:body arguments:@{@"geometry":geometry} frame:nil completion:^(id value, NSError *error) {
    if (error || ![value isKindOfClass:NSDictionary.class]) { completion(@{@"obstructed":NSNull.null}); return; }
    TLWebKitOverlayRequest *request = [TLWebKitOverlayRequest new]; request.bridge = self; request.scan = value;
    request.points = [value[@"fallbacks"] isKindOfClass:NSArray.class] ? value[@"fallbacks"] : @[];
    request.completion = ^(NSDictionary *result) {
      if (self.generation != generation || self.stopped) { completion(@{@"obstructed":NSNull.null}); return; }
      self.overlayCursor = [result[@"cursor"] unsignedIntegerValue];
      if ([result[@"hint"] isKindOfClass:NSDictionary.class]) self.overlayHint = result[@"hint"];
      completion(result);
    };
    [request start];
  }];
}
- (void)configureDocumentFooter:(NSDictionary *)configuration completion:(void (^)(BOOL))completion {
  if (self.stopped || !self.webView) { if (completion) completion(NO); return; }
  self.configuration = [configuration copy];
  NSMutableDictionary *documentConfiguration = [configuration mutableCopy];
  if (@available(macOS 26.0, *)) {
    // Preserve a separate extended band below the page's layout viewport.
    // WebKit keeps fixed controls and scroll limits above the floating input.
    CGFloat height = [configuration[@"height"] doubleValue];
    CGFloat bottom = [configuration[@"enabled"] boolValue] && isfinite(height) ? MAX(0, height) : 0;
    self.webView.obscuredContentInsets = NSEdgeInsetsMake(0, 0, bottom, 0);
    documentConfiguration[@"enabled"] = @NO;
    documentConfiguration[@"nativeFill"] = @(bottom > 0);
  }
  if (!self.footerSource.length) { if (completion) completion(NO); return; }
  NSString *body = [NSString stringWithFormat:@"if (!globalThis.__talariaDocumentFooter) (%@)(); const footer=globalThis.__talariaDocumentFooter; globalThis.__talariaTabColorRange=configuration.topRange; return {applied:footer.configure(configuration),fill:footer.fillState(),id:globalThis.__talariaWebKitBridge?.identifier};",self.footerSource];
  [self evaluateBody:body arguments:@{@"configuration":documentConfiguration} frame:nil completion:^(id value, NSError *error) {
    NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : nil;
    BOOL applied = !error && [result[@"applied"] isEqual:@YES];
    if (applied) {
      self.ready = YES;
      if ([self.configuration isEqual:configuration]) {
        self.footerDocumentIdentifier = result[@"id"];
        [self applyFooterFill:result[@"fill"]];
      }
    }
    if (completion) completion(applied);
  }];
}
// Encode only the sampled edge, not an entire high-resolution page. A complex
// viewport can exceed the analyzer's byte limit even though its edge is tiny.
static NSData *TLColorEdgeData(CGImageRef image, double bottomFraction, double leftFraction, double widthFraction) {
  if(!image || !isfinite(bottomFraction) || bottomFraction<=0 || bottomFraction>1 ||
     !isfinite(leftFraction) || !isfinite(widthFraction) || leftFraction<0 || widthFraction<=0 || leftFraction+widthFraction>1.000001)return nil;
  double width=CGImageGetWidth(image),height=CGImageGetHeight(image);
  double bottom=MAX(1,floor(height*bottomFraction));
  CGImageRef edge=CGImageCreateWithImageInRect(image,CGRectMake(floor(width*leftFraction),MAX(0,bottom-12),MAX(1,floor(width*widthFraction)),MIN(12,bottom)));
  if(!edge)return nil;
  NSBitmapImageRep *strip=[[NSBitmapImageRep alloc] initWithCGImage:edge];CGImageRelease(edge);
  return [strip representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
static BOOL TLColorNeedsPixels(NSDictionary *sample) {
  return sample && ![sample[@"rgb"] isKindOfClass:NSArray.class] && ![sample[@"busy"] boolValue] && [sample[@"captureReady"] boolValue];
}
static void TLRestoreColorPixels(NSMutableDictionary *sample, NSDictionary *cache) {
  if (sample && ![sample[@"rgb"] isKindOfClass:NSArray.class] && [sample[@"captureKey"] isKindOfClass:NSString.class] &&
      [sample[@"captureKey"] isEqual:cache[@"captureKey"]] && [cache[@"rgb"] isKindOfClass:NSArray.class]) {
    sample[@"rgb"] = cache[@"rgb"]; sample[@"mode"] = @"cachedPixels";
  }
}
- (void)rememberColorSample:(NSDictionary *)sample {
  NSMutableDictionary *cache = [self.pixelSample mutableCopy] ?: [NSMutableDictionary dictionary];
  if ([sample[@"mode"] isEqual:@"pixels"] && [sample[@"rgb"] isKindOfClass:NSArray.class]) {
    cache[@"rgb"] = sample[@"rgb"];
    if ([sample[@"captureKey"] isKindOfClass:NSString.class]) cache[@"captureKey"] = sample[@"captureKey"];
    else [cache removeObjectForKey:@"captureKey"];
  }
  NSDictionary *top = [sample[@"top"] isKindOfClass:NSDictionary.class] ? sample[@"top"] : nil;
  if ([top[@"mode"] isEqual:@"pixels"] && [top[@"rgb"] isKindOfClass:NSArray.class]) cache[@"top"] = top;
  self.pixelSample = cache;
}
- (void)sampleFooterColorAllowingCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {
  [self sampleColorsAllowingCapture:capture headerOnly:NO completion:completion];
}
- (void)sampleHeaderColorAllowingCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {
  [self sampleColorsAllowingCapture:capture headerOnly:YES completion:completion];
}
- (void)sampleColorsAllowingCapture:(BOOL)capture headerOnly:(BOOL)headerOnly completion:(void (^)(NSDictionary *))completion {
  if (!self.ready || !self.colorSource.length) { completion(@{}); return; }
  NSString *body = [NSString stringWithFormat:@"const read=(%@); const top=read(null,true,topRange); const bottom=headerOnly ? {} : read(banner); return {...bottom,top,extensionRGB:globalThis.__talariaDocumentFooter?.preparedColor?.(),cpuMS:(top.cpuMS||0)+(bottom.cpuMS||0),maxSliceMS:(top.cpuMS||0)+(bottom.cpuMS||0)};",self.colorSource];
  NSUInteger generation = self.generation;
  [self evaluateBody:body arguments:@{@"headerOnly":@(headerOnly),@"banner":self.configuration[@"banner"] ?: NSNull.null,@"topRange":self.configuration[@"topRange"] ?: NSNull.null} frame:nil completion:^(id value, NSError *error) {
    if (error || ![value isKindOfClass:NSDictionary.class]) { completion(@{}); return; }
    NSMutableDictionary *sample = [value mutableCopy];
    NSMutableDictionary *top = [sample[@"top"] isKindOfClass:NSDictionary.class] ? [sample[@"top"] mutableCopy] : nil;
    TLRestoreColorPixels(sample,self.pixelSample); TLRestoreColorPixels(top,self.pixelSample[@"top"]);
    if (top) sample[@"top"] = top;
    BOOL captureFooter = !headerOnly && TLColorNeedsPixels(sample), captureTop = TLColorNeedsPixels(top);
    if (!capture || (!captureFooter && !captureTop)) { completion(sample); return; }
    if (self.webView.fullscreenState != WKFullscreenStateNotInFullscreen || self.generation != generation || self.stopped) { completion(@{}); return; }
    NSDictionary *captureSample = captureFooter ? sample : top;
    NSArray *view = captureSample[@"viewState"];
    if (![view isKindOfClass:NSArray.class] || view.count != 4) { completion(sample); return; }
    double width = [view[0] doubleValue], height = [view[1] doubleValue];
    double pixels = width*height*pow([captureSample[@"deviceScale"] doubleValue],2);
    BOOL extension = captureFooter && [sample[@"documentExtension"] boolValue];
    if (!isfinite(pixels) || pixels <= 0 || pixels > TLBrowserContentColorMaximumImagePixels ||
        (extension && ![sample[@"token"] isKindOfClass:NSNumber.class])) { completion(sample); return; }
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    // Snapshot the existing viewport. This API does not resize the live view,
    // and all image analysis runs off the main thread.
    WKSnapshotConfiguration *configuration = [WKSnapshotConfiguration new];
    configuration.afterScreenUpdates = NO;
    if (@available(macOS 26.0, *)) {
      CGFloat bottomInset = self.webView.obscuredContentInsets.bottom;
      if (bottomInset > 0) configuration.rect = CGRectMake(0, 0, NSWidth(self.webView.bounds), MAX(1, NSHeight(self.webView.bounds) - bottomInset));
    }
    // The native tab needs only the page's top edge. Capturing the video and
    // the entire Retina viewport creates avoidable GPU readback on busy pages,
    // especially just after WebKit restores a fullscreen presentation.
    BOOL topStripOnly = captureTop && !captureFooter;
    if (topStripOnly) {
      CGRect viewport = CGRectIsNull(configuration.rect) ? self.webView.bounds : configuration.rect;
      configuration.rect = CGRectMake(CGRectGetMinX(viewport),CGRectGetMinY(viewport),CGRectGetWidth(viewport),
        MAX(1,CGRectGetHeight(viewport)*[top[@"sampleBottom"] doubleValue]/height));
    }
    __block BOOL finished = NO;
    void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
      if (finished) return; finished = YES;
      if (self.generation != generation || self.stopped) { completion(@{}); return; }
      [self rememberColorSample:result]; completion(result);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{ finish(sample); });
    [self.webView takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image, NSError *snapshotError) {
      if (finished) return;
      if (snapshotError || !image || self.generation != generation || self.webView.fullscreenState != WKFullscreenStateNotInFullscreen) { finish(@{}); return; }
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        // WKSnapshot already supplies a bitmap. Avoid encoding and decoding the
        // entire Retina viewport just to analyze a twelve-pixel edge strip.
        CGImageRef bitmap = [image CGImageForProposedRect:NULL context:nil hints:nil];
        double bottom = [sample[@"sampleBottom"] doubleValue];
        NSData *topData = captureTop ? TLColorEdgeData(bitmap,topStripOnly ? 1 : [top[@"sampleBottom"] doubleValue]/height,[top[@"sampleLeft"] doubleValue],top[@"sampleWidth"] ? [top[@"sampleWidth"] doubleValue] : 1) : nil;
        NSData *footerData = captureFooter ? TLColorEdgeData(bitmap,bottom>0 ? bottom/height : 1,0,extension ? [sample[@"contentWidth"] doubleValue]/width : 1) : nil;
        NSArray *topRGB = topData ? [TLBrowserContentColor dominantRGBForImageData:topData] : nil;
        NSArray *rgb = footerData && !extension ? [TLBrowserContentColor dominantRGBForImageData:footerData] : nil;
        NSArray *colors = footerData && extension ? [TLBrowserContentColor horizontalRGBStripForImageData:footerData bottomFraction:1 widthFraction:1] : nil;
        dispatch_async(dispatch_get_main_queue(),^{
          if (finished) return;
          sample[@"captureMS"] = @((NSProcessInfo.processInfo.systemUptime-started)*1000);
          if (self.generation != generation) { finish(@{}); return; }
          if (!topRGB && !rgb && !colors) { finish(sample); return; }
          NSString *validation = @"let valid = !globalThis.__talariaDocumentFooter?.isScrolling() && JSON.stringify([innerWidth,innerHeight,scrollX,scrollY]) === JSON.stringify(state);";
          if (captureFooter && !extension) validation = [validation stringByAppendingString:
            @" const edge = typeof bannerBottom === 'number' ? Math.max(1,innerHeight-bannerBottom) : (globalThis.__talariaDocumentFooter?.sampleBottom?.() ?? innerHeight); valid = valid && Math.abs(edge-bottom)<1;"];
          if (colors) validation = [validation stringByAppendingString:@"valid = valid && globalThis.__talariaDocumentFooter?.acceptCanvasSample(strip);"];
          validation = [validation stringByAppendingString:@"return !!valid;"];
          NSDictionary *strip = colors ? @{@"token":sample[@"token"], @"viewState":view, @"colors":colors} : @{};
          [self evaluateBody:validation arguments:@{@"state":view, @"bottom":@(bottom), @"bannerBottom":sample[@"bannerBottom"] ?: NSNull.null, @"strip":strip} frame:nil completion:^(id valid, NSError *validationError) {
            BOOL accepted = !validationError && [valid isEqual:@YES];
            if (accepted && topRGB) { top[@"rgb"] = topRGB; top[@"mode"] = @"pixels"; }
            if (accepted && rgb) { sample[@"rgb"] = rgb; sample[@"mode"] = @"pixels"; }
            if (extension) sample[@"applied"] = @(accepted && colors != nil);
            finish(sample);
          }];
        });
      });
    }];
  }];
}
- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext completion:(void (^)(NSInteger, NSInteger, BOOL))completion {
  if (!text.length || !self.webView || self.stopped) { [self stopFinding]; completion(0,0,YES); return; }
  BOOL fresh = !findNext || ![self.findQuery isEqualToString:text];
  if (fresh) { self.activeMatch = 0; self.findQuery = text; }
  NSUInteger searchGeneration = ++self.findGeneration;
  NSUInteger documentGeneration = self.generation;
  NSMutableArray *frames = [NSMutableArray arrayWithObject:NSNull.null];
  for (WKFrameInfo *frame in self.frames.allValues) if (!frame.mainFrame) [frames addObject:frame];
  dispatch_group_t group = dispatch_group_create();
  NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
  for (id item in frames) {
    WKFrameInfo *frame = item == NSNull.null ? nil : item;
    dispatch_group_enter(group);
    NSString *body = fresh ? @"const bridge=globalThis.__talariaWebKitBridge; bridge?.clearSelection(); return {id:bridge?.identifier,count:await bridge?.count(query)};" : @"const bridge=globalThis.__talariaWebKitBridge; return {id:bridge?.identifier,count:await bridge?.count(query)};";
    [self evaluateBody:body arguments:@{@"query":text} frame:frame completion:^(id value, NSError *error) {
      if (!error && [value isKindOfClass:NSDictionary.class] && [value[@"id"] isKindOfClass:NSString.class] && [value[@"count"] isKindOfClass:NSNumber.class])
        counts[value[@"id"]] = @(MAX(0,[value[@"count"] integerValue]));
      dispatch_group_leave(group);
    }];
  }
  dispatch_group_notify(group,dispatch_get_main_queue(),^{
    if (self.findGeneration != searchGeneration || self.generation != documentGeneration || self.stopped) return;
    NSInteger count = 0; for (NSNumber *value in counts.allValues) count += value.integerValue;
    WKFindConfiguration *configuration = [WKFindConfiguration new];
    configuration.backwards = !forward; configuration.caseSensitive = NO; configuration.wraps = YES;
    void (^search)(void) = ^{
      if (self.findGeneration != searchGeneration || self.generation != documentGeneration || self.stopped) return;
      [self.webView findString:text withConfiguration:configuration completionHandler:^(WKFindResult *result) {
        if (self.findGeneration != searchGeneration || self.generation != documentGeneration || self.stopped) return;
        // Native find owns selection, scrolling, frame traversal and highlighting.
        // WebKit exposes a match flag; isolated DOM counting supplies the total.
        NSInteger total = result.matchFound ? MAX(1,count) : 0;
        if (!total) self.activeMatch = 0;
        else if (fresh) self.activeMatch = forward ? 1 : total;
        else self.activeMatch = ((self.activeMatch-1+(forward ? 1 : total-1))%total)+1;
        completion(total,self.activeMatch,YES);
      }];
    };
    if (fresh) [self.webView findString:@"" withConfiguration:nil completionHandler:^(WKFindResult *result) { search(); }];
    else search();
  });
}
- (BOOL)finding { return self.findQuery.length > 0; }
- (void)stopFinding {
  self.findGeneration++; self.findQuery = nil; self.activeMatch = 0;
  if (!self.stopped) [self.webView findString:@"" withConfiguration:nil completionHandler:^(WKFindResult *result) {}];
}
@end
