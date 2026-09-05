#import "TLWorkspaceOutlineView.h"
#import "TLChromeTabView.h"
#import "UIComponents.h"
#import <QuartzCore/QuartzCore.h>

@interface TLWorkspaceOutlineView ()
@property (nonatomic, strong) CAShapeLayer *outlineLayer;
@property (nonatomic, strong) CALayer *shadowLayer;
@property (nonatomic, strong) CAShapeLayer *shadowMask;
@end

@implementation TLWorkspaceOutlineView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _shadowLayer = [CALayer layer];
    _shadowMask = [CAShapeLayer layer];
    _shadowMask.fillRule = kCAFillRuleEvenOdd;
    _shadowLayer.mask = _shadowMask;
    [self.layer addSublayer:_shadowLayer];
    _outlineLayer = [CAShapeLayer layer];
    [self.layer addSublayer:_outlineLayer];
  }
  return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self updateOutline]; }
- (void)layout { [super layout]; [self updateOutline]; }

- (CGAffineTransform)transformFromView:(NSView *)view {
  NSPoint origin = [view convertPoint:NSZeroPoint toView:self];
  NSPoint x = [view convertPoint:NSMakePoint(1, 0) toView:self];
  NSPoint y = [view convertPoint:NSMakePoint(0, 1) toView:self];
  return CGAffineTransformMake(x.x - origin.x, x.y - origin.y,
                               y.x - origin.x, y.y - origin.y, origin.x, origin.y);
}

- (void)updateOutline {
  if (!self.contentView || !self.superview) return;
  CGPathRef content = [self.contentView newOutlinePath];
  CGAffineTransform contentTransform = [self transformFromView:self.contentView];
  CGPathRef outline = CGPathCreateCopyByTransformingPath(content, &contentTransform);
  CGPathRelease(content);
  if (self.selectionView && !self.selectionView.isHiddenOrHasHiddenAncestor &&
      !NSIsEmptyRect(self.selectionView.selectionFrame)) {
    CGPathRef tab = [self.selectionView newOutlinePath];
    CGAffineTransform tabTransform = [self transformFromView:self.selectionView];
    CGPathRef positionedTab = CGPathCreateCopyByTransformingPath(tab, &tabTransform);
    // Auto Layout can leave the touching edges a fraction of a pixel apart.
    // Extend only the tab's bottom edge into the content for the outline union;
    // its top, body geometry and the actual filled surfaces remain unchanged.
    CGFloat pixel = 1.0 / (self.window.backingScaleFactor ?: 1.0);
    CGFloat bottom = CGRectGetMinY(CGPathGetBoundingBox(positionedTab));
    CGFloat contentTop = CGRectGetMaxY(CGPathGetBoundingBox(outline));
    if (fabs(bottom - contentTop) <= pixel) {
      CGMutablePathRef weldedTab = CGPathCreateMutable();
      CGPathApplyWithBlock(positionedTab, ^(const CGPathElement *element) {
        CGPoint points[3];
        NSUInteger count = element->type == kCGPathElementAddCurveToPoint ? 3 :
          element->type == kCGPathElementAddQuadCurveToPoint ? 2 :
          element->type == kCGPathElementCloseSubpath ? 0 : 1;
        for (NSUInteger i = 0; i < count; i++) {
          points[i] = element->points[i];
          if (fabs(points[i].y - bottom) < 0.00001) points[i].y = contentTop - pixel;
        }
        switch (element->type) {
          case kCGPathElementMoveToPoint: CGPathMoveToPoint(weldedTab, NULL, points[0].x, points[0].y); break;
          case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(weldedTab, NULL, points[0].x, points[0].y); break;
          case kCGPathElementAddQuadCurveToPoint: CGPathAddQuadCurveToPoint(weldedTab, NULL, points[0].x, points[0].y, points[1].x, points[1].y); break;
          case kCGPathElementAddCurveToPoint: CGPathAddCurveToPoint(weldedTab, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y); break;
          case kCGPathElementCloseSubpath: CGPathCloseSubpath(weldedTab); break;
        }
      });
      CGPathRelease(positionedTab);
      positionedTab = weldedTab;
    }
    CGPathRef joined = CGPathCreateCopyByUnioningPath(outline, positionedTab, false);
    if (joined) { CGPathRelease(outline); outline = joined; }
    CGPathRelease(positionedTab);
    CGPathRelease(tab);
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.outlineLayer.frame = self.bounds;
  self.outlineLayer.path = outline;
  self.outlineLayer.fillColor = TLCGColor(self.palette.transparentSurface);
  self.outlineLayer.strokeColor = TLCGColor(self.palette.controlBorder);
  self.outlineLayer.lineWidth = self.palette.borderWidth;
  self.outlineLayer.opacity = self.palette.workspaceOutlineOpacity;
  // Reuse the exact welded outline for a single shadow. The exterior-only
  // mask prevents this overlay from shading content or the tab/content join.
  self.shadowLayer.frame = self.bounds;
  self.shadowLayer.shadowPath = outline;
  self.shadowLayer.shadowColor = TLCGColor(self.palette.contentShadow);
  self.shadowLayer.shadowRadius = self.palette.workspaceShadowRadius;
  self.shadowLayer.shadowOffset = CGSizeMake(self.palette.space0, self.palette.workspaceShadowOffsetY);
  self.shadowLayer.shadowOpacity = self.palette.workspaceShadowOpacity;
  CGMutablePathRef exterior = CGPathCreateMutable();
  CGPathAddRect(exterior, NULL, self.bounds);
  CGPathAddPath(exterior, NULL, outline);
  self.shadowMask.frame = self.bounds;
  self.shadowMask.path = exterior;
  self.shadowMask.fillColor = TLCGColor(self.palette.tabBackground);
  CGPathRelease(exterior);
  self.hidden = self.contentView.isHiddenOrHasHiddenAncestor;
  [CATransaction commit];
  CGPathRelease(outline);
}
@end
