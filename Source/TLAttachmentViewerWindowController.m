#import "TLAttachmentViewerWindowController.h"
#import "design_system/UIComponents.h"
#import "design_system/TLAttachmentCard.h"
#import "design_system/TLThemedButton.h"
#import "design_system/TLGlassButton.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TLAttachmentViewerWindowController () <NSWindowDelegate>
@property (nonatomic, copy) NSArray<TLAttachmentPreviewItem *> *items;
@property (nonatomic) NSUInteger selectedIndex;
@property (nonatomic, strong) TLThemePalette *palette;
@property (nonatomic, strong) TLTokenView *root;
@property (nonatomic, strong) TLTokenView *sidebar;
@property (nonatomic, strong) TLTokenView *header;
@property (nonatomic, strong) TLTokenView *previewHost;
@property (nonatomic, strong) NSScrollView *fileScroll;
@property (nonatomic, strong) NSStackView *fileList;
@property (nonatomic, strong) NSMutableArray<TLAttachmentCard *> *cards;
@property (nonatomic, strong) NSTextField *sectionLabel;
@property (nonatomic, strong) NSTextField *conversationLabel;
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSTextField *counterLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSTextField *emptyTitle;
@property (nonatomic, strong) NSTextField *emptyDetail;
@property (nonatomic, strong) NSStackView *emptyState;
@property (nonatomic, strong) TLHoverIconButton *previousButton;
@property (nonatomic, strong) TLHoverIconButton *nextButton;
@property (nonatomic, strong) TLThemedButton *saveButton;
@property (nonatomic, strong) TLThemedButton *finderButton;
@property (nonatomic, strong) QLPreviewView *preview;
@property (nonatomic, strong) NSScrollView *textScroll;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidth;
@property (nonatomic, strong) NSLayoutConstraint *headerLeading;
@property (nonatomic, strong) id keyMonitor;
@property (nonatomic) NSUInteger previewGeneration;
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
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, palette.attachmentViewerWidth, palette.attachmentViewerHeight)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
  if ((self = [super initWithWindow:window])) {
    _items = [items copy]; _palette = palette; _cards = [NSMutableArray array];
    window.title = @"Attachments";
    window.releasedWhenClosed = NO;
    window.delegate = self;
    window.contentMinSize = NSMakeSize(palette.attachmentViewerMinimumWidth, palette.attachmentViewerMinimumHeight);
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    [self buildInterfaceForConversation:title];
    [self applyPalette:palette];
    [self selectItemAtIndex:MIN(index, items.count ? items.count - 1 : 0)];
    [window center];
  }
  return self;
}
- (void)buildInterfaceForConversation:(NSString *)title {
  TLThemePalette *p = self.palette;
  self.root = [[TLTokenView alloc] init]; self.window.contentView = self.root;
  self.sidebar = [[TLTokenView alloc] init];
  self.header = [[TLTokenView alloc] init];
  self.previewHost = [[TLTokenView alloc] init];
  for (NSView *view in @[self.sidebar, self.header, self.previewHost]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.root addSubview:view]; }
  self.sectionLabel = [self label:[NSString stringWithFormat:@"Attachments · %lu", (unsigned long)self.items.count]];
  self.conversationLabel = [self label:title.length ? title : @"Conversation"];
  self.conversationLabel.toolTip = title;
  [self.sidebar addSubview:self.sectionLabel]; [self.sidebar addSubview:self.conversationLabel];
  self.fileScroll = [[NSScrollView alloc] init]; self.fileScroll.translatesAutoresizingMaskIntoConstraints = NO;
  self.fileScroll.drawsBackground = NO; self.fileScroll.hasVerticalScroller = YES; self.fileScroll.autohidesScrollers = YES;
  self.fileList = [[NSStackView alloc] init]; self.fileList.translatesAutoresizingMaskIntoConstraints = NO;
  self.fileList.orientation = NSUserInterfaceLayoutOrientationVertical; self.fileList.alignment = NSLayoutAttributeWidth;
  self.fileList.spacing = p.space4; self.fileList.edgeInsets = NSEdgeInsetsMake(p.space2, p.space5, p.space5, p.space5);
  TLFlippedView *fileDocument = [[TLFlippedView alloc] init]; fileDocument.translatesAutoresizingMaskIntoConstraints = NO;
  [fileDocument addSubview:self.fileList]; self.fileScroll.documentView = fileDocument;
  NSLayoutConstraint *documentHeight = [fileDocument.heightAnchor constraintEqualToAnchor:self.fileList.heightAnchor];
  documentHeight.priority = NSLayoutPriorityDefaultHigh;
  [NSLayoutConstraint activateConstraints:@[
    [fileDocument.widthAnchor constraintEqualToAnchor:self.fileScroll.contentView.widthAnchor],
    [fileDocument.heightAnchor constraintGreaterThanOrEqualToAnchor:self.fileScroll.contentView.heightAnchor], documentHeight,
    [self.fileList.topAnchor constraintEqualToAnchor:fileDocument.topAnchor],
    [self.fileList.leadingAnchor constraintEqualToAnchor:fileDocument.leadingAnchor],
    [self.fileList.trailingAnchor constraintEqualToAnchor:fileDocument.trailingAnchor],
    [self.fileList.bottomAnchor constraintLessThanOrEqualToAnchor:fileDocument.bottomAnchor],
  ]];
  [self.sidebar addSubview:self.fileScroll];
  __weak typeof(self) weakSelf = self;
  [self.items enumerateObjectsUsingBlock:^(TLAttachmentPreviewItem *item, NSUInteger index, BOOL *stop) {
    TLAttachmentCard *card = [[TLAttachmentCard alloc] init]; card.translatesAutoresizingMaskIntoConstraints = NO;
    card.palette = p; card.title = item.name; card.directory = item.directory; card.subtitle = item.detail; card.fileURL = item.previewItemURL;
    card.activationHandler = ^{ [weakSelf selectItemAtIndex:index]; };
    [self.fileList addArrangedSubview:card]; [self.cards addObject:card];
    [card.heightAnchor constraintEqualToConstant:p.attachmentCardHeight].active = YES;
    [card.widthAnchor constraintEqualToAnchor:self.fileList.widthAnchor constant:-p.space5 * 2].active = YES;
  }];
  self.nameLabel = [self label:@""]; self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle; self.nameLabel.selectable = YES;
  self.detailLabel = [self label:@""];
  [self.header addSubview:self.nameLabel]; [self.header addSubview:self.detailLabel];
  self.previousButton = [self navigationButton:@"chevron.left" label:@"Previous attachment (⌘[)" action:@selector(previous:)];
  self.nextButton = [self navigationButton:@"chevron.right" label:@"Next attachment (⌘])" action:@selector(next:)];
  self.counterLabel = [self label:@""]; self.counterLabel.alignment = NSTextAlignmentCenter;
  NSStackView *navigation = [NSStackView stackViewWithViews:@[self.previousButton, self.counterLabel, self.nextButton]];
  navigation.translatesAutoresizingMaskIntoConstraints = NO; navigation.spacing = p.space3;
  [self.header addSubview:navigation];
  self.saveButton = [[TLThemedButton alloc] init]; self.saveButton.title = @"Save Copy…"; self.saveButton.target = self; self.saveButton.action = @selector(saveCopy:);
  self.finderButton = [[TLThemedButton alloc] init]; self.finderButton.title = @"Show in Finder"; self.finderButton.target = self; self.finderButton.action = @selector(showInFinder:);
  NSStackView *actions = [NSStackView stackViewWithViews:@[self.finderButton, self.saveButton]];
  actions.translatesAutoresizingMaskIntoConstraints = NO; actions.spacing = p.space5;
  [self.root addSubview:actions];
  self.hintLabel = [self label:@"⌘[ / ⌘] to browse · Esc to close"];
  [self.root addSubview:self.hintLabel];
  self.emptyTitle = [self label:@"No attachments"];
  self.emptyDetail = [NSTextField wrappingLabelWithString:@"Files shared in this conversation appear here."];
  self.emptyDetail.translatesAutoresizingMaskIntoConstraints = NO; self.emptyDetail.alignment = NSTextAlignmentCenter;
  self.emptyState = [NSStackView stackViewWithViews:@[self.emptyTitle, self.emptyDetail]];
  self.emptyState.translatesAutoresizingMaskIntoConstraints = NO; self.emptyState.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.emptyState.alignment = NSLayoutAttributeCenterX; self.emptyState.spacing = p.space6;
  [self.previewHost addSubview:self.emptyState];
  self.sidebarWidth = [self.sidebar.widthAnchor constraintEqualToConstant:p.attachmentViewerSidebarWidth];
  self.headerLeading = [self.header.leadingAnchor constraintEqualToAnchor:self.root.leadingAnchor constant:p.attachmentViewerSidebarWidth];
  [NSLayoutConstraint activateConstraints:@[
    [self.sidebar.leadingAnchor constraintEqualToAnchor:self.root.leadingAnchor], [self.sidebar.topAnchor constraintEqualToAnchor:self.root.topAnchor], [self.sidebar.bottomAnchor constraintEqualToAnchor:self.root.bottomAnchor], self.sidebarWidth,
    [self.sectionLabel.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:p.space9], [self.sectionLabel.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-p.space9], [self.sectionLabel.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor constant:p.space10],
    [self.conversationLabel.leadingAnchor constraintEqualToAnchor:self.sectionLabel.leadingAnchor], [self.conversationLabel.trailingAnchor constraintEqualToAnchor:self.sectionLabel.trailingAnchor], [self.conversationLabel.topAnchor constraintEqualToAnchor:self.sectionLabel.bottomAnchor constant:p.space3],
    [self.fileScroll.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor constant:p.attachmentViewerHeaderHeight], [self.fileScroll.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor], [self.fileScroll.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor], [self.fileScroll.bottomAnchor constraintEqualToAnchor:self.sidebar.bottomAnchor],
    self.headerLeading, [self.header.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor], [self.header.topAnchor constraintEqualToAnchor:self.root.topAnchor], [self.header.heightAnchor constraintEqualToConstant:p.attachmentViewerHeaderHeight],
    [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:p.space12], [self.nameLabel.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:p.space9], [self.nameLabel.trailingAnchor constraintEqualToAnchor:navigation.leadingAnchor constant:-p.space9],
    [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor], [self.detailLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:p.space3], [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
    [navigation.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-p.space9], [navigation.centerYAnchor constraintEqualToAnchor:self.header.centerYAnchor],
    [self.counterLabel.widthAnchor constraintEqualToConstant:p.space16],
    [navigation.widthAnchor constraintEqualToConstant:p.browserToolbarButtonSize * 2 + p.space16 + p.space3 * 2],
    [self.previewHost.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:p.space9], [self.previewHost.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor constant:-p.space9], [self.previewHost.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:p.space9], [self.previewHost.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-p.space9],
    [actions.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor constant:-p.space9], [actions.bottomAnchor constraintEqualToAnchor:self.root.bottomAnchor constant:-p.space9],
    [self.hintLabel.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:p.space12], [self.hintLabel.centerYAnchor constraintEqualToAnchor:actions.centerYAnchor], [self.hintLabel.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-p.space6],
    [self.emptyState.centerXAnchor constraintEqualToAnchor:self.previewHost.centerXAnchor], [self.emptyState.centerYAnchor constraintEqualToAnchor:self.previewHost.centerYAnchor], [self.emptyState.widthAnchor constraintLessThanOrEqualToAnchor:self.previewHost.widthAnchor constant:-p.space16], [self.emptyDetail.widthAnchor constraintEqualToAnchor:self.emptyState.widthAnchor],
  ]];
}
- (TLHoverIconButton *)navigationButton:(NSString *)symbol label:(NSString *)label action:(SEL)action {
  TLHoverIconButton *button = [[TLHoverIconButton alloc] init]; button.translatesAutoresizingMaskIntoConstraints = NO;
  button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label]; button.imagePosition = NSImageOnly;
  button.bordered = NO; button.target = self; button.action = action; button.toolTip = label; button.accessibilityLabel = label;
  [button.widthAnchor constraintEqualToConstant:self.palette.browserToolbarButtonSize].active = YES;
  [button.heightAnchor constraintEqualToAnchor:button.widthAnchor].active = YES;
  return button;
}
- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.appContentBackground;
  self.root.fillColor = palette.appContentBackground;
  self.sidebar.fillColor = palette.sidebarSurface; self.sidebar.borderColor = palette.sidebarBorder; self.sidebar.borderEdges = TLBorderEdgeRight; self.sidebar.borderWidth = palette.borderWidth;
  self.header.fillColor = palette.appContentBackground; self.header.borderColor = palette.controlBorder; self.header.borderEdges = TLBorderEdgeBottom; self.header.borderWidth = palette.borderWidth;
  self.previewHost.fillColor = palette.controlSurface; self.previewHost.borderColor = palette.controlBorder; self.previewHost.borderWidth = palette.borderWidth; self.previewHost.borderEdges = TLBorderEdgeAll; self.previewHost.cornerRadius = palette.radiusMedium;
  for (NSTextField *label in @[self.sectionLabel, self.nameLabel, self.emptyTitle]) { label.textColor = palette.appText; label.font = palette.labelFont; }
  self.nameLabel.font = palette.titleFont; self.emptyTitle.font = palette.titleFont;
  for (NSTextField *label in @[self.conversationLabel, self.detailLabel, self.counterLabel, self.hintLabel, self.emptyDetail]) { label.textColor = palette.textMuted; label.font = palette.smallFont; }
  self.emptyDetail.font = palette.bodyFont;
  self.saveButton.palette = palette; self.finderButton.palette = palette;
  self.previousButton.palette = palette; self.nextButton.palette = palette;
  for (TLAttachmentCard *card in self.cards) card.palette = palette;
  self.textView.backgroundColor = palette.controlSurface; self.textView.textColor = palette.controlText; self.textView.insertionPointColor = palette.controlText;
  self.textView.font = palette.markdownCodeFont;
  if (self.preview) [self.preview refreshPreviewItem];
  [self updateResponsiveLayout];
}
- (void)windowDidResize:(NSNotification *)notification { [self updateResponsiveLayout]; }
- (void)updateResponsiveLayout {
  CGFloat width = NSWidth(self.window.contentView.bounds);
  BOOL compact = width < self.palette.attachmentViewerMinimumWidth + self.palette.attachmentViewerSidebarWidth;
  self.sidebar.hidden = compact;
  self.headerLeading.constant = compact ? 0 : self.palette.attachmentViewerSidebarWidth;
  self.hintLabel.hidden = width < self.palette.attachmentViewerWidth;
}
- (void)embedPreview:(NSView *)view {
  view.translatesAutoresizingMaskIntoConstraints = NO; [self.previewHost addSubview:view];
  CGFloat inset = self.palette.space2;
  [NSLayoutConstraint activateConstraints:@[[view.leadingAnchor constraintEqualToAnchor:self.previewHost.leadingAnchor constant:inset], [view.trailingAnchor constraintEqualToAnchor:self.previewHost.trailingAnchor constant:-inset], [view.topAnchor constraintEqualToAnchor:self.previewHost.topAnchor constant:inset], [view.bottomAnchor constraintEqualToAnchor:self.previewHost.bottomAnchor constant:-inset]]];
}
- (void)clearPreview {
  self.previewGeneration++;
  [self.preview close]; [self.preview removeFromSuperview]; self.preview = nil;
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
  [self.cards enumerateObjectsUsingBlock:^(TLAttachmentCard *card, NSUInteger cardIndex, BOOL *stop) { card.selected = cardIndex == index; }];
  TLAttachmentCard *card = self.cards[index]; card.subtitle = item.detail; card.fileURL = URL;
  [card scrollRectToVisible:card.bounds];
  self.emptyState.hidden = NO;
  self.emptyTitle.stringValue = URL ? (item.directory ? @"Folder attachment" : @"Loading preview…") : @"File unavailable";
  self.emptyDetail.stringValue = URL ? (item.directory ? @"Show this folder in Finder to explore its contents, or save a copy." : @"Preparing your attachment.") : @"The saved file could not be found or read. It may have been moved or deleted.";
  if (!URL || item.directory) return;
  UTType *type = [UTType typeWithFilenameExtension:item.name.pathExtension];
  NSSet *textExtensions = [NSSet setWithArray:@[@"md", @"txt", @"csv", @"tsv", @"json", @"log", @"yaml", @"yml", @"toml", @"py", @"js", @"ts", @"jsx", @"tsx", @"sh", @"m", @"h", @"swift", @"rs", @"go"]];
  if ([type conformsToType:UTTypePlainText] || [type conformsToType:UTTypeSourceCode] || [textExtensions containsObject:item.name.pathExtension.lowercaseString]) {
    [self loadTextAtURL:URL]; return;
  }
  self.emptyState.hidden = YES;
  self.preview = [[QLPreviewView alloc] initWithFrame:self.previewHost.bounds style:QLPreviewViewStyleNormal];
  self.preview.autostarts = NO; self.preview.shouldCloseWithWindow = NO;
  [self embedPreview:self.preview]; self.preview.previewItem = URL;
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
      controller.textScroll = [[NSScrollView alloc] init]; controller.textScroll.hasVerticalScroller = YES; controller.textScroll.autohidesScrollers = YES;
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
  [super showWindow:sender];
  [self.window makeKeyAndOrderFront:sender];
  if (!self.keyMonitor) {
    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
      TLAttachmentViewerWindowController *controller = weakSelf;
      if (!controller || event.window != controller.window || controller.window.attachedSheet) return event;
      if (event.keyCode == 53) { [controller close]; return nil; }
      if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqual:@"["]) { [controller previous:nil]; return nil; }
      if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers isEqual:@"]"]) { [controller next:nil]; return nil; }
      return event;
    }];
  }
}
- (void)windowWillClose:(NSNotification *)notification {
  if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor]; self.keyMonitor = nil;
  [self clearPreview];
}
- (void)dealloc { if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor]; [_preview close]; }
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
