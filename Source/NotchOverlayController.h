#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLNotchOverlayFileDropHandler)(NSArray<NSURL *> *fileURLs);

@interface TLNotchOverlayController : NSObject

@property (nonatomic, readonly) NSPoint lastMouseLocation;
@property (nonatomic, copy, nullable) TLNotchOverlayFileDropHandler fileDropHandler;

- (instancetype)initWithPalette:(TLThemePalette *)palette target:(id)target action:(SEL)action;
- (void)startTracking;
- (void)stopTracking;
- (void)updatePalette:(TLThemePalette *)palette;

@end

NS_ASSUME_NONNULL_END
