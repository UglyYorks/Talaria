#import "TLASCIIPlanetScreensaverView.h"
#import <math.h>

static const NSTimeInterval TLASCIIPlanetFrameInterval = 1.0 / 8.0;
static const CGFloat TLASCIIPlanetFontSize = 12.0;

static NSUInteger TLASCIIPlanetHash(NSUInteger column, NSUInteger row) {
  NSUInteger value = column * 0x45d9f3bU + row * 0x119de1f3U + 0x27d4eb2dU;
  value = (value ^ (value >> 16)) * 0x45d9f3bU;
  return value ^ (value >> 16);
}

@interface TLASCIIPlanetScreensaverView ()

@property (nonatomic, strong) NSColor *screensaverBackgroundColor;
@property (nonatomic, strong) NSColor *artColor;
@property (nonatomic, strong) NSFont *artFont;
@property (nonatomic, strong, nullable) NSTimer *animationTimer;
@property (nonatomic) NSUInteger frameIndex;

@end


@implementation TLASCIIPlanetScreensaverView

- (instancetype)initWithFrame:(NSRect)frame
              backgroundColor:(NSColor *)backgroundColor
                     artColor:(NSColor *)artColor {
  self = [super initWithFrame:frame];
  if (self) {
    _screensaverBackgroundColor = [backgroundColor colorWithAlphaComponent:1.0];
    _artColor = artColor;
    _artFont = [NSFont monospacedSystemFontOfSize:TLASCIIPlanetFontSize weight:NSFontWeightRegular];
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  return self;
}

- (BOOL)isOpaque {
  return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (self.window) {
    [self startAnimating];
  } else {
    [self stopAnimating];
  }
}

- (void)dealloc {
  [self stopAnimating];
}

- (void)updateBackgroundColor:(NSColor *)backgroundColor artColor:(NSColor *)artColor {
  self.screensaverBackgroundColor = [backgroundColor colorWithAlphaComponent:1.0];
  self.artColor = artColor;
  [self setNeedsDisplay:YES];
}

- (void)startAnimating {
  if (self.animationTimer) {
    return;
  }

  __weak typeof(self) weakSelf = self;
  self.animationTimer = [NSTimer timerWithTimeInterval:TLASCIIPlanetFrameInterval repeats:YES block:^(NSTimer *timer) {
    weakSelf.frameIndex += 1;
    [weakSelf setNeedsDisplay:YES];
  }];
  [[NSRunLoop mainRunLoop] addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
}

- (void)stopAnimating {
  [self.animationTimer invalidate];
  self.animationTimer = nil;
}

- (void)mouseDown:(NSEvent *)event {
  dispatch_block_t dismissHandler = self.dismissHandler;
  if (dismissHandler) {
    dismissHandler();
  }
}

- (NSString *)sceneWithColumns:(NSUInteger)columns rows:(NSUInteger)rows {
  NSUInteger stride = columns + 1;
  NSMutableData *sceneData = [NSMutableData dataWithLength:stride * rows];
  char *characters = sceneData.mutableBytes;
  memset(characters, ' ', sceneData.length);
  for (NSUInteger row = 0; row < rows; row++) {
    characters[(row * stride) + columns] = row + 1 < rows ? '\n' : ' ';
  }

  for (NSUInteger row = 0; row < rows; row++) {
    for (NSUInteger column = 0; column < columns; column++) {
      NSUInteger hash = TLASCIIPlanetHash(column, row);
      if (hash % 101 >= 7) {
        continue;
      }
      NSUInteger twinkle = ((hash / 101) + (self.frameIndex / 4)) % 4;
      characters[(row * stride) + column] = ".+*"[MIN(twinkle, (NSUInteger)2)];
    }
  }

  CGFloat centerColumn = ((CGFloat)columns - 1.0) * 0.5;
  CGFloat centerRow = ((CGFloat)rows - 1.0) * 0.5;
  CGFloat radiusY = MIN((CGFloat)rows * 0.28, 14.0);
  radiusY = MAX(radiusY, 5.0);
  CGFloat radiusX = radiusY * 2.05;
  CGFloat rotation = (CGFloat)self.frameIndex * 0.035;

  for (NSUInteger row = 0; row < rows; row++) {
    CGFloat normalizedY = ((CGFloat)row - centerRow) / radiusY;
    for (NSUInteger column = 0; column < columns; column++) {
      CGFloat normalizedX = ((CGFloat)column - centerColumn) / radiusX;
      CGFloat distanceSquared = normalizedX * normalizedX + normalizedY * normalizedY;
      if (distanceSquared > 1.08) {
        continue;
      }

      NSUInteger index = (row * stride) + column;
      if (distanceSquared >= 0.88) {
        characters[index] = fabs(normalizedY) > 0.78 ? '-' : (normalizedX < 0.0 ? '(' : ')');
        continue;
      }

      CGFloat sphereDepth = sqrt(MAX(0.0, 1.0 - normalizedX * normalizedX - normalizedY * normalizedY));
      CGFloat longitude = atan2(normalizedX, sphereDepth) + rotation;
      CGFloat latitude = asin(MAX(-1.0, MIN(1.0, normalizedY)));
      CGFloat land = sin(longitude * 2.4 + sin(latitude * 3.1)) +
        0.58 * cos(longitude * 4.6 - latitude * 2.0) +
        0.34 * sin(latitude * 6.2 + longitude * 1.3);
      NSUInteger surfacePhase = (column + row * 2 + self.frameIndex / 3) % 5;
      if (land > 0.46) {
        characters[index] = "#%xo+"[surfacePhase];
      } else {
        characters[index] = surfacePhase == 0 ? '~' : (surfacePhase == 3 ? '.' : ' ');
      }
    }
  }

  return [[NSString alloc] initWithData:sceneData encoding:NSASCIIStringEncoding] ?: @"";
}

- (void)drawRect:(NSRect)dirtyRect {
  [self.screensaverBackgroundColor setFill];
  NSRectFill(dirtyRect);

  NSDictionary<NSAttributedStringKey, id> *attributes = @{
    NSFontAttributeName: self.artFont,
    NSForegroundColorAttributeName: self.artColor,
  };
  NSSize cellSize = [@"M" sizeWithAttributes:attributes];
  CGFloat cellWidth = MAX(1.0, ceil(cellSize.width));
  CGFloat lineHeight = MAX(1.0, ceil(cellSize.height));
  NSUInteger columns = MAX((NSUInteger)1, (NSUInteger)floor(NSWidth(self.bounds) / cellWidth));
  NSUInteger rows = MAX((NSUInteger)1, (NSUInteger)floor(NSHeight(self.bounds) / lineHeight));
  NSString *scene = [self sceneWithColumns:columns rows:rows];
  NSRect drawingRect = NSMakeRect(floor((NSWidth(self.bounds) - columns * cellWidth) * 0.5),
                                  floor((NSHeight(self.bounds) - rows * lineHeight) * 0.5),
                                  columns * cellWidth,
                                  rows * lineHeight);
  [scene drawWithRect:drawingRect
              options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
           attributes:attributes];
}

@end
