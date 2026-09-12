#import "UIComponents.h"
#import "MarkdownRenderer.h"
#import "TLQuestionRequest.h"

@interface TLBrowserChatPane : TLGlassPaneView
@property (nonatomic, readonly) NSButton *minimizeButton;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) TLMarkdownLinkHandler linkHandler;
@property (nonatomic, copy) TLMarkdownLinkContextMenuHandler linkContextMenuHandler;
@property (nonatomic, copy) BOOL (^approvalHandler)(NSString *requestID, NSString *choice);
- (void)showApprovalRequest:(NSDictionary *)request;
- (void)showQuestions:(NSArray<TLQuestionRequest *> *)questions;
- (void)showToolActivities:(NSArray<NSDictionary<NSString *, NSString *> *> *)activities;
@property (nonatomic, readonly, getter=isPresented) BOOL presented;
- (void)setPresented:(BOOL)presented animated:(BOOL)animated;
- (void)showMarkdown:(NSString *)markdown loading:(BOOL)loading;
@end
