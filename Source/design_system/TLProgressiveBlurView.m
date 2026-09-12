#import "TLProgressiveBlurView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

@implementation TLProgressiveBlurView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
  }
  return self;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self updateBlur]; }
- (void)layout { [super layout]; [self updateBlur]; }
- (void)updateBlur {
  if (!self.palette || NSIsEmptyRect(self.bounds)) return;
  CIFilter *gradient = [CIFilter filterWithName:@"CILinearGradient"];
  [gradient setValue:[CIVector vectorWithX:0 Y:NSHeight(self.bounds)] forKey:@"inputPoint0"];
  [gradient setValue:[CIVector vectorWithX:0 Y:0] forKey:@"inputPoint1"];
  [gradient setValue:[CIColor colorWithCGColor:TLCGColor(self.palette.transparentSurface)] forKey:@"inputColor0"];
  [gradient setValue:[CIColor colorWithCGColor:TLCGColor(self.palette.controlText)] forKey:@"inputColor1"];
  // The mask is coverage, not a painted color: map alpha to luminance so both
  // themes produce the same clear-to-blurred progression.
  CIFilter *coverage = [CIFilter filterWithName:@"CIColorMatrix"];
  [coverage setValue:gradient.outputImage forKey:kCIInputImageKey];
  for (NSString *key in @[@"inputRVector",@"inputGVector",@"inputBVector"])
    [coverage setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:key];
  CIFilter *blur = [CIFilter filterWithName:@"CIMaskedVariableBlur"];
  [blur setValue:[coverage.outputImage imageByCroppingToRect:self.bounds] forKey:@"inputMask"];
  [blur setValue:@(self.palette.browserBottomBlurRadius) forKey:kCIInputRadiusKey];
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  // Let AppKit retain and configure Core Image rendering for its backing layer.
  // Direct layer assignment bypasses that setup and can be lost on later redraws.
  self.backgroundFilters = @[blur];
  self.layer.backgroundColor = TLCGColor(self.palette.chatInputBackdrop);
  [CATransaction commit];
}
@end
