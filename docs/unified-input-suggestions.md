# Unified input suggestions

Chat, browser address entry, and notch quick input share Talaria's native suggestion pipeline.

Navigation labels use “Go to [domain]” without `www.`, while opening the full URL including its path, query, and fragment.

In chats with existing messages, suggestions default to collapsed. A composer chevron toggles the list, and Escape collapses it. Typing preserves the chosen state until submission. Enter sends to the agent while collapsed; expanded lists retain normal selection shortcuts. Empty chats, browser input, and quick input continue showing suggestions automatically.

For nonempty input, “Ask agent” is first by default. A URL or a match within a saved destination’s domain puts that website (or Switch to tab) first and Ask agent second. Title-only and path-only matches keep Ask agent first. Attachments also keep Ask agent first. When Ask agent is first, the second action is a strong local match or search using the configured engine. Discovered slash commands appear below “Ask agent” with search alongside them. Search preserves the exact entered text, including whitespace and punctuation, and encodes it as one query value.

Local destinations come from Talaria's saved browser history, website bookmarks, and browser tabs in the current workspace. Domain matches rank ahead of title-only and path-only matches. Within those groups, exact and prefix matches outrank substring matches. Visit frequency and recency break ties within those match groups. Duplicate URLs collapse into one destination; an already open destination offers “Switch to tab.” URL path, query, and fragment remain significant. Private windows use their own database and workspace.

History snapshots load on the database queue, including one saved favicon per origin. No database reads happen during typing. Visible rows reuse cached decoded icons, bookmark favicons, and open-tab favicons; missing icons use the action symbol. Edits filter the in-memory snapshot. There is no remote autocomplete request, external-browser inspection, generated query prediction, or separate search-history store. With empty history, only the applicable agent, search, and navigation actions appear.

Arrow keys select rows, Enter and the submit button activate the selection, Cmd+Enter always asks the agent regardless of selection, Escape dismisses suggestions, and clicking a row activates it. Shortcut hints show ↵ on the selected row and ⌘↵ on Ask agent only when it is not selected. Local rows show a favicon, title, and URL on one line with matching text in bold. Missing or URL-only titles fall back to the domain without `www.`. Tab can fill a selected strong local match or complete a selected discovered slash command. Ordinary text is never speculatively rewritten. Input-method composition keeps control of its own keys. Quick input retains its existing Escape-to-dismiss behavior.

The former browser-only “Address bar text” setting has been removed because default routing is now shared across inputs. Search-engine selection remains available.

Validation: `make test-input-suggestions` covers ranking, URL deduplication, exact query encoding, queued chat behavior, virtualized keyboard/mouse selection, browser tab switching, and light/dark layouts at 200px and 600px widths. Native UI tests need access to the macOS window server.
