#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>

NS_ASSUME_NONNULL_BEGIN
@interface TLAttachmentPreviewItem : NSObject <QLPreviewItem>
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL directory;
@property (nonatomic, copy) NSURL *_Nullable (^URLResolver)(void);
@property (nonatomic, readonly, nullable) NSURL *previewItemURL;
@property (nonatomic, readonly) NSString *previewItemTitle;
@property (nonatomic, readonly) NSString *detail;
// Call off the main thread. Revalidates the source and preserves it on every path.
- (BOOL)saveCopyToURL:(NSURL *)destination error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
