#import <AppKit/AppKit.h>
#import "TLBrowserLinkStore.h"
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TLBrowserLinkDestination) { TLBrowserLinkNewTab, TLBrowserLinkNewWindow, TLBrowserLinkTabGroup };
typedef void (^TLBrowserLinkOpenHandler)(NSURL *URL, TLBrowserLinkDestination destination, NSString * _Nullable groupID);
@interface TLBrowserLinkActions : NSObject
+ (void)copyURL:(NSURL *)URL toPasteboard:(NSPasteboard *)pasteboard;
+ (NSMenu *)menuForURL:(NSURL *)URL title:(NSString *)title view:(NSView *)view point:(NSPoint)point
                 open:(TLBrowserLinkOpenHandler)open download:(void (^)(BOOL saveAs))download inspect:(dispatch_block_t)inspect;
+ (void)appendLibraryMenusToMenu:(NSMenu *)menu window:(NSWindow *)window open:(TLBrowserLinkOpenHandler)open;
+ (void)promptForName:(NSString *)title initialValue:(NSString *)value window:(NSWindow *)window completion:(void (^)(NSString * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
