#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLThemedButton.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLFindBar : NSView <NSTextFieldDelegate>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, readonly) NSTextField *searchField;
@property (nonatomic, strong, readonly) NSTextField *resultLabel;
@property (nonatomic, strong, readonly) TLThemedButton *previousButton;
@property (nonatomic, strong, readonly) TLThemedButton *nextButton;
@property (nonatomic, strong, readonly) TLThemedButton *closeButton;
@property (nonatomic, copy, nullable) dispatch_block_t queryChangedHandler;
@property (nonatomic, copy, nullable) void (^navigateHandler)(BOOL forward);
@property (nonatomic, copy, nullable) dispatch_block_t closeHandler;
- (void)focusSearchField;
- (void)setMatchCount:(NSInteger)count activeMatch:(NSInteger)activeMatch searching:(BOOL)searching;
@end
NS_ASSUME_NONNULL_END
