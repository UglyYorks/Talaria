#import "TLLinkServicesView.h"
@implementation TLLinkServicesView
- (BOOL)acceptsFirstResponder { return YES; }
- (id)validRequestorForSendType:(NSPasteboardType)sendType returnType:(NSPasteboardType)returnType {
  if ((!returnType || !returnType.length) && [@[NSPasteboardTypeString, NSPasteboardTypeURL] containsObject:sendType]) return self;
  return [super validRequestorForSendType:sendType returnType:returnType];
}
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pasteboard types:(NSArray<NSPasteboardType> *)types {
  NSMutableArray *supported = [NSMutableArray array];
  for (NSString *type in types) if ([@[NSPasteboardTypeString, NSPasteboardTypeURL] containsObject:type]) [supported addObject:type];
  if (!supported.count) return NO;
  [pasteboard declareTypes:supported owner:nil];
  for (NSString *type in supported) [pasteboard setString:self.URL.absoluteString forType:type];
  return YES;
}
@end
