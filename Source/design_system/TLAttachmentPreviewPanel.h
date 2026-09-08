#import <AppKit/AppKit.h>

// A screen-sized overlay, without moving the app into a separate fullscreen Space.
@interface TLAttachmentPreviewPanel : NSPanel
@property (nonatomic, copy) void (^dismissHandler)(void);
// Points are in content-view coordinates. Content and controls can opt out.
@property (nonatomic, copy) BOOL (^isBackdropPoint)(NSPoint point);
@end
