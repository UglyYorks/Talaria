#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern NSNotificationName const TLBrowserDownloadsDidChangeNotification;
typedef NS_ENUM(NSInteger, TLBrowserDownloadState) {
  TLBrowserDownloadStateDownloading, TLBrowserDownloadStatePaused,
  TLBrowserDownloadStateComplete, TLBrowserDownloadStateCancelled, TLBrowserDownloadStateFailed
};
typedef NS_ENUM(NSInteger, TLBrowserDownloadAction) {
  TLBrowserDownloadActionPause, TLBrowserDownloadActionResume, TLBrowserDownloadActionCancel
};
typedef void (^TLBrowserDownloadControl)(TLBrowserDownloadAction action);

@interface TLBrowserDownload : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *URLString;
@property (nonatomic, copy, readonly) NSString *fileName;
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *failureReason;
@property (nonatomic, strong, readonly) NSDate *startedAt;
@property (nonatomic, readonly) TLBrowserDownloadState state;
@property (nonatomic, readonly) int64_t receivedBytes;
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) int64_t bytesPerSecond;
@property (nonatomic, readonly) BOOL active;
@property (nonatomic, readonly) BOOL controllable;
@property (nonatomic, readonly) BOOL canRetry;
@property (nonatomic, readonly) BOOL fileAvailable;
@property (nonatomic, copy, readonly) NSString *statusText;
@end

/// Main-thread download snapshots and history; Chromium owns the actual transfers.
@interface TLBrowserDownloadManager : NSObject
+ (instancetype)sharedManager;
- (instancetype)initWithHistoryURL:(NSURL *)URL;
@property (nonatomic, copy, readonly) NSArray<TLBrowserDownload *> *downloads;
@property (nonatomic, strong, readonly, nullable) NSError *persistenceError;
- (void)updateDownloadWithID:(NSUInteger)downloadID browserIdentifier:(NSInteger)browserIdentifier
                  URLString:(NSString *)URLString fileName:(NSString *)fileName path:(NSString *)path
              receivedBytes:(int64_t)received totalBytes:(int64_t)total bytesPerSecond:(int64_t)speed
                      state:(TLBrowserDownloadState)state failureReason:(NSString *)failureReason
                    control:(nullable TLBrowserDownloadControl)control;
- (NSString *)reserveDestinationForDownloadID:(NSUInteger)downloadID directory:(NSString *)directory fileName:(NSString *)name;
- (void)performAction:(TLBrowserDownloadAction)action forDownload:(TLBrowserDownload *)download;
- (void)removeDownload:(TLBrowserDownload *)download;
- (void)clearFinishedDownloads;
- (BOOL)hasActiveDownloadsForBrowser:(NSInteger)browserIdentifier;
- (void)browserClosed:(NSInteger)browserIdentifier;
- (void)finishSession;
@end
NS_ASSUME_NONNULL_END
