# Chrome extensions in Talaria's existing tabs

Status: **best-effort support implemented with the standard CEF distribution**.
Validated on macOS on 2026-09-07 with CEF `151.3.24+g2384915`, based on
Chromium `151.0.7922.174`. No custom engine build is required.

## Using extensions

1. Choose **Extensions → Chrome Web Store…**, find an extension, and use the
   store's install button. Chromium presents the extension's permission prompt.
2. Reload the Talaria pages where the extension should run. Ordinary browsing
   remains in Talaria's existing embedded tabs.
3. Choose **Extensions → Manage Extensions…** to inspect permissions, enable or
   disable extensions, or remove them. Reload affected pages after changes.

The store and manager open in a Chromium-owned utility window sharing the same
persistent browser profile as Talaria's embedded tabs. Closing that window does
not disable extensions. Reopening it reuses its primary tab when still available.
Store links, store addresses, and `chrome://extensions/` entered in Talaria route
to this utility without replacing the current embedded page. Chromium handles
package verification, install permission prompts, management, and its extension
update machinery; Talaria does not download or unpack Web Store packages itself.
Update delivery has not been separately verified.

## Verified milestone

**Dark Reader** (`eimadpbcbfnmbkopoojfekhnkhdbieeh`) was installed from the Chrome
Web Store through its normal permission dialog in a signed desktop test app
using Talaria's production browser controller and tab view. The isolated profile
recorded `from_webstore: true`. After closing the installer and reloading, Dark
Reader injected eight style sheets and changed an ordinary local page to a dark
background inside the native Alloy tab. After normal app termination and desktop
relaunch, the same page was modified again without an installation call, loading
flags, or an open manager. The page's rendered screenshot and inspection results
were saved as `build/darkreader-after-restart.png` and
`build/darkreader-restart-results.json` during the manual check.

The automated desktop test installs a local Manifest V3 extension through
Chromium's normal unpacked-extension installer. It verifies:

- A visible page marker inserted by a content script in the actual embedded tab.
- Content-script/service-worker messaging and shared `chrome.storage.local`.
- Extension registration, local storage, and the local `chrome.storage.sync`
  backing store surviving normal app shutdown and restart. Account/cloud sync is
  not implemented or claimed.
- Continued operation with the manager closed, manager reuse, and disabling and
  re-enabling the extension while retaining its data.
- The browser remaining Alloy, attached to the native tab, with a visible,
  nonzero-sized viewport, and successful shutdown with the manager open.

Run on macOS from this checkout with the normal signing identity available:

```sh
python3 Tests/run-browser-extensions-cef.py
```

Use `--skip-build` after building this checkout. The test requires Node.js with
built-in WebSocket support and the normal Xcode/CEF build dependencies. It compiles
against this checkout's production objects, signs an isolated desktop app, and
launches it twice with `open -n -W`. A test-only folder-picker handler selects the
local fixture; production installation retains Chromium's own dialogs. The test
uses a loopback HTTP fixture and remote debugging for assertions, with no
`--load-extension` or unsafe extension-debugging flags. Its temporary app and
profile are removed afterwards. Results and a rendered page screenshot remain
at `build/browser-extensions-results.json` and `build/extension-restart-page.png`.
This desktop integration test runs separately from `make test`; address-routing
regressions are covered by `FeatureControllerTests` in the ordinary test suite.

Validation of this change included a successful full suite and successful final
`FeatureControllerTests` and desktop extension runs. A later full-suite rerun
reached an unrelated `QuickInputTests` focus assertion while the Mac was locked;
that native focus check requires an unlocked desktop.

## Compatibility limits

Content scripts, worker messaging, and storage are the first supported use cases.
This does not promise general Chrome/Brave extension compatibility. In particular:

- `chrome.tabs.query({})` does not enumerate Talaria's Alloy tabs. Extensions
  relying on Chrome tab/window identity, selection, creation, or events may fail.
- Talaria has no extension action toolbar for its embedded tabs. Popup-driven
  extensions and extensions requiring `activeTab` may not work on those pages.
- Other extension APIs, automatic updates, and installation policies are subject
  to the bundled Chromium implementation and have not all been tested.
- Existing pages should be reloaded after installation or enable/disable changes.

The optional diagnostic below compares an embedded tab with a Chrome-style
control window. It demonstrates working content scripts and worker messages but
missing embedded-tab enumeration:

```sh
python3 Tests/run-browser-extension-probe.py
```

Its exit status 2 is the expected **full tab-API compatibility failure** on this
engine, not a failure of the supported milestone above. Exit 1 is an execution
error; exit 0 only means its limited probes pass. Its report is retained at
`build/browser-extension-compatibility.json`.

## Engine evidence

The exact shipped CEF revision documents the limits:

- [`cef_types_mac.h`](https://github.com/chromiumembedded/cef/blob/2384915/include/internal/cef_types_mac.h)
  requires Alloy style when a native `parent_view` is supplied.
- [`browser_host_create.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/browser_host_create.cc)
  enforces that macOS native-parent restriction.
- [`chrome_extension_util.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/chrome/extensions/chrome_extension_util.cc)
  can find an Alloy WebContents by tab ID, but does not provide a complete
  browser-window/tab model; the desktop probe confirms the missing enumeration.
- [`alloy_browser_host_impl.cc`](https://github.com/chromiumembedded/cef/blob/2384915/libcef/browser/alloy/alloy_browser_host_impl.cc)
  does not host `chrome://extensions` or implement Chrome commands in Alloy.

The utility window provides the stock Chrome UI needed for installation and
management while leaving the embedded runtime unchanged. Future compatibility
work should add tests for specific requested extensions within these standard
CEF constraints.
