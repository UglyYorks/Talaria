#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLHoverIconButton : NSButton
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL hoverSurfaceOnly;
@property (nonatomic, strong, nullable) NSColor *idleSurfaceColor;
@end

@interface TLGlassButton : NSView

@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) NSFont *font;
@property (nonatomic, strong, nullable) NSColor *contentTintColor;
@property (nonatomic, strong, nullable) NSColor *glassTintColor;
@property (nonatomic, strong, nullable) NSColor *glassHoverTintColor;
@property (nonatomic, strong, nullable) NSColor *solidSurfaceColor;
@property (nonatomic, strong, nullable) NSColor *disabledSolidSurfaceColor;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) BOOL usesGlassEffect;
@property (nonatomic) BOOL hoverSurfaceOnly;

// For icon-only buttons: shrink/fade the old image, then grow/fade the new one.
// The logical image and action remain current throughout the visual transition.
- (void)setImage:(nullable NSImage *)image animated:(BOOL)animated;

- (instancetype)initWithUsesGlassEffect:(BOOL)usesGlassEffect;

@end

NS_ASSUME_NONNULL_END
