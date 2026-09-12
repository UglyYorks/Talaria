#import "TLHostCommandBridge.h"
#import "Theme.h"
#import <spawn.h>
#import <sys/wait.h>
#import <poll.h>
#import <fcntl.h>
#import <signal.h>

static NSString *const TLHostPolicyKey = @"TalariaHostCommandPolicies";
static NSString *const TLHostChatsKey = @"TalariaHostCommandChats";
static const NSUInteger TLHostOutputLimit = 65536;

@interface TLHostCommandOperation ()
@property (atomic, readwrite) BOOL cancelled;
@property (nonatomic, strong) NSAlert *alert;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) pid_t processGroup;
@property (nonatomic, strong) id terminationObserver;
@end
@implementation TLHostCommandOperation
- (instancetype)init {
  if ((self = [super init])) {
    __weak typeof(self) weakSelf = self;
    _terminationObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification
      object:nil queue:nil usingBlock:^(NSNotification *note) { [weakSelf cancel]; }];
  }
  return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self.terminationObserver]; }
- (void)cancel {
  @synchronized (self) {
    self.cancelled = YES;
    if (self.processGroup > 0) kill(-self.processGroup, SIGKILL);
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.alert.window.sheetParent) [self.alert.window.sheetParent endSheet:self.alert.window returnCode:NSModalResponseCancel];
    [self.timer invalidate];
    self.timer = nil;
  });
}
@end

BOOL TLValidateHostCommand(NSDictionary *request) {
  id command = request[@"command"], cwd = request[@"cwd"], timeout = request[@"timeout_seconds"];
  NSString *nul = [NSString stringWithFormat:@"%C", (unichar)0];
  return [command isKindOfClass:NSString.class] && [command length] && [command length] <= 32768 &&
    [command rangeOfString:nul].location == NSNotFound &&
    [cwd isKindOfClass:NSString.class] && [cwd length] <= 4096 && [cwd rangeOfString:nul].location == NSNotFound &&
    (![cwd length] || [cwd hasPrefix:@"/"] || [cwd hasPrefix:@"~/"]) &&
    [timeout isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)timeout) != CFBooleanGetTypeID() &&
    [timeout doubleValue] == [timeout integerValue] && [timeout integerValue] >= 1 && [timeout integerValue] <= 120;
}

static NSString *TLHostOutputString(NSData *data) {
  // Preserve arbitrary shell bytes instead of dropping all output when a
  // command emits non-UTF-8 data or hits a multibyte boundary.
  NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return text ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
}

NSDictionary *TLExecuteHostCommand(NSDictionary *request, TLHostCommandOperation *operation) {
  if (!TLValidateHostCommand(request)) return @{@"error":@"Invalid host command."};
  if (operation.cancelled) return @{@"error":@"Host command cancelled.", @"cancelled":@YES};
  NSString *cwd = [request[@"cwd"] length] ? [request[@"cwd"] stringByExpandingTildeInPath] : NSHomeDirectory();
  int outFD[2], errFD[2];
  if (pipe(outFD)) return @{@"error":@"Could not open host command output."};
  if (pipe(errFD)) { close(outFD[0]); close(outFD[1]); return @{@"error":@"Could not open host command error output."}; }
  for (int fd = 0; fd < 2; fd++) {
    fcntl(outFD[fd], F_SETFD, FD_CLOEXEC);
    fcntl(errFD[fd], F_SETFD, FD_CLOEXEC);
  }
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_adddup2(&actions, outFD[1], STDOUT_FILENO);
  posix_spawn_file_actions_adddup2(&actions, errFD[1], STDERR_FILENO);
  posix_spawn_file_actions_addchdir_np(&actions, cwd.fileSystemRepresentation);
  posix_spawnattr_t attributes;
  posix_spawnattr_init(&attributes);
  posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT);
  posix_spawnattr_setpgroup(&attributes, 0);
  NSString *shell = NSProcessInfo.processInfo.environment[@"SHELL"];
  if (![shell hasPrefix:@"/"] || ![NSFileManager.defaultManager isExecutableFileAtPath:shell]) shell = @"/bin/zsh";
  NSArray *argv = @[shell, @"-l", @"-c", request[@"command"]];
  char *arguments[5] = {0};
  for (NSUInteger i = 0; i < argv.count; i++) arguments[i] = (char *)[argv[i] UTF8String];
  NSMutableDictionary *environment = [NSMutableDictionary dictionary];
  for (NSString *key in @[@"PATH", @"HOME", @"USER", @"LOGNAME", @"TMPDIR", @"LANG", @"LC_ALL", @"SHELL"])
    if (NSProcessInfo.processInfo.environment[key]) environment[key] = NSProcessInfo.processInfo.environment[key];
  environment[@"HOME"] = NSHomeDirectory();
  environment[@"PATH"] = environment[@"PATH"] ?: @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  NSMutableArray *entries = [NSMutableArray array];
  for (NSString *key in environment) [entries addObject:[NSString stringWithFormat:@"%@=%@", key, environment[key]]];
  char **envp = calloc(entries.count + 1, sizeof(char *));
  for (NSUInteger i = 0; i < entries.count; i++) envp[i] = (char *)[entries[i] UTF8String];
  pid_t pid = 0;
  int spawnError = operation.cancelled ? ECANCELED : posix_spawn(&pid, shell.fileSystemRepresentation, &actions, &attributes, arguments, envp);
  free(envp);
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  close(outFD[1]); close(errFD[1]);
  if (spawnError) {
    close(outFD[0]); close(errFD[0]);
    return @{@"error":[NSString stringWithFormat:@"Could not start host command: %s", strerror(spawnError)], @"cancelled":@(operation.cancelled)};
  }
  @synchronized (operation) {
    operation.processGroup = pid;
    if (operation.cancelled) kill(-pid, SIGKILL);
  }
  int descriptors[] = {outFD[0], errFD[0]};
  NSMutableData *buffers[] = {[NSMutableData data], [NSMutableData data]};
  for (int i = 0; i < 2; i++) fcntl(descriptors[i], F_SETFL, O_NONBLOCK);
  double deadline = NSProcessInfo.processInfo.systemUptime + [request[@"timeout_seconds"] doubleValue];
  BOOL timedOut = NO, truncated = NO, exited = NO;
  int status = 0;
  while (!exited) {
    timedOut = NSProcessInfo.processInfo.systemUptime >= deadline;
    if (operation.cancelled || timedOut) kill(-pid, SIGKILL);
    struct pollfd polls[] = {{descriptors[0], POLLIN, 0}, {descriptors[1], POLLIN, 0}};
    poll(polls, 2, 25);
    for (int i = 0; i < 2; i++) {
      char bytes[8192];
      // Bound each pass so an infinite writer cannot starve cancellation.
      for (int chunk = 0; chunk < 16; chunk++) {
        ssize_t count = read(descriptors[i], bytes, sizeof(bytes));
        if (count == 0) { close(descriptors[i]); descriptors[i] = -1; }
        if (count <= 0) break;
        NSUInteger keep = MIN((NSUInteger)count, TLHostOutputLimit - buffers[i].length);
        [buffers[i] appendBytes:bytes length:keep];
        truncated |= keep < (NSUInteger)count;
      }
    }
    pid_t waited = waitpid(pid, &status, WNOHANG);
    exited = waited == pid || (waited < 0 && errno == ECHILD);
  }
  // No detached/background jobs: close descendants' inherited output as well.
  @synchronized (operation) {
    kill(-pid, SIGKILL);
    operation.processGroup = 0;
  }
  for (int i = 0; i < 2; i++) {
    char bytes[8192];
    for (int chunk = 0; chunk < 16; chunk++) {
      ssize_t count = read(descriptors[i], bytes, sizeof(bytes));
      if (count <= 0) break;
      NSUInteger keep = MIN((NSUInteger)count, TLHostOutputLimit - buffers[i].length);
      [buffers[i] appendBytes:bytes length:keep];
      truncated |= keep < (NSUInteger)count;
    }
    if (descriptors[i] >= 0) close(descriptors[i]);
  }
  NSInteger exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
  return @{@"stdout":TLHostOutputString(buffers[0]), @"stderr":TLHostOutputString(buffers[1]),
    @"exit_code":@(exitCode), @"timed_out":@(timedOut), @"cancelled":@(operation.cancelled), @"truncated":@(truncated), @"cwd":cwd};
}

@interface TLHostCommandBridge ()
@property NSUserDefaults *defaults;
@property NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *privateChats;
@end

@implementation TLHostCommandBridge
+ (instancetype)sharedBridge {
  static TLHostCommandBridge *bridge;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ bridge = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
  return bridge;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
  if ((self = [super init])) { _defaults = defaults; _privateChats = [NSMutableDictionary dictionary]; }
  return self;
}
- (NSString *)policyForAgent:(NSString *)agentKey {
  NSString *policy = [self.defaults dictionaryForKey:TLHostPolicyKey][agentKey];
  return [@[@"ask", @"always", @"deny"] containsObject:policy] ? policy : @"ask";
}
- (void)setPolicy:(NSString *)policy forAgent:(NSString *)agentKey {
  if (!agentKey.length || ![@[@"ask", @"always", @"deny"] containsObject:policy]) return;
  NSMutableDictionary *policies = [[self.defaults dictionaryForKey:TLHostPolicyKey] mutableCopy] ?: [NSMutableDictionary dictionary];
  policies[agentKey] = policy;
  [self.defaults setObject:policies forKey:TLHostPolicyKey];
  // Resetting access revokes existing chat grants too, including private chats.
  NSMutableDictionary *chats = [[self.defaults dictionaryForKey:TLHostChatsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
  [chats removeObjectForKey:agentKey];
  [self.defaults setObject:chats forKey:TLHostChatsKey];
  for (NSString *scope in self.privateChats) {
    for (NSString *key in self.privateChats[scope].copy)
      if ([key hasPrefix:[agentKey stringByAppendingString:@"\n"]]) [self.privateChats[scope] removeObject:key];
  }
}
- (BOOL)isAllowedForAgent:(NSString *)agentKey chat:(NSString *)chatID privateScope:(NSString *)privateScope {
  NSString *policy = [self policyForAgent:agentKey];
  if ([policy isEqual:@"deny"]) return NO;
  if ([policy isEqual:@"always"]) return YES;
  if (privateScope.length) return [self.privateChats[privateScope] containsObject:[NSString stringWithFormat:@"%@\n%@", agentKey, chatID]];
  return [[self.defaults dictionaryForKey:TLHostChatsKey][agentKey] containsObject:chatID];
}
- (void)allowChat:(NSString *)chatID agent:(NSString *)agentKey privateScope:(NSString *)privateScope {
  if (!chatID.length || !agentKey.length) return;
  if (privateScope.length) {
    if (!self.privateChats[privateScope]) self.privateChats[privateScope] = [NSMutableSet set];
    [self.privateChats[privateScope] addObject:[NSString stringWithFormat:@"%@\n%@", agentKey, chatID]];
    return;
  }
  NSMutableDictionary *chats = [[self.defaults dictionaryForKey:TLHostChatsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
  NSMutableSet *allowed = [NSMutableSet setWithArray:chats[agentKey] ?: @[]];
  [allowed addObject:chatID];
  chats[agentKey] = allowed.allObjects;
  [self.defaults setObject:chats forKey:TLHostChatsKey];
}
- (void)clearPrivateScope:(NSString *)privateScope { [self.privateChats removeObjectForKey:privateScope]; }

- (TLHostCommandOperation *)runRequest:(NSDictionary *)request agent:(NSString *)agentKey name:(NSString *)agentName
                                 chat:(NSString *)chatID privateScope:(NSString *)privateScope window:(NSWindow *)window
                           completion:(void (^)(NSDictionary *))completion {
  NSAssert(NSThread.isMainThread, @"Host consent belongs to the main thread");
  TLHostCommandOperation *operation = [TLHostCommandOperation new];
  if (!TLValidateHostCommand(request) || !agentKey.length || !chatID.length) {
    completion(@{@"error":@"Invalid host command request."}); return operation;
  }
  request = @{@"command":[request[@"command"] copy], @"cwd":[request[@"cwd"] copy], @"timeout_seconds":request[@"timeout_seconds"]};
  void (^execute)(void) = ^{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSDictionary *result = TLExecuteHostCommand(request, operation);
      dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
  };
  if ([[self policyForAgent:agentKey] isEqual:@"deny"]) {
    completion(@{@"error":@"Host commands are blocked in Agent Settings.", @"denied":@YES});
  } else if ([self isAllowedForAgent:agentKey chat:chatID privateScope:privateScope]) {
    execute();
  } else if (!window) {
    completion(@{@"error":@"Open the chat window to approve host commands.", @"denied":@YES});
  } else {
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Allow %@ to run a command on your Mac?", agentName];
    alert.informativeText = [NSString stringWithFormat:@"This command runs with your macOS account and can change files and apps. Chat access applies only to the chat that requested it. Always allow applies to this agent and can be changed in Agent Settings.%@",
      privateScope.length ? @" Incognito commands can still change files on your Mac." : @""];
    TLThemePalette *palette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem effectiveAppearance:window.effectiveAppearance];
    NSScrollView *preview = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, palette.settingsSheetWidth - palette.space16 * 2, palette.fieldHeight * 4)];
    preview.hasVerticalScroller = YES;
    NSTextView *code = [[NSTextView alloc] initWithFrame:preview.bounds];
    code.editable = NO; code.selectable = YES; code.richText = NO;
    code.verticallyResizable = YES; code.horizontallyResizable = NO;
    code.autoresizingMask = NSViewWidthSizable;
    code.textContainer.widthTracksTextView = YES;
    code.textContainer.containerSize = NSMakeSize(NSWidth(preview.bounds), CGFLOAT_MAX);
    code.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    code.textContainerInset = NSMakeSize(palette.space4, palette.space4);
    code.string = [NSString stringWithFormat:@"Folder: %@\n\n%@", [request[@"cwd"] length] ? request[@"cwd"] : NSHomeDirectory(), request[@"command"]];
    preview.documentView = code;
    alert.accessoryView = preview;
    for (NSString *title in @[@"Allow once", @"Allow in this chat", @"Always allow", @"Deny"]) [alert addButtonWithTitle:title];
    for (NSButton *button in alert.buttons) button.keyEquivalent = @"";
    alert.buttons.lastObject.keyEquivalent = @"\e";
    operation.alert = alert;
    // Sheets are queued per window and expire if there is no user response.
    double deadline = NSProcessInfo.processInfo.systemUptime + 180;
    __weak TLHostCommandOperation *weakOperation = operation;
    operation.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
      TLHostCommandOperation *op = weakOperation;
      if (!op || op.cancelled) { [timer invalidate]; return; }
      alert.window.appearance = window.effectiveAppearance;
      TLThemePalette *currentPalette = [TLThemePalette paletteForPreference:TLThemePreferenceSystem effectiveAppearance:window.effectiveAppearance];
      code.font = currentPalette.markdownCodeFont;
      code.textColor = currentPalette.markdownCodeText;
      code.backgroundColor = currentPalette.markdownCodeSurface;
      preview.backgroundColor = currentPalette.markdownCodeSurface;
      if (!window.visible || NSProcessInfo.processInfo.systemUptime >= deadline) {
        if (alert.window.sheetParent) [window endSheet:alert.window returnCode:NSModalResponseCancel];
        else { [op cancel]; completion(@{@"error":@"Host command approval expired.", @"denied":@YES}); }
        return;
      }
      if (window.attachedSheet) return;
      [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        [op.timer invalidate]; op.timer = nil; op.alert = nil;
        @synchronized (op) {
          if (op.cancelled || response < NSAlertFirstButtonReturn || response > NSAlertThirdButtonReturn) {
            completion(@{@"error":@"Host command denied or cancelled.", @"denied":@YES}); return;
          }
          if (response == NSAlertSecondButtonReturn) [self allowChat:chatID agent:agentKey privateScope:privateScope];
          if (response == NSAlertThirdButtonReturn) [self setPolicy:@"always" forAgent:agentKey];
          execute();
        }
      }];
    }];
  }
  return operation;
}
@end
