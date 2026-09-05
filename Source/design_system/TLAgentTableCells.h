#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLAgentNameCellView : NSTableCellView
- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)configureWithName:(NSString *)name avatar:(NSString *)avatar current:(BOOL)current palette:(TLThemePalette *)palette;
@end

@interface TLAgentStatusCellView : NSTableCellView
- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)configureWithStatus:(NSString *)status running:(BOOL)running initializing:(BOOL)initializing setupRequired:(BOOL)setupRequired palette:(TLThemePalette *)palette;
@end

NS_ASSUME_NONNULL_END
