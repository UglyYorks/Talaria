#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// One host process owns an agent's shared writable filesystem at a time.
@interface TLAgentVMLock : NSObject
- (nullable instancetype)initWithDirectoryURL:(NSURL *)directoryURL error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
