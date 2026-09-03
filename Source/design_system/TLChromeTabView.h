#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@class TLChromeTabView;

@protocol TLChromeTabViewDelegate <NSObject>
- (CGFloat)chromeTabView:(TLChromeTabView *)tabView constrainedHorizontalTranslationForEvent:(NSEvent *)event proposedTranslation:(CGFloat)translationX;
- (void)chromeTabView:(TLChromeTabView *)tabView didDragWithEvent:(NSEvent *)event;
- (void)chromeTabViewDidEndDragging:(TLChromeTabView *)tabView;
@end

@interface TLChromeTabView : NSControl

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic) BOOL active;
@property (nonatomic) BOOL closeable;
@property (nonatomic) BOOL showsLeadingSeparator;
@property (nonatomic) BOOL showsTrailingSeparator;
@property (nonatomic, readonly) CGFloat dragTranslationX;
@property (nonatomic) CGFloat leadingFlareOutset;
@property (nonatomic, weak, nullable) id<TLChromeTabViewDelegate> dragDelegate;
@property (nonatomic, strong, nullable) id representedObject;
@property (nonatomic, assign, nullable) SEL closeAction;

- (void)applyCurrentState;

@end

NS_ASSUME_NONNULL_END
