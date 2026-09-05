#import "TLTabShortcuts.h"

// One table defines both menu equivalents and application-level routing, so
// Chromium focus cannot change what a workspace shortcut does.
static NSArray<NSDictionary *> *TLTabBindings(void) {
  static NSArray<NSDictionary *> *bindings;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    NSEventModifierFlags shift = NSEventModifierFlagShift;
    NSEventModifierFlags ctrl = NSEventModifierFlagControl;
    NSEventModifierFlags opt = NSEventModifierFlagOption;
    NSMutableArray *items = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSEventModifierFlags, TLTabCommand, BOOL) =
      ^(NSString *title, NSString *key, NSEventModifierFlags flags, TLTabCommand command, BOOL hidden) {
        [items addObject:@{@"title": title, @"key": key, @"flags": @(flags), @"command": @(command), @"hidden": @(hidden)}];
      };
    add(@"New Tab", @"t", cmd, TLTabCommandNew, NO);
    add(@"Close Tab", @"w", cmd, TLTabCommandClose, NO);
    add(@"Reopen Closed Tab", @"t", cmd | shift, TLTabCommandReopen, NO);
    add(@"Close Window", @"w", cmd | shift, TLTabCommandCloseWindow, NO);
    add(@"Next Tab", @"\t", ctrl, TLTabCommandNext, NO);
    add(@"Previous Tab", @"\t", ctrl | shift, TLTabCommandPrevious, NO);
    add(@"Next Tab", @"]", cmd | shift, TLTabCommandNext, YES);
    add(@"Previous Tab", @"[", cmd | shift, TLTabCommandPrevious, YES);
    add(@"Next Tab", [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], cmd | opt, TLTabCommandNext, YES);
    add(@"Previous Tab", [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey], cmd | opt, TLTabCommandPrevious, YES);
    for (NSInteger number = 1; number <= 9; number++) {
      add(number == 9 ? @"Select Last Tab" : [NSString stringWithFormat:@"Select Tab %ld", (long)number],
          [NSString stringWithFormat:@"%ld", (long)number], cmd, (TLTabCommand)(100 + number), NO);
    }
    add(@"Move Tab Left", [NSString stringWithFormat:@"%C", (unichar)NSPageUpFunctionKey], ctrl | shift, TLTabCommandMoveLeft, NO);
    add(@"Move Tab Right", [NSString stringWithFormat:@"%C", (unichar)NSPageDownFunctionKey], ctrl | shift, TLTabCommandMoveRight, NO);
    bindings = [items copy];
  });
  return bindings;
}

TLTabCommand TLTabCommandForEvent(NSEvent *event) {
  if (event.type != NSEventTypeKeyDown) return TLTabCommandNone;
  NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand |
    NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
  // Function and numeric-pad flags accompany arrows/Page Up/Page Down on macOS.
  NSString *key = event.charactersIgnoringModifiers.lowercaseString;
  if ([key isEqualToString:@"{"]) key = @"[";
  if ([key isEqualToString:@"}"]) key = @"]";
  if ([key isEqualToString:@"\x19"]) key = @"\t"; // Shift-Tab / backtab
  for (NSDictionary *binding in TLTabBindings()) {
    if (flags == [binding[@"flags"] unsignedIntegerValue] && [key isEqualToString:binding[@"key"]]) {
      return [binding[@"command"] integerValue];
    }
  }
  return TLTabCommandNone;
}

BOOL TLTabCommandAllowsRepeat(TLTabCommand command) {
  return command == TLTabCommandNext || command == TLTabCommandPrevious ||
    command == TLTabCommandMoveLeft || command == TLTabCommandMoveRight ||
    (command >= TLTabCommandSelectFirst && command <= TLTabCommandSelectLast);
}

NSMenu *TLCreateTabMenu(id target, SEL action) {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
  for (NSDictionary *binding in TLTabBindings()) {
    NSMenuItem *item = [menu addItemWithTitle:binding[@"title"] action:action keyEquivalent:binding[@"key"]];
    item.target = target;
    item.tag = [binding[@"command"] integerValue];
    item.keyEquivalentModifierMask = [binding[@"flags"] unsignedIntegerValue];
    item.hidden = [binding[@"hidden"] boolValue];
    item.allowsKeyEquivalentWhenHidden = YES;
  }
  return menu;
}
