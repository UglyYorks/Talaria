#import "TLAttachmentViewerWindowController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLAttachmentPreviewPanel.h"
#import "design_system/TLGlassButton.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TLAttachmentViewerWindowController () <NSWindowDelegate>
@property (nonatomic, copy) NSArray<TLAttachmentPreviewItem *> *items;
@property (nonatomic) NSUInteger selectedIndex;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLTokenView *root;
@property (nonatomic, strong) TLTokenView *previewHost;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSTextField *counterLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSTextField *emptyTitle;
@property (nonatomic, strong) NSTextField *emptyDetail;
@property (nonatomic, strong) NSStackView *emptyState;
@property (nonatomic, strong) TLHoverIconButton *previousButton;
@property (nonatomic, strong) TLHoverIconButton *nextButton;
@property (nonatomic, strong) TLHoverIconButton *closeButton;
@property (nonatomic, strong) TLHoverIconButton *saveButton;
@property (nonatomic, strong) TLHoverIconButton *finderButton;
@property (nonatomic, strong) QLPreviewView *preview;
@property (nonatomic, strong) NSImageView *imageView;
@property (nonatomic, strong) NSScrollView *textScroll;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSLayoutConstraint *titleTop;
@property (nonatomic, strong) NSLayoutConstraint *actionsTop;
@property (nonatomic, strong) id keyMonitor;
@property (nonatomic) NSUInteger previewGeneration;
@property (nonatomic, strong) NSScreen *presentationScreen;
@end

@implementation TLAttachmentViewerWindowController
- (NSTextField *)label:(NSString *)text {
  NSTextField *label = [NSTextField labelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}
- (instancetype)initWithItems:(NSArray<TLAttachmentPreviewItem *> *)items conversationTitle:(NSString *)title selectedIndex:(NSUInteger)index palette:(TLThemePalette *)palette {
  NSScreen *screen = NSApp.keyWindow.screen ?: NSScreen.mainScreen;
  TLAttachmentPreviewPanel *window = [[TLAttachmentPreviewPanel alloc] initWithContentRect:screen.frame
    styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
  if ((self = [super initWithWindow:window])) {
    _items = [items copy]; _presentationScreen = screen;
    // The viewer is an intentionally dark lightbox, in either conversation theme.
    _palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
    window.title = title.length ? title : @"Attachments";
    window.releasedWhenClosed = NO; window.delegate = self;
    window.opaque = NO; window.hasShadow = NO; window.hidesOnDeactivate = YES;
    window.level = NSMainMenuWindowLevel + 1;
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorTransient;
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    __weak typeof(self) weakSelf = self;
    window.dismissHandler = ^{ [weakSelf close]; };
    [self buildInterface]; [self applyPalette:palette];
    [self selectItemAtIndex:MIN(index, items.count ? items.count - 1 : 0)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenParametersChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
  }
  return self;
}
- (void)buildInterface {
  TLThemePalette *p = self.palette;
  self.root = [[TLTokenView alloc] init]; self.window.contentView = self.root;
  self.previewHost = [[TLTokenView alloc] init]; self.previewHost.translatesAutoresizingMaskIntoConstraints = NO;
  [self.root addSubview:self.previewHost];
  self.nameLabel = [self label:@""]; self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
  self.nameLabel.alignment = NSTextAlignmentCenter;
  self.detailLabel = [self label:@""]; self.detailLabel.alignment = NSTextAlignmentCenter;
  self.counterLabel = [self label:@""]; self.counterLabel.alignment = NSTextAlignmentCenter;
  self.hintLabel = [self label:@"←  → to browse    ·    Esc to close"]; self.hintLabel.alignment = NSTextAlignmentCenter;
  for (NSView *label in @[self.nameLabel, self.detailLabel, self.counterLabel, self.hintLabel]) [self.root addSubview:label];
  self.previousButton = [self iconButton:@"chevron.left" label:@"Previous attachment (←)" action:@selector(previous:)];
  self.nextButton = [self iconButton:@"chevron.right" label:@"Next attachment (→)" action:@selector(next:)];
  [self.root addSubview:self.previousButton]; [self.root addSubview:self.nextButton];
  self.closeButton = [self iconButton:@"xmark" label:@"Close preview (Esc)" action:@selector(closePreview:)];
  self.saveButton = [self iconButton:@"square.and.arrow.down" label:@"Save a copy" action:@selector(saveCopy:)];
  self.finderButton = [self iconButton:@"folder" label:@"Show in Finder" action:@selector(showInFinder:)];
  NSStackView *actions = [NSStackView stackViewWithViews:@[self.finderButton,self.saveButton,self.closeButton]];
  actions.translatesAutoresizingMaskIntoConstraints = NO; actions.spacing = p.space3; [self.root addSubview:actions];
  self.emptyTitle = [self label:@"No attachments"];
  self.emptyDetail = [NSTextField wrappingLabelWithString:@"Files shared in this conversation appear here."];
  self.emptyDetail.translatesAutoresizingMaskIntoConstraints = NO; self.emptyDetail.alignment = NSTextAlignmentCenter;
  self.emptyState = [NSStackView stackViewWithViews:@[self.emptyTitle,self.emptyDetail]];
  self.emptyState.translatesAutoresizingMaskIntoConstraints = NO; self.emptyState.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.emptyState.alignment = NSLayoutAttributeCenterX; self.emptyState.spacing = p.space6; [self.previewHost addSubview:self.emptyState];
  self.titleTop = [self.nameLabel.topAnchor constraintEqualToAnchor:self.root.topAnchor constant:p.space12];
  self.actionsTop = [actions.topAnchor constraintEqualToAnchor:self.root.topAnchor constant:p.space9];
  [NSLayoutConstraint activateConstraints:@[
    self.titleTop, self.actionsTop,
    [self.nameLabel.centerXAnchor constraintEqualToAnchor:self.root.centerXAnchor], [self.nameLabel.widthAnchor constraintEqualToAnchor:self.root.widthAnchor multiplier:0.55],
    [self.detailLabel.centerXAnchor constraintEqualToAnchor:self.root.centerXAnchor], [self.detailLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:p.space3], [self.detailLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.nameLabel.widthAnchor],
    [actions.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor constant:-p.space12],
    [actions.widthAnchor constraintEqualToConstant:p.attachmentViewerControlSize * 3 + p.space3 * 2],
    [self.previousButton.leadingAnchor constraintEqualToAnchor:self.root.leadingAnchor constant:p.space12], [self.previousButton.centerYAnchor constraintEqualToAnchor:self.root.centerYAnchor],
    [self.nextButton.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor constant:-p.space12], [self.nextButton.centerYAnchor constraintEqualToAnchor:self.root.centerYAnchor],
    [self.previewHost.leadingAnchor constraintEqualToAnchor:self.root.leadingAnchor constant:p.attachmentViewerContentInset], [self.previewHost.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor constant:-p.attachmentViewerContentInset],
    [self.previewHost.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:p.space12], [self.previewHost.bottomAnchor constraintEqualToAnchor:self.counterLabel.topAnchor constant:-p.space12],
    [self.counterLabel.centerXAnchor constraintEqualToAnchor:self.root.centerXAnchor], [self.counterLabel.bottomAnchor constraintEqualToAnchor:self.hintLabel.topAnchor constant:-p.space3],
    [self.hintLabel.centerXAnchor constraintEqualToAnchor:self.root.centerXAnchor], [self.hintLabel.bottomAnchor constraintEqualToAnchor:self.root.bottomAnchor constant:-p.space12],
    [self.emptyState.centerXAnchor constraintEqualToAnchor:self.previewHost.centerXAnchor], [self.emptyState.centerYAnchor constraintEqualToAnchor:self.previewHost.centerYAnchor], [self.emptyState.widthAnchor constraintLessThanOrEqualToAnchor:self.previewHost.widthAnchor constant:-p.space16], [self.emptyDetail.widthAnchor constraintEqualToAnchor:self.emptyState.widthAnchor],
  ]];
}
- (TLHoverIconButton *)iconButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  TLHoverIconButton *button = [[TLHoverIconButton alloc] init]; button.translatesAutoresizingMaskIntoConstraints = NO;
  button.image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:self.palette.space10 weight:NSFontWeightMedium]];
  button.imagePosition = NSImageOnly; button.hoverSurfaceOnly = YES; button.bordered = NO;
  button.target = self; button.action = action; button.toolTip = label; button.accessibilityLabel = label;
  [button.widthAnchor constraintEqualToConstant:self.palette.attachmentViewerControlSize].active = YES;
  [button.heightAnchor constraintEqualToAnchor:button.widthAnchor].active = YES;
  return button;
}
- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceDark];
  TLThemePalette *p = self.palette;
  self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.window.backgroundColor = p.transparentSurface; self.root.fillColor = p.modalBackdrop;
  self.previewHost.fillColor = p.transparentSurface; self.previewHost.borderEdges = TLBorderEdgeNone;
  for (NSTextField *label in @[self.nameLabel,self.counterLabel,self.emptyTitle]) { label.textColor = p.appText; label.font = p.labelFont; }
  self.emptyTitle.font = p.titleFont;
  for (NSTextField *label in @[self.detailLabel,self.hintLabel,self.emptyDetail]) { label.textColor = p.textMuted; label.font = p.smallFont; }
  self.emptyDetail.font = p.bodyFont;
  for (TLHoverIconButton *button in @[self.previousButton,self.nextButton,self.closeButton,self.saveButton,self.finderButton]) {
    button.palette = p; button.idleSurfaceColor = p.secondaryActionSurface; button.layer.cornerRadius = p.attachmentViewerControlSize / 2;
  }
  self.textView.backgroundColor = p.controlSurface; self.textView.textColor = p.controlText; self.textView.insertionPointColor = p.controlText; self.textView.font = p.markdownCodeFont;
  if (self.preview) [self.preview refreshPreviewItem];
}
- (void)showOnScreen:(NSScreen *)screen { self.presentationScreen = screen ?: NSScreen.mainScreen; [self showWindow:nil]; }
- (void)fitToScreen {
  if (![NSScreen.screens containsObject:self.presentationScreen]) self.presentationScreen = NSScreen.mainScreen;
  [self.window setFrame:self.presentationScreen.frame display:NO];
  CGFloat top = self.presentationScreen.safeAreaInsets.top;
  self.titleTop.constant = MAX(top + self.palette.space6, self.palette.space12);
  self.actionsTop.constant = MAX(top + self.palette.space3, self.palette.space9);
}
- (void)screenParametersChanged:(NSNotification *)notification { if (self.window.isVisible) [self fitToScreen]; }
- (void)closePreview:(id)sender { [self close]; }
- (void)embedPreview:(NSView *)view {
  view.translatesAutoresizingMaskIntoConstraints = NO; [self.previewHost addSubview:view];
  CGFloat inset = self.palette.space2;
  [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:self.previewHost.leadingAnchor constant:inset], [view.trailingAnchor constraintEqualToAnchor:self.previewHost.trailingAnchor constant:-inset], [view.topAnchor constraintEqualToAnchor:self.previewHost.topAnchor constant:inset], [view.bottomAnchor constraintEqualToAnchor:self.previewHost.bottomAnchor constant:-inset]]];
}
- (void)clearPreview {
  self.previewGeneration++;
  [self.preview close]; [self.preview removeFromSuperview]; self.preview = nil;
  [self.imageView removeFromSuperview]; self.imageView = nil;
  [self.textScroll removeFromSuperview]; self.textScroll = nil; self.textView = nil;
}
- (void)selectItemAtIndex:(NSUInteger)index {
  if (index >= self.items.count) { self.saveButton.enabled = NO; self.finderButton.enabled = NO; self.previousButton.enabled = NO; self.nextButton.enabled = NO; return; }
  [self clearPreview]; self.selectedIndex = index;
  TLAttachmentPreviewItem *item = self.items[index];
  NSURL *URL = item.previewItemURL;
  self.nameLabel.stringValue = item.name; self.nameLabel.toolTip = item.name;
  self.detailLabel.stringValue = item.detail;
  self.window.title = [NSString stringWithFormat:@"%@ — Attachments", item.name];
  self.counterLabel.stringValue = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)index + 1, (unsigned long)self.items.count];
  self.previousButton.enabled = index > 0; self.nextButton.enabled = index + 1 < self.items.count;
  self.saveButton.enabled = URL != nil; self.finderButton.enabled = URL != nil;
  self.emptyState.hidden = NO;
  self.emptyTitle.stringValue = URL ? (item.directory ? @"Folder attachment" : @"Loading preview…") : @"File unavailable";
  self.emptyDetail.stringValue = URL ? (item.directory ? @"Show this folder in Finder to explore its contents, or save a copy." : @"Preparing your attachment.") : @"The saved file could not be found or read. It may have been moved or deleted.";
  if (!URL || item.directory) return;
  UTType *type = [UTType typeWithFilenameExtension:item.name.pathExtension];
  NSSet *textExtensions = [NSSet setWithArray:@[@"md", @"txt", @"csv", @"tsv", @"json", @"log", @"yaml", @"yml", @"toml", @"py", @"js", @"ts", @"jsx", @"tsx", @"sh", @"m", @"h", @"swift", @"rs", @"go"]];
  if ([type conformsToType:UTTypeImage]) { [self loadImageAtURL:URL]; return; }
  if ([type conformsToType:UTTypePlainText] || [type conformsToType:UTTypeSourceCode] || [textExtensions containsObject:item.name.pathExtension.lowercaseString]) {
    [self loadTextAtURL:URL]; return;
  }
  self.emptyState.hidden = YES;
  self.preview = [[QLPreviewView alloc] initWithFrame:self.previewHost.bounds style:QLPreviewViewStyleNormal];
  self.preview.autostarts = NO; self.preview.shouldCloseWithWindow = NO;
  [self embedPreview:self.preview]; self.preview.previewItem = URL;
}
- (void)loadImageAtURL:(NSURL *)URL {
  NSUInteger generation = self.previewGeneration;
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:URL];
    dispatch_async(dispatch_get_main_queue(), ^{
      TLAttachmentViewerWindowController *controller = weakSelf;
      if (!controller || generation != controller.previewGeneration) return;
      if (!image) { controller.emptyTitle.stringValue = @"Preview unavailable"; controller.emptyDetail.stringValue = @"This image could not be opened. You can still save a copy."; return; }
      controller.emptyState.hidden = YES;
      controller.imageView = [[NSImageView alloc] init]; controller.imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
      controller.imageView.animates = YES; controller.imageView.image = image;
      controller.imageView.accessibilityLabel = controller.items[controller.selectedIndex].name;
      [controller embedPreview:controller.imageView];
    });
  });
}
- (void)loadTextAtURL:(NSURL *)URL {
  NSUInteger generation = self.previewGeneration;
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    // Bound memory use for logs and generated files; never interpret text as HTML.
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:URL error:nil];
    NSData *data = [file readDataUpToLength:2 * 1024 * 1024 + 1 error:nil]; [file closeAndReturnError:nil];
    BOOL truncated = data.length > 2 * 1024 * 1024;
    if (truncated) data = [data subdataWithRange:NSMakeRange(0, 2 * 1024 * 1024)];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    // A bounded read can split the final UTF-8 character.
    if (!text && truncated) for (NSUInteger trim = 1; trim <= 3 && !text; trim++) text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, data.length - trim)] encoding:NSUTF8StringEncoding];
    if (!text && data) text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    dispatch_async(dispatch_get_main_queue(), ^{
      TLAttachmentViewerWindowController *controller = weakSelf;
      if (!controller || controller.previewGeneration != generation) return;
      if (!text) { controller.emptyTitle.stringValue = @"Preview unavailable"; controller.emptyDetail.stringValue = @"This file could not be displayed as text. Save a copy or open its location in Finder."; return; }
      controller.emptyState.hidden = YES;
      controller.textScroll = [[NSScrollView alloc] init]; controller.textScroll.drawsBackground = NO; controller.textScroll.hasVerticalScroller = YES; controller.textScroll.autohidesScrollers = YES;
      controller.textView = [[NSTextView alloc] initWithFrame:controller.previewHost.bounds];
      controller.textView.editable = NO; controller.textView.selectable = YES; controller.textView.richText = NO;
      controller.textView.autoresizingMask = NSViewWidthSizable;
      controller.textView.textContainerInset = NSMakeSize(controller.palette.space12, controller.palette.space12);
      controller.textView.textContainer.widthTracksTextView = YES;
      controller.textView.string = text;
      controller.textScroll.documentView = controller.textView;
      [controller embedPreview:controller.textScroll];
      [controller applyPalette:controller.palette];
      if (truncated) controller.detailLabel.stringValue = [controller.detailLabel.stringValue stringByAppendingString:@" · Showing first 2 MB"];
    });
  });
}
- (void)previous:(id)sender { if (self.selectedIndex > 0) [self selectItemAtIndex:self.selectedIndex - 1]; }
- (void)next:(id)sender { if (self.selectedIndex + 1 < self.items.count) [self selectItemAtIndex:self.selectedIndex + 1]; }
- (void)showWindow:(id)sender {
  [self fitToScreen];
  [super showWindow:sender];
  [self.window makeKeyAndOrderFront:sender];
  if (!self.keyMonitor) {
    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
      TLAttachmentViewerWindowController *controller = weakSelf;
      if (!controller || event.window != controller.window || controller.window.attachedSheet) return event;
      if (event.keyCode == 53) { [controller close]; return nil; }
      BOOL plainArrow = !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift));
      if ((plainArrow && event.keyCode == 123) || ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqual:@"["])) { [controller previous:nil]; return nil; }
      if ((plainArrow && event.keyCode == 124) || ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqual:@"]"])) { [controller next:nil]; return nil; }
      return event;
    }];
  }
}
- (void)windowWillClose:(NSNotification *)notification {
  if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor]; self.keyMonitor = nil;
  [self clearPreview];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor]; [_preview close]; }
- (NSURL *)currentURL {
  NSURL *URL = self.items.count ? self.items[self.selectedIndex].previewItemURL : nil;
  if (!URL) [self selectItemAtIndex:self.selectedIndex];
  return URL;
}
- (void)showInFinder:(id)sender {
  NSURL *URL = [self currentURL]; if (URL) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[URL]];
}
- (void)saveCopy:(id)sender {
  NSURL *URL = [self currentURL]; if (!URL) return;
  TLAttachmentPreviewItem *item = self.items[self.selectedIndex];
  NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = item.name; panel.canCreateDirectories = YES;
  panel.title = @"Save a Copy"; panel.prompt = @"Save Copy";
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL) return;
    NSURL *destination = panel.URL;
    self.saveButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      [item saveCopyToURL:destination error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{ self.saveButton.enabled = [self currentURL] != nil; if (error) [self presentError:error]; });
    });
  }];
}
@end
