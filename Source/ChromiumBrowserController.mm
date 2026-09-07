#import "ChromiumBrowserController.h"
#import "ChromiumRunLoop.h"
#import "ChromiumOverlayProbe.h"
#import "ChromiumDocumentFooter.h"
#import "BrowserPageContext.h"

#include <algorithm>
#include <limits.h>
#include <stdint.h>

#include <string>
#include <utility>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_display_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_keyboard_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_task.h"
#include "include/cef_values.h"
#include "include/internal/cef_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

static int TLChromiumMainArgc = 0;
static char **TLChromiumMainArgv = nullptr;
static const int64_t TLChromiumMessagePumpPlaceholderDelayMS = INT_MAX;
static const int64_t TLChromiumMessagePumpMaxDelayMS = 1000 / 30;

void TLChromiumBrowserControllerConfigureMainArgs(int argc, char * _Nonnull * _Nonnull argv) {
  TLChromiumMainArgc = argc;
  TLChromiumMainArgv = argv;
}

static std::string TLStringFromNSString(NSString *value) {
  return value.length > 0 ? std::string(value.UTF8String) : std::string();
}

static NSString *TLNSStringFromCefString(const CefString &value) {
  std::string stringValue(value);
  return [NSString stringWithUTF8String:stringValue.c_str()] ?: @"";
}

static NSValue *TLChromiumContainerKey(NSView *view) {
  return view ? [NSValue valueWithNonretainedObject:view] : nil;
}

static NSEventModifierFlags TLChromiumCurrentModifierFlags(void) {
  NSEventModifierFlags flags = NSApp.currentEvent ? NSApp.currentEvent.modifierFlags : 0;
  NSEventModifierFlags linkModifierFlags = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagShift | NSEventModifierFlagOption;
  if ((flags & linkModifierFlags) == 0) {
    flags = [NSEvent modifierFlags];
  }
  return flags;
}

static BOOL TLChromiumModifierFlagsIncludeCommand(NSEventModifierFlags flags) {
  return (flags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand;
}

static BOOL TLChromiumModifierFlagsRequestNewTab(NSEventModifierFlags flags) {
  return (flags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand ||
         (flags & NSEventModifierFlagControl) == NSEventModifierFlagControl;
}

static BOOL TLChromiumDispositionRequestsNewTab(cef_window_open_disposition_t disposition) {
  switch (disposition) {
    case CEF_WOD_NEW_FOREGROUND_TAB:
    case CEF_WOD_NEW_BACKGROUND_TAB:
    case CEF_WOD_NEW_POPUP:
    case CEF_WOD_NEW_WINDOW:
    case CEF_WOD_OFF_THE_RECORD:
#if CEF_API_ADDED(14800)
    case CEF_WOD_NEW_SPLIT_VIEW:
#endif
      return YES;
    default:
      return NO;
  }
}

@interface TLChromiumBrowserSession ()
@property (nonatomic, weak, readwrite, nullable) NSView *containerView;
@property (nonatomic, copy, readwrite) NSString *initialURLString;
@property (nonatomic, readwrite) NSInteger browserIdentifier;
@property (nonatomic, readwrite) NSUInteger documentGeneration;
@property (nonatomic, readwrite, getter=isFullscreen) BOOL fullscreen;
@property (nonatomic) NSUInteger overlayCursor;
@property (nonatomic, copy) NSDictionary *overlayHint;
@property (nonatomic) NSTimeInterval overlayFallbackAfter;
@property (nonatomic, strong) TLChromiumDocumentFooter *documentFooter;
@property (nonatomic, copy) NSDictionary *documentFooterConfiguration;
- (instancetype)initWithContainerView:(NSView *)containerView initialURLString:(NSString *)initialURLString;
@end

@implementation TLChromiumBrowserSession

- (instancetype)initWithContainerView:(NSView *)containerView initialURLString:(NSString *)initialURLString {
  self = [super init];
  if (self) {
    _containerView = containerView;
    _initialURLString = [initialURLString copy] ?: @"";
    _browserIdentifier = -1;
  }
  return self;
}

@end

@interface TLChromiumBrowserController ()
- (BOOL)initializeCEFIfNeededFromWindow:(nullable NSWindow *)window;
- (void)scheduleMessagePumpWork:(int64_t)delayMS;
- (void)handleScheduledMessagePumpWork:(int64_t)delayMS;
- (void)performMessagePumpWork;
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(nullable NSView *)parentView;
- (void)browserClosed:(CefRefPtr<CefBrowser>)browser;
- (void)browserFullscreenChanged:(CefRefPtr<CefBrowser>)browser fullscreen:(BOOL)fullscreen;
- (void)restoreFullscreenBrowser;
- (void)exitBrowserFullscreen;
- (void)browserTitleChanged:(CefRefPtr<CefBrowser>)browser title:(NSString *)title;
- (void)browserFaviconURLChanged:(CefRefPtr<CefBrowser>)browser URLString:(NSString *)URLString;
- (void)browserFaviconDownloadedForIdentifier:(NSInteger)browserIdentifier
                                    URLString:(NSString *)URLString
                                        image:(nullable NSImage *)image;
- (void)browserURLChanged:(CefRefPtr<CefBrowser>)browser URL:(NSURL *)URL;
- (void)browserDocumentStarted:(CefRefPtr<CefBrowser>)browser;
- (void)installDocumentFooterInSession:(TLChromiumBrowserSession *)session browser:(CefRefPtr<CefBrowser>)browser;
- (void)browserNavigationStateChanged:(CefRefPtr<CefBrowser>)browser
                           canGoBack:(BOOL)canGoBack
                        canGoForward:(BOOL)canGoForward
                           isLoading:(BOOL)isLoading;
- (void)navigateBrowserWithIdentifier:(NSInteger)browserIdentifier toURLString:(NSString *)URLString;
- (void)goBackInBrowserWithIdentifier:(NSInteger)browserIdentifier;
- (void)goForwardInBrowserWithIdentifier:(NSInteger)browserIdentifier;
- (void)reloadBrowserWithIdentifier:(NSInteger)browserIdentifier;
- (void)createBrowserWithURLString:(NSString *)urlString parentView:(nullable NSView *)parentView;
- (void)openBrowserURLString:(NSString *)urlString;
- (void)openExternalURLString:(NSString *)urlString;
- (BOOL)handleBrowserLinkURLString:(NSString *)urlString fromBrowser:(CefRefPtr<CefBrowser>)browser userGesture:(BOOL)userGesture;
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (nullable NSWindow *)windowForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)attachBrowserViewForBrowser:(CefRefPtr<CefBrowser>)browser toContainerView:(NSView *)containerView;
- (void)presentCEFError:(NSString *)message fromWindow:(nullable NSWindow *)window;
- (void)createOrFocusExtensionWindow;
- (void)extensionBrowserCreated:(CefRefPtr<CefBrowser>)browser;
@end

// A short-lived DevTools observer owns one extraction, independent of navigation/UI handlers.
class TLChromiumPageReader : public CefDevToolsMessageObserver {
 public:
  TLChromiumPageReader(NSString *script, void (^completion)(NSDictionary *, NSError *))
      : script_([script copy]), completion_([completion copy]) {}

  void Start(CefRefPtr<CefBrowser> browser) {
    browser_ = browser;
    registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    Send("Page.getFrameTree", CefDictionaryValue::Create());
    CefRefPtr<TLChromiumPageReader> keepAlive = this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      keepAlive->Finish(nil, @"Reading this page timed out. Please try again.");
    });
  }

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser, int message_id,
                             bool success, const void *result, size_t result_size) override {
    if (!completion_ || message_id != messageID_) return;
    CefRefPtr<TLChromiumPageReader> keepAlive = this;
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:result_size] options:0 error:nil];
    if (!success || ![value isKindOfClass:NSDictionary.class]) {
      Finish(nil, @"Could not read this page. Please try again."); return;
    }
    if (stage_ == 0) {
      NSString *frameID = value[@"frameTree"][@"frame"][@"id"];
      if (!frameID.length) { Finish(nil, @"The browser page is not ready."); return; }
      stage_ = 1;
      auto params = CefDictionaryValue::Create();
      params->SetString("frameId", TLStringFromNSString(frameID));
      params->SetString("worldName", "talaria-readability");
      Send("Page.createIsolatedWorld", params);
    } else if (stage_ == 1) {
      NSNumber *contextID = value[@"executionContextId"];
      if (!contextID) { Finish(nil, @"Could not create a page reader."); return; }
      stage_ = 2;
      auto params = CefDictionaryValue::Create();
      params->SetInt("contextId", contextID.intValue);
      params->SetString("expression", TLStringFromNSString(script_));
      params->SetBool("returnByValue", true);
      params->SetDouble("timeout", 4000);
      Send("Runtime.evaluate", params);
    } else {
      NSDictionary *page = value[@"result"][@"value"];
      if (value[@"exceptionDetails"] || ![page isKindOfClass:NSDictionary.class]) {
        Finish(nil, @"Page text could not be extracted, or the page changed. Please try again.");
      } else { Finish(page, nil); }
    }
  }

  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser> browser) override {
    CefRefPtr<TLChromiumPageReader> keepAlive = this;
    Finish(nil, @"The browser page was closed. Please try again.");
  }

 private:
  void Send(const char *method, CefRefPtr<CefDictionaryValue> params) {
    messageID_ = browser_->GetHost()->ExecuteDevToolsMethod(0, method, params);
    if (!messageID_) Finish(nil, @"The browser page is no longer available.");
  }
  void Finish(NSDictionary *page, NSString *error) {
    if (!completion_) return;
    auto completion = completion_;
    completion_ = nil;
    registration_ = nullptr;
    browser_ = nullptr;
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(page, error ? [NSError errorWithDomain:@"Talaria.PageReader" code:1 userInfo:@{NSLocalizedDescriptionKey:error}] : nil);
    });
  }
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  int messageID_ = 0;
  int stage_ = 0;
  NSString *__strong script_;
  void (^__strong completion_)(NSDictionary *, NSError *);
  IMPLEMENT_REFCOUNTING(TLChromiumPageReader);
};

class TLChromiumFaviconDownloadCallback : public CefDownloadImageCallback {
 public:
  TLChromiumFaviconDownloadCallback(TLChromiumBrowserController *controller,
                                    NSInteger browserIdentifier,
                                    std::string URLString)
      : controller_(controller),
        browserIdentifier_(browserIdentifier),
        URLString_(std::move(URLString)) {}

  void OnDownloadImageFinished(const CefString &image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    CEF_REQUIRE_UI_THREAD();
    NSImage *nativeImage = nil;
    if (image && !image->IsEmpty() && http_status_code >= 200 && http_status_code < 400) {
      int pixelWidth = 0;
      int pixelHeight = 0;
      CefRefPtr<CefBinaryValue> PNGData = image->GetAsPNG(1.0, true, pixelWidth, pixelHeight);
      if (PNGData && PNGData->GetSize() > 0) {
        NSMutableData *data = [NSMutableData dataWithLength:PNGData->GetSize()];
        if (PNGData->GetData(data.mutableBytes, data.length, 0) == data.length) {
          nativeImage = [[NSImage alloc] initWithData:data];
        }
      }
    }

    [controller_ browserFaviconDownloadedForIdentifier:browserIdentifier_
                                             URLString:[NSString stringWithUTF8String:URLString_.c_str()] ?: @""
                                                 image:nativeImage];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;
  NSInteger browserIdentifier_;
  std::string URLString_;

  IMPLEMENT_REFCOUNTING(TLChromiumFaviconDownloadCallback);
};

class TLChromiumApp : public CefApp, public CefBrowserProcessHandler {
 public:
  explicit TLChromiumApp(TLChromiumBrowserController *controller)
      : controller_(controller) {}

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeCommandLineProcessing(const CefString &process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    command_line->AppendSwitch("use-mock-keychain");
  }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    [controller_ scheduleMessagePumpWork:delay_ms];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;

  IMPLEMENT_REFCOUNTING(TLChromiumApp);
};

class TLChromiumClient : public CefClient,
                         public CefDisplayHandler,
                         public CefKeyboardHandler,
                         public CefLifeSpanHandler,
                         public CefLoadHandler,
                         public CefRequestHandler {
 public:
  explicit TLChromiumClient(TLChromiumBrowserController *browserController,
                            NSView *parentView = nil)
      : browserController_(browserController),
        parentView_(parentView) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }

  void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserFullscreenChanged:browser fullscreen:fullscreen];
  }

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent &event,
                    CefEventHandle os_event, bool *is_keyboard_shortcut) override {
    CEF_REQUIRE_UI_THREAD();
    if ((event.type == KEYEVENT_RAWKEYDOWN || event.type == KEYEVENT_KEYDOWN) &&
        event.windows_key_code == 27 && browser->GetHost()->IsFullscreen()) {
      browser->GetHost()->ExitFullscreen(true);
      return true;
    }
    return false;
  }

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserNavigationStateChanged:browser
                                           canGoBack:canGoBack
                                        canGoForward:canGoForward
                                           isLoading:isLoading];
  }

  void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
    CEF_REQUIRE_UI_THREAD();
    if (frame && frame->IsMain()) [browserController_ browserDocumentStarted:browser];
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserTitleChanged:browser title:TLNSStringFromCefString(title)];
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString> &icon_urls) override {
    CEF_REQUIRE_UI_THREAD();
    NSString *URLString = @"";
    for (const CefString &iconURL : icon_urls) {
      NSString *candidate = TLNSStringFromCefString(iconURL);
      if (URLString.length == 0) {
        URLString = candidate;
      }
      NSURL *URL = [NSURL URLWithString:candidate];
      if ([URL.path.pathExtension.lowercaseString isEqualToString:@"png"] ||
          [candidate.lowercaseString hasPrefix:@"data:image/png;"]) {
        URLString = candidate;
        break;
      }
    }
    [browserController_ browserFaviconURLChanged:browser URLString:URLString];
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString &url) override {
    CEF_REQUIRE_UI_THREAD();
    if (!frame || !frame->IsMain()) {
      return;
    }
    NSURL *address = [NSURL URLWithString:TLNSStringFromCefString(url)];
    if (address) {
      [browserController_ browserURLChanged:browser URL:address];
    }
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString &target_url,
                     const CefString &target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures &popupFeatures,
                     CefWindowInfo &windowInfo,
                     CefRefPtr<CefClient> &client,
                     CefBrowserSettings &settings,
                     CefRefPtr<CefDictionaryValue> &extra_info,
                     bool *no_javascript_access) override {
    CEF_REQUIRE_UI_THREAD();
    NSString *urlString = TLNSStringFromCefString(target_url);
    if (urlString.length > 0) {
      return [browserController_ handleBrowserLinkURLString:urlString fromBrowser:browser userGesture:user_gesture];
    }
    return false;
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserCreated:browser parentView:parentView_];
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    if (!parentView_) {
      return false;
    }
    // Embedded browsers must tear down their own view. Closing the app window
    // only hides it, leaving CEF waiting forever for OnBeforeClose.
    TLChromiumDeferToMainRunLoop(^{
      @autoreleasepool {
        if (!browser->IsValid()) { return; }
        NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
        [browserView removeFromSuperview];
      }
    });
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserClosed:browser];
  }

  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const CefString &target_url,
                        WindowOpenDisposition target_disposition,
                        bool user_gesture) override {
    CEF_REQUIRE_UI_THREAD();
    NSString *urlString = TLNSStringFromCefString(target_url);
    if (!user_gesture || urlString.length == 0) {
      return false;
    }

    NSEventModifierFlags modifierFlags = TLChromiumCurrentModifierFlags();
    if (!TLChromiumDispositionRequestsNewTab(target_disposition) &&
        !TLChromiumModifierFlagsRequestNewTab(modifierFlags)) {
      return false;
    }

    return [browserController_ handleBrowserLinkURLString:urlString fromBrowser:browser userGesture:user_gesture];
  }

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool user_gesture,
                      bool is_redirect) override {
    CEF_REQUIRE_UI_THREAD();
    if (frame && frame->IsMain() && request &&
        [browserController_ openExtensionURL:[NSURL URLWithString:TLNSStringFromCefString(request->GetURL())]
                                 fromWindow:nil]) {
      return true;
    }
    if (!user_gesture || is_redirect || !frame || !frame->IsMain() || !request) {
      return false;
    }

    cef_transition_type_t transition = request->GetTransitionType();
    if ((transition & TT_SOURCE_MASK) != TT_LINK || (transition & TT_FORWARD_BACK_FLAG) == TT_FORWARD_BACK_FLAG) {
      return false;
    }

    NSString *urlString = TLNSStringFromCefString(request->GetURL());
    if (urlString.length == 0) {
      return false;
    }

    if (!TLChromiumModifierFlagsRequestNewTab(TLChromiumCurrentModifierFlags())) {
      return false;
    }

    return [browserController_ handleBrowserLinkURLString:urlString fromBrowser:browser userGesture:user_gesture];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *browserController_;
  __unsafe_unretained NSView *parentView_;

  IMPLEMENT_REFCOUNTING(TLChromiumClient);
};

// Keep Chromium's installer, permission prompts, extension manager, and popup
// handling intact. This client never applies the embedded tab's link interception
// or native-view teardown to a Chrome-style utility window.
class TLChromiumExtensionClient : public CefClient, public CefLifeSpanHandler {
 public:
  explicit TLChromiumExtensionClient(TLChromiumBrowserController *controller)
      : controller_(controller) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    [controller_ extensionBrowserCreated:browser];
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    [controller_ browserClosed:browser];
  }
 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;
  IMPLEMENT_REFCOUNTING(TLChromiumExtensionClient);
};

class TLChromiumCreateBrowserTask : public CefTask {
 public:
  TLChromiumCreateBrowserTask(TLChromiumBrowserController *controller,
                              std::string url,
                              NSView *parentView)
      : controller_(controller),
        url_(std::move(url)),
        parentView_(parentView) {}

  void Execute() override {
    CEF_REQUIRE_UI_THREAD();
    [controller_ createBrowserWithURLString:[NSString stringWithUTF8String:url_.c_str()]
                                 parentView:parentView_];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;
  std::string url_;
  __unsafe_unretained NSView *parentView_;

  IMPLEMENT_REFCOUNTING(TLChromiumCreateBrowserTask);
};

class TLChromiumNavigateBrowserTask : public CefTask {
 public:
  TLChromiumNavigateBrowserTask(TLChromiumBrowserController *controller,
                                NSInteger browserIdentifier,
                                std::string url)
      : controller_(controller),
        browserIdentifier_(browserIdentifier),
        url_(std::move(url)) {}

  void Execute() override {
    CEF_REQUIRE_UI_THREAD();
    [controller_ navigateBrowserWithIdentifier:browserIdentifier_
                                   toURLString:[NSString stringWithUTF8String:url_.c_str()]];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;
  NSInteger browserIdentifier_;
  std::string url_;

  IMPLEMENT_REFCOUNTING(TLChromiumNavigateBrowserTask);
};

enum class TLChromiumNavigationCommand {
  GoBack,
  GoForward,
  Reload,
};

class TLChromiumNavigationCommandTask : public CefTask {
 public:
  TLChromiumNavigationCommandTask(TLChromiumBrowserController *controller,
                                  NSInteger browserIdentifier,
                                  TLChromiumNavigationCommand command)
      : controller_(controller),
        browserIdentifier_(browserIdentifier),
        command_(command) {}

  void Execute() override {
    CEF_REQUIRE_UI_THREAD();
    switch (command_) {
      case TLChromiumNavigationCommand::GoBack:
        [controller_ goBackInBrowserWithIdentifier:browserIdentifier_];
        break;
      case TLChromiumNavigationCommand::GoForward:
        [controller_ goForwardInBrowserWithIdentifier:browserIdentifier_];
        break;
      case TLChromiumNavigationCommand::Reload:
        [controller_ reloadBrowserWithIdentifier:browserIdentifier_];
        break;
    }
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;
  NSInteger browserIdentifier_;
  TLChromiumNavigationCommand command_;

  IMPLEMENT_REFCOUNTING(TLChromiumNavigationCommandTask);
};

@implementation TLChromiumBrowserController {
  CefScopedLibraryLoader *_libraryLoader;
  CefRefPtr<TLChromiumApp> _cefApp;
  std::vector<CefRefPtr<CefBrowser>> _browsers;
  NSMutableDictionary<NSValue *, NSNumber *> *_browserIdentifiersByContainer;
  NSMutableDictionary<NSNumber *, NSValue *> *_containersByBrowserIdentifier;
  NSMutableDictionary<NSValue *, TLChromiumBrowserSession *> *_sessionsByContainer;
  NSMutableDictionary<NSNumber *, TLChromiumBrowserSession *> *_sessionsByBrowserIdentifier;
  NSMutableDictionary<NSValue *, TLChromiumBrowserTitleHandler> *_titleHandlersByContainer;
  NSMutableDictionary<NSValue *, TLChromiumBrowserLinkHandler> *_linkHandlersByContainer;
  NSMutableDictionary<NSValue *, TLChromiumBrowserURLHandler> *_URLHandlersByContainer;
  NSMutableDictionary<NSValue *, TLChromiumBrowserFaviconHandler> *_faviconHandlersByContainer;
  NSMutableDictionary<NSValue *, TLChromiumBrowserNavigationHandler> *_navigationHandlersByContainer;
  NSMutableDictionary<NSNumber *, NSString *> *_pendingFaviconURLsByBrowserIdentifier;
  NSMutableDictionary<NSNumber *, NSString *> *_hostsByBrowserIdentifier;
  NSView *_fullscreenView;
  NSInteger _fullscreenBrowserIdentifier;
  __weak NSWindow *_fullscreenOriginWindow;
  id _fullscreenCloseObserver;
  id _fullscreenDeactivateObserver;
  NSTimer *_messagePumpTimer;
  BOOL _initialized;
  BOOL _shuttingDown;
  BOOL _shutdownRequested;
  BOOL _doingMessagePumpWork;
  BOOL _messagePumpReentrancyDetected;
  BOOL _terminating;
  BOOL _terminationReplyPending;
  NSInteger _extensionBrowserIdentifier;
  BOOL _extensionWindowOpening;
  NSString *_pendingExtensionURLString;
}

+ (instancetype)sharedController {
  static TLChromiumBrowserController *controller = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    controller = [[TLChromiumBrowserController alloc] init];
  });
  return controller;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _extensionBrowserIdentifier = -1;
    _fullscreenBrowserIdentifier = -1;
    _browserIdentifiersByContainer = [NSMutableDictionary dictionary];
    _containersByBrowserIdentifier = [NSMutableDictionary dictionary];
    _sessionsByContainer = [NSMutableDictionary dictionary];
    _sessionsByBrowserIdentifier = [NSMutableDictionary dictionary];
    _titleHandlersByContainer = [NSMutableDictionary dictionary];
    _linkHandlersByContainer = [NSMutableDictionary dictionary];
    _URLHandlersByContainer = [NSMutableDictionary dictionary];
    _faviconHandlersByContainer = [NSMutableDictionary dictionary];
    _navigationHandlersByContainer = [NSMutableDictionary dictionary];
    _pendingFaviconURLsByBrowserIdentifier = [NSMutableDictionary dictionary];
    _hostsByBrowserIdentifier = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)openURL:(NSURL *)url fromWindow:(NSWindow *)window {
  [self openURL:url fromWindow:window modifierFlags:TLChromiumCurrentModifierFlags()];
}

+ (BOOL)isExtensionURL:(NSURL *)URL {
  if (URL.user.length || URL.password.length || URL.port) return NO;
  NSString *scheme = URL.scheme.lowercaseString;
  NSString *host = URL.host.lowercaseString;
  if ([scheme isEqualToString:@"chrome"]) return [host isEqualToString:@"extensions"];
  if (![scheme isEqualToString:@"https"]) return NO;
  return [host isEqualToString:@"chromewebstore.google.com"] ||
    ([host isEqualToString:@"chrome.google.com"] &&
      ([URL.path isEqualToString:@"/webstore"] || [URL.path hasPrefix:@"/webstore/"]));
}

- (void)showExtensionsFromWindow:(NSWindow *)window {
  [self openExtensionURL:[NSURL URLWithString:@"chrome://extensions/"] fromWindow:window];
}

- (void)showChromeWebStoreFromWindow:(NSWindow *)window {
  [self openExtensionURL:[NSURL URLWithString:@"https://chromewebstore.google.com/category/extensions"] fromWindow:window];
}

- (BOOL)openExtensionURL:(NSURL *)URL fromWindow:(NSWindow *)window {
  if (![TLChromiumBrowserController isExtensionURL:URL]) return NO;
  if (_terminating || _shuttingDown || ![self initializeCEFIfNeededFromWindow:window]) return YES;
  _pendingExtensionURLString = URL.absoluteString;
  // Native Chrome windows must be created/focused outside CEF event callbacks.
  TLChromiumDeferToMainRunLoop(^{ [self createOrFocusExtensionWindow]; });
  return YES;
}

- (void)createOrFocusExtensionWindow {
  if (!_initialized || _terminating || _shuttingDown || !_pendingExtensionURLString) return;
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)_extensionBrowserIdentifier];
  if (browser) {
    browser->GetMainFrame()->LoadURL(TLStringFromNSString(_pendingExtensionURLString));
    _pendingExtensionURLString = nil;
    NSWindow *window = [self windowForBrowser:browser];
    [window deminiaturize:nil];
    [window makeKeyAndOrderFront:nil];
    browser->GetHost()->SetFocus(true);
    return;
  }
  if (_extensionWindowOpening) return;
  _extensionWindowOpening = YES;
  CefWindowInfo windowInfo;
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_CHROME;
  windowInfo.bounds = CefRect(100, 100, 1000, 760);
  CefBrowserSettings settings;
  // The null request context intentionally shares the embedded tabs' persistent
  // global profile. Chromium owns installation, storage, updates and removal.
  if (!CefBrowserHost::CreateBrowser(windowInfo, new TLChromiumExtensionClient(self),
                                    TLStringFromNSString(_pendingExtensionURLString), settings, nullptr, nullptr)) {
    _extensionWindowOpening = NO;
    _pendingExtensionURLString = nil;
    [self presentCEFError:@"The extension manager could not be opened. Please try again." fromWindow:NSApp.keyWindow];
  }
}

- (void)extensionBrowserCreated:(CefRefPtr<CefBrowser>)browser {
  [self browserCreated:browser parentView:nil];
  if (_terminating || _shuttingDown) { browser->GetHost()->CloseBrowser(true); return; }
  // Popups and Chromium-created tabs also need lifecycle tracking, but should
  // not replace the utility's primary tab or consume a pending navigation.
  if (!_extensionWindowOpening) return;
  _extensionBrowserIdentifier = browser->GetIdentifier();
  _extensionWindowOpening = NO;
  TLChromiumDeferToMainRunLoop(^{ [self createOrFocusExtensionWindow]; });
}

- (void)openURL:(NSURL *)url fromWindow:(NSWindow *)window modifierFlags:(NSEventModifierFlags)modifierFlags {
  if ([self openExtensionURL:url fromWindow:window]) return;
  NSURL *browserURL = [self browserURLFromURL:url];
  if (!browserURL) {
    return;
  }

  if (TLChromiumModifierFlagsIncludeCommand(modifierFlags)) {
    [NSWorkspace.sharedWorkspace openURL:browserURL];
    return;
  }

  if (![self initializeCEFIfNeededFromWindow:window]) {
    return;
  }

  CefPostTask(TID_UI, new TLChromiumCreateBrowserTask(self,
                                                      TLStringFromNSString(browserURL.absoluteString),
                                                      nil));
}

- (TLChromiumBrowserSession *)loadURL:(NSURL *)url
                                inView:(NSView *)view
                            fromWindow:(NSWindow *)window
                          titleHandler:(TLChromiumBrowserTitleHandler)titleHandler
                           linkHandler:(TLChromiumBrowserLinkHandler)linkHandler
                            URLHandler:(TLChromiumBrowserURLHandler)URLHandler
                        faviconHandler:(TLChromiumBrowserFaviconHandler)faviconHandler
                     navigationHandler:(TLChromiumBrowserNavigationHandler)navigationHandler {
  NSURL *browserURL = [self browserURLFromURL:url];
  if (!browserURL || !view) {
    return nil;
  }

  NSValue *containerKey = TLChromiumContainerKey(view);
  TLChromiumBrowserSession *session = [[TLChromiumBrowserSession alloc] initWithContainerView:view
                                                                            initialURLString:browserURL.absoluteString];
  if (containerKey) {
    _sessionsByContainer[containerKey] = session;
    if (titleHandler) {
      _titleHandlersByContainer[containerKey] = [titleHandler copy];
    } else {
      [_titleHandlersByContainer removeObjectForKey:containerKey];
    }

    if (linkHandler) {
      _linkHandlersByContainer[containerKey] = [linkHandler copy];
    } else {
      [_linkHandlersByContainer removeObjectForKey:containerKey];
    }
    if (URLHandler) {
      _URLHandlersByContainer[containerKey] = [URLHandler copy];
    } else {
      [_URLHandlersByContainer removeObjectForKey:containerKey];
    }
    if (faviconHandler) {
      _faviconHandlersByContainer[containerKey] = [faviconHandler copy];
    } else {
      [_faviconHandlersByContainer removeObjectForKey:containerKey];
    }
    if (navigationHandler) {
      _navigationHandlersByContainer[containerKey] = [navigationHandler copy];
    } else {
      [_navigationHandlersByContainer removeObjectForKey:containerKey];
    }
  }

  if (![self initializeCEFIfNeededFromWindow:window ?: view.window]) {
    if (containerKey) {
      [_sessionsByContainer removeObjectForKey:containerKey];
      [_titleHandlersByContainer removeObjectForKey:containerKey];
      [_linkHandlersByContainer removeObjectForKey:containerKey];
      [_URLHandlersByContainer removeObjectForKey:containerKey];
      [_faviconHandlersByContainer removeObjectForKey:containerKey];
      [_navigationHandlersByContainer removeObjectForKey:containerKey];
    }
    return nil;
  }

  CefPostTask(TID_UI, new TLChromiumCreateBrowserTask(self,
                                                      TLStringFromNSString(browserURL.absoluteString),
                                                      view));
  return session;
}

- (void)navigateSession:(TLChromiumBrowserSession *)session toURL:(NSURL *)URL {
  NSURL *browserURL = [self browserURLFromURL:URL];
  if (!session || !browserURL || session.browserIdentifier < 0) {
    return;
  }

  CefPostTask(TID_UI, new TLChromiumNavigateBrowserTask(self,
                                                        session.browserIdentifier,
                                                        TLStringFromNSString(browserURL.absoluteString)));
}

- (void)goBackInSession:(TLChromiumBrowserSession *)session {
  if (!session || session.browserIdentifier < 0) {
    return;
  }
  CefPostTask(TID_UI, new TLChromiumNavigationCommandTask(self,
                                                          session.browserIdentifier,
                                                          TLChromiumNavigationCommand::GoBack));
}

- (void)goForwardInSession:(TLChromiumBrowserSession *)session {
  if (!session || session.browserIdentifier < 0) {
    return;
  }
  CefPostTask(TID_UI, new TLChromiumNavigationCommandTask(self,
                                                          session.browserIdentifier,
                                                          TLChromiumNavigationCommand::GoForward));
}

- (void)reloadSession:(TLChromiumBrowserSession *)session {
  if (!session || session.browserIdentifier < 0) {
    return;
  }
  CefPostTask(TID_UI, new TLChromiumNavigationCommandTask(self,
                                                          session.browserIdentifier,
                                                          TLChromiumNavigationCommand::Reload));
}

- (void)readPageInSession:(TLChromiumBrowserSession *)session expectedURL:(NSURL *)URL
              completion:(void (^)(NSDictionary *, NSError *))completion {
  CefRefPtr<CefBrowser> browser = session ? [self browserWithIdentifier:(int)session.browserIdentifier] : nullptr;
  NSURL *scriptURL = [NSBundle.mainBundle URLForResource:@"Readability" withExtension:@"js"];
  NSString *source = scriptURL ? [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil] : nil;
  if (!browser || !source.length) {
    completion(nil, [NSError errorWithDomain:@"Talaria.PageReader" code:1
      userInfo:@{NSLocalizedDescriptionKey:@"The browser page reader is not ready. Please try again."}]);
    return;
  }
  CefRefPtr<TLChromiumPageReader> reader = new TLChromiumPageReader(TLBrowserReadabilityScript(source, URL.absoluteString), completion);
  reader->Start(browser);
}

- (void)probeOverlayInSession:(TLChromiumBrowserSession *)session
                 overlayRect:(NSRect)rect viewportSize:(NSSize)viewport quick:(BOOL)quick
                  completion:(void (^)(NSDictionary *))completion {
  CefRefPtr<CefBrowser> browser = session ? [self browserWithIdentifier:(int)session.browserIdentifier] : nullptr;
  static NSString *source;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURL *URL = [NSBundle.mainBundle URLForResource:@"BrowserOverlayProbe" withExtension:@"js"];
    source = URL ? [NSString stringWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:nil] : nil;
  });
  if (!browser || !source.length || NSIsEmptyRect(rect) || viewport.width <= 0 || viewport.height <= 0) {
    completion(@{@"obstructed":NSNull.null}); return;
  }
  NSMutableDictionary *geometry = [@{@"left":@(NSMinX(rect)), @"bottom":@(NSMinY(rect)),
    @"width":@(NSWidth(rect)), @"height":@(NSHeight(rect)), @"currentWidth":@(viewport.width),
    @"currentHeight":@(viewport.height), @"cursor":@(session.overlayCursor), @"quick":@(quick)} mutableCopy];
  if (session.overlayHint) geometry[@"hint"] = session.overlayHint;
  geometry[@"skipFallback"] = @(NSProcessInfo.processInfo.systemUptime < session.overlayFallbackAfter);
  NSUInteger generation = session.documentGeneration;
  TLChromiumProbeOverlay(browser, source, geometry, ^(NSDictionary *result) {
    if (session.browserIdentifier < 0 || session.documentGeneration != generation) {
      completion(@{@"obstructed":NSNull.null}); return;
    }
    session.overlayCursor = [result[@"cursor"] unsignedIntegerValue];
    // A detached/loading opaque frame must not stop ordinary DOM checks. Only
    // the browser-level fallback backs off; skipped fallback remains unknown.
    if ([result[@"fallbackFailed"] boolValue])
      session.overlayFallbackAfter = NSProcessInfo.processInfo.systemUptime + 3.0;
    if ([result[@"hint"] isKindOfClass:NSDictionary.class]) session.overlayHint = result[@"hint"];
    completion(result);
  });
}

- (void)closeSession:(TLChromiumBrowserSession *)session {
  if (!session) {
    return;
  }
  if (session.browserIdentifier == _fullscreenBrowserIdentifier) [self exitBrowserFullscreen];
  [session.documentFooter stop]; session.documentFooter = nil;

  NSView *containerView = session.containerView;
  if (containerView) {
    [self closeBrowserInView:containerView];
    return;
  }

  if (session.browserIdentifier < 0) {
    return;
  }

  NSNumber *browserIdentifier = @(session.browserIdentifier);
  [_sessionsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)session.browserIdentifier];
  session.browserIdentifier = -1;
  if (browser) {
    browser->GetHost()->CloseBrowser(true);
  }
}

- (void)closeBrowserInView:(NSView *)view {
  NSValue *containerKey = TLChromiumContainerKey(view);
  if (!containerKey) {
    return;
  }

  NSNumber *browserIdentifier = _browserIdentifiersByContainer[containerKey];
  TLChromiumBrowserSession *session = _sessionsByContainer[containerKey];
  if (browserIdentifier && browserIdentifier.integerValue == _fullscreenBrowserIdentifier) [self exitBrowserFullscreen];
  [_browserIdentifiersByContainer removeObjectForKey:containerKey];
  [session.documentFooter stop]; session.documentFooter = nil;

  [_sessionsByContainer removeObjectForKey:containerKey];
  [_titleHandlersByContainer removeObjectForKey:containerKey];
  [_linkHandlersByContainer removeObjectForKey:containerKey];
  [_URLHandlersByContainer removeObjectForKey:containerKey];
  [_faviconHandlersByContainer removeObjectForKey:containerKey];
  [_navigationHandlersByContainer removeObjectForKey:containerKey];

  if (!browserIdentifier) {
    session.browserIdentifier = -1;
    return;
  }

  [_containersByBrowserIdentifier removeObjectForKey:browserIdentifier];
  [_sessionsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  [_pendingFaviconURLsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  [_hostsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  session.browserIdentifier = -1;
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:browserIdentifier.intValue];
  if (browser) {
    browser->GetHost()->CloseBrowser(true);
  }
}

- (BOOL)initializeRuntimeFromWindow:(NSWindow *)window {
  return [self initializeCEFIfNeededFromWindow:window];
}

- (BOOL)prepareForApplicationTermination {
  if (!_initialized) {
    return YES;
  }

  [self exitBrowserFullscreen];
  _terminating = YES;
  if (_browsers.empty()) {
    BOOL needsDeferredShutdown = _doingMessagePumpWork;
    _terminationReplyPending = needsDeferredShutdown;
    [self shutdown];
    return !needsDeferredShutdown && !_initialized;
  }

  _terminationReplyPending = YES;
  std::vector<CefRefPtr<CefBrowser>> browsers = _browsers;
  for (const auto &browser : browsers) {
    if (browser) {
      browser->GetHost()->CloseBrowser(true);
    }
  }
  return NO;
}

- (void)shutdown {
  if (!NSThread.isMainThread) {
    TLChromiumDeferToMainRunLoop(^{
      [self shutdown];
    });
    return;
  }

  if (!_initialized || _shuttingDown) {
    return;
  }

  if (_doingMessagePumpWork) {
    _shutdownRequested = YES;
    [_messagePumpTimer invalidate];
    _messagePumpTimer = nil;
    return;
  }

  _shuttingDown = YES;
  _shutdownRequested = NO;
  [_messagePumpTimer invalidate];
  _messagePumpTimer = nil;
  _browsers.clear();
  CefShutdown();
  _cefApp = nullptr;
  _initialized = NO;

  delete _libraryLoader;
  _libraryLoader = nullptr;
  BOOL shouldReplyToTermination = _terminationReplyPending;
  _terminationReplyPending = NO;
  _terminating = NO;
  _shuttingDown = NO;
  if (shouldReplyToTermination) {
    [NSApp replyToApplicationShouldTerminate:YES];
  }
}

- (BOOL)initializeCEFIfNeededFromWindow:(NSWindow *)window {
  if (_initialized) {
    return YES;
  }

  _libraryLoader = new CefScopedLibraryLoader();
  if (!_libraryLoader->LoadInMain()) {
    delete _libraryLoader;
    _libraryLoader = nullptr;
    [self presentCEFError:@"Talaria could not load its embedded Chromium framework." fromWindow:window];
    return NO;
  }

  NSString *mainBundlePath = NSBundle.mainBundle.bundlePath;
  NSString *frameworkPath = [mainBundlePath
    stringByAppendingPathComponent:@"Contents/Frameworks/Chromium Embedded Framework.framework"];
  NSString *cachePath = [self chromiumCachePath];
  if (![self createDirectoryAtPath:cachePath]) {
    [self presentCEFError:@"Talaria could not create its Chromium profile directory." fromWindow:window];
    delete _libraryLoader;
    _libraryLoader = nullptr;
    return NO;
  }

  CefSettings settings;
  settings.external_message_pump = true;
  CefString(&settings.main_bundle_path) = TLStringFromNSString(mainBundlePath);
  CefString(&settings.framework_dir_path) = TLStringFromNSString(frameworkPath);
  CefString(&settings.root_cache_path) = TLStringFromNSString(cachePath);
  CefString(&settings.cache_path) = TLStringFromNSString(cachePath);
  CefString(&settings.locale) = "en-US";

  _cefApp = new TLChromiumApp(self);
  CefMainArgs mainArgs(TLChromiumMainArgc, TLChromiumMainArgv);
  if (!CefInitialize(mainArgs, settings, _cefApp.get(), nullptr)) {
    _cefApp = nullptr;
    delete _libraryLoader;
    _libraryLoader = nullptr;
    [self presentCEFError:@"Talaria could not initialize its embedded Chromium runtime." fromWindow:window];
    return NO;
  }

  _initialized = YES;
  [self scheduleMessagePumpWork:0];
  return YES;
}

- (void)scheduleMessagePumpWork:(int64_t)delayMS {
  TLChromiumDeferToMainRunLoop(^{
    [self handleScheduledMessagePumpWork:delayMS];
  });
}

- (void)handleScheduledMessagePumpWork:(int64_t)delayMS {
  if (!_initialized || _shuttingDown || _shutdownRequested) {
    return;
  }

  if (delayMS == TLChromiumMessagePumpPlaceholderDelayMS && _messagePumpTimer) {
    return;
  }

  [_messagePumpTimer invalidate];
  _messagePumpTimer = nil;

  if (delayMS <= 0) {
    [self performMessagePumpWork];
    return;
  }

  delayMS = MIN(delayMS, TLChromiumMessagePumpMaxDelayMS);
  NSTimeInterval delaySeconds = (NSTimeInterval)delayMS / 1000.0;
  _messagePumpTimer = [NSTimer timerWithTimeInterval:delaySeconds
                                             repeats:NO
                                               block:^(NSTimer *timer) {
    _messagePumpTimer = nil;
    [self performMessagePumpWork];
  }];
  [NSRunLoop.mainRunLoop addTimer:_messagePumpTimer forMode:NSRunLoopCommonModes];
  [NSRunLoop.mainRunLoop addTimer:_messagePumpTimer forMode:NSModalPanelRunLoopMode];
  [NSRunLoop.mainRunLoop addTimer:_messagePumpTimer forMode:NSEventTrackingRunLoopMode];
}

- (void)performMessagePumpWork {
  if (!_initialized || _shuttingDown || _shutdownRequested || _doingMessagePumpWork) {
    if (_doingMessagePumpWork) {
      _messagePumpReentrancyDetected = YES;
    }
    return;
  }

  _messagePumpReentrancyDetected = NO;
  _doingMessagePumpWork = YES;
  CefDoMessageLoopWork();
  _doingMessagePumpWork = NO;

  if (_shutdownRequested) {
    [self shutdown];
    return;
  }

  if (_messagePumpReentrancyDetected) {
    [self scheduleMessagePumpWork:0];
  } else if (!_messagePumpTimer) {
    [self scheduleMessagePumpWork:TLChromiumMessagePumpPlaceholderDelayMS];
  }
}

- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(NSView *)parentView {
  _browsers.push_back(browser);
  if (parentView) {
    NSNumber *browserIdentifier = @(browser ? browser->GetIdentifier() : -1);
    NSValue *containerKey = TLChromiumContainerKey(parentView);
    if (browserIdentifier.intValue >= 0 && containerKey) {
      _browserIdentifiersByContainer[containerKey] = browserIdentifier;
      _containersByBrowserIdentifier[browserIdentifier] = containerKey;
      TLChromiumBrowserSession *session = _sessionsByContainer[containerKey];
      session.browserIdentifier = browserIdentifier.integerValue;
      if (session) {
        _sessionsByBrowserIdentifier[browserIdentifier] = session;
      }
    }
    [self attachBrowserViewForBrowser:browser toContainerView:parentView];
    [self browserNavigationStateChanged:browser
                              canGoBack:browser->CanGoBack()
                           canGoForward:browser->CanGoForward()
                              isLoading:browser->IsLoading()];
    return;
  }
}

// Alloy reports renderer fullscreen but leaves native presentation to the host.
// Move only the CEF view: the original window, split layout and footer stay intact.
- (void)browserFullscreenChanged:(CefRefPtr<CefBrowser>)browser fullscreen:(BOOL)fullscreen {
  if (!browser) return;
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(browser->GetIdentifier())];
  session.fullscreen = fullscreen;
  [session.documentFooter configure:fullscreen ? @{@"enabled":@NO} : (session.documentFooterConfiguration ?: @{@"enabled":@NO}) completion:nil];
  // AppKit can pump events during presentation. Never re-enter Chromium's pump
  // while it is delivering the fullscreen notification.
  TLChromiumDeferToMainRunLoop(^{
    if (!browser->IsValid()) return;
    BOOL requested = browser->GetHost()->IsFullscreen();
    NSInteger identifier = browser->GetIdentifier();
    if (!requested) {
      if (self->_fullscreenBrowserIdentifier == identifier) [self restoreFullscreenBrowser];
      return;
    }
    if (self->_fullscreenBrowserIdentifier == identifier) return;
    NSView *view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    NSWindow *window = view.window;
    if (!window.isVisible || view.isHiddenOrHasHiddenAncestor || !window.screen || self->_shuttingDown) {
      browser->GetHost()->ExitFullscreen(false);
      return;
    }
    [self exitBrowserFullscreen];
    self->_fullscreenView = view;
    self->_fullscreenBrowserIdentifier = identifier;
    self->_fullscreenOriginWindow = window;
    BOOL entered = [view enterFullScreenMode:window.screen withOptions:@{
      NSFullScreenModeAllScreens:@NO,
      NSFullScreenModeApplicationPresentationOptions:@(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)
    }];
    if (!entered) { [self exitBrowserFullscreen]; return; }
    [view.window makeKeyAndOrderFront:nil];
    [view.window makeFirstResponder:view];
    browser->GetHost()->SetFocus(true);
    __weak TLChromiumBrowserController *weakSelf = self;
    self->_fullscreenCloseObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
      object:window queue:nil usingBlock:^(NSNotification *note) { [weakSelf exitBrowserFullscreen]; }];
    self->_fullscreenDeactivateObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillResignActiveNotification
      object:NSApp queue:nil usingBlock:^(NSNotification *note) { [weakSelf exitBrowserFullscreen]; }];
  });
}

- (void)exitBrowserFullscreen {
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)_fullscreenBrowserIdentifier];
  if (browser && browser->GetHost()->IsFullscreen()) browser->GetHost()->ExitFullscreen(true);
  [self restoreFullscreenBrowser];
}

- (void)restoreFullscreenBrowser {
  if (!_fullscreenView) return;
  NSView *view = _fullscreenView;
  NSInteger identifier = _fullscreenBrowserIdentifier;
  NSWindow *origin = _fullscreenOriginWindow;
  _fullscreenView = nil; _fullscreenBrowserIdentifier = -1; _fullscreenOriginWindow = nil;
  for (id observer in @[_fullscreenCloseObserver ?: NSNull.null, _fullscreenDeactivateObserver ?: NSNull.null]) {
    if (observer != NSNull.null) [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
  _fullscreenCloseObserver = nil; _fullscreenDeactivateObserver = nil;
  if (view.inFullScreenMode) [view exitFullScreenModeWithOptions:nil];
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(identifier)];
  session.fullscreen = NO;
  if (session.containerView) {
    [session.containerView layoutSubtreeIfNeeded];
    view.frame = session.containerView.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  }
  [session.documentFooter configure:session.documentFooterConfiguration ?: @{@"enabled":@NO} completion:nil];
  if (NSApp.isActive && origin.isVisible) [origin makeFirstResponder:view];
}

- (void)browserClosed:(CefRefPtr<CefBrowser>)browser {
  int identifier = browser ? browser->GetIdentifier() : -1;
  if (identifier == _extensionBrowserIdentifier) _extensionBrowserIdentifier = -1;
  if (identifier == _fullscreenBrowserIdentifier) [self restoreFullscreenBrowser];
  NSNumber *browserIdentifier = @(identifier);
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  if (containerKey) {
    [_browserIdentifiersByContainer removeObjectForKey:containerKey];
    [_titleHandlersByContainer removeObjectForKey:containerKey];
    [_linkHandlersByContainer removeObjectForKey:containerKey];
    [_URLHandlersByContainer removeObjectForKey:containerKey];
    [_faviconHandlersByContainer removeObjectForKey:containerKey];
    [_navigationHandlersByContainer removeObjectForKey:containerKey];
    TLChromiumBrowserSession *session = _sessionsByContainer[containerKey];
    [session.documentFooter stop];
    session.documentFooter = nil;
    session.browserIdentifier = -1;
    [_sessionsByContainer removeObjectForKey:containerKey];
    [_containersByBrowserIdentifier removeObjectForKey:browserIdentifier];
  }
  [_sessionsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  [_pendingFaviconURLsByBrowserIdentifier removeObjectForKey:browserIdentifier];
  [_hostsByBrowserIdentifier removeObjectForKey:browserIdentifier];

  _browsers.erase(std::remove_if(_browsers.begin(), _browsers.end(), [identifier](const CefRefPtr<CefBrowser> &candidate) {
    return !candidate || candidate->GetIdentifier() == identifier;
  }), _browsers.end());

  if (_terminating && _browsers.empty()) {
    TLChromiumDeferToMainRunLoop(^{
      [self shutdown];
    });
  }
}

- (void)browserTitleChanged:(CefRefPtr<CefBrowser>)browser title:(NSString *)title {
  if (!browser || title.length == 0) {
    return;
  }

  NSNumber *browserIdentifier = @(browser ? browser->GetIdentifier() : -1);
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  TLChromiumBrowserTitleHandler titleHandler = nil;
  if (containerKey) {
    titleHandler = _titleHandlersByContainer[containerKey];
  }
  if (titleHandler) {
    titleHandler(title);
    return;
  }

  NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
  browserView.window.title = title;
}

- (void)browserFaviconURLChanged:(CefRefPtr<CefBrowser>)browser URLString:(NSString *)URLString {
  if (!browser) {
    return;
  }

  NSNumber *browserIdentifier = @(browser->GetIdentifier());
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  TLChromiumBrowserFaviconHandler faviconHandler = nil;
  if (containerKey) {
    faviconHandler = _faviconHandlersByContainer[containerKey];
  }
  if (URLString.length == 0) {
    [_pendingFaviconURLsByBrowserIdentifier removeObjectForKey:browserIdentifier];
    if (faviconHandler) {
      faviconHandler(nil);
    }
    return;
  }

  if ([_pendingFaviconURLsByBrowserIdentifier[browserIdentifier] isEqualToString:URLString]) {
    return;
  }

  _pendingFaviconURLsByBrowserIdentifier[browserIdentifier] = URLString;
  if (faviconHandler) {
    faviconHandler(nil);
  }
  browser->GetHost()->DownloadImage(TLStringFromNSString(URLString),
                                    true,
                                    32,
                                    false,
                                    new TLChromiumFaviconDownloadCallback(self,
                                                                          browser->GetIdentifier(),
                                                                          TLStringFromNSString(URLString)));
}

- (void)browserFaviconDownloadedForIdentifier:(NSInteger)browserIdentifier
                                    URLString:(NSString *)URLString
                                        image:(NSImage *)image {
  NSNumber *identifier = @(browserIdentifier);
  if (![_pendingFaviconURLsByBrowserIdentifier[identifier] isEqualToString:URLString]) {
    return;
  }
  if (!image) {
    [_pendingFaviconURLsByBrowserIdentifier removeObjectForKey:identifier];
  }

  NSValue *containerKey = _containersByBrowserIdentifier[identifier];
  TLChromiumBrowserFaviconHandler faviconHandler = nil;
  if (containerKey) {
    faviconHandler = _faviconHandlersByContainer[containerKey];
  }
  if (faviconHandler) {
    faviconHandler(image);
  }
}

- (void)browserDocumentStarted:(CefRefPtr<CefBrowser>)browser {
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(browser->GetIdentifier())];
  session.documentGeneration += 1;
  session.documentFooterConfiguration = nil;
  session.overlayCursor = 0;
  session.overlayHint = nil;
  session.overlayFallbackAfter = 0;
  [self installDocumentFooterInSession:session browser:browser];
}

- (void)configureDocumentFooter:(NSDictionary *)configuration inSession:(TLChromiumBrowserSession *)session completion:(void (^)(BOOL))completion {
  session.documentFooterConfiguration = configuration;
  if (!session.documentFooter) [self installDocumentFooterInSession:session browser:[self browserWithIdentifier:(int)session.browserIdentifier]];
  if(session.documentFooter)[session.documentFooter configure:session.fullscreen ? @{@"enabled":@NO} : configuration completion:completion];
  else if(completion)completion(NO);
}
- (void)sampleFooterColorInSession:(TLChromiumBrowserSession *)session allowCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {
  if (!session.documentFooter) { completion(@{}); return; }
  [session.documentFooter sampleColorAllowingCapture:capture completion:completion];
}
- (void)installDocumentFooterInSession:(TLChromiumBrowserSession *)session browser:(CefRefPtr<CefBrowser>)browser {
  [session.documentFooter stop]; session.documentFooter = nil;
  if (!session || !browser) return;
  static NSString *source;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURL *URL=[NSBundle.mainBundle URLForResource:@"BrowserDocumentFooter" withExtension:@"js"];
    source=URL ? [NSString stringWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:nil] : nil;
  });
  if (!source.length) return;
  session.documentFooter=[[TLChromiumDocumentFooter alloc] initWithBrowser:browser source:source];
  [session.documentFooter configure:session.fullscreen ? @{@"enabled":@NO} : (session.documentFooterConfiguration ?: @{@"enabled":@NO}) completion:nil];
}

- (void)browserURLChanged:(CefRefPtr<CefBrowser>)browser URL:(NSURL *)URL {
  if (!browser || !URL) {
    return;
  }

  NSNumber *browserIdentifier = @(browser->GetIdentifier());
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  NSString *nextHost = URL.host.lowercaseString ?: @"";
  NSString *previousHost = _hostsByBrowserIdentifier[browserIdentifier];
  if (previousHost.length > 0 && ![previousHost isEqualToString:nextHost]) {
    [_pendingFaviconURLsByBrowserIdentifier removeObjectForKey:browserIdentifier];
    TLChromiumBrowserFaviconHandler faviconHandler = nil;
    if (containerKey) {
      faviconHandler = _faviconHandlersByContainer[containerKey];
    }
    if (faviconHandler) {
      faviconHandler(nil);
    }
  }
  _hostsByBrowserIdentifier[browserIdentifier] = nextHost;

  TLChromiumBrowserURLHandler URLHandler = nil;
  if (containerKey) {
    URLHandler = _URLHandlersByContainer[containerKey];
  }
  if (URLHandler) {
    URLHandler(URL);
  }
}

- (void)browserNavigationStateChanged:(CefRefPtr<CefBrowser>)browser
                           canGoBack:(BOOL)canGoBack
                        canGoForward:(BOOL)canGoForward
                           isLoading:(BOOL)isLoading {
  if (!browser) {
    return;
  }

  NSNumber *browserIdentifier = @(browser->GetIdentifier());
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[browserIdentifier];
  if (!isLoading && !session.documentFooter.ready)
    [self installDocumentFooterInSession:session browser:browser];
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  TLChromiumBrowserNavigationHandler navigationHandler = nil;
  if (containerKey) {
    navigationHandler = _navigationHandlersByContainer[containerKey];
  }
  if (navigationHandler) {
    navigationHandler(canGoBack, canGoForward, isLoading);
  }
}

- (void)navigateBrowserWithIdentifier:(NSInteger)browserIdentifier toURLString:(NSString *)URLString {
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)browserIdentifier];
  if (!browser || URLString.length == 0) {
    return;
  }
  browser->GetMainFrame()->LoadURL(TLStringFromNSString(URLString));
}

- (void)goBackInBrowserWithIdentifier:(NSInteger)browserIdentifier {
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)browserIdentifier];
  if (browser && browser->CanGoBack()) {
    browser->GoBack();
  }
}

- (void)goForwardInBrowserWithIdentifier:(NSInteger)browserIdentifier {
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)browserIdentifier];
  if (browser && browser->CanGoForward()) {
    browser->GoForward();
  }
}

- (void)reloadBrowserWithIdentifier:(NSInteger)browserIdentifier {
  CefRefPtr<CefBrowser> browser = [self browserWithIdentifier:(int)browserIdentifier];
  if (browser) {
    browser->Reload();
  }
}

- (void)createBrowserWithURLString:(NSString *)urlString parentView:(NSView *)parentView {
  if (urlString.length == 0 || !_initialized || _shuttingDown) {
    return;
  }

  CefWindowInfo windowInfo;
  if (parentView) {
    NSRect bounds = parentView.bounds;
    windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(parentView),
                          CefRect(0, 0, (int)MAX(1.0, bounds.size.width), (int)MAX(1.0, bounds.size.height)));
  } else {
    windowInfo.bounds = CefRect(80, 80, 1120, 760);
    windowInfo.hidden = false;
  }
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefString(&windowInfo.window_name) = TLStringFromNSString(urlString);

  CefBrowserSettings browserSettings;
  CefRefPtr<TLChromiumClient> client(new TLChromiumClient(self, parentView));
  CefBrowserHost::CreateBrowser(
    windowInfo,
    client,
    TLStringFromNSString(urlString),
    browserSettings,
    nullptr,
    nullptr);
}

- (void)openBrowserURLString:(NSString *)urlString {
  NSURL *url = [NSURL URLWithString:urlString];
  NSURL *browserURL = url ? [self browserURLFromURL:url] : nil;
  if (!browserURL) {
    return;
  }

  if (![self initializeCEFIfNeededFromWindow:NSApp.keyWindow]) {
    return;
  }

  CefPostTask(TID_UI, new TLChromiumCreateBrowserTask(self,
                                                      TLStringFromNSString(browserURL.absoluteString),
                                                      nil));
}

- (void)openExternalURLString:(NSString *)urlString {
  NSURL *url = [NSURL URLWithString:urlString];
  NSURL *externalURL = url ? [self browserURLFromURL:url] : nil;
  if (externalURL) {
    [NSWorkspace.sharedWorkspace openURL:externalURL];
  }
}

- (BOOL)handleBrowserLinkURLString:(NSString *)urlString fromBrowser:(CefRefPtr<CefBrowser>)browser userGesture:(BOOL)userGesture {
  NSURL *url = [NSURL URLWithString:urlString];
  if ([self openExtensionURL:url fromWindow:nil]) return YES;
  NSURL *browserURL = url ? [self browserURLFromURL:url] : nil;
  if (!browserURL) {
    return NO;
  }

  NSEventModifierFlags modifierFlags = TLChromiumCurrentModifierFlags();
  NSNumber *browserIdentifier = @(browser ? browser->GetIdentifier() : -1);
  NSValue *containerKey = _containersByBrowserIdentifier[browserIdentifier];
  TLChromiumBrowserLinkHandler linkHandler = nil;
  if (containerKey) {
    linkHandler = _linkHandlersByContainer[containerKey];
  }
  if (linkHandler) {
    linkHandler(browserURL, modifierFlags);
    return YES;
  }

  [self openBrowserURLString:browserURL.absoluteString];
  return YES;
}

- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier {
  if (identifier < 0) {
    return nullptr;
  }

  for (const auto &browser : _browsers) {
    if (browser && browser->GetIdentifier() == identifier) {
      return browser;
    }
  }

  return nullptr;
}

- (NSWindow *)windowForBrowser:(CefRefPtr<CefBrowser>)browser {
  if (!browser) {
    return nil;
  }

  CefWindowHandle windowHandle = browser->GetHost()->GetWindowHandle();
  if (!windowHandle) {
    return nil;
  }

  NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(windowHandle);
  return browserView.window;
}

- (void)attachBrowserViewForBrowser:(CefRefPtr<CefBrowser>)browser toContainerView:(NSView *)containerView {
  if (!browser || !containerView) {
    return;
  }

  CefWindowHandle windowHandle = browser->GetHost()->GetWindowHandle();
  if (!windowHandle) {
    return;
  }

  NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(windowHandle);
  if (!browserView) {
    return;
  }

  if (browserView.superview != containerView) {
    [containerView addSubview:browserView];
  }
  browserView.translatesAutoresizingMaskIntoConstraints = YES;
  browserView.frame = containerView.bounds;
  browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

- (NSURL *)browserURLFromURL:(NSURL *)url {
  NSString *scheme = url.scheme.lowercaseString;
  if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
    return url;
  }

  return nil;
}

- (NSString *)chromiumCachePath {
  // Explicit isolation for desktop verification while another worktree owns
  // the normal Chromium profile. Ordinary launches keep the existing profile.
  NSString *profileOverride = NSProcessInfo.processInfo.environment[@"TL_CHROMIUM_PROFILE_DIR"];
  if (profileOverride.isAbsolutePath) return profileOverride.stringByStandardizingPath;
  NSURL *supportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
  NSURL *profileURL = [[supportURL URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES]
    URLByAppendingPathComponent:@"Chromium" isDirectory:YES];
  return profileURL.path;
}

- (BOOL)createDirectoryAtPath:(NSString *)path {
  if (path.length == 0) {
    return NO;
  }

  NSError *error = nil;
  return [NSFileManager.defaultManager createDirectoryAtPath:path
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error];
}

- (void)presentCEFError:(NSString *)message fromWindow:(NSWindow *)window {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Talaria";
  alert.informativeText = message;
  if (window) {
    [alert beginSheetModalForWindow:window completionHandler:nil];
  } else {
    [alert runModal];
  }
}

@end
