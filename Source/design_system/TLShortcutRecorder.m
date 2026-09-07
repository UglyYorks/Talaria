#import "TLShortcutRecorder.h"
@interface TLShortcutRecorder ()
@property (nonatomic, readwrite) BOOL recording;
@end
@implementation TLShortcutRecorder
- (instancetype)init {
  if (!(self = [super init])) return nil;
  self.target = self; self.action = @selector(beginRecording:);
  self.accessibilityLabel = @"Quick input keyboard shortcut";
  self.toolTip = @"Click to record. Escape cancels; Delete clears the shortcut.";
  [self updateTitle];
  return self;
}
- (void)setShortcut:(NSDictionary *)shortcut { _shortcut = [shortcut copy]; [self updateTitle]; }
- (void)updateTitle {
  if (self.recording) { self.title = @"Press shortcut…"; return; }
  if (!self.shortcut) { self.title = @"Record shortcut…"; return; }
  NSUInteger flags = [self.shortcut[@"modifiers"] unsignedIntegerValue];
  self.title = [NSString stringWithFormat:@"%@%@%@%@%@", flags & NSEventModifierFlagControl ? @"⌃" : @"",
    flags & NSEventModifierFlagOption ? @"⌥" : @"", flags & NSEventModifierFlagShift ? @"⇧" : @"",
    flags & NSEventModifierFlagCommand ? @"⌘" : @"", self.shortcut[@"label"]];
}
- (void)setRecording:(BOOL)recording {
  if (_recording == recording) return;
  _recording = recording;
  if (self.recordingHandler) self.recordingHandler(recording);
}
- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
  [self cancelRecording];
  [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:self.window];
  [super viewWillMoveToWindow:newWindow];
  if (newWindow) [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:newWindow];
}
- (void)windowDidResignKey:(NSNotification *)notification { [self cancelRecording]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)beginRecording:(id)sender {
  [self.window makeFirstResponder:self];
  self.recording = YES; [self updateTitle];
}
- (void)cancelRecording { self.recording = NO; [self updateTitle]; }
- (BOOL)resignFirstResponder { [self cancelRecording]; return [super resignFirstResponder]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
  if (!self.recording) return [super performKeyEquivalent:event];
  [self keyDown:event]; return YES;
}
- (void)keyDown:(NSEvent *)event {
  if (!self.recording) { [super keyDown:event]; return; }
  if (event.isARepeat) return;
  if (event.keyCode == 53) { [self cancelRecording]; return; }
  if (event.keyCode == 51 || event.keyCode == 117) {
    [self cancelRecording]; if (self.changeHandler) self.changeHandler(nil); return;
  }
  NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand |
    NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift);
  if (!(flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) {
    self.title = @"Include ⌘, ⌃ or ⌥"; return;
  }
  NSString *label = event.charactersIgnoringModifiers.uppercaseString;
  NSDictionary *special = @{@36:@"↩",@48:@"⇥",@49:@"Space",@76:@"⌅",@123:@"←",@124:@"→",@125:@"↓",@126:@"↑",@115:@"↖",@119:@"↘",@116:@"⇞",@121:@"⇟"};
  if (special[@(event.keyCode)]) label = special[@(event.keyCode)];
  if (label.length == 1 && [label characterAtIndex:0] >= NSF1FunctionKey && [label characterAtIndex:0] <= NSF35FunctionKey)
    label = [NSString stringWithFormat:@"F%u", [label characterAtIndex:0] - NSF1FunctionKey + 1];
  if (!label.length) return;
  [self cancelRecording];
  if (self.changeHandler) self.changeHandler(@{@"keyCode":@(event.keyCode),@"modifiers":@(flags),@"label":label});
}
@end
