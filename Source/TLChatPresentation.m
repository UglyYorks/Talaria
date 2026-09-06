#import "TLChatPresentation.h"
@implementation TLChatPresentation
- (instancetype)init {
  if ((self = [super init])) {
    _messages = [NSMutableArray array];
    _messageRowViews = [NSMapTable strongToStrongObjectsMapTable];
    _messageRowSignatures = [NSMapTable strongToStrongObjectsMapTable];
    _messageMarkdownViews = [NSMapTable strongToStrongObjectsMapTable];
    _errorMessage = @"";
  }
  return self;
}
- (void)dealloc { [_slashCommandUpdateTimer invalidate]; }
@end
