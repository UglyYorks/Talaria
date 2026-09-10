#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Maps the saved browser catalogue onto the WebKit APIs present on this Mac.
@interface TLWebKitBrowserSettings : NSObject
+ (BOOL)supportsSettingID:(NSString *)identifier;
+ (NSDictionary *)stateForSetting:(NSDictionary *)setting;
+ (BOOL)setValue:(nullable id)value forSetting:(NSDictionary *)setting error:(NSError **)error;
+ (void)applyToConfiguration:(WKWebViewConfiguration *)configuration;
+ (void)applyToWebView:(WKWebView *)webView;
+ (NSURLRequest *)requestForURL:(NSURL *)URL;
+ (NSURLRequest *)requestForRequest:(NSURLRequest *)request;
@end
NS_ASSUME_NONNULL_END
