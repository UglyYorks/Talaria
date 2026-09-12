#import <AppKit/AppKit.h>
#import "Theme.h"

@interface TLToolStatusPill : NSView
@property (nonatomic, strong) TLThemePalette *palette;
- (void)setAvatar:(NSString *)avatar activity:(NSDictionary *)activity;
+ (NSString *)labelForToolName:(NSString *)name;
@end
