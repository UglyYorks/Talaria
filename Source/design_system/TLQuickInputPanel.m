#import "TLQuickInputPanel.h"

@implementation TLQuickInputPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen {
  return self.pinsToScreenTop ? frameRect : [super constrainFrameRect:frameRect toScreen:screen];
}
- (void)cancelOperation:(id)sender {
  if (self.dismissHandler) self.dismissHandler();
}
@end
