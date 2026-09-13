#import <WebKit/WebKit.h>
@class TLThemePalette;

NS_ASSUME_NONNULL_BEGIN
/// User-initiated system AutoFill, scoped to the original HTTPS frame and form.
@interface TLBrowserPasswordAutofill : NSObject
@property (nonatomic, readonly) BOOL available;
- (instancetype)initWithWebView:(WKWebView *)webView;
- (void)present;
- (void)reset;
- (void)stop;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
