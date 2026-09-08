#import "TLAttachmentPreviewPanel.h"

@implementation TLAttachmentPreviewPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }
- (void)cancelOperation:(id)sender { if (self.dismissHandler) self.dismissHandler(); }
- (void)sendEvent:(NSEvent *)event {
  if (event.type == NSEventTypeLeftMouseDown && !self.attachedSheet && self.isBackdropPoint && self.dismissHandler) {
    NSPoint point = [self.contentView convertPoint:event.locationInWindow fromView:nil];
    if (self.isBackdropPoint(point)) { self.dismissHandler(); return; }
  }
  [super sendEvent:event];
}
@end
