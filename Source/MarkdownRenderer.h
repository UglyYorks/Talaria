#import <AppKit/AppKit.h>

@class TLThemePalette;

NS_ASSUME_NONNULL_BEGIN

typedef dispatch_block_t _Nullable (^TLMarkdownLinkContextMenuHandler)(NSURL *URL, NSMenu *menu, NSView *view, NSPoint point);

FOUNDATION_EXPORT NSNotificationName const TLMarkdownContentDidChangeNotification;

typedef void (^TLMarkdownLinkHandler)(NSURL *URL, NSEventModifierFlags modifierFlags);

@interface TLMarkdownRenderer : NSObject

@property (nonatomic, copy, nullable) TLMarkdownLinkHandler linkHandler;
@property (nonatomic, copy, nullable) TLMarkdownLinkContextMenuHandler linkContextMenuHandler;
@property (nonatomic, copy, nullable) void (^heightChangeHandler)(void);

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (NSView *)viewForMarkdown:(NSString *)markdown textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont;
- (NSView *)viewForPlainText:(NSString *)text textColor:(NSColor *)textColor baseFont:(NSFont *)baseFont;
+ (void)findText:(NSString *)query inView:(NSView *)view completion:(void (^)(NSInteger count))completion;
+ (void)selectFindMatch:(NSInteger)index inView:(NSView *)view reveal:(BOOL)reveal completion:(void (^)(NSRect rect))completion;
- (void)updateMarkdown:(NSString *)markdown inView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
