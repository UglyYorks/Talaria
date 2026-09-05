#import "WorkspaceTabRuntime.h"

@implementation TLWorkspaceTabRuntime
- (void)dealloc { [_featureController close]; }

+ (instancetype)runtimeWithContentView:(NSView *)contentView
                            openAction:(SEL)openAction
                           closeAction:(SEL)closeAction {
  TLWorkspaceTabRuntime *runtime = [[self alloc] init];
  runtime.contentView = contentView;
  runtime.openAction = openAction;
  runtime.closeAction = closeAction;
  return runtime;
}
@end

NSString *TLWorkspaceTabRuntimeKey(TLWorkspaceTabKind kind, NSInteger tabID) {
  return [NSString stringWithFormat:@"%ld:%ld", (long)kind, (long)tabID];
}
