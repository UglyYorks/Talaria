#import "TLGlobalShortcut.h"
#import <Carbon/Carbon.h>

@interface TLGlobalShortcut ()
@property EventHotKeyRef hotKey;
@property EventHandlerRef eventHandler;
@property UInt32 identifier;
@end

static OSStatus TLHandleQuickInputHotKey(EventHandlerCallRef next, EventRef event, void *context) {
  TLGlobalShortcut *owner = (__bridge TLGlobalShortcut *)context;
  EventHotKeyID key;
  if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(key), NULL, &key) != noErr ||
      key.signature != 'Tlqi' || key.id != owner.identifier) return eventNotHandledErr;
  if (owner.handler) owner.handler();
  return noErr;
}

@implementation TLGlobalShortcut
- (BOOL)registerShortcut:(NSDictionary *)shortcut error:(NSError **)error {
  if (!shortcut) {
    if (self.hotKey) UnregisterEventHotKey(self.hotKey);
    self.hotKey = NULL;
    return YES;
  }
  OSStatus result = noErr;
  if (!self.eventHandler) {
    EventTypeSpec type = { kEventClassKeyboard, kEventHotKeyPressed };
    EventHandlerRef handler = NULL;
    result = InstallApplicationEventHandler(&TLHandleQuickInputHotKey, 1, &type, (__bridge void *)self, &handler);
    if (result == noErr) self.eventHandler = handler;
  }
  NSEventModifierFlags flags = [shortcut[@"modifiers"] unsignedIntegerValue];
  UInt32 carbonFlags = 0;
  if (flags & NSEventModifierFlagCommand) carbonFlags |= cmdKey;
  if (flags & NSEventModifierFlagControl) carbonFlags |= controlKey;
  if (flags & NSEventModifierFlagOption) carbonFlags |= optionKey;
  if (flags & NSEventModifierFlagShift) carbonFlags |= shiftKey;
  static UInt32 nextIdentifier = 1;
  EventHotKeyID identifier = { 'Tlqi', nextIdentifier++ };
  EventHotKeyRef replacement = NULL;
  if (result == noErr) result = RegisterEventHotKey([shortcut[@"keyCode"] unsignedIntValue], carbonFlags,
    identifier, GetApplicationEventTarget(), 0, &replacement);
  if (result != noErr) {
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result
      userInfo:@{NSLocalizedDescriptionKey:@"This shortcut could not be registered. It may already be in use; choose another combination."}];
    return NO;
  }
  // Keep the previous shortcut working if macOS rejects the replacement.
  if (self.hotKey) UnregisterEventHotKey(self.hotKey);
  self.hotKey = replacement; self.identifier = identifier.id;
  return YES;
}
- (void)dealloc {
  if (_hotKey) UnregisterEventHotKey(_hotKey);
  if (_eventHandler) RemoveEventHandler(_eventHandler);
}
@end
