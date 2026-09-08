#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TLBrowserLinkURLIsNavigable(NSURL * _Nullable URL);
typedef NS_ENUM(NSInteger, TLBrowserLinkDestination) { TLBrowserLinkNewTab, TLBrowserLinkNewWindow, TLBrowserLinkSplitView };
typedef void (^TLBrowserLinkOpenHandler)(NSURL *URL, TLBrowserLinkDestination destination);
@interface TLBrowserLinkActions : NSObject
+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard;
+ (NSMenu *)menuForURL:(NSURL *)URL canSplit:(BOOL)canSplit view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open inspect:(dispatch_block_t)inspect
            imageMenu:(nullable NSMenu *)imageMenu;
@end
NS_ASSUME_NONNULL_END
