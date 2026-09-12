#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import "AgentVMService.h"
#import "TLFolderMounts.h"
#import <sys/socket.h>
#import <poll.h>

@interface TLAgentVMService (FolderTests)
- (VZVirtioFileSystemDeviceConfiguration *)folderSharingDeviceForAgent:(TLAgentRecord *)agent error:(NSError **)error;
@end
static void Check(BOOL ok, NSString *message) {
  if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Wait(BOOL (^ready)(void)) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
  while (!ready() && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  Check(ready(), @"VM operation completes before timeout");
}
static void Start(TLAgentVMService *service, TLAgentRecord *agent) {
  __block BOOL done = NO; __block NSError *failure;
  [service startAgent:agent completion:^(NSError *error) { failure = error; done = YES; }];
  Wait(^BOOL{ return done; });
  Check(!failure, [NSString stringWithFormat:@"start disposable VM: %@", failure]);
}
static void Stop(TLAgentVMService *service, TLAgentRecord *agent) {
  __block BOOL done = NO;
  [service stopAgent:agent completion:^(NSError *error) { Check(!error, @"stop disposable VM"); done = YES; }];
  Wait(^BOOL{ return done; });
}
static NSString *Shell(TLAgentVMService *service, TLAgentRecord *agent, NSString *command) {
  __block BOOL done = NO; __block NSString *output;
  [service connectToAgent:agent port:7047 timeout:45 completion:^(VZVirtioSocketConnection *connection, NSError *error) {
    Check(connection != nil, [NSString stringWithFormat:@"connect to disposable VM: %@", error]);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
      NSDictionary *request = @{@"operation":@"shell_command", @"request_id":@"mount-test", @"session_id":@"mount-test", @"command":command};
      NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:request options:0 error:nil] mutableCopy];
      [data appendBytes:"\n" length:1];
      Check(write(connection.fileDescriptor, data.bytes, data.length) == (ssize_t)data.length, @"send mount probe");
      NSMutableData *pending = [NSMutableData data]; NSMutableString *text = [NSMutableString string];
      BOOL complete = NO;
      while (!complete) {
        struct pollfd fd = {connection.fileDescriptor, POLLIN, 0};
        Check(poll(&fd, 1, 45000) > 0, @"mount probe returns before timeout");
        char bytes[8192]; ssize_t count = read(fd.fd, bytes, sizeof(bytes));
        Check(count > 0, @"mount probe returns a complete response");
        [pending appendBytes:bytes length:count];
        NSRange line;
        while ((line = [pending rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, pending.length)]).location != NSNotFound) {
          NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[pending subdataWithRange:NSMakeRange(0, line.location)] options:0 error:nil];
          [pending replaceBytesInRange:NSMakeRange(0, line.location + 1) withBytes:NULL length:0];
          Check(![event[@"type"] isEqual:@"error"], [NSString stringWithFormat:@"mount probe: %@", event]);
          if ([event[@"type"] isEqual:@"delta"]) [text appendString:event[@"text"] ?: @""];
          if ([event[@"type"] isEqual:@"complete"]) { complete = YES; break; }
        }
      }
      [connection close];
      dispatch_async(dispatch_get_main_queue(), ^{ output = text; done = YES; });
    });
  }];
  Wait(^BOOL{ return done; });
  return output;
}
int main(int argc, const char **argv) { @autoreleasepool {
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"TalariaMountTests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
  NSArray *folders = @[[root stringByAppendingPathComponent:@"a/work"], [root stringByAppendingPathComponent:@"b/work"],
    [root stringByAppendingPathComponent:@"a/my projects"], [root stringByAppendingPathComponent:@"a/旅行"]];
  for (NSString *path in folders) Check([fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil], @"create fixture folders");
  NSDictionary *paths = TLFolderMountPaths(folders);
  Check([paths isEqual:TLFolderMountPaths(folders.reverseObjectEnumerator.allObjects)], @"mount names do not depend on selection order");
  Check([NSSet setWithArray:paths.allValues].count == folders.count, @"matching folder names never overwrite another share");
  Check([TLFolderMountPaths(@[@"/"])[@"/"] isEqual:@"/mnt/mac/root"], @"disk has a predictable guest path");
  Check([TLFolderMountPaths(@[NSHomeDirectory()])[NSHomeDirectory()] isEqual:@"/mnt/mac/home"], @"home has a predictable guest path");
  Check([TLFolderMountPaths(@[@"/tmp/work", @"/tmp/work/"])[@"/tmp/work"] isEqual:@"/mnt/mac/work"], @"ordinary folders have readable names and deduplicate");
  for (NSString *path in paths.allValues) Check([VZMultipleDirectoryShare validateName:path.lastPathComponent error:nil], @"all export names satisfy Virtualization validation");
  TLAgentVMService *service = [[TLAgentVMService alloc] initWithAgentsDirectoryURL:[NSURL fileURLWithPath:root]
    runtimeBundleURL:[NSURL fileURLWithPath:argc > 2 ? @(argv[2]) : root]];
  TLAgentRecord *agent = [TLAgentRecord new]; agent.agentID = 91; agent.vmDirectory = [root stringByAppendingPathComponent:@"agent"]; agent.folderPaths = folders;
  NSError *error;
  VZVirtioFileSystemDeviceConfiguration *device = [service folderSharingDeviceForAgent:agent error:&error];
  Check(device && [device.tag isEqual:TLFolderMountTag], @"folder shares have their own virtiofs device");
  NSDictionary<NSString *, VZSharedDirectory *> *shares = ((VZMultipleDirectoryShare *)device.share).directories;
  Check(shares.count == folders.count, @"only selected folders are exported");
  for (NSString *path in folders) {
    VZSharedDirectory *share = shares[[paths[path] lastPathComponent]];
    Check([share.URL.path isEqual:path] && !share.readOnly, @"VM exports the exact folder at the displayed path with write access");
  }
  agent.folderPaths = @[[root stringByAppendingPathComponent:@"missing"]];
  Check(![service folderSharingDeviceForAgent:agent error:&error] && error, @"unavailable folders fail startup rather than pretending to mount");
  agent.folderPaths = @[];
  device = [service folderSharingDeviceForAgent:agent error:nil];
  Check(((VZMultipleDirectoryShare *)device.share).directories.count == 0, @"no selections export no Mac folders");
  if (argc > 2 && strcmp(argv[1], "--live") == 0) {
    NSString *allowed = [root stringByAppendingPathComponent:@"allowed"];
    NSString *forbidden = [root stringByAppendingPathComponent:@"forbidden"];
    for (NSString *path in @[allowed, forbidden]) [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    [@"from-mac" writeToFile:[allowed stringByAppendingPathComponent:@"from-mac.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"outside" writeToFile:[forbidden stringByAppendingPathComponent:@"secret"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check([fm createSymbolicLinkAtPath:[allowed stringByAppendingPathComponent:@"outside"] withDestinationPath:@"../forbidden/secret" error:nil], @"create an out-of-share symlink fixture");
    agent.folderPaths = @[allowed];
    Start(service, agent);
    Check([[service folderMountPathsForAgent:agent] isEqual:TLFolderMountPaths(@[allowed])], @"running VM reports its actual export mapping");
    NSString *out = Shell(service, agent, @"cat /mnt/mac/allowed/from-mac.txt && printf from-vm > /mnt/mac/allowed/from-vm.txt && test ! -e /mnt/mac/forbidden && test ! -e /mnt/mac/allowed/outside && printf '\\nmount-round-trip-ok\\n'");
    Check([out containsString:@"from-mac"] && [out containsString:@"mount-round-trip-ok"], @"guest reads shared data and cannot see unselected folders");
    Check([[NSString stringWithContentsOfFile:[allowed stringByAppendingPathComponent:@"from-vm.txt"] encoding:NSUTF8StringEncoding error:nil] isEqual:@"from-vm"], @"guest writes reach the chosen Mac folder");
    agent.folderPaths = @[];
    Check([service folderMountPathsForAgent:agent].count == 1, @"editing saved folders does not misreport the active VM's shares");
    Stop(service, agent);
    Check([service folderMountPathsForAgent:agent] == nil, @"stopped agents have no active mount mapping");
    Start(service, agent);
    out = Shell(service, agent, @"test -d /mnt/mac && test ! -e /mnt/mac/allowed && printf mount-removal-ok");
    Check([out containsString:@"mount-removal-ok"], @"restart revokes the removed folder without exposing others");
    Stop(service, agent);
  }
  [fm removeItemAtPath:root error:nil];
  puts("AgentFolderMountTests passed");
} return 0; }
