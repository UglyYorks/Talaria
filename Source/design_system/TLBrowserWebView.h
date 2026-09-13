#import <WebKit/WebKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Native browser surface; the controller supplies page-specific menu actions.
@interface TLBrowserWebView : WKWebView <NSMenuItemValidation>
@property (nonatomic, copy, nullable) void (^contextMenuHandler)(NSMenu *, NSEvent *);
@property (nonatomic, copy, nullable) dispatch_block_t contextMenuClosedHandler;
@property (nonatomic, copy, nullable) dispatch_block_t passwordAutofillHandler;
@property (nonatomic, copy, nullable) BOOL (^passwordAutofillAvailable)(void);
- (void)autofillPassword:(nullable id)sender;
@property (nonatomic) BOOL smoothMouseWheelScrolling;
@property (nonatomic, readonly) BOOL mouseWheelAnimationActive;
- (void)cancelMouseWheelScrolling;
@end
NS_ASSUME_NONNULL_END
