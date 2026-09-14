# Native mouse-wheel scrolling

Browser wheel input uses the standard AppKit and WebKit path. Talaria does not
intercept wheel steps, subdivide their deltas, or convert them into synthetic
trackpad gestures. WebKit handles scrolling, nested targets, site wheel handlers,
and trackpad momentum.

The custom mouse-wheel smoother, animation timer, lifecycle hooks, and **Smooth
mouse-wheel scrolling** setting have been removed. Previously saved values for
that setting have no effect. History swipe gestures remain enabled during wheel
input.

## Regression verification

Run on an unlocked macOS desktop with the normal signing identity:

```sh
make test-browser-wheel-routing
make build/BrowserSettingsTests
build/BrowserSettingsTests
```

The wheel-routing target launches a signed desktop fixture from the current
worktree with a disposable profile. It sends native events through
`NSApplication.sendEvent:` and verifies that the original event reaches
`NSWindow.sendEvent:` unchanged. JavaScript observes resulting DOM events and
scroll positions; it does not drive the scrolling under test.

Coverage includes ordinary, repeated, reversed, horizontal and Shift-wheel input,
nested panels, a cross-origin iframe, wheel-consuming handlers, modifiers,
precise input and gesture phases. Momentum metadata is checked at the window;
fabricated events do not establish a physical trackpad momentum sequence.
The fixture starts with the old smoothing preference saved as enabled to verify
that it cannot reactivate event conversion.

Full traces are written to `build/BrowserWheelRoutingWebKitResults.json`.
