#import "TLOnboardingDemoWindowController.h"
#import <QuartzCore/QuartzCore.h>
#import <SceneKit/SceneKit.h>
#import <math.h>
#import <stdint.h>

static const CGFloat TLOnboardingCubeSideLength = 2.35;
static const CGFloat TLOnboardingCubeRimRadius = 0.22;
static const NSInteger TLOnboardingCubeRimSegmentCount = 18;
static const NSInteger TLOnboardingCubeFlatFaceMaterialCount = 6;
static const NSInteger TLOnboardingCubeRimMaterialIndex = 6;
static const NSInteger TLOnboardingCubeMaterialCount = 7;
static const CGFloat TLOnboardingCubePitch = 0.0;
static const CGFloat TLOnboardingSafariFaceRoll = -0.10;
static const CGFloat TLOnboardingAutomatorFaceRoll = 0.07;
static const CGFloat TLOnboardingNotesFaceRoll = -0.04;
static const CGFloat TLOnboardingCameraZPosition = 7.0;
static const CGFloat TLOnboardingFaceTextureSize = 1024.0;
static const CGFloat TLOnboardingRimTextureSize = 512.0;
static const CGFloat TLOnboardingIconInset = 128.0;
static const CGFloat TLOnboardingIconSourceCropInset = 64.0;
static const CGFloat TLOnboardingTalariaIconSourceCropInset = 51.2;
static const CGFloat TLOnboardingIconClipCornerRadiusRatio = 0.22;
static const CGFloat TLOnboardingFaceBorderInset = 3.0;
static const CGFloat TLOnboardingFaceBorderWidth = 5.0;
static const CGFloat TLOnboardingRimTransitionFramesPerSecond = 60.0;
static const NSInteger TLOnboardingIntroSlideCount = 3;
static const CGFloat TLOnboardingIntroCubeScale = 0.82;
static const CGFloat TLOnboardingIntroCubeYOffset = 0.30;
static const CGFloat TLOnboardingIntroFadeOutScale = 0.62;
static const CGFloat TLOnboardingIntroInitialFadeDuration = 0.48;
static const CGFloat TLOnboardingIntroPostStaticImageDelay = 0.5;
static const CGFloat TLOnboardingIntroSwapFadeDuration = 0.28;
static const CGFloat TLOnboardingIntroCaptionTopOffset = 208.0;
static const CGFloat TLOnboardingRotationDuration = 0.64;
static const CGFloat TLOnboardingRotationFullSpinDuration = 1.16;
static const CGFloat TLOnboardingRotationZoomScale = 0.76;
static const CGFloat TLOnboardingRotationSkipZoomScale = 0.62;
static const CGFloat TLOnboardingRotationFullSpinZoomScale = 0.54;
static const CGFloat TLOnboardingRotationZoomOutRatio = 0.42;
static const CGFloat TLOnboardingRotationBounceOvershootRatio = 0.06;
static const CGFloat TLOnboardingRotationSecondBounceRatio = 0.016;
static const CGFloat TLOnboardingRotationBounceSettleRatio = 0.40;
static const CGFloat TLOnboardingRotationSecondBounceDurationRatio = 0.45;
static const CGFloat TLOnboardingAlternativeBrowserCorrectionTiltDegrees = -6.0;
static const CGFloat TLOnboardingOpenAppButtonRevealDelay = 3.0;
static const CGFloat TLOnboardingOpenAppButtonFadeDuration = 0.42;
static const CGFloat TLOnboardingTalariaRevealCubeXPosition = -1.28;
static const CGFloat TLOnboardingTalariaTitleLeadingOffset = 125.0;

typedef struct {
  float x;
  float y;
  float z;
} TLOnboardingGeometryVector3;

typedef struct {
  float u;
  float v;
} TLOnboardingGeometryVector2;

typedef NS_ENUM(NSInteger, TLOnboardingDemoPhase) {
  TLOnboardingDemoPhaseStaticImage,
  TLOnboardingDemoPhaseIntro,
  TLOnboardingDemoPhaseCarousel,
};

typedef NS_ENUM(NSInteger, TLOnboardingCubeFaceIndex) {
  TLOnboardingAgentFaceIndex = 0,
  TLOnboardingBrowserFaceIndex = 1,
  TLOnboardingNotesFaceIndex = 2,
  TLOnboardingHiddenFaceIndex = 3,
  TLOnboardingAlternativeBrowserFaceIndex = TLOnboardingHiddenFaceIndex,
};

static CGFloat TLOnboardingCubeHalfExtent(void) {
  return TLOnboardingCubeSideLength * 0.5;
}

static CGFloat TLOnboardingCubeFlatHalfExtent(void) {
  return TLOnboardingCubeHalfExtent() - TLOnboardingCubeRimRadius;
}

static CGFloat TLOnboardingClampedValue(CGFloat value, CGFloat minimumValue, CGFloat maximumValue) {
  return MIN(MAX(value, minimumValue), maximumValue);
}

static SCNVector3 TLOnboardingRawPositionForFaceIndex(NSInteger faceIndex, CGFloat u, CGFloat v) {
  CGFloat halfExtent = TLOnboardingCubeHalfExtent();
  switch (faceIndex) {
    case 0:
      return SCNVector3Make(u, v, halfExtent);
    case 1:
      return SCNVector3Make(halfExtent, v, -u);
    case 2:
      return SCNVector3Make(-u, v, -halfExtent);
    case 3:
      return SCNVector3Make(-halfExtent, v, u);
    case 4:
      return SCNVector3Make(u, halfExtent, -v);
    default:
      return SCNVector3Make(u, -halfExtent, v);
  }
}

static SCNVector3 TLOnboardingRoundedCubeNormalForRawPosition(SCNVector3 rawPosition) {
  CGFloat flatHalfExtent = TLOnboardingCubeFlatHalfExtent();
  CGFloat clampedX = TLOnboardingClampedValue(rawPosition.x, -flatHalfExtent, flatHalfExtent);
  CGFloat clampedY = TLOnboardingClampedValue(rawPosition.y, -flatHalfExtent, flatHalfExtent);
  CGFloat clampedZ = TLOnboardingClampedValue(rawPosition.z, -flatHalfExtent, flatHalfExtent);
  CGFloat deltaX = rawPosition.x - clampedX;
  CGFloat deltaY = rawPosition.y - clampedY;
  CGFloat deltaZ = rawPosition.z - clampedZ;
  CGFloat length = sqrt((deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ));
  if (length <= 0.0) {
    return SCNVector3Make(0.0, 0.0, 1.0);
  }
  return SCNVector3Make(deltaX / length, deltaY / length, deltaZ / length);
}

static SCNVector3 TLOnboardingRoundedCubePositionForRawPosition(SCNVector3 rawPosition) {
  CGFloat flatHalfExtent = TLOnboardingCubeFlatHalfExtent();
  CGFloat clampedX = TLOnboardingClampedValue(rawPosition.x, -flatHalfExtent, flatHalfExtent);
  CGFloat clampedY = TLOnboardingClampedValue(rawPosition.y, -flatHalfExtent, flatHalfExtent);
  CGFloat clampedZ = TLOnboardingClampedValue(rawPosition.z, -flatHalfExtent, flatHalfExtent);
  CGFloat deltaX = rawPosition.x - clampedX;
  CGFloat deltaY = rawPosition.y - clampedY;
  CGFloat deltaZ = rawPosition.z - clampedZ;
  CGFloat length = sqrt((deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ));
  if (length <= 0.0) {
    return rawPosition;
  }
  CGFloat radiusScale = TLOnboardingCubeRimRadius / length;
  return SCNVector3Make(clampedX + (deltaX * radiusScale),
                        clampedY + (deltaY * radiusScale),
                        clampedZ + (deltaZ * radiusScale));
}

static uint32_t TLOnboardingAppendGeometryVertex(NSMutableData *vertexData,
                                                 NSMutableData *normalData,
                                                 NSMutableData *texcoordData,
                                                 SCNVector3 position,
                                                 SCNVector3 normal,
                                                 CGPoint texcoord) {
  uint32_t vertexIndex = (uint32_t)(vertexData.length / sizeof(TLOnboardingGeometryVector3));
  TLOnboardingGeometryVector3 vertex = {
    (float)position.x,
    (float)position.y,
    (float)position.z,
  };
  TLOnboardingGeometryVector3 normalVector = {
    (float)normal.x,
    (float)normal.y,
    (float)normal.z,
  };
  TLOnboardingGeometryVector2 textureCoordinate = {
    (float)texcoord.x,
    (float)texcoord.y,
  };
  [vertexData appendBytes:&vertex length:sizeof(vertex)];
  [normalData appendBytes:&normalVector length:sizeof(normalVector)];
  [texcoordData appendBytes:&textureCoordinate length:sizeof(textureCoordinate)];
  return vertexIndex;
}

static void TLOnboardingAppendTriangle(NSMutableData *indexData,
                                       uint32_t firstIndex,
                                       uint32_t secondIndex,
                                       uint32_t thirdIndex) {
  uint32_t indices[3] = { firstIndex, secondIndex, thirdIndex };
  [indexData appendBytes:indices length:sizeof(indices)];
}

static CGFloat TLOnboardingRollAngleForFaceIndex(NSInteger faceIndex) {
  switch (faceIndex) {
    case TLOnboardingAgentFaceIndex:
      return TLOnboardingAutomatorFaceRoll;
    case TLOnboardingBrowserFaceIndex:
      return TLOnboardingSafariFaceRoll;
    case TLOnboardingNotesFaceIndex:
      return TLOnboardingNotesFaceRoll;
    default:
      return TLOnboardingAutomatorFaceRoll;
  }
}

static BOOL TLOnboardingFaceUsesFlippedGradient(NSInteger faceIndex) {
  return NO;
}

static CGFloat TLOnboardingEaseInOutProgress(CGFloat progress) {
  CGFloat clampedProgress = TLOnboardingClampedValue(progress, 0.0, 1.0);
  return (clampedProgress * clampedProgress) * (3.0 - (2.0 * clampedProgress));
}

static CGFloat TLOnboardingIntroCubeYPosition(void) {
  return TLOnboardingIntroCubeYOffset;
}

static SCNVector3 TLOnboardingCarouselCubePosition(BOOL showsTalariaReveal) {
  return SCNVector3Make(showsTalariaReveal ? TLOnboardingTalariaRevealCubeXPosition : 0.0, 0.0, 0.0);
}

static CGFloat TLOnboardingFinalRollAngleForFaceIndex(NSInteger faceIndex, BOOL showsTalariaReveal) {
  return showsTalariaReveal && faceIndex == TLOnboardingNotesFaceIndex
      ? 0.0
      : TLOnboardingRollAngleForFaceIndex(faceIndex);
}

@interface TLOnboardingSceneView : SCNView
@end

@interface TLOnboardingDemoView : NSView

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSView *staticIntroImageView;
@property (nonatomic, strong) SCNView *sceneView;
@property (nonatomic, strong) NSTextField *captionLabel;
@property (nonatomic, strong) NSTextField *talariaTitleLabel;
@property (nonatomic, strong) NSTextField *alternativeBrowserCorrectionLabel;
@property (nonatomic, strong) NSView *talariaStrikeLineView;
@property (nonatomic, strong) NSButton *openAppButton;
@property (nonatomic, copy, nullable) void (^openAppHandler)(void);
@property (nonatomic, strong) NSLayoutConstraint *talariaStrikeLineWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *openAppButtonWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *openAppButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *openAppButtonTopConstraint;
@property (nonatomic, strong) SCNNode *cubeRollNode;
@property (nonatomic, strong) SCNNode *cubeNode;
@property (nonatomic, strong) SCNMaterial *rimMaterial;
@property (nonatomic) TLOnboardingDemoPhase demoPhase;
@property (nonatomic) NSInteger introSlideIndex;
@property (nonatomic) NSInteger carouselCompletedRoundCount;
@property (nonatomic) NSInteger visibleFaceIndex;
@property (nonatomic) CGFloat cubePitchAngle;
@property (nonatomic) CGFloat cubeYawAngle;
@property (nonatomic) CGFloat cubeRollAngle;
@property (nonatomic) BOOL showsTalariaReveal;
@property (nonatomic) BOOL showsAlternativeBrowserReveal;
@property (nonatomic) BOOL alternativeBrowserSurfacePrepared;
@property (nonatomic) BOOL initialIntroAnimationStarted;
@property (nonatomic) BOOL rotationAnimationInProgress;
@property (nonatomic) NSInteger openAppButtonRevealGeneration;

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)updatePalette:(TLThemePalette *)palette;
- (void)startInitialIntroAnimationIfNeeded;
- (void)advanceDemo;
- (void)retreatDemo;
- (void)loadStaticIntroImage;
- (void)showStaticIntroImage;
- (void)showIntroSlideAtIndex:(NSInteger)slideIndex;
- (void)transitionFromStaticImageToIntro;
- (void)transitionFromIntroToStaticImage;
- (void)transitionToIntroSlideAtIndex:(NSInteger)slideIndex;
- (void)transitionFromIntroToCarousel;
- (void)transitionFromCarouselToIntro;
- (void)rotateToNextFace;
- (void)rotateToPreviousFace;
- (void)rotateToAlternativeBrowserFace;
- (void)rotateFromAlternativeBrowserFaceToTalaria;
- (CGFloat)yawAngleForFaceIndex:(NSInteger)faceIndex;
- (NSString *)captionTextForIntroSlideAtIndex:(NSInteger)slideIndex;
- (void)refreshCubeMaterials;
- (void)updateTitleMarkupAppearance;
- (void)setAlternativeBrowserTitleMarkupVisible:(BOOL)visible;
- (void)setAlternativeBrowserTitleMarkupVisible:(BOOL)visible animatedWithDuration:(CGFloat)duration;
- (void)setOpenAppButtonVisible:(BOOL)visible;
- (void)setOpenAppButtonVisible:(BOOL)visible animatedWithDuration:(CGFloat)duration;
- (void)scheduleOpenAppButtonRevealAfterDelay:(CGFloat)delay;
- (void)openAppButtonPressed:(id)sender;
- (NSArray<NSNumber *> *)facePathFromFaceIndex:(NSInteger)startingFaceIndex
                                   toFaceIndex:(NSInteger)targetFaceIndex
                               includesFullSpin:(BOOL)includesFullSpin;
- (NSArray<NSNumber *> *)facePathFromFaceIndex:(NSInteger)startingFaceIndex
                                   toFaceIndex:(NSInteger)targetFaceIndex
                               includesFullSpin:(BOOL)includesFullSpin
                                      direction:(NSInteger)direction;
- (SCNAction *)turnActionWithRadians:(CGFloat)turnRadians
               bounceReferenceRadians:(CGFloat)bounceReferenceRadians
                              duration:(CGFloat)duration;
- (SCNAction *)pitchActionWithRadians:(CGFloat)pitchRadians
                bounceReferenceRadians:(CGFloat)bounceReferenceRadians
                              duration:(CGFloat)duration;
- (SCNAction *)zoomActionToScale:(CGFloat)zoomScale
                      finalScale:(CGFloat)finalScale
                        duration:(CGFloat)duration;
- (SCNAction *)rollActionForFacePath:(NSArray<NSNumber *> *)facePath
                   startingRollAngle:(CGFloat)startingRollAngle
                            duration:(CGFloat)duration;
- (SCNAction *)rollActionForFacePath:(NSArray<NSNumber *> *)facePath
                   startingRollAngle:(CGFloat)startingRollAngle
                       finalRollAngle:(CGFloat)finalRollAngle
                            duration:(CGFloat)duration;
- (SCNGeometry *)roundedCubeGeometry;
- (NSArray<NSNumber *> *)roundedCubeCoordinateValues;
- (void)addRoundedCubeFaceWithIndex:(NSInteger)faceIndex
                    coordinateValues:(NSArray<NSNumber *> *)coordinateValues
                          vertexData:(NSMutableData *)vertexData
                          normalData:(NSMutableData *)normalData
                        texcoordData:(NSMutableData *)texcoordData
                 indexDataByMaterial:(NSArray<NSMutableData *> *)indexDataByMaterial;
- (void)addRoundedCubeQuadWithFaceIndex:(NSInteger)faceIndex
                                     u0:(CGFloat)u0
                                     v0:(CGFloat)v0
                                     u1:(CGFloat)u1
                                     v1:(CGFloat)v1
                          materialIndex:(NSInteger)materialIndex
                             vertexData:(NSMutableData *)vertexData
                             normalData:(NSMutableData *)normalData
                           texcoordData:(NSMutableData *)texcoordData
                    indexDataByMaterial:(NSArray<NSMutableData *> *)indexDataByMaterial;
- (NSColor *)surfaceColorForFaceIndex:(NSInteger)faceIndex;
- (SCNMaterial *)rimMaterialForFaceIndex:(NSInteger)faceIndex;
- (void)updateRimMaterialForFaceIndex:(NSInteger)faceIndex;
- (SCNAction *)rimMaterialActionFromFaceIndex:(NSInteger)startingFaceIndex
                                  toFaceIndex:(NSInteger)targetFaceIndex
                          includesSkippedFace:(BOOL)includesSkippedFace
                                     duration:(CGFloat)duration;
- (SCNAction *)rimMaterialActionForFacePath:(NSArray<NSNumber *> *)facePath
                                   duration:(CGFloat)duration;
- (SCNAction *)rimMaterialTransitionActionFromColor:(NSColor *)startingColor
                                            toColor:(NSColor *)targetColor
                                           duration:(CGFloat)duration;
- (SCNAction *)rimMaterialTransitionActionFromFaceIndex:(NSInteger)startingFaceIndex
                                            toFaceIndex:(NSInteger)targetFaceIndex
                                               duration:(CGFloat)duration;
- (NSArray<NSImage *> *)rimTransitionTexturesFromColor:(NSColor *)startingColor
                                               toColor:(NSColor *)targetColor
                                              duration:(CGFloat)duration;
- (NSArray<NSImage *> *)rimTransitionTexturesFromFaceIndex:(NSInteger)startingFaceIndex
                                               toFaceIndex:(NSInteger)targetFaceIndex
                                                  duration:(CGFloat)duration;
- (SCNAction *)rimMaterialAnimationActionWithTextures:(NSArray<NSImage *> *)textures
                                             duration:(CGFloat)duration;
- (NSImage *)rimTextureForFaceIndex:(NSInteger)faceIndex;
- (NSImage *)rimTextureWithSurfaceColor:(NSColor *)surfaceColor;
- (NSImage *)rimTextureWithSurfaceColor:(NSColor *)surfaceColor
                      flipsFaceGradient:(BOOL)flipsFaceGradient;
- (NSImage *)rimTextureByBlendingTexture:(NSImage *)startingTexture
                             withTexture:(NSImage *)targetTexture
                                progress:(CGFloat)progress;
- (SCNAction *)rollActionFromAngle:(CGFloat)startingRollAngle
                            toAngle:(CGFloat)targetRollAngle
                includesSkippedFace:(BOOL)includesSkippedFace
                           duration:(CGFloat)duration;
- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient;
- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient
                         iconInset:(CGFloat)iconInset
               iconSourceCropInset:(CGFloat)iconSourceCropInset
                        clipsIcon:(BOOL)clipsIcon
               flipsIconVertically:(BOOL)flipsIconVertically
                       drawsBorder:(BOOL)drawsBorder;
- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient
                       drawsBorder:(BOOL)drawsBorder;
- (NSImage *)faceTextureWithIcon:(nullable NSImage *)icon
                 backgroundColor:(NSColor *)backgroundColor
               showsFaceGradient:(BOOL)showsFaceGradient
                      drawsBorder:(BOOL)drawsBorder;
- (NSImage *)faceTextureWithIcon:(nullable NSImage *)icon
                 backgroundColor:(NSColor *)backgroundColor
               showsFaceGradient:(BOOL)showsFaceGradient
               flipsFaceGradient:(BOOL)flipsFaceGradient
                      drawsBorder:(BOOL)drawsBorder;
- (NSImage *)textureWithIcon:(nullable NSImage *)icon
             backgroundColor:(NSColor *)backgroundColor
           showsFaceGradient:(BOOL)showsFaceGradient
           flipsFaceGradient:(BOOL)flipsFaceGradient
                        size:(CGFloat)textureDimension
                   iconInset:(CGFloat)iconInset
         iconSourceCropInset:(CGFloat)iconSourceCropInset
                  clipsIcon:(BOOL)clipsIcon
         flipsIconVertically:(BOOL)flipsIconVertically
                 drawsBorder:(BOOL)drawsBorder;
- (void)drawFaceGradientInRect:(NSRect)textureRect
                  surfaceColor:(NSColor *)surfaceColor
             flipsFaceGradient:(BOOL)flipsFaceGradient;
- (nullable NSImage *)appIconWithBundleIdentifier:(NSString *)bundleIdentifier
                                    fallbackPaths:(NSArray<NSString *> *)fallbackPaths;
- (nullable NSImage *)talariaAppIcon;

@end

@interface TLOnboardingDemoWindowController ()

@property (nonatomic, strong) TLOnboardingDemoView *demoView;

@end

@implementation TLOnboardingSceneView

- (BOOL)acceptsFirstResponder {
  return NO;
}

- (void)mouseDown:(NSEvent *)event {
  [self.window performWindowDragWithEvent:event];
}

@end

@implementation TLOnboardingDemoWindowController

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  TLThemePalette *resolvedPalette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSScreen *screen = NSScreen.mainScreen;
  NSRect frame = NSMakeRect(0.0,
                            0.0,
                            resolvedPalette.windowInitialWidth,
                            resolvedPalette.windowInitialHeight);
  if (screen) {
    NSRect visibleFrame = screen.visibleFrame;
    frame.origin.x = NSMidX(visibleFrame) - (NSWidth(frame) * 0.5);
    frame.origin.y = NSMidY(visibleFrame) - (NSHeight(frame) * 0.5);
  }
  NSWindowStyleMask styleMask = NSWindowStyleMaskTitled |
    NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable |
    NSWindowStyleMaskResizable |
    NSWindowStyleMaskFullSizeContentView;
  NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:styleMask
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
  window.title = @"Onboarding";
  window.titleVisibility = NSWindowTitleHidden;
  window.titlebarAppearsTransparent = YES;
  window.movableByWindowBackground = YES;
  window.releasedWhenClosed = NO;
  window.opaque = YES;
  window.backgroundColor = resolvedPalette.onboardingDemoBackgroundTop;
  window.hasShadow = YES;
  window.level = NSNormalWindowLevel;
  window.collectionBehavior = NSWindowCollectionBehaviorManaged;

  self = [super initWithWindow:window];
  if (self) {
    _demoView = [[TLOnboardingDemoView alloc] initWithPalette:resolvedPalette];
    __weak typeof(self) weakSelf = self;
    _demoView.openAppHandler = ^{
      TLOnboardingDemoWindowController *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      if (strongSelf.openAppHandler) {
        strongSelf.openAppHandler();
      } else {
        [strongSelf.window close];
        [NSApp activateIgnoringOtherApps:YES];
      }
    };
    window.contentView = _demoView;
  }
  return self;
}

- (void)showFromWindow:(nullable NSWindow *)parentWindow {
  if (parentWindow) {
    [self.window setFrame:parentWindow.frame display:YES];
  }
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp unhide:nil];
  [self.window deminiaturize:nil];
  [self.window makeKeyAndOrderFront:nil];
  if (parentWindow.windowNumber > 0) {
    [self.window orderWindow:NSWindowAbove relativeTo:parentWindow.windowNumber];
  }
  [self.window orderFrontRegardless];
  [self.window makeFirstResponder:self.demoView];
  [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)updatePalette:(TLThemePalette *)palette {
  TLThemePalette *resolvedPalette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  self.window.backgroundColor = resolvedPalette.onboardingDemoBackgroundTop;
  [self.demoView updatePalette:resolvedPalette];
}

@end

@implementation TLOnboardingDemoView

- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super initWithFrame:NSZeroRect];
  if (self) {
    _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _demoPhase = TLOnboardingDemoPhaseStaticImage;
    _introSlideIndex = 0;
    _visibleFaceIndex = TLOnboardingAgentFaceIndex;
    _cubePitchAngle = 0.0;
    _cubeYawAngle = [self yawAngleForFaceIndex:_visibleFaceIndex];
    _cubeRollAngle = 0.0;
    self.translatesAutoresizingMaskIntoConstraints = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;

    _gradientLayer = [CAGradientLayer layer];
    [self.layer addSublayer:_gradientLayer];
    [self buildScene];
    [self applyPalette];
  }
  return self;
}

- (BOOL)acceptsFirstResponder {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window) {
    [self.window makeFirstResponder:self];
    [self startInitialIntroAnimationIfNeeded];
  }
}

- (void)layout {
  [super layout];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.gradientLayer.frame = self.bounds;
  [CATransaction commit];
}

- (void)keyDown:(NSEvent *)event {
  NSString *characters = event.charactersIgnoringModifiers ?: @"";
  if (characters.length == 0) {
    [super keyDown:event];
    return;
  }

  unichar key = [characters characterAtIndex:0];
  if (key == NSRightArrowFunctionKey) {
    [self advanceDemo];
    return;
  }
  if (key == NSLeftArrowFunctionKey) {
    [self retreatDemo];
    return;
  }
  if (key == 27) {
    [self.window close];
    return;
  }

  [super keyDown:event];
}

- (void)updatePalette:(TLThemePalette *)palette {
  self.palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  [self applyPalette];
  self.captionLabel.textColor = self.palette.onboardingDemoCaptionText;
  self.captionLabel.font = self.palette.onboardingDemoCaptionFont;
  self.talariaTitleLabel.textColor = self.palette.onboardingDemoCaptionText;
  self.talariaTitleLabel.font = self.palette.onboardingDemoCaptionFont;
  [self updateTitleMarkupAppearance];
  [self refreshCubeMaterials];
}

- (void)buildScene {
  self.staticIntroImageView = [[NSView alloc] initWithFrame:NSZeroRect];
  self.staticIntroImageView.translatesAutoresizingMaskIntoConstraints = NO;
  self.staticIntroImageView.wantsLayer = YES;
  self.staticIntroImageView.alphaValue = 1.0;
  [self addSubview:self.staticIntroImageView];
  [self loadStaticIntroImage];

  self.sceneView = [[TLOnboardingSceneView alloc] init];
  self.sceneView.translatesAutoresizingMaskIntoConstraints = NO;
  self.sceneView.allowsCameraControl = NO;
  self.sceneView.autoenablesDefaultLighting = NO;
  self.sceneView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
  self.sceneView.alphaValue = 0.0;
  [self addSubview:self.sceneView];

  self.captionLabel = [NSTextField labelWithString:[self captionTextForIntroSlideAtIndex:self.introSlideIndex]];
  self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.captionLabel.alignment = NSTextAlignmentCenter;
  self.captionLabel.font = self.palette.onboardingDemoCaptionFont;
  self.captionLabel.textColor = self.palette.onboardingDemoCaptionText;
  self.captionLabel.alphaValue = 0.0;
  [self addSubview:self.captionLabel];

  self.talariaTitleLabel = [NSTextField labelWithString:@"Talaria Browser"];
  self.talariaTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.talariaTitleLabel.alignment = NSTextAlignmentLeft;
  self.talariaTitleLabel.font = self.palette.onboardingDemoCaptionFont;
  self.talariaTitleLabel.textColor = self.palette.onboardingDemoCaptionText;
  self.talariaTitleLabel.alphaValue = 0.0;
  [self addSubview:self.talariaTitleLabel];

  self.alternativeBrowserCorrectionLabel = [NSTextField labelWithString:@"Browser?"];
  self.alternativeBrowserCorrectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.alternativeBrowserCorrectionLabel.alignment = NSTextAlignmentLeft;
  self.alternativeBrowserCorrectionLabel.font = self.palette.onboardingDemoAlternativeBrowserCorrectionFont;
  self.alternativeBrowserCorrectionLabel.textColor = self.palette.onboardingDemoAlternativeBrowserCorrectionText;
  self.alternativeBrowserCorrectionLabel.frameCenterRotation = TLOnboardingAlternativeBrowserCorrectionTiltDegrees;
  self.alternativeBrowserCorrectionLabel.alphaValue = 0.0;
  [self addSubview:self.alternativeBrowserCorrectionLabel];

  self.talariaStrikeLineView = [[NSView alloc] initWithFrame:NSZeroRect];
  self.talariaStrikeLineView.translatesAutoresizingMaskIntoConstraints = NO;
  self.talariaStrikeLineView.wantsLayer = YES;
  self.talariaStrikeLineView.alphaValue = 0.0;
  [self addSubview:self.talariaStrikeLineView];
  self.talariaStrikeLineWidthConstraint =
      [self.talariaStrikeLineView.widthAnchor constraintEqualToConstant:0.0];

  self.openAppButton = [NSButton buttonWithTitle:@"Open App"
                                          target:self
                                          action:@selector(openAppButtonPressed:)];
  self.openAppButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.openAppButton.bordered = NO;
  self.openAppButton.focusRingType = NSFocusRingTypeNone;
  self.openAppButton.alphaValue = 0.0;
  self.openAppButton.enabled = NO;
  self.openAppButton.wantsLayer = YES;
  self.openAppButton.layer.masksToBounds = YES;
  [self addSubview:self.openAppButton];
  self.openAppButtonWidthConstraint = [self.openAppButton.widthAnchor constraintEqualToConstant:0.0];
  self.openAppButtonHeightConstraint = [self.openAppButton.heightAnchor constraintEqualToConstant:0.0];
  self.openAppButtonTopConstraint =
      [self.openAppButton.topAnchor constraintEqualToAnchor:self.talariaTitleLabel.bottomAnchor constant:0.0];

  [NSLayoutConstraint activateConstraints:@[
    [self.staticIntroImageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.staticIntroImageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.staticIntroImageView.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.staticIntroImageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [self.sceneView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.sceneView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.sceneView.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.sceneView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [self.captionLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [self.captionLabel.topAnchor constraintEqualToAnchor:self.centerYAnchor constant:TLOnboardingIntroCaptionTopOffset],
    [self.captionLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:32.0],
    [self.captionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-32.0],
    [self.talariaTitleLabel.leadingAnchor constraintEqualToAnchor:self.centerXAnchor
                                                           constant:TLOnboardingTalariaTitleLeadingOffset],
    [self.talariaTitleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    [self.talariaTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-64.0],
    [self.alternativeBrowserCorrectionLabel.leadingAnchor constraintEqualToAnchor:self.talariaTitleLabel.leadingAnchor
                                                            constant:8.0],
    [self.alternativeBrowserCorrectionLabel.bottomAnchor constraintEqualToAnchor:self.talariaTitleLabel.topAnchor
                                                           constant:-4.0],
    [self.alternativeBrowserCorrectionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-64.0],
    [self.talariaStrikeLineView.leadingAnchor constraintEqualToAnchor:self.talariaTitleLabel.leadingAnchor],
    [self.talariaStrikeLineView.centerYAnchor constraintEqualToAnchor:self.talariaTitleLabel.centerYAnchor
                                                               constant:4.0],
    [self.talariaStrikeLineView.heightAnchor constraintEqualToConstant:5.0],
    self.talariaStrikeLineWidthConstraint,
    [self.openAppButton.leadingAnchor constraintEqualToAnchor:self.talariaTitleLabel.leadingAnchor],
    self.openAppButtonTopConstraint,
    self.openAppButtonWidthConstraint,
    self.openAppButtonHeightConstraint,
  ]];
  [self updateTitleMarkupAppearance];

  SCNScene *scene = [SCNScene scene];
  self.sceneView.scene = scene;

  SCNNode *cameraNode = [SCNNode node];
  cameraNode.camera = [SCNCamera camera];
  cameraNode.camera.fieldOfView = 36.0;
  cameraNode.position = SCNVector3Make(0.0, 0.0, TLOnboardingCameraZPosition);
  self.sceneView.pointOfView = cameraNode;
  [scene.rootNode addChildNode:cameraNode];

  self.cubeRollNode = [SCNNode node];
    self.cubeRollNode.eulerAngles = SCNVector3Make(self.cubePitchAngle, 0.0, self.cubeRollAngle);
  [scene.rootNode addChildNode:self.cubeRollNode];

  SCNGeometry *cubeGeometry = [self roundedCubeGeometry];
  cubeGeometry.materials = [self cubeMaterials];
  self.cubeNode = [SCNNode nodeWithGeometry:cubeGeometry];
  self.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, self.cubeYawAngle, 0.0);
  self.cubeNode.scale = SCNVector3Make(TLOnboardingIntroCubeScale,
                                       TLOnboardingIntroCubeScale,
                                       TLOnboardingIntroCubeScale);
  self.cubeNode.opacity = 1.0;
  [self.cubeRollNode addChildNode:self.cubeNode];
  [self showIntroSlideAtIndex:self.introSlideIndex];
  [self showStaticIntroImage];
}

- (void)startInitialIntroAnimationIfNeeded {
  if (self.initialIntroAnimationStarted) {
    return;
  }
  self.initialIntroAnimationStarted = YES;
  [self showStaticIntroImage];
}

- (void)advanceDemo {
  if (self.rotationAnimationInProgress) {
    return;
  }

  if (self.demoPhase == TLOnboardingDemoPhaseStaticImage) {
    [self transitionFromStaticImageToIntro];
    return;
  }

  if (self.demoPhase == TLOnboardingDemoPhaseIntro) {
    if (self.introSlideIndex < TLOnboardingIntroSlideCount - 1) {
      [self transitionToIntroSlideAtIndex:self.introSlideIndex + 1];
      return;
    }
    [self transitionFromIntroToCarousel];
    return;
  }

  [self rotateToNextFace];
}

- (void)retreatDemo {
  if (self.rotationAnimationInProgress) {
    return;
  }

  if (self.demoPhase == TLOnboardingDemoPhaseStaticImage) {
    return;
  }

  if (self.demoPhase == TLOnboardingDemoPhaseIntro) {
    if (self.introSlideIndex > 0) {
      [self transitionToIntroSlideAtIndex:self.introSlideIndex - 1];
    } else {
      [self transitionFromIntroToStaticImage];
    }
    return;
  }

  if (self.visibleFaceIndex == TLOnboardingAgentFaceIndex && self.carouselCompletedRoundCount == 0) {
    [self transitionFromCarouselToIntro];
    return;
  }

  [self rotateToPreviousFace];
}

- (void)loadStaticIntroImage {
  self.staticIntroImageView.layer.contents = nil;
}

- (void)showStaticIntroImage {
  self.demoPhase = TLOnboardingDemoPhaseStaticImage;
  [self showIntroSlideAtIndex:0];
  self.staticIntroImageView.hidden = NO;
  self.staticIntroImageView.alphaValue = 1.0;
  self.sceneView.alphaValue = 0.0;
  self.captionLabel.alphaValue = 0.0;
  self.talariaTitleLabel.alphaValue = 0.0;
  [self setAlternativeBrowserTitleMarkupVisible:NO];
  self.cubeNode.scale = SCNVector3Make(TLOnboardingIntroCubeScale,
                                       TLOnboardingIntroCubeScale,
                                       TLOnboardingIntroCubeScale);
}

- (void)showIntroSlideAtIndex:(NSInteger)slideIndex {
  NSInteger boundedSlideIndex = MIN(MAX(slideIndex, 0), TLOnboardingIntroSlideCount - 1);
    self.showsTalariaReveal = NO;
    self.showsAlternativeBrowserReveal = NO;
    self.introSlideIndex = boundedSlideIndex;
    self.visibleFaceIndex = boundedSlideIndex;
    self.cubePitchAngle = 0.0;
    self.cubeYawAngle = [self yawAngleForFaceIndex:boundedSlideIndex];
    self.cubeRollAngle = 0.0;
    self.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, self.cubeYawAngle, 0.0);
    self.cubeRollNode.eulerAngles = SCNVector3Make(self.cubePitchAngle, 0.0, self.cubeRollAngle);
  self.cubeRollNode.position = SCNVector3Make(0.0, TLOnboardingIntroCubeYPosition(), 0.0);
  [self updateRimMaterialForFaceIndex:self.visibleFaceIndex];
    self.captionLabel.stringValue = [self captionTextForIntroSlideAtIndex:boundedSlideIndex];
    self.talariaTitleLabel.alphaValue = 0.0;
  [self setAlternativeBrowserTitleMarkupVisible:NO];
  [self refreshCubeMaterials];
}

- (void)transitionFromStaticImageToIntro {
  self.rotationAnimationInProgress = YES;
  self.demoPhase = TLOnboardingDemoPhaseIntro;
  [self showIntroSlideAtIndex:0];
  self.staticIntroImageView.hidden = NO;
  self.staticIntroImageView.alphaValue = 1.0;
  self.sceneView.alphaValue = 0.0;
  self.captionLabel.alphaValue = 0.0;
  self.talariaTitleLabel.alphaValue = 0.0;
  [self setAlternativeBrowserTitleMarkupVisible:NO];
  self.cubeNode.opacity = 1.0;
  self.cubeNode.scale = SCNVector3Make(TLOnboardingIntroFadeOutScale,
                                       TLOnboardingIntroFadeOutScale,
                                       TLOnboardingIntroFadeOutScale);

  __weak typeof(self) weakSelf = self;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = TLOnboardingIntroInitialFadeDuration;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.staticIntroImageView.animator.alphaValue = 0.0;
  } completionHandler:^{
    TLOnboardingDemoView *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    strongSelf.staticIntroImageView.hidden = YES;
    strongSelf.staticIntroImageView.alphaValue = 0.0;
    strongSelf.sceneView.alphaValue = 0.0;
    strongSelf.captionLabel.alphaValue = 0.0;

    dispatch_time_t revealTime =
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TLOnboardingIntroPostStaticImageDelay * NSEC_PER_SEC));
    dispatch_after(revealTime, dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *delayedSelf = weakSelf;
      if (!delayedSelf) {
        return;
      }

      SCNAction *zoomInAction = [SCNAction scaleTo:TLOnboardingIntroCubeScale
                                           duration:TLOnboardingIntroInitialFadeDuration];
      zoomInAction.timingMode = SCNActionTimingModeEaseInEaseOut;
      [delayedSelf.cubeNode runAction:zoomInAction];

      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = TLOnboardingIntroInitialFadeDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        delayedSelf.sceneView.animator.alphaValue = 1.0;
        delayedSelf.captionLabel.animator.alphaValue = 1.0;
      } completionHandler:^{
        TLOnboardingDemoView *completedSelf = weakSelf;
        if (!completedSelf) {
          return;
        }
        completedSelf.rotationAnimationInProgress = NO;
      }];
    });
  }];
}

- (void)transitionFromIntroToStaticImage {
  self.rotationAnimationInProgress = YES;
  self.staticIntroImageView.hidden = NO;
  self.staticIntroImageView.alphaValue = 0.0;
  [self setAlternativeBrowserTitleMarkupVisible:NO];

  __weak typeof(self) weakSelf = self;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = TLOnboardingIntroInitialFadeDuration;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.staticIntroImageView.animator.alphaValue = 1.0;
    self.sceneView.animator.alphaValue = 0.0;
    self.captionLabel.animator.alphaValue = 0.0;
    self.talariaTitleLabel.animator.alphaValue = 0.0;
  } completionHandler:^{
    TLOnboardingDemoView *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf.demoPhase = TLOnboardingDemoPhaseStaticImage;
    strongSelf.sceneView.alphaValue = 0.0;
    strongSelf.captionLabel.alphaValue = 0.0;
    strongSelf.talariaTitleLabel.alphaValue = 0.0;
    [strongSelf setAlternativeBrowserTitleMarkupVisible:NO];
    strongSelf.rotationAnimationInProgress = NO;
  }];
}

- (void)transitionToIntroSlideAtIndex:(NSInteger)slideIndex {
  self.rotationAnimationInProgress = YES;

  self.cubeNode.opacity = 1.0;
  SCNAction *zoomOutAction = [SCNAction scaleTo:TLOnboardingIntroFadeOutScale
                                       duration:TLOnboardingIntroSwapFadeDuration];
  zoomOutAction.timingMode = SCNActionTimingModeEaseInEaseOut;

  __weak typeof(self) weakSelf = self;
  [self.cubeNode runAction:zoomOutAction];

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = TLOnboardingIntroSwapFadeDuration;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.sceneView.animator.alphaValue = 0.0;
    self.captionLabel.animator.alphaValue = 0.0;
  } completionHandler:^{
    TLOnboardingDemoView *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }

    strongSelf.sceneView.alphaValue = 0.0;
    strongSelf.captionLabel.alphaValue = 0.0;
    [strongSelf showIntroSlideAtIndex:slideIndex];
    strongSelf.cubeNode.opacity = 1.0;
    strongSelf.sceneView.alphaValue = 0.0;
    strongSelf.cubeNode.scale = SCNVector3Make(TLOnboardingIntroFadeOutScale,
                                               TLOnboardingIntroFadeOutScale,
                                               TLOnboardingIntroFadeOutScale);
    strongSelf.captionLabel.alphaValue = 0.0;

    SCNAction *zoomInAction = [SCNAction scaleTo:TLOnboardingIntroCubeScale
                                        duration:TLOnboardingIntroSwapFadeDuration];
    zoomInAction.timingMode = SCNActionTimingModeEaseInEaseOut;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
      context.duration = TLOnboardingIntroSwapFadeDuration;
      context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      strongSelf.sceneView.animator.alphaValue = 1.0;
      strongSelf.captionLabel.animator.alphaValue = 1.0;
    } completionHandler:nil];

    [strongSelf.cubeNode runAction:zoomInAction completionHandler:^{
      dispatch_async(dispatch_get_main_queue(), ^{
        TLOnboardingDemoView *completedSelf = weakSelf;
        if (!completedSelf) {
          return;
        }
        completedSelf.rotationAnimationInProgress = NO;
      });
    }];
  }];
}

- (void)transitionFromIntroToCarousel {
  self.rotationAnimationInProgress = YES;

  NSInteger currentFaceIndex = self.visibleFaceIndex;
  NSInteger targetFaceIndex = TLOnboardingAgentFaceIndex;
  NSArray<NSNumber *> *facePath = [self facePathFromFaceIndex:currentFaceIndex
                                                  toFaceIndex:targetFaceIndex
                                              includesFullSpin:NO];
  NSInteger quarterTurnCount = (NSInteger)facePath.count - 1;
  CGFloat turnRadians = -(CGFloat)M_PI_2 * (CGFloat)quarterTurnCount;
  CGFloat bounceReferenceRadians = -(CGFloat)M_PI;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = TLOnboardingRollAngleForFaceIndex(targetFaceIndex);
  CGFloat bounceDuration = TLOnboardingRotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = TLOnboardingRotationDuration - bounceDuration;

    self.demoPhase = TLOnboardingDemoPhaseCarousel;
    self.showsTalariaReveal = NO;
    self.showsAlternativeBrowserReveal = NO;
    self.visibleFaceIndex = targetFaceIndex;
    self.cubePitchAngle = 0.0;
    self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  self.carouselCompletedRoundCount = 0;

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = mainTurnDuration * 0.65;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.captionLabel.animator.alphaValue = 0.0;
  } completionHandler:nil];

  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:bounceReferenceRadians
                                             duration:TLOnboardingRotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:TLOnboardingRotationSkipZoomScale
                                       finalScale:1.0
                                         duration:mainTurnDuration];
  SCNAction *rollAction = [self rollActionForFacePath:facePath
                                    startingRollAngle:startingRollAngle
                                             duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialActionForFacePath:facePath
                                                           duration:mainTurnDuration];
  SCNAction *positionAction = [SCNAction moveTo:SCNVector3Make(0.0, 0.0, 0.0)
                                      duration:mainTurnDuration];
  positionAction.timingMode = SCNActionTimingModeEaseInEaseOut;

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction, positionAction]]];
  [self.cubeNode runAction:[SCNAction group:@[turnAction, zoomAction]] completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, strongSelf.cubeYawAngle, 0.0);
        strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(strongSelf.cubePitchAngle, 0.0, strongSelf.cubeRollAngle);
      strongSelf.cubeRollNode.position = SCNVector3Make(0.0, 0.0, 0.0);
      [strongSelf updateRimMaterialForFaceIndex:strongSelf.visibleFaceIndex];
      strongSelf.cubeNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
      strongSelf.cubeNode.opacity = 1.0;
        strongSelf.captionLabel.alphaValue = 0.0;
        strongSelf.talariaTitleLabel.alphaValue = 0.0;
      [strongSelf setAlternativeBrowserTitleMarkupVisible:NO];
        strongSelf.rotationAnimationInProgress = NO;
    });
  }];
}

- (void)transitionFromCarouselToIntro {
  self.rotationAnimationInProgress = YES;

  NSInteger currentFaceIndex = self.visibleFaceIndex;
  NSInteger targetFaceIndex = TLOnboardingIntroSlideCount - 1;
  NSArray<NSNumber *> *facePath = [self facePathFromFaceIndex:currentFaceIndex
                                                  toFaceIndex:targetFaceIndex
                                              includesFullSpin:NO
                                                     direction:-1];
  NSInteger quarterTurnCount = (NSInteger)facePath.count - 1;
  CGFloat turnRadians = (CGFloat)M_PI_2 * (CGFloat)quarterTurnCount;
  CGFloat bounceReferenceRadians = (CGFloat)M_PI;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = 0.0;
  CGFloat bounceDuration = TLOnboardingRotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = TLOnboardingRotationDuration - bounceDuration;

    self.demoPhase = TLOnboardingDemoPhaseIntro;
    self.showsTalariaReveal = NO;
    self.showsAlternativeBrowserReveal = NO;
    self.introSlideIndex = targetFaceIndex;
    self.visibleFaceIndex = targetFaceIndex;
    self.cubePitchAngle = 0.0;
    self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  self.carouselCompletedRoundCount = 0;
  self.captionLabel.stringValue = [self captionTextForIntroSlideAtIndex:targetFaceIndex];
    self.captionLabel.alphaValue = 0.0;
    self.talariaTitleLabel.alphaValue = 0.0;
  [self setAlternativeBrowserTitleMarkupVisible:NO];

  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:bounceReferenceRadians
                                             duration:TLOnboardingRotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:TLOnboardingRotationSkipZoomScale
                                       finalScale:TLOnboardingIntroCubeScale
                                         duration:mainTurnDuration];
  SCNAction *rollAction = [self rollActionForFacePath:facePath
                                    startingRollAngle:startingRollAngle
                                       finalRollAngle:targetRollAngle
                                             duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialActionForFacePath:facePath
                                                           duration:mainTurnDuration];
  SCNAction *positionAction = [SCNAction moveTo:SCNVector3Make(0.0, TLOnboardingIntroCubeYPosition(), 0.0)
                                      duration:mainTurnDuration];
  positionAction.timingMode = SCNActionTimingModeEaseInEaseOut;

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction, positionAction]]];
  [self.cubeNode runAction:[SCNAction group:@[turnAction, zoomAction]] completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.cubeYawAngle = [strongSelf yawAngleForFaceIndex:targetFaceIndex];
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, strongSelf.cubeYawAngle, 0.0);
        strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(strongSelf.cubePitchAngle, 0.0, strongSelf.cubeRollAngle);
      strongSelf.cubeRollNode.position = SCNVector3Make(0.0, TLOnboardingIntroCubeYPosition(), 0.0);
      [strongSelf updateRimMaterialForFaceIndex:strongSelf.visibleFaceIndex];
      strongSelf.cubeNode.scale = SCNVector3Make(TLOnboardingIntroCubeScale,
                                                 TLOnboardingIntroCubeScale,
                                                 TLOnboardingIntroCubeScale);
      strongSelf.cubeNode.opacity = 1.0;

      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = TLOnboardingIntroSwapFadeDuration;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        strongSelf.captionLabel.animator.alphaValue = 1.0;
      } completionHandler:^{
        strongSelf.rotationAnimationInProgress = NO;
      }];
    });
  }];
}

- (CGFloat)yawAngleForFaceIndex:(NSInteger)faceIndex {
  return -(CGFloat)M_PI_2 * (CGFloat)faceIndex;
}

- (NSString *)captionTextForIntroSlideAtIndex:(NSInteger)slideIndex {
    switch (slideIndex) {
      case TLOnboardingAgentFaceIndex:
        return @"Multitasking agents";
    case TLOnboardingBrowserFaceIndex:
      return @"Revolutionary AI Browser";
    default:
      return @"Breakthrough Notes App";
    }
  }

- (void)updateTitleMarkupAppearance {
  self.alternativeBrowserCorrectionLabel.font = self.palette.onboardingDemoAlternativeBrowserCorrectionFont;
  self.alternativeBrowserCorrectionLabel.textColor = self.palette.onboardingDemoAlternativeBrowserCorrectionText;
  self.alternativeBrowserCorrectionLabel.frameCenterRotation = TLOnboardingAlternativeBrowserCorrectionTiltDegrees;
  self.talariaStrikeLineView.layer.backgroundColor = TLCGColor(self.palette.onboardingDemoTitleStrike);
  self.openAppButton.layer.backgroundColor = TLCGColor(self.palette.onboardingDemoOpenAppButtonSurface);
  self.openAppButton.contentTintColor = self.palette.onboardingDemoOpenAppButtonText;
  self.openAppButton.font = self.palette.onboardingDemoOpenAppButtonFont;
  self.openAppButtonHeightConstraint.constant = self.palette.onboardingDemoOpenAppButtonHeight;
  self.openAppButtonTopConstraint.constant = self.palette.onboardingDemoOpenAppButtonTopOffset;
  self.openAppButton.layer.cornerRadius =
      MIN(self.palette.onboardingDemoOpenAppButtonHeight * 0.5, self.palette.radiusPill);

  NSFont *titleFont = self.talariaTitleLabel.font ?: self.palette.onboardingDemoCaptionFont;
  NSDictionary<NSAttributedStringKey, id> *attributes = @{ NSFontAttributeName: titleFont };
  self.talariaStrikeLineWidthConstraint.constant = ceil([@"Talaria" sizeWithAttributes:attributes].width);

  NSDictionary<NSAttributedStringKey, id> *buttonAttributes = @{
    NSFontAttributeName: self.palette.onboardingDemoOpenAppButtonFont,
    NSForegroundColorAttributeName: self.palette.onboardingDemoOpenAppButtonText,
  };
  self.openAppButton.attributedTitle =
      [[NSAttributedString alloc] initWithString:@"Open App" attributes:buttonAttributes];
  self.openAppButtonWidthConstraint.constant =
      ceil([@"Open App" sizeWithAttributes:buttonAttributes].width +
           (self.palette.onboardingDemoOpenAppButtonHorizontalPadding * 2.0));
}

- (void)setAlternativeBrowserTitleMarkupVisible:(BOOL)visible {
  self.alternativeBrowserCorrectionLabel.alphaValue = visible ? 1.0 : 0.0;
  self.talariaStrikeLineView.alphaValue = visible ? 1.0 : 0.0;
  if (!visible) {
    self.openAppButtonRevealGeneration += 1;
    [self setOpenAppButtonVisible:NO];
  }
}

- (void)setAlternativeBrowserTitleMarkupVisible:(BOOL)visible animatedWithDuration:(CGFloat)duration {
  if (!visible) {
    self.openAppButtonRevealGeneration += 1;
    self.openAppButton.enabled = NO;
  }

  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = duration;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.alternativeBrowserCorrectionLabel.animator.alphaValue = visible ? 1.0 : 0.0;
    self.talariaStrikeLineView.animator.alphaValue = visible ? 1.0 : 0.0;
    if (!visible) {
      self.openAppButton.animator.alphaValue = 0.0;
    }
  } completionHandler:nil];
}

- (void)setOpenAppButtonVisible:(BOOL)visible {
  self.openAppButton.alphaValue = visible ? 1.0 : 0.0;
  self.openAppButton.enabled = visible;
}

- (void)setOpenAppButtonVisible:(BOOL)visible animatedWithDuration:(CGFloat)duration {
  self.openAppButton.enabled = visible;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
    context.duration = duration;
    context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    self.openAppButton.animator.alphaValue = visible ? 1.0 : 0.0;
  } completionHandler:^{
    if (!visible) {
      self.openAppButton.enabled = NO;
    }
  }];
}

- (void)scheduleOpenAppButtonRevealAfterDelay:(CGFloat)delay {
  self.openAppButtonRevealGeneration += 1;
  NSInteger revealGeneration = self.openAppButtonRevealGeneration;
  [self setOpenAppButtonVisible:NO];

  __weak typeof(self) weakSelf = self;
  dispatch_time_t revealTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
  dispatch_after(revealTime, dispatch_get_main_queue(), ^{
    TLOnboardingDemoView *strongSelf = weakSelf;
    if (!strongSelf ||
        strongSelf.openAppButtonRevealGeneration != revealGeneration ||
        !strongSelf.showsAlternativeBrowserReveal) {
      return;
    }

    [strongSelf setOpenAppButtonVisible:YES animatedWithDuration:TLOnboardingOpenAppButtonFadeDuration];
  });
}

- (void)openAppButtonPressed:(id)sender {
  if (self.openAppHandler) {
    self.openAppHandler();
    return;
  }

  [self.window close];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)refreshCubeMaterials {
  if (!self.showsTalariaReveal) {
    self.alternativeBrowserSurfacePrepared = NO;
  }
  if (self.cubeNode.geometry) {
    self.cubeNode.geometry.materials = [self cubeMaterials];
  }
}

- (NSArray<NSNumber *> *)facePathFromFaceIndex:(NSInteger)startingFaceIndex
                                   toFaceIndex:(NSInteger)targetFaceIndex
                               includesFullSpin:(BOOL)includesFullSpin {
  return [self facePathFromFaceIndex:startingFaceIndex
                         toFaceIndex:targetFaceIndex
                     includesFullSpin:includesFullSpin
                            direction:1];
}

- (NSArray<NSNumber *> *)facePathFromFaceIndex:(NSInteger)startingFaceIndex
                                   toFaceIndex:(NSInteger)targetFaceIndex
                               includesFullSpin:(BOOL)includesFullSpin
                                      direction:(NSInteger)direction {
  NSInteger normalizedStart = ((startingFaceIndex % 4) + 4) % 4;
  NSInteger normalizedTarget = ((targetFaceIndex % 4) + 4) % 4;
  NSInteger normalizedDirection = direction < 0 ? -1 : 1;
  NSInteger quarterTurnCount = normalizedDirection > 0
      ? (normalizedTarget - normalizedStart + 4) % 4
      : (normalizedStart - normalizedTarget + 4) % 4;
  if (includesFullSpin) {
    quarterTurnCount += 4;
  }

  NSMutableArray<NSNumber *> *path = [NSMutableArray arrayWithCapacity:(NSUInteger)quarterTurnCount + 1];
  NSInteger faceIndex = normalizedStart;
  [path addObject:@(faceIndex)];
  for (NSInteger index = 0; index < quarterTurnCount; index++) {
    faceIndex = (faceIndex + normalizedDirection + 4) % 4;
    [path addObject:@(faceIndex)];
  }
  return path;
}

- (SCNAction *)turnActionWithRadians:(CGFloat)turnRadians
               bounceReferenceRadians:(CGFloat)bounceReferenceRadians
                              duration:(CGFloat)duration {
  CGFloat firstBounceRadians = bounceReferenceRadians * TLOnboardingRotationBounceOvershootRatio;
  CGFloat secondBounceRadians = -bounceReferenceRadians * TLOnboardingRotationSecondBounceRatio;
  CGFloat bounceDuration = duration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = duration - bounceDuration;
  CGFloat secondBounceDuration = bounceDuration * TLOnboardingRotationSecondBounceDurationRatio;
  CGFloat finalSettleDuration = bounceDuration - secondBounceDuration;

  SCNAction *turnOvershootAction = [SCNAction rotateByX:0.0
                                                     y:turnRadians + firstBounceRadians
                                                     z:0.0
                                              duration:mainTurnDuration];
  turnOvershootAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *turnSecondBounceAction = [SCNAction rotateByX:0.0
                                                        y:-firstBounceRadians + secondBounceRadians
                                                        z:0.0
                                                 duration:secondBounceDuration];
  turnSecondBounceAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *turnFinalSettleAction = [SCNAction rotateByX:0.0
                                                       y:-secondBounceRadians
                                                       z:0.0
                                                duration:finalSettleDuration];
  turnFinalSettleAction.timingMode = SCNActionTimingModeEaseOut;
  return [SCNAction sequence:@[
    turnOvershootAction,
    turnSecondBounceAction,
    turnFinalSettleAction,
    ]];
  }

- (SCNAction *)pitchActionWithRadians:(CGFloat)pitchRadians
                bounceReferenceRadians:(CGFloat)bounceReferenceRadians
                              duration:(CGFloat)duration {
  CGFloat firstBounceRadians = bounceReferenceRadians * TLOnboardingRotationBounceOvershootRatio;
  CGFloat secondBounceRadians = -bounceReferenceRadians * TLOnboardingRotationSecondBounceRatio;
  CGFloat bounceDuration = duration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = duration - bounceDuration;
  CGFloat secondBounceDuration = bounceDuration * TLOnboardingRotationSecondBounceDurationRatio;
  CGFloat finalSettleDuration = bounceDuration - secondBounceDuration;

  SCNAction *pitchOvershootAction = [SCNAction rotateByX:pitchRadians + firstBounceRadians
                                                       y:0.0
                                                       z:0.0
                                                duration:mainTurnDuration];
  pitchOvershootAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *pitchSecondBounceAction = [SCNAction rotateByX:-firstBounceRadians + secondBounceRadians
                                                          y:0.0
                                                          z:0.0
                                                   duration:secondBounceDuration];
  pitchSecondBounceAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *pitchFinalSettleAction = [SCNAction rotateByX:-secondBounceRadians
                                                         y:0.0
                                                         z:0.0
                                                  duration:finalSettleDuration];
  pitchFinalSettleAction.timingMode = SCNActionTimingModeEaseOut;
  return [SCNAction sequence:@[
    pitchOvershootAction,
    pitchSecondBounceAction,
    pitchFinalSettleAction,
  ]];
}

- (SCNAction *)zoomActionToScale:(CGFloat)zoomScale
                      finalScale:(CGFloat)finalScale
                        duration:(CGFloat)duration {
  SCNAction *zoomOutAction = [SCNAction scaleTo:zoomScale
                                       duration:duration * TLOnboardingRotationZoomOutRatio];
  zoomOutAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *zoomInAction = [SCNAction scaleTo:finalScale
                                      duration:duration * (1.0 - TLOnboardingRotationZoomOutRatio)];
  zoomInAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  return [SCNAction sequence:@[zoomOutAction, zoomInAction]];
}

- (SCNAction *)rollActionForFacePath:(NSArray<NSNumber *> *)facePath
                   startingRollAngle:(CGFloat)startingRollAngle
                            duration:(CGFloat)duration {
  CGFloat finalRollAngle = TLOnboardingRollAngleForFaceIndex(facePath.lastObject.integerValue);
  return [self rollActionForFacePath:facePath
                   startingRollAngle:startingRollAngle
                       finalRollAngle:finalRollAngle
                            duration:duration];
}

- (SCNAction *)rollActionForFacePath:(NSArray<NSNumber *> *)facePath
                   startingRollAngle:(CGFloat)startingRollAngle
                       finalRollAngle:(CGFloat)finalRollAngle
                            duration:(CGFloat)duration {
  if (facePath.count <= 1) {
    return [SCNAction waitForDuration:duration];
  }

  CGFloat segmentDuration = duration / (CGFloat)(facePath.count - 1);
  CGFloat currentRollAngle = startingRollAngle;
  NSMutableArray<SCNAction *> *actions = [NSMutableArray arrayWithCapacity:facePath.count - 1];
  for (NSUInteger index = 1; index < facePath.count; index++) {
    CGFloat targetRollAngle = index == facePath.count - 1
        ? finalRollAngle
        : TLOnboardingRollAngleForFaceIndex(facePath[index].integerValue);
    SCNAction *rollAction = [SCNAction rotateByX:0.0
                                               y:0.0
                                               z:targetRollAngle - currentRollAngle
                                        duration:segmentDuration];
    rollAction.timingMode = SCNActionTimingModeEaseInEaseOut;
    [actions addObject:rollAction];
    currentRollAngle = targetRollAngle;
  }
  return [SCNAction sequence:actions];
}

- (SCNGeometry *)roundedCubeGeometry {
  NSMutableData *vertexData = [NSMutableData data];
  NSMutableData *normalData = [NSMutableData data];
  NSMutableData *texcoordData = [NSMutableData data];
  NSMutableArray<NSMutableData *> *indexDataByMaterial = [NSMutableArray arrayWithCapacity:TLOnboardingCubeMaterialCount];
  for (NSInteger materialIndex = 0; materialIndex < TLOnboardingCubeMaterialCount; materialIndex++) {
    [indexDataByMaterial addObject:[NSMutableData data]];
  }

  NSArray<NSNumber *> *coordinateValues = [self roundedCubeCoordinateValues];
  for (NSInteger faceIndex = 0; faceIndex < TLOnboardingCubeFlatFaceMaterialCount; faceIndex++) {
    [self addRoundedCubeFaceWithIndex:faceIndex
                      coordinateValues:coordinateValues
                            vertexData:vertexData
                          normalData:normalData
                        texcoordData:texcoordData
                   indexDataByMaterial:indexDataByMaterial];
  }

  NSInteger vertexCount = (NSInteger)(vertexData.length / sizeof(TLOnboardingGeometryVector3));
  SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithData:vertexData
                                                                     semantic:SCNGeometrySourceSemanticVertex
                                                                  vectorCount:vertexCount
                                                              floatComponents:YES
                                                          componentsPerVector:3
                                                            bytesPerComponent:sizeof(float)
                                                                   dataOffset:0
                                                                   dataStride:sizeof(TLOnboardingGeometryVector3)];
  SCNGeometrySource *normalSource = [SCNGeometrySource geometrySourceWithData:normalData
                                                                     semantic:SCNGeometrySourceSemanticNormal
                                                                  vectorCount:vertexCount
                                                              floatComponents:YES
                                                          componentsPerVector:3
                                                            bytesPerComponent:sizeof(float)
                                                                   dataOffset:0
                                                                   dataStride:sizeof(TLOnboardingGeometryVector3)];
  SCNGeometrySource *texcoordSource = [SCNGeometrySource geometrySourceWithData:texcoordData
                                                                       semantic:SCNGeometrySourceSemanticTexcoord
                                                                    vectorCount:vertexCount
                                                                floatComponents:YES
                                                            componentsPerVector:2
                                                              bytesPerComponent:sizeof(float)
                                                                     dataOffset:0
                                                                     dataStride:sizeof(TLOnboardingGeometryVector2)];

  NSMutableArray<SCNGeometryElement *> *elements = [NSMutableArray arrayWithCapacity:TLOnboardingCubeMaterialCount];
  for (NSInteger materialIndex = 0; materialIndex < TLOnboardingCubeMaterialCount; materialIndex++) {
    NSMutableData *indexData = indexDataByMaterial[(NSUInteger)materialIndex];
    NSInteger primitiveCount = (NSInteger)(indexData.length / (sizeof(uint32_t) * 3));
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                                primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                               primitiveCount:primitiveCount
                                                                bytesPerIndex:sizeof(uint32_t)];
    [elements addObject:element];
  }

  return [SCNGeometry geometryWithSources:@[vertexSource, normalSource, texcoordSource]
                                 elements:elements];
}

- (NSArray<NSNumber *> *)roundedCubeCoordinateValues {
  CGFloat halfExtent = TLOnboardingCubeHalfExtent();
  CGFloat flatHalfExtent = TLOnboardingCubeFlatHalfExtent();
  NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:(TLOnboardingCubeRimSegmentCount * 2) + 2];
  for (NSInteger index = 0; index <= TLOnboardingCubeRimSegmentCount; index++) {
    CGFloat progress = (CGFloat)index / (CGFloat)TLOnboardingCubeRimSegmentCount;
    [values addObject:@(-halfExtent + ((halfExtent - flatHalfExtent) * progress))];
  }
  [values addObject:@(flatHalfExtent)];
  for (NSInteger index = 1; index <= TLOnboardingCubeRimSegmentCount; index++) {
    CGFloat progress = (CGFloat)index / (CGFloat)TLOnboardingCubeRimSegmentCount;
    [values addObject:@(flatHalfExtent + ((halfExtent - flatHalfExtent) * progress))];
  }
  return values;
}

- (void)addRoundedCubeFaceWithIndex:(NSInteger)faceIndex
                    coordinateValues:(NSArray<NSNumber *> *)coordinateValues
                          vertexData:(NSMutableData *)vertexData
                          normalData:(NSMutableData *)normalData
                        texcoordData:(NSMutableData *)texcoordData
                 indexDataByMaterial:(NSArray<NSMutableData *> *)indexDataByMaterial {
  NSInteger centralCellIndex = TLOnboardingCubeRimSegmentCount;
  NSInteger lastCoordinateIndex = (NSInteger)coordinateValues.count - 1;
  for (NSInteger uIndex = 0; uIndex < lastCoordinateIndex; uIndex++) {
    for (NSInteger vIndex = 0; vIndex < lastCoordinateIndex; vIndex++) {
      CGFloat u0 = coordinateValues[(NSUInteger)uIndex].doubleValue;
      CGFloat v0 = coordinateValues[(NSUInteger)vIndex].doubleValue;
      CGFloat u1 = coordinateValues[(NSUInteger)(uIndex + 1)].doubleValue;
      CGFloat v1 = coordinateValues[(NSUInteger)(vIndex + 1)].doubleValue;
      NSInteger materialIndex = (uIndex == centralCellIndex && vIndex == centralCellIndex)
          ? faceIndex
          : TLOnboardingCubeRimMaterialIndex;
      [self addRoundedCubeQuadWithFaceIndex:faceIndex
                                         u0:u0
                                         v0:v0
                                         u1:u1
                                         v1:v1
                              materialIndex:materialIndex
                                 vertexData:vertexData
                                 normalData:normalData
                               texcoordData:texcoordData
                        indexDataByMaterial:indexDataByMaterial];
    }
  }
}

- (void)addRoundedCubeQuadWithFaceIndex:(NSInteger)faceIndex
                                     u0:(CGFloat)u0
                                     v0:(CGFloat)v0
                                     u1:(CGFloat)u1
                                     v1:(CGFloat)v1
                          materialIndex:(NSInteger)materialIndex
                             vertexData:(NSMutableData *)vertexData
                             normalData:(NSMutableData *)normalData
                           texcoordData:(NSMutableData *)texcoordData
                    indexDataByMaterial:(NSArray<NSMutableData *> *)indexDataByMaterial {
  CGFloat uvHalfExtent = TLOnboardingCubeFlatHalfExtent();
  CGFloat uTexture0 = (u0 + uvHalfExtent) / (uvHalfExtent * 2.0);
  CGFloat uTexture1 = (u1 + uvHalfExtent) / (uvHalfExtent * 2.0);
  CGFloat vTexture0 = (v0 + uvHalfExtent) / (uvHalfExtent * 2.0);
  CGFloat vTexture1 = (v1 + uvHalfExtent) / (uvHalfExtent * 2.0);
  if (faceIndex == 4 || faceIndex == 5) {
    CGFloat originalVTexture0 = vTexture0;
    vTexture0 = 1.0 - vTexture1;
    vTexture1 = 1.0 - originalVTexture0;
  }
  SCNVector3 rawPosition0 = TLOnboardingRawPositionForFaceIndex(faceIndex, u0, v0);
  SCNVector3 rawPosition1 = TLOnboardingRawPositionForFaceIndex(faceIndex, u1, v0);
  SCNVector3 rawPosition2 = TLOnboardingRawPositionForFaceIndex(faceIndex, u1, v1);
  SCNVector3 rawPosition3 = TLOnboardingRawPositionForFaceIndex(faceIndex, u0, v1);
  CGPoint texcoord0 = CGPointMake(uTexture0, vTexture0);
  CGPoint texcoord1 = CGPointMake(uTexture1, vTexture0);
  CGPoint texcoord2 = CGPointMake(uTexture1, vTexture1);
  CGPoint texcoord3 = CGPointMake(uTexture0, vTexture1);
  if (materialIndex == TLOnboardingCubeRimMaterialIndex) {
    texcoord0 = CGPointMake(uTexture0, (rawPosition0.y + uvHalfExtent) / (uvHalfExtent * 2.0));
    texcoord1 = CGPointMake(uTexture1, (rawPosition1.y + uvHalfExtent) / (uvHalfExtent * 2.0));
    texcoord2 = CGPointMake(uTexture1, (rawPosition2.y + uvHalfExtent) / (uvHalfExtent * 2.0));
    texcoord3 = CGPointMake(uTexture0, (rawPosition3.y + uvHalfExtent) / (uvHalfExtent * 2.0));
  }

  uint32_t index0 = TLOnboardingAppendGeometryVertex(vertexData,
                                                    normalData,
                                                    texcoordData,
                                                    TLOnboardingRoundedCubePositionForRawPosition(rawPosition0),
                                                    TLOnboardingRoundedCubeNormalForRawPosition(rawPosition0),
                                                    texcoord0);
  uint32_t index1 = TLOnboardingAppendGeometryVertex(vertexData,
                                                    normalData,
                                                    texcoordData,
                                                    TLOnboardingRoundedCubePositionForRawPosition(rawPosition1),
                                                    TLOnboardingRoundedCubeNormalForRawPosition(rawPosition1),
                                                    texcoord1);
  uint32_t index2 = TLOnboardingAppendGeometryVertex(vertexData,
                                                    normalData,
                                                    texcoordData,
                                                    TLOnboardingRoundedCubePositionForRawPosition(rawPosition2),
                                                    TLOnboardingRoundedCubeNormalForRawPosition(rawPosition2),
                                                    texcoord2);
  uint32_t index3 = TLOnboardingAppendGeometryVertex(vertexData,
                                                    normalData,
                                                    texcoordData,
                                                    TLOnboardingRoundedCubePositionForRawPosition(rawPosition3),
                                                    TLOnboardingRoundedCubeNormalForRawPosition(rawPosition3),
                                                    texcoord3);

  NSMutableData *indexData = indexDataByMaterial[(NSUInteger)materialIndex];
  TLOnboardingAppendTriangle(indexData, index0, index1, index2);
  TLOnboardingAppendTriangle(indexData, index0, index2, index3);
}

- (void)applyPalette {
  self.gradientLayer.colors = @[
    (__bridge id)TLCGColor(self.palette.onboardingDemoBackgroundTop),
    (__bridge id)TLCGColor(self.palette.onboardingDemoBackgroundBottom),
  ];
  self.gradientLayer.locations = @[@0.0, @1.0];
  self.gradientLayer.startPoint = CGPointMake(0.5, 1.0);
  self.gradientLayer.endPoint = CGPointMake(0.5, 0.0);
  self.sceneView.backgroundColor = self.palette.transparentSurface;
}

- (void)rotateToNextFace {
    if (self.rotationAnimationInProgress) {
      return;
    }

  if (self.showsAlternativeBrowserReveal) {
    return;
  }
  if (self.showsTalariaReveal && self.visibleFaceIndex == TLOnboardingNotesFaceIndex) {
    [self rotateToAlternativeBrowserFace];
    return;
  }

    self.rotationAnimationInProgress = YES;
    NSInteger currentFaceIndex = self.visibleFaceIndex;
  BOOL wasShowingTalariaReveal = self.showsTalariaReveal;
  BOOL wrapsToFirstFace = currentFaceIndex == TLOnboardingNotesFaceIndex;
  NSInteger nextFaceIndex = wrapsToFirstFace ? TLOnboardingAgentFaceIndex : currentFaceIndex + 1;
  BOOL usesFullSpin = self.carouselCompletedRoundCount > 0;
  BOOL revealsTalaria = usesFullSpin &&
      currentFaceIndex == TLOnboardingBrowserFaceIndex &&
      nextFaceIndex == TLOnboardingNotesFaceIndex;
  BOOL leavesTalariaReveal = wasShowingTalariaReveal && !revealsTalaria;
  if (revealsTalaria && !self.showsTalariaReveal) {
    self.showsTalariaReveal = YES;
    [self refreshCubeMaterials];
  }
  NSArray<NSNumber *> *facePath = [self facePathFromFaceIndex:currentFaceIndex
                                                  toFaceIndex:nextFaceIndex
                                              includesFullSpin:usesFullSpin];
  NSInteger quarterTurnCount = (NSInteger)facePath.count - 1;
  CGFloat turnRadians = -(CGFloat)M_PI_2 * (CGFloat)quarterTurnCount;
  CGFloat bounceReferenceRadians = wrapsToFirstFace ? -(CGFloat)M_PI : -(CGFloat)M_PI_2;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = TLOnboardingFinalRollAngleForFaceIndex(nextFaceIndex, revealsTalaria);
  CGFloat rotationDuration = usesFullSpin ? TLOnboardingRotationFullSpinDuration : TLOnboardingRotationDuration;

  self.visibleFaceIndex = nextFaceIndex;
  self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  if (revealsTalaria) {
    self.cubePitchAngle = 0.0;
  }
  CGFloat zoomScale = usesFullSpin
      ? TLOnboardingRotationFullSpinZoomScale
      : (wrapsToFirstFace ? TLOnboardingRotationSkipZoomScale : TLOnboardingRotationZoomScale);

  CGFloat bounceDuration = rotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = rotationDuration - bounceDuration;
  SCNVector3 targetPosition = TLOnboardingCarouselCubePosition(revealsTalaria);

  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:bounceReferenceRadians
                                             duration:rotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:zoomScale
                                       finalScale:1.0
                                         duration:mainTurnDuration];
  SCNAction *animation = [SCNAction group:@[turnAction, zoomAction]];
  SCNAction *rollAction = [self rollActionForFacePath:facePath
                                    startingRollAngle:startingRollAngle
                                       finalRollAngle:targetRollAngle
                                             duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialActionForFacePath:facePath
                                                           duration:mainTurnDuration];
  SCNAction *positionAction = [SCNAction moveTo:targetPosition duration:mainTurnDuration];
  positionAction.timingMode = SCNActionTimingModeEaseInEaseOut;

  if (revealsTalaria || leavesTalariaReveal) {
    self.talariaTitleLabel.stringValue = @"Talaria Browser";
    if (revealsTalaria) {
      self.talariaTitleLabel.alphaValue = 0.0;
    }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
      context.duration = mainTurnDuration * 0.70;
      context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      self.talariaTitleLabel.animator.alphaValue = revealsTalaria ? 1.0 : 0.0;
    } completionHandler:nil];
  }

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction, positionAction]]];
  [self.cubeNode runAction:animation completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, strongSelf.cubeYawAngle, 0.0);
      if (strongSelf.showsTalariaReveal) {
        strongSelf.cubePitchAngle = 0.0;
        strongSelf.cubeRollAngle = 0.0;
      }
      strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(strongSelf.cubePitchAngle, 0.0, strongSelf.cubeRollAngle);
      if (revealsTalaria) {
        strongSelf.alternativeBrowserSurfacePrepared = YES;
        [strongSelf refreshCubeMaterials];
      }
      if (leavesTalariaReveal) {
        strongSelf.showsTalariaReveal = NO;
        [strongSelf refreshCubeMaterials];
      }
      strongSelf.cubeRollNode.position = TLOnboardingCarouselCubePosition(strongSelf.showsTalariaReveal);
      [strongSelf updateRimMaterialForFaceIndex:strongSelf.visibleFaceIndex];
      strongSelf.cubeNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
        strongSelf.talariaTitleLabel.alphaValue =
            strongSelf.showsTalariaReveal && !strongSelf.showsAlternativeBrowserReveal ? 1.0 : 0.0;
      if (wrapsToFirstFace) {
        strongSelf.carouselCompletedRoundCount += 1;
      }
      strongSelf.rotationAnimationInProgress = NO;
    });
  }];
}

- (void)rotateToPreviousFace {
    if (self.rotationAnimationInProgress) {
      return;
    }

  if (self.showsAlternativeBrowserReveal) {
    [self rotateFromAlternativeBrowserFaceToTalaria];
    return;
  }

    self.rotationAnimationInProgress = YES;
  NSInteger currentFaceIndex = self.visibleFaceIndex;
  BOOL wrapsToLastFace = currentFaceIndex == TLOnboardingAgentFaceIndex;
  NSInteger previousFaceIndex = wrapsToLastFace ? TLOnboardingNotesFaceIndex : currentFaceIndex - 1;
  BOOL usesFullSpin = wrapsToLastFace ? self.carouselCompletedRoundCount > 1 : self.carouselCompletedRoundCount > 0;
  BOOL reducesCompletedRoundCount = wrapsToLastFace && self.carouselCompletedRoundCount > 0;
  BOOL leavesTalariaReveal = self.showsTalariaReveal &&
      currentFaceIndex == TLOnboardingNotesFaceIndex &&
      previousFaceIndex != TLOnboardingNotesFaceIndex;
  NSArray<NSNumber *> *facePath = [self facePathFromFaceIndex:currentFaceIndex
                                                  toFaceIndex:previousFaceIndex
                                              includesFullSpin:usesFullSpin
                                                     direction:-1];
  NSInteger quarterTurnCount = (NSInteger)facePath.count - 1;
  CGFloat turnRadians = (CGFloat)M_PI_2 * (CGFloat)quarterTurnCount;
  CGFloat bounceReferenceRadians = wrapsToLastFace ? (CGFloat)M_PI : (CGFloat)M_PI_2;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = TLOnboardingFinalRollAngleForFaceIndex(previousFaceIndex, NO);
  CGFloat rotationDuration = usesFullSpin ? TLOnboardingRotationFullSpinDuration : TLOnboardingRotationDuration;

  self.visibleFaceIndex = previousFaceIndex;
  self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  CGFloat zoomScale = usesFullSpin
      ? TLOnboardingRotationFullSpinZoomScale
      : (wrapsToLastFace ? TLOnboardingRotationSkipZoomScale : TLOnboardingRotationZoomScale);

  CGFloat bounceDuration = rotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = rotationDuration - bounceDuration;
  SCNVector3 targetPosition = TLOnboardingCarouselCubePosition(NO);

  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:bounceReferenceRadians
                                             duration:rotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:zoomScale
                                       finalScale:1.0
                                         duration:mainTurnDuration];
  SCNAction *animation = [SCNAction group:@[turnAction, zoomAction]];
  SCNAction *rollAction = [self rollActionForFacePath:facePath
                                    startingRollAngle:startingRollAngle
                                       finalRollAngle:targetRollAngle
                                             duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialActionForFacePath:facePath
                                                           duration:mainTurnDuration];
  SCNAction *positionAction = [SCNAction moveTo:targetPosition duration:mainTurnDuration];
  positionAction.timingMode = SCNActionTimingModeEaseInEaseOut;

  if (leavesTalariaReveal) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
      context.duration = mainTurnDuration * 0.45;
      context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
      self.talariaTitleLabel.animator.alphaValue = 0.0;
    } completionHandler:nil];
  }

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction, positionAction]]];
  [self.cubeNode runAction:animation completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch, strongSelf.cubeYawAngle, 0.0);
        strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(strongSelf.cubePitchAngle, 0.0, strongSelf.cubeRollAngle);
      strongSelf.cubeRollNode.position = targetPosition;
      if (leavesTalariaReveal) {
        strongSelf.showsTalariaReveal = NO;
        [strongSelf refreshCubeMaterials];
      }
      [strongSelf updateRimMaterialForFaceIndex:strongSelf.visibleFaceIndex];
      strongSelf.cubeNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
        strongSelf.talariaTitleLabel.alphaValue =
            strongSelf.showsTalariaReveal && !strongSelf.showsAlternativeBrowserReveal ? 1.0 : 0.0;
      if (reducesCompletedRoundCount) {
        strongSelf.carouselCompletedRoundCount -= 1;
      }
      strongSelf.rotationAnimationInProgress = NO;
    });
    }];
  }

- (void)rotateToAlternativeBrowserFace {
  if (self.rotationAnimationInProgress) {
    return;
  }

  self.rotationAnimationInProgress = YES;
  self.showsTalariaReveal = YES;
  self.showsAlternativeBrowserReveal = YES;
  self.talariaTitleLabel.stringValue = @"Talaria Browser";
  self.talariaTitleLabel.alphaValue = 1.0;
  [self setOpenAppButtonVisible:NO];

  CGFloat turnRadians = -(CGFloat)M_PI_2;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = 0.0;
  CGFloat bounceDuration = TLOnboardingRotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = TLOnboardingRotationDuration - bounceDuration;
  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:-(CGFloat)M_PI_2
                                             duration:TLOnboardingRotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:TLOnboardingRotationZoomScale
                                       finalScale:1.0
                                         duration:mainTurnDuration];
  SCNAction *rollAction = [self rollActionFromAngle:startingRollAngle
                                            toAngle:targetRollAngle
                                includesSkippedFace:NO
                                           duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialTransitionActionFromFaceIndex:TLOnboardingNotesFaceIndex
                                                                    toFaceIndex:TLOnboardingAlternativeBrowserFaceIndex
                                                                       duration:mainTurnDuration];

  self.visibleFaceIndex = TLOnboardingAlternativeBrowserFaceIndex;
  self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  [self setAlternativeBrowserTitleMarkupVisible:YES animatedWithDuration:mainTurnDuration];

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction]]];
  [self.cubeNode runAction:[SCNAction group:@[turnAction, zoomAction]] completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch,
                                                       strongSelf.cubeYawAngle,
                                                       0.0);
      strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(0.0, 0.0, 0.0);
      strongSelf.cubeNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
      [strongSelf updateRimMaterialForFaceIndex:TLOnboardingAlternativeBrowserFaceIndex];
      [strongSelf scheduleOpenAppButtonRevealAfterDelay:TLOnboardingOpenAppButtonRevealDelay];
      strongSelf.rotationAnimationInProgress = NO;
    });
  }];
}

- (void)rotateFromAlternativeBrowserFaceToTalaria {
  if (self.rotationAnimationInProgress) {
    return;
  }

  self.rotationAnimationInProgress = YES;
  self.showsTalariaReveal = YES;
  self.talariaTitleLabel.stringValue = @"Talaria Browser";
  self.talariaTitleLabel.alphaValue = 1.0;
  [self setOpenAppButtonVisible:NO];

  CGFloat turnRadians = (CGFloat)M_PI_2;
  CGFloat startingRollAngle = self.cubeRollAngle;
  CGFloat targetRollAngle = 0.0;
  CGFloat bounceDuration = TLOnboardingRotationDuration * TLOnboardingRotationBounceSettleRatio;
  CGFloat mainTurnDuration = TLOnboardingRotationDuration - bounceDuration;
  SCNAction *turnAction = [self turnActionWithRadians:turnRadians
                               bounceReferenceRadians:(CGFloat)M_PI_2
                                             duration:TLOnboardingRotationDuration];
  SCNAction *zoomAction = [self zoomActionToScale:TLOnboardingRotationZoomScale
                                       finalScale:1.0
                                         duration:mainTurnDuration];
  SCNAction *rollAction = [self rollActionFromAngle:startingRollAngle
                                            toAngle:targetRollAngle
                                includesSkippedFace:NO
                                           duration:mainTurnDuration];
  SCNAction *rimMaterialAction = [self rimMaterialTransitionActionFromFaceIndex:TLOnboardingAlternativeBrowserFaceIndex
                                                                    toFaceIndex:TLOnboardingNotesFaceIndex
                                                                       duration:mainTurnDuration];

  self.visibleFaceIndex = TLOnboardingNotesFaceIndex;
  self.cubeYawAngle += turnRadians;
  self.cubeRollAngle = targetRollAngle;
  [self setAlternativeBrowserTitleMarkupVisible:NO animatedWithDuration:mainTurnDuration];

  __weak typeof(self) weakSelf = self;
  [self.cubeRollNode runAction:[SCNAction group:@[rollAction, rimMaterialAction]]];
  [self.cubeNode runAction:[SCNAction group:@[turnAction, zoomAction]] completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
      TLOnboardingDemoView *strongSelf = weakSelf;
      if (!strongSelf) {
        return;
      }
      strongSelf.showsAlternativeBrowserReveal = NO;
      strongSelf.cubeNode.eulerAngles = SCNVector3Make(TLOnboardingCubePitch,
                                                       strongSelf.cubeYawAngle,
                                                       0.0);
      strongSelf.cubeRollNode.eulerAngles = SCNVector3Make(0.0, 0.0, 0.0);
      strongSelf.cubeNode.scale = SCNVector3Make(1.0, 1.0, 1.0);
      [strongSelf updateRimMaterialForFaceIndex:TLOnboardingNotesFaceIndex];
      strongSelf.rotationAnimationInProgress = NO;
    });
  }];
}

- (NSColor *)surfaceColorForFaceIndex:(NSInteger)faceIndex {
  switch (faceIndex) {
    case TLOnboardingAgentFaceIndex:
      return self.palette.onboardingDemoAutomatorFaceSurface;
    case TLOnboardingBrowserFaceIndex:
      return self.palette.onboardingDemoSafariFaceSurface;
    case TLOnboardingNotesFaceIndex:
      return self.showsTalariaReveal
        ? self.palette.onboardingDemoTalariaFaceSurface
        : self.palette.onboardingDemoNotesFaceSurface;
    case TLOnboardingAlternativeBrowserFaceIndex:
      return self.alternativeBrowserSurfacePrepared
        ? self.palette.onboardingDemoAlternativeBrowserFaceSurface
        : self.palette.onboardingDemoAutomatorFaceSurface;
    default:
      return self.palette.onboardingDemoAutomatorFaceSurface;
  }
}

- (SCNMaterial *)rimMaterialForFaceIndex:(NSInteger)faceIndex {
  SCNMaterial *material = [SCNMaterial material];
  material.diffuse.contents = [self rimTextureForFaceIndex:faceIndex];
  material.diffuse.wrapS = SCNWrapModeClamp;
  material.diffuse.wrapT = SCNWrapModeClamp;
  material.lightingModelName = SCNLightingModelConstant;
  material.doubleSided = YES;
  return material;
}

- (void)updateRimMaterialForFaceIndex:(NSInteger)faceIndex {
  self.rimMaterial.diffuse.contents = [self rimTextureForFaceIndex:faceIndex];
}

- (SCNAction *)rimMaterialActionFromFaceIndex:(NSInteger)startingFaceIndex
                                  toFaceIndex:(NSInteger)targetFaceIndex
                          includesSkippedFace:(BOOL)includesSkippedFace
                                     duration:(CGFloat)duration {
  if (!includesSkippedFace) {
    return [self rimMaterialTransitionActionFromFaceIndex:startingFaceIndex
                                              toFaceIndex:targetFaceIndex
                                                 duration:duration];
  }

  CGFloat firstTransitionDuration = duration * 0.5;
  CGFloat secondTransitionDuration = duration - firstTransitionDuration;
  return [SCNAction sequence:@[
    [self rimMaterialTransitionActionFromFaceIndex:startingFaceIndex
                                       toFaceIndex:TLOnboardingHiddenFaceIndex
                                          duration:firstTransitionDuration],
    [self rimMaterialTransitionActionFromFaceIndex:TLOnboardingHiddenFaceIndex
                                       toFaceIndex:targetFaceIndex
                                          duration:secondTransitionDuration],
  ]];
}

- (SCNAction *)rimMaterialActionForFacePath:(NSArray<NSNumber *> *)facePath
                                   duration:(CGFloat)duration {
  if (facePath.count <= 1) {
    return [SCNAction waitForDuration:duration];
  }

  CGFloat segmentDuration = duration / (CGFloat)(facePath.count - 1);
  NSMutableArray<SCNAction *> *actions = [NSMutableArray arrayWithCapacity:facePath.count - 1];
  for (NSUInteger index = 1; index < facePath.count; index++) {
    [actions addObject:[self rimMaterialTransitionActionFromFaceIndex:facePath[index - 1].integerValue
                                                           toFaceIndex:facePath[index].integerValue
                                                              duration:segmentDuration]];
  }
  return [SCNAction sequence:actions];
}

- (SCNAction *)rimMaterialTransitionActionFromColor:(NSColor *)startingColor
                                            toColor:(NSColor *)targetColor
                                           duration:(CGFloat)duration {
  NSArray<NSImage *> *textures = [self rimTransitionTexturesFromColor:startingColor
                                                              toColor:targetColor
                                                             duration:duration];
  return [self rimMaterialAnimationActionWithTextures:textures duration:duration];
}

- (SCNAction *)rimMaterialTransitionActionFromFaceIndex:(NSInteger)startingFaceIndex
                                            toFaceIndex:(NSInteger)targetFaceIndex
                                               duration:(CGFloat)duration {
  NSArray<NSImage *> *textures = [self rimTransitionTexturesFromFaceIndex:startingFaceIndex
                                                              toFaceIndex:targetFaceIndex
                                                                 duration:duration];
  return [self rimMaterialAnimationActionWithTextures:textures duration:duration];
}

- (NSArray<NSImage *> *)rimTransitionTexturesFromColor:(NSColor *)startingColor
                                               toColor:(NSColor *)targetColor
                                              duration:(CGFloat)duration {
  NSInteger frameCount = MAX(2, (NSInteger)ceil(duration * TLOnboardingRimTransitionFramesPerSecond) + 1);
  NSMutableArray<NSImage *> *textures = [NSMutableArray arrayWithCapacity:(NSUInteger)frameCount];
  NSImage *startingTexture = [self rimTextureWithSurfaceColor:startingColor];
  NSImage *targetTexture = [self rimTextureWithSurfaceColor:targetColor];
  for (NSInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
    CGFloat progress = frameCount <= 1 ? 1.0 : (CGFloat)frameIndex / (CGFloat)(frameCount - 1);
    NSImage *texture = [self rimTextureByBlendingTexture:startingTexture
                                             withTexture:targetTexture
                                                progress:TLOnboardingEaseInOutProgress(progress)];
    [textures addObject:texture];
  }
  return textures;
}

- (NSArray<NSImage *> *)rimTransitionTexturesFromFaceIndex:(NSInteger)startingFaceIndex
                                               toFaceIndex:(NSInteger)targetFaceIndex
                                                  duration:(CGFloat)duration {
  NSInteger frameCount = MAX(2, (NSInteger)ceil(duration * TLOnboardingRimTransitionFramesPerSecond) + 1);
  NSMutableArray<NSImage *> *textures = [NSMutableArray arrayWithCapacity:(NSUInteger)frameCount];
  NSImage *startingTexture = [self rimTextureForFaceIndex:startingFaceIndex];
  NSImage *targetTexture = [self rimTextureForFaceIndex:targetFaceIndex];
  for (NSInteger frameIndex = 0; frameIndex < frameCount; frameIndex++) {
    CGFloat progress = frameCount <= 1 ? 1.0 : (CGFloat)frameIndex / (CGFloat)(frameCount - 1);
    NSImage *texture = [self rimTextureByBlendingTexture:startingTexture
                                             withTexture:targetTexture
                                                progress:TLOnboardingEaseInOutProgress(progress)];
    [textures addObject:texture];
  }
  return textures;
}

- (SCNAction *)rimMaterialAnimationActionWithTextures:(NSArray<NSImage *> *)textures
                                             duration:(CGFloat)duration {
  __weak typeof(self) weakSelf = self;
  return [SCNAction customActionWithDuration:duration actionBlock:^(SCNNode *node, CGFloat elapsedTime) {
    TLOnboardingDemoView *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    NSUInteger lastIndex = textures.count - 1;
    if (lastIndex == 0) {
      strongSelf.rimMaterial.diffuse.contents = textures.firstObject;
      return;
    }
    CGFloat progress = duration <= 0.0 ? 1.0 : TLOnboardingClampedValue(elapsedTime / duration, 0.0, 1.0);
    NSUInteger textureIndex = MIN(lastIndex, (NSUInteger)llround(progress * (CGFloat)lastIndex));
    strongSelf.rimMaterial.diffuse.contents = textures[textureIndex];
  }];
}

- (NSImage *)rimTextureWithSurfaceColor:(NSColor *)surfaceColor {
  return [self rimTextureWithSurfaceColor:surfaceColor
                        flipsFaceGradient:NO];
}

- (NSImage *)rimTextureForFaceIndex:(NSInteger)faceIndex {
  return [self rimTextureWithSurfaceColor:[self surfaceColorForFaceIndex:faceIndex]
                        flipsFaceGradient:TLOnboardingFaceUsesFlippedGradient(faceIndex)];
}

- (NSImage *)rimTextureWithSurfaceColor:(NSColor *)surfaceColor
                      flipsFaceGradient:(BOOL)flipsFaceGradient {
  return [self textureWithIcon:nil
               backgroundColor:surfaceColor
             showsFaceGradient:YES
             flipsFaceGradient:flipsFaceGradient
                          size:TLOnboardingRimTextureSize
                     iconInset:0.0
           iconSourceCropInset:0.0
                    clipsIcon:NO
           flipsIconVertically:YES
                   drawsBorder:NO];
}

- (NSImage *)rimTextureByBlendingTexture:(NSImage *)startingTexture
                             withTexture:(NSImage *)targetTexture
                                progress:(CGFloat)progress {
  CGFloat clampedProgress = TLOnboardingClampedValue(progress, 0.0, 1.0);
  NSSize textureSize = NSMakeSize(TLOnboardingRimTextureSize, TLOnboardingRimTextureSize);
  NSImage *texture = [[NSImage alloc] initWithSize:textureSize];
  [texture lockFocus];

  NSGraphicsContext *context = NSGraphicsContext.currentContext;
  context.imageInterpolation = NSImageInterpolationHigh;

  NSRect textureRect = NSMakeRect(0.0, 0.0, textureSize.width, textureSize.height);
  NSDictionary *hints = @{ NSImageHintInterpolation: @(NSImageInterpolationHigh) };
  [startingTexture drawInRect:textureRect
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0
               respectFlipped:NO
                        hints:hints];
  [targetTexture drawInRect:textureRect
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:clampedProgress
             respectFlipped:NO
                      hints:hints];

  [texture unlockFocus];
  return texture;
}

- (SCNAction *)rollActionFromAngle:(CGFloat)startingRollAngle
                            toAngle:(CGFloat)targetRollAngle
                includesSkippedFace:(BOOL)includesSkippedFace
                           duration:(CGFloat)duration {
  if (!includesSkippedFace) {
    SCNAction *rollAction = [SCNAction rotateByX:0.0
                                               y:0.0
                                               z:targetRollAngle - startingRollAngle
                                        duration:duration];
    rollAction.timingMode = SCNActionTimingModeEaseInEaseOut;
    return rollAction;
  }

  CGFloat skippedRollAngle = TLOnboardingRollAngleForFaceIndex(TLOnboardingHiddenFaceIndex);
  SCNAction *rollToSkippedFaceAction = [SCNAction rotateByX:0.0
                                                          y:0.0
                                                          z:skippedRollAngle - startingRollAngle
                                                   duration:duration * 0.5];
  rollToSkippedFaceAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  SCNAction *rollToTargetFaceAction = [SCNAction rotateByX:0.0
                                                         y:0.0
                                                         z:targetRollAngle - skippedRollAngle
                                                  duration:duration * 0.5];
  rollToTargetFaceAction.timingMode = SCNActionTimingModeEaseInEaseOut;
  return [SCNAction sequence:@[
    rollToSkippedFaceAction,
    rollToTargetFaceAction,
  ]];
}

- (NSArray<SCNMaterial *> *)cubeMaterials {
  SCNMaterial *agentMaterial = [self materialWithIcon:[self appIconWithBundleIdentifier:@"com.apple.Automator"
                                                                          fallbackPaths:@[@"/System/Applications/Automator.app",
                                                                                          @"/Applications/Automator.app"]]
                                      backgroundColor:self.palette.onboardingDemoAutomatorFaceSurface
                                    showsFaceGradient:YES];
  SCNMaterial *browserMaterial = [self materialWithIcon:[self appIconWithBundleIdentifier:@"com.apple.Safari"
                                                                            fallbackPaths:@[@"/Applications/Safari.app",
                                                                                            @"/System/Applications/Safari.app",
                                                                                            @"/System/Cryptexes/App/System/Applications/Safari.app"]]
                                        backgroundColor:self.palette.onboardingDemoSafariFaceSurface
                                      showsFaceGradient:YES];
  NSImage *thirdFaceIcon = nil;
  NSColor *thirdFaceSurface = nil;
  CGFloat thirdFaceIconSourceCropInset = TLOnboardingIconSourceCropInset;
  if (self.showsTalariaReveal) {
    thirdFaceIcon = [self talariaAppIcon];
    thirdFaceSurface = self.palette.onboardingDemoTalariaFaceSurface;
    thirdFaceIconSourceCropInset = TLOnboardingTalariaIconSourceCropInset;
  } else {
    thirdFaceIcon = [self appIconWithBundleIdentifier:@"com.apple.Notes"
                                       fallbackPaths:@[@"/System/Applications/Notes.app",
                                                       @"/Applications/Notes.app"]];
    thirdFaceSurface = self.palette.onboardingDemoNotesFaceSurface;
  }
  SCNMaterial *thirdFaceMaterial = [self materialWithIcon:thirdFaceIcon
                                          backgroundColor:thirdFaceSurface
                                        showsFaceGradient:YES
                                        flipsFaceGradient:NO
                                                 iconInset:TLOnboardingIconInset
                                       iconSourceCropInset:thirdFaceIconSourceCropInset
                                                clipsIcon:!self.showsTalariaReveal
                                               flipsIconVertically:YES
                                               drawsBorder:NO];
  SCNMaterial *fourthFaceMaterial = agentMaterial;
  SCNMaterial *capMaterial = [self materialWithIcon:nil
                                    backgroundColor:self.palette.onboardingDemoCapFaceSurface
                                  showsFaceGradient:YES];
  self.rimMaterial = [self rimMaterialForFaceIndex:self.visibleFaceIndex];

  return @[
    agentMaterial,
    browserMaterial,
    thirdFaceMaterial,
    fourthFaceMaterial,
    capMaterial,
    capMaterial,
    self.rimMaterial,
  ];
}

- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient {
  return [self materialWithIcon:icon
                backgroundColor:backgroundColor
              showsFaceGradient:showsFaceGradient
              flipsFaceGradient:NO
                     drawsBorder:NO];
}

- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient {
  return [self materialWithIcon:icon
                backgroundColor:backgroundColor
              showsFaceGradient:showsFaceGradient
              flipsFaceGradient:flipsFaceGradient
                     drawsBorder:NO];
}

- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                       drawsBorder:(BOOL)drawsBorder {
  return [self materialWithIcon:icon
                backgroundColor:backgroundColor
              showsFaceGradient:showsFaceGradient
              flipsFaceGradient:NO
                       iconInset:TLOnboardingIconInset
             iconSourceCropInset:TLOnboardingIconSourceCropInset
                      clipsIcon:YES
            flipsIconVertically:YES
                     drawsBorder:drawsBorder];
}

- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient
                         iconInset:(CGFloat)iconInset
               iconSourceCropInset:(CGFloat)iconSourceCropInset
                        clipsIcon:(BOOL)clipsIcon
               flipsIconVertically:(BOOL)flipsIconVertically
                       drawsBorder:(BOOL)drawsBorder {
  SCNMaterial *material = [SCNMaterial material];
  material.diffuse.contents = [self textureWithIcon:icon
                                    backgroundColor:backgroundColor
                                  showsFaceGradient:showsFaceGradient
                                  flipsFaceGradient:flipsFaceGradient
                                               size:TLOnboardingFaceTextureSize
                                          iconInset:iconInset
                                iconSourceCropInset:iconSourceCropInset
                                         clipsIcon:clipsIcon
                                flipsIconVertically:flipsIconVertically
                                        drawsBorder:drawsBorder];
  material.diffuse.wrapS = SCNWrapModeClamp;
  material.diffuse.wrapT = SCNWrapModeClamp;
  material.lightingModelName = SCNLightingModelConstant;
  material.doubleSided = YES;
  return material;
}

- (SCNMaterial *)materialWithIcon:(nullable NSImage *)icon
                  backgroundColor:(NSColor *)backgroundColor
                showsFaceGradient:(BOOL)showsFaceGradient
                flipsFaceGradient:(BOOL)flipsFaceGradient
                       drawsBorder:(BOOL)drawsBorder {
  return [self materialWithIcon:icon
                backgroundColor:backgroundColor
              showsFaceGradient:showsFaceGradient
              flipsFaceGradient:flipsFaceGradient
                       iconInset:TLOnboardingIconInset
             iconSourceCropInset:TLOnboardingIconSourceCropInset
                      clipsIcon:YES
            flipsIconVertically:YES
                     drawsBorder:drawsBorder];
}

- (NSImage *)faceTextureWithIcon:(nullable NSImage *)icon
                 backgroundColor:(NSColor *)backgroundColor
               showsFaceGradient:(BOOL)showsFaceGradient {
  return [self faceTextureWithIcon:icon
                   backgroundColor:backgroundColor
                 showsFaceGradient:showsFaceGradient
                 flipsFaceGradient:NO
                        drawsBorder:NO];
}

- (NSImage *)faceTextureWithIcon:(nullable NSImage *)icon
                 backgroundColor:(NSColor *)backgroundColor
               showsFaceGradient:(BOOL)showsFaceGradient
                      drawsBorder:(BOOL)drawsBorder {
  return [self faceTextureWithIcon:icon
                   backgroundColor:backgroundColor
                 showsFaceGradient:showsFaceGradient
                 flipsFaceGradient:NO
                        drawsBorder:drawsBorder];
}

- (NSImage *)faceTextureWithIcon:(nullable NSImage *)icon
                 backgroundColor:(NSColor *)backgroundColor
               showsFaceGradient:(BOOL)showsFaceGradient
               flipsFaceGradient:(BOOL)flipsFaceGradient
                      drawsBorder:(BOOL)drawsBorder {
  return [self textureWithIcon:icon
               backgroundColor:backgroundColor
             showsFaceGradient:showsFaceGradient
             flipsFaceGradient:flipsFaceGradient
                          size:TLOnboardingFaceTextureSize
                     iconInset:TLOnboardingIconInset
           iconSourceCropInset:TLOnboardingIconSourceCropInset
                    clipsIcon:YES
           flipsIconVertically:YES
                   drawsBorder:drawsBorder];
}

- (NSImage *)textureWithIcon:(nullable NSImage *)icon
             backgroundColor:(NSColor *)backgroundColor
           showsFaceGradient:(BOOL)showsFaceGradient
           flipsFaceGradient:(BOOL)flipsFaceGradient
                        size:(CGFloat)textureDimension
                   iconInset:(CGFloat)iconInset
         iconSourceCropInset:(CGFloat)iconSourceCropInset
                  clipsIcon:(BOOL)clipsIcon
         flipsIconVertically:(BOOL)flipsIconVertically
                 drawsBorder:(BOOL)drawsBorder {
  NSSize textureSize = NSMakeSize(textureDimension, textureDimension);
  NSImage *texture = [[NSImage alloc] initWithSize:textureSize];
  [texture lockFocus];

  NSGraphicsContext *context = NSGraphicsContext.currentContext;
  context.imageInterpolation = NSImageInterpolationHigh;

  NSRect textureRect = NSMakeRect(0.0, 0.0, textureSize.width, textureSize.height);
  NSColor *fillColor = backgroundColor ?: self.palette.onboardingDemoCubeFaceSurface;
  [fillColor setFill];
  NSRectFill(textureRect);
  if (showsFaceGradient) {
    [self drawFaceGradientInRect:textureRect
                    surfaceColor:fillColor
               flipsFaceGradient:flipsFaceGradient];
  }

  if (icon) {
    NSRect iconRect = NSInsetRect(textureRect, iconInset, iconInset);
    NSRect iconSourceRect = NSInsetRect(NSMakeRect(0.0,
                                                   0.0,
                                                   icon.size.width,
                                                   icon.size.height),
                                        iconSourceCropInset,
                                        iconSourceCropInset);
    CGContextRef cgContext = context.CGContext;
    if (cgContext) {
      CGContextSetShadowWithColor(cgContext, CGSizeZero, 0.0, NULL);
    }
    [NSGraphicsContext saveGraphicsState];
    if (clipsIcon) {
      CGFloat iconClipCornerRadius = NSWidth(iconRect) * TLOnboardingIconClipCornerRadiusRatio;
      NSBezierPath *iconClipPath = [NSBezierPath bezierPathWithRoundedRect:iconRect
                                                                   xRadius:iconClipCornerRadius
                                                                   yRadius:iconClipCornerRadius];
      [iconClipPath addClip];
    }
    if (flipsIconVertically) {
      NSAffineTransform *iconFlipTransform = [NSAffineTransform transform];
      [iconFlipTransform translateXBy:0.0 yBy:NSMinY(iconRect) + NSMaxY(iconRect)];
      [iconFlipTransform scaleXBy:1.0 yBy:-1.0];
      [iconFlipTransform concat];
    }
    [icon drawInRect:iconRect
            fromRect:iconSourceRect
           operation:NSCompositingOperationSourceOver
            fraction:1.0
      respectFlipped:NO
               hints:@{ NSImageHintInterpolation: @(NSImageInterpolationHigh) }];
    [NSGraphicsContext restoreGraphicsState];
  }

  if (drawsBorder) {
    NSRect borderRect = NSInsetRect(textureRect, TLOnboardingFaceBorderInset, TLOnboardingFaceBorderInset);
    NSBezierPath *borderPath = [NSBezierPath bezierPathWithRect:borderRect];
    [borderPath setLineWidth:TLOnboardingFaceBorderWidth];
    [self.palette.onboardingDemoCubeFaceBorder setStroke];
    [borderPath stroke];
  }

  [texture unlockFocus];
  return texture;
}

- (void)drawFaceGradientInRect:(NSRect)textureRect
                  surfaceColor:(NSColor *)surfaceColor
             flipsFaceGradient:(BOOL)flipsFaceGradient {
  BOOL usesTalariaGradient = [surfaceColor isEqual:self.palette.onboardingDemoTalariaFaceSurface];
  BOOL usesAlternativeBrowserGradient = [surfaceColor isEqual:self.palette.onboardingDemoAlternativeBrowserFaceSurface];
  NSArray<NSColor *> *gradientColors = nil;
  if (usesTalariaGradient) {
    gradientColors = @[self.palette.onboardingDemoTalariaFaceGradientBottom,
                       self.palette.onboardingDemoTalariaFaceGradientTop];
  } else if (usesAlternativeBrowserGradient) {
    gradientColors = @[self.palette.onboardingDemoAlternativeBrowserFaceGradientBottom,
                       self.palette.onboardingDemoAlternativeBrowserFaceGradientTop];
  } else {
    gradientColors = @[self.palette.onboardingDemoCubeFaceBorder,
                       self.palette.transparentSurface];
  }
  if (flipsFaceGradient) {
    gradientColors = gradientColors.reverseObjectEnumerator.allObjects;
  }
  NSGradient *faceGradient = [[NSGradient alloc] initWithColors:gradientColors];
  NSPoint startPoint = NSMakePoint(NSMidX(textureRect), NSMaxY(textureRect));
  NSPoint endPoint = NSMakePoint(NSMidX(textureRect), NSMinY(textureRect));
  [faceGradient drawFromPoint:startPoint
                      toPoint:endPoint
                      options:0];
}

- (nullable NSImage *)appIconWithBundleIdentifier:(NSString *)bundleIdentifier
                                    fallbackPaths:(NSArray<NSString *> *)fallbackPaths {
  NSURL *applicationURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bundleIdentifier];
  if (applicationURL.path.length > 0) {
    NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:applicationURL.path];
    icon.size = NSMakeSize(TLOnboardingFaceTextureSize, TLOnboardingFaceTextureSize);
    return icon;
  }

  for (NSString *path in fallbackPaths) {
    NSString *expandedPath = [path stringByExpandingTildeInPath];
    if ([NSFileManager.defaultManager fileExistsAtPath:expandedPath]) {
      NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:expandedPath];
      icon.size = NSMakeSize(TLOnboardingFaceTextureSize, TLOnboardingFaceTextureSize);
      return icon;
    }
  }

  return nil;
}

- (nullable NSImage *)talariaAppIcon {
  NSImage *icon = NSApplication.sharedApplication.applicationIconImage;
  icon.size = NSMakeSize(TLOnboardingFaceTextureSize, TLOnboardingFaceTextureSize);
  return icon;
}

@end
