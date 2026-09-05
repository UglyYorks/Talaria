#import "TLTerminalClient.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <termios.h>
#include <unistd.h>

static volatile sig_atomic_t TLTerminalResized;
static volatile sig_atomic_t TLTerminalInterrupted;
static void TLTerminalSignal(int signalNumber) {
  if (signalNumber == SIGWINCH) TLTerminalResized = 1;
  else TLTerminalInterrupted = signalNumber;
}

static void TLAppendFrame(NSMutableData *buffer, char kind, NSData *payload) {
  uint32_t size = htonl((uint32_t)payload.length);
  [buffer appendBytes:&kind length:1];
  [buffer appendBytes:&size length:4];
  [buffer appendData:payload];
}

static struct winsize TLTerminalSize(void) {
  struct winsize size = {0};
  ioctl(STDIN_FILENO, TIOCGWINSZ, &size);
  if (!size.ws_row) size.ws_row = 24;
  if (!size.ws_col) size.ws_col = 80;
  return size;
}

static BOOL TLWriteTerminalBytes(const void *bytes, NSUInteger length) {
  const char *cursor = bytes;
  while (length) {
    ssize_t count = write(STDOUT_FILENO, cursor, length);
    if (count < 0 && errno == EINTR && !TLTerminalInterrupted) continue;
    if (count <= 0) return NO;
    cursor += count;
    length -= count;
  }
  return YES;
}

int TLRunTerminalClient(const char *socketPath) {
  if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
    fprintf(stderr, "Open this VM session in Terminal.app.\n");
    return 1;
  }
  struct sockaddr_un address = {0};
  address.sun_family = AF_UNIX;
  if (strlen(socketPath) >= sizeof(address.sun_path)) return 1;
  strlcpy(address.sun_path, socketPath, sizeof(address.sun_path));
  int connection = socket(AF_UNIX, SOCK_STREAM, 0);
  if (connection < 0 || connect(connection, (struct sockaddr *)&address, sizeof(address)) < 0) {
    fprintf(stderr, "This VM terminal session has expired. Open a new session from Talaria's Debug screen.\n");
    if (connection >= 0) close(connection);
    return 1;
  }
  struct termios original;
  if (tcgetattr(STDIN_FILENO, &original) < 0) { close(connection); return 1; }
  const int signals[] = {SIGWINCH, SIGHUP, SIGTERM, SIGINT, SIGPIPE};
  struct sigaction previous[5], action = {0};
  sigemptyset(&action.sa_mask);
  TLTerminalResized = TLTerminalInterrupted = 0;
  for (NSUInteger i = 0; i < 5; i++) {
    action.sa_handler = signals[i] == SIGPIPE ? SIG_IGN : TLTerminalSignal;
    sigaction(signals[i], &action, &previous[i]);
  }
  struct termios raw = original;
  cfmakeraw(&raw);
  int exitCode = 1;
  BOOL receivedExit = NO;
  NSString *errorMessage = nil;
  if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0) {
    const char banner[] = "\033]0;Talaria VM\007Talaria VM terminal\r\n";
    TLWriteTerminalBytes(banner, sizeof(banner) - 1);
    fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) | O_NONBLOCK);
    NSMutableData *outgoing = [NSMutableData data];
    NSMutableData *incoming = [NSMutableData data];
    struct winsize size = TLTerminalSize();
    NSString *term = NSProcessInfo.processInfo.environment[@"TERM"] ?: @"xterm-256color";
    NSData *hello = [NSJSONSerialization dataWithJSONObject:@{@"term":term, @"rows":@(size.ws_row), @"columns":@(size.ws_col)} options:0 error:nil];
    TLAppendFrame(outgoing, 'H', hello);
    while (!TLTerminalInterrupted && !receivedExit) {
      @autoreleasepool {
        if (TLTerminalResized) {
          TLTerminalResized = 0;
          size = TLTerminalSize();
          uint16_t dimensions[] = {htons(size.ws_row), htons(size.ws_col)};
          TLAppendFrame(outgoing, 'W', [NSData dataWithBytes:dimensions length:sizeof(dimensions)]);
        }
        struct pollfd descriptors[] = {
          {STDIN_FILENO, outgoing.length < 1024 * 1024 ? POLLIN : 0, 0},
          {connection, POLLIN | (outgoing.length ? POLLOUT : 0), 0},
        };
        int ready = poll(descriptors, 2, 100);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        char buffer[65536];
        if (descriptors[0].revents & POLLIN) {
          ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
          if (count <= 0) break;
          TLAppendFrame(outgoing, 'D', [NSData dataWithBytes:buffer length:(NSUInteger)count]);
        }
        if (descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL)) break;
        if (descriptors[1].revents & POLLOUT) {
          ssize_t count = write(connection, outgoing.bytes, outgoing.length);
          if (count > 0) [outgoing replaceBytesInRange:NSMakeRange(0, (NSUInteger)count) withBytes:NULL length:0];
          else if (count < 0 && errno != EAGAIN && errno != EINTR) break;
        }
        if (descriptors[1].revents & (POLLIN | POLLHUP)) {
          ssize_t count = read(connection, buffer, sizeof(buffer));
          if (count == 0) break;
          if (count < 0) { if (errno == EAGAIN || errno == EINTR) continue; break; }
          [incoming appendBytes:buffer length:(NSUInteger)count];
          while (incoming.length >= 5) {
            const unsigned char *bytes = incoming.bytes;
            uint32_t networkLength;
            memcpy(&networkLength, bytes + 1, 4);
            NSUInteger length = ntohl(networkLength);
            if (length > 1024 * 1024) { errorMessage = @"Invalid VM terminal response."; receivedExit = YES; break; }
            if (incoming.length < 5 + length) break;
            char kind = bytes[0];
            if (kind == 'D') {
              if (!TLWriteTerminalBytes(bytes + 5, length)) { receivedExit = YES; break; }
            } else if (kind == 'X' && length == 4) {
              uint32_t result;
              memcpy(&result, bytes + 5, 4);
              exitCode = (int)MIN(ntohl(result), 255);
              receivedExit = YES;
            } else {
              errorMessage = kind == 'E' ? [[NSString alloc] initWithBytes:bytes + 5 length:length encoding:NSUTF8StringEncoding] : @"Invalid VM terminal response.";
              receivedExit = YES;
            }
            [incoming replaceBytesInRange:NSMakeRange(0, 5 + length) withBytes:NULL length:0];
          }
        }
        if (descriptors[1].revents & (POLLERR | POLLNVAL)) break;
      }
    }
  }
  close(connection);
  tcsetattr(STDIN_FILENO, TCSANOW, &original);
  const char reset[] = "\033[0m\033[?25h\033[?1049l\033[?2004l";
  TLWriteTerminalBytes(reset, sizeof(reset) - 1);
  for (NSUInteger i = 0; i < 5; i++) sigaction(signals[i], &previous[i], NULL);
  if (errorMessage) fprintf(stderr, "\n%s\n", errorMessage.UTF8String);
  else if (!receivedExit && !TLTerminalInterrupted) fprintf(stderr, "\nThe VM terminal disconnected.\n");
  return TLTerminalInterrupted ? 128 + TLTerminalInterrupted : exitCode;
}
