#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Temporarily supplies the clicked link to macOS Services without replacing the clipboard.
@interface TLLinkServicesView : NSView
@property (copy) NSURL *URL;
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard types:(NSArray<NSPasteboardType> *)types;
@end
NS_ASSUME_NONNULL_END
