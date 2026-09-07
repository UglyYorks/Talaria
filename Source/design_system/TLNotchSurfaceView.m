#import "TLNotchSurfaceView.h"

NSBezierPath *TLNotchSurfacePath(NSRect rect, TLThemePalette *palette) {
  CGFloat flareOutset = MIN(palette.notchOverlayTopFlareOutset, rect.size.width * 0.24);
  CGFloat bodyWidth = MAX(0.0, rect.size.width - (flareOutset * 2.0));
  CGFloat flareHeight = MIN(palette.notchOverlayTopFlareHeight, rect.size.height);
  CGFloat bodyHeight = rect.size.height;
  CGFloat radius = MIN(palette.notchOverlayCornerRadius, MIN(bodyWidth * 0.5, bodyHeight * 0.5));
  CGFloat flareRadius = MIN(flareOutset, flareHeight);
  CGFloat topY = NSMaxY(rect);
  CGFloat bottomY = NSMinY(rect);
  CGFloat leftTopX = NSMinX(rect);
  CGFloat rightTopX = NSMaxX(rect);
  CGFloat leftBodyX = leftTopX + flareOutset;
  CGFloat rightBodyX = rightTopX - flareOutset;
  CGFloat leftArcTopX = leftBodyX - flareRadius;
  CGFloat rightArcTopX = rightBodyX + flareRadius;
  NSBezierPath *path = [NSBezierPath bezierPath];

  [path moveToPoint:NSMakePoint(leftArcTopX, topY)];
  [path lineToPoint:NSMakePoint(rightArcTopX, topY)];
  [path appendBezierPathWithArcWithCenter:NSMakePoint(rightArcTopX, topY - flareRadius)
                                   radius:flareRadius
                               startAngle:90.0
                                 endAngle:180.0
                                clockwise:NO];
  [path lineToPoint:NSMakePoint(rightBodyX, bottomY + radius)];
  [path appendBezierPathWithArcFromPoint:NSMakePoint(rightBodyX, bottomY)
                                 toPoint:NSMakePoint(rightBodyX - radius, bottomY)
                                  radius:radius];
  [path lineToPoint:NSMakePoint(leftBodyX + radius, bottomY)];
  [path appendBezierPathWithArcFromPoint:NSMakePoint(leftBodyX, bottomY)
                                 toPoint:NSMakePoint(leftBodyX, bottomY + radius)
                                  radius:radius];
  [path lineToPoint:NSMakePoint(leftBodyX, topY - flareRadius)];
  [path appendBezierPathWithArcWithCenter:NSMakePoint(leftArcTopX, topY - flareRadius)
                                   radius:flareRadius
                               startAngle:0.0
                                 endAngle:90.0
                                clockwise:NO];
  [path closePath];

  return path;
}

@implementation TLNotchSurfaceView
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  [self.palette.notchOverlaySurface setFill];
  [TLNotchSurfacePath(self.bounds, self.palette) fill];
}
@end
