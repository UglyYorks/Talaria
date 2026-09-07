#import "TLApplicationPreferences.h"

/// Registers only the user's chosen combination with macOS, without monitoring keyboard input.
@interface TLGlobalShortcut : NSObject <TLGlobalShortcutRegistration>
@property (nonatomic, copy, nullable) void (^handler)(void);
@end
