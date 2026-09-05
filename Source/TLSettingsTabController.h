#import "TLFeatureTabController.h"
#import "Database.h"

@class TLAgentOrchestrator;
NS_ASSUME_NONNULL_BEGIN
@interface TLSettingsTabController : TLFeatureTabController
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
@property (nonatomic, copy, nullable) void (^onboardingHandler)(void);
@property (nonatomic, copy, nullable) void (^settingsSavedHandler)(TLAppSettings *settings);
@property (nonatomic, copy, nullable) void (^errorHandler)(NSString *message);
- (instancetype)initWithSettings:(TLAppSettings *)settings
                       database:(TLDatabase *)database
                   orchestrator:(TLAgentOrchestrator *)orchestrator
                        palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
