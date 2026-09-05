#import "TLWorkspaceOutlineView.h"
#import "TLChromeTabView.h"
#import "UIComponents.h"
#import <QuartzCore/QuartzCore.h>

@interface TLWorkspaceOutlineView ()
@property (nonatomic, strong) CAShapeLayer *outlineLayer;
@end

@implementation TLWorkspaceOutlineView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
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
  self.hidden = self.contentView.isHiddenOrHasHiddenAncestor;
  [CATransaction commit];
  CGPathRelease(outline);
}
@end
