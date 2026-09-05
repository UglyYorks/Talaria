#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLButtonStyle) {
  TLButtonStyleMinimal,
  TLButtonStyleCompactMinimal,
};

typedef NS_ENUM(NSInteger, TLButtonSize) {
  TLButtonSizeMedium,
};

@interface TLButton : NSView

@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, strong, nullable) NSColor *contentTintColor;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) TLButtonStyle style;
@property (nonatomic) TLButtonSize size;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) BOOL hoverSuppressed;
@property (nonatomic, copy, nullable) void (^hoverChanged)(BOOL hovered);

@end

NS_ASSUME_NONNULL_END
