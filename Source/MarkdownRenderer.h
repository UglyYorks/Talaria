#import <AppKit/AppKit.h>

@class TLThemePalette;

NS_ASSUME_NONNULL_BEGIN

typedef void (^TLMarkdownLinkHandler)(NSURL *URL, NSEventModifierFlags modifierFlags);

@interface TLMarkdownRenderer : NSObject

@property (nonatomic, copy, nullable) TLMarkdownLinkHandler linkHandler;
@property (nonatomic, copy, nullable) void (^heightChangeHandler)(void);

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (NSView *)viewForMarkdown:(NSString *)markdown textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont;
- (NSView *)viewForPlainText:(NSString *)text textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont;
- (void)updateMarkdown:(NSString *)markdown inView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
