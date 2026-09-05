// Optional real-VM integration probe. Arguments: runtime directory, temporary
// agents directory, app executable. Prints its private socket path when ready;
// any byte on stdin stops the disposable VM cleanly.
#import <Foundation/Foundation.h>
#import "AgentVMService.h"
#import "TLVMTerminalSession.h"
#include <unistd.h>

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 4) return 2;
    TLAgentVMService *service = [[TLAgentVMService alloc]
      initWithAgentsDirectoryURL:[NSURL fileURLWithPath:@(argv[2])]
      runtimeBundleURL:[NSURL fileURLWithPath:@(argv[1])]];
    TLAgentRecord *agent = [[TLAgentRecord alloc] init];
    agent.agentID = 1;
    agent.name = @"Disposable terminal test";
    agent.vmDirectory = [service newVMDirectoryPathForAgentName:agent.name];
    __block BOOL finished = NO;
    __block int result = 0;
    __block TLVMTerminalSession *session = nil;
    void (^stop)(void) = ^{
      [session cancel];
      [service stopAgent:agent completion:^(NSError *error) {
        if (error) { NSLog(@"VM cleanup failed: %@", error); result = 1; }
        session = nil;
        finished = YES;
      }];
    };
    [service startAgent:agent completion:^(NSError *error) {
      if (error) { NSLog(@"VM start failed: %@", error); result = 1; finished = YES; return; }
      [service connectToAgent:agent port:7048 timeout:45 completion:^(VZVirtioSocketConnection *connection, NSError *connectError) {
        if (!connection) { NSLog(@"Terminal connect failed: %@", connectError); result = 1; stop(); return; }
        NSError *sessionError = nil;
        session = [[TLVMTerminalSession alloc] initWithConnection:connection executableURL:[NSURL fileURLWithPath:@(argv[3])] error:&sessionError];
        if (!session) { NSLog(@"Session failed: %@", sessionError); result = 1; stop(); return; }
        [session beginForwarding];
        puts(session.socketURL.path.fileSystemRepresentation);
        fflush(stdout);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
          char byte;
          read(STDIN_FILENO, &byte, 1);
          dispatch_async(dispatch_get_main_queue(), stop);
        });
      }];
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!finished) { NSLog(@"VM probe timed out"); return 1; }
    return result;
  }
}
