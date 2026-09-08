#import <AppKit/AppKit.h>

@interface TLAppDelegate : NSObject <NSApplicationDelegate>
- (BOOL)handleBrowserFindShortcutEvent:(NSEvent *)event;
- (BOOL)handleTabShortcutEvent:(NSEvent *)event;
@end
