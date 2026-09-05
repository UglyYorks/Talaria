#import <Foundation/Foundation.h>

// Headless mode entered before AppKit/Chromium startup, from Terminal.app.
FOUNDATION_EXPORT int TLRunTerminalClient(const char *socketPath);
