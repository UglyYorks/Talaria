#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TLOpenRouterErrorDomain;

NSError *TLOpenRouterError(NSString *message);
NSString *TLOpenRouterTrim(NSString *_Nullable value);
NSString *_Nullable TLOpenRouterNonEmpty(NSString *_Nullable value);
NSString *_Nullable TLOpenRouterStringValue(id _Nullable value);
NSInteger TLOpenRouterIntegerValue(id _Nullable value);

NS_ASSUME_NONNULL_END
