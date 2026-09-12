#import "TLHostCommandBridge.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSDictionary *Request(NSString *command, NSInteger timeout) {
  return @{@"command":command, @"cwd":@"/private/tmp", @"timeout_seconds":@(timeout)};
}
static void WaitFor(BOOL (^condition)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!condition() && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  Check(condition(), @"asynchronous operation completes");
}
int main(void) { @autoreleasepool {
  [NSApplication sharedApplication];
  [NSApp finishLaunching];
  NSString *suite = [@"TalariaHostCommandTests." stringByAppendingString:NSUUID.UUID.UUIDString];
  NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
  TLHostCommandBridge *bridge = [[TLHostCommandBridge alloc] initWithDefaults:defaults];
  Check(![bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@""], @"default requires consent");
  [bridge allowChat:@"one" agent:@"a" privateScope:@""];
  Check([bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@""], @"chat permission applies");
  Check(![bridge isAllowedForAgent:@"a" chat:@"two" privateScope:@""], @"chat permission does not cross chats");
  Check(![bridge isAllowedForAgent:@"b" chat:@"one" privateScope:@""], @"chat permission does not cross agents");
  TLHostCommandBridge *restored = [[TLHostCommandBridge alloc] initWithDefaults:defaults];
  Check([restored isAllowedForAgent:@"a" chat:@"one" privateScope:@""], @"normal chat grant survives relaunch");
  [bridge allowChat:@"one" agent:@"a" privateScope:@"private"];
  Check(![restored isAllowedForAgent:@"a" chat:@"one" privateScope:@"private"], @"private grant is not persisted");
  [bridge clearPrivateScope:@"private"];
  Check(![bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@"private"], @"private close clears permission");
  [bridge setPolicy:@"always" forAgent:@"a"];
  Check([restored isAllowedForAgent:@"a" chat:@"two" privateScope:@""], @"always permission is persistent");
  [bridge setPolicy:@"ask" forAgent:@"a"];
  Check(![bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@""], @"revoke also clears old chat grants");
  [bridge setPolicy:@"deny" forAgent:@"a"];
  [bridge allowChat:@"one" agent:@"a" privateScope:@""];
  Check(![bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@""], @"deny overrides chat grants");

  NSDictionary *result = TLExecuteHostCommand(Request(@"printf hello; printf problem >&2; exit 7", 3), [TLHostCommandOperation new]);
  Check([result[@"stdout"] isEqual:@"hello"] && [result[@"stderr"] isEqual:@"problem"] && [result[@"exit_code"] intValue] == 7, @"real host command captures both streams and exit status");
  result = TLExecuteHostCommand(Request(@"pwd", 3), [TLHostCommandOperation new]);
  Check([result[@"stdout"] isEqual:@"/private/tmp\n"], @"host cwd is respected");
  result = TLExecuteHostCommand(Request(@"while :; do printf 0123456789012345678901234567890123456789; done", 1), [TLHostCommandOperation new]);
  Check([result[@"timed_out"] boolValue] && [result[@"truncated"] boolValue] && [result[@"stdout"] length] == 65536, @"unbounded writer is drained, bounded and timed out");
  TLHostCommandOperation *cancel = [TLHostCommandOperation new];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_global_queue(0, 0), ^{ [cancel cancel]; });
  double began = NSProcessInfo.processInfo.systemUptime;
  result = TLExecuteHostCommand(Request(@"sleep 20 & wait", 30), cancel);
  Check([result[@"cancelled"] boolValue] && NSProcessInfo.processInfo.systemUptime - began < 3, @"cancellation stops child processes promptly");
  for (id timeout in @[@0, @121, @YES, @1.5, @"2"])
    Check(!TLValidateHostCommand(@{@"command":@"x", @"cwd":@"", @"timeout_seconds":timeout}), @"invalid timeouts fail closed");

  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  [window orderFront:nil];
  for (NSNumber *choice in @[@(NSAlertFirstButtonReturn), @(NSAlertSecondButtonReturn), @(NSAlertThirdButtonReturn), @(NSAlertThirdButtonReturn + 1)]) {
    [bridge setPolicy:@"ask" forAgent:@"a"];
    __block NSDictionary *completed = nil;
    TLHostCommandOperation *op = [bridge runRequest:Request(@"printf consent", 3) agent:@"a" name:@"Test Agent"
      chat:@"one" privateScope:@"" window:window completion:^(NSDictionary *output) { completed = output; }];
    WaitFor(^BOOL{ return window.attachedSheet != nil || completed != nil; });
    Check(window.attachedSheet != nil, [NSString stringWithFormat:@"native consent appears: %@", completed]);
    Check(completed == nil, @"no command runs while waiting for native consent");
    NSView *consent = window.attachedSheet.contentView;
    [consent layoutSubtreeIfNeeded];
    NSBitmapImageRep *image = [consent bitmapImageRepForCachingDisplayInRect:consent.bounds];
    [consent cacheDisplayInRect:consent.bounds toBitmapImageRep:image];
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:[NSString stringWithFormat:@"build/host-consent-%@.png", choice] atomically:YES];
    [window endSheet:window.attachedSheet returnCode:choice.integerValue];
    WaitFor(^BOOL{ return completed != nil; });
    if (choice.integerValue <= NSAlertThirdButtonReturn) Check([completed[@"stdout"] isEqual:@"consent"], @"approved command executes");
    else Check([completed[@"denied"] boolValue] && !completed[@"stdout"], @"denied command does not execute");
    Check([bridge isAllowedForAgent:@"a" chat:@"one" privateScope:@""] == (choice.integerValue == NSAlertSecondButtonReturn || choice.integerValue == NSAlertThirdButtonReturn), @"once and deny do not grant ongoing permission");
    Check([bridge isAllowedForAgent:@"a" chat:@"two" privateScope:@""] == (choice.integerValue == NSAlertThirdButtonReturn), @"only always applies to another chat");
    [op cancel];
  }
  [window close];
  [defaults removePersistentDomainForName:suite];
  NSLog(@"HostCommandTests passed");
} return 0; }
