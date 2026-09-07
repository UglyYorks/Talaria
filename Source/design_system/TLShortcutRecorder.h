#import "TLThemedButton.h"

NS_ASSUME_NONNULL_BEGIN
/// Native focusable shortcut recorder. Escape cancels; Delete clears the binding.
@interface TLShortcutRecorder : TLThemedButton
@property (nonatomic, copy, nullable) NSDictionary *shortcut;
@property (nonatomic, copy, nullable) void (^changeHandler)(NSDictionary * _Nullable shortcut);
@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, copy, nullable) void (^recordingHandler)(BOOL recording);
- (void)cancelRecording;
@end
NS_ASSUME_NONNULL_END
