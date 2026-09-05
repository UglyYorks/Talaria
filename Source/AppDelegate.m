#import "AppDelegate.h"
#import "AgentClient.h"
#import "AgentOrchestrator.h"
#import "AgentVMService.h"
#import "AppStateManager.h"
#import "ChromiumBrowserController.h"
#import "Database.h"
#import "TalariaWindowController.h"
#import "Theme.h"
#import "TLAppReset.h"

@interface TLAppDelegate ()

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAppStateManager *appStateManager;
@property (nonatomic, strong) TalariaWindowController *windowController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic) BOOL resetInProgress;

@end

@implementation TLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [self installMainMenu];

  TLAppReset *reset = [[TLAppReset alloc] init];
  while (reset.resetPending) {
    NSError *resetError = nil;
    if (![self hasOtherRunningInstance] && [reset performPendingReset:&resetError]) break;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Talaria reset could not finish";
    alert.informativeText = resetError.localizedDescription ?: @"Quit all other copies of Talaria, then retry. No app data can be cleared while another copy is running.";
    [alert addButtonWithTitle:@"Retry"];
    [alert addButtonWithTitle:@"Quit"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
      [NSApp terminate:nil];
      return;
    }
  }

  NSError *error = nil;
  self.database = [[TLDatabase alloc] initWithURL:TLDatabase.defaultDatabaseURL error:&error];
  if (!self.database) {
    [self presentStartupError:error];
    [NSApp terminate:nil];
    return;
  }

  TLAgentVMService *vmService = [[TLAgentVMService alloc] init];
  TLBundledAgentClient *agentClient = [[TLBundledAgentClient alloc] initWithVMService:vmService];
  self.agentOrchestrator = [[TLAgentOrchestrator alloc] initWithDatabase:self.database
                                                             agentClient:agentClient
                                                               vmService:vmService];
  self.appStateManager = [[TLAppStateManager alloc] init];
  self.windowController = [[TalariaWindowController alloc] initWithDatabase:self.database
                                                            agentOrchestrator:self.agentOrchestrator
                                                              appStateManager:self.appStateManager];
  [self installStatusItem];
  [self presentMainWindow:self];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self presentMainWindow:self];
  });
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  [self presentMainWindow:self];
  return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
  return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
  return [TLChromiumBrowserController.sharedController prepareForApplicationTermination]
    ? NSTerminateNow
    : NSTerminateLater;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  [TLChromiumBrowserController.sharedController shutdown];
}

- (BOOL)hasOtherRunningInstance {
  for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.talaria.chat"]) {
    if (app.processIdentifier != NSProcessInfo.processInfo.processIdentifier && !app.terminated) return YES;
  }
  return NO;
}

- (void)resetApp:(id)sender {
  if (self.resetInProgress) return;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.alertStyle = NSAlertStyleCritical;
  alert.messageText = @"Completely reset Talaria?";
  alert.informativeText = @"This permanently deletes all Talaria chats, settings, saved API token, browser data, and every Talaria VM and its files. Talaria will quit and reopen at onboarding. This affects all copies of Talaria on this Mac and cannot be undone.";
  [alert addButtonWithTitle:@"Cancel"];
  [alert addButtonWithTitle:@"Reset everything"];
  [alert beginSheetModalForWindow:self.windowController.window completionHandler:^(NSModalResponse response) {
    if (response != NSAlertSecondButtonReturn) return;
    if ([self hasOtherRunningInstance]) {
      NSAlert *otherAppAlert = [[NSAlert alloc] init];
      otherAppAlert.messageText = @"Quit other copies of Talaria first";
      otherAppAlert.informativeText = @"Another copy is using the same app data. Quit it, then reset again.";
      [otherAppAlert beginSheetModalForWindow:self.windowController.window completionHandler:nil];
      return;
    }
    TLAppReset *reset = [[TLAppReset alloc] init];
    NSError *error = nil;
    if (![reset requestReset:&error]) {
      [NSApp presentError:error];
      return;
    }
    // Wait for this process to exit, releasing every VM and database handle.
    // Pass the bundle path as an argument, never interpolate it into shell code.
    NSTask *relauncher = [[NSTask alloc] init];
    relauncher.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    relauncher.arguments = @[@"-c", @"while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$2\"", @"talaria-reset",
      [NSString stringWithFormat:@"%d", NSProcessInfo.processInfo.processIdentifier], NSBundle.mainBundle.bundleURL.path];
    relauncher.standardInput = NSFileHandle.fileHandleWithNullDevice;
    relauncher.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    relauncher.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![relauncher launchAndReturnError:&error]) {
      NSError *cancelError = nil;
      if (![reset cancelReset:&cancelError]) {
        [NSApp presentError:cancelError];
      }
      [NSApp presentError:error];
      return;
    }
    self.resetInProgress = YES;
    [NSApp terminate:self];
  }];
}

- (void)openChat:(id)sender {
  [self presentMainWindow:sender];
}

- (void)presentMainWindow:(id)sender {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp unhide:self];
  [self.windowController showWindow:self];
  [self.windowController.window deminiaturize:sender];
  [self.windowController.window makeKeyAndOrderFront:sender];
  [self.windowController.window orderFrontRegardless];
  [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeApp:(id)sender {
  [NSApp terminate:self];
}

- (BOOL)workspaceAcceptsTabCommands {
  NSWindow *window = self.windowController.window;
  return window && NSApp.keyWindow == window && !window.attachedSheet && !NSApp.modalWindow;
}

- (BOOL)handleTabShortcutEvent:(NSEvent *)event {
  TLTabCommand command = TLTabCommandForEvent(event);
  if (command == TLTabCommandNone || ![self workspaceAcceptsTabCommands] ||
      (event.window && event.window != self.windowController.window)) return NO;
  // Consume recognized but disabled shortcuts too: a page must not act on them.
  if ((!event.isARepeat || TLTabCommandAllowsRepeat(command)) &&
      [self.windowController canPerformTabCommand:command]) {
    [self.windowController performTabCommand:command];
  }
  return YES;
}

- (void)performTabMenuCommand:(NSMenuItem *)sender {
  if ([self workspaceAcceptsTabCommands] && [self.windowController canPerformTabCommand:sender.tag]) {
    [self.windowController performTabCommand:sender.tag];
  }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  if (item.action == @selector(performTabMenuCommand:)) {
    return [self workspaceAcceptsTabCommands] && [self.windowController canPerformTabCommand:item.tag];
  }
  return YES;
}

- (void)installMainMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

  NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:appMenuItem];

  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Talaria"];
  [appMenu addItemWithTitle:@"Open Chat" action:@selector(openChat:) keyEquivalent:@"0"].target = self;
  [appMenu addItem:NSMenuItem.separatorItem];
  [appMenu addItemWithTitle:@"Hide Talaria" action:@selector(hide:) keyEquivalent:@"h"];
  NSMenuItem *quitItem = [appMenu addItemWithTitle:@"Quit Talaria" action:@selector(terminate:) keyEquivalent:@"q"];
  quitItem.target = NSApp;
  quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
  appMenuItem.submenu = appMenu;

  NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:editMenuItem];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  NSMenuItem *redoItem = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  redoItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
  [editMenu addItem:NSMenuItem.separatorItem];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  editMenuItem.submenu = editMenu;

  NSMenuItem *tabMenuItem = [[NSMenuItem alloc] initWithTitle:@"Tab" action:nil keyEquivalent:@""];
  tabMenuItem.submenu = TLCreateTabMenu(self, @selector(performTabMenuCommand:));
  [mainMenu addItem:tabMenuItem];

  NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:windowMenuItem];
  NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];

  windowMenuItem.submenu = windowMenu;
  NSApp.windowsMenu = windowMenu;

  NSApp.mainMenu = mainMenu;
}

- (void)installStatusItem {
  self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
  self.statusItem.button.image = [self statusBarIcon];
  self.statusItem.button.imagePosition = NSImageOnly;
  self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;
  self.statusItem.button.title = @"";
  self.statusItem.button.toolTip = @"Talaria";

  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Talaria"];
  NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open chat" action:@selector(openChat:) keyEquivalent:@""];
  openItem.target = self;
  [menu addItem:openItem];

  NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close app" action:@selector(closeApp:) keyEquivalent:@""];
  closeItem.target = self;
  [menu addItem:closeItem];

  self.statusItem.menu = menu;
}

- (NSImage *)statusBarIcon {
  NSImage *image = [NSImage imageWithSystemSymbolName:@"app"
                             accessibilityDescription:@"Talaria"];
  image.size = NSMakeSize(18.0, 18.0);
  image.template = YES;
  return image;
}

- (void)presentStartupError:(NSError *)error {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Talaria could not start";
  alert.informativeText = error.localizedDescription ?: @"The database could not be opened.";
  [alert runModal];
}

@end
