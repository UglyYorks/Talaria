#import "TLChromeTabView.h"
#import "TLTabIconView.h"
#import "TLTransitionCoordinator.h"
#import <QuartzCore/QuartzCore.h>

CGFloat TLChromeTabInterTabOverlapForWidth(CGFloat width, TLThemePalette *palette) {
  CGFloat flareOutset = MIN(palette.tabFlareRadius, width * 0.18);
  CGFloat tightening = palette.tabFlareRadius > 0
    ? palette.tabInterTabTightening * flareOutset / palette.tabFlareRadius : 0;
  return flareOutset + tightening;
}

static NSBezierPath *TLChromeTabBackgroundPath(NSRect rect,
                                               TLThemePalette *palette,
                                               CGFloat requestedLeadingFlareOutset) {
  CGFloat radius = MIN(palette.radiusMedium, NSHeight(rect) * 0.45);
  CGFloat flareOutset = MIN(palette.tabActiveFlareRadius, rect.size.width * 0.18);
  CGFloat flareHeight = MIN(palette.tabActiveFlareRadius, rect.size.height * 0.5);
  CGFloat leadingFlareOutset = requestedLeadingFlareOutset >= 0.0
    ? MIN(flareOutset, requestedLeadingFlareOutset)
    : flareOutset;
  CGFloat leadingFlareRadius = MIN(leadingFlareOutset, flareHeight);
  CGFloat trailingFlareRadius = MIN(flareOutset, flareHeight);
  CGFloat minX = NSMinX(rect);
  CGFloat maxX = NSMaxX(rect);
  CGFloat minY = NSMinY(rect);
  CGFloat maxY = NSMaxY(rect);
  CGFloat leftBodyX = minX + leadingFlareOutset;
  CGFloat rightBodyX = maxX - flareOutset;
  CGFloat leftFlareX = leftBodyX - leadingFlareRadius;
  CGFloat rightFlareX = rightBodyX + trailingFlareRadius;

  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint(leftFlareX, minY)];
  [path lineToPoint:NSMakePoint(rightFlareX, minY)];
  [path appendBezierPathWithArcWithCenter:NSMakePoint(rightFlareX, minY + trailingFlareRadius)
                                   radius:trailingFlareRadius
                               startAngle:270.0
                                 endAngle:180.0
                                clockwise:YES];
  [path lineToPoint:NSMakePoint(rightBodyX, maxY - radius)];
  [path curveToPoint:NSMakePoint(rightBodyX - radius, maxY)
       controlPoint1:NSMakePoint(rightBodyX, maxY - radius * 0.45)
       controlPoint2:NSMakePoint(rightBodyX - radius * 0.45, maxY)];
  [path lineToPoint:NSMakePoint(leftBodyX + radius, maxY)];
  [path curveToPoint:NSMakePoint(leftBodyX, maxY - radius)
       controlPoint1:NSMakePoint(leftBodyX + radius * 0.45, maxY)
       controlPoint2:NSMakePoint(leftBodyX, maxY - radius * 0.45)];
  [path lineToPoint:NSMakePoint(leftBodyX, minY + leadingFlareRadius)];
  if (leadingFlareRadius > 0.0) {
    [path appendBezierPathWithArcWithCenter:NSMakePoint(leftFlareX, minY + leadingFlareRadius)
                                     radius:leadingFlareRadius
                                 startAngle:0.0
                                   endAngle:270.0
                                  clockwise:YES];
  } else {
    [path lineToPoint:NSMakePoint(leftFlareX, minY)];
  }
  [path closePath];
  return path;
}

static CGPathRef TLCreateCGPathFromBezierPath(NSBezierPath *bezierPath) CF_RETURNS_RETAINED {
  CGMutablePathRef path = CGPathCreateMutable();
  NSPoint points[3];
  for (NSInteger index = 0; index < bezierPath.elementCount; index += 1) {
    switch ([bezierPath elementAtIndex:index associatedPoints:points]) {
      case NSBezierPathElementMoveTo:
        CGPathMoveToPoint(path, nil, points[0].x, points[0].y);
        break;
      case NSBezierPathElementLineTo:
        CGPathAddLineToPoint(path, nil, points[0].x, points[0].y);
        break;
      case NSBezierPathElementCurveTo:
        CGPathAddCurveToPoint(path, nil,
                              points[0].x, points[0].y,
                              points[1].x, points[1].y,
                              points[2].x, points[2].y);
        break;
      case NSBezierPathElementClosePath:
        CGPathCloseSubpath(path);
        break;
      case NSBezierPathElementQuadraticCurveTo:
        CGPathAddQuadCurveToPoint(path, nil,
                                  points[0].x, points[0].y,
                                  points[1].x, points[1].y);
        break;
    }
  }
  return path;
}

static CGPathRef TLCreateTabLifecycleMaskPath(NSRect rect) CF_RETURNS_RETAINED {
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, nil, NSMinX(rect), NSMinY(rect));
  CGPathAddLineToPoint(path, nil, NSMaxX(rect), NSMinY(rect));
  CGPathAddLineToPoint(path, nil, NSMaxX(rect), NSMaxY(rect));
  CGPathAddLineToPoint(path, nil, NSMinX(rect), NSMaxY(rect));
  CGPathCloseSubpath(path);
  return path;
}

// Preserve only the small native chrome surface when a wave is interrupted.
// This never snapshots web content, and replaces rather than accumulates layers.
static CGImageRef TLChromeWaveImage(CALayer *layer, CGRect rect, CGFloat scale) CF_RETURNS_RETAINED {
  size_t width=ceil(CGRectGetWidth(rect)*scale),height=ceil(CGRectGetHeight(rect)*scale);
  if(!width || !height || width>16384 || height>1024)return nil;
  CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(space);if(!context)return nil;
  CGContextScaleCTM(context,scale,scale);
  CGContextTranslateCTM(context,-CGRectGetMinX(rect),-CGRectGetMinY(rect));
  [layer renderInContext:context];
  CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);return image;
}

@interface TLChromeTabSelectionView ()
@property (nonatomic, strong) CAShapeLayer *backgroundLayer;
@property (nonatomic, strong) CALayer *frozenBackground;
@property (nonatomic, strong) CAShapeLayer *waveLayer;
@property (nonatomic, strong) CAGradientLayer *waveMask;
@property (nonatomic) CGFloat waveProgress;
@property (nonatomic) CGFloat waveTimeProgress;
@property (nonatomic) NSTimeInterval waveDuration;
@property (nonatomic) CGFloat waveFeather;
@property (nonatomic) CGFloat waveContrast;
@property (nonatomic, strong) NSColor *waveStartText;
@property (nonatomic, strong) NSColor *waveEndText;
@property (nonatomic) BOOL waveActive;
@property (nonatomic, strong) TLTransitionCoordinator *colorTransition;
@property (nonatomic, strong) NSColor *contentBackgroundColor;
@property (nonatomic, strong, readwrite) NSColor *displayedBackgroundColor;
@property (nonatomic, strong, readwrite) NSColor *displayedTextColor;
@property (nonatomic, readwrite) NSRect selectionFrame;
@end

@implementation TLChromeTabSelectionView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _leadingFlareOutset = -1.0;
    self.wantsLayer = YES;
    _colorTransition = [TLTransitionCoordinator new];
    _backgroundLayer = [CAShapeLayer layer];
    [self.layer addSublayer:_backgroundLayer];
    _frozenBackground=[CALayer layer];_frozenBackground.hidden=YES;
    [self.layer addSublayer:_frozenBackground];
    _waveLayer = [CAShapeLayer layer];
    _waveMask = [CAGradientLayer layer];
    _waveMask.startPoint=CGPointMake(0.5,0);
    _waveMask.endPoint=CGPointMake(0.5,1);
    _waveMask.locations=@[@0,@0.375,@0.625,@1];
    _waveLayer.mask = _waveMask;
    _waveLayer.hidden = YES;
    [self.layer addSublayer:_waveLayer];
    [self applyCurrentState];
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (NSView *)hitTest:(NSPoint)point {
  return nil;
}

- (void)setPalette:(TLThemePalette *)palette {
  TLThemePalette *next=palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  if(_palette==next)return;
  _palette=next;
  [self.colorTransition cancelAllTransitions];
  [self applyCurrentState];
}

- (void)setContentBackgroundColor:(NSColor *)color animated:(BOOL)animated {
  NSColor *target=color ?: self.palette.tabBackground;
  BOOL unchanged=[target isEqual:self.contentBackgroundColor ?: self.palette.tabBackground];
  self.contentBackgroundColor=color;
  BOOL animate=animated && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if(unchanged && self.displayedBackgroundColor && (animate || !self.waveActive))return;
  NSTimeInterval duration=self.waveActive ? self.waveDuration*(1-self.waveTimeProgress) : self.palette.browserTabColorTransitionDuration;
  if(duration<=0)animate=NO;
  if(animate && self.waveActive) {
    CGRect rect=CGPathGetBoundingBox(self.backgroundLayer.path);
    CGFloat scale=self.window.backingScaleFactor ?: 1;
    CGImageRef image=TLChromeWaveImage(self.layer,rect,scale);
    if(image) {
      [CATransaction begin];[CATransaction setDisableActions:YES];
      self.frozenBackground.frame=rect;self.frozenBackground.contentsScale=scale;
      self.frozenBackground.contents=(__bridge id)image;
      self.frozenBackground.hidden=NO;self.backgroundLayer.hidden=YES;
      [CATransaction commit];CGImageRelease(image);
      if(self.freezeTextWave)self.freezeTextWave();
    }
    [self.colorTransition cancelAllTransitions];
  }
  if(!animate) {
    [self.colorTransition cancelAllTransitions];
    [self applyCurrentState];
    if(self.backgroundColorChanged)self.backgroundColorChanged(self.displayedBackgroundColor);
    return;
  }
  NSColor *start=self.displayedBackgroundColor ?: self.palette.tabBackground;
  // Keep the original completion time so continuous scrolling cannot keep
  // pushing the end of the reveal further into the future.
  self.waveDuration=duration;self.waveTimeProgress=0;
  self.waveActive=YES;self.waveProgress=0;
  self.waveFeather=self.palette.browserTabColorWaveHeightFraction;
  self.waveContrast=[self.palette tabWaveContrastFromColor:start toColor:target];
  self.waveStartText=[self.palette textColorForContentBackground:start];
  self.waveEndText=[self.palette textColorForContentBackground:target];
  [CATransaction begin];[CATransaction setDisableActions:YES];
  self.backgroundLayer.fillColor=TLCGColor(start);
  self.waveLayer.fillColor=TLCGColor(target);
  self.waveMask.colors=@[(__bridge id)TLCGColor(self.palette.white),(__bridge id)TLCGColor(self.palette.white),(__bridge id)TLCGColor(self.palette.transparentSurface),(__bridge id)TLCGColor(self.palette.transparentSurface)];
  self.waveLayer.hidden=NO;
  [self updateWaveMask];
  [CATransaction commit];
  __weak typeof(self) weakSelf=self;
  [self.colorTransition startTransitionForKey:@"content-color" duration:duration update:^(CGFloat progress){
    TLChromeTabSelectionView *owner=weakSelf;if(!owner)return;
    owner.waveTimeProgress=0.5-sin(asin(1-2*MIN(1,MAX(0,progress)))/3);
    CGFloat contrast=owner.waveContrast;
    // Concentrate more travel around the midpoint without a velocity jump.
    CGFloat incoming=progress*progress,outgoing=(1-progress)*(1-progress);
    CGFloat fasterMiddle=incoming/(incoming+outgoing);
    CGFloat fastestMiddle=(incoming*progress)/(incoming*progress+outgoing*(1-progress));
    owner.waveProgress=fasterMiddle+(fastestMiddle-fasterMiddle)*contrast;
    [owner updateWaveMask];
    // Keep semantic foreground state in sync; the visible label uses the wave mask.
    NSColor *underLabel=progress<0.5 ? start : target;
    if(![owner.displayedBackgroundColor isEqual:underLabel]) {
      owner.displayedBackgroundColor=underLabel;
      owner.displayedTextColor=[owner.palette textColorForContentBackground:underLabel];
      if(owner.backgroundColorChanged)owner.backgroundColorChanged(underLabel);
    }
  } completion:^(BOOL finished){
    TLChromeTabSelectionView *owner=weakSelf;if(!owner || !finished)return;
    owner.waveActive=NO;
    if(owner.textWaveChanged)owner.textWaveChanged(owner.waveStartText,owner.waveEndText,NSZeroRect,@[],NO);
    owner.backgroundLayer.fillColor=TLCGColor(target);
    owner.waveLayer.hidden=YES;
    owner.backgroundLayer.hidden=NO;owner.frozenBackground.hidden=YES;owner.frozenBackground.contents=nil;

  }];
}
- (void)updateWaveMask {
  if(!self.waveActive)return;
  CGRect rect=CGPathGetBoundingBox(self.backgroundLayer.path);
  CGFloat height=CGRectGetHeight(rect);
  if(height<=0)return;
  CGFloat scale=self.window.backingScaleFactor ?: 1;
  CGFloat feather=MAX(self.waveFeather,self.palette.browserTabColorWaveMinimumPixelWidth/(scale*height));
  // The uniform feather travels fully beyond both edges. The oversized
  // mask keeps the already-covered region opaque throughout the sweep.
  CGFloat front=CGRectGetMinY(rect)+height*((1+feather)*self.waveProgress-feather/2);
  [CATransaction begin];[CATransaction setDisableActions:YES];
  self.waveMask.locations=@[@0,@(0.5-feather/8),@(0.5+feather/8),@1];
  self.waveMask.frame=CGRectMake(CGRectGetMinX(rect),front-2*height,CGRectGetWidth(rect),4*height);
  [CATransaction commit];
  if(self.textWaveChanged)self.textWaveChanged(self.waveStartText,self.waveEndText,self.waveMask.frame,self.waveMask.locations,YES);
}
- (void)setLeadingFlareOutset:(CGFloat)leadingFlareOutset {
  _leadingFlareOutset = leadingFlareOutset;
  [self updateBackgroundPath];
}

- (void)applyCurrentState {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.waveActive=NO;self.waveLayer.hidden=YES;
  self.backgroundLayer.hidden=NO;self.frozenBackground.hidden=YES;self.frozenBackground.contents=nil;
  if(self.textWaveChanged)self.textWaveChanged(self.displayedTextColor ?: self.palette.appText,self.displayedTextColor ?: self.palette.appText,NSZeroRect,@[],NO);
  self.displayedBackgroundColor = self.contentBackgroundColor ?: self.palette.tabBackground;
  self.displayedTextColor = [self.palette textColorForContentBackground:self.displayedBackgroundColor];
  self.backgroundLayer.fillColor = TLCGColor(self.displayedBackgroundColor);
  [CATransaction commit];
  [self updateBackgroundPath];
}

- (void)layout {
  [super layout];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.backgroundLayer.frame = self.bounds;
  self.waveLayer.frame = self.bounds;
  [self updateWaveMask];
  [CATransaction commit];
}

- (CGPathRef)newBackgroundPathForSelectionFrame:(NSRect)selectionFrame
                             leadingFlareOutset:(CGFloat)leadingFlareOutset CF_RETURNS_RETAINED {
  NSRect rect = selectionFrame;
  rect.size.height = MAX(self.palette.space0,
                         NSHeight(rect) - self.palette.tabActiveHeightReduction);
  return TLCreateCGPathFromBezierPath(TLChromeTabBackgroundPath(rect, self.palette, leadingFlareOutset));
}

- (void)updateBackgroundPath {
  CGPathRef path = [self newBackgroundPathForSelectionFrame:self.selectionFrame
                                         leadingFlareOutset:self.leadingFlareOutset];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.backgroundLayer.path = path;
  self.waveLayer.path = path;
  [self updateWaveMask];
  [CATransaction commit];
  CGPathRelease(path);
  if (self.geometryChanged) self.geometryChanged();
}

- (CGPathRef)newOutlinePath {
  return [self newBackgroundPathForSelectionFrame:self.selectionFrame leadingFlareOutset:self.leadingFlareOutset];
}

- (void)setHidden:(BOOL)hidden {
  [super setHidden:hidden];
  if (self.geometryChanged) self.geometryChanged();
}

- (void)setSelectionFrame:(NSRect)selectionFrame
        leadingFlareOutset:(CGFloat)leadingFlareOutset
                 animated:(BOOL)animated
                fromFrame:(NSRect)startFrame
                  duration:(NSTimeInterval)duration {
  if (!animated && NSEqualRects(self.selectionFrame, selectionFrame) &&
      [self.backgroundLayer animationForKey:@"tab-selection-slide"] != nil) {
    return;
  }

  CAShapeLayer *visibleLayer = (CAShapeLayer *)(self.backgroundLayer.presentationLayer ?: self.backgroundLayer);
  CGPathRef visiblePath = visibleLayer.path;
  CGPathRef fallbackStartPath = [self newBackgroundPathForSelectionFrame:startFrame
                                                       leadingFlareOutset:self.leadingFlareOutset];
  CGPathRef targetPath = [self newBackgroundPathForSelectionFrame:selectionFrame
                                                leadingFlareOutset:leadingFlareOutset];
  BOOL usesTeleportedStart = !NSEqualRects(startFrame, self.selectionFrame);
  CGPathRef sourcePath = usesTeleportedStart ? fallbackStartPath : (visiblePath ?: fallbackStartPath);
  _selectionFrame = selectionFrame;
  _leadingFlareOutset = leadingFlareOutset;

  [self.backgroundLayer removeAnimationForKey:@"tab-selection-slide"];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.backgroundLayer.path = targetPath;
  self.waveLayer.path = targetPath;
  [self updateWaveMask];
  [CATransaction commit];
  if (self.geometryChanged) self.geometryChanged();
  if (!animated || duration <= 0.0 || CGPathEqualToPath(sourcePath, targetPath)) {
    CGPathRelease(fallbackStartPath);
    CGPathRelease(targetPath);
    return;
  }

  CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"path"];
  slide.fromValue = (__bridge id)sourcePath;
  slide.toValue = (__bridge id)targetPath;
  slide.duration = duration;
  slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [self.backgroundLayer addAnimation:slide forKey:@"tab-selection-slide"];
  CGPathRelease(fallbackStartPath);
  CGPathRelease(targetPath);
}

@end

@interface TLChromeTabTextFieldCell : NSTextFieldCell
@end

@implementation TLChromeTabTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)rect {
  NSRect drawingRect = [super drawingRectForBounds:rect];
  NSSize cellSize = [self cellSizeForBounds:rect];
  CGFloat heightDelta = NSHeight(drawingRect) - ceil(cellSize.height);
  if (heightDelta > 0.0) {
    drawingRect.origin.y += floor(heightDelta * 0.5);
    drawingRect.size.height -= heightDelta;
  }
  return drawingRect;
}

@end

@interface TLChromeTabCloseButton : NSButton
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSColor *normalContentTintColor;
@property (nonatomic, strong) NSColor *hoverContentTintColor;
@end

@interface TLChromeTabCloseButton ()
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic, strong) CALayer *hoverBackgroundLayer;
@property (nonatomic, strong) NSImageView *glyphView;
@property (nonatomic, strong) NSLayoutConstraint *glyphWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *glyphHeightConstraint;
@property (nonatomic, getter=isHovered) BOOL hovered;
@end

@implementation TLChromeTabCloseButton

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _normalContentTintColor = _palette.textMuted;
    _hoverContentTintColor = _palette.appText;
    self.bordered = NO;
    self.imagePosition = NSImageOnly;
    self.imageScaling = NSImageScaleNone;
    self.wantsLayer = YES;
    _hoverBackgroundLayer = [CALayer layer];
    [self.layer addSublayer:_hoverBackgroundLayer];
    _glyphView = [[NSImageView alloc] init];
    _glyphView.translatesAutoresizingMaskIntoConstraints = NO;
    _glyphView.imageAlignment = NSImageAlignCenter;
    _glyphView.imageScaling = NSImageScaleProportionallyDown;
    [self addSubview:_glyphView];
    _glyphWidthConstraint = [_glyphView.widthAnchor constraintEqualToConstant:[self glyphLength]];
    _glyphHeightConstraint = [_glyphView.heightAnchor constraintEqualToConstant:[self glyphLength]];
    [NSLayoutConstraint activateConstraints:@[
      [_glyphView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
      [_glyphView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
      _glyphWidthConstraint,
      _glyphHeightConstraint,
    ]];
    [self applyCurrentState];
  }
  return self;
}

- (NSSize)intrinsicContentSize {
  CGFloat length = [self buttonLength];
  return NSMakeSize(length, length);
}

- (NSEdgeInsets)alignmentRectInsets {
  return NSEdgeInsetsMake(self.palette.space0, self.palette.space0, self.palette.space0, self.palette.space0);
}

- (NSView *)hitTest:(NSPoint)point {
  NSView *hitView = [super hitTest:point];
  return hitView == self.glyphView ? self : hitView;
}

- (void)layout {
  [super layout];
  [self updateHoverBackgroundLayer];
  [self applyCurrentState];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self invalidateIntrinsicContentSize];
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  NSImage *templateImage = image ? [image copy] : nil;
  templateImage.template = YES;
  self.glyphView.image = templateImage;
  [super setImage:nil];
}

- (void)setNormalContentTintColor:(NSColor *)normalContentTintColor {
  _normalContentTintColor = normalContentTintColor ?: self.palette.textMuted;
  [self applyCurrentState];
}

- (void)setHoverContentTintColor:(NSColor *)hoverContentTintColor {
  _hoverContentTintColor = hoverContentTintColor ?: self.palette.appText;
  [self applyCurrentState];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  [self applyCurrentState];
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
  [self applyCurrentState];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!self.window) {
    self.hovered = NO;
  }
  [self applyCurrentState];
}

- (void)applyCurrentState {
  BOOL showHoverBackground = self.enabled && self.hovered;
  NSColor *tintColor = showHoverBackground
    ? (self.hoverContentTintColor ?: self.palette.appText)
    : (self.normalContentTintColor ?: self.palette.textMuted);
  self.contentTintColor = tintColor;
  self.glyphView.contentTintColor = tintColor;
  self.glyphView.alphaValue = showHoverBackground ? 1.0 : self.palette.roleOpacity;
  self.glyphWidthConstraint.constant = [self glyphLength];
  self.glyphHeightConstraint.constant = [self glyphLength];
  self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title attributes:@{
    NSForegroundColorAttributeName: tintColor,
    NSFontAttributeName: self.font ?: self.palette.smallFont,
  }];
  self.layer.backgroundColor = TLCGColor(self.palette.transparentSurface);
  self.layer.masksToBounds = NO;
  self.hoverBackgroundLayer.backgroundColor = showHoverBackground
    ? TLCGColor(self.palette.secondaryActionSurface)
    : TLCGColor(self.palette.transparentSurface);
  [self updateHoverBackgroundLayer];
}

- (void)updateHoverBackgroundLayer {
  if (!self.layer) {
    return;
  }
  if (!self.hoverBackgroundLayer.superlayer) {
    [self.layer insertSublayer:self.hoverBackgroundLayer atIndex:0];
  }

  CGFloat availableWidth = MAX(self.palette.space0, NSWidth(self.bounds));
  CGFloat availableHeight = MAX(self.palette.space0, NSHeight(self.bounds));
  CGFloat length = MIN([self buttonLength], MIN(availableWidth, availableHeight));
  CGFloat originX = floor((availableWidth - length) * 0.5);
  CGFloat originY = floor((availableHeight - length) * 0.5);

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.hoverBackgroundLayer.frame = CGRectMake(originX, originY, length, length);
  self.hoverBackgroundLayer.cornerRadius = length * 0.5;
  self.hoverBackgroundLayer.masksToBounds = YES;
  [CATransaction commit];
}

- (CGFloat)buttonLength {
  return self.palette.space9 + self.palette.space2;
}

- (CGFloat)glyphLength {
  return self.palette.space6;
}

@end

@interface TLChromeTabView ()
@property (nonatomic, strong) NSView *contentContainer;
@property (nonatomic, strong) TLTabIconView *tabIconView;
@property (nonatomic, strong) NSView *titleClipView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *waveTitleLabel;
@property (nonatomic, strong) CAGradientLayer *textWaveMask;
@property (nonatomic, strong) CALayer *frozenText;
@property (nonatomic, strong) NSColor *textWaveStart;
@property (nonatomic) BOOL textWaveActive;
@property (nonatomic, strong) TLChromeTabCloseButton *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *iconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *iconSpacingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleClipHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleClipTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *closeTrailingConstraint;
@property (nonatomic, strong) CALayer *inactiveHoverBackgroundLayer;
@property (nonatomic, strong) CALayer *leadingSeparatorLayer;
@property (nonatomic, strong) CALayer *trailingSeparatorLayer;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;
@property (nonatomic) NSPoint mouseDownWindowPoint;
@property (nonatomic) BOOL didDrag;
@property (nonatomic) BOOL pointerDragCancelled;
@property (nonatomic, readwrite, getter=isHovered) BOOL hovered;
@property (nonatomic, readwrite) CGFloat dragTranslationX;
@property (nonatomic, readwrite) CGFloat reorderTranslationX;
- (void)updateInactiveDecorationGeometry;
- (void)updateInactiveDecorationVisibilityAnimated:(BOOL)animated;
- (void)setOpacity:(CGFloat)opacity forLayer:(CALayer *)layer duration:(NSTimeInterval)duration animated:(BOOL)animated;
@end

@implementation TLChromeTabView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"";
    _icon = @"";
    _systemIconName = @"";
    _closeable = YES;
    _drawsActiveBackground = YES;
    _animatesDecorationChanges = YES;
    _leadingFlareOutset = -1.0;
    self.wantsLayer = YES;
    _inactiveHoverBackgroundLayer = [CALayer layer];
    _leadingSeparatorLayer = [CALayer layer];
    _trailingSeparatorLayer = [CALayer layer];
    _inactiveHoverBackgroundLayer.opacity = 0.0;
    _leadingSeparatorLayer.opacity = 0.0;
    _trailingSeparatorLayer.opacity = 0.0;
    [self.layer addSublayer:_inactiveHoverBackgroundLayer];
    [self.layer addSublayer:_leadingSeparatorLayer];
    [self.layer addSublayer:_trailingSeparatorLayer];
    [self buildSubviews];
    [self applyCurrentState];
    [self updateInactiveDecorationVisibilityAnimated:NO];
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (BOOL)mouseDownCanMoveWindow {
  return NO;
}

- (void)setTag:(NSInteger)tag {
  [super setTag:tag];
  self.closeButton.tag = tag;
}

- (void)freezeCurrentTextWave {
  if(!self.textWaveActive)return;
  CGFloat scale=self.window.backingScaleFactor ?: 1;
  // The enclosing truncation mask remains live; do not bake it in twice.
  CALayer *clipMask=self.titleClipView.layer.mask;
  self.titleClipView.layer.mask=nil;
  CGImageRef image=TLChromeWaveImage(self.titleClipView.layer,self.titleClipView.bounds,scale);
  self.titleClipView.layer.mask=clipMask;
  if(!image)return;
  [CATransaction begin];[CATransaction setDisableActions:YES];
  self.frozenText.frame=self.titleClipView.bounds;self.frozenText.contentsScale=scale;
  self.frozenText.contents=(__bridge id)image;self.frozenText.hidden=NO;
  self.titleLabel.hidden=YES;
  [CATransaction commit];CGImageRelease(image);
}
- (void)showTextWaveFromColor:(NSColor *)start toColor:(NSColor *)end maskFrame:(NSRect)frame locations:(NSArray<NSNumber *> *)locations sourceView:(NSView *)source active:(BOOL)active {
  BOOL showing=active && (![start isEqual:end] || self.frozenText.contents!=nil);
  if(!showing && !self.textWaveActive)return;
  self.textWaveActive=showing;
  self.textWaveStart=start;
  self.waveTitleLabel.hidden=!self.textWaveActive;
  if(!self.textWaveActive){
    self.frozenText.hidden=YES;self.frozenText.contents=nil;self.titleLabel.hidden=NO;
    [self updateContentForeground];return;
  }
  self.titleLabel.textColor=start;self.waveTitleLabel.textColor=end;
  self.waveTitleLabel.stringValue=self.title;self.waveTitleLabel.font=self.palette.labelFont;
  [CATransaction begin];[CATransaction setDisableActions:YES];
  self.textWaveMask.colors=@[(__bridge id)TLCGColor(self.palette.white),(__bridge id)TLCGColor(self.palette.white),(__bridge id)TLCGColor(self.palette.transparentSurface),(__bridge id)TLCGColor(self.palette.transparentSurface)];
  self.textWaveMask.locations=locations;
  self.textWaveMask.startPoint=CGPointMake(.5,self.waveTitleLabel.isFlipped ? 1 : 0);
  self.textWaveMask.endPoint=CGPointMake(.5,self.waveTitleLabel.isFlipped ? 0 : 1);
  self.textWaveMask.frame=[self.waveTitleLabel convertRect:frame fromView:source];
  [CATransaction commit];
}
- (void)setActiveTextColor:(NSColor *)color {
  if ([_activeTextColor isEqual:color] || (!_activeTextColor && !color)) return;
  _activeTextColor = color;
  [self updateContentForeground];
}
- (void)setActiveBackgroundColor:(NSColor *)color {
  if([_activeBackgroundColor isEqual:color] || (!_activeBackgroundColor && !color))return;
  _activeBackgroundColor=color;
  [self updateContentForeground];
}
- (void)updateContentForeground {
  NSColor *color=self.activeBackgroundColor;
  // A color-animation tick must not relayout the tab or reload its favicon.
  BOOL highlighted=self.active || (self.hovered && self.enabled);
  NSColor *foreground=self.active && color ? (self.activeTextColor ?: [self.palette textColorForContentBackground:color]) : (highlighted ? self.palette.appText : self.palette.labelText);
  self.titleLabel.textColor=self.textWaveActive ? self.textWaveStart : foreground;
  self.tabIconView.contentTintColor=foreground;
  self.closeButton.normalContentTintColor=self.active && color ? foreground : self.palette.textMuted;
  self.closeButton.hoverContentTintColor=foreground;
  [self setNeedsDisplay:YES];
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyCurrentState];
  [self updateInactiveDecorationVisibilityAnimated:NO];
}

- (void)updateTitle:(NSString *)title image:(NSImage *)image icon:(NSString *)icon
    systemIconName:(NSString *)systemIconName {
  if ([self.title isEqual:title] && self.image == image &&
      [self.icon isEqual:icon] && [self.systemIconName isEqual:systemIconName]) return;
  _title = [title copy] ?: @"";
  _image = image;
  _icon = [icon copy] ?: @"";
  _systemIconName = [systemIconName copy] ?: @"";
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self applyCurrentState];
  [CATransaction commit];
}

- (void)setTitle:(NSString *)title {
  _title = [title copy] ?: @"";
  [self applyCurrentState];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self applyCurrentState];
}

- (void)setIcon:(NSString *)icon {
  _icon = [icon copy] ?: @"";
  [self applyCurrentState];
}

- (void)setSystemIconName:(NSString *)systemIconName {
  _systemIconName = [systemIconName copy] ?: @"";
  [self applyCurrentState];
}

- (void)setActive:(BOOL)active {
  _active = active;
  self.layer.zPosition = active ? 1.0 : 0.0;
  [self applyCurrentState];
  [self updateInactiveDecorationVisibilityAnimated:self.window != nil && self.animatesDecorationChanges];
}

- (void)setSplitCompanion:(BOOL)splitCompanion {
  _splitCompanion = splitCompanion;
  [self updateInactiveDecorationVisibilityAnimated:self.window != nil];
}
- (void)setCloseable:(BOOL)closeable {
  _closeable = closeable;
  [self applyCurrentState];
}

- (void)setDrawsActiveBackground:(BOOL)drawsActiveBackground {
  _drawsActiveBackground = drawsActiveBackground;
  [self setNeedsDisplay:YES];
}

- (void)setShowsLeadingSeparator:(BOOL)showsLeadingSeparator {
  if (_showsLeadingSeparator == showsLeadingSeparator) {
    return;
  }
  _showsLeadingSeparator = showsLeadingSeparator;
  [self updateInactiveDecorationVisibilityAnimated:self.window != nil && self.animatesDecorationChanges];
}

- (void)setShowsTrailingSeparator:(BOOL)showsTrailingSeparator {
  if (_showsTrailingSeparator == showsTrailingSeparator) {
    return;
  }
  _showsTrailingSeparator = showsTrailingSeparator;
  [self updateInactiveDecorationVisibilityAnimated:self.window != nil && self.animatesDecorationChanges];
}

- (void)setLeadingFlareOutset:(CGFloat)leadingFlareOutset {
  _leadingFlareOutset = leadingFlareOutset;
  [self updateHorizontalContentInset];
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  self.closeButton.enabled = enabled && self.closeable;
  [self applyCurrentState];
  [self updateInactiveDecorationVisibilityAnimated:self.window != nil && self.animatesDecorationChanges];
}

- (void)buildSubviews {
  self.contentContainer = [[NSView alloc] init];
  self.contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentContainer.wantsLayer = YES;
  self.contentContainer.layer.masksToBounds = YES;

  self.tabIconView = [[TLTabIconView alloc] init];
  self.tabIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabIconView.palette = self.palette;

  self.titleClipView = [[NSView alloc] init];
  self.titleClipView.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleClipView.wantsLayer = YES;
  self.titleClipView.layer.masksToBounds = YES;
  [self.titleClipView setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self.titleClipView setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];

  self.titleLabel = [self labelWithString:@""];
  self.titleLabel.lineBreakMode = NSLineBreakByClipping;

  self.closeButton = [[TLChromeTabCloseButton alloc] init];
  self.closeButton.title = @"x";
  self.closeButton.target = self;
  self.closeButton.action = @selector(closeTab:);
  self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.closeButton.toolTip = @"Close tab";
  if (@available(macOS 11.0, *)) {
    self.closeButton.title = @"";
    self.closeButton.image = [self closeButtonImageWithLength:self.palette.space6];
  }

  [self addSubview:self.contentContainer];
  [self.contentContainer addSubview:self.tabIconView];
  [self.contentContainer addSubview:self.titleClipView];
  [self.titleClipView addSubview:self.titleLabel];
  self.waveTitleLabel=[self labelWithString:@""];
  self.waveTitleLabel.wantsLayer=YES;self.waveTitleLabel.hidden=YES;
  self.waveTitleLabel.accessibilityElement=NO;
  self.textWaveMask=[CAGradientLayer layer];self.waveTitleLabel.layer.mask=self.textWaveMask;
  [self.titleClipView addSubview:self.waveTitleLabel];
  self.frozenText=[CALayer layer];self.frozenText.hidden=YES;
  [self.titleClipView.layer insertSublayer:self.frozenText below:self.waveTitleLabel.layer];
  [NSLayoutConstraint activateConstraints:@[
    [self.waveTitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
    [self.waveTitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
    [self.waveTitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.topAnchor],
    [self.waveTitleLabel.bottomAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor]]];
  [self.contentContainer addSubview:self.closeButton];

  self.iconLeadingConstraint = [self.tabIconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor
                                                                               constant:self.palette.tabIconLeadingInset];
  self.iconWidthConstraint = [self.tabIconView.widthAnchor constraintEqualToConstant:self.palette.tabIconSize];
  self.iconHeightConstraint = [self.tabIconView.heightAnchor constraintEqualToConstant:self.palette.tabIconSize];
  self.iconCenterYConstraint = [self.tabIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
                                                                               constant:[self tabIconContainerVerticalOffset]];
  self.iconSpacingConstraint = [self.titleClipView.leadingAnchor constraintEqualToAnchor:self.tabIconView.trailingAnchor
                                                                                 constant:self.palette.tabIconTextSpacing];
  self.titleClipHeightConstraint = [self.titleClipView.heightAnchor constraintEqualToConstant:self.palette.tabHeight];
  self.titleCenterYConstraint = [self.titleClipView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-self.palette.tabContentVerticalOffset];
  self.closeCenterYConstraint = [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-self.palette.tabContentVerticalOffset];
  self.titleClipTrailingConstraint = [self.titleClipView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                                       constant:self.palette.space0];
  // The icon/title/close chain must not impose a minimum tab or window width.
  // Prefer clipping content over breaking the tab controller's assigned width.
  self.titleClipTrailingConstraint.priority = NSLayoutPriorityDragThatCannotResizeWindow - 1;
  self.closeWidthConstraint = [self.closeButton.widthAnchor constraintEqualToConstant:[self closeButtonLength]];
  self.closeHeightConstraint = [self.closeButton.heightAnchor constraintEqualToConstant:[self closeButtonLength]];
  self.closeTrailingConstraint = [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor
                                                                                 constant:self.palette.space0];

  [NSLayoutConstraint activateConstraints:@[
    [self.contentContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.contentContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.contentContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.contentContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

    self.iconLeadingConstraint,
    self.iconWidthConstraint,
    self.iconHeightConstraint,
    self.iconCenterYConstraint,

    self.iconSpacingConstraint,
    self.titleClipTrailingConstraint,
    self.titleCenterYConstraint,
    self.titleClipHeightConstraint,
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.titleClipView.leadingAnchor],
    [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.titleClipView.trailingAnchor],
    [self.titleLabel.topAnchor constraintEqualToAnchor:self.titleClipView.topAnchor],
    [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.titleClipView.bottomAnchor],

    self.closeTrailingConstraint,
    self.closeCenterYConstraint,
    self.closeWidthConstraint,
    self.closeHeightConstraint,
  ]];
}

- (NSTextField *)labelWithString:(NSString *)string {
  NSTextField *label = [[NSTextField alloc] init];
  label.cell = [[TLChromeTabTextFieldCell alloc] initTextCell:string ?: @""];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.bordered = NO;
  label.bezeled = NO;
  label.drawsBackground = NO;
  label.editable = NO;
  label.selectable = NO;
  label.lineBreakMode = NSLineBreakByClipping;
  label.maximumNumberOfLines = 1;
  label.cell.lineBreakMode = NSLineBreakByClipping;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
  [label setContentHuggingPriority:NSLayoutPriorityDefaultLow
                    forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}

- (void)layout {
  [super layout];
  [self updateHorizontalContentInset];
  [self updateTitleFadeMask];
  [self updateInactiveDecorationGeometry];
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)setFrameOrigin:(NSPoint)origin {
  [super setFrameOrigin:origin];
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)setPinned:(BOOL)pinned {
  _pinned = pinned;
  [self applyCurrentState];
}

- (void)applyCurrentState {
  if (!self.tabIconView || !self.titleLabel || !self.closeButton) {
    return;
  }

  BOOL highlighted = self.active || (self.hovered && self.enabled);
  NSColor *foreground = self.active && self.activeBackgroundColor ? (self.activeTextColor ?: [self.palette textColorForContentBackground:self.activeBackgroundColor]) : (highlighted ? self.palette.appText : self.palette.labelText);
  BOOL hasSystemIcon = self.systemIconName.length > 0;
  BOOL hasEmojiIcon = self.icon.length > 0 && !hasSystemIcon;
  self.titleClipView.hidden = self.pinned;
  self.titleLabel.stringValue = self.title;
  self.titleLabel.font = self.palette.labelFont;
  self.titleLabel.textColor = self.textWaveActive ? self.textWaveStart : foreground;
  self.waveTitleLabel.stringValue=self.title;self.waveTitleLabel.font=self.palette.labelFont;
  self.tabIconView.palette = self.palette;
  self.tabIconView.image = self.image;
  self.tabIconView.icon = hasEmojiIcon ? self.icon : @"";
  self.tabIconView.systemIconName = hasSystemIcon ? self.systemIconName : @"";
  self.tabIconView.contentTintColor = foreground;
  [self updateHorizontalContentInset];
  self.iconWidthConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconSize : self.palette.space0;
  self.iconHeightConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconSize : self.palette.space0;
  self.iconCenterYConstraint.constant = [self tabIconContainerVerticalOffset];
  self.titleCenterYConstraint.constant = -self.palette.tabContentVerticalOffset;
  self.closeCenterYConstraint.constant = -self.palette.tabContentVerticalOffset;
  self.iconSpacingConstraint.constant = self.tabIconView.hasIcon ? self.palette.tabIconTextSpacing : self.palette.space0;
  self.titleClipHeightConstraint.constant = self.palette.tabHeight;

  BOOL closeButtonVisible = self.closeable && !self.pinned && self.hovered;
  self.closeButton.hidden = !closeButtonVisible;
  self.closeButton.enabled = self.enabled && closeButtonVisible;
  self.closeButton.alphaValue = closeButtonVisible ? 1.0 : 0.0;
  self.closeButton.palette = self.palette;
  self.closeButton.font = self.palette.smallFont;
  self.closeButton.normalContentTintColor = self.active && self.activeBackgroundColor ? foreground : self.palette.textMuted;
  self.closeButton.hoverContentTintColor = foreground;
  if (@available(macOS 11.0, *)) {
    self.closeButton.image = [self closeButtonImageWithLength:self.palette.space6];
  }
  // Keep text layout stable; the gradient mask makes room for the close button.
  self.titleClipTrailingConstraint.constant = -self.palette.tabIconLeadingInset;
  self.closeWidthConstraint.constant = closeButtonVisible ? [self closeButtonLength] : self.palette.space0;
  self.closeHeightConstraint.constant = closeButtonVisible ? [self closeButtonLength] : self.palette.space0;
  self.closeTrailingConstraint.constant = closeButtonVisible ? -self.palette.space8 : self.palette.space0;

  self.layer.backgroundColor = TLCGColor(self.palette.transparentSurface);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.inactiveHoverBackgroundLayer.backgroundColor = TLCGColor(self.palette.itemHighlightSurface);
  self.leadingSeparatorLayer.backgroundColor = TLCGColor(self.palette.tabBorder);
  self.trailingSeparatorLayer.backgroundColor = TLCGColor(self.palette.tabBorder);
  [CATransaction commit];
  [self updateInactiveDecorationGeometry];
  [self setNeedsLayout:YES];
  [self setNeedsDisplay:YES];
  [self updateTitleFadeMask];
}

- (nullable NSImage *)closeButtonImageWithLength:(CGFloat)length {
  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close tab"];
    image.template = YES;
    NSImage *sizedImage = [image copy];
    sizedImage.size = NSMakeSize(length, length);
    return sizedImage;
  }
  return nil;
}

- (CGFloat)closeButtonLength {
  return self.palette.space9 + self.palette.space2;
}

- (CGFloat)tabIconContainerVerticalOffset {
  // Auto Layout's vertical constants increase downward, unlike our layer coordinates.
  return -self.palette.tabContentVerticalOffset +
    (self.image || self.systemIconName.length > 0 ? self.palette.space0 : self.palette.space2);
}

- (void)updateHorizontalContentInset {
  if (self.pinned) {
    self.iconLeadingConstraint.constant = MAX(self.palette.space0, (NSWidth(self.bounds) - self.palette.tabIconSize) / 2);
    return;
  }
  CGFloat width = NSWidth(self.bounds);
  CGFloat defaultFlareOutset = width > self.palette.space0
    ? MIN(self.palette.tabFlareRadius, width * 0.18)
    : self.palette.tabFlareRadius;
  CGFloat effectiveFlareOutset = self.leadingFlareOutset >= self.palette.space0
    ? MIN(defaultFlareOutset, self.leadingFlareOutset)
    : defaultFlareOutset;
  self.iconLeadingConstraint.constant = self.palette.tabIconLeadingInset -
    (defaultFlareOutset - effectiveFlareOutset);
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.trackingArea) {
    [self removeTrackingArea:self.trackingArea];
  }

  // On unclipped views visibleRect may extend beyond the tab into its parent.
  // Never use that larger region as the tab's hover target.
  self.trackingArea = [[NSTrackingArea alloc] initWithRect:NSIntersectionRect(self.bounds, self.visibleRect)
                                                   options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                     owner:self
                                                  userInfo:nil];
  [self addTrackingArea:self.trackingArea];
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)mouseEntered:(NSEvent *)event {
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)mouseExited:(NSEvent *)event {
  [self updateHoverStateFromCurrentMouseLocation];
}

- (void)updateHoverStateFromCurrentMouseLocation {
  BOOL hovered = NO;
  if (self.enabled && self.window.isVisible && !self.isHiddenOrHasHiddenAncestor) {
    NSPoint point = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    point.x -= self.dragTranslationX + self.reorderTranslationX;
    hovered = NSPointInRect(point, NSIntersectionRect(self.bounds, self.visibleRect));
  }
  if (self.hovered == hovered) return;
  self.hovered = hovered;
  [self applyCurrentState];
  [self updateInactiveDecorationVisibilityAnimated:self.animatesDecorationChanges];
  [self.dragDelegate chromeTabViewHoverStateDidChange:self];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self updateHoverStateFromCurrentMouseLocation];
  [self applyCurrentState];
  [self updateInactiveDecorationVisibilityAnimated:NO];
}

- (void)updateTitleFadeMask {
  if (!self.titleClipView.layer) {
    return;
  }

  CGFloat clipWidth = NSWidth(self.titleClipView.bounds);
  if (self.closeable && self.hovered) {
    clipWidth = MAX(0.0, clipWidth - (self.palette.space8 + [self closeButtonLength] +
      self.palette.space3 - self.palette.tabIconLeadingInset));
  }
  CGFloat labelWidth = self.titleLabel.intrinsicContentSize.width;

  CGFloat preferredFadeWidth = self.closeable && self.hovered
    ? self.palette.space12
    : self.palette.space12 - self.palette.space2;
  CGFloat fadeWidth = MIN(preferredFadeWidth, clipWidth * 0.5);
  CGFloat solidStop = clipWidth > 0 ? MAX(0.0, MIN(1.0, (clipWidth - fadeWidth) / clipWidth)) : 0;
  CAGradientLayer *mask = (CAGradientLayer *)self.titleClipView.layer.mask;
  BOOL hadMask = mask != nil;
  if (!mask) mask = [CAGradientLayer layer];
  CGFloat previousWidth = CGRectGetWidth(mask.bounds);
  CGFloat visibleWidth = CGRectGetWidth((mask.presentationLayer ?: mask).bounds);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  mask.anchorPoint = CGPointZero;
  mask.position = self.titleClipView.bounds.origin;
  mask.bounds = CGRectMake(0, 0, clipWidth, NSHeight(self.titleClipView.bounds));
  mask.startPoint = CGPointMake(0.0, 0.5);
  mask.endPoint = CGPointMake(1.0, 0.5);
  mask.colors = @[
    (__bridge id)TLCGColor(self.palette.appText),
    (__bridge id)TLCGColor(self.palette.appText),
    (__bridge id)TLCGColor(labelWidth > clipWidth ? self.palette.transparentSurface : self.palette.appText),
  ];
  mask.locations = @[@0.0, @(solidStop), @1.0];
  self.titleClipView.layer.mask = mask;
  [CATransaction commit];
  if (hadMask && fabs(previousWidth - clipWidth) > 0.001) {
    if (self.window && self.animatesDecorationChanges &&
        !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
      CABasicAnimation *resize = [CABasicAnimation animationWithKeyPath:@"bounds.size.width"];
      resize.fromValue = @(visibleWidth);
      resize.toValue = @(clipWidth);
      resize.duration = self.palette.tabHoverFadeDuration;
      resize.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      [mask addAnimation:resize forKey:@"tab-content-resize"];
    } else {
      [mask removeAnimationForKey:@"tab-content-resize"];
    }
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  if (!self.active || !self.drawsActiveBackground) {
    return;
  }

  NSBezierPath *path = [self tabPathInRect:[self activeTabRectInRect:self.bounds]];
  [(self.activeBackgroundColor ?: self.palette.tabBackground) setFill];
  [path fill];
}

- (NSRect)activeTabRectInRect:(NSRect)rect {
  rect.size.height = MAX(self.palette.space0,
                         NSHeight(rect) - self.palette.tabActiveHeightReduction);
  return rect;
}

- (BOOL)shouldDrawInactiveHoverPill {
  return self.enabled && self.hovered;
}

- (NSRect)inactiveHoverPillRectInRect:(NSRect)rect {
  CGFloat flareOutset = MIN(self.palette.tabFlareRadius, NSWidth(rect) * 0.18);
  CGFloat leadingOutset = self.leadingFlareOutset >= self.palette.space0
    ? MIN(flareOutset, self.leadingFlareOutset) : flareOutset;
  return NSMakeRect(NSMinX(rect) + leadingOutset,
                    NSMinY(rect) + self.palette.space2 + self.palette.tabContentVerticalOffset,
                    MAX(self.palette.space0, NSWidth(rect) - leadingOutset - flareOutset),
                    MAX(self.palette.space0, NSHeight(rect) - self.palette.space2 * 2.0));
}

- (void)updateInactiveDecorationGeometry {
  NSRect rect = self.bounds;
  NSRect pillRect = [self inactiveHoverPillRectInRect:rect];
  CGFloat width = self.palette.borderWidth;
  CGFloat insetY = self.palette.space5;
  CGFloat height = MAX(0.0, rect.size.height - insetY * 2.0);
  CGFloat leadingCenterX = [self inactiveLeadingSeparatorCenterXInRect:rect];
  CGFloat trailingCenterX = NSMaxX(rect) - (leadingCenterX - NSMinX(rect));
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.inactiveHoverBackgroundLayer.frame = pillRect;
  self.inactiveHoverBackgroundLayer.cornerRadius = MIN(self.palette.tabFlareRadius, NSHeight(pillRect) * 0.5);
  self.inactiveHoverBackgroundLayer.masksToBounds = YES;
  self.leadingSeparatorLayer.frame = NSMakeRect(leadingCenterX - width * 0.5,
                                                NSMinY(rect) + insetY + self.palette.tabContentVerticalOffset,
                                                width,
                                                height);
  self.trailingSeparatorLayer.frame = NSMakeRect(trailingCenterX - width * 0.5,
                                                 NSMinY(rect) + insetY + self.palette.tabContentVerticalOffset,
                                                 width,
                                                 height);
  [CATransaction commit];
}

- (CGFloat)inactiveLeadingSeparatorCenterXInRect:(NSRect)rect {
  CGFloat overlap = TLChromeTabInterTabOverlapForWidth(NSWidth(rect), self.palette);
  return NSMinX(rect) + overlap * 0.5;
}

- (void)updateInactiveDecorationVisibilityAnimated:(BOOL)animated {
  BOOL hoverVisible = !self.active && (self.splitCompanion || [self shouldDrawInactiveHoverPill]);
  BOOL separatorsVisible = !self.active && !hoverVisible;
  [self setOpacity:hoverVisible ? 1.0 : 0.0
           forLayer:self.inactiveHoverBackgroundLayer
           duration:self.palette.tabHoverFadeDuration
           animated:animated];
  [self setOpacity:separatorsVisible && self.showsLeadingSeparator ? 1.0 : 0.0
           forLayer:self.leadingSeparatorLayer
           duration:self.palette.tabSeparatorFadeDuration
           animated:animated];
  [self setOpacity:separatorsVisible && self.showsTrailingSeparator ? 1.0 : 0.0
           forLayer:self.trailingSeparatorLayer
           duration:self.palette.tabSeparatorFadeDuration
           animated:animated];
}

- (void)setOpacity:(CGFloat)opacity
           forLayer:(CALayer *)layer
           duration:(NSTimeInterval)duration
           animated:(BOOL)animated {
  CGFloat modelOpacity = layer.opacity;
  CALayer *visibleLayer = layer.presentationLayer ?: layer;
  CGFloat visibleOpacity = visibleLayer.opacity;
  BOOL shouldAnimate = animated && self.window && duration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (!shouldAnimate) {
    [layer removeAnimationForKey:@"tab-decoration-fade"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.opacity = opacity;
    [CATransaction commit];
    return;
  }
  if (fabs(modelOpacity - opacity) < 0.001) {
    return;
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.opacity = opacity;
  [CATransaction commit];
  CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
  fade.fromValue = @(visibleOpacity);
  fade.toValue = @(opacity);
  fade.duration = duration;
  fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [layer addAnimation:fade forKey:@"tab-decoration-fade"];
}

- (NSBezierPath *)tabPathInRect:(NSRect)rect {
  return TLChromeTabBackgroundPath(rect, self.palette, self.leadingFlareOutset);
}

- (void)mouseDown:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  if ([self.dragDelegate respondsToSelector:@selector(chromeTabViewWillSelect:)]) {
    [self.dragDelegate chromeTabViewWillSelect:self];
  }
  self.mouseDownWindowPoint = event.locationInWindow;
  self.pointerDragCancelled = NO;
  self.didDrag = NO;
  self.dragTranslationX = 0.0;
  self.layer.zPosition = 2.0;
  if (self.action) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
  self.layer.zPosition = 2.0;
}

- (void)mouseDragged:(NSEvent *)event {
  if (!self.enabled || self.pointerDragCancelled) {
    return;
  }

  CGFloat proposedHorizontalTranslation = event.locationInWindow.x - self.mouseDownWindowPoint.x;
  CGFloat deltaX = fabs(proposedHorizontalTranslation);
  CGFloat deltaY = fabs(event.locationInWindow.y - self.mouseDownWindowPoint.y);
  if (deltaX < 4.0 && deltaY < 4.0 && !self.didDrag) {
    return;
  }

  self.didDrag = YES;
  CGFloat horizontalTranslation = [self.dragDelegate chromeTabView:self
                      constrainedHorizontalTranslationForEvent:event
                                           proposedTranslation:proposedHorizontalTranslation];
  self.dragTranslationX = horizontalTranslation;
  [self.dragDelegate chromeTabView:self didDragWithEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
  if (!self.enabled) {
    return;
  }

  if (self.didDrag) {
    [self.dragDelegate chromeTabView:self didDragWithEvent:event];
    if (self.dragDelegate) [self.dragDelegate chromeTabViewDidEndDragging:self];
    else [self finishPointerDrag];
    return;
  }

  self.layer.zPosition = self.active ? 1.0 : 0.0;
}

- (void)finishPointerDrag {
  self.didDrag = NO;
  self.dragTranslationX = 0;
  self.layer.zPosition = self.active ? 1.0 : 0.0;
}

- (void)cancelPointerDrag {
  self.pointerDragCancelled = YES;
  [self finishPointerDrag];
}

- (void)setDragTranslationX:(CGFloat)dragTranslationX {
  _dragTranslationX = dragTranslationX;
  [self updateDragTransform];
}

- (void)updateDragTransform {
  CGFloat translationX = self.dragTranslationX + self.reorderTranslationX;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.layer.transform = CATransform3DMakeTranslation(translationX, 0.0, 0.0);
  [CATransaction commit];
}

- (void)setReorderTranslationX:(CGFloat)translationX animated:(BOOL)animated {
  [self setReorderTranslationX:translationX animated:animated duration:self.palette.tabReorderSlideDuration];
}

- (void)setReorderTranslationX:(CGFloat)translationX
                       animated:(BOOL)animated
                       duration:(NSTimeInterval)duration {
  if (fabs(_reorderTranslationX - translationX) < 0.001) {
    if (!animated) {
      [self.layer removeAnimationForKey:@"tab-reorder-slide"];
    }
    return;
  }

  CALayer *visibleLayer = self.layer.presentationLayer ?: self.layer;
  CATransform3D visibleTransform = visibleLayer.transform;
  _reorderTranslationX = translationX;
  [self updateDragTransform];

  BOOL shouldAnimate = animated && self.window && duration > 0.0 &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (!shouldAnimate) {
    [self.layer removeAnimationForKey:@"tab-reorder-slide"];
    return;
  }

  CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform"];
  slide.fromValue = [NSValue valueWithCATransform3D:visibleTransform];
  slide.toValue = [NSValue valueWithCATransform3D:self.layer.transform];
  slide.duration = duration;
  slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
  [self.layer addAnimation:slide forKey:@"tab-reorder-slide"];
}

- (CGFloat)lifecycleVisibleWidth {
  CAShapeLayer *mask = (CAShapeLayer *)self.contentContainer.layer.mask;
  return mask ? CGRectGetWidth(CGPathGetBoundingBox(mask.path)) : NSWidth(self.bounds);
}

- (CGFloat)lifecycleContentOpacity { return self.titleClipView.layer.opacity; }

- (void)setLifecycleVisibleWidth:(CGFloat)width contentOpacity:(CGFloat)opacity {
  [self layoutSubtreeIfNeeded];
  CAShapeLayer *mask = [self.contentContainer.layer.mask isKindOfClass:CAShapeLayer.class]
    ? (CAShapeLayer *)self.contentContainer.layer.mask : [CAShapeLayer layer];
  NSRect visibleRect = self.contentContainer.bounds;
  visibleRect.size.width = MIN(NSWidth(visibleRect), MAX(0.0, width));
  CGPathRef path = TLCreateTabLifecycleMaskPath(visibleRect);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  mask.frame = self.contentContainer.bounds;
  mask.path = path;
  mask.mask = nil;
  self.contentContainer.layer.mask = mask;
  for (NSView *view in @[self.tabIconView, self.titleClipView, self.closeButton]) {
    view.layer.opacity = MIN(1.0, MAX(0.0, opacity));
  }
  [CATransaction commit];
  CGPathRelease(path);
}

- (void)clipLifecycleContentToSelectionView:(TLChromeTabSelectionView *)selectionView {
  CALayer *lifecycleMask = self.contentContainer.layer.mask;
  if (!lifecycleMask) return;
  NSPoint origin = [selectionView convertPoint:NSZeroPoint toView:self.contentContainer];
  NSPoint x = [selectionView convertPoint:NSMakePoint(1, 0) toView:self.contentContainer];
  NSPoint y = [selectionView convertPoint:NSMakePoint(0, 1) toView:self.contentContainer];
  CGAffineTransform transform = CGAffineTransformMake(x.x - origin.x, x.y - origin.y,
    y.x - origin.x, y.y - origin.y, origin.x, origin.y);
  CGPathRef background = [selectionView newOutlinePath];
  CGPathRef localPath = CGPathCreateCopyByTransformingPath(background, &transform);
  CAShapeLayer *mask = [CAShapeLayer layer];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  mask.frame = self.contentContainer.bounds;
  mask.path = localPath;
  lifecycleMask.mask = mask;
  [CATransaction commit];
  CGPathRelease(localPath);
  CGPathRelease(background);
}

- (void)resetLifecycleAppearance {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.contentContainer.layer.mask = nil;
  for (NSView *view in @[self.tabIconView, self.titleClipView, self.closeButton]) {
    view.layer.opacity = 1.0;
  }
  [CATransaction commit];
}

- (void)prepareForInsertionAnimation {
  [self setLifecycleVisibleWidth:NSWidth(self.bounds) * self.palette.tabLifecycleCollapsedWidthRatio
                 contentOpacity:1.0];
}

- (BOOL)canOpenTabContextMenu {
  if (self.didDrag || (NSEvent.pressedMouseButtons & 1)) return NO;
  if ([self.dragDelegate respondsToSelector:@selector(chromeTabViewShouldOpenContextMenu:)]) {
    return [self.dragDelegate chromeTabViewShouldOpenContextMenu:self];
  }
  return YES;
}

- (void)rightMouseDown:(NSEvent *)event {
  if (![self canOpenTabContextMenu]) return;
  [super rightMouseDown:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
  if (![self canOpenTabContextMenu]) return nil;
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  if ([self.dragDelegate respondsToSelector:@selector(contextMenuForChromeTabView:)]) {
    NSMenu *tabMenu = [self.dragDelegate contextMenuForChromeTabView:self];
    for (NSMenuItem *item in tabMenu.itemArray.copy) {
      [tabMenu removeItem:item]; [menu addItem:item];
    }
    if (menu.numberOfItems) [menu addItem:NSMenuItem.separatorItem];
  }
  menu.autoenablesItems = NO;

  NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close"
                                                     action:@selector(closeTab:)
                                              keyEquivalent:@""];
  closeItem.target = self;
  closeItem.enabled = self.enabled && self.closeable;
  [menu addItem:closeItem];

  NSMenuItem *closeOtherTabsItem = [[NSMenuItem alloc] initWithTitle:@"Close Other Tabs"
                                                              action:@selector(closeOtherTabs:)
                                                       keyEquivalent:@""];
  closeOtherTabsItem.target = self;
  closeOtherTabsItem.enabled = self.enabled && self.canCloseOtherTabs;
  [menu addItem:closeOtherTabsItem];
  return menu;
}

- (void)closeTab:(id)sender {
  if (self.closeAction) {
    self.closeButton.tag = self.tag;
    [NSApp sendAction:self.closeAction to:self.target from:self.closeButton];
  }
}

- (void)closeOtherTabs:(id)sender {
  [self.dragDelegate chromeTabViewDidRequestCloseOtherTabs:self];
}

@end
