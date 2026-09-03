#import <AppKit/AppKit.h>
#import "WorkspaceState.h"

NS_ASSUME_NONNULL_BEGIN

@class TLChromiumBrowserSession;
@class TLBrowserConversation, TLBrowserChatPane;

@interface TLWorkspaceTabRuntime : NSObject

@property (nonatomic, strong, nullable) NSView *contentView;
@property (nonatomic, strong, nullable) NSView *browserHostView;
@property (nonatomic, strong, nullable) NSView *browserAddressInput;
@property (nonatomic, strong, nullable) NSLayoutConstraint *browserAddressInputWidthConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *browserHostBottomConstraint;
@property (nonatomic, strong, nullable) NSImage *browserFavicon;
@property (nonatomic) BOOL browserUsesReducedHeight;
@property (nonatomic) SEL openAction;
@property (nonatomic) SEL closeAction;
@property (nonatomic, strong, nullable) TLChromiumBrowserSession *browserSession;
@property (nonatomic, strong, nullable) TLBrowserConversation *browserConversation;
@property (nonatomic, strong, nullable) TLBrowserChatPane *browserChatPane;

- (void)setBrowserBottomInset:(CGFloat)inset duration:(NSTimeInterval)duration overshoot:(CGFloat)overshoot;

+ (instancetype)runtimeWithContentView:(nullable NSView *)contentView
                            openAction:(SEL)openAction
                           closeAction:(SEL)closeAction;

@end

FOUNDATION_EXPORT NSString *TLWorkspaceTabRuntimeKey(TLWorkspaceTabKind kind, NSInteger tabID);

NS_ASSUME_NONNULL_END
