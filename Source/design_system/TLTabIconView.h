#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLTabIconView : NSView

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic, strong, nullable) NSColor *contentTintColor;
@property (nonatomic, readonly) BOOL hasIcon;

- (void)applyCurrentState;

@end

NS_ASSUME_NONNULL_END
