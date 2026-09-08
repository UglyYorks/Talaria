#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
// Plain text keeps tool-provided context from becoming executable links or markup.
@interface TLToolActivityView : NSStackView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *activities;
@end
NS_ASSUME_NONNULL_END
