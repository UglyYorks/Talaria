#!/usr/bin/env python3
"""Build and launch a separate Talaria desktop app with a live database snapshot."""
import argparse
from contextlib import closing
import datetime
import fcntl
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def snapshot_database(source, destination):
    """Use SQLite backup so committed WAL data is included while Talaria runs."""
    if not source.is_file():
        raise FileNotFoundError(f"Current Talaria database not found: {source}")
    deadline = time.monotonic() + 30

    def progress(status, remaining, total):
        if time.monotonic() > deadline:
            raise TimeoutError("Talaria database stayed busy for 30 seconds; retry the launch.")

    try:
        with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)) as original:
            with closing(sqlite3.connect(destination)) as copied:
                original.backup(copied, pages=256, progress=progress, sleep=0.05)
                # Reuse the existing VM disks, Hermes installation, credentials,
                # workspace and mounts. Runtime status belongs to the old process;
                # the VM service acquires its existing storage lock before booting.
                columns = {row[1] for row in copied.execute("PRAGMA table_info(agents)")}
                if columns:
                    copied.execute("UPDATE agents SET status='stopped', last_error=NULL")
                copied.commit()
    except BaseException:
        destination.unlink(missing_ok=True)
        raise
    os.chmod(destination, 0o600)


def configure_bundle(bundle, data_root, identifier, instructions):
    plist_path = bundle / "Contents/Info.plist"
    with plist_path.open("rb") as handle:
        info = plistlib.load(handle)
    executable = "TalariaDev-" + identifier.rsplit(".", 1)[-1]
    (bundle / "Contents/MacOS" / info["CFBundleExecutable"]).rename(bundle / "Contents/MacOS" / executable)
    info.update(CFBundleExecutable=executable, CFBundleIdentifier=identifier, CFBundleDisplayName="Talaria Development",
                CFBundleName="Talaria Development", TLDevelopmentDataDirectory=str(data_root),
                TLDevelopmentReuseAgentState=True,
                TLDevelopmentTestInstructions=instructions)
    # Development copies must not become candidates for opening ordinary links.
    info.pop("CFBundleURLTypes", None)
    with plist_path.open("wb") as handle:
        plistlib.dump(info, handle)


def launch(copy_db, instructions, root=ROOT):
    if not copy_db:
        raise ValueError("Pass --copy-db to launch with an isolated database.")
    # Building the same worktree concurrently would otherwise replace the source
    # bundle while the other launcher is copying it. This lock never touches a
    # running app and is released on every failure.
    development = root / ".talaria-dev"
    development.mkdir(mode=0o700, exist_ok=True)
    with (development / "launcher.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        subprocess.run(["make", "build"], cwd=root, check=True)
        identity = uuid.uuid4().hex
        run = Path(tempfile.mkdtemp(prefix=datetime.datetime.now().strftime("%Y%m%d-%H%M%S-"), dir=development))
        try:
            data = run / "data"
            data.mkdir(mode=0o700)
            source = Path.home() / "Library/Application Support/com.talaria.chat/talaria.sqlite3"
            snapshot_database(source, data / "talaria.sqlite3")
            bundle = run / "Talaria.app"
            subprocess.run(["/usr/bin/ditto", str(root / "build/Talaria.app"), str(bundle)], check=True)
            configure_bundle(bundle, data, "com.talaria.chat.dev." + identity, instructions)
            # The helper trusts our certificate and signing identifier. Keep that
            # identifier while LaunchServices uses the unique CFBundleIdentifier.
            # No reinstall or trust-policy change is needed for the existing helper.
            signing_identity = (root / "build/.signing-identity").read_text().strip()
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", signing_identity,
                            "--identifier", "com.talaria.chat",
                            "--entitlements", str(root / "Entitlements.plist"), str(bundle)], check=True)
            (run / "test-instructions.txt").write_text(instructions + "\n")
        except BaseException:
            shutil.rmtree(run)
            raise
        # LaunchServices creates a real desktop application. Never kill another
        # Talaria process, and never select a bundle by name or installed location.
        subprocess.run(["/usr/bin/open", "-n", str(bundle)], check=True)
        print(f"Development app: {bundle}\nDatabase: {data / 'talaria.sqlite3'}", flush=True)
        print("Reusing existing VMs and credentials. Stop an agent in other Talaria instances before starting it here.", flush=True)
        return bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--copy-db", action="store_true", required=True,
                        help="snapshot the current database into .talaria-dev, reusing existing VMs and credentials")
    parser.add_argument("--test-instructions", default="", metavar="TEXT",
                        help="display these manual test instructions on launch and in the app menu")
    args = parser.parse_args()
    try:
        launch(args.copy_db, args.test_instructions)
    except (OSError, sqlite3.Error, subprocess.CalledProcessError, ValueError) as error:
        parser.exit(1, f"Development launch failed: {error}\n")


if __name__ == "__main__":
    main()
