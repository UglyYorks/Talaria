#import "TLStarryEmptyStateView.h"
#import "UIComponents.h"
#import <math.h>

static NSUInteger TLStarHash(NSUInteger column, NSUInteger row) {
  NSUInteger value = column * 0x45d9f3bU + row * 0x119de1f3U + 0x27d4eb2dU;
  value = (value ^ (value >> 16)) * 0x45d9f3bU;
  return value ^ (value >> 16);
}

@interface TLStarryEmptyStateView ()
@property (nonatomic, strong) NSTextField *tipLabel;
@property (nonatomic, strong) NSTextField *avatarLabel;
@property (nonatomic, strong) NSTimer *animationTimer;
@property (nonatomic) NSUInteger frameIndex;
@property (nonatomic) NSRect bubbleRect;
@property (nonatomic) NSRect quietRect;
@end

@implementation TLStarryEmptyStateView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _tipLabel = [NSTextField labelWithString:@""];
    _tipLabel.maximumNumberOfLines = 0;
    _tipLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _tipLabel.usesSingleLineMode = NO;
    _avatarLabel = [NSTextField labelWithString:@"🤖"];
    _avatarLabel.alignment = NSTextAlignmentCenter;
    _avatarLabel.accessibilityElement = NO;
    [self addSubview:_tipLabel];
    [self addSubview:_avatarLabel];
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateAnimation)
      name:NSWindowDidChangeOcclusionStateNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(updateAnimation)
      name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
  }
  return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
// Decorative space must not consume composer focus or workspace gestures.
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.tipLabel.font = palette.messageBodyFont;
  self.tipLabel.textColor = palette.secondaryActionText;
  self.avatarLabel.font = palette.agentListAvatarFont;
  self.avatarLabel.textColor = palette.appText;
  self.needsLayout = YES;
  self.needsDisplay = YES;
}
- (void)setAvailableMessageWidth:(CGFloat)availableMessageWidth {
  _availableMessageWidth = availableMessageWidth;
  self.needsLayout = YES;
}
- (void)setAvatar:(NSString *)avatar {
  _avatar = [avatar copy];
  self.avatarLabel.stringValue = avatar.length ? avatar : @"🤖";
  self.needsLayout = YES;
}
- (void)setTip:(NSString *)tip {
  _tip = [tip copy];
  self.tipLabel.stringValue = tip ?: @"";
  self.needsLayout = YES;
  self.needsDisplay = YES;
}
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self updateAnimation]; }
- (void)viewDidHide { [super viewDidHide]; [self updateAnimation]; }
- (void)viewDidUnhide { [super viewDidUnhide]; [self updateAnimation]; }
- (void)setHidden:(BOOL)hidden { [super setHidden:hidden]; [self updateAnimation]; }
- (void)updateAnimation {
  BOOL animate = self.window && !self.hiddenOrHasHiddenAncestor &&
    (self.window.occlusionState & NSWindowOcclusionStateVisible) &&
    !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  if (!animate) {
    [self.animationTimer invalidate];
    self.animationTimer = nil;
  } else if (!self.animationTimer) {
    __weak typeof(self) weakSelf = self;
    self.animationTimer = [NSTimer timerWithTimeInterval:self.palette.emptyStateSparkleFrameInterval repeats:YES block:^(NSTimer *timer) {
      weakSelf.frameIndex += 1;
      weakSelf.needsDisplay = YES;
    }];
    self.animationTimer.tolerance = self.palette.emptyStateSparkleFrameInterval * 0.2;
    [NSRunLoop.mainRunLoop addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
  }
  self.needsDisplay = YES;
}
- (void)dealloc {
  [self.animationTimer invalidate];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)layout {
  [super layout];
  TLThemePalette *p = self.palette;
  CGFloat margin = MIN(p.space12, NSWidth(self.bounds) * 0.06);
  CGFloat available = MAX(1, NSWidth(self.bounds) - margin * 2);
  NSSize avatarSize = self.avatarLabel.intrinsicContentSize;
  CGFloat tail = p.userMessageTailHeight;
  CGFloat gap = p.space2;
  BOOL compact = available < avatarSize.width * 5;
  CGFloat messageWidth = self.availableMessageWidth > 0 ? self.availableMessageWidth :
    MIN(p.messageInputMaxWidth, MAX(1, NSWidth(self.bounds) - p.space11 * 2));
  CGFloat maximumBubbleWidth = MIN(messageWidth * p.userMessageMaxWidthMultiplier,
    MAX(1, available - (compact ? 0 : avatarSize.width + gap)));
  CGFloat padding = p.userMessageHorizontalPadding;
  self.tipLabel.preferredMaxLayoutWidth = MAX(1, maximumBubbleWidth - padding * 2);
  // Match user messages: natural label width, symmetric minimum-width padding,
  // and only the content height plus the shared vertical padding and tail.
  CGFloat minimumBubbleWidth = MIN(p.userMessageMinWidth, maximumBubbleWidth);
  padding = MAX(padding, (minimumBubbleWidth - self.tipLabel.intrinsicContentSize.width) * 0.5);
  self.tipLabel.preferredMaxLayoutWidth = MAX(1, maximumBubbleWidth - padding * 2);
  NSSize textSize = self.tipLabel.intrinsicContentSize;
  CGFloat textWidth = MIN(self.tipLabel.preferredMaxLayoutWidth, ceil(textSize.width));
  CGFloat textHeight = ceil(textSize.height);
  CGFloat bodyWidth = textWidth + padding * 2;
  CGFloat bodyHeight = textHeight + p.userMessageVerticalPadding * 2 + tail;
  CGFloat groupWidth = (compact ? 0 : avatarSize.width + gap) + bodyWidth;
  CGFloat avatarDrop = compact ? avatarSize.height + gap : avatarSize.height * 0.5;
  CGFloat groupHeight = bodyHeight + avatarDrop;
  CGFloat x = floor((NSWidth(self.bounds) - groupWidth) / 2);
  CGFloat y = MAX(p.space6, floor((NSHeight(self.bounds) - groupHeight) / 2));
  self.bubbleRect = NSMakeRect(x + (compact ? 0 : avatarSize.width + gap), y, bodyWidth, bodyHeight);
  self.avatarLabel.frame = NSMakeRect(x, NSMaxY(self.bubbleRect) + avatarDrop - avatarSize.height,
    avatarSize.width, avatarSize.height);
  // Auto Layout positions user-message labels by their alignment rect, which
  // excludes NSTextField's internal cell insets. Preserve those same insets here.
  self.tipLabel.frame = [self.tipLabel frameForAlignmentRect:NSMakeRect(NSMinX(self.bubbleRect) + padding,
    NSMinY(self.bubbleRect) + p.userMessageVerticalPadding, textWidth, textHeight)];
  self.quietRect = NSInsetRect(NSUnionRect(self.bubbleRect, self.avatarLabel.frame), -p.space12, -p.space16);
  self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  [p.tabBackground setFill];
  NSRectFill(dirtyRect);
  CGFloat spacing = p.emptyStateSparkleSpacing;
  NSUInteger columns = (NSUInteger)MAX(0, ceil(NSWidth(self.bounds) / spacing));
  NSUInteger rows = (NSUInteger)MAX(0, ceil(NSHeight(self.bounds) / spacing));
  NSTimeInterval time = self.frameIndex * p.emptyStateSparkleFrameInterval;
  [NSGraphicsContext saveGraphicsState];
  [p.emptyText setFill];
  for (NSUInteger row = 0; row < rows; row++) {
    for (NSUInteger col = 0; col < columns; col++) {
      NSUInteger hash = TLStarHash(col, row);
      if (hash % 3 == 0) continue;
      CGFloat x = (col + 0.2 + 0.6 * ((hash / 101) % 100) / 100.0) * spacing;
      CGFloat y = (row + 0.2 + 0.6 * ((hash / 701) % 100) / 100.0) * spacing;
      CGFloat radius = p.emptyStateSparkleSize * (0.65 + 0.35 * (hash % 100) / 100.0) * 0.5;
      NSRect envelope = NSMakeRect(x - radius, y - radius, radius * 2, radius * 2);
      // Reserve the entire animation envelope so sparkles never enter the tip's
      // breathing room or suddenly disappear as they expand.
      if (NSIntersectsRect(envelope, self.quietRect) || !NSIntersectsRect(envelope, dirtyRect)) continue;
      CGFloat period = p.emptyStateSparkleCycleDuration * (0.75 + (hash % 51) / 100.0);
      CGFloat phase = (hash % 997) / 997.0 * M_PI * 2;
      CGFloat pulse = (sin(time / period * M_PI * 2 + phase) + 1) * 0.5;
      CGFloat scale = p.emptyStateSparkleMinimumScale + (1 - p.emptyStateSparkleMinimumScale) * pulse;
      CGFloat opacity = p.emptyStateSparkleMinimumOpacity +
        (p.emptyStateSparkleMaximumOpacity - p.emptyStateSparkleMinimumOpacity) * pulse;
      CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, opacity);
      CGFloat rx = radius * scale, ry = rx * 0.85;
      // Four tapered rays with inward-curving shoulders, matching the reference.
      NSBezierPath *sparkle = [NSBezierPath bezierPath];
      [sparkle moveToPoint:NSMakePoint(x, y - ry)];
      [sparkle curveToPoint:NSMakePoint(x + rx, y)
        controlPoint1:NSMakePoint(x, y - ry * 0.16) controlPoint2:NSMakePoint(x + rx * 0.16, y)];
      [sparkle curveToPoint:NSMakePoint(x, y + ry)
        controlPoint1:NSMakePoint(x + rx * 0.16, y) controlPoint2:NSMakePoint(x, y + ry * 0.16)];
      [sparkle curveToPoint:NSMakePoint(x - rx, y)
        controlPoint1:NSMakePoint(x, y + ry * 0.16) controlPoint2:NSMakePoint(x - rx * 0.16, y)];
      [sparkle curveToPoint:NSMakePoint(x, y - ry)
        controlPoint1:NSMakePoint(x - rx * 0.16, y) controlPoint2:NSMakePoint(x, y - ry * 0.16)];
      [sparkle closePath];
      [sparkle fill];
    }
  }
  [NSGraphicsContext restoreGraphicsState];
  NSBezierPath *bubble = TLCreateIncomingMessageBubblePath(self.bubbleRect, p);
  // Convert the shared AppKit outline into this flipped view.
  NSAffineTransform *flip = [NSAffineTransform transform];
  flip.transformStruct = (NSAffineTransformStruct){1, 0, 0, -1, 0,
    NSMinY(self.bubbleRect) + NSMaxY(self.bubbleRect)};
  [bubble transformUsingAffineTransform:flip];
  [p.secondaryActionSurface setFill];
  [bubble fill];
}
@end
