#import <AppKit/AppKit.h>
#include "include/cef_browser.h"

// Holds the last visible frame across an Alloy render-widget swap.
@interface TLChromiumNavigationTransition : NSObject
- (instancetype)initWithBrowser:(CefRefPtr<CefBrowser>)browser container:(NSView *)container;
- (void)begin;
- (void)finish;
- (void)cancel;
- (void)stop;
@end
