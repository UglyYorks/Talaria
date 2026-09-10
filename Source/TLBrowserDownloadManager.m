#import "TLBrowserDownloadManager.h"
#import "TLBrowserPreferences.h"

NSNotificationName const TLBrowserDownloadsDidChangeNotification = @"TLBrowserDownloadsDidChange";
@interface TLBrowserDownload ()
@property (nonatomic, copy, readwrite) NSString *identifier, *URLString, *fileName, *path, *failureReason;
@property (nonatomic, strong, readwrite) NSDate *startedAt;
@property (nonatomic, readwrite) TLBrowserDownloadState state;
@property (nonatomic, readwrite) int64_t receivedBytes, totalBytes, bytesPerSecond;
@property (nonatomic) NSInteger browserIdentifier;
@property (nonatomic, copy) TLBrowserDownloadControl control;
@end
@implementation TLBrowserDownload
- (BOOL)active { return self.state == TLBrowserDownloadStateDownloading || self.state == TLBrowserDownloadStatePaused; }
- (BOOL)controllable { return self.active && self.control != nil; }
- (BOOL)canRetry {
  NSURL *URL = [NSURL URLWithString:self.URLString];
  return !self.active && self.state != TLBrowserDownloadStateComplete && URL.host.length &&
    [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString];
}
- (BOOL)fileAvailable {
  BOOL directory = NO;
  return self.state == TLBrowserDownloadStateComplete && self.path.isAbsolutePath &&
    [NSFileManager.defaultManager fileExistsAtPath:self.path isDirectory:&directory] && !directory;
}
- (NSString *)statusText {
  NSString *received = [NSByteCountFormatter stringFromByteCount:self.receivedBytes countStyle:NSByteCountFormatterCountStyleFile];
  if (self.state == TLBrowserDownloadStateComplete) return self.fileAvailable ? [@"Completed · " stringByAppendingString:received] : @"File moved or deleted";
  if (self.state == TLBrowserDownloadStateCancelled) return @"Cancelled";
  if (self.state == TLBrowserDownloadStateFailed) return self.failureReason.length ? [@"Failed · " stringByAppendingString:self.failureReason] : @"Download interrupted";
  NSString *size = self.totalBytes > 0 ? [NSString stringWithFormat:@"%@ of %@", received,
    [NSByteCountFormatter stringFromByteCount:self.totalBytes countStyle:NSByteCountFormatterCountStyleFile]] : received;
  if (self.state == TLBrowserDownloadStatePaused) return self.failureReason.length ? [@"Paused · " stringByAppendingString:self.failureReason] : [@"Paused · " stringByAppendingString:size];
  if (!self.path.length) return @"Starting download…";
  if (self.bytesPerSecond <= 0) return [@"Downloading · " stringByAppendingString:size];
  return [NSString stringWithFormat:@"%@ · %@/s", size,
    [NSByteCountFormatter stringFromByteCount:self.bytesPerSecond countStyle:NSByteCountFormatterCountStyleFile]];
}
@end

@interface TLBrowserDownloadManager ()
@property NSURL *historyURL;
@property NSMutableArray<TLBrowserDownload *> *items;
@property NSMutableDictionary<NSNumber *, TLBrowserDownload *> *liveItems;
@property NSMutableDictionary<NSNumber *, NSString *> *reservedPaths;
@property (nonatomic, strong, readwrite) NSError *persistenceError;
@property BOOL saveScheduled;
@end
@implementation TLBrowserDownloadManager
+ (instancetype)sharedManager {
  static TLBrowserDownloadManager *manager; static dispatch_once_t once;
  dispatch_once(&once, ^{ manager = [[self alloc] initWithHistoryURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"TalariaDownloads.json"]]; });
  return manager;
}
- (instancetype)initWithHistoryURL:(NSURL *)URL {
  if ((self = [super init])) {
    _historyURL = URL;
    _items = [NSMutableArray array]; _liveItems = [NSMutableDictionary dictionary]; _reservedPaths = [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfURL:URL];
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([stored isKindOfClass:NSArray.class]) for (id value in stored) {
      if (![value isKindOfClass:NSDictionary.class]) continue;
      NSDictionary *row = value;
      BOOL valid = YES;
      for (NSString *key in @[@"identifier", @"URL", @"name", @"path", @"failure"]) valid &= [row[key] isKindOfClass:NSString.class];
      for (NSString *key in @[@"started", @"state", @"received", @"total"]) valid &= [row[key] isKindOfClass:NSNumber.class];
      if (!valid || ![row[@"identifier"] length] || [row[@"state"] integerValue] < 0 || [row[@"state"] integerValue] > TLBrowserDownloadStateFailed) continue;
      TLBrowserDownload *item = [[TLBrowserDownload alloc] init];
      item.identifier = row[@"identifier"]; item.URLString = row[@"URL"]; item.fileName = row[@"name"];
      item.path = row[@"path"]; item.failureReason = row[@"failure"]; item.startedAt = [NSDate dateWithTimeIntervalSince1970:[row[@"started"] doubleValue]];
      item.state = [row[@"state"] integerValue]; item.receivedBytes = MAX(0, [row[@"received"] longLongValue]); item.totalBytes = MAX(0, [row[@"total"] longLongValue]);
      item.browserIdentifier = -1;
      if (item.active) { item.state = TLBrowserDownloadStateFailed; item.failureReason = @"Talaria closed before this download finished"; }
      [_items addObject:item];
    }
  }
  return self;
}
- (NSArray<TLBrowserDownload *> *)downloads { return self.items.copy; }
- (void)save {
  NSMutableArray *rows = [NSMutableArray array];
  for (TLBrowserDownload *item in self.items) [rows addObject:@{@"identifier":item.identifier, @"URL":item.URLString,
    @"name":item.fileName, @"path":item.path, @"failure":item.failureReason, @"started":@(item.startedAt.timeIntervalSince1970),
    @"state":@(item.state), @"received":@(item.receivedBytes), @"total":@(item.totalBytes)}];
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:&error];
  if (data && [NSFileManager.defaultManager createDirectoryAtURL:self.historyURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error])
    [data writeToURL:self.historyURL options:NSDataWritingAtomic error:&error];
  self.persistenceError = error;
}
- (void)changedSavingImmediately:(BOOL)immediately {
  if (immediately) [self save];
  else if (!self.saveScheduled) {
    self.saveScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      typeof(self) self = weakSelf;
      if (!self) return;
      self.saveScheduled = NO; [self save];
      [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserDownloadsDidChangeNotification object:self];
    });
  }
  [NSNotificationCenter.defaultCenter postNotificationName:TLBrowserDownloadsDidChangeNotification object:self];
}
- (void)updateDownloadWithID:(NSUInteger)downloadID browserIdentifier:(NSInteger)browserIdentifier
                  URLString:(NSString *)URLString fileName:(NSString *)fileName path:(NSString *)path
              receivedBytes:(int64_t)received totalBytes:(int64_t)total bytesPerSecond:(int64_t)speed
                      state:(TLBrowserDownloadState)state failureReason:(NSString *)failureReason control:(TLBrowserDownloadControl)control {
  TLBrowserDownload *item = self.liveItems[@(downloadID)];
  // Late engine events must not resurrect cleared or completed entries.
  if (item && !item.active) return;
  BOOL created = !item;
  if (!item) {
    item = [[TLBrowserDownload alloc] init]; item.identifier = NSUUID.UUID.UUIDString; item.startedAt = NSDate.date;
    item.URLString = @""; item.fileName = @"Download"; item.path = @"";
    self.liveItems[@(downloadID)] = item; [self.items insertObject:item atIndex:0];
  }
  TLBrowserDownloadState previousState = item.state;
  item.browserIdentifier = browserIdentifier;
  if (URLString.length) item.URLString = URLString;
  if (fileName.length) item.fileName = fileName.lastPathComponent;
  if (path.length) { item.path = path; item.fileName = path.lastPathComponent; }
  item.receivedBytes = MAX(0, received); item.totalBytes = MAX(0, total); item.bytesPerSecond = MAX(0, speed);
  item.state = state; item.failureReason = failureReason ?: @"";
  if (control) item.control = control;
  if (!item.active) { item.control = nil; [self.reservedPaths removeObjectForKey:@(downloadID)]; }
  [self changedSavingImmediately:created || previousState != state || !item.active];
}
- (NSString *)reserveDestinationForDownloadID:(NSUInteger)downloadID directory:(NSString *)directory fileName:(NSString *)name {
  if (self.reservedPaths[@(downloadID)]) return self.reservedPaths[@(downloadID)];
  name = name.lastPathComponent;
  if (!name.length || [@[@".", @"..", @"/"] containsObject:name]) name = @"Download";
  NSString *path = [directory stringByAppendingPathComponent:name];
  NSUInteger suffix = 1;
  while ([NSFileManager.defaultManager fileExistsAtPath:path] || [self.reservedPaths.allValues containsObject:path]) {
    NSString *ext = name.pathExtension;
    path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%lu)%@%@", name.stringByDeletingPathExtension,
      (unsigned long)suffix++, ext.length ? @"." : @"", ext]];
  }
  self.reservedPaths[@(downloadID)] = path;
  return path;
}
- (void)releaseDestinationForDownloadID:(NSUInteger)downloadID { [self.reservedPaths removeObjectForKey:@(downloadID)]; }
- (void)performAction:(TLBrowserDownloadAction)action forDownload:(TLBrowserDownload *)item {
  if (![self.items containsObject:item] || !item.controllable) return;
  if (action == TLBrowserDownloadActionPause && item.state != TLBrowserDownloadStateDownloading) return;
  if (action == TLBrowserDownloadActionResume && item.state != TLBrowserDownloadStatePaused) return;
  item.control(action); // State changes only when WebKit confirms them.
}
- (void)removeDownload:(TLBrowserDownload *)item {
  if (item.active) return;
  [self.items removeObject:item]; [self changedSavingImmediately:YES];
}
- (void)clearFinishedDownloads {
  NSIndexSet *finished = [self.items indexesOfObjectsPassingTest:^BOOL(TLBrowserDownload *item, NSUInteger index, BOOL *stop) { return !item.active; }];
  [self.items removeObjectsAtIndexes:finished]; [self changedSavingImmediately:YES];
}
- (BOOL)hasActiveDownloadsForBrowser:(NSInteger)browserIdentifier {
  for (TLBrowserDownload *item in self.items) if (item.active && item.browserIdentifier == browserIdentifier) return YES;
  return NO;
}
- (void)browserClosed:(NSInteger)browserIdentifier {
  for (NSNumber *key in self.liveItems) {
    TLBrowserDownload *item = self.liveItems[key];
    if (item.browserIdentifier != browserIdentifier || !item.active) continue;
    item.state = TLBrowserDownloadStateFailed; item.failureReason = @"Browser closed before this download finished"; item.control = nil;
    [self.reservedPaths removeObjectForKey:key];
  }
  [self changedSavingImmediately:YES];
}
- (void)finishSession {
  for (TLBrowserDownload *item in self.items) {
    item.control = nil;
    if (item.active) { item.state = TLBrowserDownloadStateFailed; item.failureReason = @"Talaria closed before this download finished"; }
  }
  [self.liveItems removeAllObjects]; [self.reservedPaths removeAllObjects]; [self changedSavingImmediately:YES];
}
@end
