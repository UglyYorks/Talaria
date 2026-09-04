#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TLDefaultModelID;
extern NSString * const TLDefaultSupportingModelID;
extern NSString * const TLRoleSystem;
extern NSString * const TLRoleUser;
extern NSString * const TLRoleAssistant;
extern NSString * const TLAgentGuestKindLinux;
extern NSString * const TLAgentRuntimePython;
extern NSString * const TLAgentStatusStopped;
extern NSString * const TLAgentStatusStarting;
extern NSString * const TLAgentStatusRunning;
extern NSString * const TLAgentStatusStopping;
extern NSString * const TLAgentStatusError;

typedef NS_ENUM(NSInteger, TLThemePreference) {
  TLThemePreferenceSystem = 0,
  TLThemePreferenceLight,
  TLThemePreferenceDark,
};

NSString *TLStringFromThemePreference(TLThemePreference preference);
TLThemePreference TLThemePreferenceFromString(NSString *value);
NSString *TLDisplayModelName(NSString *modelID);
NSString *TLDefaultChatIcon(void);
NSString *TLAgentDisplayGuestKind(NSString *guestKind);
NSString *TLAgentDisplayRuntime(NSString *runtime);
NSString *TLAgentDisplayStatus(NSString *status);

@interface TLChatMessage : NSObject <NSCopying>

@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy, nullable) NSString *thinking;

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content thinking:(nullable NSString *)thinking;
- (NSDictionary<NSString *, NSString *> *)requestDictionary;

@end

@interface TLStoredChatMessage : TLChatMessage

@property (nonatomic) NSInteger messageID;
@property (nonatomic, copy) NSString *createdAt;

@end

@interface TLChatSummary : NSObject <NSCopying>

@property (nonatomic) NSInteger chatID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *hermesSessionID;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;

@end

@interface TLChatRecord : TLChatSummary

@property (nonatomic, copy) NSArray<TLStoredChatMessage *> *messages;

@end

@interface TLAgentRecord : NSObject <NSCopying>

@property (nonatomic) NSInteger agentID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *guestKind;
@property (nonatomic, copy) NSString *runtime;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *vmDirectory;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;

@end

@interface TLAppSettings : NSObject <NSCopying>

@property (nonatomic, copy) NSString *openRouterToken;
@property (nonatomic) BOOL rememberOpenRouterToken;
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, copy) NSString *supportingModel;
@property (nonatomic) TLThemePreference theme;
@property (nonatomic) BOOL onboardingCompleted;

+ (instancetype)defaultSettings;

@end

NS_ASSUME_NONNULL_END
