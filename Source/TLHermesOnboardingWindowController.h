#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLHermesOnboardingWindowController : NSWindowController

@property (nonatomic, copy, nullable) void (^startHandler)(NSString *token, NSString *model);
@property (nonatomic, copy, nullable) void (^closeHandler)(void);

- (instancetype)initWithPalette:(TLThemePalette *)palette
                           token:(NSString *)token
                           model:(NSString *)model;
- (void)showFromWindow:(nullable NSWindow *)parentWindow;
- (void)appendProgress:(NSString *)text;
- (void)finishWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
