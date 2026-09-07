#import <Foundation/Foundation.h>
#include "include/cef_browser.h"

void TLChromiumCapturePageArchive(CefRefPtr<CefBrowser> browser,
                                 void (^completion)(NSData * _Nullable archive, NSError * _Nullable error));
