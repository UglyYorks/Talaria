#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TLBrowserWheelEventCanBeSmoothed(NSEvent *event);
@interface TLBrowserWheelSmoother : NSObject
- (instancetype)initWithWebView:(WKWebView *)webView;
@property (nonatomic) BOOL enabled;
@property (nonatomic, readonly) BOOL animating;
- (void)attachToWindow:(nullable NSWindow *)window;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
