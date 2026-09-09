#import "TLFeatureTabController.h"
#import "Database.h"
#import "TLBrowserPreferences.h"
#import "TLApplicationPreferences.h"

@class TLAgentOrchestrator;
NS_ASSUME_NONNULL_BEGIN
@interface TLSettingsTabController : TLFeatureTabController
@property (nonatomic, strong) id<TLBrowserPreferencesService> browserPreferences;
@property (nonatomic, strong) TLApplicationPreferences *applicationPreferences;
@property (nonatomic, copy, nullable) void (^onboardingHandler)(void);
@property (nonatomic, copy, nullable) void (^settingsSavedHandler)(TLAppSettings *settings);
@property (nonatomic, copy, nullable) void (^skillsSavedHandler)(NSInteger agentID);
@property (nonatomic, copy, nullable) void (^errorHandler)(NSString *message);
- (void)refreshPluginsForSelectedAgent;
- (instancetype)initWithSettings:(TLAppSettings *)settings
                       database:(TLDatabase *)database
                   orchestrator:(TLAgentOrchestrator *)orchestrator
                        palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
