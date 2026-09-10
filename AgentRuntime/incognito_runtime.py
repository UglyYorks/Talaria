"""Disposable Hermes TUI runtimes. No persistent profile is ever used as a fallback."""
import base64
import contextvars
import os
from pathlib import Path
import re
import shutil
import signal
import tempfile
import threading
import time
import uuid

scope = contextvars.ContextVar("incognito_scope", default="")
_lock = threading.RLock()
_runtimes = {}
_closed = set()
_reaper_started = False
LEASE_SECONDS = 90


def validate_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9-]{16,80}", value):
        raise ValueError("Invalid Incognito window identity.")
    return value


def require_ram_storage(directory=Path("/tmp")):
    # No disk-backed temp directory, nor guest swap, is acceptable.
    mounts = []
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        fields = line.split()
        mountpoint = Path(fields[4])
        if directory == mountpoint or mountpoint in directory.parents:
            mounts.append((len(str(mountpoint)), fields[fields.index("-") + 1]))
    if not mounts or max(mounts)[1] != "tmpfs" or len(Path("/proc/swaps").read_text().splitlines()) > 1:
        raise RuntimeError("Incognito requires RAM-backed temporary storage with guest swap disabled.")


def _destroy(record):
    gateway = record["gateway"]
    # Kill the gateway and any terminal/subagent children before removing RAM files.
    try:
        os.killpg(gateway.process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    gateway.process.wait(timeout=5)
    shutil.rmtree(record["root"], ignore_errors=True)


def close(identity):
    validate_id(identity)
    with _lock:
        _closed.add(identity)
        record = _runtimes.pop(identity, None)
    if record:
        _destroy(record)


def keepalive(identity):
    validate_id(identity)
    with _lock:
        if identity in _closed:
            raise RuntimeError("This Incognito window is closed. Open a new Incognito window.")
        if identity in _runtimes:
            _runtimes[identity]["touched"] = time.monotonic()


def reap_expired(now=None):
    now = time.monotonic() if now is None else now
    with _lock:
        # Keep expiry and removal atomic with heartbeats; a late heartbeat must not
        # revive an expired runtime or lose a runtime it just renewed.
        for identity, row in list(_runtimes.items()):
            if now - row["touched"] > LEASE_SECONDS:
                close(identity)


def _reap():
    while True:
        time.sleep(15)
        reap_expired()


def get_gateway(identity, python, environment, source_home, gateway_class):
    global _reaper_started
    validate_id(identity)
    with _lock:
        if identity in _closed:
            raise RuntimeError("This Incognito window has expired. Open a new Incognito window.")
        existing = _runtimes.get(identity)
        if existing:
            if existing["gateway"].process.poll() is not None:
                close(identity)
                raise RuntimeError("The private Hermes runtime stopped. Open a new Incognito window.")
            existing["touched"] = time.monotonic()
            return existing["gateway"]
        require_ram_storage()
        root = Path(tempfile.mkdtemp(prefix="talaria-incognito-", dir="/tmp"))
        home = root / ".hermes"
        home.mkdir(mode=0o700)
        try:
            # Copy only configuration/auth, never sessions, logs, plugins, or background jobs.
            for name in ("config.yaml", ".env", "auth.json", "SOUL.md"):
                source = source_home / name
                if source.is_file():
                    shutil.copyfile(source, home / name)
            memories = root / "readonly-memories"
            memories.mkdir()
            for name in ("MEMORY.md", "USER.md"):
                source = source_home / "memories" / name
                if source.is_file():
                    shutil.copyfile(source, memories / name)
            # Read-only memory lies OUTSIDE the only writable tree.
            writable = root / "runtime"
            writable.mkdir()
            home.rename(writable / ".hermes")
            home = writable / ".hermes"
            (home / "memories").symlink_to(memories, target_is_directory=True)
            if (source_home / "skills").is_dir():
                (home / "skills").symlink_to(source_home / "skills", target_is_directory=True)
            for name in ("tmp", "cache", "config", "data"):
                (writable / name).mkdir()
            env = dict(environment)
            env.update({"HOME": str(writable), "HERMES_HOME": str(home),
                        "TMPDIR": str(writable / "tmp"), "TMP": str(writable / "tmp"),
                        "XDG_CACHE_HOME": str(writable / "cache"), "XDG_CONFIG_HOME": str(writable / "config"),
                        "XDG_DATA_HOME": str(writable / "data"), "PYTHONDONTWRITEBYTECODE": "1",
                        "HERMES_ENABLE_PROJECT_PLUGINS": "false", "HERMES_DISABLE_MCP": "1", "TALARIA_INCOGNITO_ROOT": str(writable)})
            gateway = gateway_class(python, env, home, entry_module="incognito_entry")
            record = {"root": root, "gateway": gateway, "touched": time.monotonic()}
            _runtimes[identity] = record
            # Startup handshake proves the RAM profile and kernel write restriction are in force.
            if gateway.call("talaria.incognito.status", timeout=45).get("isolated") is not True:
                raise RuntimeError("Hermes could not verify private storage isolation.")
            gateway.apply_skill_policy()
        except Exception:
            if identity in _runtimes:
                close(identity)
            else:
                shutil.rmtree(root, ignore_errors=True)
            raise
        if not _reaper_started:
            _reaper_started = True
            threading.Thread(target=_reap, daemon=True).start()
        return gateway


def upload(gateway, files):
    if not isinstance(files, list) or len(files) > 20:
        raise ValueError("Choose at most 20 Incognito attachments.")
    folder = gateway.home.parent / "attachments" / uuid.uuid4().hex
    folder.mkdir(parents=True)
    rows = []
    try:
        for item in files:
            name = item.get("name")
            if not isinstance(name, str) or name in ("", ".", "..") or Path(name).name != name:
                raise ValueError("Invalid attachment filename.")
            data = base64.b64decode(item.get("data", ""), validate=True)
            if len(data) > 20 * 1024 * 1024:
                raise ValueError("Incognito attachments must be smaller than 20 MB.")
            target = folder / (str(len(rows)) + "-" + name)
            target.write_bytes(data)
            rows.append({"name": name, "guestPath": str(target), "directory": False})
    except Exception:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    return rows
