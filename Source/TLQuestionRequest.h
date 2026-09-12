#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// A live, native question. Only its presentation is serializable; a restored
// transcript can never restore the authority to answer it.
@interface TLQuestionRequest : NSObject
@property (nonatomic, readonly) NSDictionary *presentation;
@property (nonatomic, readonly) BOOL pending;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);
- (instancetype)initWithPresentation:(NSDictionary *)presentation response:(void (^)(NSString *option))response;
- (BOOL)respondWithOption:(NSString *)option;
- (void)finishWithStatus:(NSString *)status;
@end
NS_ASSUME_NONNULL_END
