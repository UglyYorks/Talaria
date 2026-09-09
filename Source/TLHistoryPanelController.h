#import <AppKit/AppKit.h>
#import "TalariaModels.h"
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLHistoryFilter) {
  TLHistoryFilterAll,
  TLHistoryFilterChats,
  TLHistoryFilterBrowsing,
};

@class TLHistoryPanelController;
@class TLTokenView;

@protocol TLHistoryPanelControllerDelegate <NSObject>
- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectChatID:(NSInteger)chatID;
- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteChatID:(NSInteger)chatID;
@optional
- (void)historyPanelController:(TLHistoryPanelController *)controller didSelectBrowserURL:(NSURL *)URL;
- (void)historyPanelController:(TLHistoryPanelController *)controller didRequestDeleteBrowserVisitID:(NSInteger)visitID;
- (void)historyPanelControllerDidRequestRefresh:(TLHistoryPanelController *)controller;
@end

@interface TLHistoryPanelController : NSObject

@property (nonatomic, strong, readonly) TLTokenView *panelView;
@property (nonatomic, copy) NSArray<TLChatSummary *> *chats;
@property (nonatomic, copy) NSArray<TLBrowserHistoryEntry *> *browsingHistory;
@property (nonatomic) TLHistoryFilter filter;
@property (nonatomic, copy) NSString *browsingStatusMessage;
@property (nonatomic, weak, nullable) id<TLHistoryPanelControllerDelegate> delegate;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *searchPreviews;

- (instancetype)initWithPalette:(TLThemePalette *)palette;
- (void)applyPalette:(TLThemePalette *)palette;
- (void)reloadData;
- (void)deselectAll;
- (void)selectChatWithID:(NSInteger)chatID;

@end

NS_ASSUME_NONNULL_END
