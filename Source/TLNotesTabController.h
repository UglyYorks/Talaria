#import "TLFeatureTabController.h"
#import "design_system/TLMessageInput.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLNotesTabController : TLFeatureTabController
@property (nonatomic, strong, readonly) TLMessageInput *notesMessageInput;
@property (nonatomic, strong, readonly) NSTextView *notesPromptTextView;
@property (nonatomic, getter=isInputEnabled) BOOL inputEnabled;
@property (nonatomic, copy, nullable) void (^sendPromptHandler)(NSString *prompt);
- (void)updateNotesMessageInputWidth;
@end
NS_ASSUME_NONNULL_END
