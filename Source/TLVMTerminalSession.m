#import "TLVMTerminalSession.h"
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static NSError *TLTerminalError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.Terminal" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *TLShellQuote(NSString *value) {
  return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}
static void TLCopyTerminalStream(int source, int destination) {
  char bytes[65536];
  while (YES) {
    ssize_t count = read(source, bytes, sizeof(bytes));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return;
    ssize_t offset = 0;
    while (offset < count) {
      ssize_t written = write(destination, bytes + offset, (size_t)(count - offset));
      if (written < 0 && errno == EINTR) continue;
      if (written <= 0) return;
      offset += written;
    }
  }
}

@interface TLVMTerminalSession ()
@property (nonatomic, strong) VZVirtioSocketConnection *connection;
@property (nonatomic, strong) NSURL *directoryURL;
@property (nonatomic, strong) NSURL *commandURL;
@property (nonatomic, strong) NSURL *socketURL;
@property (nonatomic) int listener;
@property (nonatomic) int client;
@property (nonatomic) int guest;
@property (atomic) BOOL cancelled;
@property (nonatomic) BOOL started;
@property (nonatomic, strong) id terminationObserver;
@end

@implementation TLVMTerminalSession
- (instancetype)initWithConnection:(VZVirtioSocketConnection *)connection executableURL:(NSURL *)executableURL error:(NSError **)error {
  self = [super init];
  if (!self) return nil;
  _listener = _client = _guest = -1;
  _connection = connection;
  // A short private directory also fits macOS's 104-byte Unix socket path limit.
  char directory[] = "/tmp/talaria-terminal.XXXXXX";
  if (!mkdtemp(directory)) {
    if (error) *error = TLTerminalError(@"Could not create a private terminal session.");
    return nil;
  }
  _directoryURL = [NSURL fileURLWithPath:@(directory) isDirectory:YES];
  _socketURL = [_directoryURL URLByAppendingPathComponent:@"socket"];
  _commandURL = [_directoryURL URLByAppendingPathComponent:@"Talaria VM.command"];
  NSString *script = [NSString stringWithFormat:@"#!/bin/sh\nexec %@ --vm-terminal %@\n",
    TLShellQuote(executableURL.path), TLShellQuote(_socketURL.path)];
  if (![script writeToURL:_commandURL atomically:YES encoding:NSUTF8StringEncoding error:error] ||
      ![NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:_commandURL.path error:error]) return nil;
  _listener = socket(AF_UNIX, SOCK_STREAM, 0);
  struct sockaddr_un address = {0};
  address.sun_family = AF_UNIX;
  strlcpy(address.sun_path, _socketURL.path.fileSystemRepresentation, sizeof(address.sun_path));
  if (_listener < 0 || bind(_listener, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(_listener, 1) < 0) {
    if (error) *error = TLTerminalError(@"Could not prepare the private VM terminal connection.");
    return nil;
  }
  __weak typeof(self) weakSelf = self;
  _terminationObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil
    usingBlock:^(NSNotification *notification) { [weakSelf cancel]; }];
  return self;
}

- (void)dealloc {
  if (_listener >= 0) close(_listener);
  if (_client >= 0) close(_client);
  if (_guest >= 0) close(_guest);
  if (_terminationObserver) [NSNotificationCenter.defaultCenter removeObserver:_terminationObserver];
  [_connection close];
  if (_directoryURL) [NSFileManager.defaultManager removeItemAtURL:_directoryURL error:nil];
}

- (void)cancel {
  self.cancelled = YES;
  @synchronized (self) {
    if (self.client >= 0) shutdown(self.client, SHUT_RDWR);
    if (self.guest >= 0) shutdown(self.guest, SHUT_RDWR);
  }
}

- (void)beginForwarding {
  if (self.started) return;
  self.started = YES;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    // The block keeps this one-use session alive until Terminal disconnects.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    int client = -1;
    while (!self.cancelled && deadline.timeIntervalSinceNow > 0) {
      struct pollfd descriptor = {self.listener, POLLIN, 0};
      int ready = poll(&descriptor, 1, 250);
      if (ready < 0 && errno == EINTR) continue;
      if (ready < 0) break;
      if (descriptor.revents & POLLIN) { client = accept(self.listener, NULL, NULL); break; }
    }
    close(self.listener);
    self.listener = -1;
    unlink(self.socketURL.path.fileSystemRepresentation);
    if (client >= 0) {
      int guest = dup(self.connection.fileDescriptor);
      @synchronized (self) {
        self.client = client;
        self.guest = guest;
      }
      int noSigPipe = 1;
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
      if (guest >= 0 && !self.cancelled) {
        setsockopt(guest, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
        dispatch_group_t transfers = dispatch_group_create();
        dispatch_group_async(transfers, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          TLCopyTerminalStream(client, guest);
          [self cancel];
        });
        dispatch_group_async(transfers, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
          TLCopyTerminalStream(guest, client);
          [self cancel];
        });
        dispatch_group_wait(transfers, DISPATCH_TIME_FOREVER);
      }
      @synchronized (self) {
        close(client);
        if (guest >= 0) close(guest);
        self.client = self.guest = -1;
      }
    }
    // Virtualization connection lifecycle stays on its owning main queue.
    dispatch_async(dispatch_get_main_queue(), ^{ [self.connection close]; self.connection = nil; });
  });
}

- (void)openInTerminalWithCompletion:(void (^)(NSError *))completion {
  NSURL *terminalURL = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
  if (!terminalURL) {
    [self cancel];
    completion(TLTerminalError(@"Terminal.app could not be found on this Mac."));
    return;
  }
  [self beginForwarding];
  NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
  configuration.activates = YES;
  [NSWorkspace.sharedWorkspace openURLs:@[self.commandURL] withApplicationAtURL:terminalURL configuration:configuration
    completionHandler:^(NSRunningApplication *application, NSError *error) {
      if (error) [self cancel];
      dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    }];
}
@end
