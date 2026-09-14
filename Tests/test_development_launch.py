import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("development_launch", Path(__file__).resolve().parents[1] / "Scripts/launch-dev.py")
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class DevelopmentLaunchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "live.sqlite3"
        self.live = sqlite3.connect(self.source)
        self.addCleanup(self.live.close)
        self.live.executescript("""
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE agents(id INTEGER PRIMARY KEY, vm_directory TEXT, status TEXT, last_error TEXT, folder_paths TEXT);
            INSERT INTO agents VALUES(1, '/original/VM', 'running', 'old error', '["/original/files"]');
            CREATE TABLE chats(id INTEGER PRIMARY KEY, content TEXT);
            INSERT INTO chats VALUES(1, 'Committed in WAL');
        """)
        self.live.commit()

    def test_live_wal_snapshot_is_independent_and_reuses_agents(self):
        data = self.root / "local"
        data.mkdir()
        destination = data / "talaria.sqlite3"
        self.live.execute("INSERT INTO chats VALUES(2, 'uncommitted')")
        launcher.snapshot_database(self.source, destination)
        with sqlite3.connect(destination) as copied:
            self.assertEqual(copied.execute("SELECT * FROM chats").fetchall(), [(1, "Committed in WAL")])
            self.assertEqual(copied.execute("SELECT vm_directory, status, last_error, folder_paths FROM agents").fetchone(),
                             ("/original/VM", "stopped", None, '["/original/files"]'))
            copied.execute("UPDATE chats SET content='local edit'")
        self.live.rollback()
        self.assertEqual(self.live.execute("SELECT content FROM chats").fetchone()[0], "Committed in WAL")
        self.assertEqual(self.live.execute("SELECT vm_directory, status, folder_paths FROM agents").fetchone(),
                         ("/original/VM", "running", '["/original/files"]'))
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_missing_or_invalid_source_never_creates_a_database(self):
        destination = self.root / "copy.sqlite3"
        with self.assertRaises(FileNotFoundError):
            launcher.snapshot_database(self.root / "missing.sqlite3", destination)
        self.assertFalse(destination.exists())
        bad = self.root / "bad.sqlite3"
        bad.write_text("not sqlite")
        with self.assertRaises(sqlite3.DatabaseError):
            launcher.snapshot_database(bad, destination)
        self.assertFalse(destination.exists())

    def test_repeated_launches_use_distinct_desktop_bundles_and_snapshots(self):
        bundle = self.root / "build/Talaria.app"
        (bundle / "Contents").mkdir(parents=True)
        with (bundle / "Contents/Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": "com.talaria.chat", "CFBundleExecutable": "Talaria", "CFBundleURLTypes": ["http"]}, handle)
        (bundle / "Contents/MacOS").mkdir()
        (bundle / "Contents/MacOS/Talaria").write_text("fixture executable")
        (self.root / "build/.signing-identity").write_text("Test Identity\n")
        home = self.root / "home"
        real_source = home / "Library/Application Support/com.talaria.chat/talaria.sqlite3"
        real_source.parent.mkdir(parents=True)
        with sqlite3.connect(real_source) as target:
            self.live.backup(target)
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[0] == "/usr/bin/ditto":
                launcher.shutil.copytree(args[1], args[2])
        instructions = 'Check "tabs"\nThen resize; $(do-not-execute)'
        with patch.object(launcher.Path, "home", return_value=home), patch.object(launcher.subprocess, "run", side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            first = launcher.launch(True, instructions, self.root)
            second = launcher.launch(True, "second", self.root)
        self.assertNotEqual(first, second)
        identifiers = []
        for app in [first, second]:
            with (app / "Contents/Info.plist").open("rb") as handle:
                info = plistlib.load(handle)
            identifiers.append(info["CFBundleIdentifier"])
            self.assertTrue(info["CFBundleExecutable"].startswith("TalariaDev-"))
            self.assertTrue((app / "Contents/MacOS" / info["CFBundleExecutable"]).is_file())
            self.assertFalse((app / "Contents/MacOS/Talaria").exists())
            self.assertNotIn("CFBundleURLTypes", info)
            self.assertTrue(info["TLDevelopmentReuseAgentState"])
            data = Path(info["TLDevelopmentDataDirectory"])
            self.assertTrue(data.is_relative_to(app.parent))
            self.assertTrue((data / "talaria.sqlite3").is_file())
            with sqlite3.connect(data / "talaria.sqlite3") as copied:
                self.assertEqual(copied.execute("SELECT vm_directory, folder_paths, status FROM agents").fetchone(),
                                 ("/original/VM", '["/original/files"]', "stopped"))
            self.assertFalse((data / "Agents").exists())
        self.assertNotEqual(*identifiers)
        with (first / "Contents/Info.plist").open("rb") as handle:
            self.assertEqual(plistlib.load(handle)["TLDevelopmentTestInstructions"], instructions)
        self.assertEqual([call for call in calls if call[0] == "/usr/bin/open"],
                         [["/usr/bin/open", "-n", str(first)], ["/usr/bin/open", "-n", str(second)]])
        self.assertFalse(any("pkill" in str(call) or "close-running-app" in call for call in calls))
        signatures = [call for call in calls if call[0] == "/usr/bin/codesign"]
        self.assertEqual(len(signatures), 2)
        for signature in signatures:
            self.assertEqual(signature[signature.index("--identifier") + 1], "com.talaria.chat")
        self.assertEqual((first.parent / "test-instructions.txt").read_text(), instructions + "\n")

    def test_isolation_is_required(self):
        with self.assertRaises(ValueError):
            launcher.launch(False, "test", self.root)
        self.assertFalse((self.root / ".talaria-dev").exists())


if __name__ == "__main__":
    unittest.main()
