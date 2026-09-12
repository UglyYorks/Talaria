# Browser frame profiling — 12 September 2026

The largest reproducible frame-cadence problem is **resizing the complete browser window**. Repeated native tab-color changes also produce smaller stalls. Ordinary scrolling remained steady with blur and color matching enabled. This is the baseline investigation; see the [implementation and follow-up measurements](browser-performance-improvements-2026-09-12.md).

Baseline: `origin/main` **49b2a25**, branch `browser-frame-profiling`.

## Primary measurements: complete production window

The final benchmark calls the production `TalariaWindowController` initializer and reuses its window while navigating between fixtures. It includes the **visible sidebar, four browser tabs, one chat tab, native resize delegate, window visual effects, address-input progressive blur, page-color sampling, and animated tab-color bindings**. It uses a temporary database/profile, skips restoration of user data and external AI traffic, and launches the signed desktop app from this worktree through LaunchServices.

All **24 primary cases** reported active and visible throughout, with blur, color bindings, sidebar, and the production window delegate enabled. Alternating-section and color-pulse cases each recorded seven distinct successive header-color samples per five-second run. This verifies that color matching was working during measurement, rather than merely configured.

Machine: M2 Pro, 12 CPU / 19 GPU cores, 32 GB RAM, macOS 27.0 (26A428). External LG display: 6144 × 3456 pixels, 3072 × 1728 points, 60 Hz. Low Power Mode off. Window: **2600 × 1400 points at 2× scale**. Other user apps remained open.

Each workload ran three times, with 0.7 seconds of warm-up and five seconds measured. Scrolling uses native precise wheel events at nominal 60 Hz. Resizing programmatically varies both window dimensions at 60 Hz; it is a stress test, not a measurement of a particular hand-drag speed.

**These are requestAnimationFrame scheduling gaps, not verified compositor presentation drops.** At the display's 60 Hz rate, 16.67 ms is the reference interval; a gap is an interval above 25 ms. Native event-loop timing and process CPU time are recorded separately.

| Workload | Gaps >25 ms in each 5 s run | p95 interval | Worst interval | Mean native CPU / 5 s |
|---|---|---:|---:|---:|
| Ordinary scrolling | 0, 0, 0 | 18 ms | 22 ms | 0.49 s |
| 3000-row scrolling | 0, 0, 0 | 18 ms | 23 ms | 0.46 s |
| 30 DOM text updates per frame | 0, 1, 0 | 18 ms | 36 ms | 0.35 s |
| Scrolling with canvas animation | 0, 0, 0 | 18 ms | 20 ms | 0.57 s |
| Continuous resize | 42, 38, 41 | 29–30 ms | 47 ms | 2.91 s |
| Scroll alternating page colors | 0, 0, 1 | 18 ms | 27 ms | 0.70 s |
| Static gradient / pixel color sample | 0, 0, 0 | 18 ms | 21 ms | 0.28 s |
| Repeated tab-color changes | 6, 5, 6 | 18 ms | 37 ms | 0.47 s |

The resize workload consumed about **5.9×** the native CPU of ordinary scrolling. The native process reached roughly 55–62% of one CPU core during resize, compared with about 9–10% during ordinary scrolling. WebKit's separate page/GPU processes are not included in that process CPU total.

A bare-WebKit comparison at the same outer window size had resize gaps of **1, 0, 0** and p95 intervals of **19, 19, 17 ms**. Its color-pulse cases had **0, 0, 0** gaps. That supports investigating Talaria's native UI overhead, but the control intentionally lacks the production chrome and is not a feature-equivalent browser.

## Profiling evidence and what to change

Apple **Time Profiler** successfully captured a 70-second exploratory desktop run. Its earlier workspace fixture had the browser blur and native tab-color bindings, but bypassed the production window initializer. That trace includes window/tab creation, so its cumulative CPU weights must not be represented as phase-isolated production resize costs.

Within that exploratory trace, main-thread samples totaled 9.543 s; `CA::Transaction::commit()` appeared in 2.139 s of inclusive samples and `NSView layoutSubtreeIfNeeded` in 1.586 s. These overlap and include setup. They support inspecting layout and compositing, not blaming one effect conclusively.

1. **Consolidate the resize layout path first.** `Source/TalariaWindowController.m:880` calls `updateSidebarLayoutAnimated:NO` for each resize notification. That method (`:4877`) performs three synchronous `layoutSubtreeIfNeeded` calls, updates tab widths, and updates the workspace outline; the resize callback also updates input widths. Add a dedicated nonanimated resize path that updates constraints together, skips unchanged geometry, and performs one necessary layout pass. Preserve the sidebar, blur, outline, and color matching. Validate against the same full-window workload; a useful target is p95 below 25 ms and fewer than five gaps per five seconds, not a promised improvement.

2. **Investigate interrupted tab-color transitions next.** `TLChromeTabView.m:105`, `:190`, and `:657` synchronously rasterize native layers with `renderInContext:` when a color wave is interrupted. The full-window color-pulse runs show 5–6 gaps versus zero in bare WebKit. Compare with the test-only `--no-color-wave` switch, then optimize reuse of transition images/masks or reduce synchronous rasterization while retaining the visual transition. That diagnostic comparison was not completed because later desktop activation failed; this is a supported hypothesis, not a proven root cause.

3. **Keep screenshot color matching bounded.** `WebKitPageBridge.m:313` snapshots the viewport, then converts the image through TIFF/bitmap data before extracting small edge strips. Processing is already off the main thread and capture is deferred while scrolling. Investigate narrow snapshot rectangles or direct image access to avoid a full-resolution intermediate, while retaining existing geometry validation and color accuracy. The static-gradient case was steady, so this is a secondary optimization candidate rather than the first fix.

4. **Do not remove blur based on this investigation.** An earlier, partial-workspace comparison that hid the bottom blur did not improve frame cadence. It is not a controlled comparison of the final production initializer, but it gives no basis for treating blur removal as the fix. `TLProgressiveBlurView.m:16` rebuilds its filter graph on layout; caching unchanged inputs is worth measuring after the larger resize work is addressed.

At the end of this baseline investigation, no production optimization had been applied. The subsequent implementation and measurements are recorded in the follow-up report.

## Correctness testing

- **159 Python tests passed:** 139 repository tests, seven terminal-service tests, and 13 agent-runtime tests.
- **147 browser JavaScript checks passed:** 33 document-footer and 114 overlay checks.
- **39 of 40 native suites passed.** `FeatureControllerTests` failed at “keyboard activation opens a sidebar category”, including a separate retry. The skipped suites after that failure were run individually and passed.
- **20 desktop browser suites attempted:** 12 passed, six failed, and two were blocked by window activation. The full test suite is not green.

Passed desktop coverage: wheel routing, images, links, find, user-agent behavior, closing tabs, incognito browsing, popup tabs, backdrop rendering, profile import, page-bridge behavior, and image-loader cookie/redirect scope.

| Suite | Observed outcome |
|---|---|
| Navigation | Failed timed assertion: “old frame was checked while destination CSS was pending”. Needs callback/timing triage before attributing it to rendering. |
| Smooth scrolling | Earlier native input/cancellation assertions passed; the final close case tried to read JavaScript from the closed view and returned an unsupported result type. Final Python contract verification did not run. |
| Preferences | Failed “background tab scripts pause after the chosen delay”. Background scheduling on this OS and whether the test's own JavaScript evaluation wakes the page need investigation. |
| Tab color | Failed “Initial page color is applied without a transition”. Separate from the successful dynamic-color measurements above. |
| Native overlay | Timed out after 120 seconds at the first overlay-latency case. |
| Native document footer | Spacer assertion failed; diagnostic code then referenced removed key `browserUsesReducedHeight` and threw `NSUnknownKeyException`. The fixture needs updating before this can be treated as a clean product regression. |
| Fullscreen / DevTools | Both blocked because their desktop windows could not activate; not established functionality failures. |

One additional window-creation/teardown stress run crashed inside WebKit's IPC stream connection code on macOS 27. It was not reproduced during the subsequent persistent-window benchmark, which completed all 24 cases. This is a single observation, not an established ordinary-browsing crash.

## Limits and retained evidence

An initial long run was invalidated by window occlusion and excluded. Earlier workspaces that bypassed the production initializer are controls/exploratory data, not the primary table. A dark-theme exploratory run used that earlier setup; an equivalent final production dark-theme measurement remains outstanding.

The combined **Animation Hitches + Time Profiler** attempt completed its 12 browser workloads, but Instruments stalled while finalizing. The unusable oversized trace was removed; its status and page timings remain. Later CPU-only retries were blocked by app activation, and the desktop-control tool eventually stalled for over an hour. No successful compositor hitch count or final phase-isolated production CPU trace is claimed. Animated full-viewport canvas color matching still needs a clean follow-up measurement; its fixture was corrected to expose the canvas to color hit-testing after the attempted recording.

Local evidence in `build/profiling/`:

- `production-workspace.json` and `.summary.json`: primary raw frame intervals, native timing, CPU, and feature/visibility checks.
- `raw-controls.json`: bare-WebKit comparisons.
- `native-time-profile.trace`, `native-samples.xml`, `native-cpu-summary.json`: successful exploratory Instruments recording and export.
- `full-tests.log`, `integration-summary.json`, `remaining-summary.json`, and individual suite logs: correctness evidence.
- `window-churn-crash.json`: sanitized crash summary.

A compact, durable copy of the primary per-case results is included beside this report as `browser-frame-profile-2026-09-12.json`.

## Reproduce

Run from this worktree on an unlocked desktop and leave the test window visible:

```sh
make build-browser-frame-profile
python3 Scripts/profile-browser-frames.py --repeats 3 --width 2600 --height 1400
python3 Scripts/profile-browser-instruments.py --name production-cpu --seconds 45
```

`--dark` selects the test app's dark appearance. `--modes raw` provides the engine control. `--no-blur`, `--no-color-wave`, `--skip-scroll-color`, and `--instrument-color` are explicit test-only diagnostic switches; they do not alter production source. Do not present those runs as the full-feature baseline. The current default also includes the corrected `canvas-edge` follow-up fixture.

To analyze a successful timestamped CPU run:

```sh
xcrun xctrace export --input build/profiling/production-cpu.trace --toc > build/profiling/production-cpu-toc.xml
xcrun xctrace export --input build/profiling/production-cpu.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output build/profiling/production-cpu-samples.xml
python3 Scripts/analyze-browser-profile.py --samples build/profiling/production-cpu-samples.xml --toc build/profiling/production-cpu-toc.xml --frames build/profiling/production-cpu.json --output build/profiling/production-cpu-summary.json
```

Use a new `--name` when a trace with that name already exists. CPU comparisons should use uninstrumented runs; Instruments changes scheduling and resource use.
