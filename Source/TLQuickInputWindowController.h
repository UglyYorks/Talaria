#import <AppKit/AppKit.h>
#import "design_system/UIComponents.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLQuickInputWindowController : NSWindowController <NSTextViewDelegate>
@property (nonatomic, strong, readonly) TLGlassMessageInput *messageInput;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *supportingModel;
@property (nonatomic, copy) NSString *reasoningEffort;
@property (nonatomic) BOOL settingsPopoverVisible;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *commands;
@property (nonatomic, copy, nullable) void (^submissionHandler)(NSString *text, NSArray<NSURL *> *files, BOOL allowAutomaticRouting);
@property (nonatomic, copy, nullable) void (^settingsHandler)(void);
@property (nonatomic, copy, nullable) void (^visibilityChangeHandler)(BOOL visible);
@property (nonatomic, copy, nullable) NSArray * (^suggestionsProvider)(NSString *input);
@property (nonatomic, copy, nullable) void (^destinationHandler)(NSDictionary *suggestion);
- (void)updateSuggestions;
- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)presentInNotchOnScreen:(NSScreen *)screen;
- (void)presentInNotchOnScreen:(NSScreen *)screen fromFrame:(NSRect)frame;
- (void)dismiss;
- (void)applyPalette:(TLThemePalette *)palette;
@end

NS_ASSUME_NONNULL_END
