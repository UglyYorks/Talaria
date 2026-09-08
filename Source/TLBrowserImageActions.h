#import <AppKit/AppKit.h>
@class TLBrowserDownloadManager;
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TLBrowserImageAction) {
  TLBrowserImageOpenTab, TLBrowserImageOpenWindow, TLBrowserImageSaveDownloads, TLBrowserImageSaveAs,
  TLBrowserImageAddToPhotos, TLBrowserImageWallpaper, TLBrowserImageCopyAddress, TLBrowserImageCopy,
  TLBrowserImageCopySubject, TLBrowserImageLookUp, TLBrowserImageShare
};
@interface TLBrowserImageResource : NSObject
@property (nonatomic, copy) NSData *data;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong, nullable) NSImage *image;
+ (nullable instancetype)resourceWithData:(NSData *)data URL:(NSURL *)URL MIMEType:(NSString *)MIMEType;
@end
FOUNDATION_EXPORT BOOL TLBrowserImageURLIsSupported(NSURL * _Nullable URL);
FOUNDATION_EXPORT NSArray<NSString *> *TLBrowserImageMenuTitles(void);
@interface TLBrowserImageActions : NSObject
+ (void)shareURL:(NSURL *)URL fromView:(NSView *)view atPoint:(NSPoint)point;
+ (void)performAction:(TLBrowserImageAction)action resource:(TLBrowserImageResource *)resource
                 URL:(NSURL *)URL fromView:(NSView *)view atPoint:(NSPoint)point;
+ (void)saveResource:(TLBrowserImageResource *)resource URL:(NSURL *)URL destination:(NSURL *)destination
          overwrite:(BOOL)overwrite manager:(TLBrowserDownloadManager *)manager completion:(void (^)(NSError * _Nullable))completion;
+ (BOOL)copyImage:(NSImage *)image toPasteboard:(NSPasteboard *)pasteboard;
+ (void)copySubjectOfImage:(NSImage *)image completion:(void (^)(NSImage * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
