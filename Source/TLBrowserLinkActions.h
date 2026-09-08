#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TLBrowserLinkURLIsNavigable(NSURL * _Nullable URL);
typedef NS_ENUM(NSInteger, TLBrowserLinkDestination) { TLBrowserLinkNewTab, TLBrowserLinkNewWindow, TLBrowserLinkSplitView };
typedef void (^TLBrowserLinkOpenHandler)(NSURL *URL, TLBrowserLinkDestination destination);
@interface TLBrowserLinkActions : NSObject
+ (dispatch_block_t)prepareMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view;
+ (dispatch_block_t)configureNativeMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view atPoint:(NSPoint)point open:(TLBrowserLinkOpenHandler)open;
+ (void)popUpMenu:(NSMenu *)menu forURL:(NSURL *)URL inView:(NSView *)view atPoint:(NSPoint)point;
+ (void)showSelectedText:(NSString *)text inView:(NSView *)view atPoint:(NSPoint)point;
+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard;
+ (NSMenu *)menuForURL:(NSURL *)URL canSplit:(BOOL)canSplit view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open inspect:(nullable dispatch_block_t)inspect
            imageMenu:(nullable NSMenu *)imageMenu;
@end
NS_ASSUME_NONNULL_END
