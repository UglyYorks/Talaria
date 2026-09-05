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
@property (nonatomic) BOOL showsStopButton;
@property (nonatomic, strong, nullable) NSView *backgroundView;
@property (nonatomic, copy, nullable) void (^textChangeHandler)(void);
@property (nonatomic, copy, nullable) void (^heightChangeHandler)(CGFloat height);

- (void)setLeadingAccessoryView:(NSView *)leadingView trailingAccessoryView:(NSView *)trailingView;

// Opt-in so browser address inputs keep their existing behavior.
@property (nonatomic) BOOL attachmentsEnabled;
@property (nonatomic) BOOL attachmentsEditable;
@property (nonatomic, copy) NSArray<NSURL *> *attachmentURLs;
@property (nonatomic, copy, nullable) void (^attachmentsChangeHandler)(void);
// Use an immediate replacement when switching between conversation drafts.
- (void)setAttachmentURLs:(NSArray<NSURL *> *)URLs animated:(BOOL)animated;
- (void)addAttachmentURLs:(NSArray<NSURL *> *)URLs;
- (void)recalculateHeight;

@end

NS_ASSUME_NONNULL_END
