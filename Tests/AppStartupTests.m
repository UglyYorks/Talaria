#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "AppDelegate.h"

static void Check(BOOL condition, NSString *message) {
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// Every process and NSWorkspace launch is mocked. No real app or user data opens.
@interface TLStartupRunningApplication : NSObject
@property pid_t processIdentifier;
@property NSDate *launchDate;
@property NSURL *bundleURL;
@property(getter=isTerminated) BOOL terminated;
@property NSUInteger activations;
@property NSUInteger unhides;
@property NSApplicationActivationOptions activationOptions;
@end
@implementation TLStartupRunningApplication
- (BOOL)unhide { self.unhides++; return YES; }
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options {
  Check(NSThread.isMainThread, @"fallback activation runs on the main thread");
  self.activations++;
  self.activationOptions = options;
  return YES;
}
@end

static TLStartupRunningApplication *currentApplication;
static NSArray *runningApplications;
@interface NSRunningApplication (StartupTests)
+ (NSRunningApplication *)startupTestCurrentApplication;
+ (NSArray<NSRunningApplication *> *)startupTestRunningApplicationsWithBundleIdentifier:(NSString *)identifier;
@end
@implementation NSRunningApplication (StartupTests)
+ (NSRunningApplication *)startupTestCurrentApplication { return (id)currentApplication; }
+ (NSArray<NSRunningApplication *> *)startupTestRunningApplicationsWithBundleIdentifier:(NSString *)identifier {
  Check([identifier isEqual:@"com.talaria.chat"], @"startup only inspects Talaria copies");
  return runningApplications;
}
@end

static NSURL *openedURL;
static NSWorkspaceOpenConfiguration *openConfiguration;
static void (^openCompletion)(NSRunningApplication *, NSError *);
@interface NSWorkspace (StartupTests)
- (void)startupTestOpenApplicationAtURL:(NSURL *)URL configuration:(NSWorkspaceOpenConfiguration *)configuration
  completionHandler:(void (^)(NSRunningApplication *, NSError *))completion;
@end
@implementation NSWorkspace (StartupTests)
- (void)startupTestOpenApplicationAtURL:(NSURL *)URL configuration:(NSWorkspaceOpenConfiguration *)configuration
  completionHandler:(void (^)(NSRunningApplication *, NSError *))completion {
  Check(openedURL == nil, @"one reopen request per duplicate launch");
  openedURL = URL;
  openConfiguration = configuration;
  openCompletion = [completion copy];
}
@end

@interface TLStartupApplication : NSApplication
@property NSUInteger terminations;
@end
@implementation TLStartupApplication
- (void)terminate:(id)sender {
  Check(NSThread.isMainThread, @"duplicate termination runs on the main thread");
  self.terminations++;
}
- (BOOL)setActivationPolicy:(NSApplicationActivationPolicy)policy { return YES; }
@end

@interface TLStartupDelegate : TLAppDelegate
@property NSUInteger normalStarts;
@end
@implementation TLStartupDelegate
- (void)installMainMenu {
  self.normalStarts++;
  // Stop at the first ordinary startup action, before touching any user data.
  @throw [NSException exceptionWithName:@"StartupTestReachedNormalLaunch" reason:nil userInfo:nil];
}
@end

static TLStartupRunningApplication *App(pid_t PID, NSTimeInterval launched) {
  TLStartupRunningApplication *app = [TLStartupRunningApplication new];
  app.processIdentifier = PID;
  app.launchDate = launched ? [NSDate dateWithTimeIntervalSince1970:launched] : nil;
  app.bundleURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/private/tmp/TalariaStartupTests/%d/Talaria.app", PID]];
  return app;
}

static void LaunchWithResult(TLStartupRunningApplication *current, NSArray *running,
                             TLStartupRunningApplication *expected, NSError *error, BOOL backgroundCompletion) {
  currentApplication = current;
  runningApplications = running;
  openedURL = nil; openConfiguration = nil; openCompletion = nil;
  TLStartupDelegate *delegate = [TLStartupDelegate new];
  TLStartupApplication *application = (id)NSApp;
  application.terminations = 0;
  NSUInteger activations = expected.activations, unhides = expected.unhides;
  @try {
    [delegate applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:application]];
  } @catch (NSException *exception) {
    Check([exception.name isEqual:@"StartupTestReachedNormalLaunch"], @"only the test startup boundary may throw");
  }
  Check(delegate.normalStarts == (expected ? 0U : 1U),
    expected ? @"duplicate stops before reset, data access, and tab restoration" : @"first copy proceeds to normal startup");
  if (!expected) {
    Check(!openedURL && !openCompletion && application.terminations == 0, @"first copy neither reopens nor terminates");
    return;
  }
  if (expected.bundleURL) {
    Check([openedURL isEqual:expected.bundleURL], @"reopen targets the exact existing bundle, independent of installed/worktree location");
    Check(!openConfiguration.createsNewApplicationInstance && !openConfiguration.allowsRunningApplicationSubstitution && openConfiguration.activates,
      @"normal reopen restores the existing app window without requesting a new process");
    Check(!openConfiguration.promptsUserIfNeeded, @"internal handoff errors reach completion without waiting on a launch dialog");
    Check(openCompletion != nil && application.terminations == 0, @"duplicate waits for reopen completion before terminating");
    void (^completion)(NSRunningApplication *, NSError *) = openCompletion;
    openCompletion = nil;
    if (backgroundCompletion) {
      dispatch_semaphore_t finished = dispatch_semaphore_create(0);
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        completion(error ? nil : (id)expected, error);
        dispatch_semaphore_signal(finished);
      });
      Check(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0,
        @"background launch completion returned");
    } else {
      completion(error ? nil : (id)expected, error);
    }
    Check(application.terminations == 0, @"completion defers AppKit work to the main queue");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!application.terminations && deadline.timeIntervalSinceNow > 0) {
      [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
  } else {
    Check(!openedURL && !openCompletion, @"missing bundle URL uses direct activation without a launch request");
  }
  Check(application.terminations == 1, @"duplicate terminates exactly once after handoff");
  BOOL fallback = error || !expected.bundleURL;
  Check(expected.activations == activations + (fallback ? 1U : 0U) &&
    expected.unhides == unhides + (fallback ? 1U : 0U), @"activation fallback is used only when reopen is unavailable");
  if (fallback) Check(expected.activationOptions == (NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows),
    @"fallback brings the existing app forward");
}

static void Launch(TLStartupRunningApplication *current, NSArray *running, TLStartupRunningApplication *expected) {
  LaunchWithResult(current, running, expected, nil, NO);
}

int main(void) {
  @autoreleasepool {
    [TLStartupApplication sharedApplication];
    Method current = class_getClassMethod(NSRunningApplication.class, @selector(currentApplication));
    Method testCurrent = class_getClassMethod(NSRunningApplication.class, @selector(startupTestCurrentApplication));
    Method running = class_getClassMethod(NSRunningApplication.class, @selector(runningApplicationsWithBundleIdentifier:));
    Method testRunning = class_getClassMethod(NSRunningApplication.class, @selector(startupTestRunningApplicationsWithBundleIdentifier:));
    Method open = class_getInstanceMethod(NSWorkspace.class, @selector(openApplicationAtURL:configuration:completionHandler:));
    Method testOpen = class_getInstanceMethod(NSWorkspace.class, @selector(startupTestOpenApplicationAtURL:configuration:completionHandler:));
    method_exchangeImplementations(current, testCurrent);
    method_exchangeImplementations(running, testRunning);
    method_exchangeImplementations(open, testOpen);

    TLStartupRunningApplication *installed = App(400, 100);
    TLStartupRunningApplication *worktree = App(500, 200);
    Launch(installed, @[installed], nil);
    Launch(worktree, @[worktree, installed], installed);
    Launch(installed, @[worktree, installed], nil);
    TLStartupRunningApplication *newInstalled = App(600, 300);
    Launch(newInstalled, @[newInstalled, worktree], worktree);
    installed.terminated = YES;
    Launch(worktree, @[installed, worktree], nil);
    Launch(worktree, @[], nil);

    TLStartupRunningApplication *wrappedPID = App(20, 400);
    Launch(wrappedPID, @[wrappedPID, worktree], worktree);
    TLStartupRunningApplication *sameTime = App(700, 200);
    Launch(sameTime, @[sameTime, worktree], worktree);
    Launch(worktree, @[sameTime, worktree], nil);
    TLStartupRunningApplication *noDate = App(800, 0);
    Launch(noDate, @[noDate, worktree], worktree);
    Launch(worktree, @[noDate, worktree], nil);
    TLStartupRunningApplication *undated = App(200, 0);
    TLStartupRunningApplication *earlier = App(300, 100);
    TLStartupRunningApplication *lowerPID = App(100, 200);
    Launch(undated, @[earlier, lowerPID, undated], lowerPID);
    Launch(earlier, @[undated, lowerPID, earlier], lowerPID);
    Launch(lowerPID, @[earlier, lowerPID, undated], nil);

    LaunchWithResult(newInstalled, @[newInstalled, worktree], worktree, nil, YES);
    NSError *launchError = [NSError errorWithDomain:@"StartupTests" code:1 userInfo:nil];
    LaunchWithResult(newInstalled, @[newInstalled, worktree], worktree, launchError, YES);
    worktree.bundleURL = nil;
    Launch(newInstalled, @[newInstalled, worktree], worktree);

    method_exchangeImplementations(open, testOpen);
    method_exchangeImplementations(running, testRunning);
    method_exchangeImplementations(current, testCurrent);
    NSLog(@"App startup tests passed");
  }
  return 0;
}
