#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface TLWebKitImageLoader : NSObject
// Streams a bounded image into memory. Cookie scope is recomputed on every
// redirect from the originating WKWebsiteDataStore snapshot.
+ (void)loadURL:(NSURL *)URL cookies:(NSArray<NSHTTPCookie *> *)cookies completion:(void (^)(NSData * _Nullable, NSString * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
