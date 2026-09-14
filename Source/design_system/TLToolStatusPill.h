#import <AppKit/AppKit.h>
#import "Theme.h"

@interface TLToolStatusPill : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) dispatch_block_t actionHandler;
- (void)setAvatar:(NSString *)avatar activity:(NSDictionary *)activity;
+ (NSString *)labelForToolName:(NSString *)name;
@end
