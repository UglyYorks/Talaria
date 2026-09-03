#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

@class TLHistoryPanelController;
@class TLTokenView;

@protocol TLHistoryPanelControllerDelegate <NSObject>
- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectChatID:(NSInteger)chatID;
- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteChatID:(NSInteger)chatID;
@end

@interface TLHistoryPanelController : NSObject

@property (nonatomic, strong, readonly) TLTokenView *panelView;
@property (nonatomic, copy) NSArray<TLChatSummary *> *chats;
@property (nonatomic, weak, nullable) id<TLHistoryPanelControllerDelegate> delegate;
@property (nonatomic) BOOL enabled;

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
- (void)reloadData;
- (void)deselectAll;
- (void)selectChatWithID:(NSInteger)chatID;

@end

NS_ASSUME_NONNULL_END
