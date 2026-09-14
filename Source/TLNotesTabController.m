#import "TLNotesTabController.h"
#import "design_system/TLCollectionEditorView.h"
#import "design_system/TLThemedButton.h"

@interface TLNotesTabController () <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, copy) TLNotesRequest request;
@property (nonatomic) NSInteger agentID;
@property (nonatomic, strong) TLCollectionEditorView *surface;
@property (nonatomic, strong) NSTextField *heading, *subtitle, *status, *pathLabel, *emptyLabel;
@property (nonatomic, strong) NSTextField *collectionEmptyLabel;
@property (nonatomic, strong) NSSearchField *search;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSScrollView *listScroll, *editorScroll;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) TLThemedButton *createButton, *refreshButton, *saveButton, *duplicateButton, *deleteButton, *backButton;
@property (nonatomic, copy) NSArray<NSDictionary *> *notes;
@property (nonatomic, copy, nullable) NSDictionary *note;
@property (nonatomic, copy, nullable) NSDictionary *pendingCreate;
@property (nonatomic, copy, nullable) dispatch_block_t afterSave;
@property (nonatomic) BOOL busy, saving, dirty, failed, selecting;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) NSTimer *saveTimer, *refreshTimer;
@end

@implementation TLNotesTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette agentID:(NSInteger)agentID request:(TLNotesRequest)request {
  if ((self = [super initWithPalette:palette])) {
    _agentID = agentID; _request = [request copy]; _notes = @[];
    [self buildView]; [self applyPalette:palette]; [self updateControls];
    __weak typeof(self) weakSelf = self;
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) {
      typeof(self) controller = weakSelf;
      if (!controller) { [timer invalidate]; return; }
      if (controller.view.window.isVisible && !controller.view.isHiddenOrHasHiddenAncestor &&
          !controller.dirty && !controller.failed && !controller.busy) [controller refresh:nil];
    }];
  }
  return self;
}
- (NSArray<TLThemedButton *> *)buttons {
  return @[self.createButton, self.refreshButton, self.saveButton, self.duplicateButton, self.deleteButton, self.backButton];
}
- (TLThemedButton *)button:(NSString *)title action:(SEL)action parent:(NSView *)parent {
  TLThemedButton *button = [TLThemedButton buttonWithTitle:title target:self action:action];
  button.palette = self.palette;
  [parent addSubview:button];
  return button;
}
- (void)buildView {
  self.surface = [TLCollectionEditorView new]; self.view = self.surface;
  self.heading = [self labelWithString:@"Notes" font:self.palette.titleFont colorToken:@"appText"];
  self.subtitle = [self labelWithString:@"A place to write and think with your agent." font:self.palette.bodyFont colorToken:@"textMuted"];
  for (NSView *view in @[self.heading, self.subtitle]) [self.surface.header addSubview:view];
  self.createButton = [self button:@"New note" action:@selector(newNote:) parent:self.surface.header];
  self.createButton.primary = YES;
  self.refreshButton = [self button:@"Refresh" action:@selector(refresh:) parent:self.surface.header];
  self.search = [NSSearchField new]; self.search.placeholderString = @"Search notes";
  self.search.delegate = self; self.search.sendsSearchStringImmediately = NO;
  self.search.sendsWholeSearchString = YES; self.search.target = self; self.search.action = @selector(searchChanged:);
  [self.surface.collection addSubview:self.search];
  self.table = [NSTableView new]; self.table.headerView = nil;
  self.table.dataSource = self; self.table.delegate = self;
  self.table.target = self; self.table.action = @selector(revealSelectedNote:);
  self.table.rowSizeStyle = NSTableViewRowSizeStyleCustom;
  self.table.style = NSTableViewStylePlain;
  self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"note"];
  column.minWidth = 0; [self.table addTableColumn:column];
  self.table.accessibilityLabel = @"Notes";
  self.listScroll = [NSScrollView new]; self.listScroll.hasVerticalScroller = YES;
  self.listScroll.autohidesScrollers = YES; self.listScroll.drawsBackground = NO;
  self.listScroll.documentView = self.table;
  [self.surface.collection addSubview:self.listScroll];
  self.collectionEmptyLabel = [self wrappingLabelWithString:@"No notes yet.\nCreate your first note above." font:self.palette.bodyFont colorToken:@"textMuted"];
  self.collectionEmptyLabel.translatesAutoresizingMaskIntoConstraints = YES;
  [self.surface.collection addSubview:self.collectionEmptyLabel];
  self.backButton = [self button:@"All notes" action:@selector(showList:) parent:self.surface.editor];
  self.deleteButton = [self button:@"Delete" action:@selector(deleteNote:) parent:self.surface.editor];
  self.pathLabel = [self labelWithString:@"" font:self.palette.smallFont colorToken:@"textMuted"];
  self.pathLabel.selectable = YES;
  [self.surface.editor addSubview:self.pathLabel];
  self.textView = [NSTextView new]; self.textView.richText = NO; self.textView.importsGraphics = NO;
  self.textView.allowsUndo = YES; self.textView.delegate = self;
  self.textView.automaticQuoteSubstitutionEnabled = NO;
  self.textView.automaticDashSubstitutionEnabled = NO;
  self.textView.automaticTextReplacementEnabled = NO;
  self.textView.automaticLinkDetectionEnabled = NO;
  self.textView.verticallyResizable = YES; self.textView.horizontallyResizable = NO;
  self.textView.autoresizingMask = NSViewWidthSizable;
  self.textView.textContainer.widthTracksTextView = YES;
  self.textView.accessibilityLabel = @"Markdown note";
  self.editorScroll = [NSScrollView new]; self.editorScroll.hasVerticalScroller = YES;
  self.editorScroll.autohidesScrollers = YES; self.editorScroll.documentView = self.textView;
  [self.surface.editor addSubview:self.editorScroll];
  self.emptyLabel = [self wrappingLabelWithString:@"Your notes, shared with your agent.\n\nCreate a note to get started, or select one from the list."
    font:self.palette.bodyFont colorToken:@"textMuted"];
  [self.surface.editor addSubview:self.emptyLabel];
  self.status = [self labelWithString:self.agentID > 0 ? @"Notes are stored as Markdown in the agent’s VM." : @"Create an agent to start using Notes."
    font:self.palette.smallFont colorToken:@"textMuted"];
  self.status.toolTip = self.status.stringValue;
  [self.surface.footer addSubview:self.status];
  self.saveButton = [self button:@"Save" action:@selector(save:) parent:self.surface.footer];
  self.duplicateButton = [self button:@"Save copy" action:@selector(saveCopy:) parent:self.surface.footer];
  for (NSView *view in @[self.heading, self.subtitle, self.pathLabel, self.emptyLabel, self.status]) view.translatesAutoresizingMaskIntoConstraints = YES;
}
- (void)viewDidLayout {
  [super viewDidLayout];
  TLThemePalette *p = self.palette;
  CGFloat inset = p.space12, row = p.settingsActionHeight, gap = p.space8;
  CGFloat width = NSWidth(self.surface.header.bounds), height = NSHeight(self.surface.header.bounds);
  self.heading.frame = NSMakeRect(inset, height - inset - row, MAX(0, width - inset * 2), row);
  CGFloat newWidth = self.createButton.intrinsicContentSize.width, refreshWidth = self.refreshButton.intrinsicContentSize.width;
  self.createButton.frame = NSMakeRect(MAX(inset, width - inset - newWidth), height - inset - row, newWidth, row);
  self.heading.frame = NSMakeRect(inset, height - inset - row, MAX(0, width - newWidth - inset * 3), row);
  self.refreshButton.frame = NSMakeRect(MAX(inset, width - inset - refreshWidth), inset, refreshWidth, row);
  self.subtitle.hidden = self.surface.compact;
  self.subtitle.frame = NSMakeRect(inset, inset, MAX(0, width - refreshWidth - inset * 2 - gap), row);
  width = NSWidth(self.surface.collection.bounds); height = NSHeight(self.surface.collection.bounds);
  self.search.frame = NSMakeRect(inset, MAX(0, height - inset - row), MAX(0, width - inset * 2), row);
  self.listScroll.frame = NSMakeRect(0, 0, width, MAX(0, height - row - inset * 2));
  self.collectionEmptyLabel.frame = NSMakeRect(inset, MAX(0, height - row * 4 - inset * 2), MAX(0, width - inset * 2), row * 3);
  self.table.tableColumns.firstObject.width = MAX(0, self.listScroll.contentSize.width);
  width = NSWidth(self.surface.editor.bounds); height = NSHeight(self.surface.editor.bounds);
  CGFloat deleteWidth = self.deleteButton.intrinsicContentSize.width, backWidth = self.backButton.intrinsicContentSize.width;
  self.backButton.hidden = !self.surface.compact;
  self.backButton.frame = NSMakeRect(inset, MAX(0, height - row - inset), backWidth, row);
  self.deleteButton.frame = NSMakeRect(MAX(inset, width - inset - deleteWidth), MAX(0, height - row - inset), deleteWidth, row);
  CGFloat pathX = self.surface.compact ? inset + backWidth + gap : inset;
  self.pathLabel.frame = NSMakeRect(pathX, MAX(0, height - row - inset), MAX(0, width - pathX - deleteWidth - inset - gap), row);
  self.editorScroll.frame = NSMakeRect(inset, inset, MAX(0, width - inset * 2), MAX(0, height - row - inset * 3));
  self.textView.minSize = NSMakeSize(0, self.editorScroll.contentSize.height);
  self.textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
  self.textView.frame = NSMakeRect(0, 0, self.editorScroll.contentSize.width, MAX(self.textView.frame.size.height, self.editorScroll.contentSize.height));
  self.textView.textContainer.containerSize = NSMakeSize(self.editorScroll.contentSize.width, CGFLOAT_MAX);
  self.emptyLabel.frame = NSInsetRect(self.surface.editor.bounds, inset * 2, inset * 2);
  width = NSWidth(self.surface.footer.bounds);
  CGFloat saveWidth = self.saveButton.intrinsicContentSize.width, copyWidth = self.duplicateButton.intrinsicContentSize.width;
  self.saveButton.frame = NSMakeRect(MAX(inset, width - inset - saveWidth), inset, saveWidth, row);
  self.duplicateButton.frame = NSMakeRect(MAX(inset, width - inset - saveWidth - gap - copyWidth), inset, copyWidth, row);
  self.status.frame = self.surface.compact ? NSMakeRect(inset, inset * 2 + row, MAX(0, width - inset * 2), row) :
    NSMakeRect(inset, inset, MAX(0, width - inset * 3 - saveWidth - (self.duplicateButton.hidden ? 0 : copyWidth + gap)), row);
}
- (void)applyPalette:(TLThemePalette *)palette {
  [super applyPalette:palette]; self.surface.palette = palette;
  self.view.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  for (TLThemedButton *button in self.buttons) button.palette = palette;
  self.search.textColor = palette.controlText; self.search.backgroundColor = palette.controlSurface;
  self.search.font = palette.bodyFont;
  self.table.backgroundColor = palette.sidebarSurface; self.table.rowHeight = palette.historyRowHeight;
  self.table.intercellSpacing = NSMakeSize(palette.space0, palette.space2);
  self.textView.font = palette.markdownCodeFont; self.textView.textColor = palette.controlText;
  self.textView.backgroundColor = palette.controlSurface; self.editorScroll.backgroundColor = palette.controlSurface;
  self.textView.insertionPointColor = palette.controlText;
  self.textView.selectedTextAttributes = @{NSBackgroundColorAttributeName:palette.itemHighlightSurface,
    NSForegroundColorAttributeName:palette.controlText};
  self.textView.textContainerInset = NSMakeSize(palette.space12, palette.space12);
  [self reloadTable]; self.surface.needsLayout = YES;
}
- (void)setStatusText:(NSString *)text {
  self.status.stringValue = text ?: @""; self.status.toolTip = text;
  self.status.accessibilityValue = text;
}
- (void)updateControls {
  BOOL ready = self.agentID > 0 && !self.closed;
  self.createButton.enabled = self.refreshButton.enabled = !self.busy && ready;
  self.search.enabled = !self.busy && ready;
  self.deleteButton.enabled = !self.busy && self.note != nil;
  self.saveButton.enabled = !self.busy && self.dirty;
  self.duplicateButton.hidden = !self.failed || !self.dirty;
  self.duplicateButton.enabled = !self.busy && self.dirty;
  self.textView.editable = self.note != nil && (!self.busy || self.saving) && !self.closed;
  self.editorScroll.hidden = self.note == nil; self.emptyLabel.hidden = self.note != nil;
  self.collectionEmptyLabel.hidden = self.notes.count > 0;
  self.collectionEmptyLabel.stringValue = self.search.stringValue.length ? @"No matching notes." : @"No notes yet.\nCreate your first note above.";
  self.deleteButton.hidden = self.note == nil;
  self.refreshButton.title = self.failed && self.dirty ? @"Reload" : @"Refresh";
  self.surface.needsLayout = YES;
}
- (void)perform:(NSDictionary *)parameters message:(NSString *)message completion:(void (^)(NSDictionary *))completion {
  if (self.closed || self.busy || !self.agentID) return;
  self.busy = YES; [self setStatusText:message]; [self updateControls];
  NSUInteger generation = self.generation;
  __weak typeof(self) weakSelf = self;
  self.request(self.agentID, parameters, ^(NSDictionary *result, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) controller = weakSelf;
      if (!controller || controller.closed || generation != controller.generation) return;
      controller.busy = NO; controller.saving = NO;
      if (error || ![result isKindOfClass:NSDictionary.class] || [result[@"conflict"] boolValue]) {
        controller.failed = YES; controller.afterSave = nil;
        [controller.saveTimer invalidate];
        [controller setStatusText:error.localizedDescription ?: result[@"message"] ?: @"Could not load notes. Try again."];
      } else {
        controller.failed = NO;
        completion(result);
      }
      [controller updateControls];
    });
  });
}
- (BOOL)validNote:(id)note {
  if (![note isKindOfClass:NSDictionary.class]) return NO;
  for (NSString *key in @[@"id", @"content", @"revision", @"path"]) if (![note[key] isKindOfClass:NSString.class]) return NO;
  return YES;
}
- (void)displayNote:(NSDictionary *)note {
  self.note = note; self.dirty = NO; self.failed = NO;
  self.textView.string = note[@"content"] ?: @"";
  [self.textView.undoManager removeAllActions];
  self.pathLabel.stringValue = note[@"path"] ?: @""; self.pathLabel.toolTip = self.pathLabel.stringValue;
  [self.textView scrollRangeToVisible:NSMakeRange(0, 0)];
  [self reloadTable]; [self updateControls];
}
- (void)reloadTable {
  self.selecting = YES; [self.table reloadData];
  NSUInteger index = [self.notes indexOfObjectPassingTest:^BOOL(NSDictionary *note, NSUInteger idx, BOOL *stop) {
    return [note[@"id"] isEqual:self.note[@"id"]];
  }];
  if (index == NSNotFound) [self.table deselectAll:nil];
  else [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
  self.selecting = NO;
}
- (void)withSavedDraft:(dispatch_block_t)action {
  if (self.busy) return;
  if (self.dirty) { self.afterSave = action; [self save:nil]; }
  else action();
}
- (void)refresh:(id)sender {
  if (self.closed || self.busy || !self.agentID) return;
  if (self.dirty) {
    if (!sender) return;
    if (self.failed) {
      NSAlert *alert = [NSAlert new]; alert.messageText = @"Reload this note?";
      alert.informativeText = @"This discards your unsaved draft and loads the version in the VM. Use Save copy to keep both versions.";
      [alert addButtonWithTitle:@"Keep Editing"]; [alert addButtonWithTitle:@"Reload"];
      if ([alert runModal] != NSAlertSecondButtonReturn) return;
      [self openNoteID:self.note[@"id"]]; return;
    }
    __weak typeof(self) weakSelf = self;
    [self withSavedDraft:^{ [weakSelf refresh:nil]; }]; return;
  }
  [self perform:@{@"action":@"list", @"query":self.search.stringValue} message:@"Refreshing notes…" completion:^(NSDictionary *result) {
    if (![result[@"notes"] isKindOfClass:NSArray.class]) { [self setStatusText:@"The VM returned an invalid notes list."]; return; }
    NSMutableArray *notes = [NSMutableArray array];
    for (id note in result[@"notes"]) {
      if (![note isKindOfClass:NSDictionary.class]) continue;
      if ([note[@"id"] isKindOfClass:NSString.class] && [note[@"title"] isKindOfClass:NSString.class] &&
          [note[@"preview"] isKindOfClass:NSString.class] && [note[@"revision"] isKindOfClass:NSString.class]) [notes addObject:note];
    }
    self.notes = notes; [self reloadTable];
    NSUInteger skipped = [result[@"skipped"] isKindOfClass:NSArray.class] ? [result[@"skipped"] count] : 0;
    [self setStatusText:skipped ? @"Some files could not be opened. Notes must be UTF-8 Markdown, up to 1 MiB." :
      [NSString stringWithFormat:@"%lu %@ · Saved in the agent’s VM", (unsigned long)notes.count, notes.count == 1 ? @"note" : @"notes"]];
    NSDictionary *selected = nil;
    for (NSDictionary *note in notes) if ([note[@"id"] isEqual:self.note[@"id"]]) selected = note;
    if (selected && ![selected[@"revision"] isEqual:self.note[@"revision"]]) [self openNoteID:selected[@"id"]];
    else if (self.note && !selected && !self.search.stringValue.length) [self displayNote:nil];
  }];
}
- (void)openNoteID:(NSString *)identity {
  if (!identity) return;
  [self perform:@{@"action":@"read", @"id":identity} message:@"Opening note…" completion:^(NSDictionary *result) {
    if (![self validNote:result[@"note"]]) { [self setStatusText:@"The VM returned an invalid note."]; return; }
    [self displayNote:result[@"note"]]; self.surface.showsEditor = YES;
    [self setStatusText:@"Saved · Markdown · Changes sync with your agent"];
  }];
}
- (void)createContent:(NSString *)content {
  if (!self.pendingCreate || ![self.pendingCreate[@"content"] isEqual:content])
    self.pendingCreate = @{@"action":@"create", @"id":[NSUUID.UUID.UUIDString.lowercaseString stringByAppendingString:@".md"], @"content":[content copy]};
  [self perform:self.pendingCreate message:@"Creating note…" completion:^(NSDictionary *result) {
    if (![self validNote:result[@"note"]]) { [self setStatusText:@"The VM returned an invalid note."]; return; }
    self.pendingCreate = nil; self.search.stringValue = @"";
    [self displayNote:result[@"note"]]; self.surface.showsEditor = YES;
    [self refresh:nil];
    [self.view.window makeFirstResponder:self.textView];
  }];
}
- (void)newNote:(id)sender {
  __weak typeof(self) weakSelf = self;
  [self withSavedDraft:^{ [weakSelf createContent:@"# Untitled note\n\n"]; }];
}
- (void)saveCopy:(id)sender { if (!self.busy && self.dirty) [self createContent:self.textView.string]; }
- (void)save:(id)sender {
  if (self.closed || self.busy || !self.dirty || !self.note) return;
  [self.saveTimer invalidate];
  NSString *content = [self.textView.string copy];
  self.saving = YES;
  [self perform:@{@"action":@"save", @"id":self.note[@"id"], @"revision":self.note[@"revision"], @"content":content}
    message:@"Saving…" completion:^(NSDictionary *result) {
      if (![self validNote:result[@"note"]] || ![result[@"note"][@"content"] isEqual:content]) {
        self.failed = YES; self.afterSave = nil; [self setStatusText:@"The save could not be confirmed. Your draft is kept."]; return;
      }
      self.note = result[@"note"];
      self.dirty = ![self.textView.string isEqual:content];
      [self setStatusText:self.dirty ? @"Unsaved changes" : @"Saved · Markdown · Changes sync with your agent"];
      if (self.dirty) [self scheduleSave];
      else if (self.afterSave) { dispatch_block_t action = self.afterSave; self.afterSave = nil; action(); }
      else [self refresh:nil];
    }];
}
- (void)scheduleSave {
  [self.saveTimer invalidate];
  __weak typeof(self) weakSelf = self;
  self.saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:NO block:^(NSTimer *timer) { [weakSelf save:nil]; }];
}
- (void)textDidChange:(NSNotification *)notification {
  if (self.closed || !self.note) return;
  self.dirty = ![self.textView.string isEqual:self.note[@"content"]];
  if (!self.failed) {
    [self setStatusText:self.dirty ? @"Unsaved changes" : @"Saved"];
    if (self.dirty) [self scheduleSave];
  }
  [self updateControls];
}
- (void)deleteNote:(id)sender {
  if (self.busy || !self.note) return;
  NSAlert *alert = [NSAlert new]; alert.messageText = @"Delete this note?";
  alert.informativeText = @"The saved Markdown file will move to notes/.trash in the VM. Any unsaved draft will be discarded.";
  [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Delete"];
  if ([alert runModal] != NSAlertSecondButtonReturn) return;
  [self.saveTimer invalidate];
  [self perform:@{@"action":@"delete", @"id":self.note[@"id"], @"revision":self.note[@"revision"]}
    message:@"Deleting note…" completion:^(NSDictionary *result) {
      if (![result[@"deleted"] isEqual:self.note[@"id"]]) { [self setStatusText:@"Deletion could not be confirmed. Refresh to check the VM."]; return; }
      [self displayNote:nil]; self.surface.showsEditor = NO; [self refresh:nil];
    }];
}
- (void)searchChanged:(id)sender {
  __weak typeof(self) weakSelf = self;
  [self withSavedDraft:^{ [weakSelf refresh:nil]; }];
}
- (void)showList:(id)sender { self.surface.showsEditor = NO; }
- (void)revealSelectedNote:(id)sender {
  NSInteger row = self.table.selectedRow;
  if (row >= 0 && row < (NSInteger)self.notes.count && [self.notes[row][@"id"] isEqual:self.note[@"id"]])
    self.surface.showsEditor = YES;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.notes.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  NSDictionary *note = self.notes[row];
  NSTextField *label = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:@"%@\n%@", note[@"title"], note[@"preview"]]];
  label.maximumNumberOfLines = 2; label.lineBreakMode = NSLineBreakByTruncatingTail;
  NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:label.stringValue attributes:@{
    NSFontAttributeName:self.palette.smallFont, NSForegroundColorAttributeName:self.palette.textMuted}];
  [text addAttributes:@{NSFontAttributeName:self.palette.labelFont, NSForegroundColorAttributeName:self.palette.appText}
    range:NSMakeRange(0, [note[@"title"] length])];
  label.attributedStringValue = text; label.toolTip = note[@"title"];
  NSTableCellView *cell = [NSTableCellView new];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [cell addSubview:label]; cell.textField = label;
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:self.palette.space12],
    [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-self.palette.space12],
    [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
  ]];
  return cell;
}
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
  TLHistoryRowView *view = [TLHistoryRowView new]; view.palette = self.palette; return view;
}
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView { return !self.busy && !self.closed; }
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (self.selecting || self.busy || self.table.selectedRow < 0 || self.table.selectedRow >= (NSInteger)self.notes.count) return;
  NSString *identity = self.notes[self.table.selectedRow][@"id"];
  if ([identity isEqual:self.note[@"id"]]) { self.surface.showsEditor = YES; return; }
  __weak typeof(self) weakSelf = self;
  [self withSavedDraft:^{ [weakSelf openNoteID:identity]; }];
}
- (BOOL)prepareToClose {
  if (!self.dirty && !(self.busy && (self.saving || self.pendingCreate))) return YES;
  NSAlert *alert = [NSAlert new];
  alert.messageText = self.busy ? @"Notes are still saving" : @"This note has unsaved changes";
  alert.informativeText = self.busy ? @"Wait for the save to finish before closing." : @"Keep editing to save your draft, or discard your changes. The saved file in the VM will remain available.";
  [alert addButtonWithTitle:@"Keep Editing"];
  if (!self.busy) [alert addButtonWithTitle:@"Discard Changes"];
  if ([alert runModal] != NSAlertSecondButtonReturn) return NO;
  [self.saveTimer invalidate]; self.afterSave = nil;
  [self displayNote:self.note]; return YES;
}
- (void)close {
  [super close]; self.generation++; self.afterSave = nil;
  [self.saveTimer invalidate]; [self.refreshTimer invalidate]; self.request = nil;
}
- (void)dealloc { [_saveTimer invalidate]; [_refreshTimer invalidate]; }
@end
