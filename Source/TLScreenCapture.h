#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
// AppKit screen coordinates are bottom-up; capture APIs use the primary display's top-left.
NSRect TLScreenCaptureRect(NSRect screenRect, NSRect primaryScreenFrame);

@interface TLScreenCapture : NSObject
- (void)captureRect:(NSRect)screenRect excludingWindowIDs:(NSArray<NSNumber *> *)windowIDs
         completion:(void (^)(NSURL * _Nullable URL, NSError * _Nullable error))completion;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
