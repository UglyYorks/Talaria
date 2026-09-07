#import <Foundation/Foundation.h>
#import "TLBrowserOverlayPolicy.h"
#import <math.h>
static void Check(BOOL value, NSString *message) { if (!value) { NSLog(@"FAIL: %@",message);exit(1); } }
int main(void) { @autoreleasepool {
  TLBrowserOverlayPolicy *p=[TLBrowserOverlayPolicy new];
  [p updateContentSize:NSMakeSize(1000,700)];
  Check(![p observe:@YES atTime:0] && ![p observe:@YES atTime:0.1],@"brief overlap does not dock");
  Check([p observe:@YES atTime:0.2] && p.reducedHeight,@"confirmed obstruction docks within the next quick interval");
  Check(![p observe:@NO atTime:1] && ![p observe:@NO atTime:1.44],@"clearance is debounced");
  Check([p observe:@NO atTime:1.46] && !p.reducedHeight,@"confirmed clearance returns promptly to overlay");
  [p observe:@YES atTime:3];
  Check([p observe:@YES atTime:3.3] && p.latchedReducedHeight,@"resize feedback latches safely under");
  [p observe:@NO atTime:4];[p observe:@NO atTime:6];
  Check(p.reducedHeight,@"clear responsive viewport cannot perpetuate switching");
  [p updateContentSize:NSMakeSize(1001,701)];Check(p.latchedReducedHeight,@"tiny geometry jitter preserves latch");
  [p updateContentSize:NSMakeSize(1009,700)];Check(!p.latchedReducedHeight,@"real outer resize releases latch");
  [p observe:@NO atTime:7];Check([p observe:@NO atTime:9],@"fresh clearance after resize restores overlay");
  [p setManualReducedHeight:YES];
  [p observe:@NO atTime:10];[p observe:@NO atTime:20];Check(p.reducedHeight && p.manuallyOverridden,@"manual choice wins");
  [p setManualReducedHeight:NO];[p observe:@YES atTime:21];[p observe:@YES atTime:23];Check(!p.reducedHeight,@"manual overlay also wins");
  [p resetForNavigation];Check(!p.manuallyOverridden && !p.reducedHeight,@"navigation resets manual state");
  [p observe:@YES atTime:30];[p observe:nil atTime:30.1];Check(![p observe:@YES atTime:31],@"unknown breaks evidence");
  Check([p observe:@YES atTime:31.4],@"fresh confirmation resumes");
  [p observe:@NO atTime:32];[p observe:nil atTime:33];Check(![p observe:@NO atTime:34],@"failure cannot certify continuous clearance");
  Check(![p observe:@NO atTime:33.5],@"stale samples ignored");
  Check([p observe:@NO atTime:35.5],@"new clearance succeeds");
  [p resetForNavigation];[p observe:@YES atTime:40];Check(![p observe:@YES atTime:53],@"long suspension breaks confirmation");
  [p observe:@YES atTime:NAN];Check(![p observe:@YES atTime:54],@"invalid time breaks evidence");
  Check([TLBrowserOverlayPolicy quickDelayForCostMS:1 known:YES]==0.2,@"cheap page cadence");
  Check([TLBrowserOverlayPolicy quickDelayForCostMS:10 known:YES]==0.8,@"fast cadence still obeys the same measured CPU budget");
  Check([TLBrowserOverlayPolicy delayForCostMS:100 known:YES]==8.0,@"expensive scans charge eight seconds idle");
  Check([TLBrowserOverlayPolicy delayForCostMS:1 known:NO]>=3,@"failed scans back off");
  Check([TLBrowserOverlayPolicy delayForCostMS:NAN known:YES]>=3,@"invalid cost is safe");
  Check([TLBrowserOverlayPolicy delayForCostMS:200 known:NO]==16.0,@"unfinished expensive scans also charge their work");
  [p resetForNavigation];p.observationInterval=10;
  [p observe:@YES atTime:60];Check([p observe:@YES atTime:70],@"slow observations can confirm obstruction");
  [p observe:@NO atTime:80];Check([p observe:@NO atTime:90],@"slow complete clear scans can restore overlay");
  p.observationInterval=0.3;
  [p observe:@YES atTime:100];Check([p observe:@YES atTime:100.3] && p.latchedReducedHeight,@"feedback grace includes the previous slow scan interval");
  Check([TLBrowserOverlayPolicy delayForCostMS:400 known:YES]==32,@"very large pages retain the CPU duty-cycle budget");
  NSLog(@"BrowserOverlayPolicyTests passed");
} return 0; }
