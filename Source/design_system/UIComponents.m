#import "UIComponents.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <math.h>

static const NSTimeInterval TLUrgentNotificationPulseDuration = 1.8;
static const NSTimeInterval TLUrgentNotificationFrameInterval = 1.0 / 60.0;

static CGFloat TLResolvedCornerRadius(CGFloat overrideRadius, CGFloat fallbackRadius) {
  return overrideRadius >= 0.0 ? overrideRadius : fallbackRadius;
}

static CGFloat TLClampedCornerRadius(CGFloat radius, NSRect rect) {
  return MIN(MAX(0.0, radius), MIN(NSWidth(rect), NSHeight(rect)) * 0.5);
}

static CGPathRef TLCreateRoundedRectPath(NSRect rect,
                                         CGFloat topLeftRadius,
                                         CGFloat topRightRadius,
                                         CGFloat bottomRightRadius,
                                         CGFloat bottomLeftRadius) {
  CGFloat minX = NSMinX(rect);
  CGFloat maxX = NSMaxX(rect);
  CGFloat minY = NSMinY(rect);
  CGFloat maxY = NSMaxY(rect);
  CGFloat kappa = 0.5522847498307936;
  CGMutablePathRef path = CGPathCreateMutable();

  CGPathMoveToPoint(path, NULL, minX + bottomLeftRadius, minY);
  CGPathAddLineToPoint(path, NULL, maxX - bottomRightRadius, minY);
  if (bottomRightRadius > 0.0) {
    CGPathAddCurveToPoint(path, NULL,
                          maxX - bottomRightRadius + bottomRightRadius * kappa, minY,
                          maxX, minY + bottomRightRadius - bottomRightRadius * kappa,
                          maxX, minY + bottomRightRadius);
  } else {
    CGPathAddLineToPoint(path, NULL, maxX, minY);
  }

  CGPathAddLineToPoint(path, NULL, maxX, maxY - topRightRadius);
  if (topRightRadius > 0.0) {
    CGPathAddCurveToPoint(path, NULL,
                          maxX, maxY - topRightRadius + topRightRadius * kappa,
                          maxX - topRightRadius + topRightRadius * kappa, maxY,
                          maxX - topRightRadius, maxY);
  } else {
    CGPathAddLineToPoint(path, NULL, maxX, maxY);
  }

  CGPathAddLineToPoint(path, NULL, minX + topLeftRadius, maxY);
  if (topLeftRadius > 0.0) {
    CGPathAddCurveToPoint(path, NULL,
                          minX + topLeftRadius - topLeftRadius * kappa, maxY,
                          minX, maxY - topLeftRadius + topLeftRadius * kappa,
                          minX, maxY - topLeftRadius);
  } else {
    CGPathAddLineToPoint(path, NULL, minX, maxY);
  }

  CGPathAddLineToPoint(path, NULL, minX, minY + bottomLeftRadius);
  if (bottomLeftRadius > 0.0) {
    CGPathAddCurveToPoint(path, NULL,
                          minX, minY + bottomLeftRadius - bottomLeftRadius * kappa,
                          minX + bottomLeftRadius - bottomLeftRadius * kappa, minY,
                          minX + bottomLeftRadius, minY);
  } else {
    CGPathAddLineToPoint(path, NULL, minX, minY);
  }

  CGPathCloseSubpath(path);
  return path;
}

static NSBezierPath *TLCreateRoundedRectBezierPath(NSRect rect,
                                                   CGFloat topLeftRadius,
                                                   CGFloat topRightRadius,
                                                   CGFloat bottomRightRadius,
                                                   CGFloat bottomLeftRadius) {
  CGFloat minX = NSMinX(rect);
  CGFloat maxX = NSMaxX(rect);
  CGFloat minY = NSMinY(rect);
  CGFloat maxY = NSMaxY(rect);
  CGFloat kappa = 0.5522847498307936;
  NSBezierPath *path = [NSBezierPath bezierPath];

  [path moveToPoint:NSMakePoint(minX + bottomLeftRadius, minY)];
  [path lineToPoint:NSMakePoint(maxX - bottomRightRadius, minY)];
  if (bottomRightRadius > 0.0) {
    [path curveToPoint:NSMakePoint(maxX, minY + bottomRightRadius)
         controlPoint1:NSMakePoint(maxX - bottomRightRadius + bottomRightRadius * kappa, minY)
         controlPoint2:NSMakePoint(maxX, minY + bottomRightRadius - bottomRightRadius * kappa)];
  } else {
    [path lineToPoint:NSMakePoint(maxX, minY)];
  }

  [path lineToPoint:NSMakePoint(maxX, maxY - topRightRadius)];
  if (topRightRadius > 0.0) {
    [path curveToPoint:NSMakePoint(maxX - topRightRadius, maxY)
         controlPoint1:NSMakePoint(maxX, maxY - topRightRadius + topRightRadius * kappa)
         controlPoint2:NSMakePoint(maxX - topRightRadius + topRightRadius * kappa, maxY)];
  } else {
    [path lineToPoint:NSMakePoint(maxX, maxY)];
  }

  [path lineToPoint:NSMakePoint(minX + topLeftRadius, maxY)];
  if (topLeftRadius > 0.0) {
    [path curveToPoint:NSMakePoint(minX, maxY - topLeftRadius)
         controlPoint1:NSMakePoint(minX + topLeftRadius - topLeftRadius * kappa, maxY)
         controlPoint2:NSMakePoint(minX, maxY - topLeftRadius + topLeftRadius * kappa)];
  } else {
    [path lineToPoint:NSMakePoint(minX, maxY)];
  }

  [path lineToPoint:NSMakePoint(minX, minY + bottomLeftRadius)];
  if (bottomLeftRadius > 0.0) {
    [path curveToPoint:NSMakePoint(minX + bottomLeftRadius, minY)
         controlPoint1:NSMakePoint(minX, minY + bottomLeftRadius - bottomLeftRadius * kappa)
         controlPoint2:NSMakePoint(minX + bottomLeftRadius - bottomLeftRadius * kappa, minY)];
  } else {
    [path lineToPoint:NSMakePoint(minX, minY)];
  }

  [path closePath];
  return path;
}

static CGFloat TLMessageBubbleBodyRadius(CGFloat requestedRadius, NSRect bodyRect, BOOL rendersAsPill) {
  if (rendersAsPill) {
    return MAX(0.0, NSHeight(bodyRect) * 0.5);
  }

  return TLClampedCornerRadius(requestedRadius, bodyRect);
}

static NSBezierPath *TLCreateMessageBubbleBezierPath(NSRect rect, CGFloat requestedRadius, BOOL rendersAsPill) {
  CGFloat radius = TLMessageBubbleBodyRadius(requestedRadius, rect, rendersAsPill);
  return TLCreateRoundedRectBezierPath(rect, radius, radius, radius, radius);
}

static CGPathRef TLCreateMessageBubblePath(NSRect rect, CGFloat requestedRadius, BOOL rendersAsPill) {
  CGFloat radius = TLMessageBubbleBodyRadius(requestedRadius, rect, rendersAsPill);
  return TLCreateRoundedRectPath(rect, radius, radius, radius, radius);
}

static const CGFloat TLMessageBubbleTailDropScale = 0.20;
static const CGFloat TLMessageBubbleTailTipInsetScale = 0.32;
static const CGFloat TLMessageBubbleTailRightJoinWidthScale = 0.30;
static const CGFloat TLMessageBubbleTailRightJoinRadiusScale = 0.45;
static const CGFloat TLMessageBubbleTailEndHeightScale = 0.72;
static const CGFloat TLMessageBubbleTailTipRadiusScale = 0.22;
static const CGFloat TLMessageBubbleTailTipRadiusTokenScale = 0.1;
static const CGFloat TLMessageBubbleTailTipStartXScale = 0.80;
static const CGFloat TLMessageBubbleTailTipStartYScale = 0.12;
static const CGFloat TLMessageBubbleTailTipEndXScale = 0.10;
static const CGFloat TLMessageBubbleTailTipEndYScale = 0.82;
static const CGFloat TLMessageBubbleTailLeadingControlXScale = 0.52;
static const CGFloat TLMessageBubbleTailLeadingControlDropScale = 0.12;
static const CGFloat TLMessageBubbleTailLeadingControlToTipXScale = 0.44;
static const CGFloat TLMessageBubbleTailLeadingControlToTipYScale = 0.18;
static const CGFloat TLMessageBubbleTailTipControl1XScale = 0.36;
static const CGFloat TLMessageBubbleTailTipControl2XScale = 0.08;
static const CGFloat TLMessageBubbleTailTipControl2YScale = 0.28;
static const CGFloat TLMessageBubbleTailTrailingControlXScale = 0.10;
static const CGFloat TLMessageBubbleTailTrailingControlYScale = 0.22;
static const CGFloat TLMessageBubbleTailTrailingControlToEndXScale = 0.28;
static const CGFloat TLMessageBubbleTailTrailingControlToEndYScale = 0.30;

typedef struct {
  BOOL valid;
  CGPoint start;
  CGPoint leadingControl1;
  CGPoint leadingControl2;
  CGPoint tipStart;
  CGPoint tipControl1;
  CGPoint tipControl2;
  CGPoint tipEnd;
  CGPoint trailingControl1;
  CGPoint trailingControl2;
  CGPoint end;
} TLMessageBubbleTailGeometry;

static NSPoint TLNSPointFromCGPoint(CGPoint point) {
  return NSMakePoint(point.x, point.y);
}

static CGFloat TLMessageBubbleTailDrop(TLThemePalette *palette, NSRect bounds) {
  return MIN(palette.space4, NSHeight(bounds) * TLMessageBubbleTailDropScale);
}

static CGFloat TLMessageBubbleTailWidth(TLThemePalette *palette) {
  return palette.space11;
}

static CGFloat TLMessageBubbleTailBaseWidth(TLThemePalette *palette) {
  return palette.space10;
}

static NSRect TLMessageBubbleBodyRectForBounds(TLThemePalette *palette, NSRect bounds) {
  CGFloat tailDrop = TLMessageBubbleTailDrop(palette, bounds);
  NSRect bodyRect = bounds;
  bodyRect.origin.y += tailDrop;
  bodyRect.size.height = MAX(palette.space0, NSHeight(bounds) - tailDrop);
  return bodyRect;
}

static TLMessageBubbleTailGeometry TLMessageBubbleTailGeometryForBounds(NSRect bounds,
                                                                        NSRect bodyRect,
                                                                        TLThemePalette *palette,
                                                                        CGFloat bodyRadius,
                                                                        CGFloat horizontalOffset) {
  TLMessageBubbleTailGeometry geometry = {0};
  CGFloat tailDrop = NSMinY(bodyRect) - NSMinY(bounds);
  CGFloat tailWidth = TLMessageBubbleTailWidth(palette);
  if (tailDrop <= palette.borderWidth * 0.5 || tailWidth <= palette.borderWidth * 0.5) {
    return geometry;
  }

  CGFloat effectiveRadius = MIN(MAX(palette.space0, bodyRadius), NSWidth(bodyRect) * 0.5);
  CGFloat bodyMaxX = NSMaxX(bodyRect);
  CGFloat bodyMinX = NSMinX(bodyRect);
  CGFloat bodyMinY = NSMinY(bodyRect);
  CGFloat baseWidth = TLMessageBubbleTailBaseWidth(palette);
  CGFloat tailTipInset = MIN(palette.space4, tailWidth * TLMessageBubbleTailTipInsetScale);
  CGFloat rightJoinInset = MIN(tailWidth * TLMessageBubbleTailRightJoinWidthScale,
                               effectiveRadius * TLMessageBubbleTailRightJoinRadiusScale);
  CGFloat tailEndX = bodyMaxX - rightJoinInset + horizontalOffset;
  CGFloat leftJoinX = MAX(bodyMinX + effectiveRadius, tailEndX - baseWidth);
  CGFloat joinY = bodyMinY + palette.borderWidth * 0.75;
  CGFloat tipRadius = MIN(palette.borderWidth + palette.space2 * TLMessageBubbleTailTipRadiusTokenScale,
                          tailDrop * TLMessageBubbleTailTipRadiusScale);

  CGPoint tip = CGPointMake(bodyMaxX - tailTipInset + horizontalOffset,
                            NSMinY(bounds) + palette.borderWidth * 0.5);
  geometry.valid = YES;
  geometry.start = CGPointMake(leftJoinX, joinY);
  geometry.tipStart = CGPointMake(tip.x - tipRadius * TLMessageBubbleTailTipStartXScale,
                                  tip.y + tipRadius * TLMessageBubbleTailTipStartYScale);
  geometry.tipControl1 = CGPointMake(tip.x - tipRadius * TLMessageBubbleTailTipControl1XScale, tip.y);
  geometry.tipControl2 = CGPointMake(tip.x - tipRadius * TLMessageBubbleTailTipControl2XScale,
                                     tip.y + tipRadius * TLMessageBubbleTailTipControl2YScale);
  geometry.tipEnd = CGPointMake(tip.x - tipRadius * TLMessageBubbleTailTipEndXScale,
                                tip.y + tipRadius * TLMessageBubbleTailTipEndYScale);
  geometry.end = CGPointMake(tailEndX, bodyMinY + tailDrop * TLMessageBubbleTailEndHeightScale);
  geometry.leadingControl1 = CGPointMake(geometry.start.x + tailWidth * TLMessageBubbleTailLeadingControlXScale,
                                         geometry.start.y - tailDrop * TLMessageBubbleTailLeadingControlDropScale);
  geometry.leadingControl2 = CGPointMake(tip.x - tailWidth * TLMessageBubbleTailLeadingControlToTipXScale,
                                         tip.y + tailDrop * TLMessageBubbleTailLeadingControlToTipYScale);
  geometry.trailingControl1 = CGPointMake(geometry.tipEnd.x - tailWidth * TLMessageBubbleTailTrailingControlXScale,
                                          geometry.tipEnd.y + tailDrop * TLMessageBubbleTailTrailingControlYScale);
  geometry.trailingControl2 = CGPointMake(geometry.end.x - tailWidth * TLMessageBubbleTailTrailingControlToEndXScale,
                                          geometry.end.y - tailDrop * TLMessageBubbleTailTrailingControlToEndYScale);
  return geometry;
}

static NSBezierPath *TLCreateOutgoingTailBezierPath(NSRect bounds,
                                                    NSRect bodyRect,
                                                    TLThemePalette *palette,
                                                    CGFloat bodyRadius,
                                                    CGFloat horizontalOffset) {
  TLMessageBubbleTailGeometry geometry = TLMessageBubbleTailGeometryForBounds(bounds,
                                                                              bodyRect,
                                                                              palette,
                                                                              bodyRadius,
                                                                              horizontalOffset);
  NSBezierPath *path = [NSBezierPath bezierPath];
  if (!geometry.valid) {
    return path;
  }

  [path moveToPoint:TLNSPointFromCGPoint(geometry.start)];
  [path curveToPoint:TLNSPointFromCGPoint(geometry.tipStart)
       controlPoint1:TLNSPointFromCGPoint(geometry.leadingControl1)
       controlPoint2:TLNSPointFromCGPoint(geometry.leadingControl2)];
  [path curveToPoint:TLNSPointFromCGPoint(geometry.tipEnd)
       controlPoint1:TLNSPointFromCGPoint(geometry.tipControl1)
       controlPoint2:TLNSPointFromCGPoint(geometry.tipControl2)];
  [path curveToPoint:TLNSPointFromCGPoint(geometry.end)
       controlPoint1:TLNSPointFromCGPoint(geometry.trailingControl1)
       controlPoint2:TLNSPointFromCGPoint(geometry.trailingControl2)];
  [path lineToPoint:TLNSPointFromCGPoint(geometry.start)];
  [path closePath];
  return path;
}

static CGPathRef TLCreateOutgoingTailPath(NSRect bounds,
                                          NSRect bodyRect,
                                          TLThemePalette *palette,
                                          CGFloat bodyRadius,
                                          CGFloat horizontalOffset) {
  TLMessageBubbleTailGeometry geometry = TLMessageBubbleTailGeometryForBounds(bounds,
                                                                              bodyRect,
                                                                              palette,
                                                                              bodyRadius,
                                                                              horizontalOffset);
  CGMutablePathRef path = CGPathCreateMutable();
  if (!geometry.valid) {
    return path;
  }

  CGPathMoveToPoint(path, NULL, geometry.start.x, geometry.start.y);
  CGPathAddCurveToPoint(path, NULL,
                        geometry.leadingControl1.x, geometry.leadingControl1.y,
                        geometry.leadingControl2.x, geometry.leadingControl2.y,
                        geometry.tipStart.x, geometry.tipStart.y);
  CGPathAddCurveToPoint(path, NULL,
                        geometry.tipControl1.x, geometry.tipControl1.y,
                        geometry.tipControl2.x, geometry.tipControl2.y,
                        geometry.tipEnd.x, geometry.tipEnd.y);
  CGPathAddCurveToPoint(path, NULL,
                        geometry.trailingControl1.x, geometry.trailingControl1.y,
                        geometry.trailingControl2.x, geometry.trailingControl2.y,
                        geometry.end.x, geometry.end.y);
  CGPathAddLineToPoint(path, NULL, geometry.start.x, geometry.start.y);
  CGPathCloseSubpath(path);
  return path;
}

static NSColor *TLAverageVisibleImageColor(NSImage *image) {
  if (!image || image.size.width <= 0.0 || image.size.height <= 0.0) {
    return nil;
  }

  NSInteger sampleWidth = MAX(1, (NSInteger)MIN(32.0, ceil(image.size.width)));
  NSInteger sampleHeight = MAX(1, (NSInteger)MIN(32.0, ceil(image.size.height)));
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:sampleWidth
                                                                     pixelsHigh:sampleHeight
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
  if (!bitmap) {
    return nil;
  }

  NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:context];
  [image drawInRect:NSMakeRect(0.0, 0.0, sampleWidth, sampleHeight)
           fromRect:NSZeroRect
          operation:NSCompositingOperationCopy
           fraction:1.0
     respectFlipped:NO
              hints:nil];
  [NSGraphicsContext restoreGraphicsState];

  CGFloat redTotal = 0.0;
  CGFloat greenTotal = 0.0;
  CGFloat blueTotal = 0.0;
  CGFloat alphaTotal = 0.0;
  NSColorSpace *colorSpace = NSColorSpace.sRGBColorSpace;
  for (NSInteger y = 0; y < sampleHeight; y += 1) {
    for (NSInteger x = 0; x < sampleWidth; x += 1) {
      NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:colorSpace];
      if (!color) {
        continue;
      }

      CGFloat red = 0.0;
      CGFloat green = 0.0;
      CGFloat blue = 0.0;
      CGFloat alpha = 0.0;
      [color getRed:&red green:&green blue:&blue alpha:&alpha];
      if (alpha <= 0.02) {
        continue;
      }

      redTotal += red * alpha;
      greenTotal += green * alpha;
      blueTotal += blue * alpha;
      alphaTotal += alpha;
    }
  }

  if (alphaTotal <= 0.0) {
    return nil;
  }

  return [NSColor colorWithCalibratedRed:redTotal / alphaTotal
                                   green:greenTotal / alphaTotal
                                    blue:blueTotal / alphaTotal
                                   alpha:1.0];
}

@interface TLTokenView ()
- (void)updateLayerCornerGeometry;
@end

@implementation TLTokenView

- (instancetype)init {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _fillColor = palette.transparentSurface;
    _borderColor = palette.transparentSurface;
    _borderWidth = 1.0;
    _cornerRadius = 0.0;
    _topLeftCornerRadius = -1.0;
    _topRightCornerRadius = -1.0;
    _bottomRightCornerRadius = -1.0;
    _bottomLeftCornerRadius = -1.0;
    _borderEdges = TLBorderEdgeNone;
    _canDragWindow = NO;
  }
  return self;
}

- (void)setFillColor:(NSColor *)fillColor {
  _fillColor = fillColor;
  [self setNeedsDisplay:YES];
  [self.layer setNeedsDisplay];
}

- (void)setBorderColor:(NSColor *)borderColor {
  _borderColor = borderColor;
  [self setNeedsDisplay:YES];
  [self.layer setNeedsDisplay];
}

- (void)setBorderWidth:(CGFloat)borderWidth {
  _borderWidth = borderWidth;
  [self setNeedsDisplay:YES];
  [self.layer setNeedsDisplay];
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
  _cornerRadius = cornerRadius;
  [self invalidateCornerGeometry];
}

- (void)setTopLeftCornerRadius:(CGFloat)topLeftCornerRadius {
  _topLeftCornerRadius = topLeftCornerRadius;
  [self invalidateCornerGeometry];
}

- (void)setTopRightCornerRadius:(CGFloat)topRightCornerRadius {
  _topRightCornerRadius = topRightCornerRadius;
  [self invalidateCornerGeometry];
}

- (void)setBottomRightCornerRadius:(CGFloat)bottomRightCornerRadius {
  _bottomRightCornerRadius = bottomRightCornerRadius;
  [self invalidateCornerGeometry];
}

- (void)setBottomLeftCornerRadius:(CGFloat)bottomLeftCornerRadius {
  _bottomLeftCornerRadius = bottomLeftCornerRadius;
  [self invalidateCornerGeometry];
}

- (void)setBorderEdges:(TLBorderEdges)borderEdges {
  _borderEdges = borderEdges;
  [self setNeedsDisplay:YES];
  [self.layer setNeedsDisplay];
}

- (BOOL)mouseDownCanMoveWindow {
  return self.canDragWindow;
}

- (void)mouseDown:(NSEvent *)event {
  if (self.canDragWindow) {
    [self.window performWindowDragWithEvent:event];
    return;
  }

  [super mouseDown:event];
}

- (void)layout {
  [super layout];
  [self updateLayerCornerGeometry];
}

- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSColor *fillColor = self.fillColor ?: palette.transparentSurface;
  NSColor *borderColor = self.borderColor ?: palette.transparentSurface;
  [fillColor setFill];

  NSBezierPath *path = [self cornerPathForBounds:self.bounds];
  if (path) {
    [path fill];
  } else {
    NSRectFill(self.bounds);
  }

  [borderColor setFill];
  CGFloat width = self.borderWidth;
  if (self.borderEdges & TLBorderEdgeTop) {
    NSRectFill(NSMakeRect(0, self.bounds.size.height - width, self.bounds.size.width, width));
  }
  if (self.borderEdges & TLBorderEdgeRight) {
    NSRectFill(NSMakeRect(self.bounds.size.width - width, 0, width, self.bounds.size.height));
  }
  if (self.borderEdges & TLBorderEdgeBottom) {
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, width));
  }
  if (self.borderEdges & TLBorderEdgeLeft) {
    NSRectFill(NSMakeRect(0, 0, width, self.bounds.size.height));
  }
}

- (void)invalidateCornerGeometry {
  [self setNeedsDisplay:YES];
  [self setNeedsLayout:YES];
  [self updateLayerCornerGeometry];
}

- (BOOL)hasCustomCornerRadii {
  return self.topLeftCornerRadius >= 0.0 ||
    self.topRightCornerRadius >= 0.0 ||
    self.bottomRightCornerRadius >= 0.0 ||
    self.bottomLeftCornerRadius >= 0.0;
}

- (BOOL)hasAnyCornerRadius {
  return self.cornerRadius > 0.0 ||
    self.topLeftCornerRadius > 0.0 ||
    self.topRightCornerRadius > 0.0 ||
    self.bottomRightCornerRadius > 0.0 ||
    self.bottomLeftCornerRadius > 0.0;
}

- (void)resolvedTopLeftRadius:(CGFloat *)topLeftRadius
               topRightRadius:(CGFloat *)topRightRadius
            bottomRightRadius:(CGFloat *)bottomRightRadius
             bottomLeftRadius:(CGFloat *)bottomLeftRadius
                       inRect:(NSRect)rect {
  *topLeftRadius = TLClampedCornerRadius(TLResolvedCornerRadius(self.topLeftCornerRadius, self.cornerRadius), rect);
  *topRightRadius = TLClampedCornerRadius(TLResolvedCornerRadius(self.topRightCornerRadius, self.cornerRadius), rect);
  *bottomRightRadius = TLClampedCornerRadius(TLResolvedCornerRadius(self.bottomRightCornerRadius, self.cornerRadius), rect);
  *bottomLeftRadius = TLClampedCornerRadius(TLResolvedCornerRadius(self.bottomLeftCornerRadius, self.cornerRadius), rect);
}

- (nullable NSBezierPath *)cornerPathForBounds:(NSRect)bounds {
  if (NSIsEmptyRect(bounds) || ![self hasAnyCornerRadius]) {
    return nil;
  }

  CGFloat topLeftRadius = 0.0;
  CGFloat topRightRadius = 0.0;
  CGFloat bottomRightRadius = 0.0;
  CGFloat bottomLeftRadius = 0.0;
  [self resolvedTopLeftRadius:&topLeftRadius
               topRightRadius:&topRightRadius
            bottomRightRadius:&bottomRightRadius
             bottomLeftRadius:&bottomLeftRadius
                       inRect:bounds];

  return TLCreateRoundedRectBezierPath(bounds, topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius);
}

- (CGPathRef)newOutlinePath {
  CGFloat topLeft, topRight, bottomRight, bottomLeft;
  [self resolvedTopLeftRadius:&topLeft topRightRadius:&topRight
           bottomRightRadius:&bottomRight bottomLeftRadius:&bottomLeft inRect:self.bounds];
  return TLCreateRoundedRectPath(self.bounds, topLeft, topRight, bottomRight, bottomLeft);
}

- (void)updateLayerCornerGeometry {
  if (!self.layer) {
    return;
  }

  BOOL hasCustomCornerRadii = [self hasCustomCornerRadii];
  BOOL hasAnyCornerRadius = [self hasAnyCornerRadius];
  if (hasCustomCornerRadii) {
    self.layer.cornerRadius = 0.0;
  } else {
    self.layer.mask = nil;
    self.layer.cornerRadius = hasAnyCornerRadius ? self.cornerRadius : 0.0;
  }

  if (hasCustomCornerRadii && self.layer.masksToBounds && !NSIsEmptyRect(self.bounds)) {
    CGFloat topLeftRadius = 0.0;
    CGFloat topRightRadius = 0.0;
    CGFloat bottomRightRadius = 0.0;
    CGFloat bottomLeftRadius = 0.0;
    [self resolvedTopLeftRadius:&topLeftRadius
                 topRightRadius:&topRightRadius
              bottomRightRadius:&bottomRightRadius
               bottomLeftRadius:&bottomLeftRadius
                         inRect:self.bounds];
    CGPathRef maskPath = TLCreateRoundedRectPath(self.bounds, topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius);
    CAShapeLayer *maskLayer = [self.layer.mask isKindOfClass:CAShapeLayer.class] ? (CAShapeLayer *)self.layer.mask : [CAShapeLayer layer];
    maskLayer.frame = self.bounds;
    maskLayer.path = maskPath;
    self.layer.mask = maskLayer;
    CGPathRelease(maskPath);
  } else if (!hasCustomCornerRadii) {
    self.layer.mask = nil;
  }

  if ((hasCustomCornerRadii || hasAnyCornerRadius) && self.layer.shadowOpacity > 0.0 && !NSIsEmptyRect(self.bounds)) {
    CGFloat topLeftRadius = 0.0;
    CGFloat topRightRadius = 0.0;
    CGFloat bottomRightRadius = 0.0;
    CGFloat bottomLeftRadius = 0.0;
    [self resolvedTopLeftRadius:&topLeftRadius
                 topRightRadius:&topRightRadius
              bottomRightRadius:&bottomRightRadius
               bottomLeftRadius:&bottomLeftRadius
                         inRect:self.bounds];
    CGPathRef shadowPath = TLCreateRoundedRectPath(self.bounds, topLeftRadius, topRightRadius, bottomRightRadius, bottomLeftRadius);
    self.layer.shadowPath = shadowPath;
    CGPathRelease(shadowPath);
  } else {
    self.layer.shadowPath = nil;
  }
}

@end

@interface TLSlashCommandItemView ()
@property (nonatomic, strong) NSTextField *commandLabel;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) NSLayoutConstraint *descriptionLeadingConstraint;
@property (nonatomic, strong) NSImageView *commandIcon;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, getter=isHovered) BOOL hovered;
@end

@implementation TLSlashCommandItemView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _command = @"";
    _commandDescription = @"";
    _systemIconName = @"text.bubble";
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityButtonRole;

    _commandLabel = [NSTextField labelWithString:@""];
    _commandLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _commandLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_commandLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    _descriptionLabel = [NSTextField labelWithString:@""];
    _descriptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descriptionLabel.usesSingleLineMode = YES;
    [_descriptionLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _commandIcon = [[NSImageView alloc] init];
    _commandIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _commandIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_commandIcon];
    [self addSubview:_commandLabel];
    [self addSubview:_descriptionLabel];
    _descriptionLeadingConstraint = [_descriptionLabel.leadingAnchor constraintEqualToAnchor:_commandLabel.trailingAnchor];
    [NSLayoutConstraint activateConstraints:@[
      [_commandIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_palette.space8],
      [_commandIcon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      [_commandIcon.widthAnchor constraintEqualToConstant:_palette.sidebarActionIconSize],
      [_commandIcon.heightAnchor constraintEqualToConstant:_palette.sidebarActionIconSize],
      [_commandLabel.leadingAnchor constraintEqualToAnchor:_commandIcon.trailingAnchor constant:_palette.space4],
      _descriptionLeadingConstraint,
      [_descriptionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-_palette.space8],
      [_descriptionLabel.firstBaselineAnchor constraintEqualToAnchor:_commandLabel.firstBaselineAnchor],
      [_commandLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
    [self applyCurrentState];
  }
  return self;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }
  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited |
                                                           NSTrackingActiveAlways |
                                                           NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  [self applyCurrentState];
}

- (void)mouseDown:(NSEvent *)event {
  if (self.enabled && self.target && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setCommand:(NSString *)command {
  _command = [command copy] ?: @"";
  self.commandLabel.stringValue = _command;
  self.accessibilityLabel = _command;
  [self applyCurrentState];
}

- (void)setSelected:(BOOL)selected {
  _selected = selected;
  self.accessibilitySelected = selected;
  [self applyCurrentState];
}

- (void)setCommandDescription:(NSString *)commandDescription {
  _commandDescription = [commandDescription copy] ?: @"";
  self.descriptionLabel.stringValue = _commandDescription;
  self.accessibilityHelp = _commandDescription;
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy];
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

- (void)applyCurrentState {
  BOOL highlighted = self.enabled && (self.isSelected || (!self.selectionManagedExternally && self.isHovered));
  self.layer.backgroundColor = TLCGColor(highlighted
    ? self.palette.slashCommandItemHighlightedSurface
    : self.palette.slashCommandItemSurface);
  self.layer.cornerRadius = self.palette.slashCommandListCornerRadius;
  self.layer.masksToBounds = YES;
  self.commandLabel.font = self.palette.bodyFont;
  self.descriptionLabel.font = self.palette.bodyFont;
  self.descriptionLabel.textColor = self.palette.textMuted;
  self.descriptionLeadingConstraint.constant = self.commandDescription.length ? self.palette.space6 : self.palette.space0;
  self.commandLabel.textColor = highlighted
    ? self.palette.slashCommandItemHighlightedText
    : self.palette.slashCommandItemText;
  self.commandIcon.image = [NSImage imageWithSystemSymbolName:self.systemIconName accessibilityDescription:nil];
  self.commandIcon.contentTintColor = self.commandLabel.textColor;
  self.alphaValue = self.enabled ? 1.0 : self.palette.disabledOpacity;
}

@end

@implementation TLMessageBubbleView

- (instancetype)init {
  self = [super init];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _drawsOutgoingTail = NO;
    _rendersAsPill = NO;
    _outgoingTailHorizontalOffset = 0.0;
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self setNeedsDisplay:YES];
  [self setNeedsLayout:YES];
  [self updateLayerCornerGeometry];
}

- (void)setDrawsOutgoingTail:(BOOL)drawsOutgoingTail {
  _drawsOutgoingTail = drawsOutgoingTail;
  [self setNeedsDisplay:YES];
  [self setNeedsLayout:YES];
  [self updateLayerCornerGeometry];
}

- (void)setRendersAsPill:(BOOL)rendersAsPill {
  _rendersAsPill = rendersAsPill;
  [self setNeedsDisplay:YES];
  [self setNeedsLayout:YES];
  [self updateLayerCornerGeometry];
}

- (void)setOutgoingTailHorizontalOffset:(CGFloat)outgoingTailHorizontalOffset {
  _outgoingTailHorizontalOffset = outgoingTailHorizontalOffset;
  [self setNeedsDisplay:YES];
  [self setNeedsLayout:YES];
  [self updateLayerCornerGeometry];
}

- (void)drawRect:(NSRect)dirtyRect {
  if (!self.drawsOutgoingTail) {
    if (self.cornerRadius > 0.0 && !NSIsEmptyRect(self.bounds)) {
      NSBezierPath *path = TLCreateMessageBubbleBezierPath(self.bounds, self.cornerRadius, self.rendersAsPill);
      [self.fillColor setFill];
      [path fill];
      return;
    }

    [super drawRect:dirtyRect];
    return;
  }

  NSBezierPath *path = [self outgoingBubblePathForBounds:self.bounds];
  [self.fillColor setFill];
  [path fill];
}

- (NSBezierPath *)outgoingBubblePathForBounds:(NSRect)bounds {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if (NSIsEmptyRect(bounds)) {
    return [NSBezierPath bezierPath];
  }

  NSRect bodyRect = TLMessageBubbleBodyRectForBounds(palette, bounds);
  CGFloat radius = TLMessageBubbleBodyRadius(self.cornerRadius, bodyRect, self.rendersAsPill);
  NSBezierPath *path = TLCreateMessageBubbleBezierPath(bodyRect, self.cornerRadius, self.rendersAsPill);
  [path appendBezierPath:TLCreateOutgoingTailBezierPath(bounds,
                                                        bodyRect,
                                                        palette,
                                                        radius,
                                                        self.outgoingTailHorizontalOffset)];
  return path;
}

- (CGPathRef)newOutgoingBubbleCGPathForBounds:(NSRect)bounds CF_RETURNS_RETAINED {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if (NSIsEmptyRect(bounds)) {
    return CGPathCreateMutable();
  }

  NSRect bodyRect = TLMessageBubbleBodyRectForBounds(palette, bounds);
  CGMutablePathRef path = CGPathCreateMutable();
  CGFloat radius = TLMessageBubbleBodyRadius(self.cornerRadius, bodyRect, self.rendersAsPill);
  CGPathRef bodyPath = TLCreateMessageBubblePath(bodyRect, self.cornerRadius, self.rendersAsPill);
  CGPathRef tailPath = TLCreateOutgoingTailPath(bounds,
                                                bodyRect,
                                                palette,
                                                radius,
                                                self.outgoingTailHorizontalOffset);
  CGPathAddPath(path, NULL, bodyPath);
  CGPathAddPath(path, NULL, tailPath);
  CGPathRelease(bodyPath);
  CGPathRelease(tailPath);
  return path;
}

- (void)updateLayerCornerGeometry {
  [super updateLayerCornerGeometry];

  if (!self.layer) {
    return;
  }

  if (self.drawsOutgoingTail || self.cornerRadius > 0.0) {
    self.layer.cornerRadius = 0.0;
    self.layer.mask = nil;
  }

  if (self.layer.shadowOpacity <= 0.0 || NSIsEmptyRect(self.bounds)) {
    return;
  }

  CGPathRef shadowPath = NULL;
  if (self.drawsOutgoingTail) {
    shadowPath = [self newOutgoingBubbleCGPathForBounds:self.bounds];
  } else if (self.cornerRadius > 0.0) {
    shadowPath = TLCreateMessageBubblePath(self.bounds, self.cornerRadius, self.rendersAsPill);
  }
  if (!shadowPath) {
    return;
  }

  self.layer.shadowPath = shadowPath;
  CGPathRelease(shadowPath);
}

@end

@implementation TLFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation TLWindowDragStackView

- (instancetype)init {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _canDragWindow = NO;
  }
  return self;
}

- (BOOL)mouseDownCanMoveWindow {
  return self.canDragWindow;
}

- (void)mouseDown:(NSEvent *)event {
  if (self.canDragWindow) {
    [self.window performWindowDragWithEvent:event];
    return;
  }

  [super mouseDown:event];
}

@end

static void TLDrawContentSelection(NSRect bounds, NSColor *accent, TLThemePalette *palette) {
  CGFloat width = palette.sidebarTileSelectedBorderWidth;
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, width * 0.5, width * 0.5)
                                                    xRadius:palette.radiusMedium yRadius:palette.radiusMedium];
  [TLContentAccentColorWithAlpha(accent, palette.sidebarTileSelectedAccentFillOpacity) setFill];
  [path fill];
  [accent setStroke];
  path.lineWidth = width;
  [path stroke];
}

@implementation TLSpacedButtonCell

- (NSSize)cellSize {
  NSSize size = [super cellSize];
  size.width += self.imageTitleSpacing;
  return size;
}

- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView {
  frame.origin.x -= self.imageTitleSpacing / 2.0;
  frame.origin.y += controlView.isFlipped ? -self.imageUpwardOffset : self.imageUpwardOffset;
  [super drawImage:image withFrame:frame inView:controlView];
}

- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView {
  frame.origin.x += self.imageTitleSpacing / 2.0;
  return [super drawTitle:title withFrame:frame inView:controlView];
}

@end

@implementation TLInputBlockingView

- (NSView *)hitTest:(NSPoint)point {
  if (self.hidden || !NSPointInRect([self convertPoint:point fromView:self.superview], self.bounds)) {
    return nil;
  }
  return [super hitTest:point] ?: self;
}

- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)mouseDown:(NSEvent *)event {}
- (void)mouseUp:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)rightMouseDown:(NSEvent *)event {}
- (void)rightMouseUp:(NSEvent *)event {}
- (void)rightMouseDragged:(NSEvent *)event {}
- (void)otherMouseDown:(NSEvent *)event {}
- (void)otherMouseUp:(NSEvent *)event {}
- (void)otherMouseDragged:(NSEvent *)event {}
- (void)scrollWheel:(NSEvent *)event {}
- (void)magnifyWithEvent:(NSEvent *)event {}
- (void)rotateWithEvent:(NSEvent *)event {}
- (void)swipeWithEvent:(NSEvent *)event {}

@end

@interface TLGlassPaneView ()
@property (nonatomic, strong) NSView *glassView;
@end

@implementation TLGlassPaneView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _cornerRadius = -1.0;
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView *effect = [[NSGlassEffectView alloc] init];
      effect.style = NSGlassEffectViewStyleRegular;
      _glassView = effect;
    } else {
      NSVisualEffectView *effect = [[NSVisualEffectView alloc] init];
      effect.material = NSVisualEffectMaterialPopover;
      effect.blendingMode = NSVisualEffectBlendingModeWithinWindow;
      effect.state = NSVisualEffectStateActive;
      effect.wantsLayer = YES;
      effect.layer.masksToBounds = YES;
      _glassView = effect;
    }
    _glassView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_glassView];
    [NSLayoutConstraint activateConstraints:@[
      [_glassView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [_glassView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      [_glassView.topAnchor constraintEqualToAnchor:self.topAnchor],
      [_glassView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat radius = self.cornerRadius < 0 ? _palette.radiusMedium : self.cornerRadius;
  if (@available(macOS 26.0, *)) {
    NSGlassEffectView *effect = (NSGlassEffectView *)self.glassView;
    effect.tintColor = _palette.sidebarHoverSurface;
    effect.cornerRadius = radius;
  } else {
    self.glassView.layer.cornerRadius = radius;
    self.glassView.layer.backgroundColor = _palette.sidebarHoverSurface.CGColor;
  }
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
  _cornerRadius = cornerRadius;
  self.palette = self.palette;
}

@end

@interface TLSelectionStackView ()
@property (nonatomic) BOOL hovered;
@end

@implementation TLSelectionStackView

- (void)mouseEntered:(NSEvent *)event {
  [super mouseEntered:event];
  self.hovered = YES;
  self.needsDisplay = YES;
}

- (void)mouseExited:(NSEvent *)event {
  [super mouseExited:event];
  self.hovered = NO;
  self.needsDisplay = YES;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.needsDisplay = YES;
}

- (void)setSelected:(BOOL)selected {
  _selected = selected;
  [self setAccessibilitySelected:selected];
  self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                          xRadius:self.palette.radiusMedium
                                                          yRadius:self.palette.radiusMedium];
  if (self.hovered) {
    [self.palette.chromeHoverSurface setFill];
    [background fill];
  }
}

@end

@interface TLHoverStackView ()
@property (nonatomic, strong) NSTrackingArea *hoverTrackingArea;
@end

@implementation TLHoverStackView

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.hoverTrackingArea) {
    [self removeTrackingArea:self.hoverTrackingArea];
  }
  self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
    options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
    owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTrackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  if (self.hoverChanged) { self.hoverChanged(YES); }
}

- (void)mouseExited:(NSEvent *)event {
  if (self.hoverChanged) { self.hoverChanged(NO); }
}

@end

@interface TLIconTileView ()
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) TLTokenView *iconBadgeView;
@property (nonatomic, strong) NSImageView *iconBadgeImageView;
@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, strong, nullable) NSColor *imageAverageColor;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLIconTileView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _systemIconName = @"";
    _dashed = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageAlignment = NSImageAlignCenter;
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_imageView];

    _iconBadgeView = [[TLTokenView alloc] init];
    _iconBadgeView.borderEdges = TLBorderEdgeNone;
    [self addSubview:_iconBadgeView];
    _iconBadgeImageView = [[NSImageView alloc] init];
    _iconBadgeImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_iconBadgeView addSubview:_iconBadgeImageView];

    CGFloat imageLength = _palette.space12 + _palette.space5;
    _imageWidthConstraint = [_imageView.widthAnchor constraintEqualToConstant:imageLength];
    _imageHeightConstraint = [_imageView.heightAnchor constraintEqualToConstant:imageLength];
    [NSLayoutConstraint activateConstraints:@[
      [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _imageWidthConstraint,
      _imageHeightConstraint,
    ]];

    [self applyCurrentState];
  }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)layout {
  [super layout];
  CGFloat width = self.palette.agentTileBadgeWidth;
  CGFloat height = self.palette.agentTileBadgeHeight;
  CGFloat inset = self.palette.agentTileBadgeInset;
  self.iconBadgeView.frame = NSMakeRect(NSWidth(self.bounds) - width - inset,
    self.isFlipped ? inset : NSHeight(self.bounds) - height - inset, width, height);
  CGFloat iconSize = self.palette.agentTileBadgeIconSize;
  self.iconBadgeImageView.frame = NSMakeRect((width - iconSize) * 0.5,
    (height - iconSize) * 0.5, iconSize, iconSize);
}

- (NSView *)hitTest:(NSPoint)point {
  NSView *hit = [super hitTest:point];
  return hit && [hit isDescendantOf:self.iconBadgeView] ? self : hit;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self applyCurrentState];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.pressed = YES;
  [self applyCurrentState];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL inside = NSPointInRect(point, self.bounds);
  self.pressed = NO;
  self.hovered = inside;
  [self applyCurrentState];
  if (inside && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSRect tileRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:tileRect
                                                       xRadius:palette.radiusMedium
                                                       yRadius:palette.radiusMedium];

  NSColor *fillColor = self.pressed
    ? palette.sidebarActiveSurface
    : (self.hovered ? palette.chromeHoverSurface : palette.sidebarHoverSurface);
  if (!self.dashed || self.hovered || self.pressed) {
    [fillColor setFill];
    [path fill];
  }

  if (self.dashed) {
    [palette.controlBorder setStroke];
    path.lineWidth = palette.borderWidth;
    CGFloat dashPattern[] = { palette.space3, palette.space2 };
    [path setLineDash:dashPattern count:2 phase:palette.space0];
    [path stroke];
  }

  if (self.selected && self.imageAverageColor) {
    TLDrawContentSelection(self.bounds, self.imageAverageColor, palette);
  }
}

- (nullable NSImage *)systemImageNamed:(NSString *)name {
  if (name.length == 0) {
    return nil;
  }

  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    image.template = YES;
    return image;
  }
  return nil;
}

- (void)applyCurrentState {
  NSImage *resolvedImage = self.image ?: [self systemImageNamed:self.systemIconName];
  self.iconBadgeView.hidden = self.badgeSystemIconName.length == 0;
  self.iconBadgeView.fillColor = self.palette.controlSurface;
  self.iconBadgeView.cornerRadius = self.palette.agentTileBadgeHeight * 0.5;
  self.iconBadgeImageView.image = [self systemImageNamed:self.badgeSystemIconName];
  self.iconBadgeImageView.contentTintColor = self.palette.textMuted;
  self.needsLayout = YES;
  self.imageView.image = resolvedImage;
  self.imageView.contentTintColor = self.image ? nil : self.palette.labelText;
  CGFloat imageLength = self.image ? self.palette.space12 + self.palette.space5 : self.palette.sidebarTileSystemIconSize;
  if (self.imageSize > 0.0 && self.image) {
    imageLength = self.imageSize;
  }
  self.imageWidthConstraint.constant = imageLength;
  self.imageHeightConstraint.constant = imageLength;
  self.alphaValue = self.enabled ? 1.0 : self.palette.disabledOpacity;
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setImageSize:(CGFloat)imageSize {
  _imageSize = imageSize;
  [self applyCurrentState];
}

- (void)setBadgeSystemIconName:(NSString *)badgeSystemIconName {
  _badgeSystemIconName = [badgeSystemIconName copy];
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  _imageAverageColor = TLAverageVisibleImageColor(image);
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setDashed:(BOOL)dashed {
  _dashed = dashed;
  [self setNeedsDisplay:YES];
}

- (void)setSelected:(BOOL)selected {
  _selected = selected;
  [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

@end

@interface TLSidebarInboxPaneView ()
@property (nonatomic, strong, readwrite) NSStackView *contentStackView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *contentTopConstraint;
@end

@implementation TLSidebarInboxPaneView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;

    _titleLabel = [NSTextField labelWithString:@"Notifications"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.alignment = NSTextAlignmentLeft;
    [self addSubview:_titleLabel];

    _contentStackView = [[NSStackView alloc] init];
    _contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _contentStackView.alignment = NSLayoutAttributeWidth;
    _contentStackView.distribution = NSStackViewDistributionGravityAreas;
    [self addSubview:_contentStackView];

    _contentLeadingConstraint = [_contentStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                                constant:_palette.sidebarInboxItemLeadingOffset];
    _contentTopConstraint = [_contentStackView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                                                        constant:_palette.sidebarInboxHeaderItemGap];
    _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                        constant:_palette.sidebarInboxItemHorizontalInset + _palette.sidebarInboxItemLeadingOffset];

    [NSLayoutConstraint activateConstraints:@[
      _titleLeadingConstraint,
      [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-_palette.sidebarInboxItemHorizontalInset],
      [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:_palette.space5],
      _contentLeadingConstraint,
      [_contentStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
      _contentTopConstraint,
      [_contentStackView.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor],
    ]];

    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat height = palette.space5 +
    self.titleLabel.intrinsicContentSize.height +
    palette.sidebarInboxHeaderItemGap +
    self.contentStackView.fittingSize.height +
    palette.space5;
  return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

- (void)addInboxItemView:(NSView *)itemView {
  if (!itemView) {
    return;
  }
  [self.contentStackView addArrangedSubview:itemView];
  [itemView.widthAnchor constraintEqualToAnchor:self.contentStackView.widthAnchor].active = YES;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
}

- (void)insertInboxItemView:(NSView *)itemView atIndex:(NSUInteger)index {
  if (!itemView) {
    return;
  }
  NSUInteger boundedIndex = MIN(index, self.contentStackView.arrangedSubviews.count);
  [self.contentStackView insertArrangedSubview:itemView atIndex:boundedIndex];
  [itemView.widthAnchor constraintEqualToAnchor:self.contentStackView.widthAnchor].active = YES;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.titleLabel.stringValue = @"Notifications";
  self.titleLabel.font = palette.smallFont;
  self.titleLabel.textColor = palette.textMuted;
  self.titleLabel.alignment = NSTextAlignmentLeft;
  self.contentStackView.spacing = palette.space0;
  self.titleLeadingConstraint.constant = palette.sidebarInboxItemHorizontalInset + palette.sidebarInboxItemLeadingOffset;
  self.contentLeadingConstraint.constant = palette.sidebarInboxItemLeadingOffset;
  self.contentTopConstraint.constant = palette.sidebarInboxHeaderItemGap;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
}

@end

@interface TLSidebarInboxStackView ()
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@property (nonatomic, strong) NSStackView *metadataStack;
@property (nonatomic, strong) NSLayoutConstraint *imageLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, strong) TLTokenView *badgeView;
@property (nonatomic, strong) NSTextField *badgeLabel;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *metadataLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *metadataTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *badgeTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *badgeWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *badgeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *metadataTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *metadataBottomConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@property (nonatomic, strong, nullable) NSTimer *urgentPulseTimer;
@property (nonatomic) CFTimeInterval urgentPulseStartTime;
@property (nonatomic) CGFloat urgentPulseProgress;
@property (nonatomic) BOOL urgentPulseCompleted;
@end

@implementation TLSidebarInboxStackView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _subtitle = @"";
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.alignment = NSTextAlignmentLeft;
    _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _titleLabel.maximumNumberOfLines = 0;
    _titleLabel.cell.wraps = YES;
    _titleLabel.cell.scrollable = NO;
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                          forOrientation:NSLayoutConstraintOrientationVertical];
    [_titleLabel setContentHuggingPriority:NSLayoutPriorityRequired
                            forOrientation:NSLayoutConstraintOrientationVertical];
    [self addSubview:_titleLabel];

    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageAlignment = NSImageAlignCenter;
    _imageView.imageScaling = NSImageScaleProportionallyDown;

    _subtitleLabel = [NSTextField labelWithString:@""];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.alignment = NSTextAlignmentLeft;
    _subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _subtitleLabel.maximumNumberOfLines = 0;
    _subtitleLabel.cell.wraps = YES;
    _subtitleLabel.cell.scrollable = NO;
    [_subtitleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_subtitleLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                             forOrientation:NSLayoutConstraintOrientationVertical];
    [_subtitleLabel setContentHuggingPriority:NSLayoutPriorityRequired
                               forOrientation:NSLayoutConstraintOrientationVertical];

    _metadataStack = [[NSStackView alloc] init];
    _metadataStack.translatesAutoresizingMaskIntoConstraints = NO;
    _metadataStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _metadataStack.alignment = NSLayoutAttributeCenterY;
    _metadataStack.distribution = NSStackViewDistributionGravityAreas;
    _metadataStack.spacing = _palette.space3;
    [_metadataStack addArrangedSubview:_imageView];
    [_metadataStack addArrangedSubview:_subtitleLabel];
    [self addSubview:_metadataStack];

    _badgeView = [[TLTokenView alloc] init];
    _badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeView.borderEdges = TLBorderEdgeNone;
    [self addSubview:_badgeView positioned:NSWindowAbove relativeTo:nil];

    _badgeLabel = [NSTextField labelWithString:@""];
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeLabel.alignment = NSTextAlignmentCenter;
    [_badgeView addSubview:_badgeLabel];

    _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                        constant:_palette.sidebarInboxItemHorizontalInset];
    _titleTrailingConstraint = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                    constant:-_palette.sidebarInboxItemHorizontalInset];
    _metadataLeadingConstraint = [_metadataStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                              constant:_palette.sidebarInboxItemHorizontalInset];
    _metadataTrailingConstraint = [_metadataStack.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeView.leadingAnchor
                                                                                          constant:-_palette.space5];
    _imageLeadingConstraint = [_imageView.leadingAnchor constraintEqualToAnchor:_metadataStack.leadingAnchor];
    _imageWidthConstraint = [_imageView.widthAnchor constraintEqualToConstant:_palette.sidebarInboxIconSize];
    _imageHeightConstraint = [_imageView.heightAnchor constraintEqualToConstant:_palette.sidebarInboxIconSize];
    _badgeTrailingConstraint = [_badgeView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                         constant:-_palette.sidebarInboxItemHorizontalInset];
    _badgeWidthConstraint = [_badgeView.widthAnchor constraintEqualToConstant:_palette.space11];
    _badgeHeightConstraint = [_badgeView.heightAnchor constraintEqualToConstant:_palette.space9];
    _titleTopConstraint = [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:_palette.space4];
    _metadataTopConstraint = [_metadataStack.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:_palette.space4];
    _metadataBottomConstraint = [_metadataStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-_palette.space4];

    [NSLayoutConstraint activateConstraints:@[
      _titleLeadingConstraint,
      _titleTopConstraint,
      _titleTrailingConstraint,

      _metadataLeadingConstraint,
      _metadataTopConstraint,
      _metadataBottomConstraint,
      _metadataTrailingConstraint,

      _imageLeadingConstraint,
      _imageWidthConstraint,
      _imageHeightConstraint,

      _badgeTrailingConstraint,
      [_badgeView.centerYAnchor constraintEqualToAnchor:_metadataStack.centerYAnchor],
      _badgeWidthConstraint,
      _badgeHeightConstraint,

      [_badgeLabel.leadingAnchor constraintEqualToAnchor:_badgeView.leadingAnchor constant:_palette.space2],
      [_badgeLabel.trailingAnchor constraintEqualToAnchor:_badgeView.trailingAnchor constant:-_palette.space2],
      [_badgeLabel.centerYAnchor constraintEqualToAnchor:_badgeView.centerYAnchor],
    ]];

    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat rowWidth = [self availableRowWidthWithPalette:palette];
  CGFloat titleHeight = [self heightForLabel:self.titleLabel
                          constrainedToWidth:[self titleMaxLayoutWidthForRowWidth:rowWidth palette:palette]];
  CGFloat subtitleHeight = [self heightForLabel:self.subtitleLabel
                             constrainedToWidth:[self subtitleMaxLayoutWidthForRowWidth:rowWidth palette:palette]];
  CGFloat metadataHeight = MAX(palette.sidebarInboxIconSize, subtitleHeight);
  CGFloat height = palette.space4 + titleHeight + palette.space4 + metadataHeight + palette.space4;
  return NSMakeSize(NSViewNoIntrinsicMetric, ceil(height));
}

- (void)layout {
  [self updateLabelPreferredMaxLayoutWidths];
  [super layout];
  [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
  BOOL widthChanged = fabs(newSize.width - NSWidth(self.frame)) > 0.5;
  [super setFrameSize:newSize];
  if (widthChanged) {
    [self updateLabelPreferredMaxLayoutWidths];
    [self invalidateIntrinsicContentSize];
  }
}

- (CGFloat)availableRowWidthWithPalette:(TLThemePalette *)palette {
  CGFloat width = NSWidth(self.bounds);
  if (width <= 1.0 && self.superview) {
    width = NSWidth(self.superview.bounds);
  }
  if (width <= 1.0) {
    width = palette.sidebarWidth - (palette.sidebarInboxOuterHorizontalInset * 2.0);
  }
  return MAX(width, palette.space11);
}

- (CGFloat)titleMaxLayoutWidthForRowWidth:(CGFloat)rowWidth palette:(TLThemePalette *)palette {
  return MAX(1.0, rowWidth - (palette.sidebarInboxItemHorizontalInset * 2.0));
}

- (NSString *)badgeText {
  return self.notificationCount > 0 ? [NSString stringWithFormat:@"%ld", (long)self.notificationCount] : @"";
}

- (CGFloat)badgeHeightWithPalette:(TLThemePalette *)palette {
  return palette.space9;
}

- (CGFloat)badgeCornerRadiusWithPalette:(TLThemePalette *)palette {
  return [self badgeHeightWithPalette:palette] * 0.5;
}

- (CGFloat)badgeWidthWithPalette:(TLThemePalette *)palette {
  NSString *text = [self badgeText];
  if (text.length == 0) {
    return palette.space0;
  }

  NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: palette.sidebarInboxBadgeFont };
  CGFloat textWidth = [text sizeWithAttributes:attributes].width;
  CGFloat paddedTextWidth = textWidth + (palette.sidebarInboxBadgeHorizontalPadding * 2.0);
  return ceil(MAX(palette.sidebarInboxBadgeMinimumWidth, paddedTextWidth));
}

- (NSColor *)badgeSurfaceColorWithPalette:(TLThemePalette *)palette {
  if (self.isUrgent) {
    return palette.sidebarUrgentNotificationBadgeSurface;
  }
  return self.usesPrimaryBadge ? palette.sidebarInboxPrimaryBadgeSurface : palette.sidebarInboxBadgeSurface;
}

- (NSColor *)badgeTextColorWithPalette:(TLThemePalette *)palette {
  if (self.isUrgent) {
    return palette.sidebarUrgentNotificationBadgeText;
  }
  return self.usesPrimaryBadge ? palette.sidebarInboxPrimaryBadgeText : palette.sidebarInboxBadgeText;
}

- (CGFloat)subtitleMaxLayoutWidthForRowWidth:(CGFloat)rowWidth palette:(TLThemePalette *)palette {
  CGFloat itemInset = palette.sidebarInboxItemHorizontalInset;
  CGFloat trailingReserveWidth = itemInset;
  if (self.notificationCount > 0) {
    trailingReserveWidth += [self badgeWidthWithPalette:palette] + palette.space5;
  }
  CGFloat availableWidth = rowWidth - itemInset - palette.sidebarInboxIconSize - palette.space3 - trailingReserveWidth;
  return MAX(1.0, availableWidth);
}

- (CGFloat)heightForLabel:(NSTextField *)label constrainedToWidth:(CGFloat)width {
  NSFont *font = label.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
  NSDictionary *attributes = @{ NSFontAttributeName: font };
  NSRect measuredRect = [label.stringValue boundingRectWithSize:NSMakeSize(MAX(1.0, width), CGFLOAT_MAX)
                                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                     attributes:attributes];
  return ceil(MAX(label.intrinsicContentSize.height, NSHeight(measuredRect)));
}

- (void)updateLabelPreferredMaxLayoutWidths {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat rowWidth = [self availableRowWidthWithPalette:palette];
  self.titleLabel.preferredMaxLayoutWidth = [self titleMaxLayoutWidthForRowWidth:rowWidth palette:palette];
  self.subtitleLabel.preferredMaxLayoutWidth = [self subtitleMaxLayoutWidthForRowWidth:rowWidth palette:palette];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if (self.isUrgent) {
    NSRect urgentRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
    NSBezierPath *urgentPath = [NSBezierPath bezierPathWithRoundedRect:urgentRect
                                                               xRadius:palette.radiusMedium
                                                               yRadius:palette.radiusMedium];
    NSColor *surface = TLColorByInterpolatingColors(palette.transparentSurface,
                                                    palette.sidebarUrgentNotificationPulseSurface,
                                                    self.urgentPulseProgress);
    [surface setFill];
    [urgentPath fill];
  }
  if (self.enabled && (self.hovered || self.pressed)) {
    NSRect hoverRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
    NSBezierPath *hoverPath = [NSBezierPath bezierPathWithRoundedRect:hoverRect
                                                               xRadius:palette.radiusMedium
                                                               yRadius:palette.radiusMedium];
    [(self.pressed ? palette.sidebarActiveSurface : palette.chromeHoverSurface) setFill];
    [hoverPath fill];
  }

  if (self.notificationCount > 0) {
    NSString *count = [self badgeText];
    CGFloat badgeWidth = [self badgeWidthWithPalette:palette];
    CGFloat badgeHeight = [self badgeHeightWithPalette:palette];
    CGFloat badgeX = NSWidth(self.bounds) - palette.sidebarInboxItemHorizontalInset - badgeWidth;
    CGFloat badgeY = NSMidY(self.metadataStack.frame) - (badgeHeight * 0.5);
    NSRect badgeRect = NSMakeRect(badgeX, badgeY, badgeWidth, badgeHeight);
    CGFloat badgeCornerRadius = [self badgeCornerRadiusWithPalette:palette];
    NSBezierPath *badgePath = [NSBezierPath bezierPathWithRoundedRect:badgeRect
                                                              xRadius:badgeCornerRadius
                                                              yRadius:badgeCornerRadius];
    [[self badgeSurfaceColorWithPalette:palette] setFill];
    [badgePath fill];

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
      NSFontAttributeName: palette.sidebarInboxBadgeFont,
      NSForegroundColorAttributeName: [self badgeTextColorWithPalette:palette],
      NSParagraphStyleAttributeName: paragraphStyle,
    };
    NSSize textSize = [count sizeWithAttributes:attributes];
    NSRect textRect = NSMakeRect(NSMinX(badgeRect),
                                 NSMidY(badgeRect) - (textSize.height * 0.5),
                                 NSWidth(badgeRect),
                                 textSize.height);
    [count drawInRect:textRect withAttributes:attributes];
  }

  if (self.showsSeparator) {
    NSBezierPath *separatorPath = [NSBezierPath bezierPath];
    CGFloat y = palette.borderWidth * 0.5;
    [separatorPath moveToPoint:NSMakePoint(palette.space5, y)];
    [separatorPath lineToPoint:NSMakePoint(MAX(palette.space5, NSWidth(self.bounds) - palette.space5), y)];
    [palette.sidebarBorder setStroke];
    separatorPath.lineWidth = palette.borderWidth;
    [separatorPath stroke];
  }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window && self.isUrgent) {
    [self startUrgentPulse];
  } else {
    [self stopUrgentPulse];
  }
}

- (void)dealloc {
  [self stopUrgentPulse];
}

- (void)startUrgentPulse {
  if (self.urgentPulseTimer || self.urgentPulseCompleted) {
    return;
  }
  self.urgentPulseStartTime = CACurrentMediaTime();
  self.urgentPulseProgress = 0.0;
  __weak typeof(self) weakSelf = self;
  self.urgentPulseTimer = [NSTimer timerWithTimeInterval:TLUrgentNotificationFrameInterval repeats:YES block:^(NSTimer *timer) {
    typeof(self) strongSelf = weakSelf;
    if (!strongSelf) {
      [timer invalidate];
      return;
    }
    CGFloat elapsed = CACurrentMediaTime() - strongSelf.urgentPulseStartTime;
    CGFloat timelineProgress = MIN(1.0, elapsed / TLUrgentNotificationPulseDuration);
    CGFloat pulse = sin((CGFloat)(2.0 * M_PI) * timelineProgress);
    strongSelf.urgentPulseProgress = pulse * pulse;
    [strongSelf setNeedsDisplay:YES];
    if (timelineProgress >= 1.0) {
      strongSelf.urgentPulseProgress = 0.0;
      strongSelf.urgentPulseCompleted = YES;
      [strongSelf stopUrgentPulse];
      [strongSelf setNeedsDisplay:YES];
    }
  }];
  [[NSRunLoop mainRunLoop] addTimer:self.urgentPulseTimer forMode:NSRunLoopCommonModes];
}

- (void)stopUrgentPulse {
  [self.urgentPulseTimer invalidate];
  self.urgentPulseTimer = nil;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self applyCurrentState];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.pressed = YES;
  [self applyCurrentState];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL shouldSendAction = self.pressed && NSPointInRect(point, self.bounds);
  self.pressed = NO;
  [self applyCurrentState];
  if (shouldSendAction && self.target && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.image.template = self.imageUsesTemplateRendering;
  self.imageView.image = self.image;
  self.imageView.contentTintColor = self.imageUsesTemplateRendering ? palette.labelText : nil;
  BOOL showsBadge = self.notificationCount > 0;
  self.titleLabel.stringValue = self.title;
  self.titleLabel.alignment = NSTextAlignmentLeft;
  self.titleLabel.font = showsBadge ? palette.sidebarInboxUnreadTitleFont : palette.sidebarInboxReadTitleFont;
  self.titleLabel.textColor = palette.appText;
  self.subtitleLabel.stringValue = self.subtitle;
  self.subtitleLabel.alignment = NSTextAlignmentLeft;
  self.subtitleLabel.font = palette.smallFont;
  self.subtitleLabel.textColor = palette.textMuted;
  self.metadataStack.spacing = palette.space3;
  self.badgeLabel.stringValue = [self badgeText];
  self.badgeLabel.font = palette.sidebarInboxBadgeFont;
  self.badgeLabel.textColor = [self badgeTextColorWithPalette:palette];
  self.badgeView.fillColor = [self badgeSurfaceColorWithPalette:palette];
  self.badgeView.cornerRadius = [self badgeCornerRadiusWithPalette:palette];
  self.badgeView.hidden = YES;
  self.badgeLabel.hidden = YES;
  self.badgeWidthConstraint.constant = [self badgeWidthWithPalette:palette];
  self.badgeHeightConstraint.constant = [self badgeHeightWithPalette:palette];
  self.titleLeadingConstraint.constant = palette.sidebarInboxItemHorizontalInset;
  self.titleTrailingConstraint.constant = -palette.sidebarInboxItemHorizontalInset;
  self.metadataLeadingConstraint.constant = palette.sidebarInboxItemHorizontalInset;
  self.metadataTrailingConstraint.constant = showsBadge ? -palette.space5 : palette.space0;
  self.badgeTrailingConstraint.constant = -palette.sidebarInboxItemHorizontalInset;
  self.titleTopConstraint.constant = palette.space4;
  self.metadataTopConstraint.constant = palette.space4;
  self.metadataBottomConstraint.constant = -palette.space4;

  CGFloat imageLength = palette.sidebarInboxIconSize;
  self.imageWidthConstraint.constant = imageLength;
  self.imageHeightConstraint.constant = imageLength;
  [self updateLabelPreferredMaxLayoutWidths];
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  _image.template = self.imageUsesTemplateRendering;
  [self applyCurrentState];
}

- (void)setImageUsesTemplateRendering:(BOOL)imageUsesTemplateRendering {
  _imageUsesTemplateRendering = imageUsesTemplateRendering;
  [self applyCurrentState];
}

- (void)setTitle:(NSString *)title {
  _title = [title copy] ?: @"";
  [self applyCurrentState];
}

- (void)setSubtitle:(NSString *)subtitle {
  _subtitle = [subtitle copy] ?: @"";
  [self applyCurrentState];
}

- (void)setNotificationCount:(NSInteger)notificationCount {
  _notificationCount = notificationCount;
  [self applyCurrentState];
}

- (void)setUsesPrimaryBadge:(BOOL)usesPrimaryBadge {
  _usesPrimaryBadge = usesPrimaryBadge;
  [self applyCurrentState];
}

- (void)setShowsSeparator:(BOOL)showsSeparator {
  _showsSeparator = showsSeparator;
  [self setNeedsDisplay:YES];
}

- (void)setUrgent:(BOOL)urgent {
  _urgent = urgent;
  self.urgentPulseCompleted = NO;
  self.urgentPulseProgress = 0.0;
  if (urgent && self.window) {
    [self startUrgentPulse];
  } else if (!urgent) {
    [self stopUrgentPulse];
  }
  [self applyCurrentState];
}

@end

@implementation TLBrowserBackdropView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return self;
}

@end

@interface TLSidebarShortcutButton ()
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, strong, nullable) NSPanel *tooltipPanel;
@property (nonatomic) CGFloat displaySize;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
- (void)setDisplaySize:(CGFloat)displaySize;
- (nullable NSImage *)systemImageNamed:(NSString *)name;
- (NSColor *)shortcutIconColor;
- (void)showImmediateTooltip;
- (void)hideImmediateTooltip;
- (void)applyCurrentState;
@end

@implementation TLSidebarShortcutButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _systemIconName = @"";
    _shortcutKind = TLSidebarShortcutKindWebsite;
    _displaySize = _palette.sidebarBookmarkButtonSize;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageAlignment = NSImageAlignCenter;
    _imageView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_imageView];

    _widthConstraint = [self.widthAnchor constraintEqualToConstant:_displaySize];
    _heightConstraint = [self.heightAnchor constraintEqualToConstant:_displaySize];
    _imageWidthConstraint = [_imageView.widthAnchor constraintEqualToConstant:_palette.sidebarBookmarkIconSize];
    _imageHeightConstraint = [_imageView.heightAnchor constraintEqualToConstant:_palette.sidebarBookmarkIconSize];
    [NSLayoutConstraint activateConstraints:@[
      _widthConstraint,
      _heightConstraint,
      [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _imageWidthConstraint,
      _imageHeightConstraint,
    ]];
    [self setAccessibilityRole:NSAccessibilityButtonRole];
    [self applyCurrentState];
  }
  return self;
}

- (BOOL)mouseDownCanMoveWindow {
  return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }
  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self setNeedsDisplay:YES];
  [self showImmediateTooltip];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self setNeedsDisplay:YES];
  [self hideImmediateTooltip];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }
  [self hideImmediateTooltip];
  self.pressed = YES;
  [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL inside = NSPointInRect(point, self.bounds);
  self.pressed = NO;
  self.hovered = inside;
  [self setNeedsDisplay:YES];
  if (inside && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSColor *fillColor = self.pressed
    ? palette.sidebarActiveSurface
    : (self.hovered ? palette.chromeHoverSurface : palette.composerSurface);
  CGFloat radius = MIN(palette.sidebarBookmarkCornerRadius, NSHeight(self.bounds) * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius];
  [fillColor setFill];
  [path fill];
  if (self.shortcutKind != TLSidebarShortcutKindWebsite) {
    CGFloat borderInset = palette.borderWidth * 0.5;
    NSRect borderRect = NSInsetRect(self.bounds, borderInset, borderInset);
    NSBezierPath *borderPath = [NSBezierPath bezierPathWithRoundedRect:borderRect
                                                               xRadius:radius
                                                               yRadius:radius];
    borderPath.lineWidth = palette.borderWidth;
    [palette.controlBorder setStroke];
    [borderPath stroke];
  }
}

- (void)setDisplaySize:(CGFloat)displaySize {
  _displaySize = displaySize;
  CGFloat maximumIconSize = self.shortcutKind == TLSidebarShortcutKindWebsite
    ? self.palette.sidebarBookmarkIconSize : self.palette.sidebarActionIconSize;
  CGFloat iconSize = MIN(maximumIconSize, MAX(self.palette.space6, displaySize - self.palette.space6));
  self.widthConstraint.constant = displaySize;
  self.heightConstraint.constant = displaySize;
  self.imageWidthConstraint.constant = iconSize;
  self.imageHeightConstraint.constant = iconSize;
  self.imageView.wantsLayer = YES;
  self.imageView.layer.cornerRadius = self.roundsImageCorners ? self.palette.space2 : self.palette.space0;
  self.imageView.layer.masksToBounds = self.roundsImageCorners;
  [self setNeedsDisplay:YES];
}

- (void)setRoundsImageCorners:(BOOL)roundsImageCorners {
  _roundsImageCorners = roundsImageCorners;
  [self setDisplaySize:self.displaySize];
}

- (nullable NSImage *)systemImageNamed:(NSString *)name {
  if (name.length == 0) {
    return nil;
  }
  NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:self.title];
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:self.palette.sidebarActionIconSize
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleMedium];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
  }
  image.template = YES;
  return image;
}

- (NSColor *)shortcutIconColor {
  switch (self.shortcutKind) {
    case TLSidebarShortcutKindHistory:
      return self.palette.sidebarHistoryShortcutIcon;
    case TLSidebarShortcutKindWebsite:
      return self.palette.controlText;
  }
}

- (void)showImmediateTooltip {
  [self hideImmediateTooltip];
  if (self.title.length == 0 || !self.window) {
    return;
  }

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: palette.smallFont };
  NSSize textSize = [self.title sizeWithAttributes:attributes];
  CGFloat horizontalPadding = palette.space4;
  CGFloat verticalPadding = palette.space2;
  CGFloat labelWidth = ceil(textSize.width) + palette.space2;
  NSSize panelSize = NSMakeSize(labelWidth + horizontalPadding * 2.0,
                                ceil(textSize.height) + verticalPadding * 2.0);

  NSRect localRect = [self convertRect:self.bounds toView:nil];
  NSRect screenRect = [self.window convertRectToScreen:localRect];
  NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
  NSRect visibleFrame = screen.visibleFrame;
  CGFloat x = NSMidX(screenRect) - panelSize.width * 0.5;
  CGFloat y = NSMinY(screenRect) - panelSize.height - palette.space2;
  x = MAX(NSMinX(visibleFrame), MIN(x, NSMaxX(visibleFrame) - panelSize.width));
  y = MAX(NSMinY(visibleFrame), MIN(y, NSMaxY(visibleFrame) - panelSize.height));

  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(x, y, panelSize.width, panelSize.height)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
  panel.opaque = NO;
  panel.backgroundColor = palette.transparentSurface;
  panel.hasShadow = YES;
  panel.hidesOnDeactivate = YES;
  panel.ignoresMouseEvents = YES;
  panel.becomesKeyOnlyIfNeeded = YES;
  panel.collectionBehavior = NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;

  NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, panelSize.width, panelSize.height)];
  contentView.wantsLayer = YES;
  contentView.layer.backgroundColor = palette.controlSurface.CGColor;
  contentView.layer.cornerRadius = palette.radiusMedium;

  NSTextField *label = [NSTextField labelWithString:self.title];
  label.frame = NSMakeRect(horizontalPadding, verticalPadding, labelWidth,
                           panelSize.height - verticalPadding * 2.0);
  label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  label.alignment = NSTextAlignmentCenter;
  label.font = palette.smallFont;
  label.textColor = palette.controlText;
  [contentView addSubview:label];
  panel.contentView = contentView;

  self.tooltipPanel = panel;
  [self.window addChildWindow:panel ordered:NSWindowAbove];
  [panel orderFront:nil];
}

- (void)hideImmediateTooltip {
  NSPanel *panel = self.tooltipPanel;
  if (!panel) {
    return;
  }
  if (panel.parentWindow) {
    [panel.parentWindow removeChildWindow:panel];
  }
  [panel orderOut:nil];
  self.tooltipPanel = nil;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
  if (newWindow != self.window) {
    [self hideImmediateTooltip];
  }
  [super viewWillMoveToWindow:newWindow];
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  BOOL usesSystemIcon = self.shortcutKind != TLSidebarShortcutKindWebsite;
  self.imageView.image = usesSystemIcon ? [self systemImageNamed:self.systemIconName] : self.image;
  self.imageView.contentTintColor = usesSystemIcon ? [self shortcutIconColor] : nil;
  self.toolTip = nil;
  [self setAccessibilityLabel:self.title];
  [self setDisplaySize:MIN(self.displaySize, palette.sidebarBookmarkButtonSize)];
  self.alphaValue = self.enabled ? 1.0 : palette.disabledOpacity;
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  [self hideImmediateTooltip];
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  _image.template = NO;
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setTitle:(NSString *)title {
  [self hideImmediateTooltip];
  _title = [title copy] ?: @"";
  [self applyCurrentState];
}

- (void)setShortcutKind:(TLSidebarShortcutKind)shortcutKind {
  _shortcutKind = shortcutKind;
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

@end

@interface TLSidebarShortcutsView ()
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSStackView *stackView;
@property (nonatomic, strong) NSMutableArray<TLSidebarShortcutButton *> *mutableShortcutButtons;
@property (nonatomic, strong) NSLayoutConstraint *stackLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *stackTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *stackTopConstraint;
- (void)applyPalette;
@end

@implementation TLSidebarShortcutsView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _mutableShortcutButtons = [NSMutableArray array];
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [NSTextField labelWithString:@"Shortcuts"];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.alignment = NSTextAlignmentLeft;
    [self addSubview:_titleLabel];

    _stackView = [[NSStackView alloc] init];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _stackView.alignment = NSLayoutAttributeCenterY;
    _stackView.distribution = NSStackViewDistributionFill;
    [self addSubview:_stackView];

    _stackLeadingConstraint = [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                        constant:_palette.sidebarInboxItemHorizontalInset + _palette.sidebarInboxItemLeadingOffset];
    _stackTrailingConstraint = [_stackView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                   constant:-_palette.sidebarInboxItemHorizontalInset];
    _stackTopConstraint = [_stackView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor
                                                               constant:_palette.sidebarInboxHeaderItemGap];
    [NSLayoutConstraint activateConstraints:@[
      [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                constant:_palette.sidebarInboxItemHorizontalInset + _palette.sidebarInboxItemLeadingOffset],
      [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                           constant:-_palette.sidebarInboxItemHorizontalInset],
      [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
      _stackLeadingConstraint,
      _stackTrailingConstraint,
      _stackTopConstraint,
      [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    [self applyPalette];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  CGFloat height = self.titleLabel.intrinsicContentSize.height +
    self.palette.sidebarInboxHeaderItemGap + self.palette.sidebarBookmarkButtonSize;
  return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

- (NSArray<TLSidebarShortcutButton *> *)shortcutButtons {
  return [self.mutableShortcutButtons copy];
}

- (void)addShortcutButton:(TLSidebarShortcutButton *)button {
  if (!button) {
    return;
  }
  button.palette = self.palette;
  [self.mutableShortcutButtons addObject:button];
  [self.stackView addArrangedSubview:button];
  [self setNeedsLayout:YES];
}

- (void)layout {
  [super layout];
  NSUInteger buttonCount = self.mutableShortcutButtons.count;
  if (buttonCount == 0) {
    return;
  }
  CGFloat horizontalInsets = self.stackLeadingConstraint.constant - self.stackTrailingConstraint.constant;
  CGFloat availableWidth = MAX(self.palette.space0, NSWidth(self.bounds) - horizontalInsets);
  CGFloat gapCount = buttonCount > 1 ? buttonCount - 1 : self.palette.space0;
  CGFloat spacing = self.palette.sidebarBookmarkSpacing;
  CGFloat minimumButtonSize = self.palette.space9;
  if (gapCount > 0 && (minimumButtonSize * buttonCount) + (spacing * gapCount) > availableWidth) {
    spacing = MAX(self.palette.space0, floor((availableWidth - (minimumButtonSize * buttonCount)) / gapCount));
  }
  CGFloat totalSpacing = spacing * gapCount;
  CGFloat availableButtonWidth = floor((availableWidth - totalSpacing) / buttonCount);
  CGFloat buttonSize = MIN(self.palette.sidebarBookmarkButtonSize, MAX(1.0, availableButtonWidth));
  self.stackView.spacing = spacing;
  for (TLSidebarShortcutButton *button in self.mutableShortcutButtons) {
    [button setDisplaySize:buttonSize];
  }
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyPalette];
}

- (void)applyPalette {
  self.titleLabel.stringValue = @"Shortcuts";
  self.titleLabel.font = self.palette.smallFont;
  self.titleLabel.textColor = self.palette.textMuted;
  self.stackView.spacing = self.palette.sidebarBookmarkSpacing;
  self.stackLeadingConstraint.constant = self.palette.sidebarInboxItemHorizontalInset + self.palette.sidebarInboxItemLeadingOffset;
  self.stackTrailingConstraint.constant = -self.palette.sidebarInboxItemHorizontalInset;
  self.stackTopConstraint.constant = self.palette.sidebarInboxHeaderItemGap;
  for (TLSidebarShortcutButton *button in self.mutableShortcutButtons) {
    button.palette = self.palette;
  }
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
}

@end

@interface TLBrowserAddressInput ()
@property (nonatomic, readwrite) BOOL hasUserDraft;
@property (nonatomic, copy) NSString *latestAddress;
@property (nonatomic, strong, readwrite) NSButton *backButton;
@property (nonatomic, strong, readwrite) NSButton *forwardButton;
@property (nonatomic, strong, readwrite) NSButton *reloadButton;
@property (nonatomic, strong, readwrite) NSButton *heightToggleButton;
@property (nonatomic, strong, readwrite) NSButton *chatButton;
@property (nonatomic, strong) NSTextField *responseCountLabel;
@property (nonatomic, strong) NSStackView *trailingStack;
@property (nonatomic, strong) NSStackView *navigationStack;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *buttonSizeConstraints;
- (NSButton *)toolbarButtonWithToolTip:(NSString *)toolTip;
- (NSImage *)toolbarImageWithSystemName:(NSString *)systemName accessibilityDescription:(NSString *)description;
- (void)updateToolbarImages;
@end

@implementation TLGlassMessageInput

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.backgroundView = [[TLGlassPaneView alloc] init];
    [self applyGlassPalette];
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  [super setPalette:palette];
  [self applyGlassPalette];
}

- (void)setUsesChatBackdrop:(BOOL)usesChatBackdrop {
  _usesChatBackdrop = usesChatBackdrop;
  [self applyGlassPalette];
}

- (void)applyGlassPalette {
  TLGlassPaneView *glass = (TLGlassPaneView *)self.backgroundView;
  glass.palette = self.palette;
  glass.cornerRadius = self.palette.messageInputCornerRadius;
  glass.wantsLayer = YES;
  glass.layer.cornerRadius = self.palette.messageInputCornerRadius;
  glass.layer.masksToBounds = YES;
  glass.layer.backgroundColor = TLCGColor(self.usesChatBackdrop ? self.palette.chatInputBackdrop : self.palette.transparentSurface);
  self.sendButtonSize = self.palette.messageInputSendButtonSize;
  self.sendButtonInset = self.palette.space4;
  self.sendButton.solidSurfaceColor = self.palette.messageInputSendButtonSurface;
  self.sendButton.disabledSolidSurfaceColor = self.palette.messageInputSendButtonDisabledSurface;
  self.sendButton.contentTintColor = self.palette.messageInputSendButtonText;
}

@end

@implementation TLBrowserAddressInput

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.sendButton.hoverSurfaceOnly = YES;
    _backButton = [self toolbarButtonWithToolTip:@"Back"];
    _forwardButton = [self toolbarButtonWithToolTip:@"Forward"];
    _reloadButton = [self toolbarButtonWithToolTip:@"Reload"];
    _heightToggleButton = [self toolbarButtonWithToolTip:@"Use reduced-height browser"];
    _chatButton = [self toolbarButtonWithToolTip:@"Show chat"];
    _chatButton.hidden = YES;
    _responseCountLabel = [NSTextField labelWithString:@"0"];
    _responseCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _responseCountLabel.hidden = YES;
    [_responseCountLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    _backButton.enabled = NO;
    _forwardButton.enabled = NO;
    _reloadButton.enabled = NO;

    _navigationStack = [[NSStackView alloc] init];
    _navigationStack.translatesAutoresizingMaskIntoConstraints = NO;
    _navigationStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _navigationStack.alignment = NSLayoutAttributeCenterY;
    _navigationStack.distribution = NSStackViewDistributionFill;
    [_navigationStack addArrangedSubview:_backButton];
    [_navigationStack addArrangedSubview:_forwardButton];
    [_navigationStack addArrangedSubview:_reloadButton];
    _trailingStack = [NSStackView stackViewWithViews:@[_chatButton, _responseCountLabel, _heightToggleButton]];
    _trailingStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _trailingStack.alignment = NSLayoutAttributeCenterY;
    _trailingStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self setLeadingAccessoryView:_navigationStack trailingAccessoryView:_trailingStack];
    self.selectsAllOnFocus = YES;
    self.textView.delegate = self;
    [self.textView setAccessibilityLabel:@"Give a task or enter a URL"];
    __weak typeof(self) weakSelf = self;
    self.textChangeHandler = ^{
      TLBrowserAddressInput *input = weakSelf;
      input.hasUserDraft = YES;
      input.sendButton.enabled = [input.textView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    };
    NSMutableArray<NSLayoutConstraint *> *buttonSizeConstraints = [NSMutableArray array];
    for (NSButton *button in @[_backButton, _forwardButton, _reloadButton, _chatButton, _heightToggleButton]) {
      [buttonSizeConstraints addObject:[button.widthAnchor constraintEqualToConstant:self.palette.browserToolbarButtonSize]];
      [buttonSizeConstraints addObject:[button.heightAnchor constraintEqualToConstant:self.palette.browserToolbarButtonSize]];
    }
    _buttonSizeConstraints = [buttonSizeConstraints copy];
    [NSLayoutConstraint activateConstraints:_buttonSizeConstraints];
    [self applyBrowserPalette];
    self.sendButton.enabled = NO;
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  [super setPalette:palette];
  [self applyBrowserPalette];
}

- (void)applyBrowserPalette {
  TLGlassPaneView *glass = (TLGlassPaneView *)self.backgroundView;
  glass.palette = self.palette;
  glass.cornerRadius = self.palette.messageInputCornerRadius;
  self.navigationStack.spacing = self.palette.space0;
  self.trailingStack.spacing = self.palette.space0;
  [self.trailingStack setCustomSpacing:self.palette.space2 afterView:self.chatButton];
  [self.trailingStack setCustomSpacing:self.palette.space3 afterView:self.responseCountLabel];
  self.responseCountLabel.font = self.palette.smallFont;
  self.responseCountLabel.textColor = self.palette.controlText;
  self.sendButtonSize = self.palette.composerButtonHeight - (self.palette.space3 * 2.0);
  self.sendButtonInset = self.palette.space3;
  self.sendButton.contentTintColor = self.palette.labelText;
  for (NSLayoutConstraint *constraint in self.buttonSizeConstraints) {
    constraint.constant = self.palette.browserToolbarButtonSize;
  }
  for (NSButton *button in @[self.backButton, self.forwardButton, self.reloadButton, self.chatButton, self.heightToggleButton]) {
    button.contentTintColor = self.palette.controlText;
    ((TLHoverIconButton *)button).palette = self.palette;
  }
  [self updateToolbarImages];
  [self setNeedsDisplay:YES];
}

- (void)layout {
  // Keep a usable text area and circular controls at the app's minimum width.
  CGFloat size = NSWidth(self.bounds) < self.palette.messageInputMinWidth + self.palette.browserToolbarButtonSize * 2
    ? self.palette.browserToolbarIconSize + self.palette.space3
    : self.palette.browserToolbarButtonSize;
  for (NSLayoutConstraint *constraint in self.buttonSizeConstraints) {
    if (constraint.constant != size) constraint.constant = size;
  }
  [super layout];
}

- (void)setDisplayedAddress:(NSString *)address {
  self.latestAddress = address;
  self.hasUserDraft = NO;
  self.textView.string = address;
  self.sendButton.enabled = address.length > 0;
  [self recalculateHeight];
}

- (void)updateDisplayedAddress:(NSString *)address {
  self.latestAddress = address;
  if (!self.hasUserDraft && self.window.firstResponder != self.textView) {
    [self setDisplayedAddress:address];
  }
}

- (void)beginPromptEditing {
  self.textView.string = @"";
  // Keep the current address separately and protect the empty draft from navigation updates.
  [self.textView didChangeText];
  [self.window makeFirstResponder:self.textView];
}

- (void)textDidEndEditing:(NSNotification *)notification {
  if (!self.hasUserDraft) { [self setDisplayedAddress:self.latestAddress ?: @""]; }
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(cancelOperation:)) {
    [self setDisplayedAddress:self.latestAddress ?: @""];
    [self.window makeFirstResponder:nil];
    return YES;
  }
  if (commandSelector == @selector(insertNewline:) && !(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)) {
    if (self.sendButton.enabled) {
      [NSApp sendAction:self.sendButton.action to:self.sendButton.target from:self.sendButton];
    }
    return YES;
  }
  return NO;
}

- (NSButton *)toolbarButtonWithToolTip:(NSString *)toolTip {
  TLHoverIconButton *button = [[TLHoverIconButton alloc] init];
  button.hoverSurfaceOnly = YES;
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.bordered = NO;
  button.imagePosition = NSImageOnly;
  button.imageScaling = NSImageScaleNone;
  button.focusRingType = NSFocusRingTypeNone;
  button.refusesFirstResponder = YES;
  button.keyEquivalent = @"";
  button.keyEquivalentModifierMask = 0;
  button.toolTip = toolTip;
  [button setAccessibilityLabel:toolTip];
  return button;
}

- (NSImage *)toolbarImageWithSystemName:(NSString *)systemName accessibilityDescription:(NSString *)description {
  NSImage *image = [NSImage imageWithSystemSymbolName:systemName accessibilityDescription:description];
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:self.palette.browserToolbarIconSize
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleMedium];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
  }
  image.template = YES;
  return image;
}

- (void)updateToolbarImages {
  self.chatButton.image = [self toolbarImageWithSystemName:@"text.bubble" accessibilityDescription:@"Show chat"];
  self.backButton.image = [self toolbarImageWithSystemName:@"chevron.left" accessibilityDescription:@"Back"];
  self.forwardButton.image = [self toolbarImageWithSystemName:@"chevron.right" accessibilityDescription:@"Forward"];
  self.reloadButton.image = [self toolbarImageWithSystemName:@"arrow.clockwise" accessibilityDescription:@"Reload"];
  NSString *toggleName = @"inset.filled.bottomthird.square";
  NSString *toggleDescription = self.isReducedHeight ? @"Use full-height browser" : @"Use reduced-height browser";
  self.heightToggleButton.image = [self toolbarImageWithSystemName:toggleName accessibilityDescription:toggleDescription];
  self.heightToggleButton.toolTip = toggleDescription;
  [self.heightToggleButton setAccessibilityLabel:toggleDescription];
}

- (void)setReducedHeight:(BOOL)reducedHeight {
  if (_reducedHeight == reducedHeight) {
    return;
  }
  _reducedHeight = reducedHeight;
  [self updateToolbarImages];
}

- (void)setResponseCount:(NSUInteger)responseCount {
  _responseCount = responseCount;
  self.responseCountLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)responseCount];
  self.responseCountLabel.hidden = !self.chatVisible || responseCount == 0;
  [self.chatButton setAccessibilityLabel:[NSString stringWithFormat:@"Show chat, %lu AI responses", (unsigned long)responseCount]];
}

- (void)setChatVisible:(BOOL)chatVisible {
  _chatVisible = chatVisible;
  self.chatButton.hidden = !chatVisible;
  self.responseCountLabel.hidden = !chatVisible || self.responseCount == 0;
}

@end

@interface TLTaskActivityIndicatorView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSArray<CALayer *> *dotLayers;
- (void)startAnimatingIfNeeded;
- (void)stopAnimating;
@end

@interface TLSidebarNavigationButton ()
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) TLTaskActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSImageView *accessoryImageView;
@property (nonatomic, strong) NSLayoutConstraint *imageLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *activityWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *activityHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *accessoryTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *accessoryWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *accessoryHeightConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLSidebarNavigationButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _systemIconName = @"";
    _accessorySystemIconName = @"";
    _forcesHoverState = NO;
    _showsActivityIndicatorIcon = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageAlignment = NSImageAlignCenter;
    _imageView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_imageView];

    _activityIndicatorView = [[TLTaskActivityIndicatorView alloc] init];
    _activityIndicatorView.hidden = YES;
    [self addSubview:_activityIndicatorView];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_titleLabel];

    _accessoryImageView = [[NSImageView alloc] init];
    _accessoryImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _accessoryImageView.imageAlignment = NSImageAlignCenter;
    _accessoryImageView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_accessoryImageView];

    _imageLeadingConstraint = [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                       constant:_palette.sidebarActionItemHorizontalInset];
    _imageWidthConstraint = [_imageView.widthAnchor constraintEqualToConstant:_palette.sidebarActionIconSize];
    _imageHeightConstraint = [_imageView.heightAnchor constraintEqualToConstant:_palette.sidebarActionIconSize];
    _activityWidthConstraint = [_activityIndicatorView.widthAnchor constraintEqualToConstant:_palette.taskStatusIndicatorSize];
    _activityHeightConstraint = [_activityIndicatorView.heightAnchor constraintEqualToConstant:_palette.taskStatusIndicatorSize];
    _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:_imageView.trailingAnchor
                                                                        constant:_palette.sidebarActionItemContentGap];
    _titleTrailingConstraint = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_accessoryImageView.leadingAnchor
                                                                                    constant:-_palette.space3];
    _accessoryTrailingConstraint = [_accessoryImageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                                     constant:-_palette.sidebarActionItemHorizontalInset];
    _accessoryWidthConstraint = [_accessoryImageView.widthAnchor constraintEqualToConstant:_palette.sidebarTileSystemIconSize];
    _accessoryHeightConstraint = [_accessoryImageView.heightAnchor constraintEqualToConstant:_palette.sidebarTileSystemIconSize];
    [NSLayoutConstraint activateConstraints:@[
      _imageLeadingConstraint,
      [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _imageWidthConstraint,
      _imageHeightConstraint,
      [_activityIndicatorView.centerXAnchor constraintEqualToAnchor:_imageView.centerXAnchor],
      [_activityIndicatorView.centerYAnchor constraintEqualToAnchor:_imageView.centerYAnchor],
      _activityWidthConstraint,
      _activityHeightConstraint,
      _titleLeadingConstraint,
      [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _titleTrailingConstraint,
      _accessoryTrailingConstraint,
      [_accessoryImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _accessoryWidthConstraint,
      _accessoryHeightConstraint,
    ]];

    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  return NSMakeSize(NSViewNoIntrinsicMetric, self.palette.fieldHeight);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self applyCurrentState];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.pressed = YES;
  [self applyCurrentState];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL inside = NSPointInRect(point, self.bounds);
  self.pressed = NO;
  self.hovered = inside;
  [self applyCurrentState];
  if (inside && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  BOOL active = self.selected || self.pressed;
  BOOL highlighted = active || self.hovered || self.forcesHoverState;
  if (!highlighted) {
    return;
  }

  NSRect rowRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rowRect
                                                       xRadius:palette.radiusMedium
                                                       yRadius:palette.radiusMedium];
  NSColor *fillColor = active ? palette.sidebarActiveSurface : palette.chromeHoverSurface;
  [fillColor setFill];
  [path fill];
}

- (nullable NSImage *)systemImageNamed:(NSString *)name pointSize:(CGFloat)pointSize {
  if (name.length == 0) {
    return nil;
  }

  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:self.title];
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleMedium];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
    image.template = YES;
    return image;
  }
  return nil;
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  BOOL highlighted = self.selected || self.hovered || self.pressed || self.forcesHoverState;
  NSColor *foreground = highlighted ? palette.appText : palette.labelText;
  BOOL showsAccessory = (self.hovered || self.forcesHoverState) && self.accessorySystemIconName.length > 0;

  self.titleLabel.stringValue = self.title;
  self.titleLabel.font = palette.labelFont;
  self.titleLabel.textColor = foreground;
  self.imageView.image = self.showsActivityIndicatorIcon ? nil : [self systemImageNamed:self.systemIconName pointSize:palette.sidebarActionIconSize];
  self.imageView.contentTintColor = foreground;
  self.imageView.hidden = self.showsActivityIndicatorIcon;
  self.activityIndicatorView.palette = palette;
  self.activityIndicatorView.hidden = !self.showsActivityIndicatorIcon;
  if (self.showsActivityIndicatorIcon) {
    [self.activityIndicatorView startAnimatingIfNeeded];
  } else {
    [self.activityIndicatorView stopAnimating];
  }
  self.accessoryImageView.image = [self systemImageNamed:self.accessorySystemIconName pointSize:palette.space8];
  self.accessoryImageView.contentTintColor = foreground;
  self.accessoryImageView.alphaValue = showsAccessory ? palette.sidebarAccessoryIconOpacity : palette.space0;
  self.accessoryImageView.hidden = !showsAccessory;
  self.imageLeadingConstraint.constant = palette.sidebarActionItemHorizontalInset;
  self.imageWidthConstraint.constant = palette.sidebarActionIconSize;
  self.imageHeightConstraint.constant = palette.sidebarActionIconSize;
  self.activityWidthConstraint.constant = palette.taskStatusIndicatorSize;
  self.activityHeightConstraint.constant = palette.taskStatusIndicatorSize;
  self.titleLeadingConstraint.constant = palette.sidebarActionItemContentGap;
  self.titleTrailingConstraint.constant = showsAccessory ? -palette.space3 : -palette.sidebarActionItemHorizontalInset;
  self.accessoryTrailingConstraint.constant = -palette.sidebarActionItemHorizontalInset;
  self.accessoryWidthConstraint.constant = showsAccessory ? palette.sidebarTileSystemIconSize : palette.space0;
  self.accessoryHeightConstraint.constant = showsAccessory ? palette.sidebarTileSystemIconSize : palette.space0;
  self.alphaValue = self.enabled ? 1.0 : palette.disabledOpacity;
  [self invalidateIntrinsicContentSize];
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setTitle:(NSString *)title {
  _title = [title copy] ?: @"";
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setAccessorySystemIconName:(NSString *)accessorySystemIconName {
  _accessorySystemIconName = [accessorySystemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setSelected:(BOOL)selected {
  _selected = selected;
  [self applyCurrentState];
}

- (void)setForcesHoverState:(BOOL)forcesHoverState {
  _forcesHoverState = forcesHoverState;
  [self applyCurrentState];
}

- (void)setShowsActivityIndicatorIcon:(BOOL)showsActivityIndicatorIcon {
  _showsActivityIndicatorIcon = showsActivityIndicatorIcon;
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

@end

static void TLDrawAvatarInitial(NSString *initial, NSRect rect, TLThemePalette *palette) {
  [palette.userMessageSurface setFill];
  [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, palette.borderWidth * 0.5,
                                                   palette.borderWidth * 0.5)] fill];
  NSAttributedString *text = [[NSAttributedString alloc] initWithString:initial
    attributes:@{NSFontAttributeName: palette.roleFont,
                 NSForegroundColorAttributeName: palette.userMessageText}];
  CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
  // Center the visible glyph, excluding the font's ascender/descender padding.
  CGRect glyphBounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(context);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  CGContextSetTextPosition(context, NSMidX(rect) - CGRectGetMidX(glyphBounds),
                          NSMidY(rect) - CGRectGetMidY(glyphBounds));
  CTLineDraw(line, context);
  CGContextRestoreGState(context);
  CFRelease(line);
}

NSImage *TLAvatarImageForDisplayName(NSString *displayName, TLThemePalette *palette) {
  NSString *name = [displayName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *initial = name.length > 0
    ? [[name substringWithRange:[name rangeOfComposedCharacterSequenceAtIndex:0]] uppercaseString]
    : @"?";
  NSSize size = NSMakeSize(palette.sidebarActionIconSize, palette.sidebarActionIconSize);
  NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
    TLDrawAvatarInitial(initial, rect, palette);
    return YES;
  }];
  image.template = NO;
  return image;
}

@interface TLAvatarInitialView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *initial;
@end

@implementation TLAvatarInitialView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _initial = @"";
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;

    [self applyCurrentState];
  }
  return self;
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  TLDrawAvatarInitial(self.initial, self.bounds, palette);
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.layer.backgroundColor = TLCGColor(palette.transparentSurface);
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setInitial:(NSString *)initial {
  _initial = [initial copy] ?: @"";
  [self applyCurrentState];
}

@end

@interface TLSidebarUserButton ()
@property (nonatomic, strong) TLAvatarInitialView *avatarView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSImageView *chevronView;
@property (nonatomic, strong) NSLayoutConstraint *avatarLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *avatarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *chevronLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *chevronTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *chevronWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *chevronHeightConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLSidebarUserButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _displayName = @"";
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    _avatarView = [[TLAvatarInitialView alloc] init];
    [self addSubview:_avatarView];

    _titleLabel = [NSTextField labelWithString:@""];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_titleLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                          forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_titleLabel];

    _chevronView = [[NSImageView alloc] init];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.imageAlignment = NSImageAlignCenter;
    _chevronView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_chevronView];

    _avatarLeadingConstraint = [_avatarView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                         constant:_palette.sidebarUserButtonHorizontalInset];
    _avatarWidthConstraint = [_avatarView.widthAnchor constraintEqualToConstant:_palette.sidebarActionIconSize];
    _avatarHeightConstraint = [_avatarView.heightAnchor constraintEqualToConstant:_palette.sidebarActionIconSize];
    _titleLeadingConstraint = [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor
                                                                        constant:_palette.sidebarActionItemContentGap];
    _titleTrailingConstraint = [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor
                                                                                    constant:-_palette.space3];
    _chevronLeadingConstraint = [_chevronView.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor
                                                                           constant:_palette.space3];
    _chevronTrailingConstraint = [_chevronView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor
                                                                                       constant:-_palette.sidebarUserButtonHorizontalInset];
    _chevronWidthConstraint = [_chevronView.widthAnchor constraintEqualToConstant:_palette.space6];
    _chevronHeightConstraint = [_chevronView.heightAnchor constraintEqualToConstant:_palette.space6];

    [NSLayoutConstraint activateConstraints:@[
      _avatarLeadingConstraint,
      [_avatarView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _avatarWidthConstraint,
      _avatarHeightConstraint,
      _titleLeadingConstraint,
      [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _titleTrailingConstraint,
      _chevronLeadingConstraint,
      _chevronTrailingConstraint,
      [_chevronView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _chevronWidthConstraint,
      _chevronHeightConstraint,
    ]];

    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  TLThemePalette *palette = self.palette;
  CGFloat width = palette.sidebarUserButtonHorizontalInset * 2.0 +
    palette.sidebarActionIconSize + palette.sidebarActionItemContentGap +
    ceil(self.titleLabel.intrinsicContentSize.width) + palette.space3 + palette.space6;
  return NSMakeSize(width, palette.sidebarUserButtonHeight);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self applyCurrentState];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self applyCurrentState];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.pressed = YES;
  [self applyCurrentState];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL inside = NSPointInRect(point, self.bounds);
  self.pressed = NO;
  self.hovered = inside;
  [self applyCurrentState];
  if (inside && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if (!self.hovered && !self.pressed) {
    return;
  }

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSRect rowRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rowRect
                                                       xRadius:palette.radiusMedium
                                                       yRadius:palette.radiusMedium];
  NSColor *fillColor = self.pressed ? palette.sidebarActiveSurface : palette.chromeHoverSurface;
  [fillColor setFill];
  [path fill];
}

- (nullable NSImage *)systemImageNamed:(NSString *)name {
  if (name.length == 0) {
    return nil;
  }

  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:self.displayName];
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:self.palette.space6
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleSmall];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
    image.template = YES;
    return image;
  }
  return nil;
}

- (NSString *)avatarInitial {
  NSString *trimmedName = [self.displayName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmedName.length == 0) {
    return @"?";
  }

  return [[trimmedName substringToIndex:1] uppercaseString];
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSColor *foreground = (self.hovered || self.pressed) ? palette.appText : palette.labelText;

  self.avatarView.palette = palette;
  self.avatarView.initial = [self avatarInitial];
  self.titleLabel.stringValue = self.displayName;
  self.titleLabel.font = palette.sidebarActionTitleFont;
  self.titleLabel.textColor = foreground;
  self.chevronView.image = [self systemImageNamed:@"chevron.down"];
  self.chevronView.contentTintColor = foreground;

  self.avatarLeadingConstraint.constant = palette.sidebarUserButtonHorizontalInset;
  self.avatarWidthConstraint.constant = palette.sidebarActionIconSize;
  self.avatarHeightConstraint.constant = palette.sidebarActionIconSize;
  self.titleLeadingConstraint.constant = palette.sidebarActionItemContentGap;
  self.titleTrailingConstraint.constant = -palette.space3;
  self.chevronLeadingConstraint.constant = palette.space3;
  self.chevronTrailingConstraint.constant = -palette.sidebarUserButtonHorizontalInset;
  self.chevronWidthConstraint.constant = palette.space6;
  self.chevronHeightConstraint.constant = palette.space6;
  self.alphaValue = self.enabled ? 1.0 : palette.disabledOpacity;
  [self invalidateIntrinsicContentSize];
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
}

- (void)setDisplayName:(NSString *)displayName {
  _displayName = [displayName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
}

@end

static const NSInteger TLTaskStatusIndicatorColumns = 3;
static const NSInteger TLTaskStatusIndicatorDotCount = 9;
static NSString * const TLTaskStatusBlinkAnimationKey = @"tlTaskStatusBlink";

@implementation TLTaskActivityIndicatorView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    [self buildDotLayers];
    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  return NSMakeSize(self.palette.taskStatusIndicatorSize, self.palette.taskStatusIndicatorSize);
}

- (void)buildDotLayers {
  NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithCapacity:TLTaskStatusIndicatorDotCount];
  for (NSInteger index = 0; index < TLTaskStatusIndicatorDotCount; index += 1) {
    CALayer *dotLayer = [CALayer layer];
    dotLayer.opacity = self.palette.taskStatusIndicatorInactiveOpacity;
    [self.layer addSublayer:dotLayer];
    [layers addObject:dotLayer];
  }
  self.dotLayers = layers;
}

- (void)layout {
  [super layout];
  [self layoutDotLayers];
  [self startAnimatingIfNeeded];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window) {
    [self startAnimatingIfNeeded];
  } else {
    [self stopAnimating];
  }
}

- (void)layoutDotLayers {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CGFloat dotLength = MIN(palette.taskStatusIndicatorDotSize, MIN(NSWidth(self.bounds), NSHeight(self.bounds)) / TLTaskStatusIndicatorColumns);
  CGFloat availableLength = MIN(NSWidth(self.bounds), NSHeight(self.bounds));
  CGFloat gap = MAX(palette.borderWidth, (availableLength - (dotLength * TLTaskStatusIndicatorColumns)) / (TLTaskStatusIndicatorColumns - 1));
  CGFloat gridLength = (dotLength * TLTaskStatusIndicatorColumns) + (gap * (TLTaskStatusIndicatorColumns - 1));
  CGFloat startX = floor((NSWidth(self.bounds) - gridLength) * 0.5);
  CGFloat startY = floor((NSHeight(self.bounds) - gridLength) * 0.5);

  for (NSUInteger index = 0; index < self.dotLayers.count; index += 1) {
    NSInteger row = (NSInteger)index / TLTaskStatusIndicatorColumns;
    NSInteger column = (NSInteger)index % TLTaskStatusIndicatorColumns;
    CALayer *dotLayer = self.dotLayers[index];
    dotLayer.frame = NSMakeRect(startX + (column * (dotLength + gap)),
                                startY + (row * (dotLength + gap)),
                                dotLength,
                                dotLength);
    dotLayer.cornerRadius = dotLength * 0.5;
  }
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.layer.backgroundColor = TLCGColor(palette.transparentSurface);
  for (CALayer *dotLayer in self.dotLayers) {
    dotLayer.backgroundColor = TLCGColor(palette.labelText);
    if (![dotLayer animationForKey:TLTaskStatusBlinkAnimationKey]) {
      dotLayer.opacity = palette.taskStatusIndicatorInactiveOpacity;
    }
  }
  [CATransaction commit];
  [self invalidateIntrinsicContentSize];
  [self layoutDotLayers];
  [self startAnimatingIfNeeded];
}

- (void)startAnimatingIfNeeded {
  if (!self.window) {
    return;
  }

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  CFTimeInterval now = CACurrentMediaTime();
  CFTimeInterval delayStep = palette.taskStatusIndicatorBlinkDuration / (TLTaskStatusIndicatorDotCount * 2);
  for (NSUInteger index = 0; index < self.dotLayers.count; index += 1) {
    CALayer *dotLayer = self.dotLayers[index];
    if ([dotLayer animationForKey:TLTaskStatusBlinkAnimationKey]) {
      continue;
    }

    NSInteger row = (NSInteger)index / TLTaskStatusIndicatorColumns;
    NSInteger column = (NSInteger)index % TLTaskStatusIndicatorColumns;
    NSInteger center = TLTaskStatusIndicatorColumns / 2;
    NSInteger distanceFromCenter = labs(row - center) + labs(column - center);
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    animation.values = @[
      @(palette.taskStatusIndicatorInactiveOpacity),
      @(1.0),
      @(palette.taskStatusIndicatorInactiveOpacity),
    ];
    animation.keyTimes = @[ @0.0, @0.45, @1.0 ];
    animation.duration = palette.taskStatusIndicatorBlinkDuration;
    animation.beginTime = now + (distanceFromCenter * delayStep);
    animation.repeatCount = HUGE_VALF;
    animation.removedOnCompletion = NO;
    [dotLayer addAnimation:animation forKey:TLTaskStatusBlinkAnimationKey];
  }
}

- (void)stopAnimating {
  for (CALayer *dotLayer in self.dotLayers) {
    [dotLayer removeAnimationForKey:TLTaskStatusBlinkAnimationKey];
    dotLayer.opacity = self.palette.taskStatusIndicatorInactiveOpacity;
  }
}

- (void)setPalette:(TLThemePalette *)palette {
  TLThemePalette *resolvedPalette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if (_palette == resolvedPalette) {
    return;
  }

  _palette = resolvedPalette;
  [self applyCurrentState];
}

@end

@interface TLTaskStatusPillView ()
@property (nonatomic, strong) TLTaskActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSLayoutConstraint *activityWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *activityHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *activityLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleTrailingConstraint;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLTaskStatusPillView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _showsActivityIndicator = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    [self buildInterface];
    [self applyCurrentState];
  }
  return self;
}

- (void)buildInterface {
  self.activityIndicatorView = [[TLTaskActivityIndicatorView alloc] init];
  [self addSubview:self.activityIndicatorView];

  self.titleLabel = [NSTextField labelWithString:@""];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.titleLabel.usesSingleLineMode = YES;
  [self addSubview:self.titleLabel];

  self.activityLeadingConstraint = [self.activityIndicatorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                                            constant:self.palette.space5];
  self.activityWidthConstraint = [self.activityIndicatorView.widthAnchor constraintEqualToConstant:self.palette.taskStatusIndicatorSize];
  self.activityHeightConstraint = [self.activityIndicatorView.heightAnchor constraintEqualToConstant:self.palette.taskStatusIndicatorSize];
  self.titleLeadingConstraint = [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.activityIndicatorView.trailingAnchor
                                                                              constant:self.palette.space4];
  self.titleTrailingConstraint = [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                                constant:-self.palette.space5];

  [NSLayoutConstraint activateConstraints:@[
    self.activityLeadingConstraint,
    [self.activityIndicatorView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.activityWidthConstraint,
    self.activityHeightConstraint,
    self.titleLeadingConstraint,
    [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.titleTrailingConstraint,
  ]];
}

- (BOOL)mouseDownCanMoveWindow {
  return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
  self.hovered = YES;
  [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
  self.hovered = NO;
  self.pressed = NO;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  self.pressed = YES;
  [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  BOOL inside = NSPointInRect(point, self.bounds);
  self.pressed = NO;
  self.hovered = inside;
  [self setNeedsDisplay:YES];
  if (inside && self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (NSSize)intrinsicContentSize {
  CGFloat titleWidth = self.titleLabel.intrinsicContentSize.width;
  CGFloat width = self.palette.space5 + titleWidth + self.palette.space5;
  if (self.showsActivityIndicator) {
    width += self.palette.taskStatusIndicatorSize + self.palette.space4;
  }
  return NSMakeSize(width, self.palette.taskStatusPillHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSRect borderRect = NSInsetRect(self.bounds, palette.borderWidth * 0.5, palette.borderWidth * 0.5);
  CGFloat radius = MIN(palette.radiusPill, NSHeight(borderRect) * 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:borderRect xRadius:radius yRadius:radius];
  BOOL hovered = self.hovered || self.forcesHoverState;
  NSColor *fillColor = self.pressed
    ? palette.sidebarActiveSurface
    : (hovered ? palette.chromeHoverSurface : palette.taskStatusPillSurface);
  [fillColor setFill];
  [path fill];
  [palette.taskStatusPillBorder setStroke];
  path.lineWidth = palette.borderWidth;
  [path stroke];
}

- (void)applyCurrentState {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.activityIndicatorView.palette = palette;
  self.activityIndicatorView.hidden = !self.showsActivityIndicator;
  if (self.showsActivityIndicator) {
    [self.activityIndicatorView startAnimatingIfNeeded];
  } else {
    [self.activityIndicatorView stopAnimating];
  }
  self.titleLabel.stringValue = self.title;
  self.titleLabel.font = palette.labelFont;
  self.titleLabel.textColor = palette.labelText;
  self.titleLabel.alignment = self.showsActivityIndicator ? NSTextAlignmentLeft : NSTextAlignmentCenter;
  self.activityLeadingConstraint.constant = self.showsActivityIndicator ? palette.space5 : palette.space0;
  self.activityWidthConstraint.constant = self.showsActivityIndicator ? palette.taskStatusIndicatorSize : palette.space0;
  self.activityHeightConstraint.constant = self.showsActivityIndicator ? palette.taskStatusIndicatorSize : palette.space0;
  self.titleLeadingConstraint.constant = self.showsActivityIndicator ? palette.space4 : palette.space5;
  self.titleTrailingConstraint.constant = -palette.space5;
  self.layer.backgroundColor = TLCGColor(palette.transparentSurface);
  [self invalidateIntrinsicContentSize];
  [self setNeedsDisplay:YES];
}

- (void)setPalette:(TLThemePalette *)palette {
  TLThemePalette *resolvedPalette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if (_palette == resolvedPalette) {
    return;
  }

  _palette = resolvedPalette;
  [self applyCurrentState];
}

- (void)setTitle:(NSString *)title {
  NSString *resolvedTitle = title ?: @"";
  if ([_title isEqualToString:resolvedTitle]) {
    return;
  }

  _title = [resolvedTitle copy];
  [self applyCurrentState];
}

- (void)setForcesHoverState:(BOOL)forcesHoverState {
  if (_forcesHoverState == forcesHoverState) {
    return;
  }

  _forcesHoverState = forcesHoverState;
  [self setNeedsDisplay:YES];
}

- (void)setShowsActivityIndicator:(BOOL)showsActivityIndicator {
  if (_showsActivityIndicator == showsActivityIndicator) {
    return;
  }

  _showsActivityIndicator = showsActivityIndicator;
  [self applyCurrentState];
}

@end

@interface TLSidebarResizeHandle ()
@property (nonatomic, readwrite) CGFloat dragDeltaX;
@property (nonatomic, readwrite) TLSidebarResizeHandlePhase dragPhase;
@property (nonatomic) CGFloat dragStartX;
@end

@implementation TLSidebarResizeHandle

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _dragDeltaX = 0.0;
    _dragPhase = TLSidebarResizeHandlePhaseNone;
    self.translatesAutoresizingMaskIntoConstraints = NO;
  }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)resetCursorRects {
  [super resetCursorRects];
  [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event {
  self.dragStartX = event.locationInWindow.x;
  self.dragDeltaX = 0.0;
  self.dragPhase = TLSidebarResizeHandlePhaseBegan;
  [self sendResizeAction];
}

- (void)mouseDragged:(NSEvent *)event {
  self.dragDeltaX = event.locationInWindow.x - self.dragStartX;
  self.dragPhase = TLSidebarResizeHandlePhaseChanged;
  [self sendResizeAction];
}

- (void)mouseUp:(NSEvent *)event {
  self.dragDeltaX = event.locationInWindow.x - self.dragStartX;
  self.dragPhase = TLSidebarResizeHandlePhaseEnded;
  [self sendResizeAction];
  self.dragPhase = TLSidebarResizeHandlePhaseNone;
}

- (void)sendResizeAction {
  if (self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

@end

@implementation TLHistoryRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
  [self drawGreySelection];
}

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
  [super drawBackgroundInRect:dirtyRect];

  if (self.selected) {
    [self drawGreySelection];
  }
}

- (void)drawGreySelection {
  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [palette.historyRowActiveSurface setFill];
  NSRect selectedRect = NSInsetRect(self.bounds, palette.historyRowSelectionHorizontalInset, palette.historyRowSelectionVerticalInset);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:selectedRect
                                                       xRadius:palette.radiusMedium
                                                       yRadius:palette.radiusMedium];
  [path fill];
}

@end

@implementation TLBrandMarkView

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSRect bounds = NSInsetRect(self.bounds, palette.brandMarkInset, palette.brandMarkInset);
  [palette.brandMark setStroke];
  [palette.brandMark setFill];

  NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:bounds];
  circle.lineWidth = palette.brandMarkStrokeWidth;
  [circle stroke];

  CGFloat midX = NSMidX(bounds);
  CGFloat midY = NSMidY(bounds);
  CGFloat radius = palette.brandMarkDotRadius;
  NSRect dot = NSMakeRect(midX - radius, midY - radius, radius * 2.0, radius * 2.0);
  [[NSBezierPath bezierPathWithOvalInRect:dot] fill];

  CGFloat crossInset = palette.brandMarkCrossInset;
  NSBezierPath *cross = [NSBezierPath bezierPath];
  cross.lineWidth = palette.brandMarkStrokeWidth;
  [cross moveToPoint:NSMakePoint(midX, NSMinY(bounds) + crossInset)];
  [cross lineToPoint:NSMakePoint(midX, NSMaxY(bounds) - crossInset)];
  [cross moveToPoint:NSMakePoint(NSMinX(bounds) + crossInset, midY)];
  [cross lineToPoint:NSMakePoint(NSMaxX(bounds) - crossInset, midY)];
  [cross stroke];
}

@end

@implementation TLActionTrampoline
- (void)perform:(id)sender {
  if (self.block) {
    self.block();
  }
}
@end
