#import "TLEmojiPicker.h"

static BOOL TLIsSingleEmoji(NSString *text) {
  if (!text.length || [text rangeOfComposedCharacterSequenceAtIndex:0].length != text.length) return NO;
  // ICU's Unicode property includes complete emoji sequences without a fixed list.
  // Digits, # and * are emoji bases, but are only avatars as keycap sequences.
  if ([text rangeOfString:@"^[0-9#*]$" options:NSRegularExpressionSearch].location != NSNotFound) return NO;
  return [text rangeOfString:@"\\p{Emoji}" options:NSRegularExpressionSearch].location != NSNotFound;
}

@interface TLEmojiPicker ()
@property (nonatomic, strong) NSTextInputContext *emojiInputContext;
@property (nonatomic, copy) NSString *pendingText;
@property (nonatomic) NSRange pendingSelection;
@end

@implementation TLEmojiPicker

- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.bezelStyle = NSBezelStyleRounded;
    self.target = self;
    self.action = @selector(showEmojiPicker:);
    self.toolTip = @"Choose emoji…";
    self.accessibilityLabel = @"Choose emoji avatar";
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
    self.emoji = @"🤖";
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.font = palette.titleFont;
  self.bezelColor = palette.secondaryActionSurface;
  self.contentTintColor = palette.secondaryActionText;
  [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize {
  return NSMakeSize(self.palette.fieldHeight + self.palette.space6 * 2, self.palette.fieldHeight);
}

- (void)setEmoji:(NSString *)emoji {
  if (!TLIsSingleEmoji(emoji)) return;
  _emoji = [emoji copy];
  self.title = _emoji;
  self.accessibilityValue = _emoji;
  [self.emojiInputContext invalidateCharacterCoordinates];
}

- (BOOL)acceptsFirstResponder { return self.enabled; }

- (NSTextInputContext *)inputContext {
  if (!self.enabled) return nil;
  if (!self.emojiInputContext) self.emojiInputContext = [[NSTextInputContext alloc] initWithClient:self];
  return self.emojiInputContext;
}

- (BOOL)becomeFirstResponder {
  if (![super becomeFirstResponder]) return NO;
  [self.inputContext activate];
  return YES;
}

- (BOOL)resignFirstResponder {
  [self.emojiInputContext deactivate];
  [self unmarkText];
  return [super resignFirstResponder];
}

- (void)showEmojiPicker:(id)sender {
  if (!self.enabled || ![self.window makeFirstResponder:self]) return;
  [NSApp orderFrontCharacterPalette:self];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
  NSString *text = [string isKindOfClass:NSAttributedString.class] ? [string string] : string;
  [self unmarkText];
  if (!self.enabled || ![text isKindOfClass:NSString.class] || !TLIsSingleEmoji(text)) return;
  self.emoji = text;
  if (self.emojiChangedHandler) self.emojiChangedHandler(self.emoji);
}

- (void)insertText:(id)string {
  [self insertText:string replacementRange:self.selectedRange];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
  if (!self.enabled) return;
  self.pendingText = [string isKindOfClass:NSAttributedString.class] ? [string string] : string;
  self.pendingSelection = selectedRange;
}

- (void)unmarkText { self.pendingText = nil; }
- (BOOL)hasMarkedText { return self.pendingText.length > 0; }
- (NSRange)markedRange { return self.hasMarkedText ? NSMakeRange(0, self.pendingText.length) : NSMakeRange(NSNotFound, 0); }
- (NSRange)selectedRange { return self.hasMarkedText ? self.pendingSelection : NSMakeRange(0, self.emoji.length); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
  NSString *text = self.hasMarkedText ? self.pendingText : self.emoji;
  if (range.location == NSNotFound || range.location > text.length) {
    if (actualRange) *actualRange = NSMakeRange(NSNotFound, 0);
    return nil;
  }
  NSRange available = NSMakeRange(range.location, MIN(range.length, text.length - range.location));
  if (actualRange) *actualRange = available;
  return [[NSAttributedString alloc] initWithString:[text substringWithRange:available]];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
  if (actualRange) *actualRange = self.selectedRange;
  return [self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point { return 0; }

- (void)doCommandBySelector:(SEL)selector {
  if (selector == @selector(cancelOperation:)) [self unmarkText];
  else if (selector == @selector(insertTab:)) [self.window selectNextKeyView:self];
  else if (selector == @selector(insertBacktab:)) [self.window selectPreviousKeyView:self];
}

@end
