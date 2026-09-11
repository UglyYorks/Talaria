#import "WebKitImageLoader.h"

static const NSUInteger TLImageMaximumBytes = 128*1024*1024;
static NSError *TLImageLoadError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.BrowserImage" code:3 userInfo:@{NSLocalizedDescriptionKey:message}];
}
@interface TLWebKitImageLoader () <NSURLSessionDataDelegate>
@property(nonatomic, copy) NSArray<NSHTTPCookie *> *cookies;
@property(nonatomic, copy) void (^completion)(NSData *,NSString *,NSError *);
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, copy) NSString *MIMEType;
@property(nonatomic, strong) NSError *failure;
@end
@implementation TLWebKitImageLoader
+ (void)loadURL:(NSURL *)URL cookies:(NSArray<NSHTTPCookie *> *)cookies completion:(void (^)(NSData *,NSString *,NSError *))completion {
  TLWebKitImageLoader *loader = [self new]; loader.cookies = cookies; loader.completion = completion; loader.data = [NSMutableData data];
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  configuration.HTTPCookieStorage = nil; configuration.URLCredentialStorage = nil; configuration.URLCache = nil;
  configuration.HTTPShouldSetCookies = NO; configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30;
  loader.session = [NSURLSession sessionWithConfiguration:configuration delegate:loader delegateQueue:nil];
  [[loader.session dataTaskWithRequest:[loader requestForURL:URL]] resume];
}
- (NSURLRequest *)requestForURL:(NSURL *)URL {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL]; request.HTTPShouldHandleCookies = NO;
  NSMutableArray *matching = [NSMutableArray array];
  NSString *host = URL.host.lowercaseString, *path = URL.path.length ? URL.path : @"/";
  for (NSHTTPCookie *cookie in self.cookies) {
    NSString *domain = cookie.domain.lowercaseString;
    BOOL subdomains = [domain hasPrefix:@"."]; if (subdomains) domain = [domain substringFromIndex:1];
    BOOL hostMatches = [host isEqual:domain] || (subdomains && [host hasSuffix:[@"." stringByAppendingString:domain]]);
    NSString *cookiePath = cookie.path.length ? cookie.path : @"/";
    BOOL pathMatches = [path isEqual:cookiePath] || ([path hasPrefix:cookiePath] && ([cookiePath hasSuffix:@"/"] || (path.length > cookiePath.length && [path characterAtIndex:cookiePath.length] == '/')));
    if (hostMatches && pathMatches && (!cookie.secure || [URL.scheme.lowercaseString isEqual:@"https"]) &&
        (!cookie.expiresDate || cookie.expiresDate.timeIntervalSinceNow > 0)) [matching addObject:cookie];
  }
  [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:matching]];
  return request;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
  NSURL *URL = request.URL;
  if (![@[@"http",@"https"] containsObject:URL.scheme.lowercaseString] || !URL.host.length) {
    self.failure = TLImageLoadError(@"The image redirected to an unsupported address."); completionHandler(nil); [task cancel]; return;
  }
  // Reconstruct, rather than reuse, the redirected request. A Cookie or
  // Authorization header belonging to the old origin must never follow it.
  completionHandler([self requestForURL:URL]);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
  if (([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode >= 400) || response.expectedContentLength > (int64_t)TLImageMaximumBytes) {
    self.failure = TLImageLoadError(response.expectedContentLength > (int64_t)TLImageMaximumBytes ? @"This image is too large." : @"The image request failed.");
    completionHandler(NSURLSessionResponseCancel); return;
  }
  self.MIMEType = response.MIMEType; completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
  if (data.length > TLImageMaximumBytes-self.data.length) { self.failure = TLImageLoadError(@"This image is too large."); [task cancel]; return; }
  [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  void (^completion)(NSData *,NSString *,NSError *) = self.completion; self.completion = nil;
  NSError *failure = self.failure ?: error;
  NSData *data = failure ? nil : self.data; NSString *MIMEType = self.MIMEType;
  [self.session finishTasksAndInvalidate]; self.session = nil;
  if (completion) dispatch_async(dispatch_get_main_queue(),^{ completion(data,MIMEType,failure); });
}
@end
