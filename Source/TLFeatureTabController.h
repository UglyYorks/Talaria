#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// App feature ownership and semantic color bindings. Reapplying a palette never replaces views.
@interface TLFeatureTabController : NSViewController
@property (nonatomic, strong, readonly) TLThemePalette *palette;
@property (nonatomic, readonly, getter=isClosed) BOOL closed;
- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
- (void)close;
- (void)bindColorForObject:(id)object keyPath:(NSString *)keyPath token:(NSString *)token;
- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font colorToken:(NSString *)token;
- (NSTextField *)wrappingLabelWithString:(NSString *)string font:(NSFont *)font colorToken:(NSString *)token;
@end

NS_ASSUME_NONNULL_END
