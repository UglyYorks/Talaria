#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLASCIIPlanetScreensaverView : NSView

@property (nonatomic, copy, nullable) dispatch_block_t dismissHandler;

- (instancetype)initWithFrame:(NSRect)frame
              backgroundColor:(NSColor *)backgroundColor
                     artColor:(NSColor *)artColor NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (void)updateBackgroundColor:(NSColor *)backgroundColor artColor:(NSColor *)artColor;
- (void)startAnimating;
- (void)stopAnimating;

@end

NS_ASSUME_NONNULL_END
