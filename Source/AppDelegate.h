#import <AppKit/AppKit.h>

@interface TLAppDelegate : NSObject <NSApplicationDelegate>
- (BOOL)handleFindShortcutEvent:(NSEvent *)event;
- (BOOL)handleTabShortcutEvent:(NSEvent *)event;
@end
