#import "TLMainWindow.h"
#import <math.h>

@interface TLMainWindow ()

@property (nonatomic) CGFloat guardedAccessibilityWidth;
@property (nonatomic) NSInteger guardedAccessibilityPasses;

@end

@implementation TLMainWindow

- (void)restorePlacementWithName:(NSString *)name {
  [self setFrameUsingName:name];
  // AppKit's frame restoration tracks the original screen and adjusts when
  // displays change. Constrain once more so the title bar remains reachable.
  NSScreen *screen = self.screen ?: NSScreen.mainScreen;
  if (screen) [self setFrame:[self constrainFrameRect:self.frame toScreen:screen] display:NO];
  [self setFrameAutosaveName:name];
}


- (void)setFrame:(NSRect)frameRect display:(BOOL)displayFlag {
  BOOL shouldKeepAccessibilityWidth = self.guardedAccessibilityPasses > 0 &&
    self.guardedAccessibilityWidth > 0.0 &&
    fabs(frameRect.size.width - self.guardedAccessibilityWidth) > 0.5 &&
    frameRect.size.width >= self.minSize.width;
  if (shouldKeepAccessibilityWidth) {
    frameRect.size.width = self.guardedAccessibilityWidth;
    self.guardedAccessibilityPasses -= 1;
  } else if (self.guardedAccessibilityPasses <= 0) {
    self.guardedAccessibilityWidth = 0.0;
  }

  [super setFrame:frameRect display:displayFlag];
}

- (void)setAccessibilityFrame:(NSRect)accessibilityFrame {
  self.guardedAccessibilityWidth = MAX(self.minSize.width, accessibilityFrame.size.width);
  self.guardedAccessibilityPasses = 2;
  [self setFrame:accessibilityFrame display:YES];
}

- (void)accessibilitySetValue:(id)value forAttribute:(NSAccessibilityAttributeName)attribute {
  if ([attribute isEqualToString:NSAccessibilitySizeAttribute] && [value respondsToSelector:@selector(sizeValue)]) {
    NSSize requestedSize = [value sizeValue];
    NSRect frame = self.frame;
    requestedSize.width = MAX(self.minSize.width, requestedSize.width);
    requestedSize.height = MAX(self.minSize.height, requestedSize.height);
    frame.origin.y = NSMaxY(frame) - requestedSize.height;
    frame.size = requestedSize;
    self.guardedAccessibilityWidth = requestedSize.width;
    self.guardedAccessibilityPasses = 2;
    [self setFrame:frame display:YES];
    return;
  }

  [super accessibilitySetValue:value forAttribute:attribute];
}

@end
