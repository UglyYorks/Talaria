#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TLSplitDropSide) {
  TLSplitDropSideNone, TLSplitDropSideLeft, TLSplitDropSideRight
};

@interface TLSplitWorkspaceView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, readonly) NSView *leftHost;
@property (nonatomic, readonly) NSView *rightHost;
@property (nonatomic) BOOL split;
@property (nonatomic) BOOL rightFocused;
@property (nonatomic) CGFloat fraction;
@property (nonatomic, copy) NSString *leftTitle;
@property (nonatomic, copy) NSString *rightTitle;
@property (nonatomic, copy, nullable) void (^focusPane)(BOOL right);
@property (nonatomic, copy, nullable) void (^expandPane)(BOOL right);
@property (nonatomic, copy, nullable) void (^swapPanes)(void);
@property (nonatomic, copy, nullable) void (^fractionChanged)(CGFloat fraction);
@property (nonatomic, copy, nullable) void (^contentSizeChanged)(void);
- (void)showDropSide:(TLSplitDropSide)side title:(NSString *)title point:(NSPoint)point;
- (void)clearDropPreview;
- (TLSplitDropSide)dropSideAtPoint:(NSPoint)point;
@end
NS_ASSUME_NONNULL_END
