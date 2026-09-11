# Discrete mouse-wheel smoothing

## Implementation

Mouse-wheel smoothing is enabled by default. Browser Settings → Accessibility →
**Smooth mouse-wheel scrolling** disables it immediately and persists the choice.
Reduce Motion always bypasses smoothing, regardless of the saved preference.

`TLBrowserWheelSmoother` installs an AppKit local event monitor while its
`TLBrowserWebView` is attached to a window. It handles only non-precise, unphased,
non-momentum wheel input. Command, Control, Option, diagonal input and events
whose native window coordinates cannot be retained are forwarded unchanged.
Shift-wheel uses the horizontal axis already supplied by AppKit. No page scroll
API, CSS behavior, JavaScript wheel override or private WebKit hook is used.

`TLWheelScrollAnimation` emits 20% of each tick immediately, then eases the rest
with a 100 ms cubic ease-out. Repeated ticks merge into the pending tail. The
model accounts for cumulative displacement rather than accumulating frame errors;
native whole-point output carries its rounding remainder between bursts. Standard
integer wheel ticks preserve exact distance. Fractional inputs have a bounded
subpixel remainder, discarded on cancellation. On direction or target changes,
already accepted distance is settled at the old target before the new input starts,
so stale-direction frames do not follow the new input. This can make a rapid
reversal feel firmer than ordinary easing and needs hardware evaluation.

Each animation captures a native receiver and position and sends a precise
Began/Changed/Ended gesture directly to that receiver. WebKit owns DOM targeting,
scroll-node latching, cross-origin routing and `preventDefault`. Horizontal
synthesized gestures temporarily disable history swiping; the original setting is
restored before actual trackpad input is forwarded. A weak timer samples elapsed
time at up to 120 Hz and is invalidated when idle. There is no momentum tail.

Navigation (including URL changes within the same document), closing or detaching
a view, hiding a view or its ancestors, window deactivation/movement/resizing,
application deactivation, key/modifier/button actions, Reduce Motion changes and
disabling the setting cancel pending work. A main-loop stall longer than 250 ms
also cancels instead of replaying a delayed backlog. Cancellation intentionally
discards undelivered distance and ends the synthesized gesture.

## Compatibility limits

This is native event subdivision, not an engine-level animation of the original
wheel event. The user chose to proceed after the feasibility findings below.
Sites receive several smaller trusted wheel events instead of one large event.
`preventDefault` remains WebKit's responsibility, but event-count or per-event-delta
based site actions can behave differently. Gesture phases preserve a moving
nested scroll target, but also engage WebKit's gesture boundary propagation and
rubber-banding; these can differ from an ordinary wheel tick. Talaria cannot read
WebKit's resolved scrolling node, boundary state or cancellation result through
public macOS APIs. The opt-out restores the original native input path.

A device driver that labels already-smoothed input as coarse, unphased input cannot
be distinguished from an ordinary wheel through event metadata. Genuine precise
and momentum input bypasses the smoother. Physical mouse-wheel feel and actual
trackpad/Magic Mouse behavior require manual hardware checks; synthetic native
events and unit tests are not a substitute.

## Regression verification

Run on an unlocked macOS desktop with the normal signing identity:

```sh
make test-browser-smooth-scrolling
make test-browser-navigation
python3 Tests/run-browser-overlay-webkit.py --document-footer
```

The smoothing target runs displacement/eligibility unit tests and launches a signed
desktop fixture using the production controller and `TLBrowserWebView`. Public
AppKit mouse-event templates provide window metadata; public Quartz APIs convert
them into wheel events. `NSApplication.sendEvent:` exercises the production local
monitor. Events are never posted to other applications. JavaScript only resets
fixtures and observes native DOM events and positions.

The fixture covers long pages, nested vertical/horizontal panels, a moving panel,
a cross-origin iframe (`127.0.0.1` parent, `localhost` child), consuming wheel
handlers, repeated/reversed steps, Shift-wheel, precise/phase/momentum and modifier
bypasses, boundaries, preference changes, Reduce Motion and lifecycle cancellation.
Full traces are written to `build/BrowserSmoothScrollingResults.json`.
`BrowserSettingsTests` also checks default-on behavior and persisted opt-out.

The final September 11, 2026 run on macOS 27.0 (26A428), after integrating the
latest main-branch chat and build refactor, passed the full `make -j6 test` suite,
19 animation/eligibility checks, 31 desktop smoothing scenarios with 32 page
assertions, 33 navigation checks and 30 installed-Safari identity checks. Native
browser probes used their normal foreground mode on an unlocked desktop.
Settings persistence and the tab-layout regressions also passed. The signed
desktop build passed strict recursive code-signature verification.

All 106 document-footer rendering checks passed with smoothing enabled in the
normal desktop run. The five failures from the earlier inactive-window run did
not reproduce: opening/closing viewport animation, offscreen-extension sampling,
gradient readback and complex framed-banner edge capture all passed. No footer
production code was changed for this rerun. Physical hardware feel and actual
trackpad/Magic Mouse behavior remain unverified.

Momentum bypass is checked by pointer identity at `NSWindow.sendEvent:`: the
original event and metadata survive the local monitor unchanged. AppKit discards
the fixture's fabricated standalone momentum event downstream; this fixture does
not establish a real trackpad momentum sequence. Ordinary precise/phased input is
also checked through actual DOM events and final scroll positions.

## Changed files

| Files | Purpose |
| --- | --- |
| `Source/TLBrowserWheelSmoother.h`, `.m` | Native input filtering, routing, timer and cancellation |
| `Source/TLWheelScrollAnimation.h`, `.m` | Short, distance-preserving easing model |
| `Source/design_system/TLBrowserWebView.h`, `.m` | View ownership and lifecycle hooks |
| `Source/WebKitBrowserController.m` | Navigation and session-close cancellation |
| `Source/TLBrowserPreferences.m`, `Source/WebKitBrowserSettings.m` | Default-on setting, persistence and immediate application |
| `Tests/WheelScrollAnimationTests.m` | Displacement and event eligibility regression tests |
| `Tests/BrowserSmoothScrollingIntegration.mm`, `Scripts/test-browser-smooth-scrolling.py` | Real AppKit/WebKit regression fixture and assertions |
| `Tests/BrowserSettingsTests.m` | Default and persisted opt-out checks |
| `Tests/BrowserWebKitTestSupport.h`, `Tests/run-browser-overlay-webkit.py` | Explicit background desktop-test option; normal activation remains the default |
| `Makefile`, `Scripts/tests.mk` | Unit-test dependency and native smoothing test target |
| `docs/webkit-wheel-scrolling.md` | Approach, compatibility findings and verification limits |

## Earlier feasibility investigation

The following describes the baseline investigation before the implementation.

## Existing event path and API boundary

`TLBrowserWebView` subclasses `WKWebView` and customizes contextual menus. Before
smoothing was added, neither it nor `TLWebKitBrowserController` intercepted wheel
events. AppKit delivered them to WebKit's native content view; WebKit resolves the DOM target, dispatches the site's
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
actual Talaria desktop bundle from this worktree. This earlier investigation did not modify application source, `specs/` or
`README.md`. The subsequent smoothing implementation also leaves specs and README unchanged.

## What would remove the compatibility limits

Talaria would need an engine-level operation that eases default scrolling after
WebKit resolves the target and processes the site's original wheel handler, or
equivalent supported access to those decisions and the relevant scrolling node.
Sending the original event and then replaying smaller events cannot achieve this:
the original may already have scrolled, and replays are additional site events.
A page-scroll JavaScript override or WebKit fork remains outside this request.
