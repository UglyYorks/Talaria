#import "TLActionMenuItem.h"
@interface TLActionMenuItem ()
@property (copy) dispatch_block_t handler;
@end
@implementation TLActionMenuItem
+ (instancetype)itemWithTitle:(NSString *)title action:(dispatch_block_t)action {
  TLActionMenuItem *item = [[self alloc] initWithTitle:title action:@selector(invoke:) keyEquivalent:@""];
  item.handler = action; item.target = item; return item;
}
- (void)invoke:(id)sender { if (self.handler) self.handler(); }
@end
