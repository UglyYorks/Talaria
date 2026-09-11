# WebKit browser migration

Talaria now embeds the macOS `WKWebView` framework. The app no longer bundles CEF,
launches a Chromium helper, downloads a browser runtime during the build, or runs
a separate CEF message loop. WebKit security and engine updates arrive with the
installed system software.

Browser pages identify as the installed Safari release. Talaria reads Safari's
`CFBundleShortVersionString` at startup and sets WebKit's public
`applicationNameForUserAgent` before creating browser views, including private
pages and script popups. This adds `Version/<installed version> Safari/605.1.15`
to WebKit's native user agent for requests and JavaScript without injecting a
page override. Restarting Talaria picks up Safari updates. If Safari's version
cannot be read, the browser retains WebKit's default identity. The compatibility
tokens `Mac OS X 10_15_7` and `605.1.15` are intentionally frozen by Safari; they
do not identify the installed OS or engine build. The missing browser/version
tokens in macOS WKWebView's default identity are documented in
[WebKit issue 278284](https://bugs.webkit.org/show_bug.cgi?id=278284).

## Application features

The WebKit controller retains browser tabs, split panes, private windows, URL and
title updates, back/forward/reload, find in page, link and image menus, page reading
for AI tasks, downloads, printing, source viewing and developer inspection.
JavaScript-created windows use WebKit's supplied configuration so `window.opener`
and an initially blank popup remain functional. Ordinary link destinations still
route through Talaria's tab and window actions.

The automatic address bar continues to resize the live browser view and maintain
the document footer. Its DOM inspection, frame coordination and screenshot color
sampling are described in [automatic-address-bar.md](automatic-address-bar.md).
The browser remains a native view; this migration does not add a general API for
rendering a live website into arbitrary application surfaces.

Save Page now writes a `.webarchive` containing the main document and captured
resources. View Source displays the archived main resource in a themed source
window. Image actions prefer archived original bytes, then an in-page fetch, then
a bounded network request using cookies from the correct browser data store.
Network redirects recalculate cookies for the new destination.

Regular downloads can continue after their tab closes. Private downloads require
a destination choice, do not enter persistent download history, and are cancelled
when their private window closes. WebKit resume data preserves downloaded bytes
when the server supports it. Otherwise, an HTTP(S) GET download stays paused with
an explicit notice that Resume will restart from the beginning. Restart preserves
any file already at the selected destination and chooses a numbered sibling when
needed. Requests with another method, a body or a body stream are never replayed
automatically when resume data is unavailable.

## Profiles and settings

On macOS 14 and later, normal browsing uses a persistent `WKWebsiteDataStore`
identified by the profile's `WebKitStoreIdentifier` file. macOS 13 uses the default
persistent WebKit store and records `WebKitDefaultDataStore` in the profile; that
profile keeps using the same store after an OS upgrade. Each independently opened private window has a separate
nonpersistent store; script popups share their opener's store.

The first launch stages cookies and local storage from the previous Talaria
Chromium profile. A migration marker prevents subsequent launches from restoring
data the user has cleared. Browser-profile imports use the same supported cookie
and origin-local-storage paths; see
[browser-profile-import.md](browser-profile-import.md). Talaria's existing history,
bookmarks and workspace state remain in its application database. External profile
imports do not include passwords, extensions, IndexedDB or browser history.

Settings are applied to WebKit APIs where available. Controls that require an API
missing from the installed WebKit version are omitted from the settings catalogue.
Some existing controls and inspector operations use guarded WebKit SPI, so their
availability can change with system updates. Background-page suspension requires
macOS 14 or later. Closed-shadow-root inspection uses the public content-world
option introduced in macOS 27; earlier systems have reduced coverage. The bounded
fallback for `pointer-events:none` content is a heuristic and cannot reproduce
every engine-level paint-order hit test.

## Separate product work

Media now uses the installed macOS/WebKit decoding stack. Actual playback depends
on the system version, hardware and the site's media format and access rules.
This migration does not bundle additional codecs or implement an X-specific media
workaround.

Apple Passwords/Keychain autofill and Safari extensions are not implemented by
this change. Embedding `WKWebView` does not by itself add Talaria interfaces for
managing credentials or installing and running Safari extensions. Those features
need separate product and platform integration work.

## Tests

The full regression pass completed on September 11, 2026 on Apple silicon running
macOS 27.0 (26A428). Browser integration suites were launched through LaunchServices
as signed desktop bundles from the WebKit worktree, using disposable profiles and
local fixtures.

The final `make -j6 test` pass covers the native unit suites, Hermes gateway and
runtime checks, theme-color audit, profile importer, and JavaScript regressions.
The unlocked desktop also passes `QuickInputTests`; its earlier window-server
failure does not reproduce in this session.

The browser integration results are:

| Suite | Verified behavior |
| --- | --- |
| Preferences and downloads | Saved native settings, zoom, suspension, clearing data, unique destinations, true byte-range resume, GET restart fallback, cancelled-download retry, complete payloads and persistent history |
| Navigation | Native navigation callbacks, history, reload, navigation covers, resize and closure |
| Links | Trusted link/image/editing menus, copy and Services, split/window routing, blank script popups, opener access, `window.close` and late-callback cleanup |
| Images and media | Original PNG/GIF/SVG/blob bytes, copy/save, error handling, image-service inputs and actual H.264 decoding and playback; AAC capability advertisement |
| Private browsing | Persistent versus private storage, isolation between private windows, shared storage within one private window and cleanup |
| Find | Match counts, forward/backward navigation, wraparound, no matches, page changes and focus |
| Profile import | Three launches covering local storage, Unicode and `__proto__` keys, cookies, HttpOnly protection, persistence and one-time session-cookie replay |
| Page bridge | Fixed, closed-shadow and framed overlays, clear pages, edge colors, readable content, frame-aware find and document extension |
| Document footer | All 106 rendering checks, including viewport animation, 24 repeated mode changes, compositor alignment, scrolling, content colors, canvas layouts, frames and large captures |
| Overlay integration | 13 probe cases, seven native latency cases and 72 rapid footer toggles |
| Fullscreen | All 40 checks for element, video and iframe fullscreen, native geometry, Escape, navigation, tab closure and layout restoration |
| Page commands and inspector | All 36 checks for native menus, source, WebArchive save/reopen, Save/Print cancellation and inspector window lifecycle |
| Image loader | Cookie scoping across redirects and bounded response sizes |

The JavaScript suites pass 33 document-footer checks and 114 overlay/color checks.
The native 20,000-node full scan completed with 207 samples, 120 ms of measured
CPU work and a longest slice of 4 ms. Typical banner fixtures were detected within
390 ms and settled within 592 ms in the recorded run. These are observed test
results, not performance guarantees for arbitrary websites.

Verification found and fixed five migration defects: profile refresh discarded
injected scripts; empty script-popup URLs were rejected; ordinary pages could get
image menus; full scans could consume their deadline waiting between short CPU
slices; and the inspector initially docked inside the page instead of opening its
own window. Native fixtures now wait for completed menus/fullscreen transitions,
use real video, and return large JavaScript results directly through WebKit rather
than transporting them in page titles.

The signed app links system WebKit, contains no CEF engine libraries or helper
bundles, and packages the current browser scripts. Strict recursive code-signature
verification passes. Deployment still targets macOS 13, but this pass did not run
on older macOS versions or Intel hardware. Local media tests do not establish live
X-feed or DRM compatibility. The separate product work listed above remains outside
this migration's verified feature set.
