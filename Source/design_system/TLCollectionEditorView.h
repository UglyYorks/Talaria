#import "UIComponents.h"

NS_ASSUME_NONNULL_BEGIN
/// A two-column collection/editor surface that becomes a single pane at narrow widths.
@interface TLCollectionEditorView : TLTokenView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic) BOOL showsEditor;
@property (nonatomic, readonly) BOOL compact;
@property (nonatomic, strong, readonly) NSView *header;
@property (nonatomic, strong, readonly) TLTokenView *collection;
@property (nonatomic, strong, readonly) NSView *editor;
@property (nonatomic, strong, readonly) TLTokenView *footer;
@end
NS_ASSUME_NONNULL_END
