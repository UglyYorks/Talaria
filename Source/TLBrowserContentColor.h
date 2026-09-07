#import <AppKit/AppKit.h>
@interface TLBrowserContentColor : NSObject
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data;
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data bottomFraction:(double)bottomFraction;
+ (NSArray<NSArray<NSNumber *> *> *)horizontalRGBStripForImageData:(NSData *)data bottomFraction:(double)bottomFraction widthFraction:(double)widthFraction;
+ (NSString *)CSSStringForColor:(NSColor *)color;
+ (NSColor *)colorForRGB:(NSArray *)rgb;
@end
