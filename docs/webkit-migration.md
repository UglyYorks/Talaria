# WebKit browser migration

Talaria now embeds the macOS `WKWebView` framework. The app no longer bundles CEF,
launches a Chromium helper, downloads a browser runtime during the build, or runs
a separate CEF message loop. WebKit security and engine updates arrive with the
installed system software.

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

Validation on September 10–11, 2026 included a signed desktop build and the full
`make test` compilation. The packaged app links system WebKit, contains no CEF
engine symbols, libraries or helper bundles, and includes the current browser
and Markdown scripts. Its strict recursive code-signature verification passed;
the minimum supported OS remains macOS 13. The gateway, theme audit, JavaScript
and native unit suites passed except `QuickInputTests`, which fails the window-server assertion
that a fully transparent capture window receives mouse events beside the notch.
The existing pre-migration binary fails the identical assertion under the same
host conditions; its test and Quick Input/selection-window implementation are
unchanged on this branch. This may also be related to the locked desktop and
requires an unlocked-session retest. The remaining unit executables were run
individually after that failure and passed.

Focused regressions cover WebKit settings persistence, native cookie blocking
without disabling local storage, native HTTPS navigation policy and preserved
POST requests, legacy profile migration, reset-store isolation, settings
navigation after unsupported controls are removed, and asynchronous download
resume/pause/cancel races. `BrowserSettingsTests`, `BrowserProfileImportTests`,
`AppResetTests`, `FeatureControllerTests` and `WebKitDownloadLifecycleTests`
passed. Browser integration suites are launched as desktop bundles from this
worktree and use isolated test profiles.

The host session was found to be locked (`CGSSessionScreenIsLocked=Yes`), keeping
applications inactive and WebKit documents hidden. Native checks that depend on
visible rendering, foreground input, fullscreen, developer tools or compositor
sampling remain pending an unlocked desktop; results from the locked session do
not establish rendering parity. The latest GET-download fallback lifecycle tests
and theme audit passed without requiring foreground access. The HTTP download
fixture now distinguishes true byte-range resumption from a full GET restart and
checks the complete downloaded payload for both paths.

The final two-launch preferences/download integration passed: page script and
font settings, zoom, background suspension/resume, cache/cookie clearing,
concurrent destinations, nonzero byte-range resumption after closing the source
tab, cancelled-download retry, explicit GET restart without range support, exact
four-megabyte payloads, and persisted download history. The three-launch import
test also passed, including a `__proto__` storage key, Unicode values, HttpOnly
protection and one-time session-cookie replay. Image-loader redirect cookie
scoping and response-size checks passed.

After unlocking the desktop, finish these checks before declaring feature parity:

- `make test` (repeat the window-server/Quick Input check in an unlocked session).
- `make test-browser-links` (real right-click menus and script-popup opener/close).
- `python3 Tests/run-browser-overlay-webkit.py --fullscreen`.
- `python3 Tests/run-browser-overlay-webkit.py --devtools` (native menus, source,
  WebArchive save/reopen, print-dialog cancellation and inspector lifecycle).
- `python3 Tests/run-browser-overlay-webkit.py --document-footer`.
- `python3 Tests/run-browser-overlay-webkit.py`.
- `python3 Tests/run-webkit-page-bridge.py` (final visible-rendering rerun).
