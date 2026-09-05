#import "TLTerminalClient.h"
int main(int argc, const char **argv) {
  @autoreleasepool { return argc == 2 ? TLRunTerminalClient(argv[1]) : 2; }
}
