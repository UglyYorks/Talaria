#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "NotchOverlayController.h"

@interface TLNotchOverlayView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL dropPromptVisible;
@property (nonatomic) CGFloat dropPromptProgress;
@property (nonatomic) NSUInteger dropPromptFileCount;
@property (nonatomic) BOOL fileDragHovered;
@property (nonatomic) BOOL tracksFileDragHoverExternally;
@property (nonatomic, strong) NSImageView *dropIconView;
@property (nonatomic, strong) CAGradientLayer *dropGlareLayer;
@property (nonatomic, strong) CALayer *dropGlareContainer;
@property (nonatomic, copy) TLNotchOverlayFileDropHandler fileDropHandler;
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender;
- (void)draggingExited:(id<NSDraggingInfo>)sender;
- (void)draggingEnded:(id<NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender;
- (void)drawDropPromptInRect:(NSRect)rect palette:(TLThemePalette *)palette;
- (void)drawDropPromptProgressInRect:(NSRect)rect palette:(TLThemePalette *)palette;
@end

@interface TLTestNotchView : TLNotchOverlayView
@property (nonatomic) NSUInteger labelDrawCount;
@property (nonatomic) NSUInteger progressDrawCount;
@end

@implementation TLTestNotchView
- (void)drawDropPromptInRect:(NSRect)rect palette:(TLThemePalette *)palette {
  self.labelDrawCount += 1;
  [super drawDropPromptInRect:rect palette:palette];
}
- (void)drawDropPromptProgressInRect:(NSRect)rect palette:(TLThemePalette *)palette {
  self.progressDrawCount += 1;
  [super drawDropPromptProgressInRect:rect palette:palette];
}
@end

@interface TLTestDragInfo : NSObject
@property (nonatomic, strong) NSPasteboard *draggingPasteboard;
@end
@implementation TLTestDragInfo
@end

@interface TLNotchOverlayController (Testing)
- (void)showOverlayForNotchRect:(NSRect)rect screen:(NSScreen *)screen
  presentation:(NSUInteger)presentation progress:(CGFloat)progress virtualNotch:(BOOL)virtualNotch;
- (void)animateOverlayOutToFrame:(NSRect)frame;
- (void)updateFrameAnimationAtTimestamp:(NSTimeInterval)timestamp;
@end

@interface TLTestNotchPanel : NSPanel
@property (nonatomic) BOOL testVisible;
@end
@implementation TLTestNotchPanel
- (BOOL)isVisible { return self.testVisible; }
- (void)orderFrontRegardless { self.testVisible = YES; }
- (void)orderOut:(id)sender { self.testVisible = NO; }
- (void)setFrame:(NSRect)frame display:(BOOL)display { [super setFrame:frame display:NO]; }
@end

static void Check(BOOL condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAILED: %@", message);
    exit(1);
  }
}

static NSBitmapImageRep *Render(TLTestNotchView *view, NSString *snapshot) {
  view.labelDrawCount = 0;
  view.progressDrawCount = 0;
  [view layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  if (snapshot) {
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:snapshot atomically:YES];
  }
  return bitmap;
}

static CGFloat Brightness(NSBitmapImageRep *bitmap, NSInteger x, NSInteger y) {
  NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
  return MAX(pixel.redComponent, MAX(pixel.greenComponent, pixel.blueComponent));
}

static BOOL HasDropTargetBorder(NSBitmapImageRep *bitmap, TLThemePalette *palette) {
  CGFloat scale = bitmap.pixelsHigh / 96.0;
  NSInteger y = (NSInteger)(palette.notchOverlayDropTargetInset * scale);
  for (NSInteger x = bitmap.pixelsWide / 4; x < bitmap.pixelsWide * 3 / 4; x++) {
    if (Brightness(bitmap, x, y) > 0.02) {
      return YES;
    }
  }
  return NO;
}

static CGFloat HighlightCenter(NSBitmapImageRep *image, NSBitmapImageRep *baseline, TLThemePalette *palette) {
  NSInteger y = (NSInteger)(palette.notchOverlayDropTargetInset * image.pixelsHigh / 96.0);
  CGFloat weight = 0.0;
  CGFloat weightedX = 0.0;
  for (NSInteger x = 0; x < image.pixelsWide; x++) {
    CGFloat difference = MAX(0.0, Brightness(image, x, y) - Brightness(baseline, x, y));
    weight += difference;
    weightedX += difference * x;
  }
  Check(weight > 0.1, @"glare visibly lights the dashed border");
  return weightedX / weight;
}

static void TestOpeningDoesNotRestart(void) {
  TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  TLNotchOverlayController *controller = [[TLNotchOverlayController alloc] initWithPalette:palette target:NSApp action:@selector(hide:)];
  TLTestNotchPanel *panel = [[TLTestNotchPanel alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
    styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  TLTestNotchView *view = [[TLTestNotchView alloc] initWithFrame:panel.contentView.bounds];
  view.palette = palette;
  panel.contentView = view;
  [controller setValue:panel forKey:@"overlayWindow"];
  [controller setValue:view forKey:@"overlayView"];
  NSScreen *screen = NSScreen.mainScreen;
  NSRect notch = NSMakeRect(NSMidX(screen.frame) - 100, NSMaxY(screen.frame) - 20, 200, 20);
  [controller showOverlayForNotchRect:notch screen:screen presentation:1 progress:0 virtualNotch:YES];
  NSNumber *generation = [controller valueForKey:@"overlayAnimationGeneration"];
  NSTimeInterval startedAt = [[controller valueForKey:@"frameAnimationStartedAt"] doubleValue];
  [controller updateFrameAnimationAtTimestamp:startedAt + 0.06];
  NSRect intermediate = panel.frame;
  for (NSUInteger index = 0; index < 10; index++) {
    [controller showOverlayForNotchRect:notch screen:screen presentation:1 progress:0.01 virtualNotch:YES];
    Check(NSEqualRects(panel.frame, intermediate), @"tracking updates do not snap the opening frame");
    Check([[controller valueForKey:@"overlayAnimationGeneration"] isEqual:generation], @"opening is started only once");
  }
  [controller updateFrameAnimationAtTimestamp:startedAt + 1];
  Check(![[controller valueForKey:@"appearanceAnimationInFlight"] boolValue], @"opening finishes");
  NSRect target = [[controller valueForKey:@"frameAnimationTarget"] rectValue];
  Check(NSEqualRects(panel.frame, target), @"opening settles at its target");
  [controller animateOverlayOutToFrame:NSMakeRect(NSMidX(notch), NSMaxY(notch) - 1, 1, 1)];
  startedAt = [[controller valueForKey:@"frameAnimationStartedAt"] doubleValue];
  [controller updateFrameAnimationAtTimestamp:startedAt + 0.05];
  [controller showOverlayForNotchRect:notch screen:screen presentation:1 progress:0.02 virtualNotch:YES];
  startedAt = [[controller valueForKey:@"frameAnimationStartedAt"] doubleValue];
  [controller updateFrameAnimationAtTimestamp:startedAt + 1];
  Check(panel.isVisible && NSEqualRects(panel.frame, target), @"reopening replaces the old closing animation");
  [controller stopTracking];
  Check([controller valueForKey:@"frameAnimationTimer"] == nil, @"stopping removes frame animation timer");
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TLTestNotchView *view = [[TLTestNotchView alloc] initWithFrame:NSMakeRect(0, 0, 442, 96)];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:view.bounds
      styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.contentView = view;
    TLTestDragInfo *drag = [[TLTestDragInfo alloc] init];
    drag.draggingPasteboard = [NSPasteboard pasteboardWithUniqueName];
    NSURL *fileURL = [NSURL fileURLWithPath:@"/tmp/notch-test.txt"];
    [drag.draggingPasteboard writeObjects:@[fileURL]];
    id<NSDraggingInfo> sender = (id<NSDraggingInfo>)drag;

    for (NSNumber *theme in @[@(TLThemePreferenceDark), @(TLThemePreferenceLight)]) {
      view.palette = [TLThemePalette paletteForPreference:theme.integerValue];
      Check(view.palette.notchOverlayDropTargetBorder.alphaComponent < 1.0,
        @"drop border is semi-transparent in each theme");
      view.dropPromptVisible = NO;
      [view draggingEntered:sender];
      Check(!view.fileDragHovered && view.dropIconView.hidden, @"file drag alone does not reveal prompt");

      view.dropPromptVisible = YES;
      view.dropPromptFileCount = 1;
      view.dropPromptProgress = 0.5;
      NSBitmapImageRep *prompt = Render(view, @"/tmp/talaria-notch-prompt.png");
      Check(HasDropTargetBorder(prompt, view.palette), @"rectangle appears before hovering");
      Check(Brightness(prompt, prompt.pixelsWide / 4, prompt.pixelsHigh - 1) > 0.1,
        @"progress reaches the very bottom edge");
      Check(view.labelDrawCount > 0 && view.progressDrawCount > 0, @"normal prompt draws text and progress");
      Check([view draggingEntered:sender] == NSDragOperationCopy, @"file hover accepts copy");
      Check(view.fileDragHovered && !view.dropIconView.hidden, @"hover shows drop icon");
      CAAnimationGroup *animation = (CAAnimationGroup *)[view.dropIconView.layer animationForKey:@"dropIconEntrance"];
      Check(animation && fabs(animation.duration - 0.2) < 0.001, @"entrance lasts 200ms");
      Check(animation.animations.count == 2, @"entrance fades and slides");
      CAAnimationGroup *glare = (CAAnimationGroup *)[view.dropGlareLayer animationForKey:@"dropBorderGlare"];
      Check(glare && glare.repeatCount == 0 && !glare.autoreverses, @"glare plays only once on entry");
      Check(fabs(glare.duration - view.palette.notchOverlayDropGlareDuration) < 0.001,
        @"glare uses its theme duration");
      Check([(CAShapeLayer *)view.dropGlareContainer.mask lineDashPattern].count == 2,
        @"glare is masked to the dashed border");
      CABasicAnimation *sweep = (CABasicAnimation *)glare.animations.firstObject;
      Check([sweep.keyPath isEqualToString:@"position.x"] && [sweep.fromValue doubleValue] < 0 &&
        [sweep.toValue doubleValue] > NSWidth(view.bounds), @"glare physically crosses the entire border");
      Check(view.dropGlareLayer.opacity == 0.0, @"glare is invisible after its animation finishes");
      [view.dropIconView.layer removeAllAnimations];
      [view.dropGlareLayer removeAllAnimations];
      [view draggingUpdated:sender];
      Check(![view.dropIconView.layer animationForKey:@"dropIconEntrance"], @"drag updates do not restart entrance");
      Check(![view.dropGlareLayer animationForKey:@"dropBorderGlare"], @"drag updates do not restart glare");
      NSBitmapImageRep *hover = Render(view, @"/tmp/talaria-notch-hover.png");
      Check(HasDropTargetBorder(hover, view.palette), @"rectangle remains while hovering");
      Check(Brightness(hover, hover.pixelsWide / 4, hover.pixelsHigh - 1) < 0.01,
        @"hover removes bottom-edge progress");
      Check(view.labelDrawCount == 0 && view.progressDrawCount == 0, @"hover hides text and progress");
      Check(view.dropPromptProgress == 0.5, @"hover preserves progress");
      CGFloat previousCenter = -1.0;
      for (NSNumber *fraction in @[@0.2, @0.5, @0.8]) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        view.dropGlareLayer.position = CGPointMake(NSWidth(view.bounds) * fraction.doubleValue, NSMidY(view.bounds));
        view.dropGlareLayer.opacity = view.palette.notchOverlayDropGlareOpacity;
        [CATransaction commit];
        NSBitmapImageRep *frame = Render(view, [NSString stringWithFormat:@"/tmp/talaria-notch-glare-%@.png", fraction]);
        CGFloat center = HighlightCenter(frame, hover, view.palette);
        Check(center > previousCenter, @"rendered glare travels left to right");
        Check(fabs(center / frame.pixelsWide - fraction.doubleValue) < 0.08, @"rendered glare reaches each side");
        previousCenter = center;
      }
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      view.dropGlareLayer.opacity = 0.0;
      [CATransaction commit];
      [view draggingExited:sender];
      Check(!view.fileDragHovered && view.dropIconView.hidden, @"exit hides icon");
      Render(view, nil);
      Check(view.labelDrawCount > 0 && view.progressDrawCount > 0, @"exit restores prompt");
      [view draggingEntered:sender];
      Check([view.dropIconView.layer animationForKey:@"dropIconEntrance"] != nil, @"reentry animates again");
      Check([view.dropGlareLayer animationForKey:@"dropBorderGlare"] != nil, @"reentry plays glare again");
      [view draggingEnded:sender];
      Check(![view.dropGlareLayer animationForKey:@"dropBorderGlare"], @"cancellation stops glare");
      Check(!view.fileDragHovered, @"cancellation clears hover");
      [view draggingEntered:sender];
      view.dropPromptVisible = NO;
      Check(view.dropIconView.hidden && !view.fileDragHovered, @"compact presentation clears hover");
    }

    view.dropPromptVisible = YES;
    view.tracksFileDragHoverExternally = YES;
    view.fileDragHovered = YES;
    [view.dropGlareLayer removeAllAnimations];
    [view.dropIconView.layer removeAllAnimations];
    [view draggingExited:sender];
    [view draggingEntered:sender];
    [view draggingUpdated:sender];
    Check(view.fileDragHovered, @"native callback churn does not clear externally tracked hover");
    Check(![view.dropGlareLayer animationForKey:@"dropBorderGlare"], @"native reentry does not replay completed glare");
    Check(![view.dropIconView.layer animationForKey:@"dropIconEntrance"], @"native reentry does not replay icon entrance");
    view.fileDragHovered = NO;
    [view draggingEntered:sender];
    Check(!view.fileDragHovered, @"native entry cannot override the tracking loop");
    view.fileDragHovered = YES;
    Check([view.dropGlareLayer animationForKey:@"dropBorderGlare"] != nil, @"actual tracked reentry still plays glare");
    [view draggingExited:sender];
    Check([view.dropGlareLayer animationForKey:@"dropBorderGlare"] != nil, @"native exit cannot interrupt active glare");
    [view draggingEntered:sender];
    __block NSArray<NSURL *> *received;
    view.fileDropHandler = ^(NSArray<NSURL *> *files) { received = files; };
    Check([view performDragOperation:sender] && [received isEqualToArray:@[fileURL]], @"drop handler still receives files");
    Check(!view.fileDragHovered, @"successful drop clears hover");
    [drag.draggingPasteboard clearContents];
    [drag.draggingPasteboard setString:@"Not a file" forType:NSPasteboardTypeString];
    Check([view draggingEntered:sender] == NSDragOperationNone && !view.fileDragHovered, @"text drag is rejected");
    [drag.draggingPasteboard releaseGlobally];
    TestOpeningDoesNotRestart();
    NSLog(@"NotchOverlayViewTests passed");
  }
  return 0;
}
