# Refactoring implementation

Implemented on `refactoring-research`, based on fetched main `184c74224da178b27571fb226e0232c069ea046c`. The original checkout was left untouched. Specifications and README are unchanged.

## 1. Chat ownership and shared composer behavior

[TLChatTabController](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/TLChatTabController.m) replaces TLChatPresentation and implements the existing feature-controller lifecycle. It owns transcript/composer view construction, retained chat UI state, row caches, find, render scheduling, theme application, and teardown. Workspace runtimes now retain chat controllers through the same feature-controller slot used by other native features.

The window supplies explicit callbacks for attachments, approvals, links, suggestions, and queued prompts. Asynchronous work carries its originating chat controller. The temporary `withChatPresentation:perform:` substitution is removed, so updating a background chat no longer requires swapping the focused chat. Closed tabs cancel pending renders; retained queued work pauses and preserves its draft.

Main and quick input share wrap/skip-disabled navigation through [TLInputSuggestionListView](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/design_system/TLInputSuggestionListView.m). Surface-specific submission, dismissal, and queue policy stays in its adapter. Window-level navigation and orchestration remain in TalariaWindowController, with focused-action forwarding methods for compatibility; this is an ownership extraction, not a complete rewrite of the window.

## 2. Incremental transcript updates

A stream identifies its assistant message, and the controller batches updates to that dirty row. Structural changes, navigation, and theme changes take the full reconciliation path. Message indices and actual stack-row indices are tracked separately so inserted intent widgets do not displace subsequent updates. Pointer membership sets and retained width constraints eliminate repeated identity and constraint scans. Stable stored IDs preserve row and WebKit identity across record replacement.

[TLTranscriptReconciler](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/TLTranscriptReconciler.m) matches role/content occurrences with ordered buckets, retaining attachments and reasoning fallback. It emits changed rows and deleted IDs. SQLite applies those changes in one transaction using reused prepared statements. An unchanged transcript performs **zero message writes**, verified with triggers; summary refresh performs **zero message reads**, verified with an authorizer.

Markdown documents retain their configured parser between updates. Existing batching and document reuse remain. Viewport virtualization and block-level DOM patches were conditional research suggestions; they are not introduced without memory/DOM profiling. A long transcript still retains its mounted message views, and a changed Markdown message still replaces its content DOM.

## 3. Serialized storage and bounded history queries

[TLDatabase](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/Database.m) owns its connection on a serial queue, including initialization, migrations, and closure. Existing synchronous methods remain a compatibility facade and detect reentrant calls on that queue. [TLHistoryRepository](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/TLHistoryRepository.m) offers asynchronous history, favicon, and batched session-summary work, delivering results on the main queue.

Browser history uses 100-row keyset pages ordered by timestamp and ID. Page queries omit favicon BLOBs; icons are requested for displayed rows. Search preserves case/diacritic-insensitive and decoded-URL matching. Hidden history panels mark themselves dirty; visible searches debounce, and generations discard stale page/icon results.

Schema **12** adds message ordering, normalized browser origins, a chat/order index, and partial favicon indexes. Migration backfills existing data. Session-summary writes are batched and do not hydrate transcripts. The repository provides a narrow interface for history tests while the database facade supports remaining callers. Browser search can still scan matching candidates; paging bounds returned rows and memory, not worst-case substring-search work.

## 4. Hermes transport, lifecycle, and protocol

[hermes_rpc_transport.py](/Users/yn/work/talaria/.worktrees/refactoring-research/AgentRuntime/hermes_rpc_transport.py) owns subprocess framing, pending RPC calls, event listeners, and disconnect handling. Disconnect wakes pending work, and subsequent calls fail immediately.

[hermes_sessions.py](/Users/yn/work/talaria/.worktrees/refactoring-research/AgentRuntime/hermes_sessions.py) owns persistent identity mappings and per-session gates. Aliases share a gate and runtime owner. Turns, model selection, history opening, and deletion use the same exclusion rule. Interrupt delivery bypasses the gate. Provider changes also respect isolated supporting-model work.

[TLAgentProtocol](/Users/yn/work/talaria/.worktrees/refactoring-research/Source/TLAgentProtocol.m) centralizes incremental NDJSON decoding, request-ID and shape validation, and structured result accumulation. Legacy JSON-in-text responses normalize at this boundary; textual delta handlers remain compatible with unknown string delta kinds. Native wrappers use one JSON-operation path, and approval/tool payloads cross the boundary as dictionaries.

The lifecycle probe confirms that a model switch blocks concurrent deletion and retains its session. Tests use deterministic fake RPC transports; no live Hermes account or production conversation was exercised.

## 5. Build and test boundaries

App and test objects use compiler-generated dependency files. Narrow native tests reuse module source groups and app objects, while application integration tests share a link recipe in [Scripts/tests.mk](/Users/yn/work/talaria/.worktrees/refactoring-research/Scripts/tests.mk). `test-core` and `test-integration` provide separate entry points; GUI tests run sequentially because focus and pasteboard state are shared.

Compiler/linker flag fingerprints invalidate affected outputs. The CEF wrapper builds individual objects incrementally through [Scripts/cef-wrapper.mk](/Users/yn/work/talaria/.worktrees/refactoring-research/Scripts/cef-wrapper.mk), and its library is a real link dependency. Browser-import vendor objects also use dependency files. Alpine downloads are separate from the generated initrd. App linking is separate from bundle resource copying/signing.

Measured on this worktree with a warm build and `make -j8`:

| Change | App objects rebuilt | App relink |
| --- | ---: | --- |
| No-op | 0 | No |
| Protocol header | 2 | Yes |
| Shared theme header | 59 | Yes |
| Markdown JS resource | 0 | No |
| Changed flags for one requested object | 1 | Not requested |
| Restored default flags, full build | 120 | Yes |
| Final no-op | 0 | No |

These are dependency-operation counts, not clean-build or end-user performance claims. The [reproducible probe](/Users/yn/work/talaria/.worktrees/refactoring-research/docs/research/build-dependency-probe.py) restores touched timestamps and default flags. [Recorded results](/Users/yn/work/talaria/.worktrees/refactoring-research/docs/research/build-validation.json) include timings and object lists. The earlier query-plan probe intentionally retains its synthetic schema-11 baseline.

## Validation

- Signed desktop app builds successfully from this worktree.
- 98 discovered Python tests, 13 agent-runtime tests, and 7 terminal-service tests pass.
- **33 native suites pass** in the final sequential run. Coverage includes repository transactions/migrations, paging and stale-result rejection, Unicode protocol framing, split-chat isolation, queues, attachments, Markdown, themes, find, bookmarks, workspace restoration, and tab lifecycle.
- 146 browser footer/overlay checks, browser-profile import tests, and the semantic theme-color audit pass. The final app signature verifies with `codesign --verify --deep --strict`.
- `QuickInputTests` fails at the window-server assertion “fully transparent capture window receives mouse-downs beside the notch.” The same assertion fails when linking the original main quick-input controller into the test harness. The shared suggestion navigation is covered independently. This failure prevents claiming an entirely green `make test` run.

No new application latency, retained-memory, or live-Hermes performance numbers are claimed. The measured improvements are bounded queries, eliminated message reads/writes, dirty-row work counts, and precise rebuild dependencies. The desktop app was built and signed; interactive end-to-end desktop use was not performed.

[Validation inventory](/Users/yn/work/talaria/.worktrees/refactoring-research/docs/research/validation.json).

## Integration with current main

Before publication, integrated main `093fc87` (notifications and agent plugin settings). Both version-12 feature schemas are now reconciled on open. Notification source metadata survives incremental transcript updates, session-summary batches carry the owning agent without hydrating messages, and notification reveal/scroll behavior runs through each chat controller. Notifications and plugins use the shared structured protocol result path.

The combined branch passes 36 native suites, 128 discovered Python tests, 13 agent-runtime tests, 7 terminal-service tests, 146 browser checks, browser-profile import tests, and the theme audit. The desktop build and strict signature verification pass. The earlier quick-input capture failure remains excluded from the native pass. See [merge validation](research/merge-validation.json). Earlier build measurements and validation inventories describe the initial refactor revision.
