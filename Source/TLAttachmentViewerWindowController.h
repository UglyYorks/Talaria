#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLAttachmentPreviewItem.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLAttachmentViewerWindowController : NSWindowController
@property (nonatomic, readonly) NSUInteger selectedIndex;
- (instancetype)initWithItems:(NSArray<TLAttachmentPreviewItem *> *)items
           conversationTitle:(NSString *)title selectedIndex:(NSUInteger)index palette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
- (void)selectItemAtIndex:(NSUInteger)index;
@end
NS_ASSUME_NONNULL_END
