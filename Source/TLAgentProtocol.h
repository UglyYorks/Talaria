#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// The worker wire format is independent of VM connections and UI ownership.
@interface TLAgentFrameDecoder : NSObject
@property (nonatomic, copy) NSString *requestID;
- (nullable NSArray<NSDictionary *> *)appendData:(NSData *)data error:(NSError **)error;
@end

// One adapter for older installed guests that return a JSON result as content.
// New bundled guests send a structured result frame directly.
@interface TLAgentJSONResult : NSObject
@property (nonatomic, copy, nullable) NSDictionary *result;
- (void)appendLegacyText:(NSString *)text;
- (nullable NSDictionary *)finish:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
