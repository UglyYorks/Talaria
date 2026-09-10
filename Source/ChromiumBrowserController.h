#import <AppKit/AppKit.h>
#import "TLBrowserLinkActions.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLChromiumBrowserTitleHandler)(NSString *title);
typedef void (^TLChromiumBrowserLinkHandler)(NSURL *URL, NSEventModifierFlags modifierFlags);
typedef void (^TLChromiumBrowserURLHandler)(NSURL *URL);
typedef void (^TLChromiumBrowserFaviconHandler)(NSImage * _Nullable favicon);
typedef void (^TLChromiumBrowserNavigationHandler)(BOOL canGoBack, BOOL canGoForward, BOOL loading);

@interface TLChromiumBrowserSession : NSObject

@property (nonatomic, weak, readonly, nullable) NSView *containerView;
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

@interface TLChromiumBrowserController : NSObject

+ (instancetype)sharedController;
- (void)markWindowIncognito:(NSWindow *)window;
- (void)forgetIncognitoWindow:(NSWindow *)window;
- (BOOL)initializeRuntimeFromWindow:(nullable NSWindow *)window;
- (void)openURL:(NSURL *)url fromWindow:(nullable NSWindow *)window;
- (void)openURL:(NSURL *)url fromWindow:(nullable NSWindow *)window modifierFlags:(NSEventModifierFlags)modifierFlags;
- (nullable TLChromiumBrowserSession *)loadURL:(NSURL *)url
                                        inView:(NSView *)view
                                    fromWindow:(nullable NSWindow *)window
                                  titleHandler:(nullable TLChromiumBrowserTitleHandler)titleHandler
                                   linkHandler:(nullable TLChromiumBrowserLinkHandler)linkHandler
                                    URLHandler:(nullable TLChromiumBrowserURLHandler)URLHandler
                                faviconHandler:(nullable TLChromiumBrowserFaviconHandler)faviconHandler
                             navigationHandler:(nullable TLChromiumBrowserNavigationHandler)navigationHandler;
- (void)startDownloadURL:(NSURL *)URL fromWindow:(nullable NSWindow *)window;
- (void)navigateSession:(nullable TLChromiumBrowserSession *)session toURL:(NSURL *)URL;
- (void)prepareBrowserSettingsInWindow:(nullable NSWindow *)window completion:(void (^)(NSError * _Nullable))completion;
- (NSDictionary *)browserSettingState:(NSDictionary *)setting;
- (BOOL)setBrowserSetting:(NSDictionary *)setting value:(nullable id)value error:(NSError **)error;
- (void)clearBrowserData:(NSString *)kind completion:(void (^)(NSError * _Nullable))completion;
- (void)importCookies:(NSArray<NSDictionary *> *)cookies completion:(void (^)(NSUInteger imported, NSUInteger failed))completion;
- (void)applyDarkAppearance:(BOOL)dark;
- (void)goBackInSession:(nullable TLChromiumBrowserSession *)session;
- (void)goForwardInSession:(nullable TLChromiumBrowserSession *)session;
- (void)reloadSession:(nullable TLChromiumBrowserSession *)session;
- (void)findText:(NSString *)text inSession:(nullable TLChromiumBrowserSession *)session forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)stopFindingInSession:(nullable TLChromiumBrowserSession *)session;
- (void)focusSession:(nullable TLChromiumBrowserSession *)session;
- (void)readPageInSession:(nullable TLChromiumBrowserSession *)session
             expectedURL:(NSURL *)URL
              completion:(void (^)(NSDictionary * _Nullable page, NSError * _Nullable error))completion;
// Geometry is native points with a bottom origin. Unknown results never mean clear.
- (void)probeOverlayInSession:(nullable TLChromiumBrowserSession *)session
                 overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick
                  completion:(void (^)(NSDictionary *result))completion;
- (void)closeSession:(nullable TLChromiumBrowserSession *)session;
// A document spacer shares the page's real scrollbar. Configuration completes
// after Chromium applies it, allowing exclusive switching to the native footer.
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(nullable TLChromiumBrowserSession *)session completion:(nullable void (^)(BOOL applied))completion;
- (void)sampleFooterColorInSession:(nullable TLChromiumBrowserSession *)session allowCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion;
- (void)closeBrowserInView:(NSView *)view;
- (BOOL)prepareForApplicationTermination;
- (void)shutdown;

@end

void TLChromiumBrowserControllerConfigureMainArgs(int argc, char * _Nonnull * _Nonnull argv);

NS_ASSUME_NONNULL_END
