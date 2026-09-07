# Chrome extensions in Talaria's existing tabs

Status: **not implemented; blocked on a custom engine build environment**.
Investigation date: 2026-09-07. Base: `4841ac7` on branch `chrome-extensions`.
The requested behavior is Chrome Web Store installation and extension operation
inside Talaria's existing native tabs. Separate browser windows are not the
selected implementation.

## What the shipped engine can do

Talaria ships CEF `151.3.24+g2384915`, based on Chromium `151.0.7922.174`.
`Source/ChromiumBrowserController.mm` embeds each browser using
`CefWindowInfo::SetAsChild` and Alloy style. On macOS, setting Chrome style with
that same native parent is overridden by CEF and produces an Alloy browser.

A disposable desktop probe, built in this worktree with a fresh profile and a
local Manifest V3 extension, measured the following:

| Behavior | Embedded native tab | Chrome-style control window |
| --- | --- | --- |
| Requested runtime | Chrome | Chrome |
| Actual runtime | Alloy | Chrome |
| Content script runs | Yes | Yes |
| Content script exchanges messages with service worker | Yes | Yes |
| `chrome.tabs.query({})` finds its sender tab | **No** | Yes |

The control window is solely a diagnostic comparison. It is not a proposed
product feature. This proves a basic incompatibility with extension tab APIs;
it does not establish that every extension fails or that every other API works.
Chrome Web Store installation, permission prompts, updates, extension actions,
and persistence have not been validated.

## Reproduce

Run from this worktree on macOS with the normal signing identity available:

```sh
python3 Tests/run-browser-extension-probe.py
```

Use `--skip-build` only after building the app in this worktree. The runner
compiles the probe against this checkout's app objects and CEF, signs a temporary
app bundle, and launches it with `open -n -W`. It uses an isolated profile and
loads only `Tests/Fixtures/browser-extension-probe`, whose host access is limited
to a local HTTP fixture. The temporary app and profile are removed afterwards.
The report is retained at `build/browser-extension-compatibility.json`.

Exit status 2 is the expected result with the currently pinned engine: embedded
extension requirements fail. Exit 1 denotes an inconclusive probe or execution
error. Exit 0 only verifies these limited requirements; it does not certify
Chrome Web Store compatibility. This diagnostic is intentionally outside
`make test`, because it records a known missing engine capability.

## Engine evidence

The exact CEF source revision used by the app contains these restrictions:

- [`cef_types_mac.h`](https://github.com/chromiumembedded/cef/blob/2384915/include/internal/cef_types_mac.h)
  documents the mandatory Alloy style when `parent_view` is supplied.
- [`browser_host_create.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/browser_host_create.cc)
  disables Chrome style for macOS native parents in `MaybeSetWindowInfo`.
- [`chrome_child_window.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/chrome/views/chrome_child_window.cc)
  has no macOS implementation of Chrome-style native-parent embedding.
- [`chrome_extension_util.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/chrome/extensions/chrome_extension_util.cc)
  can find an Alloy WebContents by tab ID, but this is not a complete browser
  window/tab model. The desktop probe demonstrates the missing enumeration.
- [`alloy_browser_host_impl.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/alloy/alloy_browser_host_impl.cc)
  does not allow `chrome://extensions` in its tested WebUI host list and does not
  implement Chrome commands for Alloy browsers.

Upstream tracks native Chrome-style embedding in
[CEF issue 3294](https://github.com/chromiumembedded/cef/issues/3294).
Removing the runtime restriction alone does not implement the missing native
parent support or extension UI integration.

## Work required to preserve existing tabs

1. Establish a pinned custom CEF/Chromium build, then prove a supported embedded
   Chrome browser integration on macOS. This requires native hosting and lifecycle
   work; relocating a view from a hidden Chrome window is not a verified solution.
2. Make extension window/tab identity, enumeration, selection, creation, removal,
   and events correspond to Talaria's workspace tabs. Verify content scripts,
   background workers, `activeTab`, scripting, and permission enforcement across
   multiple tabs and split panes.
3. Integrate Chrome Web Store installation with Chromium's package verification
   and permission UI, profile-backed state, updates, management, and uninstall.
   Add extension actions/popups without moving browsing to separate windows.
4. Verify restart persistence and real Web Store extensions, plus existing
   fullscreen, navigation, footer, tab shortcut, theme, and resize regressions.
   Preserve the 200px minimum window width and existing theme requirements.

No product source, specs, or README changes have been made. No extension support
claim should be made until the integration and these checks are complete.

## Build environment blocker

The desktop app itself builds successfully from this worktree. The custom engine
is the blocker: the current volume has approximately 24 GiB free. CEF's
[macOS source-build guide](https://github.com/chromiumembedded/cef/blob/2384915/docs/master_build_quick_start.md#mac-os-x-setup)
requires at least 150 GB of free disk for a debug build (its automated build
guide recommends 200 GB). Xcode 26.6 is installed.

A suitable external build volume or Mac builder is needed before the custom
engine can be compiled and its behavior verified. No custom CEF patch or binary
has been produced yet.
