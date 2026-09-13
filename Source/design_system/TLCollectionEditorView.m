#import "TLCollectionEditorView.h"

@implementation TLCollectionEditorView
- (instancetype)init {
  if ((self = [super init])) {
    _header = [NSView new]; _collection = [TLTokenView new];
    _editor = [NSView new]; _footer = [TLTokenView new];
    for (NSView *view in @[_header, _collection, _editor, _footer]) [self addSubview:view];
  }
  return self;
}
- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.fillColor = palette.tabBackground;
  self.collection.fillColor = palette.sidebarSurface;
  self.collection.borderColor = palette.controlBorder;
  self.collection.borderWidth = palette.borderWidth;
  self.collection.borderEdges = TLBorderEdgeRight;
  self.footer.fillColor = palette.tabBackground;
  self.footer.borderColor = palette.controlBorder;
  self.footer.borderWidth = palette.borderWidth;
  self.footer.borderEdges = TLBorderEdgeTop;
  self.needsLayout = YES;
}
- (BOOL)compact { return NSWidth(self.bounds) < self.palette.settingsCompactWidth; }
- (void)setShowsEditor:(BOOL)showsEditor { _showsEditor = showsEditor; self.needsLayout = YES; }
- (void)layout {
  [super layout];
  TLThemePalette *p = self.palette;
  CGFloat width = NSWidth(self.bounds), height = NSHeight(self.bounds);
  CGFloat headerHeight = p.settingsActionHeight * 2 + p.space12 * 3;
  CGFloat footerHeight = self.compact ? p.settingsActionHeight * 2 + p.space12 * 3 : p.settingsActionHeight + p.space12 * 2;
  CGFloat bodyHeight = MAX(0, height - headerHeight - footerHeight);
  CGFloat side = self.compact ? width : MIN(p.settingsSidebarWidth + p.space16 * 2, width / 3);
  self.header.frame = NSMakeRect(0, height - headerHeight, width, headerHeight);
  self.collection.frame = NSMakeRect(0, footerHeight, side, bodyHeight);
  self.collection.hidden = self.compact && self.showsEditor;
  self.editor.frame = NSMakeRect(self.compact ? 0 : side, footerHeight,
                                self.compact ? width : width - side, bodyHeight);
  self.editor.hidden = self.compact && !self.showsEditor;
  self.footer.frame = NSMakeRect(0, 0, width, footerHeight);
}
@end
