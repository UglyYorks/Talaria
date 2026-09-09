#import "TLAgentProtocol.h"

static void TLProtocolError(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"Talaria.AgentProtocol" code:1
                                    userInfo:@{NSLocalizedDescriptionKey:message}];
}

@implementation TLAgentFrameDecoder {
  NSMutableData *_buffer;
  NSUInteger _scanOffset;
  BOOL _failed;
}
- (instancetype)init {
  if ((self = [super init])) { _buffer = [NSMutableData data]; _requestID = @""; }
  return self;
}
- (NSArray<NSDictionary *> *)appendData:(NSData *)data error:(NSError **)error {
  if (_failed) { TLProtocolError(error, @"The agent response decoder is closed."); return nil; }
  [_buffer appendData:data];
  NSMutableArray *events = [NSMutableArray array];
  const unsigned char *bytes = _buffer.bytes;
  NSUInteger consumed = 0;
  for (NSUInteger index = _scanOffset; index < _buffer.length; index++) {
    if (bytes[index] != '\n') continue;
    if (index > consumed) {
      NSData *line = [_buffer subdataWithRange:NSMakeRange(consumed, index - consumed)];
      id value = [NSJSONSerialization JSONObjectWithData:line options:0 error:error];
      if (![value isKindOfClass:NSDictionary.class]) {
        TLProtocolError(error, @"Agent VM returned an invalid response."); _failed = YES; return nil;
      }
      NSMutableDictionary *event = [value mutableCopy];
      NSString *type = event[@"type"];
      if (![@[@"delta", @"result", @"models", @"complete", @"error"] containsObject:type]) {
        TLProtocolError(error, @"Agent VM returned an unknown response event."); _failed = YES; return nil;
      }
      id requestID = event[@"request_id"];
      if (requestID && (![requestID isKindOfClass:NSString.class] ||
          (self.requestID.length && ![requestID isEqual:self.requestID]))) {
        TLProtocolError(error, @"Agent VM returned a response for another request."); _failed = YES; return nil;
      }
      if ([type isEqual:@"result"] && ![event[@"result"] isKindOfClass:NSDictionary.class]) {
        TLProtocolError(error, @"Hermes returned invalid result data."); _failed = YES; return nil;
      }
      if ([type isEqual:@"delta"]) {
        if (![requestID isKindOfClass:NSString.class] || ![requestID length]) {
          TLProtocolError(error, @"Agent delta has no request identity."); _failed = YES; return nil;
        }
        if (![event[@"kind"] isKindOfClass:NSString.class]) {
          TLProtocolError(error, @"Agent VM returned an invalid delta kind."); _failed = YES; return nil;
        }
        BOOL structured = [@[@"approval", @"tool_activity"] containsObject:event[@"kind"]];
        if (structured) {
          id payload = event[@"payload"];
          if (!payload && [event[@"text"] isKindOfClass:NSString.class]) {
            payload = [NSJSONSerialization JSONObjectWithData:[event[@"text"] dataUsingEncoding:NSUTF8StringEncoding]
                                                     options:0 error:nil];
          }
          if (![payload isKindOfClass:NSDictionary.class]) {
            TLProtocolError(error, @"Hermes returned invalid activity data."); _failed = YES; return nil;
          }
          event[@"payload"] = payload;
          [event removeObjectForKey:@"text"];
        } else if (![event[@"text"] isKindOfClass:NSString.class]) {
          TLProtocolError(error, @"Agent delta has invalid text."); _failed = YES; return nil;
        }
      }
      [events addObject:event];
    }
    consumed = index + 1;
  }
  _scanOffset = _buffer.length - consumed;
  if (consumed) [_buffer replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
  return events;
}
@end

@implementation TLAgentJSONResult {
  NSMutableString *_legacyText;
}
- (void)appendLegacyText:(NSString *)text {
  if (!_legacyText) _legacyText = [NSMutableString string];
  [_legacyText appendString:text];
}
- (NSDictionary *)finish:(NSError **)error {
  if (self.result) return self.result;
  id value = _legacyText.length ? [NSJSONSerialization JSONObjectWithData:[_legacyText dataUsingEncoding:NSUTF8StringEncoding]
                                                                options:0 error:error] : nil;
  if (![value isKindOfClass:NSDictionary.class]) {
    TLProtocolError(error, @"Hermes returned an invalid structured result."); return nil;
  }
  return value;
}
@end
