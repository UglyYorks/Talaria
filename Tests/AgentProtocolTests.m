#import <Foundation/Foundation.h>
#import "TLAgentProtocol.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@",message); exit(1); } }
int main(void) { @autoreleasepool {
  NSString *wire = @"{\"type\":\"delta\",\"request_id\":\"r\",\"kind\":\"content\",\"text\":\"🦊 hi\"}\n{\"type\":\"result\",\"request_id\":\"r\",\"result\":{\"items\":[1,2]}}\n{\"type\":\"complete\"}\n";
  NSData *data = [wire dataUsingEncoding:NSUTF8StringEncoding];
  for (NSUInteger split=0;split<=data.length;split++) {
    TLAgentFrameDecoder *decoder = [TLAgentFrameDecoder new]; decoder.requestID = @"r";
    NSMutableArray *frames = [NSMutableArray array]; NSError *error;
    NSArray *first = [decoder appendData:[data subdataWithRange:NSMakeRange(0,split)] error:&error];
    Check(first != nil, @"valid prefix"); [frames addObjectsFromArray:first];
    NSArray *last = [decoder appendData:[data subdataWithRange:NSMakeRange(split,data.length-split)] error:&error];
    Check(last != nil, @"valid suffix"); [frames addObjectsFromArray:last];
    Check(frames.count == 3 && [frames[0][@"text"] isEqual:@"🦊 hi"], @"every split preserves Unicode and frame ordering");
  }
  for (NSString *invalid in @[@"[]\n", @"{\"type\":\"result\",\"result\":[]}\n", @"{\"type\":\"complete\",\"request_id\":\"wrong\"}\n"]) {
    TLAgentFrameDecoder *decoder = [TLAgentFrameDecoder new]; decoder.requestID = @"r"; NSError *error;
    Check([decoder appendData:[invalid dataUsingEncoding:NSUTF8StringEncoding] error:&error] == nil && error != nil, @"malformed and foreign frames fail");
  }
  TLAgentJSONResult *result = [TLAgentJSONResult new]; [result appendLegacyText:@"{\"items\":" ]; [result appendLegacyText:@"[1,2]}"];
  Check([[result finish:nil][@"items"] count] == 2, @"old guest result adaptation");
  result.result = @{@"new":@YES}; Check([[result finish:nil][@"new"] boolValue], @"structured result avoids text parsing");
  NSLog(@"AgentProtocolTests passed");
} return 0; }
