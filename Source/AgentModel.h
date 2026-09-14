#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLAgentModel : NSObject <NSCopying>

@property (nonatomic, copy) NSString *modelID;
@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *modelDescription;
@property (nonatomic, copy) NSString *inputPrice;
@property (nonatomic, copy) NSString *outputPrice;

@property (nonatomic, copy) NSArray<NSString *> *thinkingLevels;
@property (nonatomic, copy) NSString *defaultThinkingLevel;
@property (nonatomic, copy) NSString *thinkingUnavailableReason;

- (NSString *)displayTitle;
- (NSString *)detailText;

@end

NSArray<TLAgentModel *> *_Nullable TLParseHermesModelOptions(NSData *data, NSError **error);

NS_ASSUME_NONNULL_END
