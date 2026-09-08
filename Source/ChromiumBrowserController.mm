#import "ChromiumBrowserController.h"
#import "ChromiumRunLoop.h"
#import "ChromiumContextMenu.h"
#import "ChromiumImageActions.h"
#import "ChromiumPageArchive.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "ChromiumOverlayProbe.h"
#import "ChromiumDocumentFooter.h"
#import "ChromiumNavigationTransition.h"
#import "BrowserPageContext.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"

#include <algorithm>
#include <limits.h>
#include <cmath>
#include <stdint.h>

#include <string>
#include <utility>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/cef_cookie.h"
#include "include/cef_download_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_command_line.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_display_handler.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_keyboard_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_find_handler.h"
#include "include/cef_request_handler.h"
#include "include/cef_task.h"
#include "include/cef_values.h"
#include "include/internal/cef_mac.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

static const int TLChromiumInspectElementCommand = MENU_ID_USER_FIRST;
static const int TLChromiumSavePageCommand = MENU_ID_USER_FIRST + 1;

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

static NSString *TLBrowserOrigin(NSString *string) {
  NSURLComponents *URL = [NSURLComponents componentsWithString:string];
  if (!URL.host.length || ![@[@"http",@"https"] containsObject:URL.scheme.lowercaseString]) return @"";
  URL.scheme = URL.scheme.lowercaseString; URL.host = URL.host.lowercaseString;
  if (([URL.scheme isEqual:@"https"] && URL.port.intValue == 443) || ([URL.scheme isEqual:@"http"] && URL.port.intValue == 80)) URL.port = nil;
  URL.user = nil; URL.password = nil; URL.path = @""; URL.query = nil; URL.fragment = nil;
  return URL.string;
}

static NSValue *TLChromiumContainerKey(NSView *view) {
  return view ? [NSValue valueWithNonretainedObject:view] : nil;
}

static void TLChromiumApplyZoom(CefRefPtr<CefBrowser> browser, double zoom) {
  CefRefPtr<CefBrowserHost> host = browser->GetHost();
  // SetZoomLevel(0) also resets Chromium's page scale. Avoid sending a visual
  // reset on every navigation (or unrelated preference change) at the same zoom.
  if (std::abs(host->GetZoomLevel() - zoom) > 0.000001) host->SetZoomLevel(zoom);
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
@property (nonatomic, readwrite) BOOL devToolsVisible;
@property (nonatomic) BOOL finding;
@property (nonatomic) NSInteger latestFindIdentifier;
@property (nonatomic) NSUInteger overlayCursor;
@property (nonatomic, copy) NSDictionary *overlayHint;
@property (nonatomic) NSTimeInterval overlayFallbackAfter;
@property (nonatomic, strong) TLChromiumDocumentFooter *documentFooter;
@property (nonatomic, strong) TLChromiumNavigationTransition *navigationTransition;
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
- (void)browserFindResult:(CefRefPtr<CefBrowser>)browser identifier:(int)identifier count:(int)count activeMatch:(int)activeMatch finalUpdate:(BOOL)finalUpdate;
- (void)browserContextReady;
- (void)downloadUpdatedForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)closeBrowserOrKeepDownload:(CefRefPtr<CefBrowser>)browser;
- (void)trackPermissionAlert:(NSAlert *)alert browser:(int)browserID prompt:(uint64_t)promptID;
- (void)dismissPermissionAlertForBrowser:(int)browserID prompt:(uint64_t)promptID;
- (void)applyBrowserPreferences;
- (void)checkBackgroundBrowsers;
- (BOOL)initializeCEFIfNeededFromWindow:(nullable NSWindow *)window;
- (void)scheduleMessagePumpWork:(int64_t)delayMS;
- (void)handleScheduledMessagePumpWork:(int64_t)delayMS;
- (void)performMessagePumpWork;
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser parentView:(nullable NSView *)parentView;
- (NSWindow *)browserWillClose:(CefRefPtr<CefBrowser>)browser;
- (void)browserClosed:(CefRefPtr<CefBrowser>)browser;
- (void)devToolsVisibilityChanged:(BOOL)visible forBrowserIdentifier:(NSInteger)identifier;
- (void)showPageSourceForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)savePageForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)presentPageArchive:(NSData *)archive suggestedName:(NSString *)name fromWindow:(NSWindow *)window;
- (NSSavePanel *)pageSavePanel;
- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion;
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
- (TLBrowserLinkOpenHandler)contextLinkHandlerForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)openImageURL:(NSURL *)URL fromBrowser:(CefRefPtr<CefBrowser>)browser inNewWindow:(BOOL)newWindow;
- (CefRefPtr<CefBrowser>)browserWithIdentifier:(int)identifier;
- (nullable NSWindow *)windowForBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)attachBrowserViewForBrowser:(CefRefPtr<CefBrowser>)browser toContainerView:(NSView *)containerView;
- (void)presentCEFError:(NSString *)message fromWindow:(nullable NSWindow *)window;
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
    if (![[TLBrowserPreferences.sharedPreferences localValue:@"hardwareAcceleration"] boolValue]) command_line->AppendSwitch("disable-gpu");
  }

  void OnContextInitialized() override { [controller_ browserContextReady]; }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    [controller_ scheduleMessagePumpWork:delay_ms];
  }

 private:
  __unsafe_unretained TLChromiumBrowserController *controller_;

  IMPLEMENT_REFCOUNTING(TLChromiumApp);
};

class TLChromiumClient : public CefClient,
                         public CefContextMenuHandler,
                         public CefDisplayHandler,
                         public CefKeyboardHandler,
                         public CefLifeSpanHandler,
                         public CefLoadHandler,
                         public CefFindHandler,
                         public CefRequestHandler,
                         public CefDownloadHandler,
                         public CefPermissionHandler {
 public:
  explicit TLChromiumClient(TLChromiumBrowserController *browserController,
                            NSView *parentView = nil,
                            int inspectedBrowserIdentifier = -1,
                            NSString *downloadURL = nil)
      : browserController_(browserController),
        parentView_(parentView),
        inspectedBrowserIdentifier_(inspectedBrowserIdentifier), downloadURL_([downloadURL copy]) {}

  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override {
    return inspectedBrowserIdentifier_ < 0 ? this : nullptr;
  }

  void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                           CefRefPtr<CefContextMenuParams> params,
                           CefRefPtr<CefMenuModel> model) override {
    CEF_REQUIRE_UI_THREAD();
    if (params && params->GetLinkUrl().empty() && !params->GetSelectionText().empty()) return;
    if (params && params->GetMediaType() == CM_MEDIATYPE_IMAGE) {
      TLChromiumPopulateImageMenu(model, [NSString stringWithUTF8String:params->GetSourceUrl().ToString().c_str()], params->HasImageContents());
      return;
    }
    // Keep editing, selection and link-specific actions, then add the page menu.
    for (int command : {MENU_ID_BACK, MENU_ID_FORWARD, MENU_ID_RELOAD, MENU_ID_RELOAD_NOCACHE,
                        MENU_ID_STOPLOAD, MENU_ID_PRINT, MENU_ID_VIEW_SOURCE}) model->Remove(command);
    for (int index=(int)model->GetCount()-1;index>=0;index--) {
      if (model->GetTypeAt(index)==MENUITEMTYPE_SEPARATOR &&
          (index==0 || index==(int)model->GetCount()-1 || model->GetTypeAt(index-1)==MENUITEMTYPE_SEPARATOR))
        model->RemoveAt(index);
    }
    if (model->GetCount() > 0) model->AddSeparator();
    model->AddItem(MENU_ID_RELOAD, "Reload Page");
    model->AddSeparator();
    model->AddItem(MENU_ID_VIEW_SOURCE, "Show Page Source");
    model->AddItem(TLChromiumSavePageCommand, "Save Page As…");
    model->AddSeparator();
    model->AddItem(MENU_ID_PRINT, "Print Page…");
    model->AddSeparator();
    model->AddItem(TLChromiumInspectElementCommand, "Inspect Element");
  }

  bool RunContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model,
                      CefRefPtr<CefRunContextMenuCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    if (!params->GetLinkUrl().empty()) {
      NSURL *URL = [NSURL URLWithString:TLNSStringFromCefString(params->GetLinkUrl())];
      if (URL) {
        TLChromiumBrowserController *controller = browserController_;
        TLChromiumShowLinkContextMenu(browser, params->GetMediaType() == CM_MEDIATYPE_IMAGE ? model : nullptr,
          URL, [controller contextLinkHandlerForBrowser:browser] != nil, CefPoint(params->GetXCoord(), params->GetYCoord()), callback,
          ^(NSURL *linkedURL, TLBrowserLinkDestination destination) {
            if (!browser->IsValid()) return;
            TLBrowserLinkOpenHandler handler = [controller contextLinkHandlerForBrowser:browser];
            if (handler) handler(linkedURL, destination);
            else if (destination != TLBrowserLinkSplitView) [controller openImageURL:linkedURL fromBrowser:browser inNewWindow:destination == TLBrowserLinkNewWindow];
          });
        return true;
      }
    }
    if (!params->GetSelectionText().empty() && params->IsEditable()) return false;
    if (!params->GetSelectionText().empty()) {
      NSString *text = TLNSStringFromCefString(params->GetSelectionText());
      CefPoint location(params->GetXCoord(), params->GetYCoord());
      TLChromiumDeferToMainRunLoop(^{
        if (browser->IsValid()) {
          NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
          NSPoint point = NSMakePoint(location.x, view.isFlipped ? location.y : NSHeight(view.bounds)-location.y);
          [TLBrowserLinkActions showSelectedText:text inView:view atPoint:point];
        }
        callback->Cancel();
      });
      return true;
    }
    TLChromiumShowContextMenu(browser, model, CefPoint(params->GetXCoord(),params->GetYCoord()), callback);
    return true;
  }

  bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                            CefRefPtr<CefContextMenuParams> params, int command_id,
                            cef_event_flags_t event_flags) override {
    CEF_REQUIRE_UI_THREAD();
    if (command_id >= TLChromiumImageCommandFirst && command_id <= TLChromiumImageCommandFirst + TLBrowserImageShare) {
      if (!params || params->GetMediaType() != CM_MEDIATYPE_IMAGE) return true;
      TLBrowserImageAction action = (TLBrowserImageAction)(command_id - TLChromiumImageCommandFirst);
      NSURL *URL = [NSURL URLWithString:[NSString stringWithUTF8String:params->GetSourceUrl().ToString().c_str()]];
      if (!TLBrowserImageURLIsSupported(URL) || action == TLBrowserImageLookUp) return true;
      NSString *frameURL = [NSString stringWithUTF8String:params->GetFrameUrl().ToString().c_str()];
      NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
      NSPoint point = NSMakePoint(params->GetXCoord(), view.isFlipped ? params->GetYCoord() : NSHeight(view.bounds) - params->GetYCoord());
      TLChromiumBrowserController *controller = browserController_;
      // Snapshot context params before returning to Chromium; native panels must run outside its callback.
      TLChromiumDeferToMainRunLoop(^{
        if (!browser->IsValid()) return;
        if (action == TLBrowserImageOpenTab || action == TLBrowserImageOpenWindow) {
          [controller openImageURL:URL fromBrowser:browser inNewWindow:action == TLBrowserImageOpenWindow];
        } else if (action == TLBrowserImageCopyAddress) {
          [NSPasteboard.generalPasteboard clearContents];
          [NSPasteboard.generalPasteboard setString:URL.absoluteString forType:NSPasteboardTypeString];
        } else {
          TLChromiumReadImage(browser, URL, frameURL, ^(TLBrowserImageResource *resource, NSError *error) {
            if (!view.window.isVisible) return;
            if (error) [controller presentCEFError:error.localizedDescription fromWindow:view.window];
            else [TLBrowserImageActions performAction:action resource:resource URL:URL fromView:view atPoint:point];
          });
        }
      });
      return true;
    }
    switch (command_id) {
      case MENU_ID_RELOAD: browser->Reload();return true;
      case MENU_ID_VIEW_SOURCE: [browserController_ showPageSourceForBrowser:browser];return true;
      case TLChromiumSavePageCommand: [browserController_ savePageForBrowser:browser];return true;
      case MENU_ID_PRINT: browser->GetHost()->Print();return true;
      case TLChromiumInspectElementCommand: break;
      default: return false;
    }
    CefWindowInfo windowInfo;
    CefBrowserSettings settings;
    browser->GetHost()->ShowDevTools(windowInfo, nullptr, settings,
      CefPoint(params->GetXCoord(), params->GetYCoord()));
    return true;
  }

  void OnBeforeDevToolsPopup(CefRefPtr<CefBrowser> browser, CefWindowInfo &windowInfo,
                             CefRefPtr<CefClient> &client, CefBrowserSettings &settings,
                             CefRefPtr<CefDictionaryValue> &extra_info,
                             bool *use_default_window) override {
    CEF_REQUIRE_UI_THREAD();
    // DevTools owns a separate window; it must not inherit the page's host view.
    client = new TLChromiumClient(browserController_, nil, browser->GetIdentifier());
  }

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
  CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
  void OnFindResult(CefRefPtr<CefBrowser> browser, int identifier, int count,
                    const CefRect &selectionRect, int activeMatchOrdinal, bool finalUpdate) override {
    CEF_REQUIRE_UI_THREAD();
    [browserController_ browserFindResult:browser identifier:identifier count:count
                             activeMatch:activeMatchOrdinal finalUpdate:finalUpdate];
  }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }

  void RecordDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                      CefRefPtr<CefDownloadItemCallback> callback, NSString *suggestedName = @"") {
    if (!item || !item->IsValid()) return;
    TLBrowserDownloadState state = item->IsComplete() ? TLBrowserDownloadStateComplete :
      item->IsCanceled() ? TLBrowserDownloadStateCancelled : item->IsInterrupted() ? TLBrowserDownloadStateFailed :
      item->IsPaused() ? TLBrowserDownloadStatePaused : TLBrowserDownloadStateDownloading;
    NSString *failure = @"";
    if (state == TLBrowserDownloadStateFailed) {
      switch (item->GetInterruptReason()) {
        case CEF_DOWNLOAD_INTERRUPT_REASON_FILE_NO_SPACE: failure = @"Not enough disk space"; break;
        case CEF_DOWNLOAD_INTERRUPT_REASON_FILE_ACCESS_DENIED: failure = @"Cannot write to the selected folder"; break;
        case CEF_DOWNLOAD_INTERRUPT_REASON_NETWORK_DISCONNECTED: failure = @"Network disconnected"; break;
        case CEF_DOWNLOAD_INTERRUPT_REASON_NETWORK_TIMEOUT: failure = @"Connection timed out"; break;
        case CEF_DOWNLOAD_INTERRUPT_REASON_SERVER_UNAUTHORIZED:
        case CEF_DOWNLOAD_INTERRUPT_REASON_SERVER_FORBIDDEN: failure = @"The server denied access. Sign in and try again"; break;
        case CEF_DOWNLOAD_INTERRUPT_REASON_FILE_BLOCKED:
        case CEF_DOWNLOAD_INTERRUPT_REASON_FILE_VIRUS_INFECTED:
        case CEF_DOWNLOAD_INTERRUPT_REASON_FILE_SECURITY_CHECK_FAILED: failure = @"Blocked by a security check"; break;
        default: failure = @"The transfer was interrupted. Try again"; break;
      }
    }
    TLBrowserDownloadControl control = nil;
    if (callback) control = ^(TLBrowserDownloadAction action) {
      if (action == TLBrowserDownloadActionPause) callback->Pause();
      else if (action == TLBrowserDownloadActionResume) callback->Resume();
      else callback->Cancel();
    };
    NSString *name = suggestedName.length ? suggestedName : TLNSStringFromCefString(item->GetSuggestedFileName());
    NSString *URL = TLNSStringFromCefString(item->GetOriginalUrl());
    if (!URL.length) URL = TLNSStringFromCefString(item->GetURL());
    [TLBrowserDownloadManager.sharedManager updateDownloadWithID:item->GetId() browserIdentifier:browser->GetIdentifier()
      URLString:URL fileName:name path:TLNSStringFromCefString(item->GetFullPath())
      receivedBytes:item->GetReceivedBytes() totalBytes:item->GetTotalBytes() bytesPerSecond:item->GetCurrentSpeed()
      state:state failureReason:failure control:control];
  }

  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                        const CefString &suggested_name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    if (!item || !item->IsValid()) return false;
    RecordDownload(browser, item, nullptr, TLNSStringFromCefString(suggested_name));
    auto context = browser->GetHost()->GetRequestContext();
    auto pathPref = context->GetPreference("download.default_directory");
    auto askPref = context->GetPreference("download.prompt_for_download");
    NSString *directory = pathPref ? TLNSStringFromCefString(pathPref->GetString()) : @"";
    if (!directory.isAbsolutePath) directory = [NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [TLBrowserDownloadManager.sharedManager reserveDestinationForDownloadID:item->GetId()
      directory:directory fileName:TLNSStringFromCefString(suggested_name)];
    callback->Continue(TLStringFromNSString(path), !askPref || askPref->GetBool());
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    if (!item || !item->IsValid()) return;
    RecordDownload(browser, item, callback);
    [browserController_ downloadUpdatedForBrowser:browser];
    if (downloadURL_.length && !item->IsInProgress()) {
      TLChromiumDeferToMainRunLoop(^{ if (browser->IsValid()) browser->GetHost()->CloseBrowser(true); });
    }
  }

  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t prompt_id,
                             const CefString &origin, uint32_t requested,
                             CefRefPtr<CefPermissionPromptCallback> callback) override {
    NSMutableArray *names = [NSMutableArray array];
    const std::pair<uint32_t, NSString *> permissions[] = {
      {CEF_PERMISSION_TYPE_GEOLOCATION,@"location"}, {CEF_PERMISSION_TYPE_NOTIFICATIONS,@"notifications"},
      {CEF_PERMISSION_TYPE_CAMERA_STREAM,@"camera"}, {CEF_PERMISSION_TYPE_MIC_STREAM,@"microphone"},
      {CEF_PERMISSION_TYPE_CLIPBOARD,@"clipboard"}, {CEF_PERMISSION_TYPE_LOCAL_FONTS,@"local fonts"},
      {CEF_PERMISSION_TYPE_MULTIPLE_DOWNLOADS,@"multiple downloads"}, {CEF_PERMISSION_TYPE_MIDI_SYSEX,@"MIDI devices"},
      {CEF_PERMISSION_TYPE_STORAGE_ACCESS,@"site storage"}, {CEF_PERMISSION_TYPE_FILE_SYSTEM_ACCESS,@"files"},
      {CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT,@"window management"}, {CEF_PERMISSION_TYPE_SENSORS,@"motion sensors"},
      {CEF_PERMISSION_TYPE_LOCAL_NETWORK_ACCESS_DEPRECATED,@"local network"}, {CEF_PERMISSION_TYPE_LOCAL_NETWORK,@"local network"},
      {CEF_PERMISSION_TYPE_LOOPBACK_NETWORK,@"local services"}, {CEF_PERMISSION_TYPE_TOP_LEVEL_STORAGE_ACCESS,@"third-party storage"},
      {CEF_PERMISSION_TYPE_KEYBOARD_LOCK,@"keyboard lock"}, {CEF_PERMISSION_TYPE_POINTER_LOCK,@"pointer lock"}
    };
    uint32_t known = 0;
    for (auto p : permissions) if (requested & p.first) { [names addObject:p.second]; known |= p.first; }
    if (requested & ~known) { callback->Continue(CEF_PERMISSION_RESULT_DENY); return true; }
    __weak TLChromiumBrowserController *owner = browserController_;
    NSString *requestOrigin = TLNSStringFromCefString(origin);
    NSString *topLevelURL = TLNSStringFromCefString(browser->GetMainFrame()->GetURL());
    TLChromiumDeferToMainRunLoop(^{
      NSWindow *window = [owner windowForBrowser:browser];
      if (!window || window.attachedSheet || !browser->IsValid() || ![TLNSStringFromCefString(browser->GetMainFrame()->GetURL()) isEqual:topLevelURL]) { callback->Continue(CEF_PERMISSION_RESULT_IGNORE); return; }
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = [NSString stringWithFormat:@"Allow %@?", [names componentsJoinedByString:@", "]];
      alert.informativeText = [NSString stringWithFormat:@"%@ is requesting access in Talaria.", requestOrigin];
      [alert addButtonWithTitle:@"Block"]; [alert addButtonWithTitle:@"Allow"];
      [owner trackPermissionAlert:alert browser:browser->GetIdentifier() prompt:prompt_id];
      [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        callback->Continue(result == NSAlertSecondButtonReturn && browser->IsValid() ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
      }];
    });
    return true;
  }

  void OnDismissPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t prompt_id, cef_permission_request_result_t result) override {
    [browserController_ dismissPermissionAlertForBrowser:browser->GetIdentifier() prompt:prompt_id];
  }

  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
      const CefString &origin, uint32_t requested, CefRefPtr<CefMediaAccessCallback> callback) override {
    if (requested & ~(CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE)) { callback->Cancel(); return true; }
    auto context = browser->GetHost()->GetRequestContext();
    bool needsAsk = false;
    for (auto p : {std::make_pair(CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC),
                   std::make_pair(CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE, CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA)}) {
      if (!(requested & p.first)) continue;
      auto permission = context->GetContentSetting(origin, origin, p.second);
      if (permission == CEF_CONTENT_SETTING_VALUE_BLOCK) { callback->Cancel(); return true; }
      needsAsk |= permission != CEF_CONTENT_SETTING_VALUE_ALLOW;
    }
    if (!needsAsk) { callback->Continue(requested); return true; }
    __weak TLChromiumBrowserController *owner = browserController_;
    NSString *requestOrigin = TLNSStringFromCefString(origin);
    NSString *devices = (requested & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) && (requested & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE)
      ? @"camera and microphone" : (requested & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) ? @"camera" : @"microphone";
    TLChromiumDeferToMainRunLoop(^{
      NSWindow *window = [owner windowForBrowser:browser];
      if (!window || window.attachedSheet || !browser->IsValid() || !frame->IsValid() || ![TLBrowserOrigin(TLNSStringFromCefString(frame->GetURL())) isEqual:TLBrowserOrigin(requestOrigin)]) { callback->Cancel(); return; }
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = [NSString stringWithFormat:@"Allow access to your %@?", devices];
      alert.informativeText = [NSString stringWithFormat:@"%@ is requesting access in Talaria.", requestOrigin];
      [alert addButtonWithTitle:@"Block"]; [alert addButtonWithTitle:@"Allow once"];
      [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        if (result == NSAlertSecondButtonReturn && browser->IsValid() && frame->IsValid() && [TLBrowserOrigin(TLNSStringFromCefString(frame->GetURL())) isEqual:TLBrowserOrigin(requestOrigin)]) callback->Continue(requested);
        else callback->Cancel();
      }];
    });
    return true;
  }

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
    if (frame && frame->IsMain()) {
      double zoom = log([[TLBrowserPreferences.sharedPreferences localValue:@"zoom"] doubleValue] / 100.0) / log(1.2);
      TLChromiumApplyZoom(browser, zoom);
      [browserController_ browserDocumentStarted:browser];
    }
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
    if (downloadURL_.length) browser->GetHost()->StartDownload(TLStringFromNSString(downloadURL_));
    if (inspectedBrowserIdentifier_ >= 0)
      [browserController_ devToolsVisibilityChanged:YES forBrowserIdentifier:inspectedBrowserIdentifier_];
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    NSWindow *standaloneWindow = [browserController_ browserWillClose:browser];
    if (!parentView_ && downloadURL_.length) return false;
    bool standalone = !parentView_;
    // Explicitly detach the CEF view so retained AppKit windows cannot prevent
    // OnBeforeClose. Embedded browsers must leave their workspace window open.
    TLChromiumDeferToMainRunLoop(^{
      @autoreleasepool {
        if (!browser->IsValid()) { return; }
        if (standalone) {
          // Use the saved AppKit window, not CEF's forwarding view proxy, which
          // becomes invalid as soon as the native browser is destroyed.
          [standaloneWindow orderOut:nil];
          standaloneWindow.contentView = nil;
          [standaloneWindow close];
        } else {
          NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
          [browserView removeFromSuperview];
        }
      }
    });
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    if (inspectedBrowserIdentifier_ >= 0)
      [browserController_ devToolsVisibilityChanged:NO forBrowserIdentifier:inspectedBrowserIdentifier_];
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

  int inspectedBrowserIdentifier_;
  NSString *downloadURL_;

  IMPLEMENT_REFCOUNTING(TLChromiumClient);
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

class TLBrowserCompletion : public CefCompletionCallback {
 public:
 explicit TLBrowserCompletion(void (^completion)(NSError *)) : completion_([completion copy]) {}
 void OnComplete() override { completion_(nil); }
 private:
 void (^completion_)(NSError *);
 IMPLEMENT_REFCOUNTING(TLBrowserCompletion);
};
class TLBrowserCookieCompletion : public CefDeleteCookiesCallback {
 public:
 explicit TLBrowserCookieCompletion(void (^completion)(NSError *)) : completion_([completion copy]) {}
 void OnComplete(int count) override { auto completion = completion_; dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); }
 private:
 void (^completion_)(NSError *);
 IMPLEMENT_REFCOUNTING(TLBrowserCookieCompletion);
};

@implementation TLChromiumBrowserController {
  CefScopedLibraryLoader *_libraryLoader;
  CefRefPtr<TLChromiumApp> _cefApp;
  std::vector<CefRefPtr<CefBrowser>> _browsers;
  NSMapTable<NSNumber *, NSWindow *> *_standaloneBrowserWindows;
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
  NSTimer *_backgroundTimer;
  NSMutableDictionary<NSNumber *, NSDate *> *_backgroundSince;
  NSMutableSet<NSNumber *> *_pausedBrowsers;
  NSMutableArray<void (^)(NSError *)> *_settingsReadyCallbacks;
  BOOL _browserSettingsReady;
  BOOL _browserDarkAppearance;
  NSMutableDictionary<NSString *, NSAlert *> *_permissionAlerts;
  NSMutableDictionary<NSNumber *, NSView *> *_detachedDownloadContainers;
  BOOL _initialized;
  BOOL _shuttingDown;
  BOOL _shutdownRequested;
  BOOL _doingMessagePumpWork;
  BOOL _messagePumpReentrancyDetected;
  BOOL _terminating;
  BOOL _terminationReplyPending;
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
    _standaloneBrowserWindows = [NSMapTable strongToWeakObjectsMapTable];
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
    _backgroundSince = [NSMutableDictionary dictionary];
    _pausedBrowsers = [NSMutableSet set];
    _settingsReadyCallbacks = [NSMutableArray array];
    _permissionAlerts = [NSMutableDictionary dictionary];
    _detachedDownloadContainers = [NSMutableDictionary dictionary];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(browserPreferencesChanged:) name:TLBrowserPreferencesDidChangeNotification object:nil];
  }
  return self;
}

- (void)openURL:(NSURL *)url fromWindow:(NSWindow *)window {
  [self openURL:url fromWindow:window modifierFlags:TLChromiumCurrentModifierFlags()];
}

- (void)openURL:(NSURL *)url fromWindow:(NSWindow *)window modifierFlags:(NSEventModifierFlags)modifierFlags {
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

- (void)startDownloadURL:(NSURL *)URL fromWindow:(NSWindow *)window {
  if (![self browserURLFromURL:URL]) return;
  if (![self initializeCEFIfNeededFromWindow:window]) return;
  // A retry uses the same Chromium profile even when its original tab is closed.
  CefWindowInfo info;
  info.hidden = true;
  info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings;
  if (!CefBrowserHost::CreateBrowser(info, new TLChromiumClient(self, nil, -1, URL.absoluteString),
      "about:blank", settings, nullptr, nullptr)) {
    [self presentCEFError:@"The download could not be started. Please try again." fromWindow:window];
  }
}

- (void)closeBrowserOrKeepDownload:(CefRefPtr<CefBrowser>)browser {
  browser->GetHost()->CloseDevTools();
  if (!_terminating && [TLBrowserDownloadManager.sharedManager hasActiveDownloadsForBrowser:browser->GetIdentifier()]) {
    NSView *view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(browser->GetHost()->GetWindowHandle());
    if (view) {
      // Keep a parent alive, not the CEF view itself: DoClose must be able to
      // release the native browser by removing it from its parent.
      NSView *container = [[NSView alloc] initWithFrame:view.bounds];
      _detachedDownloadContainers[@(browser->GetIdentifier())] = container;
      [container addSubview:view];
      return;
    }
  }
  browser->GetHost()->CloseBrowser(true);
}

- (void)downloadUpdatedForBrowser:(CefRefPtr<CefBrowser>)browser {
  NSInteger identifier = browser->GetIdentifier();
  if (_detachedDownloadContainers[@(identifier)] && ![TLBrowserDownloadManager.sharedManager hasActiveDownloadsForBrowser:identifier]) {
    TLChromiumDeferToMainRunLoop(^{
      if (browser->IsValid() && ![TLBrowserDownloadManager.sharedManager hasActiveDownloadsForBrowser:identifier])
        browser->GetHost()->CloseBrowser(true);
    });
  }
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

- (void)findText:(NSString *)text inSession:(TLChromiumBrowserSession *)session forward:(BOOL)forward findNext:(BOOL)findNext {
  CefRefPtr<CefBrowser> browser = session ? [self browserWithIdentifier:(int)session.browserIdentifier] : nullptr;
  if (!browser || !text.length) { [self stopFindingInSession:session]; return; }
  // Bundled CEF 151 forwards its last flag as Chromium's find_match option:
  // false counts matches without selecting one. Reset fresh searches explicitly
  // and always request an active match so typing also scrolls to the result.
  if (!findNext) [self stopFindingInSession:session];
  session.finding = YES;
  browser->GetHost()->Find(TLStringFromNSString(text), forward, false, true);
}

- (void)stopFindingInSession:(TLChromiumBrowserSession *)session {
  session.finding = NO;
  CefRefPtr<CefBrowser> browser = session ? [self browserWithIdentifier:(int)session.browserIdentifier] : nullptr;
  if (browser) browser->GetHost()->StopFinding(true);
}

- (void)focusSession:(TLChromiumBrowserSession *)session {
  CefRefPtr<CefBrowser> browser = session ? [self browserWithIdentifier:(int)session.browserIdentifier] : nullptr;
  if (browser) browser->GetHost()->SetFocus(true);
}

- (void)browserFindResult:(CefRefPtr<CefBrowser>)browser identifier:(int)identifier count:(int)count
             activeMatch:(int)activeMatch finalUpdate:(BOOL)finalUpdate {
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(browser->GetIdentifier())];
  if (!session.finding || identifier < session.latestFindIdentifier) return;
  session.latestFindIdentifier = identifier;
  if (session.findResultsChangedHandler) session.findResultsChangedHandler(count, activeMatch, finalUpdate);
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
  [self stopFindingInSession:session];
  session.findResultsChangedHandler = nil;
  session.documentStartedHandler = nil;
  if (session.browserIdentifier == _fullscreenBrowserIdentifier) [self exitBrowserFullscreen];
  [self devToolsVisibilityChanged:NO forBrowserIdentifier:session.browserIdentifier];
  [session.documentFooter stop]; session.documentFooter = nil;
  [session.navigationTransition stop]; session.navigationTransition = nil;

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
    [self closeBrowserOrKeepDownload:browser];
  }
}

- (void)closeBrowserInView:(NSView *)view {
  NSValue *containerKey = TLChromiumContainerKey(view);
  if (!containerKey) {
    return;
  }

  NSNumber *browserIdentifier = _browserIdentifiersByContainer[containerKey];
  TLChromiumBrowserSession *session = _sessionsByContainer[containerKey];
  [self devToolsVisibilityChanged:NO forBrowserIdentifier:session.browserIdentifier];
  if (browserIdentifier && browserIdentifier.integerValue == _fullscreenBrowserIdentifier) [self exitBrowserFullscreen];
  [_browserIdentifiersByContainer removeObjectForKey:containerKey];
  [session.documentFooter stop]; session.documentFooter = nil;
  [session.navigationTransition stop]; session.navigationTransition = nil;

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
    [self closeBrowserOrKeepDownload:browser];
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
  [_backgroundTimer invalidate]; _backgroundTimer = nil;
  _browserSettingsReady = NO;
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
  [TLBrowserDownloadManager.sharedManager finishSession];
  [_detachedDownloadContainers removeAllObjects];
  [_standaloneBrowserWindows removeAllObjects];
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
  [self applyBrowserPreferences];
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
        session.navigationTransition = [[TLChromiumNavigationTransition alloc] initWithBrowser:browser container:parentView];
      }
    }
    [self attachBrowserViewForBrowser:browser toContainerView:parentView];
    [self browserNavigationStateChanged:browser
                              canGoBack:browser->CanGoBack()
                           canGoForward:browser->CanGoForward()
                              isLoading:browser->IsLoading()];
    return;
  }

  // Resolve the native window while its CEF view is known to be alive. Keep
  // only a weak window reference; retaining CEF views prevents their teardown.
  NSWindow *window = [self windowForBrowser:browser];
  if (window) [_standaloneBrowserWindows setObject:window forKey:@(browser->GetIdentifier())];
}

- (void)showPageSourceForBrowser:(CefRefPtr<CefBrowser>)browser {
  NSString *URLString=TLNSStringFromCefString(browser->GetMainFrame()->GetURL());
  if (URLString.length==0) return;
  if (![URLString hasPrefix:@"view-source:"]) URLString=[@"view-source:" stringByAppendingString:URLString];
  [self createBrowserWithURLString:URLString parentView:nil];
}

- (void)savePageForBrowser:(CefRefPtr<CefBrowser>)browser {
  NSWindow *window=[self windowForBrowser:browser];
  NSString *name=TLNSStringFromCefString(browser->GetMainFrame()->GetURL());
  name=[NSURL URLWithString:name].host ?: @"Page";
  TLChromiumCapturePageArchive(browser, ^(NSData *archive, NSError *error) {
    if(error) { [NSApp presentError:error];return; }
    [self presentPageArchive:archive suggestedName:name fromWindow:window];
  });
}

- (NSSavePanel *)pageSavePanel { return [NSSavePanel savePanel]; }

- (void)presentPageArchive:(NSData *)archive suggestedName:(NSString *)name fromWindow:(NSWindow *)window {
  [self choosePageArchiveURL:name fromWindow:window completion:^(NSURL *URL) {
    if(!URL)return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
      NSError *error=nil;
      if (![archive writeToURL:URL options:NSDataWritingAtomic error:&error])
        dispatch_async(dispatch_get_main_queue(),^{[NSApp presentError:error];});
    });
  }];
}

- (void)choosePageArchiveURL:(NSString *)name fromWindow:(NSWindow *)window completion:(void (^)(NSURL *))completion {
  NSSavePanel *panel=[self pageSavePanel];
  panel.title=@"Save Page As";
  panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"mhtml"] ?: UTTypeData];
  panel.nameFieldStringValue=[name stringByAppendingPathExtension:@"mhtml"];
  panel.canCreateDirectories=YES;
  void (^responseHandler)(NSModalResponse)=^(NSModalResponse response) {
    [panel orderOut:nil];
    completion(response==NSModalResponseOK ? panel.URL : nil);
  };
  if(window.isVisible)[panel beginSheetModalForWindow:window completionHandler:responseHandler];
  else [panel beginWithCompletionHandler:responseHandler];
}

- (void)devToolsVisibilityChanged:(BOOL)visible forBrowserIdentifier:(NSInteger)identifier {
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(identifier)];
  if (!session || session.devToolsVisible == visible) return;
  session.devToolsVisible = visible;
  if (session.devToolsVisibilityChangedHandler) session.devToolsVisibilityChangedHandler();
}

// Alloy reports renderer fullscreen but leaves native presentation to the host.
// Move only the CEF view: the original window, split layout and footer stay intact.
- (void)browserFullscreenChanged:(CefRefPtr<CefBrowser>)browser fullscreen:(BOOL)fullscreen {
  if (!browser) return;
  TLChromiumBrowserSession *session = _sessionsByBrowserIdentifier[@(browser->GetIdentifier())];
  session.fullscreen = fullscreen;
  [session.navigationTransition cancel];
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

- (NSWindow *)browserWillClose:(CefRefPtr<CefBrowser>)browser {
  if (!browser) return nil;
  NSNumber *identifier = @(browser->GetIdentifier());
  NSWindow *window = [_standaloneBrowserWindows objectForKey:identifier];
  [_standaloneBrowserWindows removeObjectForKey:identifier];
  return window;
}

- (void)browserClosed:(CefRefPtr<CefBrowser>)browser {
  [self browserWillClose:browser];
  int identifier = browser ? browser->GetIdentifier() : -1;
  [TLBrowserDownloadManager.sharedManager browserClosed:identifier];
  [_detachedDownloadContainers removeObjectForKey:@(identifier)];
  if (identifier == _fullscreenBrowserIdentifier) [self restoreFullscreenBrowser];
  [self devToolsVisibilityChanged:NO forBrowserIdentifier:identifier];
  NSNumber *browserIdentifier = @(identifier);
  [_backgroundSince removeObjectForKey:browserIdentifier];
  [_pausedBrowsers removeObject:browserIdentifier];
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
    [session.navigationTransition stop]; session.navigationTransition = nil;
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
  if (!browser || !browser->IsValid() || title.length == 0) {
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

  // Embedded tabs can lose their handler before the final title notification.
  // Never fall back to their native handle: CEF can return a forwarding proxy
  // whose underlying view has already been destroyed.
  NSWindow *window = [_standaloneBrowserWindows objectForKey:browserIdentifier];
  window.title = title;
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
  [self stopFindingInSession:session];
  if (session.documentStartedHandler) session.documentStartedHandler();
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
  if (isLoading && session.documentGeneration > 0 && !session.fullscreen) [session.navigationTransition begin];
  else if (!isLoading) [session.navigationTransition finish];
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

- (TLBrowserLinkOpenHandler)contextLinkHandlerForBrowser:(CefRefPtr<CefBrowser>)browser {
  if (!browser || !browser->IsValid()) return nil;
  return _sessionsByBrowserIdentifier[@(browser->GetIdentifier())].contextLinkHandler;
}

- (void)openImageURL:(NSURL *)URL fromBrowser:(CefRefPtr<CefBrowser>)browser inNewWindow:(BOOL)newWindow {
  if (!TLBrowserImageURLIsSupported(URL)) return;
  NSValue *key = _containersByBrowserIdentifier[@(browser->GetIdentifier())];
  TLChromiumBrowserLinkHandler handler = nil;
  if (key) handler = _linkHandlersByContainer[key];
  if (!newWindow && handler) handler(URL, 0);
  else [self createBrowserWithURLString:URL.absoluteString parentView:nil];
}

- (BOOL)handleBrowserLinkURLString:(NSString *)urlString fromBrowser:(CefRefPtr<CefBrowser>)browser userGesture:(BOOL)userGesture {
  NSURL *url = [NSURL URLWithString:urlString];
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
  if (!browser || !browser->IsValid()) {
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

- (void)trackPermissionAlert:(NSAlert *)alert browser:(int)browserID prompt:(uint64_t)promptID {
  _permissionAlerts[[NSString stringWithFormat:@"%d:%llu",browserID,promptID]] = alert;
}
- (void)dismissPermissionAlertForBrowser:(int)browserID prompt:(uint64_t)promptID {
  NSString *key = [NSString stringWithFormat:@"%d:%llu",browserID,promptID];
  NSAlert *alert = _permissionAlerts[key]; [_permissionAlerts removeObjectForKey:key];
  TLChromiumDeferToMainRunLoop(^{ if (alert.window.sheetParent) [alert.window.sheetParent endSheet:alert.window returnCode:NSAlertFirstButtonReturn]; });
}
- (void)browserContextReady {
  _browserSettingsReady = YES;
  CefRequestContext::GetGlobalContext()->SetChromeColorScheme(_browserDarkAppearance ? CEF_COLOR_VARIANT_DARK : CEF_COLOR_VARIANT_LIGHT, 0);
  [self applyBrowserPreferences];
  _backgroundTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(checkBackgroundBrowsers) userInfo:nil repeats:YES];
  NSArray *callbacks = _settingsReadyCallbacks.copy;
  [_settingsReadyCallbacks removeAllObjects];
  for (void (^completion)(NSError *) in callbacks) completion(nil);
}
- (void)prepareBrowserSettingsInWindow:(NSWindow *)window completion:(void (^)(NSError *))completion {
  if (![self initializeCEFIfNeededFromWindow:window]) {
    completion([NSError errorWithDomain:@"Talaria.Browser" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The built-in browser could not start."}]); return;
  }
  if (_browserSettingsReady) completion(nil); else [_settingsReadyCallbacks addObject:[completion copy]];
}
- (NSDictionary *)browserSettingState:(NSDictionary *)setting {
  if (!_browserSettingsReady) return @{@"available":@NO,@"reason":@"The browser is still starting."};
  CefRefPtr<CefPreferenceManager> manager = [setting[@"scope"] isEqual:@"global"]
    ? CefPreferenceManager::GetGlobalPreferenceManager() : CefRequestContext::GetGlobalContext();
  NSString *path = [setting[@"scope"] isEqual:@"content"] ? [@"profile.default_content_setting_values." stringByAppendingString:setting[@"path"]] : setting[@"path"];
  auto key = TLStringFromNSString(path);
  if (!manager->HasPreference(key)) return @{@"available":@NO,@"reason":@"This option is unavailable in this version of Talaria."};
  auto pref = manager->GetPreference(key);
  std::string json = CefWriteJSON(pref, JSON_WRITER_DEFAULT);
  NSData *data = [NSData dataWithBytes:json.data() length:json.size()];
  id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
  if ([setting[@"scope"] isEqual:@"proxy"]) {
    NSString *field = @{@"proxyMode":@"mode",@"proxyServer":@"server",@"proxyPAC":@"pac_url",@"proxyBypass":@"bypass_list"}[setting[@"id"]];
    value = [value isKindOfClass:NSDictionary.class] ? value[field] : nil;
  }
  // Chromium's incognito-only cookie block has the same effect as Allow in Talaria's regular profile.
  if ([setting[@"id"] isEqual:@"thirdPartyCookies"] && [value isEqual:@2]) value = @0;
  if ([setting[@"id"] isEqual:@"preloading"] && [value isEqual:@1]) value = @0;
  return @{@"available":@(manager->CanSetPreference(key)),@"value":value ?: setting[@"default"],@"reason":@"This option is managed by the browser or a policy."};
}
- (BOOL)setBrowserSetting:(NSDictionary *)setting value:(id)value error:(NSError **)error {
  NSDictionary *canonical = [TLBrowserPreferences settingWithID:setting[@"id"]];
  if (!canonical || ![canonical isEqual:setting] || !_browserSettingsReady ||
      (value && ![TLBrowserPreferences.sharedPreferences validateValue:value forSetting:setting error:error])) return NO;
  CefRefPtr<CefPreferenceManager> manager = [setting[@"scope"] isEqual:@"global"]
    ? CefPreferenceManager::GetGlobalPreferenceManager() : CefRequestContext::GetGlobalContext();
  NSString *path = [setting[@"scope"] isEqual:@"content"] ? [@"profile.default_content_setting_values." stringByAppendingString:setting[@"path"]] : setting[@"path"];
  CefRefPtr<CefValue> pref;
  if (value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:error];
    if (!data) return NO;
    pref = CefParseJSON(data.bytes, data.length, JSON_PARSER_RFC);
  }
  if ([setting[@"scope"] isEqual:@"proxy"] && value) {
    auto current = manager->GetPreference("proxy");
    auto proxy = current && current->GetType() == VTYPE_DICTIONARY ? current->GetDictionary()->Copy(false) : CefDictionaryValue::Create();
    NSString *field = @{@"proxyMode":@"mode",@"proxyServer":@"server",@"proxyPAC":@"pac_url",@"proxyBypass":@"bypass_list"}[setting[@"id"]];
    proxy->SetString(TLStringFromNSString(field), TLStringFromNSString(value));
    std::string mode = proxy->GetString("mode");
    if ((mode == "fixed_servers" && proxy->GetString("server").empty()) || (mode == "pac_script" && proxy->GetString("pac_url").empty())) {
      if (error) *error = [NSError errorWithDomain:@"Talaria.Browser" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Save the proxy server or PAC URL before selecting that proxy mode."}]; return NO;
    }
    pref = CefValue::Create(); pref->SetDictionary(proxy);
  }
  CefString message;
  if (!manager->SetPreference(TLStringFromNSString(path), pref, message)) {
    if (error) *error = [NSError errorWithDomain:@"Talaria.Browser" code:2 userInfo:@{NSLocalizedDescriptionKey:TLNSStringFromCefString(message)}]; return NO;
  }
  return YES;
}
- (void)browserPreferencesChanged:(NSNotification *)notification {
  if (_browserSettingsReady) [self applyBrowserPreferences];
}
- (void)applyBrowserPreferences {
  if (!_browserSettingsReady) return;
  TLBrowserPreferences *preferences = TLBrowserPreferences.sharedPreferences;
  double zoom = log([[preferences localValue:@"zoom"] doubleValue] / 100.0) / log(1.2);
  for (auto browser : _browsers) {
    if (!browser->IsValid()) continue;
    TLChromiumApplyZoom(browser, zoom);
    browser->GetHost()->SetAccessibilityState([[preferences localValue:@"screenReader"] boolValue] ? STATE_ENABLED : STATE_DEFAULT);
  }
  [self checkBackgroundBrowsers];
}
- (void)checkBackgroundBrowsers {
  if (!_browserSettingsReady || _shuttingDown) return;
  TLBrowserPreferences *preferences = TLBrowserPreferences.sharedPreferences;
  BOOL enabled = [[preferences localValue:@"pauseBackground"] boolValue];
  NSTimeInterval delay = [[preferences localValue:@"pauseDelay"] doubleValue];
  for (auto browser : _browsers) {
    NSNumber *identifier = @(browser->GetIdentifier());
    NSView *container = _sessionsByBrowserIdentifier[identifier].containerView;
    BOOL hidden = container && (!container.window || !container.window.visible || container.hiddenOrHasHiddenAncestor);
    if (hidden && !_backgroundSince[identifier]) _backgroundSince[identifier] = NSDate.date;
    if (!hidden) [_backgroundSince removeObjectForKey:identifier];
    BOOL pause = enabled && hidden && -[_backgroundSince[identifier] timeIntervalSinceNow] >= delay;
    if (pause == [_pausedBrowsers containsObject:identifier]) continue;
    auto params = CefDictionaryValue::Create(); params->SetString("state", pause ? "frozen" : "active");
    browser->GetHost()->ExecuteDevToolsMethod(0, "Page.setWebLifecycleState", params);
    if (pause) [_pausedBrowsers addObject:identifier]; else [_pausedBrowsers removeObject:identifier];
  }
}
- (void)clearBrowserData:(NSString *)kind completion:(void (^)(NSError *))completion {
  if (!_browserSettingsReady) { completion([NSError errorWithDomain:@"Talaria.Browser" code:3 userInfo:@{NSLocalizedDescriptionKey:@"The browser is not ready."}]); return; }
  auto context = CefRequestContext::GetGlobalContext();
  if ([kind isEqual:@"cache"]) context->ClearHttpCache(new TLBrowserCompletion(completion));
  else if ([kind isEqual:@"cookies"]) {
    if (!context->GetCookieManager(nullptr)->DeleteCookies("", "", new TLBrowserCookieCompletion(completion)))
      completion([NSError errorWithDomain:@"Talaria.Browser" code:4 userInfo:@{NSLocalizedDescriptionKey:@"The browser could not delete cookies."}]);
  } else if ([kind isEqual:@"permissions"]) {
    CefString error;
    for (NSDictionary *setting in TLBrowserPreferences.catalogue) {
      if (![setting[@"scope"] isEqual:@"content"]) continue;
      NSString *path = [@"profile.content_settings.exceptions." stringByAppendingString:setting[@"path"]];
      if (context->HasPreference(TLStringFromNSString(path)) && !context->SetPreference(TLStringFromNSString(path), nullptr, error)) {
        completion([NSError errorWithDomain:@"Talaria.Browser" code:4 userInfo:@{NSLocalizedDescriptionKey:TLNSStringFromCefString(error)}]); return;
      }
    }
    context->ClearCertificateExceptions(new TLBrowserCompletion(completion));
  } else completion([NSError errorWithDomain:@"Talaria.Browser" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Unknown browsing data category."}]);
}

- (void)applyDarkAppearance:(BOOL)dark {
  _browserDarkAppearance = dark;
  if (!_browserSettingsReady) return;
  CefRequestContext::GetGlobalContext()->SetChromeColorScheme(
    dark ? CEF_COLOR_VARIANT_DARK : CEF_COLOR_VARIANT_LIGHT, 0);
}

- (NSURL *)browserURLFromURL:(NSURL *)url {
  return TLBrowserImageURLIsSupported(url) ? url : nil;
}

- (NSString *)chromiumCachePath {
  return TLBrowserPreferences.profileURL.path;
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
