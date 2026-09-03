#import <Foundation/Foundation.h>
#import "TalariaModels.h"

NS_ASSUME_NONNULL_BEGIN

BOOL TLWidgetbookModeEnabled(void);
NSURL *_Nullable TLWidgetbookBrowserURL(void);
TLChatRecord *TLWidgetbookChat(void);
NSArray<TLChatSummary *> *TLWidgetbookChats(void);

NS_ASSUME_NONNULL_END
