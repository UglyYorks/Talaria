"""Markdown notes in the VM workspace, served through Hermes's TUI gateway.

There is no secondary database: files written by the agent appear on the next
list/read. Revisions prevent stale editor drafts from overwriting those edits.
"""
import contextlib
import fcntl
import hashlib
import os
from pathlib import Path
import stat
import uuid


MAX_BYTES = 1024 * 1024


def note_id(value):
    if (not isinstance(value, str) or not value.endswith(".md") or value.startswith(".")
            or any(c in value for c in ("/", "\\", "\x00", "\n", "\r"))
            or len(value.encode("utf-8")) > 200):
        raise ValueError("A note must have a plain Markdown filename of at most 200 bytes.")
    return value


def content_bytes(value):
    if not isinstance(value, str) or "\x00" in value:
        raise ValueError("Note content must be UTF-8 text without null characters.")
    data = value.encode("utf-8")
    if len(data) > MAX_BYTES:
        raise ValueError("Notes can contain up to 1 MiB of Markdown.")
    return data


class Notes:
    def __init__(self, workspace):
        self.root = Path(workspace) / "notes"

    def lock_names(self):
        return (".lock",)

    @contextlib.contextmanager
    def directory(self):
        self.root.mkdir(exist_ok=True)
        directory = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        locks = []
        try:
            for name in self.lock_names():
                lock = os.open(name, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600, dir_fd=directory)
                locks.append(lock)
                if not stat.S_ISREG(os.fstat(lock).st_mode):
                    raise ValueError("The Markdown lock must be a regular file.")
                fcntl.flock(lock, fcntl.LOCK_EX)
            yield directory
        finally:
            for lock in reversed(locks):
                os.close(lock)
            os.close(directory)

    def read(self, directory, identity):
        descriptor = os.open(note_id(identity), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as file:
            info = os.fstat(file.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ValueError("Notes must be regular Markdown files.")
            data = file.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("This note exceeds the 1 MiB editor limit.")
        content = data.decode("utf-8")
        if "\x00" in content:
            raise ValueError("This note is not a text file.")
        lines = [line.strip() for line in content.splitlines() if line.strip()]
        title = next((line[2:].strip() for line in lines if line.startswith("# ")), Path(identity).stem)
        preview = next((line for line in lines if not line.startswith("# ")), "")
        return {"id": identity, "title": title[:200] or "Untitled note", "preview": preview[:200],
                "content": content, "revision": hashlib.sha256(data).hexdigest(),
                "modified_at": info.st_mtime, "path": str(self.root / identity)}

    def request(self, params):
        if not isinstance(params, dict):
            raise ValueError("Note parameters must be an object.")
        action = params.get("action")
        if action not in {"list", "read", "create", "save", "delete"}:
            raise ValueError("Unknown notes action.")
        with self.directory() as directory:
            if action == "list":
                query = params.get("query", "")
                if not isinstance(query, str):
                    raise ValueError("The search query must be text.")
                notes, skipped = [], []
                for name in os.listdir(directory):
                    if name.startswith(".") or not name.endswith(".md"):
                        continue
                    try:
                        note = self.read(directory, name)
                        if query.casefold() in (name + "\n" + note["content"]).casefold():
                            notes.append({key: value for key, value in note.items() if key != "content"})
                    except FileNotFoundError:
                        continue  # An agent removed/renamed this file during enumeration.
                    except (OSError, ValueError, UnicodeError):
                        skipped.append(name)
                notes.sort(key=lambda note: (-note["modified_at"], note["id"]))
                return {"notes": notes, "directory": str(self.root), "skipped": skipped}

            identity = note_id(params.get("id"))
            if action == "read":
                return {"note": self.read(directory, identity)}

            data = content_bytes(params.get("content")) if action in {"create", "save"} else None
            try:
                current = self.read(directory, identity)
            except FileNotFoundError:
                current = None
            if action == "create":
                # Repeating an uncertain create is safe and uses the same ID.
                if current and current["content"] == params["content"]:
                    return {"note": current}
                conflict = current is not None
            else:
                revision = params.get("revision")
                if not isinstance(revision, str) or len(revision) != 64:
                    raise ValueError("Reload the note before saving or deleting it.")
                conflict = current is None or current["revision"] != revision
            if conflict:
                return {"conflict": True, "note": current,
                        "message": "This note changed outside this editor. Your draft is kept. Reload it or save your draft as a copy."}

            if action == "delete":
                try:
                    os.mkdir(".trash", 0o700, dir_fd=directory)
                except FileExistsError:
                    pass
                trash = os.open(".trash", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
                try:
                    name = uuid.uuid4().hex + "-" + identity
                    os.rename(identity, name, src_dir_fd=directory, dst_dir_fd=trash)
                    os.fsync(trash)
                finally:
                    os.close(trash)
                os.fsync(directory)
                return {"deleted": identity, "trash_path": str(self.root / ".trash" / name)}

            temporary = ".save-" + uuid.uuid4().hex
            try:
                descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
                with os.fdopen(descriptor, "wb") as file:
                    file.write(data)
                    file.flush()
                    os.fsync(file.fileno())
                if action == "create":
                    # Never replace a file the agent created during this request.
                    os.link(temporary, identity, src_dir_fd=directory, dst_dir_fd=directory)
                else:
                    # Recheck after preparing the file, narrowing the window for
                    # non-cooperating external writers. Gateway writes are locked.
                    try:
                        latest = self.read(directory, identity)
                    except FileNotFoundError:
                        latest = None
                    if not latest or latest["revision"] != params["revision"]:
                        return {"conflict": True, "note": latest,
                                "message": "The agent edited this note while it was saving. Your draft is kept."}
                    os.replace(temporary, identity, src_dir_fd=directory, dst_dir_fd=directory)
                os.fsync(directory)
            finally:
                try:
                    os.unlink(temporary, dir_fd=directory)
                except FileNotFoundError:
                    pass
            return {"note": self.read(directory, identity)}



class Memories(Notes):
    """The two built-in Hermes stores, including editable, not-yet-created files."""
    TITLES = {"MEMORY.md": "Learned facts", "USER.md": "About you"}
    MISSING_REVISION = hashlib.sha256(b"talaria:missing-memory-file").hexdigest()

    def __init__(self, home):
        self.root = Path(home) / "memories"

    def lock_names(self):
        # Match Hermes MemoryStore's per-file locks. Hold them through the
        # revision check and atomic replace so a learning write cannot be lost.
        return tuple(name + ".lock" for name in self.TITLES)

    def read(self, directory, identity):
        if identity not in self.TITLES:
            raise ValueError("Choose Learned facts or About you.")
        try:
            note = super().read(directory, identity)
        except FileNotFoundError:
            note = {"id": identity, "content": "", "preview": "Nothing saved yet. You can add information here.",
                    "revision": self.MISSING_REVISION, "modified_at": 0, "path": str(self.root / identity)}
        note["title"] = self.TITLES[identity]
        return note

    def request(self, params):
        if not isinstance(params, dict) or params.get("action") not in {"list", "read", "save"}:
            raise ValueError("Memory supports listing, reading and saving. Remove text to forget information.")
        if params["action"] == "list":
            query = params.get("query", "")
            if not isinstance(query, str):
                raise ValueError("The search query must be text.")
            notes, skipped = [], []
            with self.directory() as directory:
                for identity in self.TITLES:
                    try:
                        note = self.read(directory, identity)
                        if query.casefold() in (identity + "\n" + note["title"] + "\n" + note["content"]).casefold():
                            notes.append({key: value for key, value in note.items() if key != "content"})
                    except (OSError, ValueError, UnicodeError):
                        skipped.append(identity)
            return {"notes": notes, "directory": str(self.root), "skipped": skipped}
        if not isinstance(params.get("id"), str) or params["id"] not in self.TITLES:
            raise ValueError("Choose Learned facts or About you.")
        return super().request(params)


def register(server, home):
    notes = Notes(Path(home).parent)
    memories = Memories(home)

    @server.method("talaria.notes")
    def handler(rid, params):
        try:
            if not isinstance(params, dict):
                raise ValueError("Notes parameters must be an object.")
            collection = params.get("collection", "notes")
            if not isinstance(collection, str) or collection not in {"notes", "memory"}:
                raise ValueError("Unknown Notes tab.")
            store = memories if collection == "memory" else notes
            return server._ok(rid, store.request(params))
        except (OSError, ValueError, UnicodeError) as exc:
            return server._err(rid, -32602, f"Could not access notes: {exc}")
    return notes
