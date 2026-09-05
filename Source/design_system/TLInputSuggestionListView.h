#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

// A reusable, virtualized list: the number of views follows the viewport, not the catalogue.
@interface TLInputSuggestionListView : NSScrollView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *suggestions;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic, copy, nullable) void (^activationHandler)(NSUInteger index);
- (BOOL)isSuggestionEnabledAtIndex:(NSUInteger)index;
@end

NS_ASSUME_NONNULL_END
