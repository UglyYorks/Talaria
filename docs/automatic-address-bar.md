# Automatic address-bar placement

Each browser tab owns a per-document placement policy. Visible fixed or
bottom-sticky content intersecting the address bar causes the page to reserve
space below its viewport. Two positive observations at least 150ms apart confirm
entry. Returning over the page requires two clear observations spanning at least
450ms, backed by a recent full scan. Unknown observations break confirmation and
preserve placement. Manual placement wins until navigation. SPA and fragment URL
changes preserve the current document’s policy.

A rapid reappearance after expansion latches the address bar underneath the page
until navigation, a material external resize, or a manual choice. The prospective
footprint is measured relative to the current viewport bottom in either mode.
Native dimensions are converted to CSS coordinates to account for page zoom.
Navigation, hidden tabs, resizing and placement settling invalidate stale results.
Only one placement request may be pending per tab.

## WebKit inspection

`TLWebKitPageBridge` runs the existing `BrowserOverlayProbe.js` in an isolated
`WKContentWorld`. `BrowserWebKitBridge.js` registers each frame through a
`WKScriptMessageHandler`, providing a public `WKFrameInfo` handle even for
cross-origin frames. These handles are discarded on navigation and frame pagehide.
The registry holds at most 128 frames.

Full scans sample at most 256 points and yield between animation frames after
about 3ms of work, with a bounded timer fallback when WebKit throttles animation
callbacks. Quick scans inspect at most three points: bottom center, a
remembered hit or alternating middle/top center, and one rotating point. The
bottom edge is always prioritized so short banners do not wait for a complete
sweep. A quick negative cannot independently certify clearance. A single browser
layout read cannot be preempted.

The bridge supplements those results with direct DOM hit tests at the fallback
points. It descends into a child frame only after validating that the visible frame
owner is anchored or fills its parent viewport. Coordinates remain in the owning
frame’s viewport, including when that document is scrolled. Frame transforms,
coverage and inherited fixed-position anchors are carried into child inspection.
An inaccessible, detached or unregistered eligible frame yields unknown.

On macOS 27 and later, the public `WKContentWorldConfiguration` option
`allowAccessingClosedShadowRoots` lets these scripts inspect closed shadow roots.
Earlier supported systems do not expose that capability, so closed-shadow
inspection is limited there. This is a WebKit API compatibility limit.

WebKit’s public DOM hit test respects `pointer-events`. A supplemental read-only
traversal looks for noninteractive painted panels, bounded to 256 elements and
about 3ms per fallback. It does not temporarily change the site’s styles. This is
a heuristic; arbitrary stacking arrangements and candidates outside the bounded
traversal can differ from engine-level hit testing. Tiny or short-lived controls
can also fall between sample points.

The final result is validated against the original viewport and scroll position.
The bridge times out individual JavaScript operations after four seconds, while
the sampled script abandons changed viewports and scans taking more than two
seconds. No screenshot or document archive is used for obstruction detection.

## Scheduling and native geometry

Quick checks start at 200ms intervals, scheduled from completion. Full scans have
a minimum interval of 1.5s. Each millisecond of measured JavaScript work adds 80ms
of idle to its lane, up to 120s. Unknown results use a three-second minimum delay.
Responsive pages target detection within 500ms; busy renderers and unsampled
controls cannot have a strict deadline.

When a quick check suggests dismissal while docked, the controller can bring a
full confirmation scan forward. Its cost extends the existing full-scan deadline;
another early confirmation waits until that debt is repaid. Manual choices and
the resize-feedback latch still win.

Automatic and manual transitions animate the real `WKWebView` height over the
theme-defined 200ms interval. A common-run-loop timer applies at most 60 absolute,
whole-point inset updates per second. WebKit reflows fixed content at each actual
viewport size. Monotonic easing avoids overshoot reflows. Reversals start at the
current committed inset, cancellation rejects old callbacks, and Reduce Motion
switches immediately. No transform stretches the page image.

Live window resizing pauses inspection and color capture. Sampling resumes at the
settled viewport. A clipping host and separate shadow outline apply the existing
theme radius and content-shadow tokens to the raised page. Decoration follows the
committed inset and returns to square corners without a shadow when closed.

## Address presentation

An unfocused address shows only the host, without a leading `www.`, centered and
truncated before it overlaps controls. Focus moves the domain to the text area’s
left edge and reveals the full URL for editing and copying. URL editing stays on
one line with horizontal scrolling. Navigation preserves unsent task drafts and
focused edits. Escape restores the latest page’s domain. Reduce Motion disables
the presentation animation.

## Document scroll extension

Two exclusive spaces use the address-bar height plus theme footer spacing:

- A document spacer extends the page’s real scrollable height while the native
  footer is closed. WebKit owns wheel input, trackpad inertia, keyboard scrolling
  and scrollbar dragging. Scrolling does not open the native footer.
- The native footer opens from the address-bar button or confirmed fixed content.
  The document spacer is removed before the height animation begins and restored
  only after closing finishes. Generation guards discard superseded callbacks.

`BrowserDocumentFooter.js` installs an inert, aria-hidden spacer outside the body
at the end of its flow content. It preserves flex/grid layout, excludes itself
from measurements, and converts native dimensions to CSS pixels. It does not write
the scroll position or remove a visible spacer just to measure the document.
Quirks-mode documents use body/root flow bounds to avoid counting the viewport as
content. Scroll-locked roots, fixed bodies and unmeasurable out-of-flow content
retain their original scroll range.

Body/root resize and structural observers coalesce changes to at most five
refreshes per second. At most 32 relevant bottom elements are watched for size or
attribute changes. There are no wheel listeners, synthetic momentum, per-scroll
native messages or scrolling-driven viewport resizes. A passive scroll timestamp
only postpones expensive pixel captures.

## Content colors

The native footer continues the visible page’s bottom-edge color; the selected
tab uses the visible top edge, including fixed headers. The address-bar controls
and surrounding chrome retain their theme colors. Failure uses
`palette.tabBackground`. The selected tab’s label and template icons use the
existing higher-contrast theme ink; favicons retain their own colors.

`BrowserFooterColor.js` reads five points per edge in the bridge’s isolated world.
It combines transparent ancestor backgrounds and chooses a consistent dominant
color, with 96 style reads and approximately 3ms of synchronous work per edge.
Complex painted content such as images, gradients, frames, canvas and
pseudo-elements requests rendered pixels. Exceeding the CSS budget defers the
sample. These checks use the existing tab timer and measured-cost backoff.

Top and bottom edges share one `takeSnapshotWithConfiguration:` capture of the
existing viewport. This public WebKit API does not resize the live web view.
The image is encoded as PNG and processed on a utility queue. Sampling crops the
12 image pixels above the relevant edge and reduces them to a dominant sRGB
color. Captures are bounded to 32 Mi physical pixels, and the content-color
image decoder accepts at most 8 MiB of encoded data. Individual bridge operations
and snapshot callbacks have four-second deadlines.

Captures require at least 150ms of scroll inactivity and the controller enforces
a minimum one-second capture interval that increases with measured latency.
Viewport, scroll, generation and footer-edge changes reject stale pixels. Weak
DOM identities and sampled styles allow stable colors to be cached without
retaining removed nodes. Dynamic opaque content keeps the throttled fallback.
Hidden tabs, fullscreen and active resizing do not capture.

The native footer and selected tab animate accepted changes using the existing
footer-color duration. Hidden or opening surfaces apply their initial color
immediately. Button/automatic opening requests a fresh sample before the height
animation, with a 150ms deadline that uses the warm color when the renderer is
busy. Theme changes update fallback surfaces without overwriting content colors.

## Independent extension and banner colors

The document spacer determines its own color from the document end before that
edge scrolls into view. A bounded reverse traversal excludes fixed/sticky banners,
composites transparent layers and resolves ordinary vertical-gradient endpoints.
It follows visible overflow while respecting actual paint clips. Unpainted
backgrounds use the browser’s Canvas color and the document’s color scheme.
A one-CSS-pixel ink overlap covers fractional seams without changing scroll range.

Canvas and CSS background-image backdrops have a rendered-pixel fallback once the
artwork bottom is visible and scrolling is quiet. The shared snapshot is cropped
to a two-pixel-high strip; 32 sRGB colors continue the artwork down the spacer.
Source, geometry, style and footer-mode changes invalidate the strip. Fixed
overlays block capture, and canvas animation alone does not force continuous
readback. No pixels are sent outside Talaria. Modern CSS colors are converted
through a cached 1×1 CPU-backed canvas; this converts colors without reading page
pixels.

A positive obstruction can also describe a broad banner’s own background and a
sample line inside its lower edge. At least 65% viewport coverage is required.
Solid colors avoid capture; complex banners use the same bounded snapshot path.
Frame scale and coverage are translated back to the main viewport. Banner
generations reject unrelated samples, unknown observations preserve its color,
and confirmed dismissal releases ownership. The document spacer remains
independent of the native banner color.

## Viewport applications and fullscreen

Top-level, non-scrolling canvas applications can return `viewport-app` when
application semantics or a Flutter host accompany a canvas covering most of the
viewport. Ordinary backgrounds, videos and embedded maps do not qualify.
Full-height flex/grid applications can return `viewport-layout` for a real text
or control hit near the bottom of an explicitly scroll-locked document. Local
scroll/clipping containers and ordinary flowing footers are excluded. Both rules
reuse sampled points and bounded ancestor reads.

WebKit owns HTML/video/frame fullscreen and native presentation. The session
tracks `WKWebView.fullscreenState`, disables the document spacer and pauses footer
inspection during fullscreen. Exit restores the existing pane and footer layout.
The controller closes media presentations on navigation, tab close and application
deactivation. Talaria does not simulate fullscreen with page CSS.

## Validation

`make test` includes native placement/controller tests and JavaScript layout
fixtures. The JavaScript fixtures still use installed Chrome/Chromium as an
independent test engine; Node 22+ is required and `CHROME_BIN` selects the executable.
This test dependency is separate from Talaria’s WebKit runtime.

`python3 Tests/run-webkit-page-bridge.py` builds a disposable desktop app in the
worktree. It checks fixed and closed-shadow banners, noninteractive banners,
cross-origin frames, a 20,000-node clear page, exact top/bottom gradient pixels,
Readability, find counts across split text and frames, find navigation/cancellation,
and document scroll extension.

`python3 Tests/run-browser-overlay-webkit.py` runs the complete browser/tab bridge
in an isolated desktop app and profile. Its `--document-footer`, `--fullscreen`
and `--devtools` modes cover scroll geometry, native wheel input, rapid height
reversals, source windows, inspector lifecycle and fullscreen restoration.
Results are recorded under `build/Browser*WebKitResults.json`. The original
JavaScript fixtures also cover visibility, positioning, zoom, dismissals,
viewport applications, color caching and stale replies. Test results from the
previous engine are not evidence of a current WebKit pass.
