#import "TLScreenRegionSelectionView.h"

@implementation TLScreenRegionSelectionPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen { return frameRect; }
@end

@interface TLScreenRegionSelectionView ()
@property (nonatomic) NSPoint startPoint;
@property (nonatomic) NSRect selectionRect;
@property (nonatomic) BOOL selecting;
@end

@implementation TLScreenRegionSelectionView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.crosshairCursor]; }
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.needsDisplay = YES;
}
- (void)resetSelection {
  self.selecting = NO;
  self.selectionRect = NSZeroRect;
  self.needsDisplay = YES;
}
- (void)mouseDown:(NSEvent *)event {
  [self resetSelection];
  self.startPoint = [self convertPoint:event.locationInWindow fromView:nil];
  self.selecting = YES;
}
- (void)mouseDragged:(NSEvent *)event {
  if (!self.selecting) return;
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  NSRect rect = NSMakeRect(MIN(point.x, self.startPoint.x), MIN(point.y, self.startPoint.y),
    fabs(point.x - self.startPoint.x), fabs(point.y - self.startPoint.y));
  self.selectionRect = NSIntersectionRect(rect, self.bounds);
  self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event {
  if (!self.selecting) return;
  [self mouseDragged:event];
  self.selecting = NO;
  NSRect rect = self.selectionRect;
  if (NSWidth(rect) < self.palette.space3 || NSHeight(rect) < self.palette.space3) {
    [self resetSelection];
    if (self.cancelHandler) self.cancelHandler();
    return;
  }
  NSRect screenRect = [self.window convertRectToScreen:[self convertRect:rect toView:nil]];
  if (self.selectionHandler) self.selectionHandler(screenRect);
}
- (void)cancelOperation:(id)sender {
  [self resetSelection];
  if (self.cancelHandler) self.cancelHandler();
}
- (void)drawRect:(NSRect)dirtyRect {
  [self.palette.transparentSurface setFill];
  NSRectFillUsingOperation(self.bounds, NSCompositingOperationCopy);
  if (!NSIsEmptyRect(self.selectionRect)) {
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:self.selectionRect];
    border.lineWidth = self.palette.borderWidth * 3;
    [self.palette.notchOverlaySurface setStroke];
    [border stroke];
    border.lineWidth = self.palette.borderWidth;
    [self.palette.notchOverlayText setStroke];
    [border stroke];
  }
}
@end
