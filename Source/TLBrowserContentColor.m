#import "TLBrowserContentColor.h"
#import <math.h>
#import <ImageIO/ImageIO.h>

const NSUInteger TLBrowserContentColorMaximumImagePixels = 32 * 1024 * 1024;

@implementation TLBrowserContentColor
+ (NSArray<NSArray<NSNumber *> *> *)horizontalRGBStripForImageData:(NSData *)data bottomFraction:(double)bottomFraction widthFraction:(double)widthFraction {
  if(!isfinite(bottomFraction) || bottomFraction<=0 || bottomFraction>1 ||
     !isfinite(widthFraction) || widthFraction<=0 || widthFraction>1 || !data.length || data.length>8*1024*1024)return nil;
  CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
  if(!source)return nil;
  NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
  double width=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
  double height=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
  if(width<1 || height<1 || width*height>TLBrowserContentColorMaximumImagePixels){CFRelease(source);return nil;}
  CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);
  if(!image)return nil;
  double bottom=MAX(1,floor(height*bottomFraction));
  CGImageRef edge=CGImageCreateWithImageInRect(image,CGRectMake(0,MAX(0,bottom-2),MAX(1,floor(width*widthFraction)),MIN(2,bottom)));
  CGImageRelease(image);if(!edge)return nil;
  unsigned char pixels[32*4]={0};
  CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context=CGBitmapContextCreate(pixels,32,1,8,32*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(space);if(!context){CGImageRelease(edge);return nil;}
  CGContextSetInterpolationQuality(context,kCGInterpolationLow);
  CGContextDrawImage(context,CGRectMake(0,0,32,1),edge);CGImageRelease(edge);CGContextRelease(context);
  NSMutableArray *colors=[NSMutableArray arrayWithCapacity:32];
  for(NSUInteger i=0;i<32;i++) {
    const unsigned char *p=pixels+i*4;if(p[3]<250)return nil;
    [colors addObject:@[@(p[0]),@(p[1]),@(p[2])]];
  }
  return colors;
}
+ (NSString *)CSSStringForColor:(NSColor *)color {
  // Serialize the same content-derived (or theme fallback) color for the DOM spacer.
  color=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  return [NSString stringWithFormat:@"rgb(%d,%d,%d)",(int)round(color.redComponent*255),(int)round(color.greenComponent*255),(int)round(color.blueComponent*255)];
}
+ (NSColor *)colorForRGB:(NSArray *)rgb {
  if (![rgb isKindOfClass:NSArray.class] || rgb.count!=3) return nil;
  for(id channel in rgb) if(![channel isKindOfClass:NSNumber.class] || !isfinite([channel doubleValue]) || [channel doubleValue]<0 || [channel doubleValue]>255) return nil;
  // Content-derived exception: page extensions, footer and active browser tab
  // continue the page edge. Other chrome and fallbacks remain theme-owned.
  return [NSColor colorWithSRGBRed:[rgb[0] doubleValue]/255 green:[rgb[1] doubleValue]/255 blue:[rgb[2] doubleValue]/255 alpha:1];
}
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data {
  return [self dominantRGBForImageData:data bottomFraction:1];
}
+ (NSArray<NSNumber *> *)dominantRGBForImageData:(NSData *)data bottomFraction:(double)bottomFraction {
  if(!isfinite(bottomFraction) || bottomFraction<=0 || bottomFraction>1)return nil;
  if(!data.length || data.length>8*1024*1024)return nil;
  CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
  if(!source)return nil;
  NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
  double imageWidth=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
  double imageHeight=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
  if(imageWidth<1 || imageHeight<1 || imageWidth*imageHeight>TLBrowserContentColorMaximumImagePixels){CFRelease(source);return nil;}
  CGImageRef image=CGImageSourceCreateImageAtIndex(source,0,NULL);CFRelease(source);
  if(!image)return nil;
  // Crop the returned image, never the live WebKit render widget. Image-space
  // y starts at the top; sampling the bottom strip must not average the page.
  double bottom=MAX(1,floor(imageHeight*bottomFraction));
  CGImageRef edge=CGImageCreateWithImageInRect(image,CGRectMake(0,MAX(0,bottom-12),imageWidth,MIN(12,bottom)));
  CGImageRelease(image);if(!edge)return nil;
  NSUInteger width=MIN(256,CGImageGetWidth(edge)),height=1;
  NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];
  CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context=CGBitmapContextCreate(pixels.mutableBytes,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(space);if(!context){CGImageRelease(edge);return nil;}
  CGContextSetInterpolationQuality(context,kCGInterpolationLow);
  CGContextDrawImage(context,CGRectMake(0,0,width,height),edge);CGImageRelease(edge);CGContextRelease(context);
  // Quantized clusters ignore isolated glyphs/noise. Within the largest cluster
  // use the most frequent exact pixel, preserving solid backgrounds exactly.
  NSUInteger buckets[4096]={0};NSMutableDictionary<NSNumber *,NSNumber *> *counts=[NSMutableDictionary dictionary];
  const unsigned char *bytes=pixels.bytes;NSUInteger winning=0;
  for(NSUInteger i=0;i<width*height;i++) {
    const unsigned char *p=bytes+i*4;if(p[3]<250)continue;
    NSUInteger bucket=(p[0]>>4)*256+(p[1]>>4)*16+(p[2]>>4);
    if(++buckets[bucket]>buckets[winning])winning=bucket;
    NSNumber *key=@((p[0]<<16)|(p[1]<<8)|p[2]);counts[key]=@([counts[key] unsignedIntegerValue]+1);
  }
  if(!buckets[winning])return nil;
  NSUInteger best=0,frequency=0;
  for(NSNumber *key in counts) {
    NSUInteger p=key.unsignedIntegerValue,bucket=((p>>20)&15)*256+((p>>12)&15)*16+((p>>4)&15);
    NSUInteger count=[counts[key] unsignedIntegerValue];
    if(bucket==winning && (count>frequency || (count==frequency && p<best))){best=p;frequency=count;}
  }
  return @[@((best>>16)&255),@((best>>8)&255),@(best&255)];
}
@end
