#import <AppKit/AppKit.h>
#import "Theme.h"
#import "TLMessageInput.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, TLBorderEdges) {
  TLBorderEdgeNone = 0,
  TLBorderEdgeTop = 1 << 0,
  TLBorderEdgeRight = 1 << 1,
  TLBorderEdgeBottom = 1 << 2,
  TLBorderEdgeLeft = 1 << 3,
  TLBorderEdgeAll = TLBorderEdgeTop | TLBorderEdgeRight | TLBorderEdgeBottom | TLBorderEdgeLeft,
};

@interface TLTokenView : NSView
- (CGPathRef)newOutlinePath CF_RETURNS_RETAINED;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *borderColor;
@property (nonatomic) CGFloat borderWidth;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) CGFloat topLeftCornerRadius;
@property (nonatomic) CGFloat topRightCornerRadius;
@property (nonatomic) CGFloat bottomRightCornerRadius;
@property (nonatomic) CGFloat bottomLeftCornerRadius;
@property (nonatomic) TLBorderEdges borderEdges;
@property (nonatomic) BOOL canDragWindow;
@end

@interface TLSlashCommandItemView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSString *commandDescription;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic, getter=isSelected) BOOL selected;
@end

@interface TLMessageBubbleView : TLTokenView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL drawsOutgoingTail;
@property (nonatomic) BOOL rendersAsPill;
@property (nonatomic) CGFloat outgoingTailHorizontalOffset;
@end

@interface TLGlassMessageInput : TLMessageInput
@end

@interface TLBrowserAddressInput : TLGlassMessageInput <NSTextViewDelegate>
@property (nonatomic, readonly) BOOL hasUserDraft;
@property (nonatomic, strong, readonly) NSButton *backButton;
@property (nonatomic, strong, readonly) NSButton *forwardButton;
@property (nonatomic, strong, readonly) NSButton *reloadButton;
@property (nonatomic, strong, readonly) NSButton *heightToggleButton;
@property (nonatomic, strong, readonly) NSButton *chatButton;
@property (nonatomic) NSUInteger responseCount;
@property (nonatomic, getter=isChatVisible) BOOL chatVisible;
@property (nonatomic, getter=isReducedHeight) BOOL reducedHeight;
- (void)setDisplayedAddress:(NSString *)address;
- (void)updateDisplayedAddress:(NSString *)address;
- (void)beginPromptEditing;
@end

@interface TLBrowserBackdropView : NSView
@end

typedef NS_ENUM(NSInteger, TLSidebarShortcutKind) {
  TLSidebarShortcutKindWebsite = 0,
  TLSidebarShortcutKindNotes,
  TLSidebarShortcutKindHistory,
};

@interface TLSidebarShortcutButton : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL roundsImageCorners;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, nullable) NSURL *URL;
@property (nonatomic) TLSidebarShortcutKind shortcutKind;
@end

@interface TLSidebarShortcutsView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, readonly) NSArray<TLSidebarShortcutButton *> *shortcutButtons;
- (void)addShortcutButton:(TLSidebarShortcutButton *)button;
@end

@interface TLFlippedView : NSView
@end

@interface TLWindowDragStackView : NSStackView
@property (nonatomic) BOOL canDragWindow;
@end

@interface TLHoverStackView : NSStackView
@property (nonatomic, copy, nullable) void (^hoverChanged)(BOOL hovered);
@end

@interface TLInputBlockingView : NSView
@end

@interface TLGlassPaneView : TLInputBlockingView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) CGFloat cornerRadius;
@end

@interface TLSpacedButtonCell : NSButtonCell
@property (nonatomic) CGFloat imageTitleSpacing;
@property (nonatomic) CGFloat imageUpwardOffset;
@end

@interface TLSelectionStackView : TLHoverStackView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL selected;
@end

@interface TLIconTileView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) CGFloat imageSize;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic, copy, nullable) NSString *badgeSystemIconName;
@property (nonatomic) BOOL dashed;
@property (nonatomic) BOOL selected;
@end

@interface TLSidebarNavigationButton : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *systemIconName;
@property (nonatomic, copy) NSString *accessorySystemIconName;
@property (nonatomic) BOOL selected;
@property (nonatomic) BOOL forcesHoverState;
@property (nonatomic) BOOL showsActivityIndicatorIcon;
@end

@interface TLSidebarUserButton : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *displayName;
@end

@interface TLSidebarInboxPaneView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, readonly) NSStackView *contentStackView;
- (void)addInboxItemView:(NSView *)itemView;
- (void)insertInboxItemView:(NSView *)itemView atIndex:(NSUInteger)index;
@end

@interface TLSidebarInboxStackView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong, nullable) NSImage *image;
@property (nonatomic) BOOL imageUsesTemplateRendering;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic) NSInteger notificationCount;
@property (nonatomic) BOOL usesPrimaryBadge;
@property (nonatomic) BOOL showsSeparator;
@property (nonatomic, getter=isUrgent) BOOL urgent;
@end

@interface TLTaskStatusPillView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL forcesHoverState;
@property (nonatomic) BOOL showsActivityIndicator;
@end

typedef NS_ENUM(NSInteger, TLSidebarResizeHandlePhase) {
  TLSidebarResizeHandlePhaseNone,
  TLSidebarResizeHandlePhaseBegan,
  TLSidebarResizeHandlePhaseChanged,
  TLSidebarResizeHandlePhaseEnded,
};

@interface TLSidebarResizeHandle : NSView
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic, readonly) CGFloat dragDeltaX;
@property (nonatomic, readonly) TLSidebarResizeHandlePhase dragPhase;
@end

@interface TLHistoryRowView : NSTableRowView
@property (nonatomic, strong) TLThemePalette *palette;
@end

@interface TLBrandMarkView : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@end

@interface TLActionTrampoline : NSObject
@property (nonatomic, copy, nullable) void (^block)(void);
- (void)perform:(id)sender;
@end

NS_ASSUME_NONNULL_END
