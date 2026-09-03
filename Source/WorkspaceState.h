#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLWorkspaceTabKind) {
  TLWorkspaceTabKindChat,
  TLWorkspaceTabKindHistory,
  TLWorkspaceTabKindBrowser,
  TLWorkspaceTabKindSettings,
  TLWorkspaceTabKindAgents,
  TLWorkspaceTabKindNotes,
};

@interface TLWorkspaceTab : NSObject <NSCopying>

@property (nonatomic) TLWorkspaceTabKind kind;
@property (nonatomic) NSInteger tabID;
@property (nonatomic, strong, nullable) NSURL *URL;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *toolTip;
@property (nonatomic) BOOL closeable;

+ (instancetype)tabWithKind:(TLWorkspaceTabKind)kind
                      tabID:(NSInteger)tabID
                      title:(nullable NSString *)title
                    toolTip:(nullable NSString *)toolTip
                         URL:(nullable NSURL *)URL
                   closeable:(BOOL)closeable;

@end

NS_ASSUME_NONNULL_END
