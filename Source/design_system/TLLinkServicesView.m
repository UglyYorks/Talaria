#import "TLLinkServicesView.h"
@implementation TLLinkServicesView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.richText = NO;
    self.editable = NO;
    self.selectable = YES;
    self.drawsBackground = NO;
  }
  return self;
}
- (void)setURL:(NSURL *)URL {
  _URL = [URL copy];
  self.string = URL.absoluteString ?: @"";
  self.selectedRange = NSMakeRange(0, self.string.length);
}
- (NSArray<NSPasteboardType> *)writablePasteboardTypes {
  // NSTextView supplies native selection context (including word counts) for
  // Services filtering. Terminal requests public.plain-text; Finder accepts URLs.
  NSMutableArray *types = super.writablePasteboardTypes.mutableCopy;
  for (NSString *type in @[NSPasteboardTypeString, @"public.plain-text", NSPasteboardTypeURL]) {
    if (![types containsObject:type]) [types addObject:type];
  }
  return types;
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard type:(NSPasteboardType)type {
  if ([@[NSPasteboardTypeString, @"public.plain-text", NSPasteboardTypeURL] containsObject:type]) {
    return self.URL && [pasteboard setString:self.URL.absoluteString forType:type];
  }
  return [super writeSelectionToPasteboard:pasteboard type:type];
}
@end
