#import <AppKit/AppKit.h>

#import "AppDelegate.h"
#import "design_system/TLShortcutRecorder.h"
#import "TLTerminalClient.h"

#include <string.h>

@interface TLApplication : NSApplication
@end

@implementation TLApplication

- (void)sendEvent:(NSEvent *)event {
  NSResponder *responder = self.keyWindow.firstResponder;
  if (event.type == NSEventTypeKeyDown && [responder isKindOfClass:TLShortcutRecorder.class] &&
      [(TLShortcutRecorder *)responder recording]) {
    [(TLShortcutRecorder *)responder keyDown:event];
    return;
  }
  NSEventModifierFlags shortcutModifiers = event.modifierFlags &
    (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
  if (event.type == NSEventTypeKeyDown && shortcutModifiers == NSEventModifierFlagCommand &&
      [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"q"]) {
    // Quit belongs to the application, even when WebKit owns keyboard focus.
    // Defer shutdown until the current native event dispatch has unwound.
    if (!event.isARepeat) {
      dispatch_async(dispatch_get_main_queue(), ^{ [self terminate:self]; });
    }
    return;
  }
  if ([(TLAppDelegate *)self.delegate handleTabShortcutEvent:event]) return;
  if ([(TLAppDelegate *)self.delegate handleFindShortcutEvent:event]) return;
  [super sendEvent:event];
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    if (argc == 3 && strcmp(argv[1], "--vm-terminal") == 0) return TLRunTerminalClient(argv[2]);

    NSApplication *application = [TLApplication sharedApplication];
    static TLAppDelegate *delegate = nil;
    delegate = [[TLAppDelegate alloc] init];
    application.delegate = delegate;

    [application run];
  }

  return 0;
}
