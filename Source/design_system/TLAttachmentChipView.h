#import <AppKit/AppKit.h>
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import "Theme.h"
#import "TLGlassButton.h"

NS_ASSUME_NONNULL_BEGIN
// Shared attachment appearance for the composer and saved conversation messages.
@interface TLAttachmentChipView : NSControl
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL showsRemoveButton;
@property (nonatomic, copy, nullable) void (^activationHandler)(void);
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, strong) TLHoverIconButton *closeButton;
@property (nonatomic, strong, nullable) QLThumbnailGenerationRequest *thumbnailRequest;
@property (nonatomic, strong) NSURL *previewURL;
@property (nonatomic) BOOL previewSecurityScope;
@property (nonatomic) BOOL hasContentPreview;
@property (nonatomic, strong) NSView *chipContentView;
@property (nonatomic, strong) NSURL *attachmentURL;
@property (nonatomic, copy) NSString *transitionKey;
@property (nonatomic) CGFloat revealProgress;
@property (nonatomic) BOOL removing;
@property (nonatomic) BOOL closingTransition;
- (void)loadPreviewForURL:(NSURL *)URL;
@end

@interface TLAttachmentChipRow : NSView
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, readonly) CGFloat preferredWidth;
- (instancetype)initWithChips:(NSArray<TLAttachmentChipView *> *)chips palette:(TLThemePalette *)palette;
@end
NS_ASSUME_NONNULL_END
