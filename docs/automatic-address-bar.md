# Automatic address-bar placement

The browser tab owns a per-document policy. Visible fixed/bottom-sticky content
intersecting the address bar causes the page to reserve space below its viewport.
Two positive observations, at least 150ms apart, confirm entry. Returning over the
page requires two clear observations spanning at least 450ms, backed by a full
scan from the last 3s.
Unknown observations break confirmation and preserve placement. A manual toggle
wins until a new main-frame document commits; SPA/fragment URL changes do not
reset it. A separate document spacer extends the page’s native scroll range when the native footer is closed. A rapid reappearance after expansion latches the bar underneath until
navigation, a material external resize, or a manual choice.

Native hit tests add the owning frame’s scroll offset to viewport points, including
scrolled cross-origin frames. JavaScript classification keeps viewport coordinates.

The prospective footprint is measured relative to the current viewport bottom
in both modes. Native geometry is converted to CSS coordinates for page zoom.
A new document, hidden tab, resize, or placement settling invalidates stale
results. New documents also reset the previous document's adaptive quick-check
interval. Only one request can be pending per tab.
Cheap checks run at 200ms intervals, scheduled from completion rather than rounded
up to a later timer tick. This targets detection within 500ms on responsive pages;
automatic placement animates the real viewport height for 200ms without scaling content. Expensive pages retain adaptive backoff,
so blocked renderers and unsampled small controls cannot have a strict deadline.

## Inspection and performance

- No DOM-wide queries, persistent page observers, style changes, screenshots, or
  document snapshots. All JavaScript runs in an isolated world.
- Full scans sample at most 256 points. Work yields between animation frames after
  about 3ms; inexpensive scans avoid unnecessary frame waits. A single browser
  layout/hit test cannot be preempted.
- Quick scans inspect at most three points: bottom-center, a remembered hit (or
  alternating middle/top center), and one rotating sample. Shallow full-width
  banners are detected on the first pass. Quick checks continue while costly full
  scans cool down. A quick negative cannot independently certify clearance.
- When a quick check first suggests dismissal while docked, it can bring one full
  confirmation scan forward to the next timer tick. Its cost extends the existing
  full-scan deadline, and another early confirmation is forbidden until that debt
  is repaid. This avoids waiting out a long cooldown without increasing sustained
  full-scan frequency. Manual choices and the resize-feedback latch still win.
- Full scans add at most three browser-level hit tests; quick scans use one, or two
  when a distinct previous hit is remembered. These pierce closed shadow
  roots and include `pointer-events:none` content. Cross-origin inspection follows
  only eligible hit-tested frame owners and releases its objects/sessions.
  The bottom-center point is included on every pass, alongside a remembered hit
  and rotating samples, so shallow centered banners inside opaque content do not
  have to wait for a full sweep.
- Full and quick scans have independent work budgets. Each millisecond of
  measured JavaScript work buys 80ms idle in its budget;
  the minimum intervals are 1.5s full and 200ms quick. Failed/unfinished scans also
  pay for their work. Maximum idle is 120s. Native hit tests receive a 1ms work
  allowance each, including failed requests. Their reply latency is recorded
  separately: IPC/renderer queueing must not become several seconds of cooldown.
  The JavaScript budget targets about 1.25% of one core per lane; native work is
  bounded by query counts and this allowance, not an exact measured CPU ceiling.
- Failed opaque inspection backs off for 3s independently. A result invalidated
  by scrolling or viewport movement is discarded without marking the opaque
  inspector as failed. Completed DOM checks
  continue at their cost-adjusted quick cadence during that cooldown. Skipping
  opaque inspection yields unknown, never clearance. A failure before completing
  the DOM scan still incurs the original 3s minimum quick backoff.
- Requests stop after 40 protocol commands or 4s. JavaScript yields/abandons a
  changed viewport and stops a scan after 2s wall time. Hidden/closed tabs and
  manual overrides perform no page inspection.

Sampling is a heuristic: tiny or briefly appearing controls can fall between
samples. Ordinary flow content and fullscreen app shells are excluded. Frame
contents count only where the frame is anchored or fills the parent viewport.
Unsupported/detached frame inspection is unknown, never proof of clearance.

Fullscreen frames preserve a verified outer fixed-position anchor when inspecting
their contents, including across process/origin boundaries. This covers Guardian's
Sourcepoint banner: a fixed outer container holds a fullscreen iframe whose bottom
panel is absolutely positioned. The inherited anchor only qualifies bounded,
painted bottom panels in a non-scrolling viewport layout. Local containing blocks,
scrolling document footers and ordinary fullscreen frames do not gain an anchor.
The proof is recomputed per inspection using cached, bounded ancestor reads and
passed with the frame hit coordinates. Native hits that jump into a same-process
child first resolve and verify its frame owner; inspection then stays in the
existing target. Separate-process frames retain their scoped target attachment.
Native hit coordinates remain relative to that target while classification uses
child viewport coordinates. Metadata traversal is capped at 128 frames and the
existing 40-command request cap remains. No polling is added. An empty fullscreen
overlay still does not count as an obstruction.

Guardian regression coverage includes same-origin, same-site cross-origin and
separate-process frames, nested closed shadows, dismissal, zoom, and negative
scrolling/local-container cases. The live-page desktop check on 2026-09-06 confirmed
placement 319ms after its first positive probe and finished animating at 520ms;
these are confirmation/animation timings, not a measurement from banner paint.

## Validation

`make test` includes native policy/controller regressions and real Chrome layout
fixtures. The browser fixtures require Node 22+ and Chrome/Chromium; `CHROME_BIN`
selects an alternate executable. They cover visibility, fixed/sticky positioning,
shadow roots, frames, zoom, dismissal, navigation, and a 20,000-node stress page.

`python3 Tests/run-browser-overlay-cef.py` additionally exercises the actual CEF
transport as a desktop test app from this worktree. It uses an isolated temporary
profile, leaves user app data alone, and records timing in
`build/BrowserOverlayCEFResults.json`. It catches synchronous DevTools callbacks
that a WebSocket-only harness cannot reproduce.
It also times late banner appearance through the real tab controller and native
height layout: six normal/closed-shadow cases at varied timer phases and one
20,000-node page. The responsive-page detection target is 500ms, with native
layout settling within one second. The stress case allows its measured adaptive
quick-check cooldown plus 750ms for confirmation and visual settling, rather than a fixed deadline
that would contradict the CPU budget on a busy renderer.
The desktop harness also switches the bar over/below the page in 24 bursts of
three rapid toggles, counts page resize events, and
checks that native subviews continue to fill their parent, the fixed footer
meets the page viewport bottom, and neither mode accumulates geometry drift.
The fixture includes a fractional-point host height and a layer-backed parent.
Each automatic/manual toggle animates the actual webview height, so Chromium
reflows the page and moves fixed-bottom content together with the footer edge.
Chromium’s internal compositor container rounds fractional size deltas, even on
Retina displays. Half-point steps accumulate a growing blank strip while NSView
and DOM viewport bounds remain correct. Use whole AppKit-point inset steps;
desktop regressions also check the internal compositor bounds after each toggle.

A common-run-loop timer applies at most 60 absolute, whole-point inset updates
per second for the short theme-defined transition. Monotonic easing avoids an
overshoot reflow. No transform, snapshot or clipping mask stretches the old page.
Delayed frames jump to elapsed time without queuing resize work. Reversals start
at the current committed inset; cancellation discards old completion callbacks.
Window resizing cannot accumulate deltas, and Reduce Motion switches immediately.
Color sampling/capture and obstruction checks pause during live resizing, then
resume at the settled viewport. The document spacer remains removed throughout
native opening/closing and returns only after closing completes. Tests record
multiple renderer viewport sizes, fixed-element alignment, stable glyph sizes,
rapid reversals, bounded updates, cancellation and exact final geometry.

## Address presentation

An unfocused address shows only the host, without a leading `www.`, centered in
the bar and truncated before it overlaps controls. Focus moves that domain to
the text area's left edge and reveals the original full URL for editing and
copying. Reduce Motion switches immediately. URL editing stays on one line with
horizontal scrolling, so long URLs cannot change the footer height. The same
component still supports multiline task drafts; navigation updates preserve
unsent drafts and focused edits. Escape restores the latest page's domain.

## Document scroll extension

There are two mutually exclusive spaces, both the measured address-bar height
plus the theme’s footer spacing:

- A document spacer extends the page’s real scrollable height while the native
  footer is closed. Chromium handles wheel input, trackpad inertia, keyboard
  scrolling and scrollbar dragging. Scrolling never opens the native footer.
- The native footer still opens from the address-bar button or confirmed fixed
  bottom content. The renderer acknowledges removal of the document spacer before
  the native height animation starts. The spacer returns only after the native
  closing animation finishes. Generation guards discard superseded callbacks.

The inert, aria-hidden spacer is absolutely positioned outside the body, at the
end of its flow content. It does not change body flex/grid layout. Its size uses
native points converted to CSS pixels. Measurements exclude the spacer itself;
updates never temporarily remove a visible spacer to measure scroll height or
write the scroll position. Repeated toggles therefore cannot accumulate padding.

Body/root ResizeObservers and a structural MutationObserver coalesce layout
changes to at most five refreshes per second. Root/body attributes and at most 32 bottom-content elements are observed;
unrelated descendant attribute churn is ignored. There are no
whole-document scans, wheel listeners, synthetic momentum, bottom-position
tracking, per-scroll native IPC, or scrolling-driven viewport resizes. A passive
scroll timestamp only postpones expensive color captures.

Quirks-mode pages (including Hacker News) use body/root flow bounds instead of
body.scrollHeight, which aliases the viewport and would include our spacer.

Scroll-locked roots, fixed bodies and layouts whose scrollable
content extends beyond the measurable document flow retain their original scroll
range. This avoids covering out-of-flow content or creating a second scrollbar
around an embedded app. Native manual/banner placement remains available.

`Tests/BrowserDocumentFooterTests.mjs` exercises real Chromium scroll geometry,
short pages, flex layouts, dynamic growth/shrink/replacement, zoom conversion,
scroll locks, repeated switches and color sampling above the spacer.
`python3 Tests/run-browser-overlay-cef.py --document-footer` runs a separate desktop
app/profile to verify the production bridge, native wheel scrolling, equal-height
exclusive modes, 24 repeated/rapid toggle cycles, navigation and fixed-banner
placement. Results are saved to `build/BrowserDocumentFooterCEFResults.json`.

## Page-matched footer background

A dedicated content-extension surface beneath the webview continues the color of
its visible bottom edge. Address-bar glass, controls and surrounding chrome retain
the theme. The default/failure surface uses `palette.tabBackground`. Samples are
applied immediately while hidden and during opening. Once open, changes crossfade
from the currently displayed color, independently of the footer geometry. The
sampled RGB conversion is isolated in `TLBrowserContentColor` and documented as a
content-derived allowance in the theme audit.

The existing isolated world reads five points near the viewport bottom, combining
transparent ancestor backgrounds and selecting a consistent dominant background.
Style data is reused within the request, with a 96-step bound and a roughly 3ms
synchronous work budget. Exceeding the budget defers the sample instead of escalating to an
expensive capture. Images, gradients, opaque frames and painted pseudo-elements
request rendered pixels. No whole-document traversal, DOM edits or mutation observer
is added.

Color checks share the existing 200ms tab timer, including while the footer is
closed, and back off with measured CSS cost. Hidden tabs and windows do no work.
CSS reads remain available during scrolling. The native footer excludes the
document spacer from its sampling: the sample line follows the content edge
immediately above it. Native samples never set the document spacer color.
Button/automatic opening requests a fresh sample before starting the height
animation, with a 150ms deadline using the warm color if the renderer is busy.
Captures require 150ms of scroll inactivity and have a minimum one-second cooldown that grows
with measured capture latency. Capture reads the existing viewport with no CDP
`clip`, scale override or capture beyond the viewport. The 12 image pixels above the content edge
are cropped, downsampled and reduced to a dominant color on a utility queue.
CDP clipping is unsafe here: even at scale 1, Chromium temporarily resizes the
live rendering widget to the clip dimensions, producing a visible blink. See
[Chromium's capture implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/content/browser/devtools/protocol/page_handler.cc).

Unchanged viewport/scroll position, hit elements and sampled background styles
reuse cached pixels. Weak element identities do not retain removed DOM nodes.
Opaque frames, canvas/video/SVG, closed shadows and painted pseudo-elements keep the
throttled fallback because their pixels can change without observable outer styles.
Images can retain a cached color during animation until their source, geometry or
sampled position changes. Capture is skipped above 16 million device pixels;
encoded data is limited to 8 MiB, with dimensions checked before image decoding.
Each request times out
after two seconds. Navigation, viewport changes and resumed scrolling discard
stale results; the cached color remains until a valid replacement arrives.

The Chromium fixtures cover light/dark solid backgrounds, banners, transparency,
gradients, shadow content, frames, the large-DOM budget and scroll deferral. The
document-footer harness checks CSS and rendered gradient color continuity above
the spacer, and confirms pixel capture never resizes the live Chromium views. Controller tests check
light/dark theme fallbacks, first-frame color and preservation of page colors on theme
changes.

## Independent page-extension color

The document spacer determines its background from the document end before it
scrolls into view. It does not reuse the native footer's viewport-edge sample or
wait for scrolling to settle. Color is applied before the spacer's first paint,
without a correction animation when scrolling exposes it.

The fill paints one CSS pixel above its box to cover fractional rasterization
seams against the page's rounded scroll height. This uses the same sampled color
and only ink overflow, so the spacer height and scroll range remain unchanged.
Pixel tests check the join at normal and Retina scale with fractional positioning.

A bounded reverse traversal inspects five horizontal positions along the last
content edge and excludes fixed/sticky banners. It follows visible overflow
through viewport-height bodies, zero-height wrappers and `display:contents`,
and prunes only where actual overflow/paint clipping prevents descendants from
painting the sampled edge. Body overflow propagated to the viewport is handled
separately from an inner scroll container. It chooses the most common background, composites transparent layers,
and resolves ordinary vertical linear-gradient endpoints. The browser's Canvas
color supplies unpainted backgrounds and follows the document's color-scheme;
the native theme is used only as a failure fallback. Opaque embedded content
and unsupported gradients/effects use their surrounding CSS background.

Full-width canvas and CSS background-image backdrops at the document end have a
rendered-pixel fallback, including SVG background artwork such as DuckDuckGo's
pond illustration. Image identity and paint settings participate in the cache
key, so changing or removing the image cannot retain its previous colors.
The existing bottom traversal checks at most 24 children of already-visited
ancestors for a backdrop; it does not query or scan the whole document.
Direct canvas reads are avoided because WebGL drawing buffers can already be
cleared, and synchronous readback can stall the page.

Once the actual artwork bottom is visible and scrolling has been quiet for 150ms,
the existing native color scheduler may capture the viewport without a CDP clip.
Clipping the capture would resize Chromium's live render widget. Native code
crops the returned image off the main thread to a two-pixel-high strip and keeps
32 sRGB colors across its width, excluding the scrollbar. A horizontal gradient
continues those colors down the extension, including its one-pixel seam overlap.
The original CSS color remains the fallback until the first usable capture.

One capture is allowed in flight, with the existing minimum one-second interval
and measured-cost backoff between captures. Captures are limited to 16 million
pixels and decoded image data to 8 MiB. The strip is cached across scrolling and
footer toggles, invalidated by source/geometry/style changes; cached polls do no
geometry work. Captures taken before scrolling, resizing, source replacement or
footer-mode changes are rejected. Fixed overlays at the sampled edge block
capture so consent dimmers are not baked into the cache. Animated canvas drawing
alone does not invalidate it: this preserves a stable continuation without
continuous readback. No page pixels are sent outside the app.

Modern computed CSS colors (`lab()`, `oklch()`, `color()`) are converted to sRGB
using a lazily created 1×1 CPU-backed canvas and a bounded 64-color cache. This
converts a solid CSS color only; it never captures page content. Unchanged colors
need no further conversion reads. Ordinary RGB values retain their direct path.

Work is limited to 128 elements, 24 levels, and approximately 3ms per pass (a single
browser layout read cannot be preempted). Geometry/style reads are reused across
sample positions. Existing structural/resize notifications trigger updates, with
at most 32 relevant bottom elements watched for attribute/size changes. Stylesheet
loads, color-scheme changes and relevant transition endings also invalidate the
sample. Updates coalesce to at most five per second and back off with measured
color cost. Observers retain their registrations between unchanged samples so
ResizeObserver's initial notification cannot create idle polling. Scrolling does
no color lookup, viewport resize, native round trip, or screenshot capture.

Tests cover distinct top/bottom colors, an immediate jump to the end, independent
native colors, fixed-banner exclusion, offscreen color/replacement changes,
gradients, transparency, dark browser canvas, visible versus clipped overflow,
modern color conversion/caching, canvas/image strip caching and stale replies, and
zero geometry reads when idle. Desktop CEF tests use a WebGL backdrop with a
non-preserved drawing buffer and assert that capture never resizes native views.

## Banner-owned native footer color

A positive obstruction result also describes the broad painted banner background
and a sample line inside its lower edge. The detector uses its existing frame and
shadow-root context, bounded ancestor/style reads, and a weak per-document identity.
It prefers the banner container over child buttons and ignores narrow widgets as
whole-footer color sources (at least 65% viewport coverage is required). Solid
backgrounds are composited through transparent ancestors; images, gradients,
painted pseudo-elements and complex effects request rendered pixels instead.
Frame scale and coverage are propagated back to the main viewport.

The controller prepares this color before the opening animation and retains its
ownership while the banner is present. Banner generations reject pending ordinary
page samples; known solid banner colors avoid separate color requests entirely.
Existing detection observations update the color, using the normal crossfade only
after opening. Unknown observations preserve it. Confirmed dismissal releases it;
manual/latched native placement can remain open while color returns to the page.
A manual override with an already-known banner keeps bounded detection active for
color validation, without changing the user's placement choice.

Complex banners use the existing throttled full-viewport capture, cropping off
thread at the detected banner edge rather than a gap below it. Captures never use
CDP clipping or resize the live webview. Navigation, source-generation changes and
viewport changes discard stale replies. Document-extension color is independent.
Tests include blue banners with white buttons/page gaps, transparency, narrow
widgets, stale replies, opening versus later color animations, and solid/gradient
banners inside cross-origin closed shadow roots.

## Interactive viewport applications

The detector also returns `reason: viewport-app` for a top-level, non-scrolling
canvas application covering most of the viewport and reaching its bottom edge.
It requires application semantics (`role="application"`) or a Flutter canvas UI
host, alongside the canvas geometry. This covers Maps and Earth without domain
allowlists or treating every fullscreen canvas/background as an obstruction.
Scrolling documents, smaller embedded applications, videos, and child-frame maps
do not qualify through this rule.

The existing sampled hit and at most 32 ancestors establish the application.
A weak reference preserves the candidate through transient controls, while every
probe rechecks visibility, geometry, scrollability, and application semantics.
No new timers, document scans, mutation observers, pixel readbacks, or scroll
handlers are added. This reason uses the existing native-footer animation and
manual override policy, without supplying a cookie-banner color descriptor or
adding a document spacer to the scroll-locked app.

Regression coverage includes ordinary and Flutter canvas apps, open/closed shadow
roots, disabled pointer events, transient controls, removal/hiding, changes to
application semantics, and transitions into scrolling or embedded layouts.
Desktop CEF tests measure appearance-to-detection timing and verify native footer
placement, stable compositor geometry, and release after the canvas disappears.

Full-height flex/grid apps can also return `reason: viewport-layout` when an
actual text or control hit overlaps the address bar, including `display: contents`
link labels and icons nested in controls. This requires a top-level,
explicitly scroll-locked document, a flex/grid panel spanning most of the viewport height and ending at its bottom.
The panel may be narrow and its content may have bottom padding (Apple Maps). The hit's ancestor chain
must have no overflowing scroll or clipping container; independently scrolling
siblings (such as Gemini's conversation) are allowed. Background paint alone,
short unlocked documents, embedded frames, and ordinary scrolling footers do
not qualify. Geometry is revalidated after opening the native footer and each
subsequent probe, so removing the bottom content releases the footer normally.
This uses the existing sampled points with at most 32 ancestors, within the
existing work budget; it adds no timers, observers, page scans, or pixel reads.

## Page fullscreen

Chromium's Alloy fullscreen callback presents only the native browser view on its current display. The original window and split-pane constraints remain intact, so leaving fullscreen restores the existing layout and manual footer mode. The document extension is disabled and footer probing/color sampling pauses while the session is fullscreen. Chromium's normal Fullscreen API handles the selected page/video element; Talaria does not simulate fullscreen by changing page CSS.

Escape is handled before page keyboard handlers and exits renderer fullscreen as well as native presentation. Page exits, navigation, closing a tab, closing its original window, and app deactivation restore the browser view. Native presentation is deferred outside Chromium's callback to avoid reentering its message pump. No additional polling or screenshot capture is introduced.

Run `python3 Tests/run-browser-overlay-cef.py --fullscreen` for isolated desktop checks of page/video/frame fullscreen, native Escape, navigation, exact pane restoration, footer exclusivity, and closing a fullscreen tab.

## Raised viewport appearance

When the native footer opens, the Chromium viewport gains rounded corners and
an exterior shadow using the existing theme radius and content-shadow tokens.
A clipping host and a separate shadow outline keep the shadow outside the page;
the explicit shadow path avoids rasterizing live web content. Decoration follows
the committed height-transition inset, including interrupted reversals, and
returns to square corners with no shadow when the footer closes. This does not
change the document extension, page dimensions, or color sampling.

## Active browser tab color

The selected tab accepts a content background and animates it over the existing
footer-color transition duration. The active label and template icons use the
higher-contrast black or white theme ink, recomputed against the displayed color
on each animation frame. Reversals start at the current color; returning to a
non-browser tab restores the theme background. Favicons retain their own colors.

Browser colors come from the visible viewport's top edge, including fixed page
headers, rather than the top of the document. Five bounded CSS samples run in
the footer's existing polling path. Complex painted edges share a single bounded
viewport screenshot with the bottom edge; each edge has an independent cache.
This adds no polling timer, document scan, mutation observer, or extra capture
loop. Combined CSS work contributes to the existing CPU backoff. Hidden tabs,
fullscreen, active viewport resizing, and stale navigation replies retain the
existing sampling guards. Color changes update the selection directly without
reloading tab layout or persisting a page-derived color in workspace state.
