#import <AppKit/AppKit.h>

@interface TLAppDelegate : NSObject <NSApplicationDelegate>
- (void)openIncognitoURLInNewWindow:(NSURL *)URL;
- (BOOL)handleFindShortcutEvent:(NSEvent *)event;
- (BOOL)handleTabShortcutEvent:(NSEvent *)event;
@end
