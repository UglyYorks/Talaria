#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "TLBrowserLinkActions.h"
#import "TLBrowserImageActions.h"
NS_ASSUME_NONNULL_BEGIN

typedef void (^TLWebKitBrowserTitleHandler)(NSString *title);
typedef void (^TLWebKitBrowserLinkHandler)(NSURL *URL, NSEventModifierFlags modifierFlags);
typedef void (^TLWebKitBrowserURLHandler)(NSURL *URL);
typedef void (^TLWebKitBrowserFaviconHandler)(NSImage * _Nullable favicon);
typedef void (^TLWebKitBrowserNavigationHandler)(BOOL canGoBack, BOOL canGoForward, BOOL loading);

@interface TLWebKitBrowserSession : NSObject
@property (nonatomic, weak, readonly, nullable) NSView *containerView;
@property (nonatomic, strong, readonly, nullable) WKWebView *webView;
@property (nonatomic, copy, readonly) NSString *initialURLString;
@property (nonatomic, readonly) NSInteger browserIdentifier;
@property (nonatomic, readonly) NSUInteger documentGeneration;
@property (nonatomic, readonly, getter=isFullscreen) BOOL fullscreen;
@property (nonatomic, readonly) BOOL devToolsVisible;
@property (nonatomic, copy, nullable) dispatch_block_t devToolsVisibilityChangedHandler;
@property (nonatomic, copy, nullable) TLBrowserLinkOpenHandler contextLinkHandler;
@property (nonatomic, copy, nullable) void (^findResultsChangedHandler)(NSInteger count, NSInteger activeMatch, BOOL finalUpdate);
@property (nonatomic, copy, nullable) dispatch_block_t documentStartedHandler;
@end

@interface TLWebKitBrowserController : NSObject
+ (instancetype)sharedController;
- (void)markWindowIncognito:(NSWindow *)window;
- (void)forgetIncognitoWindow:(NSWindow *)window;
- (BOOL)initializeRuntimeFromWindow:(nullable NSWindow *)window;
- (void)openURL:(NSURL *)URL fromWindow:(nullable NSWindow *)window;
- (void)openURL:(NSURL *)URL fromWindow:(nullable NSWindow *)window modifierFlags:(NSEventModifierFlags)flags;
- (nullable TLWebKitBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(nullable NSWindow *)window
  titleHandler:(nullable TLWebKitBrowserTitleHandler)titleHandler linkHandler:(nullable TLWebKitBrowserLinkHandler)linkHandler
  URLHandler:(nullable TLWebKitBrowserURLHandler)URLHandler faviconHandler:(nullable TLWebKitBrowserFaviconHandler)faviconHandler
  navigationHandler:(nullable TLWebKitBrowserNavigationHandler)navigationHandler;
- (void)startDownloadURL:(NSURL *)URL fromWindow:(nullable NSWindow *)window;
- (void)navigateSession:(nullable TLWebKitBrowserSession *)session toURL:(NSURL *)URL;
- (void)prepareBrowserSettingsInWindow:(nullable NSWindow *)window completion:(void (^)(NSError * _Nullable))completion;
- (NSDictionary *)browserSettingState:(NSDictionary *)setting;
- (BOOL)setBrowserSetting:(NSDictionary *)setting value:(nullable id)value error:(NSError **)error;
- (void)clearBrowserData:(NSString *)kind completion:(void (^)(NSError * _Nullable))completion;
- (void)importCookies:(NSArray<NSDictionary *> *)cookies completion:(void (^)(NSUInteger imported, NSUInteger failed))completion;
- (void)applyDarkAppearance:(BOOL)dark;
- (void)goBackInSession:(nullable TLWebKitBrowserSession *)session;
- (void)goForwardInSession:(nullable TLWebKitBrowserSession *)session;
- (void)reloadSession:(nullable TLWebKitBrowserSession *)session;
- (void)findText:(NSString *)text inSession:(nullable TLWebKitBrowserSession *)session forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFindingInSession:(nullable TLWebKitBrowserSession *)session;
- (void)focusSession:(nullable TLWebKitBrowserSession *)session;
- (void)readPageInSession:(nullable TLWebKitBrowserSession *)session expectedURL:(NSURL *)URL
  completion:(void (^)(NSDictionary * _Nullable page, NSError * _Nullable error))completion;
- (void)probeOverlayInSession:(nullable TLWebKitBrowserSession *)session overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *result))completion;
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(nullable TLWebKitBrowserSession *)session completion:(nullable void (^)(BOOL applied))completion;
- (void)sampleFooterColorInSession:(nullable TLWebKitBrowserSession *)session allowCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion;
- (void)closeSession:(nullable TLWebKitBrowserSession *)session;
- (void)closeBrowserInView:(NSView *)view;
- (BOOL)prepareForApplicationTermination;
- (void)shutdown;
// Browser actions shared by native menus and integration probes.
- (void)readImageAtURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session frame:(nullable WKFrameInfo *)frame completion:(void (^)(TLBrowserImageResource * _Nullable, NSError * _Nullable))completion;
- (void)showPageSourceInSession:(TLWebKitBrowserSession *)session;
- (void)savePageInSession:(TLWebKitBrowserSession *)session;
- (void)inspectSession:(TLWebKitBrowserSession *)session atPoint:(NSPoint)point;
- (void)closeInspectorInSession:(TLWebKitBrowserSession *)session;
@end
NS_ASSUME_NONNULL_END
