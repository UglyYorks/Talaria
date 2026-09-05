#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

/// An avatar button backed by the macOS Emoji & Symbols picker.
@interface TLEmojiPicker : NSButton <NSTextInputClient>
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, copy, nullable) void (^emojiChangedHandler)(NSString *emoji);
@end

NS_ASSUME_NONNULL_END
