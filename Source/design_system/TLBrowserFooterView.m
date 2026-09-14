#import "TLBrowserFooterView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

@interface TLBrowserFooterView ()
@property (nonatomic) NSRect appliedBlurBounds;
@property (nonatomic) BOOL hasAppliedBlur;
@property (nonatomic, strong) CAShapeLayer *footerMask;
@end

@implementation TLBrowserFooterView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    self.footerMask = [CAShapeLayer layer];
    self.layer.mask = self.footerMask;
  }
  return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; self.hasAppliedBlur = NO; [self updateBlur]; }
- (void)layout { [super layout]; [self updateBlur]; }
- (void)updateBlur {
  if (!self.palette || NSIsEmptyRect(self.bounds)) return;
  if (self.hasAppliedBlur && NSEqualRects(self.appliedBlurBounds,self.bounds) && self.backgroundFilters.count) return;
  CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
  [blur setValue:@(self.palette.browserBottomBlurRadius) forKey:kCIInputRadiusKey];
  // Gaussian blur loses alpha at the captured page edges. CIColorMatrix
  // operates on unpremultiplied color, so restoring coverage keeps that color
  // intact instead of blending transparent edges into a dark frame.
  CIFilter *coverage = [CIFilter filterWithName:@"CIColorMatrix"];
  [coverage setDefaults];
  [coverage setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputAVector"];
  [coverage setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputBiasVector"];
  CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
  CGFloat radius = MIN(self.palette.radiusMedium, MIN(width / 2, height));
  // The center stays clear for one radius above the footer. Only the two
  // outer wedges extend upward, rounding the page's visible bottom corners.
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, NULL, 0, 0);
  CGPathAddLineToPoint(path, NULL, width, 0);
  CGPathAddLineToPoint(path, NULL, width, height);
  CGPathAddArc(path, NULL, width - radius, height, radius, 0, -M_PI_2, true);
  CGPathAddLineToPoint(path, NULL, radius, height - radius);
  CGPathAddArc(path, NULL, radius, height, radius, -M_PI_2, -M_PI, true);
  CGPathCloseSubpath(path);
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  // AppKit owns Core Image setup for its backing layer, including redraws.
  self.backgroundFilters = @[blur, coverage];
  self.layer.backgroundColor = TLCGColor(self.palette.chatInputBackdrop);
  self.footerMask.frame = self.bounds;
  self.footerMask.path = path;
  self.footerMask.fillColor = TLCGColor(self.palette.controlText);
  [CATransaction commit];
  CGPathRelease(path);
  self.appliedBlurBounds = self.bounds;
  self.hasAppliedBlur = YES;
}
@end
