#import "TLAttachmentCard.h"
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>

@interface TLAttachmentCard ()
@property (nonatomic, strong) NSImage *thumbnail;
@property (nonatomic, strong) QLThumbnailGenerationRequest *thumbnailRequest;
@property (nonatomic, strong) NSTrackingArea *hoverTracking;
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL pressed;
@end

@implementation TLAttachmentCard
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    _title = @"Attachment";
    _subtitle = @"";
    self.accessibilityRole = NSAccessibilityButtonRole;
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(self.palette.attachmentCardWidth, self.palette.attachmentCardHeight); }
- (void)setPalette:(TLThemePalette *)palette { _palette = palette; [self invalidateIntrinsicContentSize]; self.needsDisplay = YES; }
- (void)setTitle:(NSString *)title { _title = [title copy]; self.toolTip = title; self.accessibilityLabel = [@"Preview " stringByAppendingString:title]; self.needsDisplay = YES; }
- (void)setSubtitle:(NSString *)subtitle { _subtitle = [subtitle copy]; self.accessibilityHelp = subtitle; self.needsDisplay = YES; }
- (void)setSelected:(BOOL)selected { _selected = selected; self.needsDisplay = YES; }
- (void)setFileURL:(NSURL *)URL {
  if ([_fileURL isEqual:URL]) return;
  _fileURL = URL;
  if (self.thumbnailRequest) [QLThumbnailGenerator.sharedGenerator cancelRequest:self.thumbnailRequest];
  self.thumbnailRequest = nil;
  self.thumbnail = nil;
  self.needsDisplay = YES;
  if (!URL || self.directory) return;
  QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:URL
    size:NSMakeSize(self.palette.attachmentThumbnailSize, self.palette.attachmentThumbnailSize)
    scale:NSScreen.mainScreen.backingScaleFactor ?: 2 representationTypes:QLThumbnailGenerationRequestRepresentationTypeAll];
  self.thumbnailRequest = request;
  __weak typeof(self) weakSelf = self;
  [QLThumbnailGenerator.sharedGenerator generateBestRepresentationForRequest:request completionHandler:^(QLThumbnailRepresentation *thumbnail, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      TLAttachmentCard *card = weakSelf;
      if (!card || card.thumbnailRequest != request) return;
      card.thumbnail = thumbnail.NSImage;
      card.thumbnailRequest = nil;
      card.needsDisplay = YES;
    });
  }];
}
- (void)dealloc { if (_thumbnailRequest) [QLThumbnailGenerator.sharedGenerator cancelRequest:_thumbnailRequest]; }
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (self.hoverTracking) [self removeTrackingArea:self.hoverTracking];
  self.hoverTracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
  [self addTrackingArea:self.hoverTracking];
}
- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.needsDisplay = YES; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseDown:(NSEvent *)event {
  [self.window makeFirstResponder:self]; self.pressed = YES; self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)event {
  BOOL activate = self.pressed && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
  self.pressed = NO; self.needsDisplay = YES;
  if (activate) [self accessibilityPerformPress];
}
- (BOOL)accessibilityPerformPress { if (self.activationHandler) self.activationHandler(); return YES; }
- (void)keyDown:(NSEvent *)event {
  if ([event.charactersIgnoringModifiers isEqual:@" "] || [event.charactersIgnoringModifiers isEqual:@"\r"]) [self accessibilityPerformPress];
  else [super keyDown:event];
}
- (void)drawRect:(NSRect)dirtyRect {
  TLThemePalette *p = self.palette;
  BOOL focused = self.window.firstResponder == self && self.window.isKeyWindow;
  NSRect bounds = NSInsetRect(self.bounds, p.borderWidth, p.borderWidth);
  NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:p.radiusMedium yRadius:p.radiusMedium];
  [(self.selected || self.pressed ? p.sidebarActiveSurface : (self.hovered ? p.chromeHoverSurface : p.controlSurface)) setFill];
  [shape fill];
  [(focused ? p.controlFocus : (self.selected ? p.controlFocus : p.controlBorder)) setStroke];
  shape.lineWidth = p.borderWidth;
  [shape stroke];
  CGFloat inset = p.space6;
  BOOL showsIcon = NSWidth(bounds) >= p.attachmentThumbnailSize * 3;
  CGFloat side = MIN(p.attachmentThumbnailSize, MAX(0, NSWidth(bounds) - inset * 2));
  NSRect iconRect = NSMakeRect(inset, (NSHeight(self.bounds) - side) / 2, side, side);
  if (showsIcon && self.thumbnail) {
    NSSize size = self.thumbnail.size;
    CGFloat scale = MIN(side / MAX(1, size.width), side / MAX(1, size.height));
    NSRect rect = NSMakeRect(NSMidX(iconRect) - size.width * scale / 2, NSMidY(iconRect) - size.height * scale / 2, size.width * scale, size.height * scale);
    [self.thumbnail drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
  } else if (showsIcon) {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:self.directory ? @"folder" : @"doc" accessibilityDescription:nil];
    NSImageSymbolConfiguration *configuration = [[NSImageSymbolConfiguration configurationWithPointSize:p.space12 weight:NSFontWeightRegular] configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:p.textMuted]];
    symbol = [symbol imageWithSymbolConfiguration:configuration];
    [symbol drawInRect:NSInsetRect(iconRect, p.space4, p.space4) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
  }
  CGFloat x = showsIcon ? NSMaxX(iconRect) + p.space5 : inset;
  CGFloat width = MAX(0, NSWidth(self.bounds) - x - inset);
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.lineBreakMode = NSLineBreakByTruncatingMiddle;
  CGFloat titleHeight = ceil(p.labelFont.ascender - p.labelFont.descender);
  CGFloat detailHeight = ceil(p.smallFont.ascender - p.smallFont.descender);
  CGFloat y = (NSHeight(self.bounds) - titleHeight - detailHeight - p.space3) / 2;
  [self.title drawInRect:NSMakeRect(x, y, width, titleHeight + p.space2) withAttributes:@{NSFontAttributeName:p.labelFont, NSForegroundColorAttributeName:p.controlText, NSParagraphStyleAttributeName:style}];
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.subtitle drawInRect:NSMakeRect(x, y + titleHeight + p.space3, width, detailHeight + p.space2) withAttributes:@{NSFontAttributeName:p.smallFont, NSForegroundColorAttributeName:p.textMuted, NSParagraphStyleAttributeName:style}];
}
@end
