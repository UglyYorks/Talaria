#import <AppKit/AppKit.h>

#import "AppDelegate.h"
#import "TLTerminalClient.h"
#import "ChromiumBrowserController.h"

#include "include/cef_application_mac.h"

@interface TLApplication : NSApplication <CefAppProtocol>
@end

@implementation TLApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  NSEventModifierFlags shortcutModifiers = event.modifierFlags &
    (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
  if (event.type == NSEventTypeKeyDown && shortcutModifiers == NSEventModifierFlagCommand &&
      [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"q"]) {
    // Quit belongs to the application, even when Chromium owns keyboard focus.
    // Defer shutdown until the current native/CEF event dispatch has unwound.
    if (!event.isARepeat) {
      dispatch_async(dispatch_get_main_queue(), ^{ [self terminate:self]; });
    }
    return;
  }
  CefScopedSendingEvent sendingEvent;
  if ([(TLAppDelegate *)self.delegate handleTabShortcutEvent:event]) return;
  [super sendEvent:event];
}

@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    if (argc == 3 && strcmp(argv[1], "--vm-terminal") == 0) return TLRunTerminalClient(argv[2]);
    TLChromiumBrowserControllerConfigureMainArgs(argc, argv);

    NSApplication *application = [TLApplication sharedApplication];
    static TLAppDelegate *delegate = nil;
    delegate = [[TLAppDelegate alloc] init];
    application.delegate = delegate;

    [application run];
  }

  return 0;
}
