#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TLSplitDropSide) {
  TLSplitDropSideNone, TLSplitDropSideLeft, TLSplitDropSideRight, TLSplitDropSideAbove, TLSplitDropSideBelow
};
@interface TLSplitWorkspaceView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, readonly) NSView *leftHost;
@property (nonatomic, readonly) NSView *rightHost;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *columns;
@property (nonatomic, copy) NSString *focusedIdentity;
@property (nonatomic) BOOL split;
@property (nonatomic) BOOL rightFocused;
@property (nonatomic) CGFloat fraction;
@property (nonatomic, copy) NSString *leftTitle;
@property (nonatomic, copy) NSString *rightTitle;
@property (nonatomic, copy, nullable) void (^focusIdentity)(NSString *identity);
@property (nonatomic, copy, nullable) void (^closeIdentity)(NSString *identity);
@property (nonatomic, copy, nullable) void (^dragPane)(NSString *identity, NSPoint windowPoint, BOOL ended, BOOL cancelled);
@property (nonatomic, copy, nullable) void (^fractionChanged)(CGFloat fraction);
@property (nonatomic, copy, nullable) void (^contentSizeChanged)(void);
@property (nonatomic, copy, nullable) void (^layoutWeightsChanged)(NSDictionary *weights);
- (void)restoreLayoutWeights:(nullable NSDictionary *)weights;
- (NSView *)hostForIdentity:(NSString *)identity;
- (nullable NSString *)identityAtPoint:(NSPoint)point;
- (void)setTitle:(NSString *)title image:(nullable NSImage *)image icon:(NSString *)icon systemIcon:(NSString *)symbol forIdentity:(NSString *)identity;
- (void)prepareDropTargetsWithValidator:(nullable BOOL (^)(NSString *identity, TLSplitDropSide side))validator;
- (nullable NSString *)dropIdentityAtPoint:(NSPoint)point;
- (void)showDropSide:(TLSplitDropSide)side title:(NSString *)title point:(NSPoint)point;
- (void)clearDropPreview;
- (TLSplitDropSide)dropSideAtPoint:(NSPoint)point;
@end
NS_ASSUME_NONNULL_END
