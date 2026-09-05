#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TLTabCommand) {
  TLTabCommandNone = 0,
  TLTabCommandNew,
  TLTabCommandClose,
  TLTabCommandReopen,
  TLTabCommandNext,
  TLTabCommandPrevious,
  TLTabCommandCloseWindow,
  TLTabCommandMoveLeft,
  TLTabCommandMoveRight,
  TLTabCommandSelectFirst = 101,
  TLTabCommandSelectLast = 109,
};

FOUNDATION_EXPORT TLTabCommand TLTabCommandForEvent(NSEvent *event);
FOUNDATION_EXPORT BOOL TLTabCommandAllowsRepeat(TLTabCommand command);
FOUNDATION_EXPORT NSMenu *TLCreateTabMenu(id target, SEL action);
NS_ASSUME_NONNULL_END
