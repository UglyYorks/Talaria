#import <AppKit/AppKit.h>
#import "TLScreenCapture.h"

// Optional native integration check; requires existing Screen Recording access.
static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void Drain(void) {
  [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static NSBitmapImageRep *Capture(TLScreenCapture *capture, NSRect rect, NSArray<NSNumber *> *excluded) {
  __block BOOL finished = NO;
  __block NSBitmapImageRep *bitmap;
  __block NSError *failure;
  [capture captureRect:rect excludingWindowIDs:excluded completion:^(NSURL *URL, NSError *error) {
    failure = error;
    if (URL) bitmap = [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfURL:URL]];
    finished = YES;
  }];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
  while (!finished && deadline.timeIntervalSinceNow > 0) Drain();
  Check(finished && bitmap != nil, [NSString stringWithFormat:@"native capture completes: %@", failure]);
  return bitmap;
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    if (!CGPreflightScreenCaptureAccess()) {
      NSLog(@"ScreenCaptureTests requires existing Screen Recording access; no permission was requested.");
      return 77;
    }
    for (NSScreen *screen in NSScreen.screens) {
      NSRect rect = NSMakeRect(NSMidX(screen.frame) - 100, NSMidY(screen.frame) - 60, 200, 120);
      NSPanel *background = [[NSPanel alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless
        backing:NSBackingStoreBuffered defer:NO];
      background.backgroundColor = NSColor.greenColor;
      background.opaque = YES;
      background.hasShadow = NO;
      background.level = NSStatusWindowLevel + 3;
      [background orderFrontRegardless];
      NSPanel *overlay = [[NSPanel alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless
        backing:NSBackingStoreBuffered defer:NO];
      overlay.backgroundColor = NSColor.redColor;
      overlay.opaque = YES;
      overlay.hasShadow = NO;
      overlay.level = background.level + 1;
      [overlay orderFrontRegardless];
      [background display];
      [overlay display];
      [NSApp activateIgnoringOtherApps:YES];
      for (NSUInteger index = 0; index < 4; index++) Drain();

      TLScreenCapture *capture = [[TLScreenCapture alloc] init];
      NSRect region = NSInsetRect(rect, 30, 20);
      NSBitmapImageRep *included = Capture(capture, region, @[]);
      NSColor *red = [[included colorAtX:included.pixelsWide / 2 y:included.pixelsHigh / 2]
        colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      [[included representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:@"/tmp/talaria-capture-included.png" atomically:YES];
      Check(red.redComponent > red.greenComponent + 0.4 && red.redComponent > red.blueComponent + 0.4,
        [NSString stringWithFormat:@"unfiltered capture includes foreground fixture (color %@, screen %@, overlay %@, region %@)",
          red, NSStringFromRect(screen.frame), NSStringFromRect(overlay.frame), NSStringFromRect(region)]);
      NSRect before = overlay.frame;
      NSBitmapImageRep *excluded = Capture(capture, region, @[@(overlay.windowNumber)]);
      NSColor *green = [[excluded colorAtX:excluded.pixelsWide / 2 y:excluded.pixelsHigh / 2]
        colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
      Check(green.greenComponent > green.redComponent + 0.4 && green.greenComponent > green.blueComponent + 0.4,
        @"excluding a visible overlay captures the real pixels underneath");
      Check(overlay.visible && overlay.alphaValue == 1 && NSEqualRects(overlay.frame, before),
        @"native capture does not hide, fade, or move the excluded window");
      Check(excluded.pixelsWide == lround(NSWidth(region) * screen.backingScaleFactor) &&
        excluded.pixelsHigh == lround(NSHeight(region) * screen.backingScaleFactor),
        @"capture crops the selected display region at its native pixel scale");
      __block BOOL cancelledDelivered = NO;
      [capture captureRect:region excludingWindowIDs:@[@(overlay.windowNumber)] completion:^(NSURL *URL, NSError *error) {
        cancelledDelivered = YES;
      }];
      [capture cancel];
      for (NSUInteger index = 0; index < 10; index++) Drain();
      Check(!cancelledDelivered, @"cancelled capture does not deliver a stale attachment");
      [overlay orderOut:nil];
      [background orderOut:nil];
    }
    NSLog(@"ScreenCaptureTests passed");
  }
  return 0;
}
