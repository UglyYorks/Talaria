#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLPromptImportance) {
  TLPromptImportanceRequired = 1,
  TLPromptImportanceUseful = 2,
  TLPromptImportanceOptional = 3,
};

typedef NS_ENUM(NSInteger, TLPromptCompactionStrategy) {
  TLPromptCompactionStrategyWhole = 0,
  TLPromptCompactionStrategyKeepStart,
  TLPromptCompactionStrategyKeepEnd,
};

@interface TLCompactedPromptPart : NSObject

@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSString *originalContent;
@property (nonatomic) TLPromptImportance importance;
@property (nonatomic) TLPromptCompactionStrategy strategy;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) NSUInteger removedCharacters;
@property (nonatomic) BOOL removed;

@end

@interface TLCompactedPrompt : NSObject

@property (nonatomic, copy) NSString *prompt;
@property (nonatomic, strong, nullable) NSNumber *limit;
@property (nonatomic) NSUInteger length;
@property (nonatomic) NSUInteger originalLength;
@property (nonatomic) BOOL wasCompacted;
@property (nonatomic, copy) NSArray<TLCompactedPromptPart *> *parts;

@end

@interface TLPromptBuilder : NSObject

- (instancetype)init;
- (instancetype)initWithLimit:(nullable NSNumber *)limit separator:(NSString *)separator NS_DESIGNATED_INITIALIZER;
- (instancetype)addPartWithContent:(NSString *)content
                        importance:(TLPromptImportance)importance
                          strategy:(TLPromptCompactionStrategy)strategy
                              name:(nullable NSString *)name;
- (instancetype)withLimit:(nullable NSNumber *)limit;
- (NSString *)build;
- (TLCompactedPrompt *)compact;
- (instancetype)clear;

@end

NS_ASSUME_NONNULL_END
