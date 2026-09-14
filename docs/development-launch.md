# Isolated desktop development launches

From the worktree you are testing:

```sh
python3 Scripts/launch-dev.py --copy-db \
  --test-instructions 'Open two tabs, resize the window, and check that both remain usable.'
```

The launcher builds **this worktree** and opens its app as a macOS desktop application. It never quits another Talaria process or launches the installed app. `--copy-db` is required. `--test-instructions TEXT` is optional; it shows a startup dialog, is available again under **Talaria → Test Instructions…**, and is saved alongside the development bundle. Text is displayed literally, not sent to an AI or executed as a command.

Every launch makes a new private directory under the worktree's gitignored `.talaria-dev/`. It contains `Talaria.app`, `data/talaria.sqlite3`, and `test-instructions.txt`. The launcher prints the exact paths. SQLite's online backup API copies committed data, including the live WAL, without shutting down the original app. A missing or unreadable source database fails the launch; it never silently opens the shared database.

Each snapshot gets a unique bundle identifier and executable name, so older launch scripts that stop processes named `Talaria` do not stop development copies. Its database, preferences, workspace session, and browser settings are separate from both the normal app and other snapshots. The single-instance handoff still applies to repeated opens of the same snapshot bundle. Reopening the printed bundle in Finder retains its data location and test instructions.

Chats and app settings are copied. Browser cookies/storage start empty and last for that app session. Existing agent records retain their VM directories and folder mounts, so **Hermes, provider sign-ins, tool credentials, VM workspace files, and attachments are reused without reinstalling**. The normal app's saved Keychain token is accessed through its existing trusted credential helper; it is never exported into the snapshot. The development bundle keeps the normal app's certificate and code-signing identifier for helper authentication, alongside its unique LaunchServices bundle identifier.

Agents start stopped in the copied database. **Stop an agent in the other Talaria instance (or quit that instance) before starting it here.** The existing VM storage lock prevents two instances from running or deleting the same active VM. The launcher does not stop other apps. Changes made inside a reused VM—including Hermes configuration, credentials, files, folder mounts, or deleting the agent's VM—affect that same agent outside this snapshot. Newly created development agents get local VM directories under the snapshot.

**Reset everything** in a development copy directs you to launch a fresh database snapshot. It cannot reset the normal app or the reused VMs. After quitting a development copy, its directory under `.talaria-dev/` can be removed; existing VMs and shared credentials remain in their original locations. Development bundles created by the older launcher retain their separate VM paths and Keychain service; launch again with the updated script to reuse existing agent state.

`make run` opens the ordinary build using shared app data. Use the launcher above for independent development copies.
