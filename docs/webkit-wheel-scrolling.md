# Discrete mouse-wheel smoothing: native WebKit feasibility

## Status

The requested smoothing feature is not implemented. The native experiment found
incompatibilities with wheel-consuming sites, target retention and boundary
behavior. No application event interception, animation timer or browser preference
was added. The existing native WebKit input path is unchanged.

This follows the requirement to report a concrete WebKit limitation instead of
shipping a workaround that silently breaks those cases. A smoothing curve and
lifecycle cancellation alone would not resolve the routing problem.

## Existing event path and API boundary

`TLBrowserWebView` subclasses `WKWebView` and customizes contextual menus. Neither
it nor `TLWebKitBrowserController` intercepts wheel events. AppKit delivers them to
WebKit's native content view; WebKit resolves the DOM target, dispatches the site's
wheel event and performs the default scrolling internally.

The public macOS `WKWebView` API exposes neither the resolved DOM scroll target
nor the result of a site's wheel-event cancellation. Its `scrollView` property is
inside `#if TARGET_OS_IPHONE` in the installed SDK; it is not a macOS `NSScrollView`
whose document offset Talaria can animate. Keeping a reference to the native
content view does not identify a nested DOM scroller or a scroller in another
origin.

AppKit's `hasPreciseScrollingDeltas`, `phase` and `momentumPhase` provide the input
metadata needed to distinguish discrete ticks from precise/gesture input. They
do not provide control over WebKit's default scroll animation. A device that
reports already-smoothed input as coarse, unphased events cannot be distinguished
from a discrete wheel using that metadata alone.

Upstream WebKit's macOS wheel handler calls `immediateScrollBy` for ordinary wheel
input. The general smooth-wheel-animation path is compiled for non-Mac platforms.
WebKit's wheel-target latching uses gesture phases; unphased wheel events do not
establish the same gesture latch. In the native experiment, setting
`NSScrollAnimationEnabled` and enabling WebKit's private `ScrollAnimatorEnabled`
feature still produced a single step, without intermediate positions. The private
feature is tested only in the disposable probe application.

Sources inspected on September 11, 2026:

- [Apple NSEvent documentation](https://developer.apple.com/documentation/appkit/nsevent)
- [Apple WKWebView documentation](https://developer.apple.com/documentation/webkit/wkwebview)
- [WebKit macOS scrolling effects](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/mac/ScrollingEffectsController.mm)
- [WebKit cross-platform scrolling effects](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/ScrollingEffectsController.cpp)
- [WebKit wheel-event latching decisions](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/PlatformWheelEvent.h)
- [WebKit scrolling-tree latching](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/scrolling/ScrollingTreeLatchingController.cpp)

## Reproduction

From the WebKit worktree, on an unlocked desktop with the normal signing identity:

```sh
make test-browser-wheel-routing
```

The target builds and launches a signed desktop probe using Talaria's real
`TLWebKitBrowserController`, session and `WKWebView`. It serves disposable local
fixtures and uses a temporary browser profile. The iframe origin is `localhost`;
the parent origin is `127.0.0.1`. Neither production browsing data nor application
preferences are changed.

Input is delivered through native `CGEvent`/`NSEvent` objects and `scrollWheel:`.
JavaScript sets up fixtures and reads DOM events/positions; it does not simulate
the measured scroll input. All slices of each experiment retain the same native
receiver and coordinates. Page callbacks record trusted wheel events and
`requestAnimationFrame` records position changes. Full observations are written
to `build/BrowserWheelRoutingWebKitResults.json`.

Three approaches are compared:

1. One unmodified three-line wheel event, which WebKit translates to 120 pixels
   on the tested system.
2. Fifteen precise eight-pixel events, spaced approximately eight milliseconds
   apart, without gesture phases.
3. The same subdivision with Began/Changed/Ended gesture phases to engage latching.

Subdivision is an experiment, not an easing implementation. Its constant slices
make distance and routing failures easy to reproduce. Choosing a different easing
curve does not preserve the original site's single wheel event.

## Observed results

Tested on Apple silicon, macOS 27.0 (26A428), September 11, 2026.

| Fixture | Original native wheel | Subdivided events | Subdivision with gesture phases |
| --- | --- | --- | --- |
| Site prevents scrolling and takes an action for a delta of at least 40 pixels | One event, one action, no scrolling | 15 events, zero actions | 15 events, zero actions |
| Nested panel moves out from under the pointer in its first wheel handler | Panel scrolls 120; page stays still | Panel scrolls 8; page scrolls 112 | Panel scrolls 120; page stays still |
| Panel starts at its lower boundary | Page stays still | Page stays still | Page scrolls 120 |
| Panel starts 16 pixels before its lower boundary | Panel reaches boundary; page stays still | Panel reaches boundary; page scrolls 104 | Panel rubber-bands about 8 pixels beyond the boundary before returning |

The animator-feature experiment observed positions of 0 and 120, with no
intermediate scroll positions. This is a frame-sampled observation, not a timing
or hardware-feel measurement.

The suite exercises 23 native scenarios and checks 13 baseline contracts,
including total distance, rapid repeated input, reversal, horizontal input,
Shift-wheel, Control-wheel delivery, precise input, momentum metadata, nested
panels, a cross-origin iframe and `preventDefault`. Experimental comparisons are
reported as observations rather than asserting that a particular WebKit defect
must remain present in future OS versions. A passing probe does **not** mean that
smoothing was implemented or passed acceptance testing.

The existing desktop navigation suite passed all 33 checks and the document-footer
suite passed all 106 checks. `make build` completed through the native probe target,
strict recursive code-signature verification passed, and `make run` launched the
actual Talaria desktop bundle from this worktree. Application source, `specs/` and
`README.md` are unchanged by this investigation.

## What would unblock the feature

Talaria needs an engine-level operation that eases the default scroll after
WebKit has resolved the target and processed the site's wheel handler, or
equivalent supported access to those decisions and the relevant scrolling node.
Sending the original event and then replaying smaller events cannot achieve this:
the original may already have scrolled, and the replays are additional site events.
Turning wheel input into a fabricated gesture changes native behavior as shown
above. A page-scroll JavaScript override or WebKit fork is outside this request.

Because no smoothing implementation is shipped, its preference, immediate
disable/Reduce Motion behavior, animation-idle behavior and lifecycle-cancellation
tests remain unimplemented. There is no pending Talaria wheel animation to cancel.
Physical mouse-wheel feel and real trackpad/Magic Mouse behavior still require
manual hardware checks; native synthesized input is not a substitute for those.
