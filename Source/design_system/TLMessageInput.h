#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLGlassButton.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLMessageInput : NSView

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, readonly) NSTextView *textView;
@property (nonatomic, strong, readonly) TLGlassButton *sendButton;
@property (nonatomic) CGFloat sendButtonSize;
@property (nonatomic) CGFloat sendButtonInset;
@property (nonatomic) CGFloat maximumExpandedHeight;
@property (nonatomic) BOOL selectsAllOnFocus;
@property (nonatomic, strong, nullable) NSView *backgroundView;
@property (nonatomic, copy, nullable) void (^textChangeHandler)(void);
@property (nonatomic, copy, nullable) void (^heightChangeHandler)(CGFloat height);

- (void)setLeadingAccessoryView:(NSView *)leadingView trailingAccessoryView:(NSView *)trailingView;

- (void)recalculateHeight;

@end

NS_ASSUME_NONNULL_END
