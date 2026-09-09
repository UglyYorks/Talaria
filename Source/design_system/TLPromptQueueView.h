#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLQueuedPrompt.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLPromptQueueView : NSView
@property (nonatomic, copy, nullable) void (^sendNowHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^editHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^removeHandler)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^resumeHandler)(void);
@property (nonatomic, copy, nullable) void (^cancelEditHandler)(void);
@property (nonatomic, readonly) CGFloat preferredHeight;
- (void)updatePrompts:(NSArray<TLQueuedPrompt *> *)prompts editing:(nullable TLQueuedPrompt *)editing
              paused:(BOOL)paused canResume:(BOOL)canResume canSendNow:(BOOL)canSendNow palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
