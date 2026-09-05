#import <AppKit/AppKit.h>
#import "WorkspaceState.h"
#import "TLFeatureTabController.h"

NS_ASSUME_NONNULL_BEGIN
@interface TLWorkspaceTabRuntime : NSObject
@property (nonatomic, strong, nullable) NSView *contentView;
@property (nonatomic, strong, nullable) TLFeatureTabController *featureController;
@property (nonatomic) SEL openAction;
@property (nonatomic) SEL closeAction;
+ (instancetype)runtimeWithContentView:(nullable NSView *)contentView
                            openAction:(SEL)openAction
                           closeAction:(SEL)closeAction;
@end
FOUNDATION_EXPORT NSString *TLWorkspaceTabRuntimeKey(TLWorkspaceTabKind kind, NSInteger tabID);
NS_ASSUME_NONNULL_END
