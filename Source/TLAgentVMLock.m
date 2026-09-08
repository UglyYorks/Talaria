#import "TLAgentVMLock.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

@implementation TLAgentVMLock {
  int _descriptor;
}
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL error:(NSError **)error {
  if ((self = [super init])) {
    _descriptor = -1;
    NSURL *path = [directoryURL URLByAppendingPathComponent:@"runtime.lock"];
    _descriptor = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    BOOL opened = _descriptor >= 0;
    if (!opened || flock(_descriptor, LOCK_EX | LOCK_NB) != 0) {
      BOOL busy = opened && (errno == EWOULDBLOCK || errno == EAGAIN);
      if (error) *error = [NSError errorWithDomain:@"Talaria.AgentVM" code:busy ? 2 : 1
        userInfo:@{NSLocalizedDescriptionKey:busy
          ? @"This agent is running in another Talaria instance. Quit that instance before starting the agent here."
          : @"Could not lock the agent's storage. Check the agent folder's permissions."}];
      return nil;
    }
  }
  return self;
}
- (void)dealloc {
  // Never unlink this file: other processes must lock the same inode.
  if (_descriptor >= 0) close(_descriptor);
}
@end
