#import <AppKit/AppKit.h>

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

@end

@interface TLChromiumBrowserController : NSObject

+ (instancetype)sharedController;
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
- (void)navigateSession:(nullable TLChromiumBrowserSession *)session toURL:(NSURL *)URL;
- (void)goBackInSession:(nullable TLChromiumBrowserSession *)session;
- (void)goForwardInSession:(nullable TLChromiumBrowserSession *)session;
- (void)reloadSession:(nullable TLChromiumBrowserSession *)session;
- (void)readPageInSession:(nullable TLChromiumBrowserSession *)session
             expectedURL:(NSURL *)URL
              completion:(void (^)(NSDictionary * _Nullable page, NSError * _Nullable error))completion;
- (void)closeSession:(nullable TLChromiumBrowserSession *)session;
- (void)closeBrowserInView:(NSView *)view;
- (BOOL)prepareForApplicationTermination;
- (void)shutdown;

@end

void TLChromiumBrowserControllerConfigureMainArgs(int argc, char * _Nonnull * _Nonnull argv);

NS_ASSUME_NONNULL_END
