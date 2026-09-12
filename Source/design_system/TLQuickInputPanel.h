#import <AppKit/AppKit.h>

// A keyboard-capable notch panel that does not activate the app's other windows.
@interface TLQuickInputPanel : NSPanel
@property (nonatomic, copy) void (^dismissHandler)(void);
@end
