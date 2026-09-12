#import "TLQuickInputPanel.h"

@implementation TLQuickInputPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {
  // The notch must reach the physical screen edge, including the menu bar.
  return frameRect;
}
- (void)cancelOperation:(id)sender {
  if (self.dismissHandler) self.dismissHandler();
}
@end
