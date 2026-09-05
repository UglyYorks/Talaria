#import "OpenRouterClient.h"
#import "OpenRouterParsing.h"
#import "OpenRouterRequestFactory.h"
#import "OpenRouterStream.h"
#import "OpenRouterSupport.h"

@interface TLOpenRouterClient ()

@property (nonatomic, strong) NSMutableSet<TLOpenRouterStream *> *activeStreams;

@end

@implementation TLOpenRouterClient

- (instancetype)init {
  self = [super init];
  if (self) {
    _activeStreams = [NSMutableSet set];
  }
  return self;
}

- (void)fetchModelCatalogueWithToken:(NSString *)token
                           completion:(TLOpenRouterModelCatalogueHandler)completion {
  NSURLRequest *request = TLOpenRouterMakeModelCatalogueRequest(token);
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    NSError *resultError = nil;
    NSArray<TLOpenRouterModel *> *models = nil;

    if (error) {
      resultError = TLOpenRouterError([NSString stringWithFormat:@"Could not load OpenRouter models: %@", error.localizedDescription]);
    } else {
      NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
      if (statusCode < 200 || statusCode >= 300) {
        NSString *body = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        resultError = TLOpenRouterError([NSString stringWithFormat:@"OpenRouter returned %ld while loading models: %@", (long)statusCode, body ?: @""]);
      } else if (data.length == 0) {
        resultError = TLOpenRouterError(@"OpenRouter returned an empty models response.");
      } else {
        models = TLParseOpenRouterModelsResponse(data, &resultError);
        if (!resultError && models.count == 0) {
          resultError = TLOpenRouterError(@"OpenRouter did not return any text models.");
        }
      }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      completion(models, resultError);
    });
  }];
  [task resume];
}

- (void)cancelChatWithRequestID:(NSString *)requestID {
  for (TLOpenRouterStream *stream in self.activeStreams.copy) {
    if ([stream.requestID isEqualToString:requestID]) [stream cancel];
  }
}

- (void)streamChatWithRequestID:(NSString *)requestID
                          token:(NSString *)token
                          model:(NSString *)model
                       messages:(NSArray<TLChatMessage *> *)messages
                          delta:(TLOpenRouterDeltaHandler)delta
                     completion:(TLOpenRouterCompletionHandler)completion {
  NSString *trimmedToken = TLOpenRouterTrim(token);
  NSString *trimmedModel = TLOpenRouterTrim(model);
  NSString *trimmedRequestID = TLOpenRouterTrim(requestID);

  NSError *validationError = TLOpenRouterValidateChatInput(trimmedToken, trimmedModel, trimmedRequestID, messages);
  if (validationError) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(validationError);
    });
    return;
  }

  NSError *requestError = nil;
  NSURLRequest *request = TLOpenRouterMakeChatRequest(trimmedToken, trimmedModel, messages, &requestError);
  if (!request) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(requestError);
    });
    return;
  }

  TLOpenRouterStream *stream = [[TLOpenRouterStream alloc] init];
  stream.requestID = trimmedRequestID;
  stream.request = request;
  stream.delta = delta;
  stream.completion = completion;
  __weak typeof(self) weakSelf = self;
  stream.releaseHandler = ^(TLOpenRouterStream *finishedStream) {
    [weakSelf.activeStreams removeObject:finishedStream];
  };

  [self.activeStreams addObject:stream];
  [stream start];
}

@end
