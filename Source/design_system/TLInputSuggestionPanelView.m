#import "TLInputSuggestionPanelView.h"

@interface TLInputSuggestionPanelView ()
@property (nonatomic, strong) NSView *tintView;
@end

@implementation TLInputSuggestionPanelView
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.material = NSVisualEffectMaterialPopover;
    self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.state = NSVisualEffectStateActive;
    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    _tintView = [[NSView alloc] initWithFrame:self.bounds];
    _tintView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _tintView.wantsLayer = YES;
    [self addSubview:_tintView];
    self.palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem];
  }
  return self;
}

- (void)setPalette:(TLThemePalette *)palette {
  _palette = palette;
  self.layer.cornerRadius = palette.slashCommandListCornerRadius;
  self.tintView.layer.backgroundColor = palette.suggestionBackdropTint.CGColor;
}
@end
