#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
// Session activity survives individual replies. All tool output is plain text.
@interface TLRuntimeActivityView : NSStackView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary *> *activities;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic) BOOL expanded;
@end
NS_ASSUME_NONNULL_END
