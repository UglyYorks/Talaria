#import <AppKit/AppKit.h>

@interface TLAppDelegate : NSObject <NSApplicationDelegate>
- (BOOL)handleTabShortcutEvent:(NSEvent *)event;
@end
