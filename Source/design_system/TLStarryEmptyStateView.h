#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// A quiet field of pulsing four-point sparkles with a clear center for an avatar and a single app tip.
@interface TLStarryEmptyStateView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *avatar;
@property (nonatomic, copy) NSString *tip;
/// The transcript/composer width used to cap user-message bubbles.
@property (nonatomic) CGFloat availableMessageWidth;
@end

NS_ASSUME_NONNULL_END
