#import "TLFeatureTabController.h"

@interface TLFeatureTabController ()
@property (nonatomic, strong, readwrite) TLThemePalette *palette;
@property (nonatomic, readwrite, getter=isClosed) BOOL closed;
@property (nonatomic, strong) NSMapTable<id, NSMutableDictionary<NSString *, NSString *> *> *colorBindings;
@end

@implementation TLFeatureTabController
- (instancetype)initWithPalette:(TLThemePalette *)palette {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _palette = palette;
    _colorBindings = [NSMapTable weakToStrongObjectsMapTable];
  }
  return self;
}

- (void)bindColorForObject:(id)object keyPath:(NSString *)keyPath token:(NSString *)token {
  NSMutableDictionary *bindings = [self.colorBindings objectForKey:object];
  if (!bindings) {
    bindings = [NSMutableDictionary dictionary];
    [self.colorBindings setObject:bindings forKey:object];
  }
  bindings[keyPath] = token;
  [object setValue:[self.palette valueForKey:token] forKeyPath:keyPath];
}

- (void)applyPalette:(TLThemePalette *)palette {
  self.palette = palette;
  for (id object in self.colorBindings) {
    NSDictionary *bindings = [self.colorBindings objectForKey:object];
    for (NSString *keyPath in bindings) {
      [object setValue:[palette valueForKey:bindings[keyPath]] forKeyPath:keyPath];
    }
    if ([object isKindOfClass:NSView.class]) [object setNeedsDisplay:YES];
  }
}

- (void)close { self.closed = YES; }

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font colorToken:(NSString *)token {
  NSTextField *label = [NSTextField labelWithString:string];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = font;
  [self bindColorForObject:label keyPath:@"textColor" token:token];
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (NSTextField *)wrappingLabelWithString:(NSString *)string font:(NSFont *)font colorToken:(NSString *)token {
  NSTextField *label = [self labelWithString:string font:font colorToken:token];
  label.lineBreakMode = NSLineBreakByWordWrapping;
  label.maximumNumberOfLines = 0;
  label.usesSingleLineMode = NO;
  return label;
}
@end
