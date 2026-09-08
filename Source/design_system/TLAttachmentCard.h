#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
/// Keyboard-accessible file card used in transcripts and attachment lists.
@interface TLAttachmentCard : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL selected;
@property (nonatomic, copy, nullable) void (^activationHandler)(void);
@end
NS_ASSUME_NONNULL_END
