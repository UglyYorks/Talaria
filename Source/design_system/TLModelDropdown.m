#import "TLModelDropdown.h"

@implementation TLModelDropdown
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _models = @[];
    _selectedModelID = @"";
    self.image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:nil];
    self.imagePosition = NSImageRight;
    self.alignment = NSTextAlignmentLeft;
    self.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.target = self;
    self.action = @selector(showModels:);
    [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  }
  return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, self.palette.fieldHeight); }
- (TLAgentModel *)selectedModel {
  for (TLAgentModel *model in self.models) {
    if ([model.modelID isEqual:self.selectedModelID]) return model;
    // Older chats store bare OpenRouter model IDs.
    if (![self.selectedModelID containsString:@"::"] && [model.providerID isEqual:@"openrouter"] &&
        [model.name isEqual:self.selectedModelID]) return model;
  }
  return nil;
}
- (void)setModels:(NSArray<TLAgentModel *> *)models { _models = [models copy]; [self updateTitle]; }
- (void)setSelectedModelID:(NSString *)selectedModelID { _selectedModelID = [selectedModelID copy]; [self updateTitle]; }
- (void)updateTitle {
  TLAgentModel *model = self.selectedModel;
  self.title = model ? model.displayTitle : (self.selectedModelID.length ? self.selectedModelID : @"Choose model");
  self.toolTip = model ? [NSString stringWithFormat:@"%@ · %@", model.modelDescription, model.displayTitle] : self.title;
  self.accessibilityValue = self.title;
}
- (void)showModels:(id)sender {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:self.accessibilityLabel ?: @"Models"];
  NSString *provider = nil;
  TLAgentModel *selected = self.selectedModel;
  for (TLAgentModel *model in self.models) {
    if (![provider isEqual:model.providerID]) {
      if (menu.numberOfItems) [menu addItem:NSMenuItem.separatorItem];
      NSMenuItem *heading = [[NSMenuItem alloc] initWithTitle:model.modelDescription.length ? model.modelDescription : model.providerID action:nil keyEquivalent:@""];
      heading.enabled = NO;
      [menu addItem:heading];
      provider = model.providerID;
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:model.displayTitle action:@selector(selectModel:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = model;
    item.state = model == selected ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
  }
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(self.bounds)) inView:self];
}
- (void)selectModel:(NSMenuItem *)sender {
  self.selectedModelID = ((TLAgentModel *)sender.representedObject).modelID;
  if (self.selectionHandler) self.selectionHandler();
}
@end
