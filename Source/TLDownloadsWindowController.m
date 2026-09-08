#import "TLDownloadsWindowController.h"
#import "ChromiumBrowserController.h"
#import "design_system/TLDownloadRowView.h"
#import "design_system/TLThemedButton.h"

@interface TLDownloadsWindowController () <NSWindowDelegate>
@property TLBrowserDownloadManager *manager;
@property TLThemePalette *palette;
@property NSTextField *titleLabel, *summaryLabel, *emptyLabel;
@property TLThemedButton *clearButton;
@property NSScrollView *scrollView;
@property NSStackView *rows;
@property NSMutableDictionary<NSString *, TLDownloadRowView *> *rowViews;
@property BOOL refreshScheduled;
@end
@implementation TLDownloadsWindowController
- (instancetype)initWithManager:(TLBrowserDownloadManager *)manager palette:(TLThemePalette *)p {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, p.settingsSheetWidth, p.settingsSheetHeight)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  if ((self = [super initWithWindow:window])) {
    _manager = manager; _rowViews = [NSMutableDictionary dictionary];
    window.title = @"Downloads"; window.releasedWhenClosed = NO; window.delegate = self;
    window.contentMinSize = NSMakeSize(p.settingsSheetWidth * 0.65, p.settingsSheetHeight * 0.5);
    [window setFrameAutosaveName:@"TalariaDownloadsWindow"]; [window center];
    TLTokenView *root = [[TLTokenView alloc] init]; window.contentView = root;
    _titleLabel = [NSTextField labelWithString:@"Downloads"];
    _summaryLabel = [NSTextField labelWithString:@""];
    _summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _clearButton = [TLThemedButton buttonWithTitle:@"Clear finished" target:self action:@selector(clearFinished:)];
    _clearButton.toolTip = @"Clear completed, cancelled, and failed downloads from this list. Files stay on disk.";
    _emptyLabel = [NSTextField wrappingLabelWithString:@"No downloads yet\nFiles you download in the browser will appear here."];
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _scrollView = [[NSScrollView alloc] init]; _scrollView.hasVerticalScroller = YES; _scrollView.drawsBackground = NO;
    TLFlippedView *document = [[TLFlippedView alloc] init]; document.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.documentView = document;
    _rows = [NSStackView stackViewWithViews:@[]]; _rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    _rows.alignment = NSLayoutAttributeLeading; _rows.spacing = p.space8; _rows.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:_rows];
    for (NSView *view in @[_titleLabel, _summaryLabel, _clearButton, _scrollView, _emptyLabel]) { view.translatesAutoresizingMaskIntoConstraints = NO; [root addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
      [_titleLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:p.space12],
      [_titleLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:p.space12],
      [_clearButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-p.space12],
      [_clearButton.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
      [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_clearButton.leadingAnchor constant:-p.space8],
      [_summaryLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:p.space5],
      [_summaryLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
      [_summaryLabel.trailingAnchor constraintEqualToAnchor:_clearButton.trailingAnchor],
      [_scrollView.topAnchor constraintEqualToAnchor:_summaryLabel.bottomAnchor constant:p.space10],
      [_scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:p.space12],
      [_scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-p.space12],
      [_scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-p.space10],
      [document.widthAnchor constraintEqualToAnchor:_scrollView.contentView.widthAnchor],
      [_rows.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
      [_rows.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
      [_rows.topAnchor constraintEqualToAnchor:document.topAnchor],
      [_rows.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
      [_emptyLabel.centerYAnchor constraintEqualToAnchor:_scrollView.centerYAnchor],
      [_emptyLabel.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:p.space10],
      [_emptyLabel.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-p.space10],
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(downloadsChanged:) name:TLBrowserDownloadsDidChangeNotification object:manager];
    [self applyPalette:p];
  }
  return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)showWindow:(id)sender { [self refresh]; [super showWindow:sender]; [self.window makeKeyAndOrderFront:sender]; }
- (void)windowDidBecomeKey:(NSNotification *)notification { [self refresh]; }
- (void)downloadsChanged:(NSNotification *)notification {
  if (self.refreshScheduled) return;
  self.refreshScheduled = YES;
  __weak typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{ typeof(self) self = weakSelf; self.refreshScheduled = NO; if (self.window.visible) [self refresh]; });
}
- (void)refresh {
  NSArray<TLBrowserDownload *> *downloads = self.manager.downloads;
  NSSet *identifiers = [NSSet setWithArray:[downloads valueForKey:@"identifier"]];
  for (NSString *key in self.rowViews.allKeys) if (![identifiers containsObject:key]) {
    TLDownloadRowView *row = self.rowViews[key]; [self.rows removeArrangedSubview:row]; [row removeFromSuperview]; [self.rowViews removeObjectForKey:key];
  }
  NSUInteger active = 0, index = 0;
  for (TLBrowserDownload *download in downloads) {
    active += download.active;
    TLDownloadRowView *row = self.rowViews[download.identifier];
    if (!row) {
      row = [[TLDownloadRowView alloc] init]; self.rowViews[download.identifier] = row;
      [self.rows insertArrangedSubview:row atIndex:index];
      [row.widthAnchor constraintEqualToAnchor:self.rows.widthAnchor].active = YES;
      __weak typeof(self) weakSelf = self;
      row.actionHandler = ^(NSString *action) { [weakSelf performAction:action download:download]; };
    }
    [row configureWithDownload:download palette:self.palette]; index++;
  }
  self.emptyLabel.hidden = downloads.count > 0;
  self.clearButton.enabled = downloads.count > active;
  self.summaryLabel.stringValue = self.manager.persistenceError ? @"Download history could not be saved. Your downloads can continue." :
    active ? [NSString stringWithFormat:@"%lu active · %lu total", (unsigned long)active, (unsigned long)downloads.count] :
    [NSString stringWithFormat:@"%lu download%@", (unsigned long)downloads.count, downloads.count == 1 ? @"" : @"s"];
  self.summaryLabel.toolTip = self.manager.persistenceError.localizedDescription;
}
- (void)performAction:(NSString *)action download:(TLBrowserDownload *)download {
  if ([action isEqual:@"Pause"]) [self.manager performAction:TLBrowserDownloadActionPause forDownload:download];
  else if ([action isEqual:@"Resume"]) [self.manager performAction:TLBrowserDownloadActionResume forDownload:download];
  else if ([action isEqual:@"Cancel"]) [self.manager performAction:TLBrowserDownloadActionCancel forDownload:download];
  else if ([action isEqual:@"Remove"]) [self.manager removeDownload:download];
  else if ([action isEqual:@"Retry"] && download.canRetry)
    [TLChromiumBrowserController.sharedController startDownloadURL:[NSURL URLWithString:download.URLString] fromWindow:self.window];
  else if ([@[@"Open", @"Show in Finder"] containsObject:action] && download.fileAvailable) {
    NSURL *URL = [NSURL fileURLWithPath:download.path];
    if ([action isEqual:@"Show in Finder"]) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[URL]];
    else if (![NSWorkspace.sharedWorkspace openURL:URL]) [self.window presentError:[NSError errorWithDomain:@"Talaria.Downloads" code:1
      userInfo:@{NSLocalizedDescriptionKey:@"The downloaded file could not be opened."}]];
  }
  [self refresh];
}
- (void)clearFinished:(id)sender { [self.manager clearFinishedDownloads]; [self refresh]; }
- (void)applyPalette:(TLThemePalette *)p {
  self.palette = p;
  self.window.appearance = [NSAppearance appearanceNamed:p.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = p.tabBackground;
  ((TLTokenView *)self.window.contentView).fillColor = p.tabBackground;
  self.titleLabel.font = p.titleFont; self.titleLabel.textColor = p.appText;
  self.summaryLabel.font = p.smallFont; self.summaryLabel.textColor = p.textMuted;
  self.emptyLabel.font = p.bodyFont; self.emptyLabel.textColor = p.textMuted;
  self.clearButton.palette = p;
  [self refresh];
}
@end
