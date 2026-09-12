# Browser performance follow-up — 12 September 2026

**Repeated tab-color transitions improved. Continuous resize and YouTube fullscreen exit remain performance problems.** Blur, native sidebar, page-color matching, and the animated tab-color wave remain enabled. These changes are on `browser-frame-profiling`, based on freshly fetched main `49b2a25`.

## Changes

- Page-color-only state updates retain the immutable workspace snapshot and notify observers without rebuilding the entire native tab strip. The existing browser callback then applies its color transition. Previously, persisting a sample synchronously reloaded the strip before that callback could finish, causing unnecessary layout and interrupting the initial color transition.
- Identical selection geometry no longer rebuilds its path or notifies the workspace outline. The blur view retains its Core Image filter graph when geometry and palette are unchanged; theme or mask changes still rebuild it.
- Nonanimated sidebar/window layout batches target constraints before layout. Tab-width preparation and selection positioning can happen on either side of that layout pass. This reduces redundant work in the code, but measurements do **not** establish a consistent resize speedup.
- Header color matching samples only the header. When rendered pixels are needed, WebKit captures the narrow top strip instead of the whole Retina viewport. Image analysis accesses the snapshot's CGImage directly, avoiding a full TIFF encode/decode. The existing footer API and footer behavior remain available. Fullscreen/generation guards reject inappropriate captures.
- Desktop application objects now compile with `-O2 -g`; `APP_OPTIMIZATION_FLAGS='-O0 -g'` remains available for debugging. The build stamp includes the flags, so changing them rebuilds the affected objects.

No specs, visual tokens, or blur intensity were changed.

## Frame measurements with all effects enabled

Same machine as the [baseline](browser-frame-profile-2026-09-12.md): M2 Pro, 32 GB, macOS 27.0 (26A428), 60 Hz external display, 2600 × 1400-point window at 2× scale. A desktop-launched production window uses a disposable database/profile, visible sidebar, four browser tabs, one chat tab, normal resize delegate, native blur, color sampling, and production color bindings. Each workload lasts five seconds. Builds and other tests did not run concurrently with these measurements.

The final implementation completed **21 foreground, visible cases**: nine light-mode workloads, plus two light and two dark repetitions each of resize, color pulse, and animated canvas-edge sampling. All feature checks were enabled. Foreground/visibility failures in earlier attempts were excluded.

| Workload | Baseline gaps >25 ms | Final gaps >25 ms | Final p95 |
|---|---:|---:|---:|
| Ordinary scroll | 0, 0, 0 | 0 | 18 ms |
| Dense DOM scroll | 0, 0, 0 | 1 | 18 ms |
| DOM churn while scrolling | 0, 1, 0 | 0 | 18 ms |
| Canvas while scrolling | 0, 0, 0 | 0 | 18 ms |
| Alternating color sections | 0, 0, 1 | 0 | 17 ms |
| Static gradient | 0, 0, 0 | 0 | 18 ms |
| Repeated tab-color transitions | 6, 5, 6 | 0, 0, 0 light; 0, 0 dark | 18 ms |
| Animated full-window canvas color | No valid equivalent baseline | 1, 1, 1 light; 0, 1 dark | 17–18 ms |
| Continuous resize | 42, 38, 41 light | 14, 27, 53 light; 53, 58 dark | 25–33 ms |

The color-pulse cases recorded seven header colors each; the canvas-edge cases recorded five. Zero color-pulse gaps therefore did not result from disabling updates. The header snapshot accuracy fixtures also verify gradient and canvas RGB and an 8-point capture height at a 1000-point viewport width.

**Resize is unresolved.** Its best focused run improved, but that result did not repeat reliably. A freshly linked control with the original resize implementation and all other optimizations identical produced 48, 53, and 55 gaps (p95 31–33 ms). This overlaps the later optimized runs. Native CPU also did not consistently improve: final light resize used 2.85–3.14 CPU seconds per five seconds versus baseline 2.74–3.08. Do not advertise the resize path as a demonstrated speedup or infer a dark-theme regression from unmatched light/dark runs.

These are JavaScript `requestAnimationFrame` scheduling gaps, **not measured compositor presentation drops**. Baseline-versus-final results include the compiler optimization change. They are descriptive workload comparisons, not an isolated estimate of each patch's contribution.

## YouTube fullscreen

Tested the public Big Buck Bunny video (`aqz-KE-bpKQ`) through YouTube's actual player controls, native Escape, and the Fullscreen API in the full production workspace. The harness also verifies tab restoration, original window geometry, native footer inset, viewport size, and closing a tab while fullscreen. This covers **player fullscreen**, not the macOS green-button window mode.

With all effects enabled, the last recovery run measured:

| Exit action | Native state/host restored | Largest gap in immediate next second | Largest gap in subsequent recovery second |
|---|---:|---:|---:|
| Fullscreen API | 626 ms | 213 ms | 18 ms |
| Escape | 609 ms | 253 ms | 28 ms |
| YouTube player button | 895 ms | 276 ms | 27 ms |

Another foreground run reached **489 ms after Escape**. The regression check intentionally remains failed when an immediate gap exceeds 250 ms; it was not relaxed to make this pass. The later recovery measurement requires the original window to be key and the fullscreen window to be hidden, and verifies the page is visible and focused. Its observation began about 1.8–2.1 seconds after the exit action because the immediate one-second measurement runs first; that timestamp is **not** an independently measured recovery latency.

A diagnostic disabling native header sampling still measured 207–214 ms immediate gaps. This shows that stopping header sampling alone does not eliminate the issue. One no-blur attempt failed to enter fullscreen; it provides no usable evidence about blur cost. The earlier small, tab-only fixture recovered more smoothly but had a much smaller viewport, so it is not a valid estimate of production-chrome cost.

The user's multi-second unresponsiveness is **not fixed**. We reproduced substantial transition/recovery pauses, although no individual rAF gap reached multiple seconds in these valid runs. Native fullscreen animations and page rendering can contribute separately to the perceived time before interaction resumes.

## Profiler evidence

The baseline Apple Time Profiler trace identified native layout and Core Animation commit work, with the limitations documented in that report. For YouTube, macOS `sample` additionally profiled **both Talaria and its WebContent process**, concurrently, for a requested 20 seconds at a 5 ms interval. The recorded interval includes playback, fullscreen transitions, and measurement callbacks; it is not isolated to one failed frame.

- Talaria main thread: 2,608 samples, including 2,270 in its idle run-loop Mach wait (~87%). Active stacks included WebKit layer-tree commits, IOSurface handling, AppKit layout, and Core Animation work.
- WebContent main thread: 2,555 samples, including 1,443 in its idle run-loop Mach wait (~56%). `WebPage::updateRendering` appeared in 594 inclusive samples and rAF callbacks in 254. Other active stacks included JavaScript property access, style resolution, layout/compositing, and garbage collection. JIT frames are not attributable to individual scripts from this capture.

These counts overlap; they are not additive CPU percentages or a proof that one subsystem caused every stall. They point the remaining fullscreen investigation toward page rendering and native presentation recovery rather than a continuously blocked Talaria event loop. The GPU process was not sampled. A finalized Animation Hitches trace remains unavailable; no verified compositor drop count is claimed.

The next useful investigation is a same-size minimal WebKit fullscreen control, paired with a successful GPU/compositor capture and phase-specific JavaScript profiling around Escape. Keep effects enabled in the primary comparison. Avoid adding a blanket delay, turning off blur, or modifying YouTube's page without evidence that it addresses the actual bottleneck.

## Verification and reproduction

- **159 Python tests and 147 browser JavaScript checks passed**, along with the theme-color audit.
- **39 of 40 native suites passed.** `FeatureControllerTests` still fails its sidebar keyboard-activation assertion, also observed before these changes. Its separate browser-extended tests pass. The full test suite is not green.
- New state-update, unchanged selection geometry, batched tab-width, and blur-filter cache regression checks pass.
- The desktop tab-color suite now passes, including the previously failing initial-color assertion, animated transitions, large-canvas pixel sampling, and split-tab color behavior.
- The desktop backdrop suite passes in both themes, including mask changes and delayed compositor redraws. The page-bridge suite passed with the new header-gradient/header-canvas accuracy and narrow-capture assertions.
- The repaired local desktop fullscreen suite passes: element/video/iframe exits, native Escape, footer inset and geometry restoration, recovered frame cadence, and closing while fullscreen. The live YouTube immediate-cadence failure remains open.
- The broader baseline desktop results remain documented separately; unrelated failing navigation, preferences, smooth-scroll, overlay, and document-footer cases were not silently reclassified as passing.

```sh
make build-browser-frame-profile
python3 Scripts/profile-browser-frames.py --width 2600 --height 1400 --repeats 3
python3 Scripts/profile-browser-frames.py --width 2600 --height 1400 --dark --repeats 2 --workloads resize,color-pulse,canvas-edge --output build/profiling/dark.json
TALARIA_FULLSCREEN_LIVE_URL='https://www.youtube.com/watch?v=aqz-KE-bpKQ' python3 Tests/run-browser-overlay-webkit.py --fullscreen
python3 Scripts/profile-browser-instruments.py --name browser-followup --seconds 45
```

Leave the desktop window active during timing runs. The YouTube runner emits `results.json.profile-ready` in its temporary bundle directory with native and renderer PIDs for attaching profilers. It writes `build/BrowserFullscreenWebKitResults.json`; copy that result before starting another fullscreen run.

The [durable results](browser-performance-improvements-2026-09-12.json) retain final workload metrics, feature/foreground checks, YouTube results, and sample counts. Raw intervals, profiler stacks, disposable comparison binaries, and test logs remain under ignored `build/profiling/`, including `final-ready`, `final-dark`, `final-all-workloads`, `final-original-layout`, `youtube-recovery`, `youtube-app.sample.txt`, `youtube-renderer.sample.txt`, and `correctness/`.
