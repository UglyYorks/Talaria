#import <AppKit/AppKit.h>

static inline void TLChromiumDeferToMainRunLoop(dispatch_block_t block) {
  // NSTerminateLater uses a modal run loop that does not drain the main GCD queue.
  CFRunLoopPerformBlock(CFRunLoopGetMain(), (__bridge CFArrayRef)@[
    NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode,
  ], block);
  CFRunLoopWakeUp(CFRunLoopGetMain());
}
