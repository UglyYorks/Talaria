#import "TLAttachmentPreviewPanel.h"

@implementation TLAttachmentPreviewPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }
- (void)cancelOperation:(id)sender { if (self.dismissHandler) self.dismissHandler(); }
@end
