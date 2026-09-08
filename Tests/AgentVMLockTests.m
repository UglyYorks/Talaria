#import <Foundation/Foundation.h>
#import "TLAgentVMLock.h"
#import "AgentVMService.h"
#include <unistd.h>

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static int Probe(NSString *executable, NSURL *directory) {
  NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:executable];
  task.arguments = @[@"--probe", directory.path];
  NSError *error = nil;
  Check([task launchAndReturnError:&error], @"launch lock contender");
  [task waitUntilExit]; return task.terminationStatus;
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc == 3) {
      __attribute__((objc_precise_lifetime)) TLAgentVMLock *lock = [[TLAgentVMLock alloc] initWithDirectoryURL:[NSURL fileURLWithPath:@(argv[2])] error:nil];
      if (!lock) return 2;
      if (strcmp(argv[1], "--hold") == 0) { puts("ready"); fflush(stdout); char byte; read(STDIN_FILENO,&byte,1); }
      return 0;
    }
    NSString *executable = [@(argv[0]) stringByStandardizingPath];
    if (![executable hasPrefix:@"/"]) executable = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:executable];
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    Check([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil], @"create test storage");
    @autoreleasepool {
      __attribute__((objc_precise_lifetime)) TLAgentVMLock *owner = [[TLAgentVMLock alloc] initWithDirectoryURL:directory error:nil];
      Check(owner != nil, @"first VM acquires its storage");
      NSError *error = nil;
      TLAgentVMLock *duplicate = [[TLAgentVMLock alloc] initWithDirectoryURL:directory error:&error];
      Check(!duplicate && error.code == 2 && [error.localizedDescription containsString:@"another Talaria instance"], @"second service cannot open the same filesystem");
      Check(Probe(executable,directory) == 2, @"another process cannot acquire an active VM's storage");
      NSURL *other = [directory URLByAppendingPathComponent:@"other-agent"];
      [NSFileManager.defaultManager createDirectoryAtURL:other withIntermediateDirectories:YES attributes:nil error:nil];
      Check(Probe(executable,other) == 0, @"independent agents are not blocked");
      TLAgentVMService *otherService = [[TLAgentVMService alloc] initWithAgentsDirectoryURL:directory runtimeBundleURL:directory];
      TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 1; agent.vmDirectory = directory.path;
      Check(![otherService deleteVMForAgent:agent error:&error] && error.code == 2, @"an active agent's storage cannot be deleted by another service");
    }
    Check(Probe(executable,directory) == 0, @"normal teardown releases the lock");
    NSTask *holder = [NSTask new]; holder.executableURL = [NSURL fileURLWithPath:executable]; holder.arguments = @[@"--hold",directory.path];
    NSPipe *ready = [NSPipe pipe]; NSPipe *input = [NSPipe pipe]; holder.standardOutput = ready; holder.standardInput = input;
    Check([holder launchAndReturnError:nil], @"launch crash fixture");
    Check([ready.fileHandleForReading availableData].length > 0, @"child owns lock before termination");
    Check(Probe(executable,directory) == 2, @"child lock blocks a second host process");
    [holder terminate]; [holder waitUntilExit];
    Check(Probe(executable,directory) == 0, @"process exit releases ownership without deleting the lock file");
    @autoreleasepool {
      TLAgentVMService *service = [[TLAgentVMService alloc] initWithAgentsDirectoryURL:directory runtimeBundleURL:[directory URLByAppendingPathComponent:@"missing-runtime"]];
      TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 1; agent.vmDirectory = directory.path;
      __block BOOL done = NO; __block NSError *failure = nil;
      [service startAgent:agent completion:^(NSError *error) { failure=error; done=YES; }];
      NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
      while (!done && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
      Check(done && failure, @"invalid runtime fails to start");
    }
    Check(Probe(executable,directory) == 0, @"startup failure does not strand ownership");
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    puts("AgentVMLockTests passed");
  }
  return 0;
}
