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
    _toolActivities = @[];
    _questions = @[];
    _sourceMessageID = @"";
    _sourceToolCallIDs = @[];
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  TLChatMessage *copy = [[[self class] allocWithZone:zone] init];
  copy.role = self.role;
  copy.content = self.content;
  copy.thinking = self.thinking;
  copy.thinkingActive = self.thinkingActive;
  copy.approvalRequest = self.approvalRequest;
  copy.approvalResponse = self.approvalResponse;
  copy.questions = self.questions;
  copy.toolActivities = self.toolActivities;
  copy.attachments = self.attachments;
  copy.sourceMessageID = self.sourceMessageID;
  copy.sourceToolCallIDs = self.sourceToolCallIDs;
  copy.notification = self.notification;
  return copy;
}

- (BOOL)applyToolActivity:(NSDictionary *)activity {
  if (![activity isKindOfClass:NSDictionary.class]) return NO;
  for (NSString *key in @[@"id", @"name", @"state"]) {
    if (![activity[key] isKindOfClass:NSString.class] || ![activity[key] length]) return NO;
  }
  if (![@[@"preparing", @"running", @"completed", @"failed"] containsObject:activity[@"state"]]) return NO;
  NSMutableDictionary *next = [NSMutableDictionary dictionary];
  for (NSString *key in @[@"id", @"name", @"state", @"detail", @"summary"]) {
    NSString *value = [activity[key] isKindOfClass:NSString.class] ? activity[key] : @"";
    next[key] = [value substringToIndex:MIN(value.length, 1000u)];
  }
  NSMutableArray *rows = [self.toolActivities mutableCopy];
  NSUInteger index = [rows indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger idx, BOOL *stop) {
    return [row[@"id"] isEqual:next[@"id"]];
  }];
  if (index == NSNotFound && ![next[@"state"] isEqual:@"preparing"]) {
    index = [rows indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger idx, BOOL *stop) {
      return [row[@"state"] isEqual:@"preparing"] && [row[@"name"] isEqual:next[@"name"]];
    }];
  }
  if (index != NSNotFound) {
    NSDictionary *previous = rows[index];
    // Replayed starts must not reopen completed calls.
    if ([@[@"completed", @"failed"] containsObject:previous[@"state"]] &&
        [@[@"preparing", @"running"] containsObject:next[@"state"]]) return NO;
    for (NSString *key in @[@"detail", @"summary"]) if (![next[key] length]) next[key] = previous[key] ?: @"";
    if ([previous isEqual:next]) return NO;
    rows[index] = [next copy];
  } else {
    [rows addObject:[next copy]];
  }
  // Keep the most recent activity without allowing long turns to grow the UI indefinitely.
  while (rows.count > 80) [rows removeObjectAtIndex:0];
  self.toolActivities = rows;
  return YES;
}

- (void)finishToolActivitiesWithState:(NSString *)state {
  NSMutableArray *rows = [NSMutableArray array];
  for (NSDictionary *row in self.toolActivities) {
    if ([@[@"preparing", @"running"] containsObject:row[@"state"]]) {
      NSMutableDictionary *finished = [row mutableCopy];
      finished[@"state"] = state;
      [rows addObject:[finished copy]];
    } else [rows addObject:row];
  }
  self.toolActivities = rows;
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
  copy.position = self.position;
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
    _sourceSessionID = @"";
    _continuationSessionID = @"";
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
  copy.sourceAgentID = self.sourceAgentID;
  copy.sourceSessionID = self.sourceSessionID;
  copy.continuationSessionID = self.continuationSessionID;
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

@implementation TLBookmark
- (instancetype)init {
  if ((self = [super init])) { _name = @""; _emoji = TLDefaultChatIcon(); }
  return self;
}
+ (NSURL *)normalizedURL:(NSString *)value {
  NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
  if ([text rangeOfString:@"://"].location == NSNotFound) text = [@"https://" stringByAppendingString:text];
  NSURL *URL = [NSURL URLWithString:text];
  return URL.host.length && [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString] && !URL.user && !URL.password ? URL : nil;
}
@end
@implementation TLBrowserHistoryEntry
@end

NSString *TLBrowserHistoryOrigin(NSURL *URL) {
  NSString *scheme = URL.scheme.lowercaseString;
  if (!URL.host.length || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) return nil;
  return [NSString stringWithFormat:@"%@://%@:%@", scheme, URL.host.lowercaseString,
          URL.port ?: ([scheme isEqualToString:@"https"] ? @443 : @80)];
}
