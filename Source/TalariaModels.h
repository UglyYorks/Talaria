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
// Presentation state while this process provisions Hermes; VM state remains stored separately.
extern NSString * const TLAgentStatusInitializing;
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

@interface TLBookmark : NSObject
@property (nonatomic) NSInteger bookmarkID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong, nullable) NSURL *URL;
@property (nonatomic) NSInteger chatID;
@property (nonatomic, copy) NSString *emoji;
@property (nonatomic, strong, nullable) NSData *faviconData;
+ (nullable NSURL *)normalizedURL:(NSString *)value;
@end

NSString * _Nullable TLBrowserHistoryOrigin(NSURL *URL);

@interface TLBrowserHistoryEntry : NSObject
@property (nonatomic) NSInteger visitID;
@property (nonatomic, copy) NSString *URLString;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *visitedAt;
@property (nonatomic, copy, nullable) NSData *faviconData;
@end

@interface TLChatMessage : NSObject <NSCopying>

@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy, nullable) NSString *thinking;
// Transient presentation state; never persisted or sent to the model.
@property (nonatomic) BOOL thinkingActive;
// Runtime-only structured approval state; never sent as model context or loaded as a live request from history.
@property (nonatomic, copy, nullable) NSDictionary *approvalRequest;
@property (nonatomic, copy, nullable) NSDictionary *approvalResponse;
// Bounded, runtime-only tool snapshots. Never used as model context or restored as running work.
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *toolActivities;
- (BOOL)applyToolActivity:(NSDictionary *)activity;
- (void)finishToolActivitiesWithState:(NSString *)state;
// JSON-compatible records: name, guestPath, directory. Originals are never exposed to the VM.
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *attachments;
// Durable Hermes identities; local SQLite message IDs are only cache keys.
@property (nonatomic, copy) NSString *sourceMessageID;
@property (nonatomic, copy) NSArray<NSString *> *sourceToolCallIDs;
@property (nonatomic, copy, nullable) NSDictionary *notification;

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content thinking:(nullable NSString *)thinking;
- (NSDictionary<NSString *, NSString *> *)requestDictionary;

@end

@interface TLStoredChatMessage : TLChatMessage
@property (nonatomic) NSInteger position;

@property (nonatomic) NSInteger messageID;
@property (nonatomic, copy) NSString *createdAt;

@end

@interface TLChatSummary : NSObject <NSCopying>

@property (nonatomic) NSInteger chatID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *supportingModel;
@property (nonatomic, copy) NSString *hermesSessionID;
@property (nonatomic) NSInteger sourceAgentID;
@property (nonatomic, copy) NSString *sourceSessionID;
@property (nonatomic, copy) NSString *continuationSessionID;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;

@end

@interface TLChatRecord : TLChatSummary

@property (nonatomic, copy) NSArray<TLStoredChatMessage *> *messages;

@end

@interface TLAgentRecord : NSObject <NSCopying>

@property (nonatomic) NSInteger agentID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *avatar;
@property (nonatomic, copy) NSString *soul;
@property (nonatomic, copy) NSArray<NSString *> *folderPaths;
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
