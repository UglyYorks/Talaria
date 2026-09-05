#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

CGFloat TLChromeTabInterTabOverlapForWidth(CGFloat width, TLThemePalette *palette);

@class TLChromeTabView;

@interface TLChromeTabSelectionView : NSView

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) CGFloat leadingFlareOutset;
@property (nonatomic, readonly) NSRect selectionFrame;
@property (nonatomic, copy, nullable) void (^geometryChanged)(void);
- (CGPathRef)newOutlinePath CF_RETURNS_RETAINED;

- (void)applyCurrentState;
- (void)setSelectionFrame:(NSRect)selectionFrame
        leadingFlareOutset:(CGFloat)leadingFlareOutset
                 animated:(BOOL)animated
                fromFrame:(NSRect)startFrame
                  duration:(NSTimeInterval)duration;

@end

@protocol TLChromeTabViewDelegate <NSObject>
- (CGFloat)chromeTabView:(TLChromeTabView *)tabView constrainedHorizontalTranslationForEvent:(NSEvent *)event proposedTranslation:(CGFloat)translationX;
- (void)chromeTabView:(TLChromeTabView *)tabView didDragWithEvent:(NSEvent *)event;
- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView;
- (void)chromeTabViewHoverStateDidChange:(TLChromeTabView *)tabView;
- (void)chromeTabViewDidRequestCloseOtherTabs:(TLChromeTabView *)tabView;
@end

@interface TLChromeTabView : NSControl

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL drawsActiveBackground;
@property (nonatomic) BOOL animatesDecorationChanges;
@property (nonatomic) BOOL closeable;
@property (nonatomic) BOOL canCloseOtherTabs;
@property (nonatomic) BOOL showsLeadingSeparator;
@property (nonatomic) BOOL showsTrailingSeparator;
@property (nonatomic, readonly, getter=isHovered) BOOL hovered;
@property (nonatomic, readonly) CGFloat dragTranslationX;
@property (nonatomic, readonly) CGFloat reorderTranslationX;
@property (nonatomic) CGFloat leadingFlareOutset;
@property (nonatomic, weak, nullable) id<TLChromeTabViewDelegate> dragDelegate;
@property (nonatomic, strong, nullable) id representedObject;
@property (nonatomic, assign, nullable) SEL closeAction;

- (void)applyCurrentState;
- (void)setReorderTranslationX:(CGFloat)translationX animated:(BOOL)animated;
- (void)finishPointerDrag;
- (void)setReorderTranslationX:(CGFloat)translationX animated:(BOOL)animated duration:(NSTimeInterval)duration;
- (void)prepareForInsertionAnimation;
@property (nonatomic, readonly) CGFloat lifecycleVisibleWidth;
@property (nonatomic, readonly) CGFloat lifecycleContentOpacity;
- (void)setLifecycleVisibleWidth:(CGFloat)width contentOpacity:(CGFloat)opacity;
- (void)clipLifecycleContentToSelectionView:(TLChromeTabSelectionView *)selectionView;
- (void)resetLifecycleAppearance;
- (void)updateTitle:(NSString *)title image:(nullable NSImage *)image icon:(NSString *)icon
    systemIconName:(NSString *)systemIconName animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
