#import "AppDelegate.h"
#import "AgentClient.h"
#import "AgentOrchestrator.h"
#import "AgentVMService.h"
#import "AppStateManager.h"
#import "ChromiumBrowserController.h"
#import "Database.h"
#import "TalariaWindowController.h"
#import "Theme.h"

@interface TLAppDelegate ()

@property (nonatomic, strong) TLDatabase *database;
@property (nonatomic, strong) TLAgentOrchestrator *agentOrchestrator;
@property (nonatomic, strong) TLAppStateManager *appStateManager;
@property (nonatomic, strong) TalariaWindowController *windowController;
@property (nonatomic, strong) NSStatusItem *statusItem;

@end

@implementation TLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [self installMainMenu];

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

- (void)closeActiveTabOrWindow:(id)sender {
  [self.windowController closeActiveTabOrWindow:sender];
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

  NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  [mainMenu addItem:windowMenuItem];
  NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  NSMenuItem *closeItem = [windowMenu addItemWithTitle:@"Close" action:@selector(closeActiveTabOrWindow:) keyEquivalent:@"w"];
  closeItem.target = self;
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
