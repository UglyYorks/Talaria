#import "TLBrowserWebView.h"
#import "../TLBrowserWheelSmoother.h"
@implementation TLBrowserWebView {
  TLBrowserWheelSmoother *_wheelSmoother;
}
- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration {
  if((self=[super initWithFrame:frame configuration:configuration]))_wheelSmoother=[[TLBrowserWheelSmoother alloc] initWithWebView:self];
  return self;
}
- (BOOL)smoothMouseWheelScrolling { return _wheelSmoother.enabled; }
- (void)setSmoothMouseWheelScrolling:(BOOL)enabled { _wheelSmoother.enabled=enabled; }
- (BOOL)mouseWheelAnimationActive { return _wheelSmoother.animating; }
- (void)cancelMouseWheelScrolling { [_wheelSmoother cancel]; }
- (void)viewWillMoveToWindow:(NSWindow *)window { [_wheelSmoother attachToWindow:nil];[super viewWillMoveToWindow:window]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow];[_wheelSmoother attachToWindow:self.window]; }
- (void)viewDidHide { [_wheelSmoother cancel];[super viewDidHide]; }
- (void)willOpenMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  [_wheelSmoother cancel];
  [super willOpenMenu:menu withEvent:event];
  if (self.contextMenuHandler) self.contextMenuHandler(menu, event);
}
- (void)didCloseMenu:(NSMenu *)menu withEvent:(NSEvent *)event {
  if (self.contextMenuClosedHandler) self.contextMenuClosedHandler();
  [super didCloseMenu:menu withEvent:event];
}
@end
