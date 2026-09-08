#import "TLBrowserImageActions.h"
#include "include/cef_browser.h"
#include "include/cef_menu_model.h"
static const int TLChromiumImageCommandFirst = MENU_ID_USER_FIRST + 20;
void TLChromiumPopulateImageMenu(CefRefPtr<CefMenuModel> model, NSString *URLString, BOOL hasImage);
void TLChromiumReadImage(CefRefPtr<CefBrowser> browser, NSURL *URL, NSString *frameURL,
                        void (^completion)(TLBrowserImageResource *, NSError *));
