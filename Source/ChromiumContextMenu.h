#import <AppKit/AppKit.h>
#include "include/cef_context_menu_handler.h"
#import "TLBrowserLinkActions.h"

// Copies CEF's temporary menu model into a native menu before leaving its callback.
void TLChromiumShowContextMenu(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefMenuModel> model,
                              CefPoint location,
                              CefRefPtr<CefRunContextMenuCallback> callback);

void TLChromiumShowLinkContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefMenuModel> imageModel,
  NSURL *URL, BOOL canSplit, CefPoint location, CefRefPtr<CefRunContextMenuCallback> callback,
  TLBrowserLinkOpenHandler open);
