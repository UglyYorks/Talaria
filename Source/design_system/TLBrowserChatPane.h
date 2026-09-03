#import "UIComponents.h"
#import "MarkdownRenderer.h"

@interface TLBrowserChatPane : TLGlassPaneView
@property (nonatomic, readonly) NSButton *minimizeButton;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) TLMarkdownLinkHandler linkHandler;
@property (nonatomic, readonly, getter=isPresented) BOOL presented;
- (void)setPresented:(BOOL)presented animated:(BOOL)animated;
- (void)showMarkdown:(NSString *)markdown loading:(BOOL)loading;
@end
