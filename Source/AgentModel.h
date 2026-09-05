#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLAgentModel : NSObject <NSCopying>

@property (nonatomic, copy) NSString *modelID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *modelDescription;
@property (nonatomic, copy) NSString *inputPrice;
@property (nonatomic, copy) NSString *outputPrice;

- (NSString *)displayTitle;
- (NSString *)detailText;

@end

NSArray<TLAgentModel *> *_Nullable TLParseHermesModelOptions(NSData *data, NSError **error);

NS_ASSUME_NONNULL_END
