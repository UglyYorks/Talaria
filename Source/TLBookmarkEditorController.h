#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLBookmarkEditorController : NSViewController
@property (nonatomic, copy, nullable) BOOL (^saveHandler)(TLBookmark *bookmark, NSError **error);
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
@property (nonatomic, copy, nullable) void (^contentSizeChangedHandler)(NSSize size);
- (instancetype)initWithBookmark:(TLBookmark *)bookmark palette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
