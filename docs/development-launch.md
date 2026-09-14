# Isolated desktop development launches

From the worktree you are testing:

```sh
python3 Scripts/launch-dev.py --copy-db \
  --test-instructions 'Open two tabs, resize the window, and check that both remain usable.'
```

The launcher builds **this worktree** and opens its app as a macOS desktop application. It never quits another Talaria process or launches the installed app. `--copy-db` is required. `--test-instructions TEXT` is optional; it shows a startup dialog, is available again under **Talaria → Test Instructions…**, and is saved alongside the development bundle. Text is displayed literally, not sent to an AI or executed as a command.

Every launch makes a new private directory under the worktree's gitignored `.talaria-dev/`. It contains `Talaria.app`, `data/talaria.sqlite3`, and `test-instructions.txt`. The launcher prints the exact paths. SQLite's online backup API copies committed data, including the live WAL, without shutting down the original app. A missing or unreadable source database fails the launch; it never silently opens the shared database.

Each snapshot gets a unique bundle identifier and executable name, so older launch scripts that stop processes named `Talaria` do not stop development copies. Its database, preferences, credentials, workspace session, browser settings, and VM paths are separate from both the normal app and other snapshots. The single-instance handoff still applies to repeated opens of the same snapshot bundle. Reopening the printed bundle in Finder retains its data location and test instructions.

Chats and app settings are copied. Browser cookies/storage start empty and last for that app session. Credentials are stored under the development copy's own Keychain service; the normal app's saved token is not copied. Agent records point to fresh local VM directories and start stopped, with no inherited shared-folder grants. Existing VM disks, Hermes installations, attachments stored in VM workspaces, and external service connections are not cloned; set up a development agent when testing AI features. This avoids using or modifying a VM that another copy is running. Actions you explicitly take against external services still affect those services.

**Reset everything** in a development copy directs you to launch a fresh snapshot. It cannot reset the normal app. After quitting a development copy, its directory under `.talaria-dev/` can be removed. Any credentials explicitly saved in that copy's Keychain service are separate from the directory.

`make run` opens the ordinary build using shared app data. Use the launcher above for independent development copies.
