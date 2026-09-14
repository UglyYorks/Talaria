#import <AppKit/AppKit.h>
#import "Theme.h"

NS_ASSUME_NONNULL_BEGIN
/// A formatted Markdown editor with a native toolbar and an optional source view.
@interface TLMarkdownEditorView : NSView
@property (nonatomic, copy) NSString *string;
@property (nonatomic, getter=isEditable) BOOL editable;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, copy, nullable) void (^changeHandler)(void);
@property (nonatomic, readonly) BOOL ready;
/// Flush WebKit input before saving, navigating away, or closing a document.
- (BOOL)finishEditing;
- (void)focusEditor;
- (void)close;
@end
NS_ASSUME_NONNULL_END
