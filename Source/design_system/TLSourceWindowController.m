#import "TLSourceWindowController.h"

@interface TLSourceWindowController () <NSWindowDelegate>
@property(nonatomic, strong) NSScrollView *scroll;
@property(nonatomic, strong) NSTextView *editor;
@end
static NSMutableSet<TLSourceWindowController *> *TLOpenSourceWindows(void) {
  static NSMutableSet *windows; static dispatch_once_t once;
  dispatch_once(&once,^{ windows = [NSMutableSet set]; }); return windows;
}
@implementation TLSourceWindowController
+ (void)showText:(NSString *)text title:(NSString *)title palette:(TLThemePalette *)palette {
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,palette.windowInitialWidth,palette.windowInitialHeight)
    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO; window.title = title; window.minSize = NSMakeSize(palette.windowMinimumWidth,palette.windowMinimumHeight);
  TLSourceWindowController *controller = [[self alloc] initWithWindow:window]; window.delegate = controller;
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds]; controller.scroll = scroll;
  scroll.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable; scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES;
  NSTextView *editor = [[NSTextView alloc] initWithFrame:scroll.bounds]; controller.editor = editor;
  editor.editable = NO; editor.selectable = YES; editor.richText = NO; editor.usesFindBar = YES;
  editor.verticallyResizable = YES; editor.horizontallyResizable = YES; editor.maxSize = NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
  editor.textContainer.widthTracksTextView = NO; editor.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
  editor.string = text; scroll.documentView = editor; [window.contentView addSubview:scroll];
  [controller applyPalette:palette]; [TLOpenSourceWindows() addObject:controller]; [window center]; [controller showWindow:nil];
}
- (void)applyPalette:(TLThemePalette *)palette {
  self.window.appearance = [NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  self.window.backgroundColor = palette.markdownCodeSurface;
  self.scroll.backgroundColor = palette.markdownCodeSurface;
  self.editor.backgroundColor = palette.markdownCodeSurface; self.editor.textColor = palette.markdownCodeText;
  self.editor.font = palette.markdownCodeFont; self.editor.insertionPointColor = palette.markdownCodeText;
  self.editor.textContainerInset = NSMakeSize(palette.space5,palette.space5);
  self.editor.selectedTextAttributes = @{NSBackgroundColorAttributeName:palette.findActiveMatchSurface,NSForegroundColorAttributeName:palette.findMatchText};
}
+ (void)applyPaletteToOpenWindows:(TLThemePalette *)palette {
  for (TLSourceWindowController *controller in TLOpenSourceWindows()) [controller applyPalette:palette];
}
- (void)windowWillClose:(NSNotification *)notification { [TLOpenSourceWindows() removeObject:self]; }
@end
