#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLInputSuggestions : NSObject
+ (nullable NSURL *)browserURLForInput:(NSString *)input;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)webSuggestionsForInput:(NSString *)input;
@end

NS_ASSUME_NONNULL_END
