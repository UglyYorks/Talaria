#import "TLQuickInputPanel.h"

@implementation TLQuickInputPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)cancelOperation:(id)sender {
  if (self.dismissHandler) self.dismissHandler();
}
@end
