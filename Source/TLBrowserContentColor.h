#import <AppKit/AppKit.h>

// Bound both viewport capture and image decoding in physical pixels. Retina
// 6K displays exceed 16 Mi pixels; 32 Mi also accommodates an 8K viewport.
FOUNDATION_EXPORT const NSUInteger TLBrowserContentColorMaximumImagePixels;

@interface TLBrowserContentColor : NSObject
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data;
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data bottomFraction:(double)bottomFraction;
+ (NSArray<NSArray<NSNumber *> *> *)horizontalRGBStripForImageData:(NSData *)data bottomFraction:(double)bottomFraction widthFraction:(double)widthFraction;
+ (NSString *)CSSStringForColor:(NSColor *)color;
+ (NSColor *)colorForRGB:(NSArray *)rgb;
@end
