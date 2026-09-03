#import "NotchOverlayController.h"
#import "NotchOverlayState.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static NSString * const TLNSFilenamesPasteboardType = @"NSFilenamesPboardType";
static NSString * const TLPublicFileURLPasteboardType = @"public.file-url";
static NSString * const TLApplePromisedFileURLPasteboardType = @"com.apple.pasteboard.promised-file-url";

typedef NS_ENUM(NSUInteger, TLNotchOverlayPresentation) {
  TLNotchOverlayPresentationCompact = 0,
  TLNotchOverlayPresentationDropPrompt,
};

static NSArray<NSURL *> *TLFileURLsFromPasteboard(NSPasteboard *pasteboard) {
  NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class]
                                                         options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
  if (fileURLs.count > 0) {
    return fileURLs;
  }

  id filenames = [pasteboard propertyListForType:TLNSFilenamesPasteboardType];
  if ([filenames isKindOfClass:NSArray.class]) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (id filename in (NSArray *)filenames) {
      if ([filename isKindOfClass:NSString.class] && [filename length] > 0) {
        [urls addObject:[NSURL fileURLWithPath:filename]];
      }
    }
    if (urls.count > 0) {
      return urls;
    }
  }

  NSString *fileURLString = [pasteboard stringForType:NSPasteboardTypeFileURL] ?:
    [pasteboard stringForType:TLPublicFileURLPasteboardType];
  NSURL *fileURL = fileURLString.length > 0 ? [NSURL URLWithString:fileURLString] : nil;
  if (fileURL.isFileURL) {
    return @[fileURL];
  }

  return @[];
}

static BOOL TLPasteboardContainsFileDrag(NSPasteboard *pasteboard) {
  if (TLFileURLsFromPasteboard(pasteboard).count > 0) {
    return YES;
  }

  NSArray<NSPasteboardType> *types = pasteboard.types ?: @[];
  for (NSPasteboardType type in types) {
    if ([type isEqualToString:NSPasteboardTypeFileURL] ||
        [type isEqualToString:TLPublicFileURLPasteboardType] ||
        [type isEqualToString:TLNSFilenamesPasteboardType] ||
        [type isEqualToString:TLApplePromisedFileURLPasteboardType]) {
      return YES;
    }
  }

  return NO;
}

static NSUInteger TLFileCountFromPasteboard(NSPasteboard *pasteboard) {
  NSArray<NSURL *> *fileURLs = TLFileURLsFromPasteboard(pasteboard);
  if (fileURLs.count > 0) {
    return fileURLs.count;
  }

  NSUInteger fileItemCount = 0;
  for (NSPasteboardItem *item in pasteboard.pasteboardItems ?: @[]) {
    NSArray<NSPasteboardType> *types = item.types ?: @[];
    if ([types containsObject:NSPasteboardTypeFileURL] ||
        [types containsObject:TLPublicFileURLPasteboardType] ||
        [types containsObject:TLNSFilenamesPasteboardType] ||
        [types containsObject:TLApplePromisedFileURLPasteboardType]) {
      fileItemCount += 1;
    }
  }

  return fileItemCount;
}

@interface TLNotchOverlayView : NSView <NSDraggingDestination>

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, copy, nullable) TLNotchOverlayFileDropHandler fileDropHandler;
@property (nonatomic) BOOL dropPromptVisible;
@property (nonatomic) CGFloat dropPromptProgress;
@property (nonatomic) NSUInteger dropPromptFileCount;
@property (nonatomic) BOOL fileDragHovered;
@property (nonatomic) BOOL tracksFileDragHoverExternally;
@property (nonatomic, strong) NSImageView *dropIconView;
@property (nonatomic, strong) CAGradientLayer *dropGlareLayer;
@property (nonatomic, strong) CALayer *dropGlareContainer;
@property (nonatomic, strong) CAShapeLayer *dropGlareMask;

@end

@implementation TLNotchOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    _dropIconView = [[NSImageView alloc] init];
    _dropIconView.wantsLayer = YES;
    _dropIconView.image = [NSImage imageWithSystemSymbolName:@"tray.and.arrow.down" accessibilityDescription:@"Drop files here"];
    _dropIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _dropIconView.hidden = YES;
    [self addSubview:_dropIconView];
    _dropGlareLayer = [CAGradientLayer layer];
    _dropGlareLayer.opacity = 0.0;
    _dropGlareLayer.startPoint = CGPointMake(0.0, 0.5);
    _dropGlareLayer.endPoint = CGPointMake(1.0, 0.5);
    _dropGlareLayer.locations = @[@0.0, @0.5, @1.0];
    _dropGlareContainer = [CALayer layer];
    _dropGlareMask = [CAShapeLayer layer];
    _dropGlareContainer.mask = _dropGlareMask;
    [_dropGlareContainer addSublayer:_dropGlareLayer];
    [self.layer addSublayer:_dropGlareContainer];
    [self registerForDraggedTypes:@[
      NSPasteboardTypeFileURL,
      TLPublicFileURLPasteboardType,
      TLNSFilenamesPasteboardType,
      TLApplePromisedFileURLPasteboardType,
    ]];
  }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (NSView *)hitTest:(NSPoint)point {
  return [super hitTest:point] ? self : nil;
}

- (void)layout {
  [super layout];
  CGFloat size = self.palette.notchOverlayDropIconSize;
  self.dropIconView.frame = NSMakeRect(NSMidX(self.bounds) - size * 0.5,
                                      NSMidY(self.bounds) - size * 0.5, size, size);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.dropGlareContainer.frame = self.bounds;
  CGFloat bandWidth = NSWidth(self.bounds) * 0.25;
  self.dropGlareLayer.frame = CGRectMake(-bandWidth, 0.0, bandWidth, NSHeight(self.bounds));
  self.dropGlareMask.frame = self.dropGlareContainer.bounds;
  NSRect targetRect = NSInsetRect(self.dropGlareContainer.bounds,
    self.palette.notchOverlayTopFlareOutset + self.palette.notchOverlayDropTargetInset,
    self.palette.notchOverlayDropTargetInset);
  CGPathRef path = CGPathCreateWithRoundedRect(NSRectToCGRect(targetRect),
    self.palette.radiusMedium, self.palette.radiusMedium, NULL);
  self.dropGlareMask.path = path;
  CGPathRelease(path);
  [CATransaction commit];
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.dropIconView.contentTintColor = palette.notchOverlayText;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.dropGlareLayer.colors = @[(id)palette.transparentSurface.CGColor,
    (id)palette.notchOverlayText.CGColor, (id)palette.transparentSurface.CGColor];
  self.dropGlareMask.fillColor = palette.transparentSurface.CGColor;
  self.dropGlareMask.strokeColor = palette.notchOverlayText.CGColor;
  self.dropGlareMask.lineWidth = palette.borderWidth;
  self.dropGlareMask.lineDashPattern = @[@(palette.space3), @(palette.space2)];
  [CATransaction commit];
  self.needsLayout = YES;
  self.needsDisplay = YES;
}

- (void)setDropPromptVisible:(BOOL)visible {
  _dropPromptVisible = visible;
  if (!visible) {
    self.fileDragHovered = NO;
  }
  self.needsDisplay = YES;
}

- (void)setFileDragHovered:(BOOL)hovered {
  hovered = hovered && self.dropPromptVisible;
  if (_fileDragHovered == hovered) {
    return;
  }
  _fileDragHovered = hovered;
  [self.dropIconView.layer removeAllAnimations];
  [self.dropGlareLayer removeAllAnimations];
  self.dropIconView.hidden = !hovered;
  if (hovered) {
    [self layoutSubtreeIfNeeded];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.0;
    fade.toValue = @1.0;
    CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    slide.fromValue = @(self.dropIconView.isFlipped
      ? -self.palette.notchOverlayDropIconSlideDistance : self.palette.notchOverlayDropIconSlideDistance);
    slide.toValue = @0.0;
    CAAnimationGroup *entrance = [CAAnimationGroup animation];
    fade.duration = self.palette.notchOverlayDropIconAnimationDuration;
    slide.duration = self.palette.notchOverlayDropIconAnimationDuration;
    entrance.animations = @[fade, slide];
    entrance.duration = self.palette.notchOverlayDropIconAnimationDuration;
    entrance.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [self.dropIconView.layer addAnimation:entrance forKey:@"dropIconEntrance"];

    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
    CGFloat halfBand = CGRectGetWidth(self.dropGlareLayer.bounds) * 0.5;
    sweep.fromValue = @(-halfBand);
    sweep.toValue = @(NSWidth(self.bounds) + halfBand);
    sweep.duration = self.palette.notchOverlayDropGlareDuration;
    CAKeyframeAnimation *glareFade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    glareFade.values = @[@0.0, @(self.palette.notchOverlayDropGlareOpacity),
      @(self.palette.notchOverlayDropGlareOpacity), @0.0];
    glareFade.keyTimes = @[@0.0, @0.15, @0.85, @1.0];
    glareFade.duration = self.palette.notchOverlayDropGlareDuration;
    CAAnimationGroup *glare = [CAAnimationGroup animation];
    glare.animations = @[sweep, glareFade];
    glare.duration = self.palette.notchOverlayDropGlareDuration;
    glare.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.dropGlareLayer addAnimation:glare forKey:@"dropBorderGlare"];
  }
  self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent *)event {
  if (self.target && self.action && [self.target respondsToSelector:self.action]) {
    [NSApp sendAction:self.action to:self.target from:self];
  }
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];

  TLThemePalette *palette = self.palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  NSBezierPath *path = [self notchPathInRect:self.bounds palette:palette];

  [palette.notchOverlaySurface setFill];
  [path fill];
  if (self.dropPromptVisible) {
    NSRect targetRect = NSInsetRect(self.bounds,
      palette.notchOverlayTopFlareOutset + palette.notchOverlayDropTargetInset,
      palette.notchOverlayDropTargetInset);
    CGPathRef target = CGPathCreateWithRoundedRect(NSRectToCGRect(targetRect),
      palette.radiusMedium, palette.radiusMedium, NULL);
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGFloat dashes[] = {palette.space3, palette.space2};
    CGContextSaveGState(context);
    CGContextAddPath(context, target);
    CGContextSetLineDash(context, palette.space0, dashes, 2);
    CGContextSetLineWidth(context, palette.borderWidth);
    CGContextSetStrokeColorWithColor(context, palette.notchOverlayDropTargetBorder.CGColor);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
    CGPathRelease(target);
    if (!self.fileDragHovered) {
      [self drawDropPromptInRect:self.bounds palette:palette];
      [self drawDropPromptProgressInRect:self.bounds palette:palette];
    }
  }
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  BOOL fileDrag = TLPasteboardContainsFileDrag(sender.draggingPasteboard);
  if (!self.tracksFileDragHoverExternally) {
    self.fileDragHovered = fileDrag;
  }
  return fileDrag ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
  return [self draggingEntered:sender];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  return TLPasteboardContainsFileDrag(sender.draggingPasteboard);
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  if (!self.tracksFileDragHoverExternally) {
    self.fileDragHovered = NO;
  }
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
  self.fileDragHovered = NO;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  self.fileDragHovered = NO;
  NSArray<NSURL *> *fileURLs = TLFileURLsFromPasteboard(sender.draggingPasteboard);
  if (fileURLs.count == 0) {
    return NO;
  }

  if (self.fileDropHandler) {
    self.fileDropHandler(fileURLs);
  } else if (self.target && self.action && [self.target respondsToSelector:self.action]) {
    [NSApp sendAction:self.action to:self.target from:self];
  }

  return YES;
}

- (NSBezierPath *)notchPathInRect:(NSRect)rect palette:(TLThemePalette *)palette {
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

- (void)drawDropPromptInRect:(NSRect)rect palette:(TLThemePalette *)palette {
  NSDictionary<NSAttributedStringKey, id> *attributes = @{
    NSFontAttributeName: palette.notchOverlayLabelFont,
    NSForegroundColorAttributeName: palette.notchOverlayText,
  };
  NSString *text = self.dropPromptFileCount == 1 ? @"Drop file here" : @"Drop files here";
  CGFloat bottomInset = palette.notchOverlayDropVerticalPadding * 0.72;
  CGFloat topInset = palette.notchOverlayDropVerticalPadding * 0.72;
  NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:text attributes:attributes];
  NSSize textSize = attributedText.size;
  CGFloat availableHeight = MAX(0.0, NSHeight(rect) - bottomInset - topInset);
  NSPoint textPoint = NSMakePoint(NSMidX(rect) - (textSize.width * 0.5),
                                  NSMinY(rect) + bottomInset + ((availableHeight - textSize.height) * 0.5));

  [attributedText drawAtPoint:textPoint];
}

- (void)drawDropPromptProgressInRect:(NSRect)rect palette:(TLThemePalette *)palette {
  CGFloat flareOutset = MIN(palette.notchOverlayTopFlareOutset, rect.size.width * 0.24);
  CGFloat horizontalInset = flareOutset + palette.notchOverlayDropHorizontalPadding;
  CGFloat fullWidth = MAX(0.0, NSWidth(rect) - (horizontalInset * 2.0));
  CGFloat progress = MIN(1.0, MAX(0.0, self.dropPromptProgress));
  CGFloat progressWidth = fullWidth * progress;
  CGFloat height = MIN(palette.notchOverlayProgressHeight, NSHeight(rect) * 0.08);
  CGFloat y = NSMinY(rect);
  NSRect trackRect = NSMakeRect(NSMinX(rect) + horizontalInset, y, fullWidth, height);
  NSRect progressRect = NSMakeRect(NSMinX(trackRect), y, progressWidth, height);

  [palette.notchOverlayProgressTrack setFill];
  [[NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:height * 0.5 yRadius:height * 0.5] fill];
  if (progressWidth > 0.0) {
    [palette.notchOverlayProgress setFill];
    [[NSBezierPath bezierPathWithRoundedRect:progressRect xRadius:height * 0.5 yRadius:height * 0.5] fill];
  }
}

@end

@interface TLNotchOverlayController ()

@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, strong) NSTimer *trackingTimer;
@property (nonatomic, strong) id localEventMonitor;
@property (nonatomic, strong) id globalEventMonitor;
@property (nonatomic, strong) NSPanel *overlayWindow;
@property (nonatomic, strong) TLNotchOverlayView *overlayView;
@property (nonatomic) NSPoint lastMouseLocation;
@property (nonatomic) TLNotchOverlayPresentation overlayPresentation;
@property (nonatomic) BOOL fileDragActive;
@property (nonatomic) NSUInteger activeFileDragCount;
@property (nonatomic) NSInteger idleDragPasteboardChangeCount;
@property (nonatomic) NSInteger activeFileDragPasteboardChangeCount;
@property (nonatomic, strong) TLShakeRecognizer *fileDragShakeRecognizer;
@property (nonatomic, strong) TLDropPromptTimer *dropPromptTimer;
@property (nonatomic) BOOL appearanceAnimationInFlight;
@property (nonatomic) BOOL disappearanceAnimationInFlight;
@property (nonatomic) NSUInteger overlayAnimationGeneration;
@property (nonatomic, strong) NSTimer *frameAnimationTimer;
@property (nonatomic) NSTimeInterval frameAnimationStartedAt;
@property (nonatomic) NSRect frameAnimationStart;
@property (nonatomic) NSRect frameAnimationOvershoot;
@property (nonatomic) NSRect frameAnimationTarget;
@property (nonatomic, strong) NSScreen *frameAnimationScreen;

@end

@implementation TLNotchOverlayController

- (instancetype)initWithPalette:(TLThemePalette *)palette target:(id)target action:(SEL)action {
  self = [super init];
  if (self) {
    _palette = palette;
    _target = target;
    _action = action;
    _lastMouseLocation = NSZeroPoint;
    _overlayPresentation = TLNotchOverlayPresentationCompact;
    _fileDragShakeRecognizer = [[TLShakeRecognizer alloc] initWithConfiguration:TLDefaultShakeRecognizerConfiguration()];
    _dropPromptTimer = [[TLDropPromptTimer alloc] init];
    _activeFileDragPasteboardChangeCount = -1;
    _idleDragPasteboardChangeCount = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag].changeCount;
  }
  return self;
}

- (void)dealloc {
  [self stopTracking];
}

- (void)setFileDropHandler:(TLNotchOverlayFileDropHandler)fileDropHandler {
  _fileDropHandler = [fileDropHandler copy];
  self.overlayView.fileDropHandler = _fileDropHandler;
}

- (void)setOverlayPresentation:(TLNotchOverlayPresentation)overlayPresentation {
  _overlayPresentation = overlayPresentation;
  self.overlayView.dropPromptVisible = overlayPresentation == TLNotchOverlayPresentationDropPrompt;
  if (overlayPresentation != TLNotchOverlayPresentationDropPrompt) {
    self.overlayView.dropPromptProgress = 0.0;
    self.overlayView.dropPromptFileCount = 0;
  }
  [self.overlayView setNeedsDisplay:YES];
}

- (void)startTracking {
  if (self.trackingTimer) {
    return;
  }

  __weak typeof(self) weakSelf = self;
  self.trackingTimer = [NSTimer timerWithTimeInterval:self.palette.notchOverlayTrackingInterval
                                             repeats:YES
                                               block:^(NSTimer *timer) {
    [weakSelf updateForCurrentMouseLocation];
  }];
  [NSRunLoop.mainRunLoop addTimer:self.trackingTimer forMode:NSRunLoopCommonModes];

  NSEventMask mouseMotionMask = NSEventMaskMouseMoved |
    NSEventMaskLeftMouseDragged |
    NSEventMaskRightMouseDragged |
    NSEventMaskOtherMouseDragged;
  self.localEventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mouseMotionMask
                                                                 handler:^NSEvent *(NSEvent *event) {
    [weakSelf updateForCurrentMouseLocation];
    return event;
  }];
  self.globalEventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mouseMotionMask
                                                                   handler:^(NSEvent *event) {
    [weakSelf updateForCurrentMouseLocation];
  }];

  [NSNotificationCenter.defaultCenter addObserver:self
                                         selector:@selector(screenParametersDidChange:)
                                             name:NSApplicationDidChangeScreenParametersNotification
                                           object:nil];
  [self updateForCurrentMouseLocation];
}

- (void)stopTracking {
  [self.trackingTimer invalidate];
  self.trackingTimer = nil;
  if (self.localEventMonitor) {
    [NSEvent removeMonitor:self.localEventMonitor];
    self.localEventMonitor = nil;
  }
  if (self.globalEventMonitor) {
    [NSEvent removeMonitor:self.globalEventMonitor];
    self.globalEventMonitor = nil;
  }
  [self hideOverlayImmediately];
  [NSNotificationCenter.defaultCenter removeObserver:self
                                                name:NSApplicationDidChangeScreenParametersNotification
                                              object:nil];
}

- (void)updatePalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.overlayView.palette = palette;
  self.overlayWindow.backgroundColor = palette.notchOverlayWindowBackground;
  [self.overlayView setNeedsDisplay:YES];
  [self updateForCurrentMouseLocation];
}

- (void)screenParametersDidChange:(NSNotification *)notification {
  [self updateForCurrentMouseLocation];
}

- (void)updateForCurrentMouseLocation {
  self.lastMouseLocation = NSEvent.mouseLocation;
  self.fileDragActive = [self isFileDragInProgress];
  NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;

  NSScreen *screen = [self screenContainingPoint:self.lastMouseLocation];
  NSRect notchRect = screen ? [self notchRectForScreen:screen] : NSZeroRect;
  BOOL virtualNotch = NO;

  if (!screen) {
    [self hideOverlayImmediately];
    return;
  }

  if (self.fileDragActive) {
    [self updateDropPromptTimerAtTimestamp:now];
    if (!self.dropPromptTimer.armed &&
        [self shouldArmDropPromptForFileDragAtPoint:self.lastMouseLocation timestamp:now]) {
      [self armDropPromptAtTimestamp:now];
    }
  } else {
    [self resetFileDragShakeTracking];
  }

  if (self.fileDragActive && self.dropPromptTimer.armed) {
    BOOL dropPromptVirtualNotch = NO;
    if (NSIsEmptyRect(notchRect)) {
      notchRect = [self virtualNotchRectForScreen:screen];
      dropPromptVirtualNotch = YES;
    }
    [self showOverlayForNotchRect:notchRect
                            screen:screen
                      presentation:TLNotchOverlayPresentationDropPrompt
                          progress:[self dropPromptProgressAtTimestamp:now]
                      virtualNotch:dropPromptVirtualNotch];
    return;
  }

  if (NSIsEmptyRect(notchRect)) {
    notchRect = [self virtualNotchRectForScreen:screen];
    virtualNotch = YES;
  }

  NSRect proximityRect = NSInsetRect(notchRect,
                                    -self.palette.notchOverlayProximity,
                                    -self.palette.notchOverlayProximity);
  if (NSPointInRect(self.lastMouseLocation, proximityRect)) {
    [self showOverlayForNotchRect:notchRect
                            screen:screen
                      presentation:TLNotchOverlayPresentationCompact
                          progress:0.0
                      virtualNotch:virtualNotch];
  } else {
    [self hideOverlayForNotchRect:notchRect screen:screen virtualNotch:virtualNotch];
  }
}

- (BOOL)isFileDragInProgress {
  NSPasteboard *dragPasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
  NSInteger changeCount = dragPasteboard.changeCount;
  BOOL leftMouseButtonDown = (NSEvent.pressedMouseButtons & 1) != 0;

  if (!leftMouseButtonDown) {
    self.idleDragPasteboardChangeCount = changeCount;
    self.activeFileDragPasteboardChangeCount = -1;
    self.activeFileDragCount = 0;
    [self resetFileDragShakeTracking];
    return NO;
  }

  if (self.activeFileDragPasteboardChangeCount == changeCount) {
    return YES;
  }
  if (changeCount == self.idleDragPasteboardChangeCount) {
    return NO;
  }

  if (!TLPasteboardContainsFileDrag(dragPasteboard)) {
    return NO;
  }

  self.activeFileDragPasteboardChangeCount = changeCount;
  self.activeFileDragCount = TLFileCountFromPasteboard(dragPasteboard);
  return YES;
}

- (BOOL)shouldArmDropPromptForFileDragAtPoint:(NSPoint)point timestamp:(NSTimeInterval)timestamp {
  return [self.fileDragShakeRecognizer recordPoint:point timestamp:timestamp];
}

- (void)resetFileDragShakeTracking {
  [self.dropPromptTimer reset];
  [self.fileDragShakeRecognizer reset];
}

- (void)armDropPromptAtTimestamp:(NSTimeInterval)timestamp {
  [self.dropPromptTimer armAtTimestamp:timestamp duration:self.palette.notchOverlayDropPromptDuration];
}

- (void)updateDropPromptTimerAtTimestamp:(NSTimeInterval)timestamp {
  if (!self.dropPromptTimer.armed) {
    return;
  }

  if (![self.dropPromptTimer updateAtTimestamp:timestamp hovered:[self isMouseHoveringDropPrompt]]) {
    [self resetFileDragShakeTracking];
  }
}

- (BOOL)isMouseHoveringDropPrompt {
  NSRect hoverFrame = self.appearanceAnimationInFlight ? self.frameAnimationTarget : self.overlayWindow.frame;
  return self.overlayPresentation == TLNotchOverlayPresentationDropPrompt &&
    self.overlayWindow.isVisible &&
    NSPointInRect(self.lastMouseLocation, hoverFrame);
}

- (CGFloat)dropPromptProgressAtTimestamp:(NSTimeInterval)timestamp {
  return [self.dropPromptTimer progressAtTimestamp:timestamp duration:self.palette.notchOverlayDropPromptDuration];
}

- (NSScreen *)screenContainingPoint:(NSPoint)point {
  for (NSScreen *screen in NSScreen.screens) {
    if (NSPointInRect(point, screen.frame)) {
      return screen;
    }
  }

  return NSScreen.mainScreen;
}

- (NSRect)notchRectForScreen:(NSScreen *)screen {
  TLNotchScreenMetrics metrics = TLNotchScreenMetricsMake(screen.frame,
                                                          screen.auxiliaryTopLeftArea,
                                                          screen.auxiliaryTopRightArea,
                                                          screen.safeAreaInsets.top,
                                                          self.palette.notchOverlayFallbackNotchWidth,
                                                          self.palette.notchOverlayMinimumHeight);
  return TLDetectedNotchRectForScreenMetrics(metrics);
}

- (NSRect)virtualNotchRectForScreen:(NSScreen *)screen {
  TLNotchScreenMetrics metrics = TLNotchScreenMetricsMake(screen.frame,
                                                          screen.auxiliaryTopLeftArea,
                                                          screen.auxiliaryTopRightArea,
                                                          screen.safeAreaInsets.top,
                                                          self.palette.notchOverlayFallbackNotchWidth,
                                                          self.palette.notchOverlayMinimumHeight);
  return TLVirtualNotchRectForScreenMetrics(metrics);
}

- (void)showOverlayForNotchRect:(NSRect)notchRect
                         screen:(NSScreen *)screen
                   presentation:(TLNotchOverlayPresentation)presentation
                       progress:(CGFloat)progress
                    virtualNotch:(BOOL)virtualNotch {
  [self ensureOverlayWindow];
  [self setOverlayPresentation:presentation];
  self.overlayView.dropPromptProgress = presentation == TLNotchOverlayPresentationDropPrompt ? progress : 0.0;
  self.overlayView.dropPromptFileCount = presentation == TLNotchOverlayPresentationDropPrompt ? self.activeFileDragCount : 0;
  self.overlayView.fileDragHovered = self.fileDragActive && [self isMouseHoveringDropPrompt];
  [self.overlayView setNeedsDisplay:YES];

  NSRect frame = [self backingAlignedTopPinnedFrame:[self overlayFrameForNotchRect:notchRect
                                                                            screen:screen
                                                                      presentation:presentation
                                                                      virtualNotch:virtualNotch]
                                             screen:screen];
  if (self.disappearanceAnimationInFlight) {
    self.disappearanceAnimationInFlight = NO;
    self.overlayAnimationGeneration += 1;
    [self animateOverlayToFrame:frame screen:screen];
    return;
  }

  if (!self.overlayWindow.isVisible) {
    NSRect startingFrame = [self backingAlignedTopPinnedFrame:[self collapsedOverlayFrameForNotchRect:notchRect
                                                                                                    screen:screen
                                                                                              virtualNotch:virtualNotch]
                                                       screen:screen];
    [self.overlayWindow setFrame:startingFrame display:YES];
    [self.overlayWindow orderFrontRegardless];
    [self animateOverlayToFrame:frame screen:screen];
    return;
  }

  if (self.appearanceAnimationInFlight) {
    if (!NSEqualRects(self.frameAnimationTarget, frame)) {
      [self animateOverlayToFrame:frame screen:screen];
    }
    return;
  }

  if (!NSEqualRects(self.overlayWindow.frame, frame)) {
    [self.overlayWindow setFrame:frame display:YES];
  }
}

- (NSRect)overlayFrameForNotchRect:(NSRect)notchRect
                            screen:(NSScreen *)screen
                      presentation:(TLNotchOverlayPresentation)presentation
                       virtualNotch:(BOOL)virtualNotch {
  BOOL dropPrompt = presentation == TLNotchOverlayPresentationDropPrompt;
  BOOL compactVirtualNotch = !dropPrompt && virtualNotch;
  CGFloat horizontalPadding = dropPrompt ? self.palette.notchOverlayDropHorizontalPadding :
    (compactVirtualNotch ? 0.0 : self.palette.notchOverlayHorizontalPadding);
  CGFloat verticalPadding = dropPrompt ? self.palette.notchOverlayDropVerticalPadding :
    (compactVirtualNotch ? 0.0 : self.palette.notchOverlayVerticalPadding);
  CGFloat minimumWidth = dropPrompt ? self.palette.notchOverlayDropMinimumWidth :
    (compactVirtualNotch ? NSWidth(notchRect) : self.palette.notchOverlayMinimumWidth);
  CGFloat minimumHeight = dropPrompt ? self.palette.notchOverlayDropMinimumHeight :
    (compactVirtualNotch ? NSHeight(notchRect) : self.palette.notchOverlayMinimumHeight);
  CGFloat flareOutset = compactVirtualNotch ? 0.0 : self.palette.notchOverlayTopFlareOutset;
  CGFloat bodyWidth = MAX(NSWidth(notchRect) + (horizontalPadding * 2.0), minimumWidth);
  CGFloat width = bodyWidth + (flareOutset * 2.0);
  CGFloat height = MAX(NSHeight(notchRect) + verticalPadding, minimumHeight);
  CGFloat horizontalMargin = 12.0;
  width = MIN(width, MAX(120.0, NSWidth(screen.frame) - (horizontalMargin * 2.0)));
  CGFloat x = MIN(MAX(NSMidX(notchRect) - (width * 0.5), NSMinX(screen.frame) + horizontalMargin),
                  NSMaxX(screen.frame) - width - horizontalMargin);
  CGFloat y = NSMaxY(screen.frame) - height - self.palette.notchOverlayTopOffset;

  return NSMakeRect(x, y, width, height);
}

- (NSRect)collapsedOverlayFrameForNotchRect:(NSRect)notchRect
                                     screen:(NSScreen *)screen
                               virtualNotch:(BOOL)virtualNotch {
  CGFloat width = virtualNotch ? 1.0 : NSWidth(notchRect);
  CGFloat height = virtualNotch ? 1.0 : NSHeight(notchRect);
  CGFloat x = NSMidX(notchRect) - (width * 0.5);
  CGFloat y = NSMaxY(screen.frame) - height - self.palette.notchOverlayTopOffset;

  return NSMakeRect(x, y, width, height);
}

- (NSRect)backingAlignedTopPinnedFrame:(NSRect)frame screen:(NSScreen *)screen {
  NSRect alignedFrame = [screen backingAlignedRect:frame options:NSAlignAllEdgesNearest];
  alignedFrame.origin.y = NSMaxY(screen.frame) - NSHeight(alignedFrame) - self.palette.notchOverlayTopOffset;

  return alignedFrame;
}

- (NSRect)topPinnedFrameByScalingFrame:(NSRect)frame scale:(CGFloat)scale screen:(NSScreen *)screen {
  CGFloat width = NSWidth(frame) * scale;
  CGFloat height = NSHeight(frame) * scale;
  CGFloat x = NSMidX(frame) - (width * 0.5);
  CGFloat y = NSMaxY(screen.frame) - height - self.palette.notchOverlayTopOffset;

  return [self backingAlignedTopPinnedFrame:NSMakeRect(x, y, width, height) screen:screen];
}

- (void)animateOverlayToFrame:(NSRect)targetFrame screen:(NSScreen *)screen {
  [self.frameAnimationTimer invalidate];
  self.appearanceAnimationInFlight = YES;
  self.disappearanceAnimationInFlight = NO;
  self.overlayAnimationGeneration += 1;
  self.frameAnimationStart = self.overlayWindow.frame;
  self.frameAnimationTarget = targetFrame;
  self.frameAnimationScreen = screen;
  self.frameAnimationOvershoot = [self topPinnedFrameByScalingFrame:targetFrame
                                                       scale:self.palette.notchOverlayAnimationOvershootScale
                                                      screen:screen];
  [self startFrameAnimationTimer];
}

- (void)animateOverlayOutToFrame:(NSRect)standardFrame {
  [self.frameAnimationTimer invalidate];
  self.appearanceAnimationInFlight = NO;
  self.disappearanceAnimationInFlight = YES;
  self.overlayAnimationGeneration += 1;
  self.frameAnimationStart = self.overlayWindow.frame;
  self.frameAnimationTarget = standardFrame;
  self.frameAnimationScreen = self.overlayWindow.screen ?: NSScreen.mainScreen;
  [self startFrameAnimationTimer];
}

- (void)startFrameAnimationTimer {
  self.frameAnimationStartedAt = CACurrentMediaTime();
  __weak typeof(self) weakSelf = self;
  self.frameAnimationTimer = [NSTimer timerWithTimeInterval:self.palette.notchOverlayTrackingInterval
    repeats:YES block:^(NSTimer *timer) {
    [weakSelf updateFrameAnimationAtTimestamp:CACurrentMediaTime()];
  }];
  [NSRunLoop.mainRunLoop addTimer:self.frameAnimationTimer forMode:NSRunLoopCommonModes];
}

- (void)updateFrameAnimationAtTimestamp:(NSTimeInterval)timestamp {
  if (!self.appearanceAnimationInFlight && !self.disappearanceAnimationInFlight) {
    return;
  }
  BOOL closing = self.disappearanceAnimationInFlight;
  NSTimeInterval elapsed = MAX(0.0, timestamp - self.frameAnimationStartedAt);
  NSTimeInterval expandDuration = self.palette.notchOverlayAnimationExpandDuration;
  NSTimeInterval duration = closing ? self.palette.notchOverlayAnimationHideDuration
    : expandDuration + self.palette.notchOverlayAnimationSettleDuration;
  NSRect start = self.frameAnimationStart;
  NSRect end = self.frameAnimationTarget;
  CGFloat progress;
  if (closing) {
    progress = MIN(1.0, elapsed / duration);
    progress = progress * progress * progress;
  } else if (elapsed < expandDuration) {
    end = self.frameAnimationOvershoot;
    progress = 1.0 - pow(1.0 - elapsed / expandDuration, 3.0);
  } else {
    start = self.frameAnimationOvershoot;
    progress = MIN(1.0, (elapsed - expandDuration) / self.palette.notchOverlayAnimationSettleDuration);
    progress = progress * progress * (3.0 - 2.0 * progress);
  }
  CGFloat width = NSWidth(start) + (NSWidth(end) - NSWidth(start)) * progress;
  CGFloat height = NSHeight(start) + (NSHeight(end) - NSHeight(start)) * progress;
  CGFloat centerX = NSMidX(start) + (NSMidX(end) - NSMidX(start)) * progress;
  CGFloat top = NSMaxY(start) + (NSMaxY(end) - NSMaxY(start)) * progress;
  NSRect frame = NSMakeRect(centerX - width * 0.5, top - height, width, height);
  [self.overlayWindow setFrame:[self backingAlignedTopPinnedFrame:frame screen:self.frameAnimationScreen] display:YES];
  if (elapsed >= duration) {
    [self.frameAnimationTimer invalidate];
    self.frameAnimationTimer = nil;
    self.appearanceAnimationInFlight = NO;
    self.disappearanceAnimationInFlight = NO;
    [self.overlayWindow setFrame:self.frameAnimationTarget display:YES];
    if (closing) {
      [self.overlayWindow orderOut:self];
    }
  }
}

- (void)ensureOverlayWindow {
  if (self.overlayWindow) {
    return;
  }

  NSRect frame = NSMakeRect(0.0, 0.0, self.palette.notchOverlayMinimumWidth, self.palette.notchOverlayMinimumHeight);
  self.overlayWindow = [[NSPanel alloc] initWithContentRect:frame
                                                  styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
  self.overlayWindow.acceptsMouseMovedEvents = YES;
  self.overlayWindow.backgroundColor = self.palette.notchOverlayWindowBackground;
  self.overlayWindow.canHide = NO;
  self.overlayWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
    NSWindowCollectionBehaviorFullScreenAuxiliary |
    NSWindowCollectionBehaviorStationary |
    NSWindowCollectionBehaviorIgnoresCycle;
  self.overlayWindow.hasShadow = NO;
  self.overlayWindow.hidesOnDeactivate = NO;
  self.overlayWindow.ignoresMouseEvents = NO;
  self.overlayWindow.level = NSStatusWindowLevel + 1;
  self.overlayWindow.opaque = NO;
  self.overlayWindow.releasedWhenClosed = NO;

  self.overlayView = [[TLNotchOverlayView alloc] initWithFrame:frame];
  self.overlayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.overlayView.palette = self.palette;
  // The tracking loop uses stable bounds; drag callbacks can fire again as the panel resizes.
  self.overlayView.tracksFileDragHoverExternally = YES;
  self.overlayView.target = self.target;
  self.overlayView.action = self.action;
  self.overlayView.fileDropHandler = self.fileDropHandler;
  self.overlayView.dropPromptVisible = self.overlayPresentation == TLNotchOverlayPresentationDropPrompt;
  self.overlayWindow.contentView = self.overlayView;
}

- (void)hideOverlayForNotchRect:(NSRect)notchRect screen:(NSScreen *)screen virtualNotch:(BOOL)virtualNotch {
  if (!self.overlayWindow.isVisible || self.disappearanceAnimationInFlight) {
    return;
  }

  self.appearanceAnimationInFlight = NO;
  [self setOverlayPresentation:TLNotchOverlayPresentationCompact];
  NSRect standardFrame = [self backingAlignedTopPinnedFrame:[self collapsedOverlayFrameForNotchRect:notchRect
                                                                                                 screen:screen
                                                                                           virtualNotch:virtualNotch]
                                                     screen:screen];
  [self animateOverlayOutToFrame:standardFrame];
}

- (void)hideOverlayImmediately {
  [self.frameAnimationTimer invalidate];
  self.frameAnimationTimer = nil;
  self.appearanceAnimationInFlight = NO;
  self.disappearanceAnimationInFlight = NO;
  self.overlayAnimationGeneration += 1;
  [self setOverlayPresentation:TLNotchOverlayPresentationCompact];
  [self.overlayWindow orderOut:self];
}

@end
