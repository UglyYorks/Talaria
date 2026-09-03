#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLStreamingBlockBuffer : NSObject

@property (nonatomic, readonly, copy) NSString *committedText;

- (NSString *)appendText:(NSString *)text;
- (NSString *)flush;

@end

NS_ASSUME_NONNULL_END
