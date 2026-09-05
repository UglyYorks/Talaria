#import "TLFeatureTabController.h"
#import "Database.h"
#import "ChromiumBrowserController.h"

@class TLAgentOrchestrator;
NS_ASSUME_NONNULL_BEGIN
@interface TLBrowserTabController : TLFeatureTabController
@property (nonatomic, strong, readonly, nullable) NSImage *favicon;
@property (nonatomic, copy, nullable) void (^metadataChangedHandler)(NSString *title, NSURL *URL);
@property (nonatomic, copy, nullable) void (^faviconChangedHandler)(void);
@property (nonatomic, copy, nullable) TLChromiumBrowserLinkHandler linkHandler;
@property (nonatomic, copy, nullable) TLAppSettings * _Nullable (^settingsProvider)(void);
@property (nonatomic, copy, nullable) void (^settingsRequiredHandler)(void);
- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                 inputWidth:(CGFloat)inputWidth;
- (instancetype)initWithURL:(NSURL *)URL palette:(TLThemePalette *)palette
                  database:(TLDatabase *)database orchestrator:(TLAgentOrchestrator *)orchestrator
                inputWidth:(CGFloat)inputWidth browserService:(TLChromiumBrowserController *)browserService;
- (void)startInWindow:(nullable NSWindow *)window;
- (void)setAddressInputWidth:(CGFloat)width;
@end
NS_ASSUME_NONNULL_END
