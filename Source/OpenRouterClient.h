#import <Foundation/Foundation.h>
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLOpenRouterDeltaKind) {
  TLOpenRouterDeltaKindContent = 0,
  TLOpenRouterDeltaKindThinking,
};

@class TLOpenRouterModel;

typedef void (^TLOpenRouterDeltaHandler)(NSString *requestID, TLOpenRouterDeltaKind kind, NSString *text);
typedef void (^TLOpenRouterCompletionHandler)(NSError *_Nullable error);
typedef void (^TLOpenRouterModelCatalogueHandler)(NSArray<TLOpenRouterModel *> *_Nullable models, NSError *_Nullable error);

@interface TLOpenRouterModel : NSObject <NSCopying>

@property (nonatomic, copy) NSString *modelID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *modelDescription;
@property (nonatomic) NSInteger contextLength;
@property (nonatomic, copy) NSString *promptPrice;
@property (nonatomic, copy) NSString *completionPrice;

- (NSString *)displayTitle;
- (NSString *)detailText;

@end

@interface TLOpenRouterClient : NSObject

- (void)fetchModelCatalogueWithToken:(NSString *)token
                           completion:(TLOpenRouterModelCatalogueHandler)completion;

- (void)cancelChatWithRequestID:(NSString *)requestID;

- (void)streamChatWithRequestID:(NSString *)requestID
                          token:(NSString *)token
                          model:(NSString *)model
                       messages:(NSArray<TLChatMessage *> *)messages
                         delta:(TLOpenRouterDeltaHandler)delta
                     completion:(TLOpenRouterCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END
