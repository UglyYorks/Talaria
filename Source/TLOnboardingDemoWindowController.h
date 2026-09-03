#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLOnboardingDemoWindowController : NSWindowController

@property (nonatomic, copy, nullable) void (^openAppHandler)(void);

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)showFromWindow:(nullable NSWindow *)parentWindow;
- (void)updatePalette:(TLThemePalette *)palette;

@end

NS_ASSUME_NONNULL_END
