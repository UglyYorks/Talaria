#import "OpenRouterStream.h"
#import "OpenRouterParsing.h"
#import "OpenRouterSupport.h"

@interface TLOpenRouterStream ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, strong) NSMutableData *errorBody;
@property (nonatomic) NSInteger statusCode;
@property (nonatomic) BOOL receivedContent;
@property (nonatomic) BOOL receivedThinking;
@property (nonatomic) BOOL finished;

@end

@implementation TLOpenRouterStream

- (instancetype)init {
  self = [super init];
  if (self) {
    _buffer = [NSMutableData data];
    _errorBody = [NSMutableData data];
    _statusCode = 0;
  }
  return self;
}

- (void)start {
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
  configuration.timeoutIntervalForRequest = 60.0;
  self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[[NSOperationQueue alloc] init]];
  self.task = [self.session dataTaskWithRequest:self.request];
  [self.task resume];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  if ([response isKindOfClass:NSHTTPURLResponse.class]) {
    self.statusCode = ((NSHTTPURLResponse *)response).statusCode;
  }

  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
  if (self.statusCode < 200 || self.statusCode >= 300) {
    [self.errorBody appendData:data];
    return;
  }

  [self.buffer appendData:data];
  [self processBufferedLines];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  if (self.finished) {
    return;
  }

  if (error) {
    [self finishWithError:TLOpenRouterError([NSString stringWithFormat:@"Could not read OpenRouter stream: %@", error.localizedDescription])];
    return;
  }

  if (self.statusCode < 200 || self.statusCode >= 300) {
    [self finishWithError:[self httpErrorFromBody]];
    return;
  }

  if (self.receivedContent || self.receivedThinking) {
    [self finishWithError:nil];
  } else {
    [self finishWithError:TLOpenRouterError(@"OpenRouter returned an empty assistant message.")];
  }
}

- (void)processBufferedLines {
  while (true) {
    const unsigned char *bytes = self.buffer.bytes;
    NSUInteger length = self.buffer.length;
    NSUInteger newlineIndex = NSNotFound;

    for (NSUInteger index = 0; index < length; index += 1) {
      if (bytes[index] == '\n') {
        newlineIndex = index;
        break;
      }
    }

    if (newlineIndex == NSNotFound) {
      break;
    }

    NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineIndex)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, newlineIndex + 1) withBytes:NULL length:0];

    if (lineData.length > 0) {
      const unsigned char *lineBytes = lineData.bytes;
      if (lineBytes[lineData.length - 1] == '\r') {
        lineData = [lineData subdataWithRange:NSMakeRange(0, lineData.length - 1)];
      }
    }

    NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
    if (line) {
      [self processLine:line];
    }

    if (self.finished) {
      break;
    }
  }
}

- (void)processLine:(NSString *)line {
  if (![line hasPrefix:@"data:"]) {
    return;
  }

  NSString *data = TLOpenRouterTrim([line substringFromIndex:5]);
  if ([data isEqualToString:@"[DONE]"]) {
    [self finishWithError:nil];
    return;
  }

  NSError *error = nil;
  NSDictionary<NSString *, NSString *> *deltaParts = TLParseOpenRouterStreamDelta(data, &error);
  if (error) {
    [self finishWithError:error];
    return;
  }

  NSString *thinking = deltaParts[@"thinking"];
  if (thinking.length > 0) {
    self.receivedThinking = YES;
    [self emitKind:TLOpenRouterDeltaKindThinking text:thinking];
  }

  NSString *content = deltaParts[@"content"];
  if (content.length > 0) {
    self.receivedContent = YES;
    [self emitKind:TLOpenRouterDeltaKindContent text:content];
  }
}

- (void)emitKind:(TLOpenRouterDeltaKind)kind text:(NSString *)text {
  dispatch_async(dispatch_get_main_queue(), ^{
    self.delta(self.requestID, kind, text);
  });
}

- (NSError *)httpErrorFromBody {
  NSString *body = [[NSString alloc] initWithData:self.errorBody encoding:NSUTF8StringEncoding] ?: @"";
  NSString *message = body;

  NSData *jsonData = [body dataUsingEncoding:NSUTF8StringEncoding];
  if (jsonData.length > 0) {
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if ([json isKindOfClass:NSDictionary.class]) {
      NSDictionary *errorEnvelope = json[@"error"];
      NSString *envelopeMessage = [errorEnvelope isKindOfClass:NSDictionary.class] ? errorEnvelope[@"message"] : nil;
      if ([envelopeMessage isKindOfClass:NSString.class]) {
        message = envelopeMessage;
      }
    }
  }

  return TLOpenRouterError([NSString stringWithFormat:@"OpenRouter returned %ld: %@", (long)self.statusCode, message]);
}

- (void)cancel {
  [self finishWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}

- (void)finishWithError:(NSError *)error {
  @synchronized (self) {
    if (self.finished) return;
    self.finished = YES;
    [self.session invalidateAndCancel];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    self.completion(error);
    self.releaseHandler(self);
  });
}

@end
