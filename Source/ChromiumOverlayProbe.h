#import <Foundation/Foundation.h>
#include "include/cef_browser.h"

// UI-thread entry. The completion is always delivered on the main run loop.
void TLChromiumProbeOverlay(CefRefPtr<CefBrowser> browser, NSString *source, NSDictionary *geometry,
                           void (^completion)(NSDictionary *result));
