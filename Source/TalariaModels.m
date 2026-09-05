#import "TalariaModels.h"

NSString * const TLDefaultModelID = @"z-ai/glm-5.2";
NSString * const TLDefaultSupportingModelID = @"openrouter/auto";
NSString * const TLRoleSystem = @"system";
NSString * const TLRoleUser = @"user";
NSString * const TLRoleAssistant = @"assistant";
NSString * const TLAgentGuestKindLinux = @"linux";
NSString * const TLAgentRuntimePython = @"python";
NSString * const TLAgentStatusStopped = @"stopped";
NSString * const TLAgentStatusInitializing = @"initializing";
NSString * const TLAgentStatusStarting = @"starting";
NSString * const TLAgentStatusRunning = @"running";
NSString * const TLAgentStatusStopping = @"stopping";
NSString * const TLAgentStatusError = @"error";

NSString *TLStringFromThemePreference(TLThemePreference preference) {
  switch (preference) {
    case TLThemePreferenceLight:
      return @"light";
    case TLThemePreferenceDark:
      return @"dark";
    case TLThemePreferenceSystem:
    default:
      return @"system";
  }
}

TLThemePreference TLThemePreferenceFromString(NSString *value) {
  if ([value isEqualToString:@"light"]) {
    return TLThemePreferenceLight;
  }

  if ([value isEqualToString:@"dark"]) {
    return TLThemePreferenceDark;
  }

  return TLThemePreferenceSystem;
}

NSString *TLDisplayModelName(NSString *modelID) {
  return [modelID isEqualToString:TLDefaultModelID] ? @"GLM 5.2" : modelID;
}

NSString *TLDefaultChatIcon(void) {
  return @"\U0001F4AC";
}

NSString *TLAgentDisplayGuestKind(NSString *guestKind) {
  if ([guestKind isEqualToString:TLAgentGuestKindLinux]) {
    return @"Linux";
  }

  return guestKind.length > 0 ? guestKind : @"Unknown";
}

NSString *TLAgentDisplayRuntime(NSString *runtime) {
  if ([runtime isEqualToString:TLAgentRuntimePython]) {
    return @"Python";
  }

  return runtime.length > 0 ? runtime : @"Unknown";
}

NSString *TLAgentDisplayStatus(NSString *status) {
  if ([status isEqualToString:TLAgentStatusInitializing]) return @"Initializing";
  if ([status isEqualToString:TLAgentStatusStopped]) {
    return @"Stopped";
  }
  if ([status isEqualToString:TLAgentStatusStarting]) {
    return @"Starting";
  }
  if ([status isEqualToString:TLAgentStatusRunning]) {
    return @"Running";
  }
  if ([status isEqualToString:TLAgentStatusStopping]) {
    return @"Stopping";
  }
  if ([status isEqualToString:TLAgentStatusError]) {
    return @"Error";
  }

  return status.length > 0 ? status : @"Unknown";
}

@implementation TLChatMessage

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content thinking:(NSString *)thinking {
  TLChatMessage *message = [[self alloc] init];
  message.role = role;
  message.content = content;
  message.thinking = thinking;
  return message;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _role = [TLRoleUser copy];
    _content = @"";
    _attachments = @[];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLChatMessage *copy = [[[self class] allocWithZone:zone] init];
  copy.role = self.role;
  copy.content = self.content;
  copy.thinking = self.thinking;
  copy.attachments = self.attachments;
  return copy;
}

- (NSDictionary<NSString *, NSString *> *)requestDictionary {
  return @{
    @"role": self.role,
    @"content": self.content,
  };
}

@end

@implementation TLStoredChatMessage

- (instancetype)init {
  self = [super init];
  if (self) {
    _createdAt = @"";
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLStoredChatMessage *copy = [super copyWithZone:zone];
  copy.messageID = self.messageID;
  copy.createdAt = self.createdAt;
  return copy;
}

@end

@implementation TLChatSummary

- (instancetype)init {
  self = [super init];
  if (self) {
    _title = @"New chat";
    _icon = @"";
    _model = [TLDefaultModelID copy];
    _supportingModel = [TLDefaultSupportingModelID copy];
    _hermesSessionID = @"";
    _createdAt = @"";
    _updatedAt = @"";
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLChatSummary *copy = [[[self class] allocWithZone:zone] init];
  copy.chatID = self.chatID;
  copy.title = self.title;
  copy.icon = self.icon;
  copy.model = self.model;
  copy.supportingModel = self.supportingModel;
  copy.hermesSessionID = self.hermesSessionID;
  copy.createdAt = self.createdAt;
  copy.updatedAt = self.updatedAt;
  return copy;
}

@end

@implementation TLChatRecord

- (instancetype)init {
  self = [super init];
  if (self) {
    _messages = @[];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLChatRecord *copy = [super copyWithZone:zone];
  copy.messages = [[NSArray alloc] initWithArray:self.messages copyItems:YES];
  return copy;
}

@end

@implementation TLAgentRecord

- (instancetype)init {
  self = [super init];
  if (self) {
    _name = @"Agent";
    _avatar = @"🤖";
    _soul = @"";
    _folderPaths = @[];
    _guestKind = [TLAgentGuestKindLinux copy];
    _runtime = [TLAgentRuntimePython copy];
    _status = [TLAgentStatusStopped copy];
    _vmDirectory = @"";
    _createdAt = @"";
    _updatedAt = @"";
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLAgentRecord *copy = [[[self class] allocWithZone:zone] init];
  copy.agentID = self.agentID;
  copy.name = self.name;
  copy.avatar = self.avatar;
  copy.soul = self.soul;
  copy.folderPaths = self.folderPaths;
  copy.guestKind = self.guestKind;
  copy.runtime = self.runtime;
  copy.status = self.status;
  copy.vmDirectory = self.vmDirectory;
  copy.lastError = self.lastError;
  copy.createdAt = self.createdAt;
  copy.updatedAt = self.updatedAt;
  return copy;
}

@end

@implementation TLAppSettings

+ (instancetype)defaultSettings {
  TLAppSettings *settings = [[self alloc] init];
  settings.openRouterToken = @"";
  settings.rememberOpenRouterToken = NO;
  settings.selectedModel = TLDefaultModelID;
  settings.supportingModel = TLDefaultSupportingModelID;
  settings.theme = TLThemePreferenceSystem;
  settings.onboardingCompleted = NO;
  return settings;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _openRouterToken = @"";
    _rememberOpenRouterToken = NO;
    _selectedModel = [TLDefaultModelID copy];
    _supportingModel = [TLDefaultSupportingModelID copy];
    _theme = TLThemePreferenceSystem;
    _onboardingCompleted = NO;
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLAppSettings *copy = [[[self class] allocWithZone:zone] init];
  copy.openRouterToken = self.openRouterToken;
  copy.rememberOpenRouterToken = self.rememberOpenRouterToken;
  copy.selectedModel = self.selectedModel;
  copy.supportingModel = self.supportingModel;
  copy.theme = self.theme;
  copy.onboardingCompleted = self.onboardingCompleted;
  return copy;
}

@end
