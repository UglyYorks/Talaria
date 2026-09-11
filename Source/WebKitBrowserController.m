#import "WebKitBrowserController.h"
#import "WebKitPageBridge.h"
#import "WebKitBrowserSettings.h"
#import "design_system/TLBrowserWebView.h"
#import "design_system/TLSourceWindowController.h"
#import "WebKitImageLoader.h"
#import "AppDelegate.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserProfileImporter.h"
#import "TLBrowserDownloadManager.h"
#import "Theme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>

// WebKit SPI: _WKRenderingProgressEventFirstVisuallyNonEmptyLayout.
// Source: WebKit/Shared/API/Cocoa/_WKRenderingProgressEvents.h.
static const NSUInteger TLFirstVisuallyNonEmptyLayout = 1 << 1;

static NSError *TLWebKitError(NSString *message) {
  return [NSError errorWithDomain:@"Talaria.Browser" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL TLBrowserURLSupported(NSURL *URL) {
  return TLBrowserImageURLIsSupported(URL) || URL.isFileURL || [URL.absoluteString isEqual:@"about:blank"];
}
static NSString *TLBrowserSafariApplicationName(void) {
  static NSString *name;
  static dispatch_once_t once;
  dispatch_once(&once,^{
    NSURL *URL=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Safari"];
    NSBundle *safari=[NSBundle bundleWithURL:URL ?: [NSURL fileURLWithPath:@"/Applications/Safari.app"]];
    NSString *version=[safari objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if(![safari.bundleIdentifier isEqual:@"com.apple.Safari"] || ![version isKindOfClass:NSString.class] || !version.length)return;
    NSRange match=[version rangeOfString:@"[0-9]+(?:\\.[0-9]+){1,2}" options:NSRegularExpressionSearch];
    if(!NSEqualRanges(match,NSMakeRange(0,version.length)))return;
    // Safari's compatibility token is frozen; the Version token tracks Safari
    // updates independently of macOS. Keep WebKit's own UA prefix untouched.
    name=[NSString stringWithFormat:@"Version/%@ Safari/605.1.15",version];
  });
  return name;
}
static NSString *TLBrowserJSON(id object) {
  NSData *data=[NSJSONSerialization dataWithJSONObject:object ?: NSNull.null options:NSJSONWritingFragmentsAllowed error:nil];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"null";
}
static id TLWebKitOptionalValue(id object, NSString *key) {
  @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static BOOL TLWebKitOptionalAction(id object, NSString *name) {
  SEL selector=NSSelectorFromString(name);
  if (![object respondsToSelector:selector]) return NO;
  ((void (*)(id,SEL))objc_msgSend)(object,selector);return YES;
}
static WKContentWorld *TLBrowserUIWorld(void) { return [WKContentWorld worldWithName:@"talaria-browser-ui"]; }
static void TLStyleBrowserPrompt(NSAlert *alert, TLThemePalette *palette) {
  alert.window.appearance=[NSAppearance appearanceNamed:palette.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  NSArray<NSView *> *fields=[alert.accessoryView isKindOfClass:NSTextField.class] ? @[alert.accessoryView] : alert.accessoryView.subviews;
  for(NSView *view in fields)if([view isKindOfClass:NSTextField.class]) {
    NSTextField *field=(NSTextField *)view;field.font=palette.bodyFont;field.textColor=palette.controlText;field.backgroundColor=palette.controlSurface;
  }
}

@interface TLWebKitBrowserSession ()
@property (nonatomic, weak, readwrite) NSView *containerView;
@property (nonatomic, strong, readwrite) WKWebView *webView;
@property (nonatomic, copy, readwrite) NSString *initialURLString;
@property (nonatomic, readwrite) NSInteger browserIdentifier;
@property (nonatomic, readwrite) NSUInteger documentGeneration;
@property (nonatomic, readwrite, getter=isFullscreen) BOOL fullscreen;
@property (nonatomic, readwrite) BOOL devToolsVisible;
@property (nonatomic) BOOL inspectorNeedsDetach;
@property (nonatomic) TLWebKitPageBridge *pageBridge;
@property (nonatomic, copy) TLWebKitBrowserTitleHandler titleHandler;
@property (nonatomic, copy) TLWebKitBrowserLinkHandler linkHandler;
@property (nonatomic, copy) TLWebKitBrowserURLHandler URLHandler;
@property (nonatomic, copy) TLWebKitBrowserFaviconHandler faviconHandler;
@property (nonatomic, copy) TLWebKitBrowserNavigationHandler navigationHandler;
@property (nonatomic, weak) NSWindow *originWindow;
@property (nonatomic) NSWindow *standaloneWindow;
@property (nonatomic) BOOL incognito;
@property (nonatomic) BOOL closed;
@property (nonatomic) BOOL downloadOnly;
@property (nonatomic) BOOL paused;
@property (nonatomic) NSDate *backgroundSince;
@property (nonatomic) NSDictionary *documentFooterConfiguration;
@property (nonatomic) NSImageView *navigationCover;
@property (nonatomic) NSUInteger transitionGeneration;
@property (nonatomic) BOOL awaitingNavigationCommit;
@property (nonatomic) NSDictionary *context;
@property (nonatomic) WKFrameInfo *contextFrame;
@property (nonatomic, copy) dispatch_block_t menuCleanup;
@property (nonatomic) NSString *lastFaviconURL;
@property (nonatomic) NSString *lastHost;
@property (nonatomic) id resizeObserver;
@property (nonatomic) BOOL navigationFailed;
@property (nonatomic) NSArray<NSNumber *> *lastNavigationState;
@end
@implementation TLWebKitBrowserSession
@end

@class TLWebKitDownloadTransfer;
@interface TLWebKitBrowserController () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSWindowDelegate>
@property (nonatomic) NSMutableDictionary<NSNumber *,TLWebKitBrowserSession *> *sessions;
@property (nonatomic) NSMapTable<NSWindow *,WKWebsiteDataStore *> *incognitoWindows;
@property (nonatomic) WKWebsiteDataStore *persistentStore;
@property (nonatomic) NSMutableSet<TLWebKitDownloadTransfer *> *transfers;
@property (nonatomic) NSTimer *stateTimer;
@property (nonatomic) BOOL initialized;
@property (nonatomic) BOOL darkAppearance;
@property (nonatomic) BOOL shuttingDown;
@property (nonatomic) BOOL preparing;
@property (nonatomic) NSError *preparationError;
@property (nonatomic) NSMutableArray *preparationCallbacks;
@property (nonatomic) NSMutableSet<NSAlert *> *alerts;
- (void)configureMenu:(NSMenu *)menu event:(NSEvent *)event session:(TLWebKitBrowserSession *)session;
- (void)recordTransfer:(TLWebKitDownloadTransfer *)transfer;
- (void)finishTransfer:(TLWebKitDownloadTransfer *)transfer;
- (void)registerDownload:(WKDownload *)download session:(TLWebKitBrowserSession *)session;
- (void)presentError:(NSError *)error window:(NSWindow *)window;
- (void)updateSession:(TLWebKitBrowserSession *)session;
- (void)openLink:(NSURL *)URL session:(TLWebKitBrowserSession *)session flags:(NSEventModifierFlags)flags destination:(TLBrowserLinkDestination)destination;
@end

@interface TLWebKitMessageHandler : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) TLWebKitBrowserController *controller;
@end
@implementation TLWebKitMessageHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.controller userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface TLWebKitMenuAction : NSObject
@property (nonatomic, copy) dispatch_block_t block;
- (void)invoke:(id)sender;
@end
@implementation TLWebKitMenuAction
- (void)invoke:(id)sender { if (self.block) self.block(); }
@end
static NSMenuItem *TLBrowserMenuItem(NSString *title, dispatch_block_t block) {
  NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(invoke:) keyEquivalent:@""];
  TLWebKitMenuAction *action=[TLWebKitMenuAction new];action.block=block;
  item.target=action;item.representedObject=action;return item;
}

@interface TLWebKitDownloadTransfer : NSObject <WKDownloadDelegate>
@property (nonatomic, weak) TLWebKitBrowserController *controller;
@property (nonatomic) TLWebKitBrowserSession *session;
@property (nonatomic) WKDownload *download;
@property (nonatomic) NSUInteger identifier;
@property (nonatomic) NSString *URLString;
@property (nonatomic) NSString *fileName;
@property (nonatomic) NSString *path;
@property (nonatomic) NSString *failureReason;
@property (nonatomic) NSData *resumeData;
@property (nonatomic, copy) NSURLRequest *restartRequest;
@property (nonatomic) BOOL restartOnResume, restarting;
@property (nonatomic) TLBrowserDownloadState state;
@property (nonatomic) NSProgress *progress;
@property (nonatomic) int64_t receivedBytes;
@property (nonatomic) int64_t totalBytes;
@property (nonatomic) int64_t lastBytes;
@property (nonatomic) NSTimeInterval lastTime;
@property (nonatomic) int64_t speed;
@property (nonatomic) BOOL cancelling;
@property (nonatomic) BOOL resumeAfterCancellation;
@property (nonatomic) BOOL resuming;
@property (nonatomic) BOOL awaitingDownload;
@property (nonatomic) NSUInteger operationGeneration;
@property (nonatomic) NSSavePanel *destinationPanel;
- (void)performAction:(TLBrowserDownloadAction)action;
- (void)publish;
@end
@implementation TLWebKitDownloadTransfer
- (void)publish {
  if (self.progress) { self.receivedBytes=self.progress.completedUnitCount;self.totalBytes=self.progress.totalUnitCount; }
  NSTimeInterval now=NSProcessInfo.processInfo.systemUptime, elapsed=now-self.lastTime;
  if (self.lastTime && elapsed>=0.2) { self.speed=MAX(0,(self.receivedBytes-self.lastBytes)/elapsed);self.lastBytes=self.receivedBytes;self.lastTime=now; }
  else if (!self.lastTime) { self.lastTime=now;self.lastBytes=self.receivedBytes; }
  [self.controller recordTransfer:self];
}
- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)filename completionHandler:(void (^)(NSURL *))completionHandler {
  self.fileName=filename.length ? filename : @"Download";
  self.totalBytes=response.expectedContentLength;
  self.progress=download.progress;
  if (self.resuming && self.path.length) { self.resuming=NO;completionHandler([NSURL fileURLWithPath:self.path]);return; }
  NSString *directory=[TLBrowserPreferences.sharedPreferences localValue:@"downloadDirectory"];
  if (!directory.isAbsolutePath) directory=[NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory,NSUserDomainMask,YES) firstObject];
  NSString *path=[TLBrowserDownloadManager.sharedManager reserveDestinationForDownloadID:self.identifier directory:directory fileName:self.fileName];
  void (^choose)(NSURL *)=^(NSURL *URL){
    self.destinationPanel=nil;
    if(self.state==TLBrowserDownloadStateCancelled || self.controller.shuttingDown || (self.session.closed && self.session.incognito))URL=nil;
    if (!URL) { self.state=TLBrowserDownloadStateCancelled;completionHandler(nil);[self publish];[self.controller finishTransfer:self];return; }
    self.path=URL.path;self.fileName=URL.lastPathComponent;completionHandler(URL);[self publish];
  };
  if(self.restarting && self.path.length) {
    self.restarting=NO;
    // The cancelled download may have left a partial file, or the user may have
    // replaced it while paused. Never remove that file to restart a request.
    [TLBrowserDownloadManager.sharedManager releaseDestinationForDownloadID:self.identifier];
    NSString *destination=[TLBrowserDownloadManager.sharedManager reserveDestinationForDownloadID:self.identifier directory:self.path.stringByDeletingLastPathComponent fileName:self.path.lastPathComponent];
    choose([NSURL fileURLWithPath:destination]);return;
  }
  self.restarting=NO;
  if (self.session.incognito || [[TLBrowserPreferences.sharedPreferences localValue:@"askDownload"] boolValue]) {
    NSSavePanel *panel=[NSSavePanel savePanel];panel.canCreateDirectories=YES;panel.nameFieldStringValue=self.fileName;
    self.destinationPanel=panel;
    panel.directoryURL=[NSURL fileURLWithPath:directory isDirectory:YES];
    void (^finished)(NSModalResponse)=^(NSModalResponse response){[panel orderOut:nil];choose(response==NSModalResponseOK ? panel.URL : nil);};
    NSWindow *window=self.session.originWindow;
    if(window.isVisible && !window.attachedSheet)[panel beginSheetModalForWindow:window completionHandler:finished];
    else [panel beginWithCompletionHandler:finished];
  } else choose([NSURL fileURLWithPath:path]);
}
- (void)download:(WKDownload *)download didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completionHandler {
  if(self.session.closed)completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);
  else [self.controller webView:self.session.webView didReceiveAuthenticationChallenge:challenge completionHandler:completionHandler];
}
- (void)downloadDidFinish:(WKDownload *)download {
  self.state=TLBrowserDownloadStateComplete;self.resumeData=nil;[self publish];[self.controller finishTransfer:self];
}
- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
  if (self.cancelling) return;
  self.resumeData=resumeData;self.state=TLBrowserDownloadStateFailed;self.failureReason=error.localizedDescription;
  [self publish];[self.controller finishTransfer:self];
}
- (void)performAction:(TLBrowserDownloadAction)action {
  if (action==TLBrowserDownloadActionResume) {
    if (self.state!=TLBrowserDownloadStatePaused) return;
    if(self.cancelling){self.resumeAfterCancellation=YES;return;}
    if(self.awaitingDownload){self.state=TLBrowserDownloadStateDownloading;[self publish];return;}
    BOOL restart=self.restartOnResume && self.restartRequest!=nil;
    if (!self.resumeData && !restart) { self.state=TLBrowserDownloadStateFailed;self.failureReason=@"This server cannot resume the download. Return to the website to start it again.";[self publish];[self.controller finishTransfer:self];return; }
    NSData *data=self.resumeData;self.resumeData=nil;self.state=TLBrowserDownloadStateDownloading;self.resuming=!restart;self.restarting=restart;self.restartOnResume=NO;self.awaitingDownload=YES;self.failureReason=@"";
    if(restart){self.progress=nil;self.receivedBytes=0;self.totalBytes=0;self.lastBytes=0;self.lastTime=0;self.speed=0;}
    NSUInteger generation=++self.operationGeneration;self.download.delegate=nil;self.download=nil;
    void (^received)(WKDownload *)=^(WKDownload *download){
      if(generation!=self.operationGeneration || self.state==TLBrowserDownloadStateCancelled || self.controller.shuttingDown || (self.session.closed && self.session.incognito)) {[download cancel:nil];return;}
      self.awaitingDownload=NO;self.download=download;download.delegate=self;self.progress=download.progress;
      if(self.state==TLBrowserDownloadStatePaused) {self.state=TLBrowserDownloadStateDownloading;[self performAction:TLBrowserDownloadActionPause];}
      else [self publish];
    };
    if(restart)[self.session.webView startDownloadUsingRequest:self.restartRequest completionHandler:received];
    else [self.session.webView resumeDownloadFromResumeData:data completionHandler:received];
    [self publish];return;
  }
  if (self.cancelling) {
    if(action==TLBrowserDownloadActionCancel){self.resumeAfterCancellation=NO;self.state=TLBrowserDownloadStateCancelled;[self publish];}
    return;
  }
  if(self.awaitingDownload) {
    self.state=action==TLBrowserDownloadActionPause ? TLBrowserDownloadStatePaused : TLBrowserDownloadStateCancelled;
    if(action==TLBrowserDownloadActionCancel){self.operationGeneration++;self.awaitingDownload=NO;[self.controller finishTransfer:self];}
    [self publish];return;
  }
  if(self.state==TLBrowserDownloadStatePaused) {self.state=TLBrowserDownloadStateCancelled;self.resumeData=nil;[self publish];[self.controller finishTransfer:self];return;}
  if(self.state!=TLBrowserDownloadStateDownloading)return;
  self.cancelling=YES;self.state=action==TLBrowserDownloadActionPause ? TLBrowserDownloadStatePaused : TLBrowserDownloadStateCancelled;
  WKDownload *download=self.download;
  if(self.destinationPanel) {
    NSSavePanel *panel=self.destinationPanel;
    if(panel.sheetParent)[panel.sheetParent endSheet:panel returnCode:NSModalResponseCancel];else [panel cancel:nil];
  }
  [download cancel:^(NSData *data){
    self.cancelling=NO;self.resumeData=data;
    if(self.state==TLBrowserDownloadStatePaused && !data) {
      if(self.restartRequest){self.restartOnResume=YES;self.failureReason=@"Resume restarts from the beginning";}
      else {self.state=TLBrowserDownloadStateFailed;self.failureReason=@"This server cannot resume the download. Return to the website to start it again.";}
    }
    BOOL paused=self.state==TLBrowserDownloadStatePaused;
    BOOL resume=paused && self.resumeAfterCancellation;self.resumeAfterCancellation=NO;
    // Settle the old download before notifying UI observers, which may request
    // Resume synchronously from the paused update.
    if(paused){
      if(self.progress){self.receivedBytes=self.progress.completedUnitCount;self.totalBytes=self.progress.totalUnitCount;}
      self.download.delegate=nil;self.download=nil;self.progress=nil;
      if(resume)[self performAction:TLBrowserDownloadActionResume];else [self publish];
    }else {[self publish];[self.controller finishTransfer:self];}
  }];
  [self publish];
}
@end

@implementation TLWebKitBrowserController
+ (instancetype)sharedController {static id controller;static dispatch_once_t once;dispatch_once(&once,^{controller=[self new];});return controller;}
- (instancetype)init {
  if((self=[super init])) {
    _sessions=[NSMutableDictionary dictionary];_incognitoWindows=[NSMapTable weakToStrongObjectsMapTable];
    _transfers=[NSMutableSet set];_preparationCallbacks=[NSMutableArray array];_alerts=[NSMutableSet set];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(browserPreferencesChanged:) name:TLBrowserPreferencesDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDeactivated:) name:NSApplicationWillResignActiveNotification object:nil];
  }return self;
}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[_stateTimer invalidate];}
- (BOOL)initializeRuntimeFromWindow:(NSWindow *)window {
  if(self.shuttingDown)return NO;if(self.initialized)return YES;
  NSError *error;NSURL *profile=TLBrowserPreferences.profileURL;
  if(![NSFileManager.defaultManager createDirectoryAtURL:profile withIntermediateDirectories:YES attributes:nil error:&error]){[self presentError:error window:window];return NO;}
  NSURL *defaultStoreRecord=[profile URLByAppendingPathComponent:@"WebKitDefaultDataStore"];
  BOOL useDefaultStore=[NSFileManager.defaultManager fileExistsAtPath:defaultStoreRecord.path];
  if(@available(macOS 14.0,*)) {} else useDefaultStore=YES;
  // Keep a macOS 13 profile in the same WebKit store after upgrading macOS.
  // Creating a new named store then would silently discard its signed-in state.
  if(useDefaultStore) {
    if(![NSFileManager.defaultManager fileExistsAtPath:defaultStoreRecord.path] &&
       ![@"default\n" writeToURL:defaultStoreRecord atomically:YES encoding:NSUTF8StringEncoding error:&error]){[self presentError:error window:window];return NO;}
    self.persistentStore=WKWebsiteDataStore.defaultDataStore;
  }else if(@available(macOS 14.0,*)) {
    NSURL *identityURL=[profile URLByAppendingPathComponent:@"WebKitStoreIdentifier"];
    BOOL hasIdentity=[NSFileManager.defaultManager fileExistsAtPath:identityURL.path];
    NSString *stored=hasIdentity ? [[NSString stringWithContentsOfURL:identityURL encoding:NSUTF8StringEncoding error:&error] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    NSUUID *identity=[[NSUUID alloc] initWithUUIDString:stored];
    if(hasIdentity && (!identity || [identity.UUIDString isEqual:@"00000000-0000-0000-0000-000000000000"])) {
      [self presentError:error ?: TLWebKitError(@"The browser profile’s data-store identifier is unreadable. Restore that file to reopen the existing profile.") window:window];return NO;
    }
    if(!identity){identity=NSUUID.UUID;if(![identity.UUIDString writeToURL:identityURL atomically:YES encoding:NSUTF8StringEncoding error:&error]){[self presentError:error window:window];return NO;}}
    self.persistentStore=[WKWebsiteDataStore dataStoreForIdentifier:identity];
  }
  if(![TLBrowserProfileImporter prepareMigrationFromLegacyProfileAtProfileURL:profile error:&error]){[self presentError:error window:window];return NO;}
  self.initialized=YES;self.preparing=YES;
  __weak typeof(self) weakSelf=self;
  self.stateTimer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer){[weakSelf pollBrowserState];}];
  NSArray *cookies=[TLBrowserProfileImporter pendingSessionCookiesAtProfileURL:profile error:&error];
  self.preparationError=error;
  if(!error){[TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:profile error:&error];self.preparationError=error;}
  [self importCookies:cookies ?: @[] completion:^(NSUInteger imported,NSUInteger failed){
    NSError *restoreError=self.preparationError;
    if(failed)restoreError=TLWebKitError(@"Some imported cookies could not be restored. Restart Talaria to retry.");
    else if(cookies.count)[TLBrowserProfileImporter clearPendingSessionCookiesAtProfileURL:profile error:&restoreError];
    self.preparationError=restoreError;self.preparing=NO;
    NSArray *callbacks=self.preparationCallbacks.copy;[self.preparationCallbacks removeAllObjects];
    for(void (^callback)(NSError *) in callbacks)callback(restoreError);
  }];return YES;
}
- (void)markWindowIncognito:(NSWindow *)window {if(window && ![self.incognitoWindows objectForKey:window])[self.incognitoWindows setObject:WKWebsiteDataStore.nonPersistentDataStore forKey:window];}
- (void)forgetIncognitoWindow:(NSWindow *)window {
  for(TLWebKitBrowserSession *session in self.sessions.allValues.copy)if(session.incognito && session.originWindow==window)[self closeSession:session];
  [self.incognitoWindows removeObjectForKey:window];
}
- (TLWebKitBrowserSession *)sessionForWebView:(WKWebView *)view {for(TLWebKitBrowserSession *session in self.sessions.allValues)if(session.webView==view)return session;return nil;}
- (WKWebsiteDataStore *)storeForWindow:(NSWindow *)window {
  WKWebsiteDataStore *privateStore=window ? [self.incognitoWindows objectForKey:window] : nil;
  if(privateStore)return privateStore;
  return self.persistentStore;
}
- (TLWebKitBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window titleHandler:(TLWebKitBrowserTitleHandler)titleHandler linkHandler:(TLWebKitBrowserLinkHandler)linkHandler URLHandler:(TLWebKitBrowserURLHandler)URLHandler faviconHandler:(TLWebKitBrowserFaviconHandler)faviconHandler navigationHandler:(TLWebKitBrowserNavigationHandler)navigationHandler {
  return [self createSessionWithURL:URL inView:view fromWindow:window titleHandler:titleHandler linkHandler:linkHandler URLHandler:URLHandler faviconHandler:faviconHandler navigationHandler:navigationHandler configuration:nil shouldLoad:YES];
}
// A supplied configuration belongs to WebKit's pending new browsing context;
// WebKit performs its navigation after the UI delegate returns the child view.
- (TLWebKitBrowserSession *)loadURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window titleHandler:(TLWebKitBrowserTitleHandler)titleHandler linkHandler:(TLWebKitBrowserLinkHandler)linkHandler URLHandler:(TLWebKitBrowserURLHandler)URLHandler faviconHandler:(TLWebKitBrowserFaviconHandler)faviconHandler navigationHandler:(TLWebKitBrowserNavigationHandler)navigationHandler configuration:(WKWebViewConfiguration *)configuration {
  if(!configuration)return [self loadURL:URL inView:view fromWindow:window titleHandler:titleHandler linkHandler:linkHandler URLHandler:URLHandler faviconHandler:faviconHandler navigationHandler:navigationHandler];
  return [self createSessionWithURL:URL inView:view fromWindow:window titleHandler:titleHandler linkHandler:linkHandler URLHandler:URLHandler faviconHandler:faviconHandler navigationHandler:navigationHandler configuration:configuration shouldLoad:NO];
}
- (TLWebKitBrowserSession *)createSessionWithURL:(NSURL *)URL inView:(NSView *)view fromWindow:(NSWindow *)window titleHandler:(TLWebKitBrowserTitleHandler)titleHandler linkHandler:(TLWebKitBrowserLinkHandler)linkHandler URLHandler:(TLWebKitBrowserURLHandler)URLHandler faviconHandler:(TLWebKitBrowserFaviconHandler)faviconHandler navigationHandler:(TLWebKitBrowserNavigationHandler)navigationHandler configuration:(WKWebViewConfiguration *)providedConfiguration shouldLoad:(BOOL)shouldLoad {
  if(!URL || !view || !TLBrowserURLSupported(URL) || ![self initializeRuntimeFromWindow:window ?: view.window])return nil;
  [self closeBrowserInView:view];
  static NSInteger nextIdentifier=1;
  TLWebKitBrowserSession *session=[TLWebKitBrowserSession new];session.containerView=view;session.originWindow=window ?: view.window;
  session.browserIdentifier=nextIdentifier++;session.initialURLString=URL.absoluteString;session.incognito=[self.incognitoWindows objectForKey:session.originWindow]!=nil;
  session.titleHandler=titleHandler;session.linkHandler=linkHandler;session.URLHandler=URLHandler;session.faviconHandler=faviconHandler;session.navigationHandler=navigationHandler;
  WKWebViewConfiguration *configuration=providedConfiguration ?: [WKWebViewConfiguration new];
  // Set before constructing any web view, including script-created windows, so
  // the first request, child frames and navigator all share the Safari identity.
  configuration.applicationNameForUserAgent=TLBrowserSafariApplicationName();
  if(!providedConfiguration)configuration.websiteDataStore=[self storeForWindow:session.originWindow];
  else configuration.userContentController=[WKUserContentController new];
  [TLWebKitBrowserSettings applyToConfiguration:configuration];
  configuration.preferences.elementFullscreenEnabled=YES;configuration.suppressesIncrementalRendering=NO;
  // WebKit's native contextual inspector action is not exposed by public API.
  @try {[configuration.preferences setValue:@YES forKey:@"developerExtrasEnabled"];} @catch(NSException *exception){}
  TLWebKitMessageHandler *handler=[TLWebKitMessageHandler new];handler.controller=self;
  [configuration.userContentController addScriptMessageHandler:handler contentWorld:TLBrowserUIWorld() name:@"talariaBrowser"];
  NSString *script=@"(() => { const post=m=>webkit.messageHandlers.talariaBrowser.postMessage(m);"
    "document.addEventListener('contextmenu',e=>{if(!e.isTrusted)return;let p=e.composedPath().filter(n=>n instanceof Element),n=p[0]||e.target;"
    "let a=p.find(n=>n.matches('a[href]')),i=p.find(n=>n.matches('img'));post({kind:'context',url:a?.href||'',image:i?.currentSrc||i?.src||'',hasImage:!!(i?.complete&&i?.naturalWidth>0),selection:String(getSelection()),editable:!!(n.isContentEditable||n.closest?.('input,textarea'))});},true);"
    "document.addEventListener('auxclick',e=>{if(!e.isTrusted||e.button!==1)return;let a=e.composedPath().find(n=>n instanceof Element&&n.matches('a[href]'));if(a){e.preventDefault();post({kind:'middle',url:a.href,meta:e.metaKey,shift:e.shiftKey});}},true);"
    "const icon=()=>post({kind:'favicon',url:document.querySelector('link[rel~=icon]')?.href || (location.protocol.startsWith('http')?new URL('/favicon.ico',location.href).href:'')});"
    "document.addEventListener('DOMContentLoaded',()=>{icon();if(document.head)new MutationObserver(icon).observe(document.head,{subtree:true,childList:true,attributes:true,attributeFilter:['href','rel']});});})();";
  [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO inContentWorld:TLBrowserUIWorld()]];
  if(!session.incognito)[self installPendingStorageInConfiguration:configuration];
  TLBrowserWebView *webView=[[TLBrowserWebView alloc] initWithFrame:view.bounds configuration:configuration];session.webView=webView;
  webView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;webView.navigationDelegate=self;webView.UIDelegate=self;
  // Observe the engine's visible-content milestone, independently of resource
  // loading and site JavaScript. Older engines still use the completion fallback.
  SEL observeRendering=NSSelectorFromString(@"_setObservedRenderingProgressEvents:");
  if([webView respondsToSelector:observeRendering])
    ((void (*)(id,SEL,NSUInteger))objc_msgSend)(webView,observeRendering,TLFirstVisuallyNonEmptyLayout);
  webView.allowsBackForwardNavigationGestures=YES;webView.allowsMagnification=YES;
  if(@available(macOS 13.3,*))webView.inspectable=YES;
  webView.appearance=[NSAppearance appearanceNamed:self.darkAppearance ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  [TLWebKitBrowserSettings applyToWebView:webView];
  __weak typeof(self) weakSelf=self;__weak TLWebKitBrowserSession *weakSession=session;
  webView.contextMenuHandler=^(NSMenu *menu,NSEvent *event){[weakSelf configureMenu:menu event:event session:weakSession];};
  webView.contextMenuClosedHandler=^{TLWebKitBrowserSession *s=weakSession;if(s.menuCleanup)s.menuCleanup();s.menuCleanup=nil;s.context=nil;s.contextFrame=nil;};
  session.pageBridge=[[TLWebKitPageBridge alloc] initWithWebView:webView];
  __weak TLWebKitBrowserSession *scrollSession=session;
  session.pageBridge.topColorChanged=^(NSArray *rgb){
    TLWebKitBrowserSession *owner=scrollSession;
    if(!owner.closed && owner.topColorChanged)owner.topColorChanged(rgb);
  };
  session.pageBridge.topScrollEnded=^{
    TLWebKitBrowserSession *owner=scrollSession;
    if(!owner.closed && owner.topScrollEnded)owner.topScrollEnded();
  };
  self.sessions[@(session.browserIdentifier)]=session;
  for(NSString *key in @[@"title",@"URL",@"canGoBack",@"canGoForward",@"loading",@"fullscreenState"])[webView addObserver:self forKeyPath:key options:0 context:NULL];
  view.postsFrameChangedNotifications=YES;
  session.resizeObserver=[NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:view queue:nil usingBlock:^(NSNotification *note){[weakSelf clearNavigationCover:weakSession];}];
  [view addSubview:webView];
  // Start the page process only after its view belongs to the window, so its
  // initial activity and visibility state reflect the actual native hierarchy.
  [session.pageBridge install];
  if(shouldLoad) { [self prepareBrowserSettingsInWindow:session.originWindow completion:^(NSError *error){
    if(session.closed)return;if(error){[self presentError:error window:session.originWindow];return;}
    [self loadURL:URL session:session];
  }]; }
  return session;
}
- (void)installPendingStorageInConfiguration:(WKWebViewConfiguration *)configuration {
  NSError *error;NSDictionary *pending=[TLBrowserProfileImporter pendingLocalStorageByOriginAtProfileURL:TLBrowserPreferences.profileURL error:&error];
  if(!pending.count)return;
  NSString *script=[NSString stringWithFormat:@"/* Talaria pending profile import */(()=>{const all=JSON.parse(%@), values=all[location.origin];if(!values)return;try{for(const [k,v] of Object.entries(values))localStorage.setItem(k,v);webkit.messageHandlers.talariaBrowser.postMessage({kind:'storageImported',origin:location.origin});}catch(e){}})();",TLBrowserJSON(TLBrowserJSON(pending))];
  [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO inContentWorld:TLBrowserUIWorld()]];
}
- (void)refreshPendingStorageScripts {
  for(TLWebKitBrowserSession *session in self.sessions.allValues) {
    if(session.incognito || session.closed)continue;
    WKUserContentController *content=session.webView.configuration.userContentController;
    // WebKit returns a live array wrapper. Snapshot it before clearing, or a
    // profile refresh also discards the browser UI and page-integration scripts.
    NSArray *scripts=[content.userScripts mutableCopy];[content removeAllUserScripts];
    for(WKUserScript *script in scripts)if(![script.source hasPrefix:@"/* Talaria pending profile import */"])[content addUserScript:script];
    [self installPendingStorageInConfiguration:session.webView.configuration];
  }
}
- (void)loadURL:(NSURL *)URL session:(TLWebKitBrowserSession *)session {
  if(session.closed)return;
  [(TLBrowserWebView *)session.webView cancelMouseWheelScrolling];
  if(URL.isFileURL)[session.webView loadFileURL:URL allowingReadAccessToURL:URL.URLByDeletingLastPathComponent];
  else [session.webView loadRequest:[TLWebKitBrowserSettings requestForURL:URL]];
}
- (void)openURL:(NSURL *)URL fromWindow:(NSWindow *)window {[self openURL:URL fromWindow:window modifierFlags:NSEvent.modifierFlags];}
- (void)openURL:(NSURL *)URL fromWindow:(NSWindow *)window modifierFlags:(NSEventModifierFlags)flags {
  if(!TLBrowserURLSupported(URL))return;
  if(flags & NSEventModifierFlagCommand){[NSWorkspace.sharedWorkspace openURL:URL];return;}
  if(window && [self.incognitoWindows objectForKey:window]) {
    if([NSApp.delegate respondsToSelector:@selector(openIncognitoURLInNewWindow:)])[(TLAppDelegate *)NSApp.delegate openIncognitoURLInNewWindow:URL];return;
  }
  TLThemePalette *palette=[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight];
  NSWindow *browserWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,palette.windowInitialWidth,palette.windowInitialHeight) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  browserWindow.releasedWhenClosed=NO;browserWindow.contentMinSize=NSMakeSize(palette.windowMinimumWidth,palette.windowMinimumHeight);browserWindow.title=URL.host ?: @"Talaria";browserWindow.delegate=self;
  TLWebKitBrowserSession *session=[self loadURL:URL inView:browserWindow.contentView fromWindow:browserWindow titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil];
  if(!session)return;session.standaloneWindow=browserWindow;
  [browserWindow center];[browserWindow makeKeyAndOrderFront:nil];[self focusSession:session];
}
- (void)openLink:(NSURL *)URL session:(TLWebKitBrowserSession *)session flags:(NSEventModifierFlags)flags destination:(TLBrowserLinkDestination)destination {
  if(!TLBrowserImageURLIsSupported(URL))return;
  if(destination!=TLBrowserLinkNewTab && session.contextLinkHandler){session.contextLinkHandler(URL,destination);return;}
  if(destination==TLBrowserLinkNewTab && session.linkHandler){session.linkHandler(URL,flags);return;}
  if(destination==TLBrowserLinkSplitView)return;
  [self openURL:URL fromWindow:session.originWindow modifierFlags:flags];
}
- (void)openImageURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session inNewWindow:(BOOL)newWindow {
  [self openLink:URL session:session flags:0 destination:newWindow ? TLBrowserLinkNewWindow : TLBrowserLinkNewTab];
}
- (void)navigateSession:(TLWebKitBrowserSession *)session toURL:(NSURL *)URL {
  if(!session || session.closed || !TLBrowserURLSupported(URL))return;
  [self resumeSession:session];[self beginNavigationCover:session];[self loadURL:URL session:session];
}
- (void)goBackInSession:(TLWebKitBrowserSession *)session {if(!session.closed && session.webView.canGoBack){[self resumeSession:session];[self beginNavigationCover:session];[session.webView goBack];}}
- (void)goForwardInSession:(TLWebKitBrowserSession *)session {if(!session.closed && session.webView.canGoForward){[self resumeSession:session];[self beginNavigationCover:session];[session.webView goForward];}}
- (void)reloadSession:(TLWebKitBrowserSession *)session {if(!session.closed){[self resumeSession:session];[self beginNavigationCover:session];[session.webView reload];}}
- (void)focusSession:(TLWebKitBrowserSession *)session {if(session.closed)return;[self resumeSession:session];[session.webView.window makeFirstResponder:session.webView];}
- (void)beginNavigationCover:(TLWebKitBrowserSession *)session {
  [(TLBrowserWebView *)session.webView cancelMouseWheelScrolling];
  if (@available(macOS 26.0, *)) {
    // WKSnapshot omits live content in obscured insets. Covering the web view
    // with that image introduces a blank footer as soon as navigation begins.
    // Keep the live view visible while WebKit loads the replacement document.
    if (session.webView.obscuredContentInsets.bottom > 0) {
      [self clearNavigationCover:session];
      return;
    }
  }
  if(!session.webView || session.fullscreen || !session.containerView.window.visible || session.containerView.hiddenOrHasHiddenAncestor)return;
  NSUInteger generation=++session.transitionGeneration;NSSize size=session.webView.bounds.size;
  if(size.width<=0 || size.height<=0 || size.width*size.height>16*1024*1024)return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(generation==session.transitionGeneration)[self clearNavigationCover:session];});
  if(session.navigationCover)return;
  WKSnapshotConfiguration *configuration=[WKSnapshotConfiguration new];configuration.afterScreenUpdates=NO;
  [session.webView takeSnapshotWithConfiguration:configuration completionHandler:^(NSImage *image,NSError *error){
    if(!image || session.closed || generation!=session.transitionGeneration || !NSEqualSizes(size,session.webView.bounds.size))return;
    NSImageView *cover=[[NSImageView alloc] initWithFrame:session.webView.frame];cover.image=image;cover.imageScaling=NSImageScaleAxesIndependently;[cover setAccessibilityHidden:YES];session.navigationCover=cover;
    [session.containerView addSubview:cover positioned:NSWindowAbove relativeTo:nil];
  }];
}
- (void)clearNavigationCover:(TLWebKitBrowserSession *)session {session.transitionGeneration++;[session.navigationCover removeFromSuperview];session.navigationCover=nil;}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  TLWebKitBrowserSession *session=[self sessionForWebView:object];if(!session)return;
  if([keyPath isEqual:@"fullscreenState"]) {
    BOOL fullscreen=session.webView.fullscreenState!=WKFullscreenStateNotInFullscreen;
    if(fullscreen!=session.fullscreen){session.fullscreen=fullscreen;[self clearNavigationCover:session];[session.pageBridge configureDocumentFooter:fullscreen ? @{@"enabled":@NO} : session.documentFooterConfiguration ?: @{@"enabled":@NO} completion:nil];}
  }
  if([keyPath isEqual:@"title"] && session.webView.title.length) {
    if(session.titleHandler)session.titleHandler(session.webView.title);else session.standaloneWindow.title=session.webView.title;
  }
  if([keyPath isEqual:@"URL"] && session.webView.URL) {
    [(TLBrowserWebView *)session.webView cancelMouseWheelScrolling];
    NSString *host=session.webView.URL.host ?: @"";
    if(![session.lastHost isEqual:host]){session.lastFaviconURL=nil;if(session.faviconHandler)session.faviconHandler(nil);}session.lastHost=host;
    if(session.URLHandler)session.URLHandler(session.webView.URL);
  }
  // Same-document Back/Forward completes loading without didFinishNavigation.
  // Fragment links can change only URL; history entries can share the same URL.
  if(([keyPath isEqual:@"loading"] || [keyPath isEqual:@"URL"]) && !session.webView.loading)
    [self revealNavigationInWebView:session.webView];
  [self updateSession:session];
}
- (void)updateSession:(TLWebKitBrowserSession *)session {
  if(!session || session.closed)return;
  NSArray *state=@[@(session.webView.canGoBack),@(session.webView.canGoForward),@(session.webView.loading)];
  if([state isEqual:session.lastNavigationState])return;session.lastNavigationState=state;
  if(session.navigationHandler)session.navigationHandler(session.webView.canGoBack,session.webView.canGoForward,session.webView.loading);
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
  [(TLBrowserWebView *)webView cancelMouseWheelScrolling];
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];if(!session)return;
  for(NSAlert *alert in self.alerts.copy)if(alert.window.sheetParent==session.originWindow)[session.originWindow endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
  session.awaitingNavigationCommit=YES;
  session.navigationFailed=NO;session.context=nil;session.contextFrame=nil;
  [session.pageBridge stopFinding];
  [self updateSession:session];
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];
  session.awaitingNavigationCommit=NO;
  session.documentGeneration++;[session.pageBridge resetForNavigation];session.documentFooterConfiguration=nil;
  if(session.documentStartedHandler)session.documentStartedHandler();
  [session.pageBridge install];
  [TLWebKitBrowserSettings applyToWebView:webView];[self updateSession:session];
}
- (void)_webView:(WKWebView *)webView renderingProgressDidChange:(NSUInteger)events {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];
  if((events & TLFirstVisuallyNonEmptyLayout) && session && !session.awaitingNavigationCommit)
    [self revealNavigationInWebView:webView];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];[session.pageBridge install];
  [self revealNavigationInWebView:webView];
  [self updateSession:session];
}
- (void)revealNavigationInWebView:(WKWebView *)webView {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];
  if(!session || session.closed)return;
  NSUInteger generation=session.transitionGeneration, document=session.documentGeneration;
  dispatch_block_t painted=^{
    if(!session.closed && generation==session.transitionGeneration && document==session.documentGeneration && !session.awaitingNavigationCommit)
      [self clearNavigationCover:session];
  };
  // Visible content can be ready while images and other resources still load.
  // Wait for its compositor presentation, not the load event. Blank pages and
  // same-document history also enter here through the completion fallback.
  SEL presented=NSSelectorFromString(@"_doAfterNextPresentationUpdate:");
  if([webView respondsToSelector:presented])((void (*)(id,SEL,dispatch_block_t))objc_msgSend)(webView,presented,painted);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),painted);
}
- (void)navigationFailedInWebView:(WKWebView *)webView error:(NSError *)error {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];session.awaitingNavigationCommit=NO;[self clearNavigationCover:session];[self updateSession:session];
  if(error.code==NSURLErrorCancelled || ([error.domain isEqual:@"WebKitErrorDomain"] && error.code==102))return;
  session.navigationFailed=YES;[self presentError:error window:session.originWindow];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self navigationFailedInWebView:webView error:error];}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {[self navigationFailedInWebView:webView error:error];}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];[self clearNavigationCover:session];
  [self presentError:TLWebKitError(@"The page stopped responding. Reload the tab to continue.") window:session.originWindow];[self updateSession:session];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action preferences:(WKWebpagePreferences *)preferences decisionHandler:(void (^)(WKNavigationActionPolicy,WKWebpagePreferences *))decisionHandler {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];NSURL *URL=action.request.URL;
  if(!session || session.closed){decisionHandler(WKNavigationActionPolicyCancel,preferences);return;}
  preferences.allowsContentJavaScript=[[TLBrowserPreferences.sharedPreferences localValue:@"javascript"] integerValue]!=2;
  if(@available(macOS 15.2,*))preferences.preferredHTTPSNavigationPolicy=[[TLBrowserPreferences.sharedPreferences localValue:@"httpsOnly"] boolValue] ? WKWebpagePreferencesUpgradeToHTTPSPolicyErrorOnFailure : WKWebpagePreferencesUpgradeToHTTPSPolicyKeepAsRequested;
  if(action.navigationType==WKNavigationTypeLinkActivated && (action.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagShift) || action.buttonNumber==2)) {
    [self openLink:URL session:session flags:action.modifierFlags destination:TLBrowserLinkNewTab];decisionHandler(WKNavigationActionPolicyCancel,preferences);return;
  }
  // Page-owned JavaScript links stay in WebKit's current origin and obey its
  // script policy; they must never be sent to a native application as a URL.
  if(![@[@"http",@"https",@"file",@"about",@"data",@"blob",@"javascript"] containsObject:URL.scheme.lowercaseString]) {
    if(action.navigationType==WKNavigationTypeLinkActivated && URL)[NSWorkspace.sharedWorkspace openURL:URL];
    decisionHandler(WKNavigationActionPolicyCancel,preferences);return;
  }
  if(action.shouldPerformDownload){decisionHandler(WKNavigationActionPolicyDownload,preferences);return;}
  if(action.targetFrame.isMainFrame && action.navigationType!=WKNavigationTypeOther)[self beginNavigationCover:session];
  decisionHandler(WKNavigationActionPolicyAllow,preferences);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
  BOOL download=!response.canShowMIMEType || ([[response.response.MIMEType lowercaseString] isEqual:@"application/pdf"] && [[TLBrowserPreferences.sharedPreferences localValue:@"pdfDownload"] boolValue]);
  decisionHandler(download ? WKNavigationResponsePolicyDownload : WKNavigationResponsePolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];NSURL *URL=action.request.URL;
  // window.open('') supplies an empty URL rather than nil. It still creates an
  // inherited about:blank document that scripts can populate through the opener.
  if(!URL.absoluteString.length)URL=[NSURL URLWithString:@"about:blank"];
  if(!session || session.closed)return nil;
  if(session.createTabHandler && TLBrowserURLSupported(URL))return session.createTabHandler(URL,configuration);
  if(action.navigationType==WKNavigationTypeLinkActivated) {[self openLink:URL session:session flags:action.modifierFlags destination:TLBrowserLinkNewTab];return nil;}
  if(!TLBrowserURLSupported(URL))return nil;
  TLThemePalette *palette=[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight];
  NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,palette.windowInitialWidth,palette.windowInitialHeight) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed=NO;window.contentMinSize=NSMakeSize(palette.windowMinimumWidth,palette.windowMinimumHeight);window.title=URL.host ?: @"Talaria";window.delegate=self;
  // A script popup belongs to its opener's storage session, including incognito.
  if(session.incognito)[self.incognitoWindows setObject:configuration.websiteDataStore forKey:window];
  TLWebKitBrowserSession *popup=[self createSessionWithURL:URL inView:window.contentView fromWindow:window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil configuration:configuration shouldLoad:NO];
  popup.standaloneWindow=window;[window center];[window makeKeyAndOrderFront:nil];return popup.webView;
}
- (void)webViewDidClose:(WKWebView *)webView {TLWebKitBrowserSession *session=[self sessionForWebView:webView];if(session.closeTabHandler)session.closeTabHandler();else if(session.standaloneWindow)[session.standaloneWindow performClose:nil];}
- (void)windowWillClose:(NSNotification *)notification {
  for(TLWebKitBrowserSession *session in self.sessions.allValues.copy)if(session.standaloneWindow==notification.object || session.originWindow==notification.object)[self closeSession:session];
  [self forgetIncognitoWindow:notification.object];
}
- (void)applicationDeactivated:(NSNotification *)notification {
  for(TLWebKitBrowserSession *session in self.sessions.allValues)if(session.fullscreen)[session.webView closeAllMediaPresentationsWithCompletionHandler:nil];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  TLWebKitBrowserSession *session=[self sessionForWebView:message.webView];
  if(!session || session.closed || ![message.body isKindOfClass:NSDictionary.class])return;
  NSDictionary *body=message.body;NSString *kind=body[@"kind"];
  if([kind isEqual:@"context"]) {session.context=body;session.contextFrame=message.frameInfo;}
  else if([kind isEqual:@"middle"] && [body[@"url"] isKindOfClass:NSString.class]) {
    NSEventModifierFlags flags=([body[@"meta"] boolValue]?NSEventModifierFlagCommand:0)|([body[@"shift"] boolValue]?NSEventModifierFlagShift:0);
    [self openLink:[NSURL URLWithString:body[@"url"]] session:session flags:flags destination:TLBrowserLinkNewTab];
  }else if([kind isEqual:@"favicon"] && message.frameInfo.isMainFrame && [body[@"url"] isKindOfClass:NSString.class]) {
    NSString *value=body[@"url"];if([session.lastFaviconURL isEqual:value])return;session.lastFaviconURL=value;
    if(!session.faviconHandler)return;
    NSURL *URL=[NSURL URLWithString:value];if(!TLBrowserImageURLIsSupported(URL)){session.faviconHandler(nil);return;}
    NSUInteger generation=session.documentGeneration;
    [self readImageAtURL:URL inSession:session frame:message.frameInfo completion:^(TLBrowserImageResource *resource,NSError *error){
      if(!session.closed && session.documentGeneration==generation && [session.lastFaviconURL isEqual:value] && session.faviconHandler)session.faviconHandler(resource.image);
    }];
  }else if([kind isEqual:@"storageImported"] && !session.incognito && [body[@"origin"] isKindOfClass:NSString.class]) {
    WKSecurityOrigin *origin=message.frameInfo.securityOrigin;
    BOOL defaultPort=([origin.protocol isEqual:@"http"] && origin.port==80) || ([origin.protocol isEqual:@"https"] && origin.port==443);
    NSString *host=origin.host;
    if([host containsString:@":"] && ![host hasPrefix:@"["])host=[NSString stringWithFormat:@"[%@]",host];
    NSString *actual=[NSString stringWithFormat:@"%@://%@%@",origin.protocol,host,origin.port>0 && !defaultPort ? [NSString stringWithFormat:@":%ld",(long)origin.port] : @""];
    if([actual isEqual:body[@"origin"]]) {
      NSError *error;[TLBrowserProfileImporter clearPendingLocalStorageForOrigin:actual profileURL:TLBrowserPreferences.profileURL error:&error];
      if(error)[self presentError:error window:session.originWindow];
      else [self refreshPendingStorageScripts];
    }
  }
}
- (NSMenu *)imageMenuForURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session frame:(WKFrameInfo *)frame hasImage:(BOOL)hasImage {
  NSMenu *menu=[NSMenu new];menu.autoenablesItems=NO;
  NSArray *titles=TLBrowserImageMenuTitles();
  for(NSUInteger index=0;index<titles.count;index++) {
    if(index==TLBrowserImageSaveDownloads || index==TLBrowserImageCopyAddress || index==TLBrowserImageShare)[menu addItem:NSMenuItem.separatorItem];
    TLBrowserImageAction action=(TLBrowserImageAction)index;
    NSMenuItem *item=TLBrowserMenuItem(titles[index],^{
      if(session.closed)return;
      if(action==TLBrowserImageOpenTab || action==TLBrowserImageOpenWindow){[self openImageURL:URL inSession:session inNewWindow:action==TLBrowserImageOpenWindow];return;}
      if(action==TLBrowserImageCopyAddress){[TLBrowserLinkActions copyURL:URL toPasteboard:NSPasteboard.generalPasteboard];return;}
      [self readImageAtURL:URL inSession:session frame:frame completion:^(TLBrowserImageResource *resource,NSError *error){
        if(session.closed)return;
        if(error)[self presentError:error window:session.originWindow];
        else [TLBrowserImageActions performAction:action resource:resource URL:URL fromView:session.webView atPoint:NSMakePoint(NSMidX(session.webView.bounds),NSMidY(session.webView.bounds))];
      }];
    });
    item.tag=index;item.enabled=TLBrowserImageURLIsSupported(URL);
    if(action==TLBrowserImageCopy || action==TLBrowserImageCopySubject || action==TLBrowserImageAddToPhotos || action==TLBrowserImageWallpaper || action==TLBrowserImageShare)item.enabled &= hasImage;
    if(action==TLBrowserImageCopySubject){if(@available(macOS 14.0,*)){}else item.enabled=NO;}
    if(action==TLBrowserImageLookUp)item.enabled=NO;
    [menu addItem:item];
  }return menu;
}
- (NSMenu *)pageMenuForSession:(TLWebKitBrowserSession *)session contextMenu:(NSMenu *)native point:(NSPoint)point {
  NSMenu *menu=[NSMenu new];menu.autoenablesItems=NO;
  for(NSMenuItem *item in native.itemArray) {
    NSString *title=item.title;
    if([@[@"Back",@"Forward",@"Reload",@"Reload Page",@"Stop",@"Inspect Element"] containsObject:title] || [item.identifier containsString:@"InspectElement"])continue;
    if(item.isSeparatorItem && (!menu.numberOfItems || menu.itemArray.lastObject.isSeparatorItem))continue;
    [menu addItem:[item copy]];
  }
  if(menu.numberOfItems && !menu.itemArray.lastObject.isSeparatorItem)[menu addItem:NSMenuItem.separatorItem];
  [menu addItem:TLBrowserMenuItem(@"Reload Page",^{[self reloadSession:session];})];[menu addItem:NSMenuItem.separatorItem];
  [menu addItem:TLBrowserMenuItem(@"Show Page Source",^{[self showPageSourceInSession:session];})];
  [menu addItem:TLBrowserMenuItem(@"Save Page As…",^{[self savePageInSession:session];})];[menu addItem:NSMenuItem.separatorItem];
  NSMenuItem *printItem=TLBrowserMenuItem(@"Print Page…",^{
    NSPrintOperation *operation=[session.webView printOperationWithPrintInfo:NSPrintInfo.sharedPrintInfo];operation.showsPrintPanel=YES;operation.showsProgressPanel=YES;
    if(session.originWindow)[operation runOperationModalForWindow:session.originWindow delegate:nil didRunSelector:NULL contextInfo:NULL];else [operation runOperation];
  });printItem.image=[NSImage imageWithSystemSymbolName:@"printer" accessibilityDescription:nil];
  [menu addItem:printItem];[menu addItem:NSMenuItem.separatorItem];
  [menu addItem:TLBrowserMenuItem(@"Inspect Element",^{[self inspectSession:session atPoint:point];})];return menu;
}
- (void)configureMenu:(NSMenu *)menu event:(NSEvent *)event session:(TLWebKitBrowserSession *)session {
  if(!session || session.closed)return;
  NSMenuItem *nativeInspector=nil;
  for(NSMenuItem *item in menu.itemArray) {
    if([item.identifier containsString:@"InspectElement"] || [item.title isEqual:@"Inspect Element"]) { nativeInspector=[item copy];break; }
  }
  objc_setAssociatedObject(session,@selector(inspectSession:atPoint:),nativeInspector,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  NSPoint point=[session.webView convertPoint:event.locationInWindow fromView:nil];
  // Native image analysis may delay WebKit's menu. Keep trusted hit-test data
  // until that menu consumes it instead of expiring it while WebKit prepares.
  NSDictionary *context=session.context;WKFrameInfo *contextFrame=session.contextFrame;
  session.context=nil;session.contextFrame=nil;
  NSURL *link=[context[@"url"] isKindOfClass:NSString.class] && [context[@"url"] length] ? [NSURL URLWithString:context[@"url"]] : nil;
  NSURL *imageURL=[context[@"image"] isKindOfClass:NSString.class] && [context[@"image"] length] ? [NSURL URLWithString:context[@"image"]] : nil;
  if([context[@"editable"] boolValue])return;
  NSMenu *replacement;
  NSMenu *images=imageURL ? [self imageMenuForURL:imageURL inSession:session frame:contextFrame hasImage:[context[@"hasImage"] boolValue]] : nil;
  if(TLBrowserLinkURLIsNavigable(link)) {
    replacement=[TLBrowserLinkActions menuForURL:link canSplit:session.contextLinkHandler!=nil view:session.webView point:point open:^(NSURL *URL,TLBrowserLinkDestination destination){
      if(session.contextLinkHandler)session.contextLinkHandler(URL,destination);else [self openLink:URL session:session flags:0 destination:destination];
    } inspect:^{[self inspectSession:session atPoint:point];} imageMenu:images];
    session.menuCleanup=[TLBrowserLinkActions prepareMenu:replacement forURL:link inView:session.webView];
  }else if(images) {
    replacement=images;[replacement addItem:NSMenuItem.separatorItem];[replacement addItem:TLBrowserMenuItem(@"Inspect Element",^{[self inspectSession:session atPoint:point];})];
  }else if([context[@"selection"] length])return;
  else replacement=[self pageMenuForSession:session contextMenu:menu point:point];
  [menu removeAllItems];menu.autoenablesItems=NO;
  for(NSMenuItem *item in replacement.itemArray){[replacement removeItem:item];[menu addItem:item];}
}
- (void)inspectSession:(TLWebKitBrowserSession *)session atPoint:(NSPoint)point {
  if(session.closed)return;
  session.inspectorNeedsDetach=YES;
  NSMenuItem *nativeInspector=objc_getAssociatedObject(session,@selector(inspectSession:atPoint:));
  objc_setAssociatedObject(session,@selector(inspectSession:atPoint:),nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if(nativeInspector.action && [NSApp sendAction:nativeInspector.action to:nativeInspector.target from:nativeInspector]) {
    [self pollBrowserState];return;
  }
  // Isolate the small compatibility surface absent from WKWebView's public API.
  id inspector=TLWebKitOptionalValue(session.webView,@"_inspector");
  if(!TLWebKitOptionalAction(inspector,@"show")) {
    [self presentError:TLWebKitError(@"Enable Safari’s Develop menu, then select this Talaria page under Inspect Apps and Devices.") window:session.originWindow];return;
  }
  [self pollBrowserState];
}
- (void)closeInspectorInSession:(TLWebKitBrowserSession *)session {TLWebKitOptionalAction(TLWebKitOptionalValue(session.webView,@"_inspector"),@"close");}
- (void)showPageSourceInSession:(TLWebKitBrowserSession *)session {
  if(session.closed)return;
  NSUInteger generation=session.documentGeneration;
  NSString *title=[@"Source: " stringByAppendingString:session.webView.URL.absoluteString ?: @""];
  [session.webView createWebArchiveDataWithCompletionHandler:^(NSData *data,NSError *error){
    if(session.closed || generation!=session.documentGeneration)return;
    NSDictionary *archive=data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&error] : nil;
    NSDictionary *main=archive[@"WebMainResource"];NSData *source=main[@"WebResourceData"];
    if(![source isKindOfClass:NSData.class]){[self presentError:error ?: TLWebKitError(@"The page source could not be read.") window:session.originWindow];return;}
    NSStringEncoding encoding=NSUTF8StringEncoding;
    NSString *charset=main[@"WebResourceTextEncodingName"];
    if([charset isKindOfClass:NSString.class]) {
      CFStringEncoding declared=CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)charset);
      if(declared!=kCFStringEncodingInvalidId)encoding=CFStringConvertEncodingToNSStringEncoding(declared);
    }
    NSString *text=[[NSString alloc] initWithData:source encoding:encoding] ?: [[NSString alloc] initWithData:source encoding:NSISOLatin1StringEncoding];
    [TLSourceWindowController showText:text ?: @"" title:title palette:[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight]];
  }];
}
- (NSSavePanel *)pageSavePanel {return [NSSavePanel savePanel];}
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion {
  NSSavePanel *panel=[self pageSavePanel];panel.title=@"Save Page As";panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"webarchive"] ?: UTTypeData];panel.nameFieldStringValue=[name stringByAppendingPathExtension:@"webarchive"];panel.canCreateDirectories=YES;
  void (^finished)(NSModalResponse)=^(NSModalResponse response){[panel orderOut:nil];completion(response==NSModalResponseOK ? panel.URL : nil);};
  if(window.isVisible && !window.attachedSheet)[panel beginSheetModalForWindow:window completionHandler:finished];else [panel beginWithCompletionHandler:finished];
}
- (void)savePageInSession:(TLWebKitBrowserSession *)session {
  if(!session || session.closed)return;
  NSUInteger generation=session.documentGeneration;
  NSString *name=session.webView.URL.host ?: @"Page";
  [session.webView createWebArchiveDataWithCompletionHandler:^(NSData *data,NSError *error){
    if(session.closed || generation!=session.documentGeneration)return;
    if(!data){[self presentError:error ?: TLWebKitError(@"This page could not be saved.") window:session.originWindow];return;}
    [self choosePageArchiveURL:name fromWindow:session.originWindow completion:^(NSURL *URL){
      if(!URL)return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *writeError;if(![data writeToURL:URL options:NSDataWritingAtomic error:&writeError])dispatch_async(dispatch_get_main_queue(),^{[self presentError:writeError window:session.originWindow];});});
    }];
  }];
}
- (void)readImageAtURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session frame:(WKFrameInfo *)frame completion:(void (^)(TLBrowserImageResource *,NSError *))completion {
  if(!TLBrowserImageURLIsSupported(URL) || session.closed){completion(nil,TLWebKitError(@"The image is no longer available."));return;}
  NSUInteger generation=session.documentGeneration;
  // A WebArchive exposes original resource bytes, preserving animated GIFs and SVG.
  [session.webView createWebArchiveDataWithCompletionHandler:^(NSData *data,NSError *error){
    if(session.closed || generation!=session.documentGeneration){completion(nil,TLWebKitError(@"The page changed before the image could be read."));return;}
    NSDictionary *archive=data.length && data.length<=256*1024*1024 ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    NSMutableArray *nodes=[NSMutableArray array];if([archive isKindOfClass:NSDictionary.class])[nodes addObject:archive];
    TLBrowserImageResource *resource=nil;
    NSUInteger visited=0;
    while(nodes.count && !resource && visited++<128) {
      NSDictionary *node=nodes.lastObject;[nodes removeLastObject];
      NSMutableArray *resources=[NSMutableArray arrayWithArray:node[@"WebSubresources"] ?: @[]];
      if(node[@"WebMainResource"])[resources addObject:node[@"WebMainResource"]];
      for(NSDictionary *item in resources)if([item[@"WebResourceURL"] isEqual:URL.absoluteString] && [item[@"WebResourceData"] isKindOfClass:NSData.class] && [item[@"WebResourceData"] length]<=128*1024*1024) {
        resource=[TLBrowserImageResource resourceWithData:item[@"WebResourceData"] URL:URL MIMEType:item[@"WebResourceMIMEType"] ?: @""];if(resource)break;
      }
      [nodes addObjectsFromArray:node[@"WebSubframeArchives"] ?: @[]];
    }
    if(resource){completion(resource,nil);return;}
    NSString *body=@"const r=await fetch(url,{credentials:'include'});if(!r.ok)throw Error('Image request failed');if(Number(r.headers.get('content-length'))>134217728)throw Error('Image too large');const chunks=[];let size=0;const stream=r.body.getReader();while(true){const part=await stream.read();if(part.done)break;size+=part.value.byteLength;if(size>134217728){stream.cancel();throw Error('Image too large')}chunks.push(part.value)}const b=new Blob(chunks,{type:r.headers.get('content-type')||''});return await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve({url:reader.result,mime:b.type});reader.onerror=reject;reader.readAsDataURL(b)});";
    [session.webView callAsyncJavaScript:body arguments:@{@"url":URL.absoluteString} inFrame:frame inContentWorld:TLBrowserUIWorld() completionHandler:^(id result,NSError *fetchError){
      if(session.closed || generation!=session.documentGeneration){completion(nil,TLWebKitError(@"The page changed before the image could be read."));return;}
      NSString *encoded=[result isKindOfClass:NSDictionary.class] ? result[@"url"] : nil;
      NSRange comma=[encoded rangeOfString:@","];
      if(encoded && comma.location!=NSNotFound) {
        NSData *bytes=[[NSData alloc] initWithBase64EncodedString:[encoded substringFromIndex:comma.location+1] options:0];
        TLBrowserImageResource *fetched=[TLBrowserImageResource resourceWithData:bytes URL:URL MIMEType:result[@"mime"] ?: @""];
        if(fetched){completion(fetched,nil);return;}
      }
      // Cross-origin fetch can be disallowed while the original <img> is valid.
      // Use an ephemeral URL session with this web view's cookie store only.
      if(![@[@"http",@"https"] containsObject:URL.scheme.lowercaseString]){completion(nil,fetchError ?: TLWebKitError(@"This image could not be read."));return;}
      [session.webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
        [TLWebKitImageLoader loadURL:URL cookies:cookies completion:^(NSData *bytes,NSString *MIMEType,NSError *networkError){
          if(session.closed || generation!=session.documentGeneration){completion(nil,TLWebKitError(@"The page changed before the image could be read."));return;}
          TLBrowserImageResource *fetched=bytes.length ? [TLBrowserImageResource resourceWithData:bytes URL:URL MIMEType:MIMEType ?: @""] : nil;
          completion(fetched,fetched ? nil : networkError ?: TLWebKitError(@"This image could not be read."));
        }];
      }];
    }];
  }];
}
- (void)findText:(NSString *)text inSession:(TLWebKitBrowserSession *)session forward:(BOOL)forward findNext:(BOOL)findNext {
  if(session.closed)return;
  NSUInteger generation=session.documentGeneration;
  [session.pageBridge findText:text forward:forward findNext:findNext completion:^(NSInteger count,NSInteger active,BOOL final){if(!session.closed && generation==session.documentGeneration && session.findResultsChangedHandler)session.findResultsChangedHandler(count,active,final);}];
}
- (void)stopFindingInSession:(TLWebKitBrowserSession *)session {[session.pageBridge stopFinding];}
- (void)readPageInSession:(TLWebKitBrowserSession *)session expectedURL:(NSURL *)URL completion:(void (^)(NSDictionary *,NSError *))completion {
  if(!session || session.closed){completion(nil,TLWebKitError(@"The browser page is no longer open."));return;}
  [session.pageBridge readPageExpectedURL:URL completion:completion];
}
- (void)probeOverlayInSession:(TLWebKitBrowserSession *)session overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick completion:(void (^)(NSDictionary *))completion {
  if(!session || session.closed){completion(@{@"status":@"unknown",@"reason":@"closed"});return;}
  [session.pageBridge probeOverlayRect:rect viewportSize:viewport quick:quick completion:completion];
}
- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(TLWebKitBrowserSession *)session completion:(void (^)(BOOL))completion {
  if(!session || session.closed){if(completion)completion(NO);return;}
  session.documentFooterConfiguration=configuration;[session.pageBridge configureDocumentFooter:session.fullscreen ? @{@"enabled":@NO} : configuration completion:completion];
}
- (void)sampleFooterColorInSession:(TLWebKitBrowserSession *)session allowCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {
  if(!session || session.closed){completion(@{});return;}[session.pageBridge sampleFooterColorAllowingCapture:capture completion:completion];
}
- (void)prepareBrowserSettingsInWindow:(NSWindow *)window completion:(void (^)(NSError *))completion {
  if(![self initializeRuntimeFromWindow:window]){completion(TLWebKitError(@"The built-in browser could not start."));return;}
  if(self.preparing)[self.preparationCallbacks addObject:[completion copy]];else completion(self.preparationError);
}
- (NSDictionary *)browserSettingState:(NSDictionary *)setting {return [TLWebKitBrowserSettings stateForSetting:setting];}
- (BOOL)setBrowserSetting:(NSDictionary *)setting value:(id)value error:(NSError **)error {return [TLWebKitBrowserSettings setValue:value forSetting:setting error:error];}
- (void)browserPreferencesChanged:(NSNotification *)notification {
  for(TLWebKitBrowserSession *session in self.sessions.allValues)if(!session.closed)[TLWebKitBrowserSettings applyToWebView:session.webView];
  [self pollBrowserState];
}
- (void)applyDarkAppearance:(BOOL)dark {
  self.darkAppearance=dark;[TLSourceWindowController applyPaletteToOpenWindows:[TLThemePalette paletteForPreference:dark ? TLThemePreferenceDark : TLThemePreferenceLight]];for(TLWebKitBrowserSession *session in self.sessions.allValues)session.webView.appearance=[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  TLThemePalette *palette=[TLThemePalette paletteForPreference:dark ? TLThemePreferenceDark : TLThemePreferenceLight];
  for(NSAlert *alert in self.alerts)TLStyleBrowserPrompt(alert,palette);
}
- (void)importCookies:(NSArray<NSDictionary *> *)cookies completion:(void (^)(NSUInteger,NSUInteger))completion {
  if(!self.persistentStore || self.shuttingDown){completion(0,cookies.count);return;}
  dispatch_group_t group=dispatch_group_create();__block NSUInteger failed=0;
  for(NSDictionary *entry in cookies) {
    NSString *domain=entry[@"domain"],*name=entry[@"name"],*value=entry[@"value"],*path=entry[@"path"];
    if(!domain.length || !name.length || ![value isKindOfClass:NSString.class]){failed++;continue;}
    NSMutableDictionary *properties=[@{NSHTTPCookieDomain:domain,NSHTTPCookieName:name,NSHTTPCookieValue:value,NSHTTPCookiePath:path.length ? path : @"/"} mutableCopy];
    if([entry[@"secure"] boolValue])properties[NSHTTPCookieSecure]=@"TRUE";
    if([entry[@"httpOnly"] boolValue])properties[@"HttpOnly"]=@"TRUE";
    if([entry[@"persistent"] boolValue])properties[NSHTTPCookieExpires]=[NSDate dateWithTimeIntervalSince1970:[entry[@"expires"] doubleValue]];
    NSInteger sameSite=[entry[@"sameSite"] integerValue];if(sameSite==1)properties[NSHTTPCookieSameSitePolicy]=NSHTTPCookieSameSiteLax;else if(sameSite==2)properties[NSHTTPCookieSameSitePolicy]=NSHTTPCookieSameSiteStrict;else if(sameSite==0)properties[NSHTTPCookieSameSitePolicy]=@"None";
    NSHTTPCookie *cookie=[NSHTTPCookie cookieWithProperties:properties];if(!cookie){failed++;continue;}
    dispatch_group_enter(group);[self.persistentStore.httpCookieStore setCookie:cookie completionHandler:^{dispatch_group_leave(group);}];
  }
  dispatch_group_notify(group,dispatch_get_main_queue(),^{[self refreshPendingStorageScripts];completion(cookies.count-failed,failed);});
}
- (void)clearBrowserData:(NSString *)kind completion:(void (^)(NSError *))completion {
  if(!self.persistentStore){completion(TLWebKitError(@"The browser is not ready."));return;}
  NSSet *types;
  if([kind isEqual:@"cache"])types=[NSSet setWithArray:@[WKWebsiteDataTypeDiskCache,WKWebsiteDataTypeMemoryCache,WKWebsiteDataTypeOfflineWebApplicationCache,WKWebsiteDataTypeFetchCache]];
  else if([kind isEqual:@"cookies"]) {
    NSError *error;
    if(![TLBrowserProfileImporter clearPendingSessionCookiesAtProfileURL:TLBrowserPreferences.profileURL error:&error]){completion(error);return;}
    types=[NSSet setWithObject:WKWebsiteDataTypeCookies];
  }else {completion(TLWebKitError(@"Unknown browsing data category."));return;}
  dispatch_group_t group=dispatch_group_create();
  for(WKWebsiteDataStore *store in @[self.persistentStore]) {dispatch_group_enter(group);[store removeDataOfTypes:types modifiedSince:NSDate.distantPast completionHandler:^{dispatch_group_leave(group);}];}
  dispatch_group_notify(group,dispatch_get_main_queue(),^{completion(nil);});
}
- (void)resumeSession:(TLWebKitBrowserSession *)session {
  if(!session.paused)return;session.paused=NO;session.backgroundSince=nil;
  if(@available(macOS 14.0,*))session.webView.configuration.preferences.inactiveSchedulingPolicy=WKInactiveSchedulingPolicyNone;
  if(session.containerView && !session.closed){session.webView.frame=session.containerView.bounds;[session.containerView addSubview:session.webView positioned:NSWindowBelow relativeTo:nil];}
  [session.webView setAllMediaPlaybackSuspended:NO completionHandler:nil];
}
- (void)checkBackgroundBrowsers {[self pollBrowserState];}
- (void)pollBrowserState {
  if(self.shuttingDown)return;
  for(TLWebKitBrowserSession *session in self.sessions.allValues.copy) {
    if(session.closed)continue;
    id inspector=TLWebKitOptionalValue(session.webView,@"_inspector");
    BOOL visible=[TLWebKitOptionalValue(inspector,@"visible") boolValue] || [TLWebKitOptionalValue(session.webView,@"_isBeingInspected") boolValue];
    // WebKit initially docks its inspector inside the page. Wait until the
    // frontend is visible, then give it the separate window used by Talaria.
    if(session.inspectorNeedsDetach && [TLWebKitOptionalValue(inspector,@"visible") boolValue]) {
      TLWebKitOptionalAction(inspector,@"detach");session.inspectorNeedsDetach=NO;
    }
    if(visible!=session.devToolsVisible){session.devToolsVisible=visible;if(session.devToolsVisibilityChangedHandler)session.devToolsVisibilityChangedHandler();}
    NSView *container=session.containerView;
    BOOL hidden=container && (!container.window.visible || container.hiddenOrHasHiddenAncestor);
    if(hidden && !session.backgroundSince)session.backgroundSince=NSDate.date;
    if(!hidden)session.backgroundSince=nil;
    BOOL pause=[[TLBrowserPreferences.sharedPreferences localValue:@"pauseBackground"] boolValue] && hidden && !session.webView.loading && !session.fullscreen && !visible && -session.backgroundSince.timeIntervalSinceNow >= [[TLBrowserPreferences.sharedPreferences localValue:@"pauseDelay"] doubleValue];
    if(!pause)[self resumeSession:session];
    else if(!session.paused) {
      if(@available(macOS 14.0,*)) {
        session.paused=YES;[session.webView setAllMediaPlaybackSuspended:YES completionHandler:nil];
        session.webView.configuration.preferences.inactiveSchedulingPolicy=WKInactiveSchedulingPolicySuspend;[session.webView removeFromSuperview];
      }
    }
  }
  for(TLWebKitDownloadTransfer *transfer in self.transfers.copy)[transfer publish];
}
- (void)registerDownload:(WKDownload *)download session:(TLWebKitBrowserSession *)session {
  if(!session || session.closed || self.shuttingDown){[download cancel:nil];return;}
  static NSUInteger nextIdentifier=1;
  TLWebKitDownloadTransfer *transfer=[TLWebKitDownloadTransfer new];transfer.controller=self;transfer.session=session;transfer.download=download;transfer.identifier=nextIdentifier++;
  NSURLRequest *request=download.originalRequest;
  NSString *method=request.HTTPMethod ?: @"GET";
  if([@[@"http",@"https"] containsObject:request.URL.scheme.lowercaseString] && [method.uppercaseString isEqual:@"GET"] && !request.HTTPBody.length && !request.HTTPBodyStream)transfer.restartRequest=request;
  transfer.URLString=download.originalRequest.URL.absoluteString ?: session.webView.URL.absoluteString ?: @"";transfer.state=TLBrowserDownloadStateDownloading;transfer.fileName=@"Download";transfer.path=@"";transfer.failureReason=@"";
  download.delegate=transfer;transfer.progress=download.progress;[self.transfers addObject:transfer];[transfer publish];
}
- (void)recordTransfer:(TLWebKitDownloadTransfer *)transfer {
  if(transfer.session.incognito)return;
  __weak TLWebKitDownloadTransfer *weakTransfer=transfer;
  TLBrowserDownloadControl control=(transfer.state==TLBrowserDownloadStateDownloading || transfer.state==TLBrowserDownloadStatePaused) ? ^(TLBrowserDownloadAction action){[weakTransfer performAction:action];} : nil;
  [TLBrowserDownloadManager.sharedManager updateDownloadWithID:transfer.identifier browserIdentifier:transfer.session.browserIdentifier URLString:transfer.URLString fileName:transfer.fileName ?: @"Download" path:transfer.path ?: @"" receivedBytes:transfer.receivedBytes totalBytes:transfer.totalBytes bytesPerSecond:transfer.speed state:transfer.state failureReason:transfer.failureReason ?: @"" control:control];
}
- (void)finishTransfer:(TLWebKitDownloadTransfer *)transfer {
  [TLBrowserDownloadManager.sharedManager releaseDestinationForDownloadID:transfer.identifier];
  TLWebKitBrowserSession *session=transfer.session;transfer.download.delegate=nil;transfer.download=nil;[self.transfers removeObject:transfer];
  BOOL active=NO;for(TLWebKitDownloadTransfer *other in self.transfers)if(other.session==session)active=YES;
  if(!active && (session.closed || session.downloadOnly)){[self destroySession:session];}
}
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)action didBecomeDownload:(WKDownload *)download {[self registerDownload:download session:[self sessionForWebView:webView]];}
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)response didBecomeDownload:(WKDownload *)download {[self registerDownload:download session:[self sessionForWebView:webView]];}
- (void)startDownloadURL:(NSURL *)URL fromWindow:(NSWindow *)window {
  if(!TLBrowserImageURLIsSupported(URL) || ![self initializeRuntimeFromWindow:window])return;
  NSView *container=[[NSView alloc] initWithFrame:NSMakeRect(0,0,1,1)];
  TLWebKitBrowserSession *session=[self createSessionWithURL:[NSURL URLWithString:@"about:blank"] inView:container fromWindow:window titleHandler:nil linkHandler:nil URLHandler:nil faviconHandler:nil navigationHandler:nil configuration:nil shouldLoad:NO];
  if(!session)return;session.downloadOnly=YES;
  [self prepareBrowserSettingsInWindow:window completion:^(NSError *error){
    if(session.closed || self.shuttingDown)return;
    if(error){[self presentError:error window:window];[self closeSession:session];return;}
    [session.webView startDownloadUsingRequest:[TLWebKitBrowserSettings requestForURL:URL] completionHandler:^(WKDownload *download){[self registerDownload:download session:session];}];
  }];
}
- (void)presentError:(NSError *)error window:(NSWindow *)window {
  if(!error || self.shuttingDown)return;
  if(window.isVisible && !window.attachedSheet)[NSApp presentError:error modalForWindow:window delegate:nil didPresentSelector:NULL contextInfo:NULL];
  else [NSApp presentError:error];
}
- (void)presentPrompt:(NSAlert *)alert session:(TLWebKitBrowserSession *)session completion:(void (^)(NSModalResponse))completion {
  NSWindow *window=session.originWindow;
  if(session.closed || !window.isVisible || window.attachedSheet){completion(NSAlertFirstButtonReturn);return;}
  TLStyleBrowserPrompt(alert,[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight]);
  NSUInteger generation=session.documentGeneration;[self.alerts addObject:alert];
  [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse result){
    [self.alerts removeObject:alert];[alert.window orderOut:nil];
    completion(session.closed || generation!=session.documentGeneration ? NSAlertFirstButtonReturn : result);
  }];
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
  NSAlert *alert=[NSAlert new];alert.messageText=frame.securityOrigin.host ?: @"Website";alert.informativeText=message ?: @"";[alert addButtonWithTitle:@"OK"];
  [self presentPrompt:alert session:[self sessionForWebView:webView] completion:^(NSModalResponse response){completionHandler();}];
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
  NSAlert *alert=[NSAlert new];alert.messageText=frame.securityOrigin.host ?: @"Website";alert.informativeText=message ?: @"";[alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:@"OK"];
  [self presentPrompt:alert session:[self sessionForWebView:webView] completion:^(NSModalResponse response){completionHandler(response==NSAlertSecondButtonReturn);}];
}
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completionHandler {
  NSAlert *alert=[NSAlert new];alert.messageText=frame.securityOrigin.host ?: @"Website";alert.informativeText=prompt ?: @"";[alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:@"OK"];
  TLThemePalette *palette=[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight];
  NSTextField *input=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,palette.browserPromptWidth,palette.fieldHeight)];input.stringValue=defaultText ?: @"";alert.accessoryView=input;
  [self presentPrompt:alert session:[self sessionForWebView:webView] completion:^(NSModalResponse response){completionHandler(response==NSAlertSecondButtonReturn ? input.stringValue : nil);}];
}
- (void)webView:(WKWebView *)webView runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSArray<NSURL *> *))completionHandler {
  TLWebKitBrowserSession *session=[self sessionForWebView:webView];
  NSWindow *window=session.originWindow;if(session.closed || !window.isVisible || window.attachedSheet){completionHandler(nil);return;}
  NSOpenPanel *panel=[NSOpenPanel openPanel];panel.allowsMultipleSelection=parameters.allowsMultipleSelection;panel.canChooseDirectories=parameters.allowsDirectories;panel.canChooseFiles=YES;
  NSUInteger generation=session.documentGeneration;
  [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response){[panel orderOut:nil];completionHandler(!session.closed && session.documentGeneration==generation && response==NSModalResponseOK ? panel.URLs : nil);}];
}
- (void)requestPermission:(NSArray<NSString *> *)identifiers origin:(WKSecurityOrigin *)origin session:(TLWebKitBrowserSession *)session decision:(void (^)(WKPermissionDecision))decision {
  for(NSString *identifier in identifiers)if([[TLBrowserPreferences.sharedPreferences localValue:identifier] integerValue]==2){decision(WKPermissionDecisionDeny);return;}
  NSMutableArray *names=[NSMutableArray array];for(NSString *identifier in identifiers)[names addObject:[TLBrowserPreferences settingWithID:identifier][@"title"] ?: identifier];
  NSAlert *alert=[NSAlert new];alert.messageText=[NSString stringWithFormat:@"Allow %@?",[names componentsJoinedByString:@", "]];
  alert.informativeText=[NSString stringWithFormat:@"%@ is requesting access in Talaria.",origin.host ?: @"This website"];
  [alert addButtonWithTitle:@"Block"];[alert addButtonWithTitle:@"Allow"];
  [self presentPrompt:alert session:session completion:^(NSModalResponse response){decision(response==NSAlertSecondButtonReturn ? WKPermissionDecisionGrant : WKPermissionDecisionDeny);}];
}
- (void)webView:(WKWebView *)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
  NSArray *permissions=type==WKMediaCaptureTypeCamera ? @[@"media_stream_camera"] : type==WKMediaCaptureTypeMicrophone ? @[@"media_stream_mic"] : @[@"media_stream_camera",@"media_stream_mic"];
  [self requestPermission:permissions origin:origin session:[self sessionForWebView:webView] decision:decisionHandler];
}
- (void)webView:(WKWebView *)webView requestGeolocationPermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
  [self requestPermission:@[@"geolocation"] origin:origin session:[self sessionForWebView:webView] decision:decisionHandler];
}
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition,NSURLCredential *))completionHandler {
  NSString *method=challenge.protectionSpace.authenticationMethod;
  if(![@[NSURLAuthenticationMethodHTTPBasic,NSURLAuthenticationMethodHTTPDigest,NSURLAuthenticationMethodDefault] containsObject:method]){completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);return;}
  if(challenge.previousFailureCount==0 && challenge.proposedCredential){completionHandler(NSURLSessionAuthChallengeUseCredential,challenge.proposedCredential);return;}
  NSAlert *alert=[NSAlert new];alert.messageText=@"Sign in to website";alert.informativeText=challenge.protectionSpace.host ?: @"";[alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:@"Sign In"];
  TLThemePalette *palette=[TLThemePalette paletteForPreference:self.darkAppearance ? TLThemePreferenceDark : TLThemePreferenceLight];
  CGFloat height=palette.fieldHeight, width=palette.browserPromptWidth, gap=palette.space4;
  NSView *fields=[[NSView alloc] initWithFrame:NSMakeRect(0,0,width,height*2+gap)];
  NSTextField *username=[[NSTextField alloc] initWithFrame:NSMakeRect(0,height+gap,width,height)];username.placeholderString=@"Username";
  NSSecureTextField *password=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,width,height)];password.placeholderString=@"Password";
  [fields addSubview:username];[fields addSubview:password];alert.accessoryView=fields;
  [self presentPrompt:alert session:[self sessionForWebView:webView] completion:^(NSModalResponse result){
    if(result==NSAlertSecondButtonReturn)completionHandler(NSURLSessionAuthChallengeUseCredential,[NSURLCredential credentialWithUser:username.stringValue password:password.stringValue persistence:NSURLCredentialPersistenceForSession]);
    else completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil);
  }];
}
- (void)closeSession:(TLWebKitBrowserSession *)session {
  if(!session || session.closed)return;
  // Invalidate first: stopping the bridge drains callbacks synchronously, and
  // none of those callbacks may revive this page or enter close a second time.
  session.closed=YES;session.fullscreen=NO;
  WKWebView *webView=session.webView;
  NSNumber *renderer=TLWebKitOptionalValue(webView,@"_webProcessIdentifier");
  __block BOOL mediaSuspended=NO;
  [(TLBrowserWebView *)webView cancelMouseWheelScrolling];
  [webView setAllMediaPlaybackSuspended:YES completionHandler:^{mediaSuspended=YES;}];
  [self closeInspectorInSession:session];[webView closeAllMediaPresentationsWithCompletionHandler:nil];
  [self clearNavigationCover:session];[session.pageBridge stop];
  if(session.menuCleanup)session.menuCleanup();session.menuCleanup=nil;
  for(NSAlert *alert in self.alerts.copy)if(alert.window.sheetParent==session.originWindow)[session.originWindow endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
  for(NSString *key in @[@"title",@"URL",@"canGoBack",@"canGoForward",@"loading",@"fullscreenState"])[session.webView removeObserver:self forKeyPath:key];
  if(session.resizeObserver)[NSNotificationCenter.defaultCenter removeObserver:session.resizeObserver];session.resizeObserver=nil;
  session.titleHandler=nil;session.linkHandler=nil;session.URLHandler=nil;session.faviconHandler=nil;session.navigationHandler=nil;session.contextLinkHandler=nil;session.createTabHandler=nil;session.closeTabHandler=nil;session.findResultsChangedHandler=nil;session.documentStartedHandler=nil;session.topScrollEnded=nil;session.topColorChanged=nil;
  session.devToolsVisible=NO;if(session.devToolsVisibilityChangedHandler)session.devToolsVisibilityChangedHandler();session.devToolsVisibilityChangedHandler=nil;
  webView.navigationDelegate=nil;webView.UIDelegate=nil;
  [webView.configuration.userContentController removeAllScriptMessageHandlers];
  ((TLBrowserWebView *)webView).contextMenuHandler=nil;
  ((TLBrowserWebView *)webView).contextMenuClosedHandler=nil;
  [webView stopLoading];[webView removeFromSuperview];session.containerView=nil;
  session.pageBridge=nil;
  // Removing a WKWebView does not close its page. Pending WebKit callbacks and
  // downloads can retain the object indefinitely, including its audio engine.
  // Close the native page now without waiting for page JavaScript or dealloc.
  // WKDownload uses the network process; its resume APIs remain usable on the
  // retained object after the browsing page is closed.
  BOOL pageClosed=TLWebKitOptionalAction(webView,@"_close");
  // A blocked renderer cannot handle WebKit's asynchronous Close message. Give
  // it time to drain normally, then terminate only an exclusively owned process.
  if(pageClosed)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
    if(mediaSuspended || renderer.intValue<=0)return;
    for(TLWebKitBrowserSession *other in self.sessions.allValues) {
      if(other.closed)continue;
      if([renderer isEqual:TLWebKitOptionalValue(other.webView,@"_webProcessIdentifier")] ||
         [renderer isEqual:TLWebKitOptionalValue(other.webView,@"_provisionalWebProcessIdentifier")])return;
    }
    TLWebKitOptionalAction(webView,@"_killWebContentProcessAndResetState");
  });

  BOOL active=NO;for(TLWebKitDownloadTransfer *transfer in self.transfers.copy)if(transfer.session==session){active=YES;if(session.incognito || self.shuttingDown)[transfer performAction:TLBrowserDownloadActionCancel];}
  if(!active)[self destroySession:session];
}
- (void)destroySession:(TLWebKitBrowserSession *)session {
  if(!session.closed){[self closeSession:session];return;}
  session.webView.navigationDelegate=nil;session.webView.UIDelegate=nil;
  [session.webView.configuration.userContentController removeAllScriptMessageHandlers];
  session.webView=nil;session.pageBridge=nil;session.standaloneWindow.delegate=nil;[session.standaloneWindow orderOut:nil];[session.standaloneWindow close];session.standaloneWindow=nil;
  [self.sessions removeObjectForKey:@(session.browserIdentifier)];[TLBrowserDownloadManager.sharedManager browserClosed:session.browserIdentifier];
}
- (void)closeBrowserInView:(NSView *)view {for(TLWebKitBrowserSession *session in self.sessions.allValues.copy)if(session.containerView==view)[self closeSession:session];}
- (BOOL)prepareForApplicationTermination {[self shutdown];return YES;}
- (void)shutdown {
  if(self.shuttingDown)return;self.shuttingDown=YES;[self.stateTimer invalidate];self.stateTimer=nil;
  for(TLWebKitDownloadTransfer *transfer in self.transfers.copy)[transfer performAction:TLBrowserDownloadActionCancel];
  for(TLWebKitBrowserSession *session in self.sessions.allValues.copy)[self closeSession:session];
  [TLBrowserDownloadManager.sharedManager finishSession];[self.incognitoWindows removeAllObjects];
}
@end
