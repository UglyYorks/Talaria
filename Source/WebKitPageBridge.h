#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

// One bridge per WKWebView. All app scripts run in an isolated content world;
// Frame handles and asynchronous replies are discarded when navigation commits.
@interface TLWebKitPageBridge : NSObject
@property(nonatomic, readonly) WKContentWorld *contentWorld;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) BOOL finding;
@property(nonatomic, copy, nullable) dispatch_block_t topScrollEnded;
@property(nonatomic, copy, nullable) void (^topColorChanged)(NSArray *rgb);
- (instancetype)initWithWebView:(WKWebView *)webView;
- (void)install;
- (void)resetForNavigation;
- (void)stop;
- (void)readPageExpectedURL:(NSURL *)URL completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
- (void)probeOverlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion;
- (void)configureDocumentFooter:(NSDictionary *)configuration completion:(void (^ _Nullable)(BOOL applied))completion;
- (void)sampleFooterColorAllowingCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion;
- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext completion:(void (^)(NSInteger count, NSInteger active, BOOL finalUpdate))completion;
- (void)stopFinding;
@end

NS_ASSUME_NONNULL_END
