#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

// Desktop launch completion precedes activation on some macOS releases. Wait
// for the real application state before exercising rendering or native input.
static inline void TLTestActivateWindowAtAttempt(NSWindow *window, NSUInteger attempt, dispatch_block_t completion) {
  if(attempt==0){NSLog(@"Desktop activation policy: %ld",(long)NSApp.activationPolicy);[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];}
  [window makeKeyAndOrderFront:nil];
  [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateAllWindows|NSApplicationActivateIgnoringOtherApps];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
    if(NSApp.isActive){completion();return;}
    if(attempt>=30){fprintf(stderr,"FAIL: desktop fixture could not activate its window (policy=%ld)\n",(long)NSApp.activationPolicy);exit(1);}
    TLTestActivateWindowAtAttempt(window,attempt+1,completion);
  });
}
static inline void TLTestActivateWindow(NSWindow *window, dispatch_block_t completion) {
  TLTestActivateWindowAtAttempt(window,0,completion);
}

// Execute against the actual page process. An exception is a failed fixture,
// never an empty result that could accidentally satisfy a negative assertion.
static inline void TLTestEvaluate(WKWebView *view, NSString *script, void (^completion)(id)) {
  [view evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
    if (error) { fprintf(stderr, "FAIL: JavaScript fixture: %s\n", error.localizedDescription.UTF8String); exit(1); }
    if (completion) completion(value);
  }];
}

static inline void TLTestScroll(WKWebView *view, CGFloat delta) {
  NSPoint point = [view convertPoint:NSMakePoint(MIN(500, NSWidth(view.bounds)/2), NSHeight(view.bounds)/2) toView:nil];
  CGEventRef native = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, (int32_t)-delta);
  CGEventSetIntegerValueField(native, kCGScrollWheelEventIsContinuous, 1);
  NSPoint screen = [view.window convertPointToScreen:point];
  CGEventSetLocation(native, CGPointMake(screen.x, NSMaxY(NSScreen.screens.firstObject.frame)-screen.y));
  NSEvent *event = [NSEvent eventWithCGEvent:native];
  NSView *target = [view hitTest:[view.superview convertPoint:point fromView:nil]] ?: view;
  [target scrollWheel:event];
  CFRelease(native);
}
