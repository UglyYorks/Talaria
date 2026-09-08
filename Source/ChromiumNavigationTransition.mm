#import "ChromiumNavigationTransition.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"

class TLNavigationTransitionObserver : public CefDevToolsMessageObserver {
 public:
  TLNavigationTransitionObserver(CefRefPtr<CefBrowser> browser, NSView *container)
      : browser_(browser), container_(container) {}

  void Start() {
    registration_ = browser_->GetHost()->AddDevToolsMessageObserver(this);
    Send(@"Page.enable", @{});
    Send(@"Page.setLifecycleEventsEnabled", @{@"enabled":@YES});
    Send(@"Page.getFrameTree", @{}, &treeID_);
  }

  void Begin() {
    NSView *container = container_;
    if (active_ || !container.window.visible || container.hiddenOrHasHiddenAncestor) return;
    NSSize size = [container convertSizeToBacking:container.bounds.size];
    if (size.width <= 0 || size.height <= 0 || size.width * size.height > 16 * 1024 * 1024) return;
    active_ = true;
    sourceLoader_ = loader_;
    captureSize_ = container.bounds.size;
    NSUInteger generation = ++generation_;
    // No clip: a clipped CDP screenshot resizes the live render widget.
    Send(@"Page.captureScreenshot", @{@"format":@"png", @"fromSurface":@YES,
        @"captureBeyondViewport":@NO, @"optimizeForSpeed":@YES}, &captureID_);
    CefRefPtr<TLNavigationTransitionObserver> alive = this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
      if (alive->generation_ == generation) alive->Clear();
    });
  }

  void Finish() {
    if (!active_) return;
    active_ = false;
    captureID_ = 0;
    NSUInteger generation = generation_;
    CefRefPtr<TLNavigationTransitionObserver> alive = this;
    // The renderer's paint notification precedes native layer presentation.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
      if (alive->generation_ == generation) alive->Clear();
    });
  }

  void Stop() { Clear(); registration_ = nullptr; browser_ = nullptr; }
  void Cancel() { Clear(); }

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int identifier, bool success,
                             const void *result, size_t size) override {
    CefRefPtr<TLNavigationTransitionObserver> alive = this;
    if (!success || size > 24 * 1024 * 1024 || (identifier != captureID_ && identifier != treeID_)) return;
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class]) return;
    if (identifier == treeID_) {
      NSDictionary *frame = value[@"frameTree"][@"frame"];
      frame_ = frame[@"id"]; loader_ = frame[@"loaderId"];
      return;
    }
    NSString *encoded = value[@"data"];
    if (![encoded isKindOfClass:NSString.class]) return;
    NSUInteger generation = generation_;
    // Decode away from the UI thread; a late capture must never cover a new page.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
      NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
      NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:data];
      if (!bitmap || bitmap.pixelsWide * bitmap.pixelsHigh > 16 * 1024 * 1024 || !bitmap.bitmapData) return;
      dispatch_async(dispatch_get_main_queue(),^{
        NSView *container = alive->container_;
        if (!alive->active_ || alive->generation_ != generation || !container.window.visible ||
            container.hiddenOrHasHiddenAncestor || !NSEqualSizes(alive->captureSize_,container.bounds.size)) return;
        NSImage *image = [[NSImage alloc] initWithSize:alive->captureSize_];
        [image addRepresentation:bitmap];
        [alive->cover_ removeFromSuperview];
        alive->cover_ = [[NSImageView alloc] initWithFrame:container.bounds];
        alive->cover_.image = image;
        alive->cover_.imageScaling = NSImageScaleAxesIndependently;
        [alive->cover_ setAccessibilityHidden:YES];
        [container addSubview:alive->cover_ positioned:NSWindowAbove relativeTo:nil];
      });
    });
  }

  void OnDevToolsEvent(CefRefPtr<CefBrowser>, const CefString &method,
                      const void *params, size_t size) override {
    if (size > 65536 || (method != "Page.frameNavigated" && method != "Page.lifecycleEvent")) return;
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:params length:size] options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class]) return;
    if (method == "Page.frameNavigated") {
      NSDictionary *frame = value[@"frame"];
      if (frame[@"parentId"]) return;
      treeID_ = 0;
      frame_ = frame[@"id"]; loader_ = frame[@"loaderId"];
    } else if (active_ && [value[@"frameId"] isEqual:frame_] &&
               [value[@"loaderId"] isEqual:loader_] &&
               ![value[@"loaderId"] isEqual:sourceLoader_] &&
               [value[@"name"] isEqual:@"firstContentfulPaint"]) {
      Finish();
    }
  }

  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    CefRefPtr<TLNavigationTransitionObserver> alive = this;
    Stop();
  }

 private:
  void Send(NSString *method, NSDictionary *parameters, int *trackedID = nullptr) {
    if (!browser_ || !browser_->IsValid()) return;
    static int next = 1600000000;
    int identifier = ++next;
    if (trackedID) *trackedID = identifier;
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"id":@(identifier),@"method":method,@"params":parameters} options:0 error:nil];
    browser_->GetHost()->SendDevToolsMessage(json.bytes,json.length);
  }
  void Clear() {
    ++generation_; active_ = false; captureID_ = 0;
    [cover_ removeFromSuperview]; cover_ = nil;
  }
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  NSView *__weak container_;
  NSImageView *__strong cover_;
  NSString *__strong frame_, *__strong loader_, *__strong sourceLoader_;
  NSSize captureSize_;
  NSUInteger generation_ = 0;
  int captureID_ = 0, treeID_ = 0;
  bool active_ = false;
  IMPLEMENT_REFCOUNTING(TLNavigationTransitionObserver);
};

@implementation TLChromiumNavigationTransition {
  CefRefPtr<TLNavigationTransitionObserver> _observer;
  id _resizeObserver;
}
- (instancetype)initWithBrowser:(CefRefPtr<CefBrowser>)browser container:(NSView *)container {
  if ((self = [super init])) {
    _observer = new TLNavigationTransitionObserver(browser,container); _observer->Start();
    container.postsFrameChangedNotifications = YES;
    __weak TLChromiumNavigationTransition *weakSelf = self;
    _resizeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification
      object:container queue:nil usingBlock:^(NSNotification *) { [weakSelf cancel]; }];
  }
  return self;
}
- (void)begin { if (_observer) _observer->Begin(); }
- (void)finish { if (_observer) _observer->Finish(); }
- (void)cancel { if (_observer) _observer->Cancel(); }
- (void)stop {
  if (_resizeObserver) { [NSNotificationCenter.defaultCenter removeObserver:_resizeObserver]; _resizeObserver = nil; }
  if (_observer) { _observer->Stop(); _observer = nullptr; }
}
- (void)dealloc { [self stop]; }
@end
