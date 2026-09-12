#import "TLQuestionRequest.h"

@implementation TLQuestionRequest {
  NSDictionary *_content;
  void (^_response)(NSString *);
  NSString *_status;
}
- (instancetype)initWithPresentation:(NSDictionary *)presentation response:(void (^)(NSString *))response {
  if ((self = [super init])) { _content = [presentation copy]; _response = [response copy]; _pending = YES; }
  return self;
}
- (NSDictionary *)presentation {
  NSMutableDictionary *value = [_content mutableCopy];
  value[@"submitted"] = @(!self.pending);
  if (_status.length) value[@"status"] = _status;
  return value;
}
- (BOOL)respondWithOption:(NSString *)option {
  NSAssert(NSThread.isMainThread, @"Question responses belong to the main thread");
  if (!self.pending || !_response) return NO;
  NSDictionary *selected = nil;
  for (NSDictionary *candidate in _content[@"options"]) if ([candidate[@"id"] isEqual:option]) selected = candidate;
  if (!selected) return NO;
  void (^response)(NSString *) = _response;
  [self finishWithStatus:[NSString stringWithFormat:@"Selected: %@", selected[@"title"]]];
  response(option);
  return YES;
}
- (void)finishWithStatus:(NSString *)status {
  NSAssert(NSThread.isMainThread, @"Question state belongs to the main thread");
  if (!self.pending) return;
  _pending = NO;
  _response = nil;
  _status = [status copy];
  if (self.changeHandler) self.changeHandler();
}
@end
