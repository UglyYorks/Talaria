#import "TLTabIconView.h"
#import <CoreText/CoreText.h>

@interface TLTabEmojiView : NSView
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) NSColor *textColor;
@property (nonatomic) CGFloat verticalOffset;
@end

@implementation TLTabEmojiView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _emoji = @"";
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (void)setEmoji:(NSString *)emoji {
  _emoji = [emoji copy] ?: @"";
  [self setNeedsDisplay:YES];
}

- (void)setFont:(NSFont *)font {
  _font = font;
  [self setNeedsDisplay:YES];
}

- (void)setTextColor:(NSColor *)textColor {
  _textColor = textColor;
  [self setNeedsDisplay:YES];
}

- (void)setVerticalOffset:(CGFloat)verticalOffset {
  _verticalOffset = verticalOffset;
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  if (self.emoji.length == 0 || !self.font || !self.textColor) {
    return;
  }

  NSDictionary<NSAttributedStringKey, id> *attributes = @{
    NSFontAttributeName: self.font,
    NSForegroundColorAttributeName: self.textColor,
  };
  NSAttributedString *attributedEmoji = [[NSAttributedString alloc] initWithString:self.emoji
                                                                        attributes:attributes];
  CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributedEmoji);
  if (!line) {
    return;
  }

  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(context);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  CGContextSetTextPosition(context, 0.0, 0.0);

  CGRect imageBounds = CTLineGetImageBounds(line, context);
  if (CGRectIsEmpty(imageBounds) || !isfinite(CGRectGetWidth(imageBounds)) || !isfinite(CGRectGetHeight(imageBounds))) {
    CGFloat ascent = 0.0;
    CGFloat descent = 0.0;
    CGFloat leading = 0.0;
    CGFloat width = (CGFloat)CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    imageBounds = CGRectMake(0.0, -descent, width, ascent + descent + leading);
  }

  CGFloat x = NSMidX(self.bounds) - CGRectGetMidX(imageBounds);
  CGFloat y = NSMidY(self.bounds) - CGRectGetMidY(imageBounds) + self.verticalOffset;
  CGContextSetTextPosition(context, x, y);
  CTLineDraw(line, context);
  CGContextRestoreGState(context);
  CFRelease(line);
}

@end

@interface TLTabIconView ()
@property (nonatomic, strong) TLTabEmojiView *emojiView;
@property (nonatomic, strong) NSImageView *systemIconView;
@property (nonatomic, strong) NSLayoutConstraint *emojiWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *emojiHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *systemIconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *systemIconHeightConstraint;
@end

@implementation TLTabIconView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _icon = @"";
    _systemIconName = @"";
    [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                  forOrientation:NSLayoutConstraintOrientationVertical];
    [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh
                      forOrientation:NSLayoutConstraintOrientationVertical];
    self.wantsLayer = YES;
    self.layer.masksToBounds = NO;
    [self buildInterface];
    [self applyCurrentState];
  }
  return self;
}

- (BOOL)isFlipped {
  return NO;
}

- (NSSize)intrinsicContentSize {
  CGFloat length = [self iconBoxLength];
  return NSMakeSize(length, length);
}

- (void)buildInterface {
  self.emojiView = [[TLTabEmojiView alloc] init];
  self.emojiView.translatesAutoresizingMaskIntoConstraints = NO;

  self.systemIconView = [[NSImageView alloc] init];
  self.systemIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.systemIconView.imageAlignment = NSImageAlignCenter;
  self.systemIconView.imageScaling = NSImageScaleProportionallyDown;

  [self addSubview:self.emojiView];
  [self addSubview:self.systemIconView];

  self.emojiWidthConstraint = [self.emojiView.widthAnchor constraintEqualToConstant:[self emojiDrawingLength]];
  self.emojiHeightConstraint = [self.emojiView.heightAnchor constraintEqualToConstant:[self emojiDrawingLength]];
  self.systemIconWidthConstraint = [self.systemIconView.widthAnchor constraintEqualToConstant:[self glyphLength]];
  self.systemIconHeightConstraint = [self.systemIconView.heightAnchor constraintEqualToConstant:[self glyphLength]];

  [NSLayoutConstraint activateConstraints:@[
    [self.emojiView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [self.emojiView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.emojiWidthConstraint,
    self.emojiHeightConstraint,
    [self.systemIconView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
    [self.systemIconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    self.systemIconWidthConstraint,
    self.systemIconHeightConstraint,
  ]];
}

- (BOOL)hasIcon {
  return self.image != nil || self.systemIconName.length > 0 || self.icon.length > 0;
}

- (void)applyCurrentState {
  if (!self.emojiView || !self.systemIconView) {
    return;
  }

  BOOL hasImage = self.image != nil;
  BOOL hasSystemIcon = self.systemIconName.length > 0 && !hasImage;
  BOOL hasEmojiIcon = self.icon.length > 0 && !hasSystemIcon && !hasImage;
  NSColor *foreground = self.contentTintColor ?: self.palette.labelText;

  self.emojiView.hidden = !hasEmojiIcon;
  self.emojiView.emoji = hasEmojiIcon ? self.icon : @"";
  self.emojiView.font = self.palette.tabIconFont;
  self.emojiView.textColor = foreground;
  self.emojiView.verticalOffset = self.palette.tabEmojiVerticalOffset;
  self.emojiWidthConstraint.constant = [self emojiDrawingLength];
  self.emojiHeightConstraint.constant = [self emojiDrawingLength];

  self.systemIconView.hidden = !hasSystemIcon && !hasImage;
  self.systemIconView.contentTintColor = hasSystemIcon ? foreground : nil;
  self.systemIconView.image = hasImage ? self.image : [self systemImageNamed:self.systemIconName];
  self.systemIconWidthConstraint.constant = [self glyphLength];
  self.systemIconHeightConstraint.constant = [self glyphLength];

  self.hidden = !self.hasIcon;
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout:YES];
}

- (void)setImage:(NSImage *)image {
  _image = image;
  [self applyCurrentState];
}

- (nullable NSImage *)systemImageNamed:(NSString *)name {
  if (name.length == 0) {
    return nil;
  }

  if (@available(macOS 11.0, *)) {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:self.palette.tabIconGlyphSize
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleMedium];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
    NSImage *sizedImage = [image copy];
    sizedImage.template = YES;
    CGFloat length = [self glyphLength];
    sizedImage.size = NSMakeSize(length, length);
    return sizedImage;
  }
  return nil;
}

- (CGFloat)iconBoxLength {
  return self.palette.tabIconSize;
}

- (CGFloat)glyphLength {
  return self.palette.tabIconGlyphSize;
}

- (CGFloat)emojiDrawingLength {
  return self.palette.tabIconSize + self.palette.space5;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette ?: [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
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

- (void)setContentTintColor:(NSColor *)contentTintColor {
  _contentTintColor = contentTintColor;
  [self applyCurrentState];
}

@end
