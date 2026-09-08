#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Temporarily supplies the clicked link to macOS Services without replacing the clipboard.
@interface TLLinkServicesView : NSTextView
@property (nonatomic, copy) NSURL *URL;
@end
NS_ASSUME_NONNULL_END
