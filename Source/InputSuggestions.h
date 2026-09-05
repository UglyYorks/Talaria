#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLInputSuggestions : NSObject
+ (nullable NSURL *)browserURLForInput:(NSString *)input;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)webSuggestionsForInput:(NSString *)input;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)hermesCommandsFromCatalogue:(NSDictionary *)catalogue;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsForInput:(NSString *)input commands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands;
@end

NS_ASSUME_NONNULL_END
