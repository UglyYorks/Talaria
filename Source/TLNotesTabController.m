#import "TLNotesTabController.h"
#import "UIComponents.h"

@interface TLNotesTabController () <NSTextViewDelegate>
@property (nonatomic, strong) NSView *notesArticleView;
@property (nonatomic, strong, readwrite) TLMessageInput *notesMessageInput;
@property (nonatomic, strong, readwrite) NSTextView *notesPromptTextView;
@property (nonatomic, strong) NSLayoutConstraint *notesMessageInputWidthConstraint;
@property (nonatomic, strong) TLBrandMarkView *brandMarkView;
@end

@implementation TLNotesTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super initWithPalette:palette];
  if (self) {
    _inputEnabled = YES;
    [self buildNotesTabContent];
  }
  return self;
}

- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette];
  self.brandMarkView.palette = palette;
  self.notesMessageInput.palette = palette;
  [self updateNotesPromptControlState];
}

- (void)setInputEnabled:(BOOL)inputEnabled {
  _inputEnabled = inputEnabled;
  [self updateNotesPromptControlState];
}

- (void)close {
  [super close];
  self.notesPromptTextView.delegate = nil;
  self.notesMessageInput.sendButton.target = nil;
  self.sendPromptHandler = nil;
}

- (NSView *)buildNotesTabContent {
  TLThemePalette *palette = self.palette;
  TLTokenView *content = [[TLTokenView alloc] init];
  content.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:content keyPath:@"fillColor" token:@"tabBackground"];
  self.view = content;

  NSView *vaultSidebar = [self notesVaultSidebarViewWithPalette:palette];
  NSView *article = [self notesArticleScrollViewWithPalette:palette];
  self.notesArticleView = article;
  for (NSView *view in @[
    vaultSidebar,
    article,
  ]) {
    [content addSubview:view];
  }
  self.notesMessageInput = [self buildNotesMessageInputWithPalette:palette];
  [content addSubview:self.notesMessageInput];

  NSLayoutConstraint *vaultWidthConstraint = [vaultSidebar.widthAnchor constraintEqualToConstant:palette.sidebarWidth + palette.space6];
  vaultWidthConstraint.priority = NSLayoutPriorityDefaultHigh;
  NSLayoutConstraint *articleMinimumWidthConstraint = [article.widthAnchor constraintGreaterThanOrEqualToConstant:palette.messageInputMinWidth];
  articleMinimumWidthConstraint.priority = NSLayoutPriorityDefaultLow;
  CGFloat initialPromptWidth = [self notesMessageInputWidthForArticleWidth:palette.messageInputMaxWidth + (palette.space11 * 2.0)];
  self.notesMessageInputWidthConstraint = [self.notesMessageInput.widthAnchor constraintEqualToConstant:initialPromptWidth];
  self.notesMessageInputWidthConstraint.priority = NSLayoutPriorityWindowSizeStayPut - 1.0;
  NSLayoutConstraint *notesInputLeadingConstraint =
    [self.notesMessageInput.leadingAnchor constraintGreaterThanOrEqualToAnchor:article.leadingAnchor
                                                                       constant:palette.space11];
  NSLayoutConstraint *notesInputTrailingConstraint =
    [self.notesMessageInput.trailingAnchor constraintLessThanOrEqualToAnchor:article.trailingAnchor
                                                                     constant:-palette.space11];
  notesInputLeadingConstraint.priority = NSLayoutPriorityDefaultLow;
  notesInputTrailingConstraint.priority = NSLayoutPriorityDefaultLow;

  [NSLayoutConstraint activateConstraints:@[
    [vaultSidebar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
    [vaultSidebar.topAnchor constraintEqualToAnchor:content.topAnchor],
    [vaultSidebar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    vaultWidthConstraint,

    [article.leadingAnchor constraintEqualToAnchor:vaultSidebar.trailingAnchor],
    [article.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    [article.topAnchor constraintEqualToAnchor:content.topAnchor],
    [article.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    articleMinimumWidthConstraint,

    [self.notesMessageInput.centerXAnchor constraintEqualToAnchor:article.centerXAnchor],
    [self.notesMessageInput.widthAnchor constraintGreaterThanOrEqualToConstant:palette.messageInputMinWidth],
    [self.notesMessageInput.widthAnchor constraintLessThanOrEqualToConstant:palette.messageInputMaxWidth],
    notesInputLeadingConstraint,
    notesInputTrailingConstraint,
    self.notesMessageInputWidthConstraint,
    [self.notesMessageInput.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-palette.space10],
  ]];

  [self updateNotesPromptControlState];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateNotesMessageInputWidth];
  });

  return content;
}

- (TLMessageInput *)buildNotesMessageInputWithPalette:(TLThemePalette *)palette {
  TLMessageInput *messageInput = [[TLMessageInput alloc] init];
  messageInput.palette = palette;
  messageInput.layer.zPosition = 20.0;
  self.notesPromptTextView = messageInput.textView;
  self.notesPromptTextView.delegate = self;
  messageInput.sendButton.target = self;
  messageInput.sendButton.action = @selector(sendNotesPrompt:);
  return messageInput;
}

- (NSView *)notesVaultSidebarViewWithPalette:(TLThemePalette *)palette {
  TLTokenView *sidebar = [[TLTokenView alloc] init];
  sidebar.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:sidebar keyPath:@"fillColor" token:@"sidebarSurface"];
  [self bindColorForObject:sidebar keyPath:@"borderColor" token:@"sidebarBorder"];
  sidebar.borderWidth = palette.borderWidth;
  sidebar.borderEdges = TLBorderEdgeRight;

  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeWidth;
  stack.distribution = NSStackViewDistributionGravityAreas;
  stack.spacing = palette.space0;
  [sidebar addSubview:stack];

  NSView *header = [self notesVaultHeaderWithPalette:palette];
  NSView *search = [self notesSearchFieldWithPalette:palette];
  [stack addArrangedSubview:header];
  [stack setCustomSpacing:palette.space8 afterView:header];
  [stack addArrangedSubview:search];
  [stack setCustomSpacing:palette.space8 afterView:search];

  NSArray<NSDictionary<NSString *, id> *> *sections = @[
    @{
      @"title": @"Advanced topics",
      @"expanded": @NO,
      @"items": @[],
    },
    @{
      @"title": @"Concepts",
      @"expanded": @NO,
      @"items": @[],
    },
    @{
      @"title": @"Extending Talaria",
      @"expanded": @YES,
      @"items": @[
        @"Community plugins",
        @"CSS snippets",
        @"Plugin security",
        @"Themes",
      ],
    },
    @{
      @"title": @"Getting started",
      @"expanded": @YES,
      @"items": @[
        @"Create a vault",
        @"Create your first note",
        @"Link notes",
        @"Sync notes across devices",
      ],
    },
    @{
      @"title": @"Linking notes and files",
      @"expanded": @NO,
      @"items": @[],
    },
  ];
  for (NSDictionary<NSString *, id> *section in sections) {
    [stack addArrangedSubview:[self notesNavigationSectionWithTitle:section[@"title"]
                                                           expanded:[section[@"expanded"] boolValue]
                                                              items:section[@"items"]
                                                       selectedItem:@"Themes"
                                                            palette:palette]];
  }

  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:palette.space12],
    [stack.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-palette.space12],
    [stack.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:palette.space12],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:sidebar.bottomAnchor constant:-palette.space12],
  ]];

  return sidebar;
}

- (NSView *)notesVaultHeaderWithPalette:(TLThemePalette *)palette {
  NSView *header = [[NSView alloc] init];
  header.translatesAutoresizingMaskIntoConstraints = NO;

  TLBrandMarkView *markView = [[TLBrandMarkView alloc] init];
  markView.translatesAutoresizingMaskIntoConstraints = NO;
  markView.palette = palette;
  self.brandMarkView = markView;
  [header addSubview:markView];

  NSTextField *titleLabel = [self labelWithString:@"Talaria Notes" font:palette.markdownHeading2Font colorToken:@"appText"];
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [header addSubview:titleLabel];

  [NSLayoutConstraint activateConstraints:@[
    [header.heightAnchor constraintEqualToConstant:palette.topbarHeight],
    [markView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
    [markView.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [markView.widthAnchor constraintEqualToConstant:palette.space10],
    [markView.heightAnchor constraintEqualToConstant:palette.space10],
    [titleLabel.leadingAnchor constraintEqualToAnchor:markView.trailingAnchor constant:palette.space4],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor],
    [titleLabel.centerYAnchor constraintEqualToAnchor:markView.centerYAnchor],
  ]];

  return header;
}

- (NSView *)notesSearchFieldWithPalette:(TLThemePalette *)palette {
  TLTokenView *field = [[TLTokenView alloc] init];
  field.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:field keyPath:@"fillColor" token:@"controlSurface"];
  [self bindColorForObject:field keyPath:@"borderColor" token:@"controlBorder"];
  field.borderWidth = palette.borderWidth;
  field.borderEdges = TLBorderEdgeAll;
  field.cornerRadius = palette.space3;

  NSImageView *searchIcon = [self notesIconViewWithSystemName:@"magnifyingglass"
                                     accessibilityDescription:@"Search"
                                                        colorToken:@"textMuted"
                                                    pointSize:palette.smallFont.pointSize];
  [field addSubview:searchIcon];

  NSTextField *placeholder = [self labelWithString:@"Search page or heading..." font:palette.smallFont colorToken:@"textMuted"];
  placeholder.lineBreakMode = NSLineBreakByTruncatingTail;
  [field addSubview:placeholder];

  [NSLayoutConstraint activateConstraints:@[
    [field.heightAnchor constraintEqualToConstant:palette.fieldHeight - palette.space2],
    [searchIcon.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:palette.space4],
    [searchIcon.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
    [searchIcon.widthAnchor constraintEqualToConstant:palette.space8],
    [searchIcon.heightAnchor constraintEqualToConstant:palette.space8],
    [placeholder.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:palette.space3],
    [placeholder.trailingAnchor constraintLessThanOrEqualToAnchor:field.trailingAnchor constant:-palette.space4],
    [placeholder.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
  ]];

  return field;
}

- (NSView *)notesNavigationSectionWithTitle:(NSString *)title
                                   expanded:(BOOL)expanded
                                      items:(NSArray<NSString *> *)items
                               selectedItem:(NSString *)selectedItem
                                    palette:(TLThemePalette *)palette {
  NSStackView *sectionStack = [[NSStackView alloc] init];
  sectionStack.translatesAutoresizingMaskIntoConstraints = NO;
  sectionStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  sectionStack.alignment = NSLayoutAttributeWidth;
  sectionStack.distribution = NSStackViewDistributionGravityAreas;
  sectionStack.spacing = palette.space0;

  NSString *chevron = expanded ? @"chevron.down" : @"chevron.right";
  [sectionStack addArrangedSubview:[self notesNavigationRowWithTitle:title
                                                            selected:NO
                                                               level:0
                                                      systemIconName:chevron
                                                             palette:palette]];
  if (expanded) {
    for (NSString *item in items) {
      [sectionStack addArrangedSubview:[self notesNavigationRowWithTitle:item
                                                                selected:[item isEqualToString:selectedItem]
                                                                   level:1
                                                          systemIconName:@""
                                                                 palette:palette]];
    }
  }

  return sectionStack;
}

- (NSView *)notesNavigationRowWithTitle:(NSString *)title
                               selected:(BOOL)selected
                                  level:(NSUInteger)level
                         systemIconName:(NSString *)systemIconName
                                palette:(TLThemePalette *)palette {
  TLTokenView *row = [[TLTokenView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:row keyPath:@"fillColor" token:selected ? @"chromeHoverSurface" : @"transparentSurface"];
  [self bindColorForObject:row keyPath:@"borderColor" token:@"transparentSurface"];
  row.borderEdges = TLBorderEdgeNone;
  row.cornerRadius = palette.radiusMedium;

  NSImageView *iconView = [self notesIconViewWithSystemName:systemIconName
                                   accessibilityDescription:title
                                                      colorToken:selected ? @"markdownLinkText" : @"labelText"
                                                  pointSize:palette.smallFont.pointSize];
  [row addSubview:iconView];

  NSTextField *titleLabel = [self labelWithString:title
                                             font:selected ? palette.labelFont : palette.bodyFont
                                            colorToken:selected ? @"markdownLinkText" : @"labelText"];
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [row addSubview:titleLabel];

  TLTokenView *accent = [[TLTokenView alloc] init];
  accent.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:accent keyPath:@"fillColor" token:selected ? @"markdownLinkText" : @"transparentSurface"];
  [self bindColorForObject:accent keyPath:@"borderColor" token:@"transparentSurface"];
  accent.borderEdges = TLBorderEdgeNone;
  accent.cornerRadius = palette.radiusPill;
  [row addSubview:accent];

  CGFloat leadingInset = palette.space2 + (CGFloat)level * palette.space11;
  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:palette.fieldHeight],
    [accent.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [accent.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [accent.widthAnchor constraintEqualToConstant:selected ? palette.borderWidth + palette.space2 : palette.space0],
    [accent.heightAnchor constraintEqualToConstant:palette.fieldHeight - palette.space3],
    [iconView.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:leadingInset],
    [iconView.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [iconView.widthAnchor constraintEqualToConstant:palette.space8],
    [iconView.heightAnchor constraintEqualToConstant:palette.space8],
    [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:palette.space4],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor constant:-palette.space4],
    [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
  ]];

  return row;
}

- (NSView *)notesArticleScrollViewWithPalette:(TLThemePalette *)palette {
  NSScrollView *scrollView = [[NSScrollView alloc] init];
  scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.hasVerticalScroller = YES;
  scrollView.autohidesScrollers = YES;
  scrollView.drawsBackground = NO;

  TLFlippedView *documentView = [[TLFlippedView alloc] init];
  documentView.translatesAutoresizingMaskIntoConstraints = NO;
  scrollView.documentView = documentView;

  NSStackView *stack = [[NSStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.distribution = NSStackViewDistributionFill;
  stack.spacing = palette.space0;
  [documentView addSubview:stack];

  NSTextField *titleLabel = [self labelWithString:@"Themes" font:palette.markdownHeading1Font colorToken:@"appText"];
  NSTextField *summaryLabel = [self wrappingLabelWithString:@"Learn how to change the look and feel of your workspace using themes built by the community."
                                                       font:palette.messageBodyFont
                                                      colorToken:@"labelText"];
  titleLabel.alignment = NSTextAlignmentLeft;
  summaryLabel.alignment = NSTextAlignmentLeft;
  [stack addArrangedSubview:titleLabel];
  [stack setCustomSpacing:palette.space12 afterView:titleLabel];
  [stack addArrangedSubview:summaryLabel];
  [stack setCustomSpacing:palette.space16 afterView:summaryLabel];

  NSView *browseSection = [self notesArticleSectionWithTitle:@"Browse themes"
                                                       steps:@[
                                                         @"Open Settings.",
                                                         @"Select Turn on community plugins, then open Community themes.",
                                                         @"Select Browse to list available community themes.",
                                                       ]
                                                   paragraph:nil
                                                     palette:palette];
  NSView *installSection = [self notesArticleSectionWithTitle:@"Install a new theme"
                                                        steps:@[
                                                          @"Open Settings.",
                                                          @"Under Appearance > Themes, select Manage.",
                                                          @"Choose a theme, then select Install and use.",
                                                        ]
                                                    paragraph:@"The selected theme is applied immediately. To return to the default look, stop using the active theme."
                                                      palette:palette];
  NSView *updateSection = [self notesArticleSectionWithTitle:@"Update themes"
                                                       steps:@[
                                                         @"Open Settings.",
                                                         @"Under Appearance > Current community themes, select Check for updates.",
                                                         @"If updates are available, select Update all.",
                                                       ]
                                                   paragraph:@"Themes do not update automatically, so review updates before applying them across a vault."
                                                     palette:palette];
  for (NSView *section in @[
    browseSection,
    installSection,
    updateSection,
  ]) {
    [stack addArrangedSubview:section];
    [section.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [stack setCustomSpacing:palette.space16 afterView:section];
  }

  [NSLayoutConstraint activateConstraints:@[
    [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:palette.space16],
    [stack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-palette.space16],
    [stack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:palette.space12 + palette.space11],
    [stack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-(palette.space16 + palette.composerButtonHeight + palette.space10)],
    [titleLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    [summaryLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
  ]];

  return scrollView;
}

- (NSView *)notesArticleSectionWithTitle:(NSString *)title
                                   steps:(NSArray<NSString *> *)steps
                               paragraph:(nullable NSString *)paragraph
                                 palette:(TLThemePalette *)palette {
  NSStackView *sectionStack = [[NSStackView alloc] init];
  sectionStack.translatesAutoresizingMaskIntoConstraints = NO;
  sectionStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  sectionStack.alignment = NSLayoutAttributeLeading;
  sectionStack.distribution = NSStackViewDistributionFill;
  sectionStack.spacing = palette.space0;

  NSTextField *titleLabel = [self labelWithString:title font:palette.markdownHeading2Font colorToken:@"appText"];
  titleLabel.alignment = NSTextAlignmentLeft;
  [sectionStack addArrangedSubview:titleLabel];
  [titleLabel.widthAnchor constraintEqualToAnchor:sectionStack.widthAnchor].active = YES;
  [sectionStack setCustomSpacing:palette.space8 afterView:titleLabel];
  NSView *divider = [self notesDividerViewWithPalette:palette];
  [sectionStack addArrangedSubview:divider];
  [divider.widthAnchor constraintEqualToAnchor:sectionStack.widthAnchor].active = YES;
  [sectionStack setCustomSpacing:palette.space8 afterView:divider];

  for (NSUInteger index = 0; index < steps.count; index += 1) {
    NSView *stepRow = [self notesOrderedLineWithNumber:index + 1 text:steps[index] palette:palette];
    [sectionStack addArrangedSubview:stepRow];
    [stepRow.widthAnchor constraintEqualToAnchor:sectionStack.widthAnchor].active = YES;
    [sectionStack setCustomSpacing:palette.space3 afterView:stepRow];
  }

  if (paragraph.length > 0) {
    NSTextField *paragraphLabel = [self wrappingLabelWithString:paragraph font:palette.messageBodyFont colorToken:@"labelText"];
    paragraphLabel.alignment = NSTextAlignmentLeft;
    [sectionStack setCustomSpacing:palette.space8 afterView:sectionStack.arrangedSubviews.lastObject];
    [sectionStack addArrangedSubview:paragraphLabel];
    [paragraphLabel.widthAnchor constraintEqualToAnchor:sectionStack.widthAnchor].active = YES;
  }
  [sectionStack setCustomSpacing:palette.space16 afterView:sectionStack.arrangedSubviews.lastObject];

  return sectionStack;
}

- (NSView *)notesOrderedLineWithNumber:(NSUInteger)number text:(NSString *)text palette:(TLThemePalette *)palette {
  NSView *row = [[NSView alloc] init];
  row.translatesAutoresizingMaskIntoConstraints = NO;

  NSTextField *numberLabel = [self labelWithString:[NSString stringWithFormat:@"%lu.", (unsigned long)number]
                                              font:palette.messageBodyFont
                                             colorToken:@"textMuted"];
  numberLabel.alignment = NSTextAlignmentRight;
  [row addSubview:numberLabel];

  NSTextField *textLabel = [self wrappingLabelWithString:text font:palette.messageBodyFont colorToken:@"labelText"];
  textLabel.alignment = NSTextAlignmentLeft;
  [row addSubview:textLabel];

  [NSLayoutConstraint activateConstraints:@[
    [numberLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
    [numberLabel.widthAnchor constraintEqualToConstant:palette.space11],
    [numberLabel.firstBaselineAnchor constraintEqualToAnchor:textLabel.firstBaselineAnchor],
    [textLabel.leadingAnchor constraintEqualToAnchor:numberLabel.trailingAnchor constant:palette.space4],
    [textLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [textLabel.topAnchor constraintEqualToAnchor:row.topAnchor],
    [textLabel.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
  ]];

  return row;
}

- (NSView *)notesDividerViewWithPalette:(TLThemePalette *)palette {
  TLTokenView *divider = [[TLTokenView alloc] init];
  divider.translatesAutoresizingMaskIntoConstraints = NO;
  [self bindColorForObject:divider keyPath:@"fillColor" token:@"transparentSurface"];
  [self bindColorForObject:divider keyPath:@"borderColor" token:@"topbarBorder"];
  divider.borderWidth = palette.borderWidth;
  divider.borderEdges = TLBorderEdgeTop;
  [divider.heightAnchor constraintEqualToConstant:palette.borderWidth].active = YES;
  return divider;
}

- (NSImageView *)notesIconViewWithSystemName:(NSString *)systemName
                    accessibilityDescription:(NSString *)accessibilityDescription
                                  colorToken:(NSString *)colorToken
                                   pointSize:(CGFloat)pointSize {
  NSImageView *iconView = [[NSImageView alloc] init];
  iconView.translatesAutoresizingMaskIntoConstraints = NO;
  iconView.imageAlignment = NSImageAlignCenter;
  iconView.imageScaling = NSImageScaleProportionallyDown;
  NSImage *image = [self symbolImageNamed:systemName accessibilityDescription:accessibilityDescription];
  if (@available(macOS 11.0, *)) {
    NSImageSymbolConfiguration *configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleMedium];
    image = [image imageWithSymbolConfiguration:configuration] ?: image;
  }
  image.template = YES;
  iconView.image = image;
  [self bindColorForObject:iconView keyPath:@"contentTintColor" token:colorToken];
  return iconView;
}

- (CGFloat)notesMessageInputWidthForArticleWidth:(CGFloat)articleWidth {
  CGFloat availableWidth = articleWidth > self.palette.space0
    ? articleWidth - (self.palette.space11 * 2.0)
    : self.palette.messageInputMaxWidth;
  return MIN(self.palette.messageInputMaxWidth,
             MAX(self.palette.messageInputMinWidth, availableWidth));
}

- (void)updateNotesMessageInputWidth {
  if (!self.notesMessageInputWidthConstraint || !self.notesArticleView) {
    return;
  }

  [self.notesArticleView.superview layoutSubtreeIfNeeded];
  self.notesMessageInputWidthConstraint.constant =
    [self notesMessageInputWidthForArticleWidth:NSWidth(self.notesArticleView.bounds)];
}

- (void)updateNotesPromptControlState {
  if (!self.notesMessageInput || !self.notesPromptTextView) {
    return;
  }

  [self.notesMessageInput recalculateHeight];
  BOOL inputEnabled = self.inputEnabled;
  NSString *prompt = [self.notesPromptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  BOOL sendEnabled = inputEnabled && prompt.length > 0;
  self.notesPromptTextView.editable = inputEnabled;
  self.notesPromptTextView.selectable = YES;
  self.notesMessageInput.sendButton.enabled = sendEnabled;
  self.notesMessageInput.sendButton.alphaValue = sendEnabled ? 1.0 : self.palette.disabledOpacity;
}


- (void)sendNotesPrompt:(id)sender {
  if (!self.inputEnabled || self.isClosed) return;
  NSString *prompt = [self.notesPromptTextView.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (prompt.length == 0 || !self.sendPromptHandler) return;
  self.notesPromptTextView.string = @"";
  [self updateNotesPromptControlState];
  self.sendPromptHandler(prompt);
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
  if (commandSelector == @selector(insertNewline:) &&
      !(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)) {
    [self sendNotesPrompt:textView];
    return YES;
  }
  return NO;
}

- (void)textDidChange:(NSNotification *)notification {
  [self updateNotesPromptControlState];
}

- (NSImage *)symbolImageNamed:(NSString *)name accessibilityDescription:(NSString *)description {
  return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
}
@end
