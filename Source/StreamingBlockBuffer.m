#import "StreamingBlockBuffer.h"

static NSUInteger TLReadyLengthForStreamingMarkdown(NSString *text);
static BOOL TLStreamingLineStartsFence(NSString *line);

@interface TLStreamingBlockBuffer ()

@property (nonatomic, strong) NSMutableString *mutableCommittedText;
@property (nonatomic, strong) NSMutableString *pendingText;

@end

@implementation TLStreamingBlockBuffer

- (instancetype)init {
  self = [super init];
  if (self) {
    _mutableCommittedText = [NSMutableString string];
    _pendingText = [NSMutableString string];
  }
  return self;
}

- (NSString *)committedText {
  return [self.mutableCommittedText copy];
}

- (NSString *)appendText:(NSString *)text {
  if (text.length == 0) {
    return self.committedText;
  }

  [self.pendingText appendString:text];
  NSUInteger readyLength = TLReadyLengthForStreamingMarkdown(self.pendingText);
  if (readyLength > 0) {
    NSString *readyText = [self.pendingText substringToIndex:readyLength];
    [self.mutableCommittedText appendString:readyText];
    [self.pendingText deleteCharactersInRange:NSMakeRange(0, readyLength)];
  }

  return self.committedText;
}

- (NSString *)flush {
  if (self.pendingText.length > 0) {
    [self.mutableCommittedText appendString:self.pendingText];
    [self.pendingText setString:@""];
  }

  return self.committedText;
}

static BOOL TLStreamingLineStartsFence(NSString *line) {
  NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return [trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"];
}

static NSUInteger TLReadyLengthForStreamingMarkdown(NSString *text) {
  NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
  BOOL insideFence = NO;
  NSUInteger readyLength = 0;
  NSUInteger offset = 0;

  for (NSUInteger index = 0; index < lines.count; index += 1) {
    NSString *line = lines[index];
    BOOL hasLineBreak = index < lines.count - 1;
    if (!hasLineBreak) {
      break;
    }

    if (TLStreamingLineStartsFence(line)) {
      insideFence = !insideFence;
    }

    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!insideFence && trimmed.length == 0) {
      readyLength = offset + line.length + 1;
    }

    offset += line.length + 1;
  }

  return readyLength;
}

@end
